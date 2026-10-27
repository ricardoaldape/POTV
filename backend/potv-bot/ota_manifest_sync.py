"""Refresh the legacy POTV OTA endpoint from validated official GitHub releases.

The Android Update Center reads GitHub directly; older POTV versions still
read /api/v1/version/latest. Keep both on the same signed release track.
No APK is downloaded or installed, and a failed lookup never erases a manifest.
"""
import argparse
import json
import os
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

RELEASES_URL = "https://api.github.com/repos/ricardoaldape/POTV/releases?per_page=30"
TAG = re.compile(r"^v\d+\.\d+\.\d+(?:-beta\.\d+)?$")
VERSION_CODE = re.compile(r"^POTV-Version-Code:\s*([1-9]\d*)\s*$", re.M)
SHA256 = re.compile(r"^sha256:[a-fA-F0-9]{64}$")
MAX_APK_SIZE = 450 * 1024 * 1024
MAX_API_BYTES = 2 * 1024 * 1024


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def release_manifest(raw, *, allow_beta=False):
    """Reject unsigned, malformed, third-party or unpublished release metadata."""
    if not isinstance(raw, dict) or raw.get("draft") is not False:
        return None
    tag = raw.get("tag_name")
    if not isinstance(tag, str) or not TAG.fullmatch(tag):
        return None
    beta = "-beta." in tag
    if raw.get("prerelease") is not beta or (beta and not allow_beta):
        return None
    body = raw.get("body")
    if not isinstance(body, str):
        return None
    codes = VERSION_CODE.findall(body)
    if len(codes) != 1:
        return None
    code = int(codes[0])
    if code > 2_147_483_647:
        return None
    published = raw.get("published_at")
    if not isinstance(published, str):
        return None
    try:
        stamp = datetime.fromisoformat(published.replace("Z", "+00:00"))
        if stamp.tzinfo is None or stamp > datetime.now(timezone.utc):
            return None
    except ValueError:
        return None
    assets = raw.get("assets")
    if not isinstance(assets, list):
        return None
    name = f"POTV-{tag}.apk"
    path = f"/ricardoaldape/POTV/releases/download/{tag}/{name}"
    matches = []
    for asset in assets:
        if not isinstance(asset, dict) or asset.get("name") != name:
            continue
        url = asset.get("browser_download_url")
        digest = asset.get("digest")
        size = asset.get("size")
        if not isinstance(url, str) or not isinstance(digest, str):
            continue
        if not SHA256.fullmatch(digest):
            continue
        if type(size) is not int or not 0 < size <= MAX_APK_SIZE:
            continue
        try:
            parsed = urlsplit(url)
        except ValueError:
            continue
        if (parsed.scheme != "https" or parsed.hostname != "github.com"
                or parsed.port not in (None, 443) or parsed.path != path
                or parsed.username or parsed.password
                or parsed.query or parsed.fragment):
            continue
        matches.append(url)
    if len(matches) != 1:
        return None
    notes = VERSION_CODE.sub("", body).strip()
    return {
        "version": tag[1:],
        "versionCode": code,
        "apk_url": matches[0],
        "changelog": notes[:2000] or "Actualización oficial de POTV.",
        "mandatory": False,
        "released_at": published,
    }


def select_manifest(releases, *, current_code=0, allow_beta=False):
    if not isinstance(releases, list):
        raise ValueError("invalid_releases_response")
    candidates = [release_manifest(x, allow_beta=allow_beta) for x in releases]
    candidates = [x for x in candidates if x and x["versionCode"] > current_code]
    if not candidates:
        return None
    candidates.sort(key=lambda x: x["versionCode"], reverse=True)
    if len(candidates) > 1 and candidates[0]["versionCode"] == candidates[1]["versionCode"]:
        raise ValueError("duplicate_release_version_code")
    return candidates[0]


def fetch_releases():
    req = Request(RELEASES_URL, headers={
        "User-Agent": "POTV-OTA-Manifest/1.0",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    with build_opener(NoRedirect()).open(req, timeout=12) as response:
        if response.status != 200:
            raise ValueError("github_release_unavailable")
        raw = response.read(MAX_API_BYTES + 1)
    if len(raw) > MAX_API_BYTES:
        raise ValueError("github_release_response_too_large")
    return json.loads(raw)


def update_manifest(path, releases, *, allow_beta=False, dry_run=False):
    target = Path(path)
    current_code = 0
    if target.exists():
        current = json.loads(target.read_text(encoding="utf-8"))
        if not isinstance(current, dict):
            raise ValueError("invalid_existing_manifest")
        current_code = int(current.get("versionCode", 0))
    new = select_manifest(releases, current_code=current_code, allow_beta=allow_beta)
    if new is None:
        return None
    if dry_run:
        return new
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".potv-version-", suffix=".json", dir=target.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(new, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temp, 0o644)
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return new


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="/opt/potv-bot/version.json")
    parser.add_argument("--allow-beta", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    selected = update_manifest(
        args.manifest, fetch_releases(),
        allow_beta=args.allow_beta, dry_run=args.dry_run,
    )
    if selected:
        print("OTA manifest selected:", selected["version"], selected["versionCode"],
              "dry_run=", args.dry_run)
    else:
        print("OTA manifest unchanged: no newer verified official release")


if __name__ == "__main__":
    main()
