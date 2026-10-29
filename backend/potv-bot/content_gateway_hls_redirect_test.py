"""A redirected HLS manifest must use its final CDN base and isolate credentials."""
import io
from urllib.parse import urlsplit

from content_gateway import ContentGateway, ContentGatewayError


class Response(io.BytesIO):
    def __init__(self, data, final_url):
        super().__init__(data)
        self.headers = {"Content-Type": "application/vnd.apple.mpegurl"}
        self.status = 200
        self.final_url = final_url

    def geturl(self):
        return self.final_url


class Handler:
    def __init__(self):
        self.headers = {}
        self.wfile = io.BytesIO()
        self.status = None

    def send_response(self, code):
        self.status = code

    def send_header(self, *_):
        pass

    def end_headers(self):
        pass


gateway = ContentGateway(
    sources=[], public_base="https://potv.example",
    signing_secret=b"qa-redirect-fixture",
)
original = "https://licensed.example/hls/master.m3u8?token=never-leak"
final = "https://cdn.example.net/live/season/master.m3u8"
headers = {
    "Authorization": "Bearer secret",
    "Cookie": "session=private",
    "Referer": "https://licensed.example/account?secret=private",
    "X-Api-Key": "secret",
    "User-Agent": "POTV-QA",
}
target = gateway._register_target(original, headers)
playlist = (
    b"#EXTM3U\n#EXT-X-VERSION:3\n"
    b"#EXT-X-KEY:METHOD=AES-128,URI=\"keys/key.bin\"\n"
    b"#EXTINF:6,\nseg001.ts\n"
    b"#EXT-X-STREAM-INF:BANDWIDTH=1000000\n"
    b"https://other-cdn.example.net/variant.m3u8\n"
)
gateway._fetch = lambda *_args, **_kwargs: Response(playlist, final)
handler = Handler()
gateway.serve_target(handler, target, urlsplit(gateway._proxy_url(target)).query)
assert handler.status == 200
assert b"cdn.example.net" not in handler.wfile.getvalue()
assert b"secret" not in handler.wfile.getvalue()
resolved = {
    url: hdr for url, hdr in gateway._targets.values() if url != original
}
assert set(resolved) == {
    "https://cdn.example.net/live/season/keys/key.bin",
    "https://cdn.example.net/live/season/seg001.ts",
    "https://other-cdn.example.net/variant.m3u8",
}, resolved
for hdr in resolved.values():
    assert hdr == {"User-Agent": "POTV-QA"}, hdr

# No redirect: provider-relative segments may retain origin credentials.
same = gateway._rewrite_hls("#EXTM3U\nseg002.ts\n", original, headers)
assert "licensed.example" not in same
assert gateway._targets[
    next(k for k, v in gateway._targets.items()
         if v[0].endswith("/hls/seg002.ts"))
][1] == {"User-Agent": "POTV-QA", "Referer": headers["Referer"]}

# Redirects into private networks or HTTPS downgrades fail closed.
for bad in ("http://cdn.example.net/live/master.m3u8",
            "https://127.0.0.1/secret"):
    gateway._fetch = lambda *_args, **_kwargs: Response(playlist, bad)
    rejected = Handler()
    gateway.serve_target(rejected, target, urlsplit(gateway._proxy_url(target)).query)
    assert rejected.status == 400, (bad, rejected.status)

print("PASS: redirected HLS segments use final CDN, strip credentials and reject unsafe redirects")
