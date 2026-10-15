"""HLS target retention must be bounded without breaking valid signed URLs."""
from unittest.mock import patch

from content_gateway import ContentGateway

gateway=ContentGateway(
    sources=[],
    public_base="https://potv.example",
    signing_secret=b"potv-hls-memory-qa-secret",
)
with patch('content_gateway.time.monotonic',return_value=1000.0):
    first=gateway._register_target('https://media.example/live/old-00001.m4s')
    kept=gateway._register_target('https://media.example/live/active-00002.m4s')
    # Touching an ID through _proxy_url must keep its signed playback valid.
    gateway._proxy_url(kept)
    assert len(gateway._targets)==2

with patch('content_gateway.time.monotonic',return_value=2150.0):
    gateway._proxy_url(kept)
with gateway._lock:
    gateway._prune_expired_targets_locked(2250.0)
assert first not in gateway._targets
assert first not in gateway._target_last_signed
assert kept in gateway._targets
assert kept in gateway._target_last_signed

# Periodic pruning during registration, not on every HLS request.
with patch('content_gateway.time.monotonic',return_value=3400.0):
    for i in range(1024):
        gateway._register_target(f'https://media.example/part/seg-{i}.m4s')
assert kept not in gateway._targets
assert len(gateway._targets) <= 1024
assert set(gateway._targets)==set(gateway._target_last_signed)
print("PASS: stale HLS targets pruned while actively signed streams are retained")
