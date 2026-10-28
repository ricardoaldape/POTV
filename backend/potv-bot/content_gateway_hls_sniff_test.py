"""Extensionless HLS must be rewritten, while ordinary binary media is unchanged."""
import io
from urllib.parse import urlsplit

from content_gateway import ContentGateway


class Response(io.BytesIO):
    def __init__(self, body, content_type):
        super().__init__(body)
        self.headers = {
            "Content-Type": content_type,
            "Content-Length": str(len(body)),
        }
        self.status = 200


class Handler:
    def __init__(self):
        self.headers = {}
        self.wfile = io.BytesIO()
        self.status = None
        self.response_headers = {}

    def send_response(self, code):
        self.status = code

    def send_header(self, key, value):
        self.response_headers[key.lower()] = value

    def end_headers(self):
        pass


def serve(body, content_type, path):
    gateway = ContentGateway(
        sources=[],
        public_base="https://potv.example",
        signing_secret=b"qa-fixture-not-production",
    )
    target = gateway._register_target("https://licensed.example/" + path)
    signed = urlsplit(gateway._proxy_url(target))
    gateway._fetch = lambda *_args, **_kwargs: Response(body, content_type)
    handler = Handler()
    gateway.serve_target(handler, target, signed.query)
    return handler, gateway


# This manifest has no .m3u8 suffix and is mislabeled as binary. A raw
# passthrough would leak a private provider token to the Android client.
manifest = (
    b"\xef\xbb\xbf#EXTM3U\n#EXT-X-VERSION:3\n"
    b"#EXTINF:6,\nsegment.ts?password=do-not-leak\n"
)
handler, gateway = serve(manifest, "application/octet-stream", "play?token=secret")
assert handler.status == 200
assert handler.response_headers["content-type"] == "application/vnd.apple.mpegurl"
assert handler.response_headers["content-length"] == str(len(handler.wfile.getvalue()))
assert handler.wfile.getvalue().startswith(b"#EXTM3U")
assert b"password=" not in handler.wfile.getvalue()
assert b"licensed.example" not in handler.wfile.getvalue()
assert b"/api/v1/content/stream/" in handler.wfile.getvalue()
assert len(gateway._targets) == 2

# Sniffing must not corrupt MPEG-TS/MP4 or silently change its length.
video = b"\x00\x00\x01\xba" + bytes(range(256)) * 80
handler, _ = serve(video, "application/octet-stream", "live")
assert handler.status == 200
assert handler.wfile.getvalue() == video
assert handler.response_headers["content-length"] == str(len(video))

# Keep the existing explicit .m3u8 detection path working for small playlists.
handler, _ = serve(b"#EXTM3U\n#EXT-X-ENDLIST\n", "text/plain", "index.m3u8")
assert handler.status == 200
assert handler.wfile.getvalue().startswith(b"#EXTM3U")

# An oversized manifest must fail closed, without returning upstream URLs.
huge = b"#EXTM3U\n" + b"#EXTINF:6,\nsegment.ts?password=secret\n" * 150000
handler, _ = serve(huge, "text/plain", "extensionless")
assert handler.status == 413
assert b"password=" not in handler.wfile.getvalue()
print("PASS: extensionless HLS rewrites signed segments; binary passthrough and size cap")
