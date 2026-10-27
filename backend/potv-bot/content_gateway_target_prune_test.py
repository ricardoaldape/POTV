"""Target pruning must not invalidate active, signed HLS segments."""
import time
from unittest.mock import patch
from content_gateway import ContentGateway

gateway = ContentGateway(
    sources=[], public_base="https://potv.example",
    signing_secret=b"prune-test-secret",
)
with patch.object(time, "monotonic", return_value=1000.0):
    old = gateway._register_target("https://media.example/old.ts")
    keep = gateway._register_target("https://media.example/active.m3u8")
with patch.object(time, "monotonic", return_value=2250.0):
    signed = gateway._proxy_url(keep)
    for n in range(510):
        gateway._register_target(f"https://media.example/segment-{n}.ts")
assert old not in gateway._targets
assert keep in gateway._targets
assert "format=hls" in signed
assert len(gateway._targets) <= 512
print("PASS: stale signed segment targets pruned; active targets retained")
