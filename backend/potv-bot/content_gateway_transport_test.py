"""Regression: extensionless signed gateway URLs must retain media hints."""
from urllib.parse import urlsplit

from content_gateway import ContentGateway

gateway = ContentGateway(
    sources=[],
    public_base="https://potv.example",
    signing_secret=b"transport-test-not-production",
)

samples = [
    ("https://cdn.example/live/espn2.m3u8", "hls"),
    ("https://cdn.example/live/espn2.ts", "ts"),
    ("https://cdn.example/vod/movie.mp4", "mp4"),
    ("https://cdn.example/dash/live.mpd", "mpd"),
]
for upstream, expected in samples:
    target = gateway._register_target(upstream)
    proxy = gateway._proxy_url(target)
    assert "format=" + expected in proxy, expected
    assert gateway._validate_signature(target, urlsplit(proxy).query)
    assert "cdn.example" not in proxy
    assert "movie.mp4" not in proxy
print("PASS: signed transport hints for HLS, MPEG-TS, MP4 and DASH")
