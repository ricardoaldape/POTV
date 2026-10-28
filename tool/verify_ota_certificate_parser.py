#!/usr/bin/env python3
"""Regression guard for apksigner label variants on the Windows release jobs.

This does not substitute for verifying the actual APK's certificate on the
Windows runner; it ensures our workflow parser accepts valid apksigner labels
without weakening the pinned certificate check.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = (
    ".github/workflows/ota-release.yml",
    ".github/workflows/hp-signed-review.yml",
)
EXPECTED_DIGEST = "0866423088ca0eac27a79954ccb93c6b99c03b7c0bc9a7ab209ac3c08c7791fe"

for name in WORKFLOWS:
    content = (ROOT / name).read_text(encoding="utf-8")
    lines = [
        line for line in content.splitlines()
        if "Select-String -Pattern" in line and "certificate SHA-256 digest:" in line
    ]
    assert len(lines) == 1, f"{name}: expected one certificate parser"
    found = re.search(r"Select-String -Pattern '([^']+)'", lines[0])
    assert found, f"{name}: no regex found"
    pattern = re.compile(found.group(1))
    for label in ("Signer #1", "V2 Signer #1", "V3 Signer #1"):
        value = f"{label} certificate SHA-256 digest: {EXPECTED_DIGEST}"
        match = pattern.search(value)
        assert match and match.group(1).lower() == EXPECTED_DIGEST, (
            f"{name}: parser rejects {label}"
        )
    for bad in (
        "Signer #1 certificate SHA-256 digest: 012345",
        f"Signer #1 certificate SHA-256 digest: {EXPECTED_DIGEST[:-1]}g",
        "Signer #1 certificate SHA-256 digest: ",
        "Signer #1 certificate SHA-1 digest: " + EXPECTED_DIGEST,
    ):
        assert not pattern.search(bad), f"{name}: accepted invalid digest"
    assert "$digestMatches.Count -ne 1" in content, (
        f"{name}: ambiguous or multiple signer outputs must fail closed"
    )
    assert "$digestMatches[0].Matches[0].Groups[1].Value" in content, (
        f"{name}: workflow must use the validated digest capture"
    )
assert "POTV_RELEASE_CERT_SHA256" in (
    ROOT / ".github/workflows/ota-release.yml"
).read_text(encoding="utf-8"), "OTA release must retain the production certificate pin"
print("PASS: Windows OTA/review parser supports apksigner signer labels; pin retained")
