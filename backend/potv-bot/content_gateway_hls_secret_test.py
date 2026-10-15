"""Regression: POTV must never expose upstream logins in HLS playlists."""
from urllib.parse import urlsplit

from content_gateway import ContentGateway, ContentGatewayError

gateway = ContentGateway(
    sources=[],
    public_base="https://potv.example",
    signing_secret=b"security-fixture-do-not-use",
)

upstream = (
    "https://licensed.example/hls/master.m3u8"
    "?username=licensed-service&password=private-test-value"
)
header = {"User-Agent": "LicensedProvider-QA"}
playlist = """#EXTM3U
#EXT-X-VERSION:3
#EXT-X-KEY:METHOD=AES-128,URI="keys/key.bin?token=secret-fixture"
#EXTINF:6,
segments/00001.ts?token=private-value
#EXT-X-STREAM-INF:BANDWIDTH=1500000
sub/variant.m3u8?username=private-user&password=private-password
"""
output = gateway._rewrite_hls(playlist, upstream, header)
for forbidden in (
    "licensed-service",
    "private-test-value",
    "private-value",
    "secret-fixture",
    "private-user",
    "private-password",
    "licensed.example",
    "/segments/00001.ts",
    "/keys/key.bin",
):
    assert forbidden not in output, f"upstream leaked: {forbidden}"
assert "https://potv.example/api/v1/content/stream/" in output
assert output.count("https://potv.example/api/v1/content/stream/") == 3
assert gateway._targets
for target_url, target_headers in gateway._targets.values():
    assert target_headers == header
    assert urlsplit(target_url).hostname == "licensed.example"

# Fail the entire playlist if any nested reference cannot be proxied.
# This is preferable to returning a raw credential-bearing segment URI.
bad_playlist = """#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="file:///private-service-password"
#EXTINF:6,
../seg.ts?password=never-expose
"""
try:
    gateway._rewrite_hls(bad_playlist, upstream, header)
    raise AssertionError("unsafe HLS key reference was allowed")
except ContentGatewayError as exc:
    assert exc.code == "upstream_not_allowed"

# Plain segment URL failure must also fail closed.
try:
    gateway._rewrite_hls("#EXTM3U\nhttp://127.0.0.1/internal?password=hide-me\n", upstream, header)
    raise AssertionError("private network HLS reference was allowed")
except ContentGatewayError as exc:
    assert exc.code == "upstream_not_allowed"

# Existing signature still validates the proxy; never send upstream URL.
target_id = next(iter(gateway._targets))
signed_url = gateway._proxy_url(target_id)
assert gateway._validate_signature(target_id, urlsplit(signed_url).query)
assert "licensed.example" not in signed_url
assert "password=" not in signed_url
print("PASS: signed HLS master/keys/segments never expose upstream accounts; fail closed")
