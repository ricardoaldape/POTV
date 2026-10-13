"""Offline smoke test for the POTV authorized content gateway."""
import io
import json
import os
import tempfile

from content_gateway import ContentGateway


class FakeResponse(io.BytesIO):
    def __init__(self, body, content_type="application/vnd.apple.mpegurl"):
        super().__init__(body)
        self.status = 200
        self.headers = {
            "Content-Type": content_type,
            "Content-Length": str(len(body)),
        }

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


class FakeOpener:
    def __init__(self, source_url, source_body):
        self.source_url = source_url
        self.source_body = source_body

    def open(self, request, timeout=0):
        url = request.full_url
        if url == self.source_url:
            return FakeResponse(self.source_body.encode("utf-8"), "audio/x-mpegurl")
        raise AssertionError("unexpected upstream request")


def run():
    source = (
        "https://partner.example/get.php?"
        "username=private-user&password=private-password&type=m3u_plus"
    )
    m3u = """#EXTM3U
#EXTINF:-1 tvg-id="espn.mx" group-title="Deportes",ESPN
http://media.partner.example/live/espn.m3u8?token=private-stream-token
#EXTINF:-1 tvg-id="hbo.mx" group-title="Cine",HBO
https://media.partner.example/live/hbo.m3u8
"""
    with tempfile.TemporaryDirectory() as directory:
        metadata_path = os.path.join(directory, "metadata.json")
        with open(metadata_path, "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "now_next": [
                        {
                            "channel_id": "espn.mx",
                            "current": {
                                "title": "Partido en vivo",
                                "starts_at": "2026-10-12T22:00:00-06:00",
                                "ends_at": "2026-10-12T23:00:00-06:00",
                            },
                            "next": {
                                "title": "SportsCenter",
                                "starts_at": "2026-10-12T23:00:00-06:00",
                                "ends_at": "2026-10-13T00:00:00-06:00",
                            },
                        }
                    ],
                    "sports_events": [
                        {
                            "id": "with-stream",
                            "sport": "Soccer",
                            "competition": "Liga MX",
                            "home": "Local",
                            "away": "Visita",
                            "starts_at": "2026-10-12T22:00:00-06:00",
                            "is_live": True,
                            "stream_url": "http://events.partner.example/live.m3u8?key=private",
                        },
                        {
                            "id": "without-stream",
                            "sport": "Soccer",
                            "competition": "Liga MX",
                            "home": "Sin",
                            "away": "Señal",
                            "starts_at": "2026-10-12T23:00:00-06:00",
                        },
                    ],
                },
                fh,
            )

        gateway = ContentGateway(
            sources=[source],
            public_base="https://potv.example",
            signing_secret=b"smoke-secret",
            refresh_seconds=120,
            opener=FakeOpener(source, m3u),
            metadata_file=metadata_path,
        )
        payload = gateway.catalog()
        data = payload["data"]

        assert [channel["name"] for channel in data["channels"]] == ["ESPN", "HBO"]
        assert [channel["name"] for channel in data["sports_channels"]] == ["ESPN"]
        assert len(data["now_next"]) == 1
        assert [event["id"] for event in data["sports_events"]] == ["with-stream"]

        encoded = json.dumps(payload)
        assert "private-user" not in encoded
        assert "private-password" not in encoded
        assert "private-stream-token" not in encoded
        assert "events.partner.example" not in encoded
        assert "media.partner.example" not in encoded
        assert "https://potv.example/api/v1/content/stream/" in encoded

        rewritten = gateway._rewrite_hls(
            "#EXTM3U\nsegment01.ts\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\n",
            "http://media.partner.example/live/master.m3u8?token=private",
            {},
        )
        assert "media.partner.example" not in rewritten
        assert "https://potv.example/api/v1/content/stream/" in rewritten

    print("PASS: partner credentials hidden, premium preserved, sports guide/event integrity")


if __name__ == "__main__":
    run()
