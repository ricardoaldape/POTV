"""Regression: Kino Archive's signed MP4 proxy preserves Range/206 and bytes."""
import io
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.parse import unquote, urlsplit
from urllib.request import Request, urlopen
from unittest.mock import patch

from content_gateway import ContentGateway

class FakeUpstream(io.BytesIO):
    def __init__(self, payload, requested_range, upstream):
        super().__init__(payload)
        self.status = 206
        self.headers = {
            "Content-Type": "video/mp4",
            "Content-Length": str(len(payload)),
            "Content-Range": f"bytes {requested_range}/{10 * 1024 * 1024}",
            "Accept-Ranges": "bytes",
        }
        self.upstream = upstream

    def geturl(self):
        return self.upstream

gateway = ContentGateway(
    sources=[],
    public_base="http://127.0.0.1",
    signing_secret=b"isolated-signed-proxy-test",
)
upstream = "https://archive.org/download/test_public_domain/film.mp4"
target = gateway._register_target(upstream)
calls = []
first = b"\x00\x00\x00\x18ftypisom" + b"x" * (4096 - 12)
later = b"y" * 4096

def fake_fetch(url, headers=None, timeout=None):
    assert url == upstream
    requested = (headers or {}).get("Range")
    calls.append(requested)
    if requested == "bytes=0-4095":
        return FakeUpstream(first, "0-4095", upstream)
    if requested == "bytes=1048576-1052671":
        return FakeUpstream(later, "1048576-1052671", upstream)
    raise AssertionError("unexpected range")

gateway._fetch = fake_fetch

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        parsed = urlsplit(self.path)
        prefix = "/api/v1/content/stream/"
        assert parsed.path.startswith(prefix)
        gateway.serve_target(self, unquote(parsed.path[len(prefix):]), parsed.query)

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    gateway.public_base = f"http://127.0.0.1:{server.server_port}"
    signed = gateway._proxy_url(target, lifetime=10800)
    assert "format=mp4" in signed
    for value, expected in [
        ("bytes=0-4095", first),
        ("bytes=1048576-1052671", later),
    ]:
        with urlopen(Request(signed, headers={"Range": value}), timeout=5) as resp:
            assert resp.status == 206
            assert resp.headers.get("Content-Type") == "video/mp4"
            assert resp.headers.get("Content-Range") == (
                f"bytes {value[6:]}/{10 * 1024 * 1024}"
            )
            assert resp.headers.get("Accept-Ranges") == "bytes"
            assert resp.read() == expected
    assert calls == ["bytes=0-4095", "bytes=1048576-1052671"]
    # A forged signature must not make a new upstream request.
    with patch("content_gateway.time.time", return_value=time.time() + 10861):
        assert not gateway._validate_signature(target, urlsplit(signed).query)
    bad = signed.replace("s=", "s=invalid", 1)
    try:
        urlopen(bad, timeout=5)
        raise AssertionError("forged signature accepted")
    except HTTPError as error:
        assert error.code == 403
    assert len(calls) == 2
finally:
    server.shutdown()
    server.server_close()

print("PASS: Kino signed MP4 proxy 206, Range, bytes, 3h expiry, rejected forgery")
