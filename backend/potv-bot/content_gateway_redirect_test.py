"""No provider redirect may reach localhost/private IPs or leak headers."""
from urllib.request import Request

from content_gateway import ContentGateway, ContentGatewayError, _SafeUpstreamRedirect

gateway = ContentGateway(
    sources=[],
    public_base="https://potv.example",
    signing_secret=b"test-only-redirects",
)
handlers = [
    handler for handler in gateway.opener.handlers
    if isinstance(handler, _SafeUpstreamRedirect)
]
assert len(handlers) == 1, "default opener must enforce redirect checks"
handler = handlers[0]
assert not gateway._allowed_upstream("http://100.64.0.1/private")
source = Request(
    "https://licensed.example/media/master.m3u8",
    headers={
        "User-Agent": "POTV",
        "Authorization": "Bearer never-forward",
        "Cookie": "session=never-forward",
    },
)
for unsafe in (
    "http://127.0.0.1/internal",
    "http://169.254.169.254/latest/meta-data",
    "http://10.0.0.2/admin",
    "http://100.64.0.1/private",
    "https://[::1]/private",
    "http://localhost/secret",
    "https://service.local/internal",
    "file:///etc/passwd",
    "javascript:alert(1)",
    "http://cdn.example/media/stream.ts",  # no HTTPS downgrade
    "https://user:password@cdn.example/stream.ts",
):
    try:
        handler.redirect_request(source, None, 302, "Found", {}, unsafe)
    except ContentGatewayError as exc:
        assert exc.code == "upstream_not_allowed", unsafe
    else:
        raise AssertionError("unsafe redirect allowed: " + unsafe)

redirected = handler.redirect_request(
    source, None, 302, "Found", {},
    "https://edge.cdn.example/live/stream.m3u8",
)
assert redirected.full_url == "https://edge.cdn.example/live/stream.m3u8"
assert redirected.get_header("User-agent") == "POTV"
assert not any(
    key.lower() in ("authorization", "cookie", "x-api-key")
    for key in redirected.headers
)
# A non-TLS upstream can upgrade to a public HTTPS CDN.
source_http = Request("http://licensed.example/live")
assert handler.redirect_request(
    source_http, None, 302, "Found", {},
    "https://edge.cdn.example/live",
).full_url == "https://edge.cdn.example/live"
print("PASS: public CDN redirects work, private/downgrade/credential redirects blocked")
