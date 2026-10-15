"""Regression: browser User-Agent commas must not appear in channel names."""
from content_gateway import ContentGateway

gateway = ContentGateway(
    sources=["https://provider.example/safe.m3u"],
    public_base="https://potv.example",
    signing_secret=b"regression-test-only",
)

line = (
    '#EXTINF:-1 http-user-agent="Mozilla/5.0 (KHTML, like Gecko) '
    'Chrome/154.0 Safari/537.36" group-title="Sports",'
    'ESPN 2 Latin America (1080p)'
)
attrs, name = gateway._parse_extinf(line)
assert attrs["group-title"] == "Sports"
assert attrs["http-user-agent"].startswith("Mozilla/")
assert name == "ESPN 2 Latin America (1080p)"
assert "Gecko" not in name

attrs, name = gateway._parse_extinf(
    '#EXTINF:-1 tvg-id="es" group-title="Deportes",ESPN 3'
)
assert name == "ESPN 3"
assert attrs["tvg-id"] == "es"

_, name = gateway._parse_extinf(
    '#EXTINF:-1 http-user-agent="Mozilla (KHTML, like Gecko),Broken'
)
assert name == ""
print("PASS: EXTINF respects quoted commas and excludes broken headers")
