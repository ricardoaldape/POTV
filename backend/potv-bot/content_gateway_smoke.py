"""Offline smoke test for the POTV authorized content gateway."""
import io
import json
import os
import tempfile
import time
import base64
from urllib.parse import parse_qs, urlsplit

from content_gateway import ContentGateway


class FakeResponse(io.BytesIO):
    def __init__(self, body, content_type="application/json"):
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
    def open(self, request, timeout=0):
        uri = urlsplit(request.full_url)
        query = parse_qs(uri.query)
        action = (query.get("action") or [""])[0]

        if not uri.path.endswith("/player_api.php"):
            raise AssertionError("unexpected upstream request")

        if action == "get_short_epg":
            now = int(time.time())
            def b64(value):
                return base64.b64encode(value.encode("utf-8")).decode("ascii")
            return FakeResponse(json.dumps({
                "epg_listings": [
                    {
                        "title": b64("Partido de prueba"),
                        "description": b64("Transmisión deportiva"),
                        "start_timestamp": now - 300,
                        "stop_timestamp": now + 1500,
                    },
                    {
                        "title": b64("Resumen de prueba"),
                        "description": b64("Después"),
                        "start_timestamp": now + 1500,
                        "stop_timestamp": now + 3300,
                    },
                ]
            }).encode("utf-8"))

        payloads = {
            "get_live_categories": [
                {"category_id": "1", "category_name": "⭐️ Deportes México"},
                {"category_id": "2", "category_name": "Adultos ❌❌❌"},
                {"category_id": "3", "category_name": "⭐️ CINE PREMIUM"},
            ],
            "get_live_streams": [
                {
                    "stream_id": 101,
                    "name": "ESPN",
                    "category_id": "1",
                    "epg_channel_id": "espn.mx",
                    "container_extension": "ts",
                },
                {
                    "stream_id": 102,
                    "name": "HBO",
                    "category_id": "3",
                    "epg_channel_id": "hbo.mx",
                    "container_extension": "ts",
                },
                {
                    "stream_id": 999,
                    "name": "Canal XXX",
                    "category_id": "2",
                    "container_extension": "ts",
                },
            ],
            "get_vod_categories": [
                {"category_id": "10", "category_name": "Películas"},
                {"category_id": "11", "category_name": "Adultos"},
            ],
            "get_vod_streams": [
                {
                    "stream_id": 501,
                    "name": "Sample Movie (2026)",
                    "category_id": "10",
                    "container_extension": "mp4",
                    "tmdb": "101",
                    "year": "2026",
                },
                {
                    "stream_id": 599,
                    "name": "Película XXX",
                    "category_id": "11",
                    "container_extension": "mp4",
                    "tmdb": "999",
                },
            ],
            "get_series_categories": [
                {"category_id": "20", "category_name": "Series"},
                {"category_id": "21", "category_name": "Adultos"},
            ],
            "get_series": [
                {
                    "series_id": 601,
                    "name": "Sample Show",
                    "category_id": "20",
                    "tmdb": "202",
                    "year": "2025",
                },
                {
                    "series_id": 699,
                    "name": "Serie Erótica",
                    "category_id": "21",
                    "tmdb": "998",
                },
            ],
            "get_series_info": {
                "episodes": {
                    "1": [
                        {
                            "id": 701,
                            "episode_num": 2,
                            "container_extension": "mp4",
                        }
                    ]
                }
            },
        }
        if action not in payloads:
            raise AssertionError("unexpected Xtream action")
        return FakeResponse(json.dumps(payloads[action]).encode("utf-8"))


def run():
    source = (
        "https://partner.example/get.php?"
        "username=private-user&password=private-password&type=m3u_plus"
    )
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
            opener=FakeOpener(),
            metadata_file=metadata_path,
        )
        payload = gateway.catalog()
        data = payload["data"]

        assert [channel["name"] for channel in data["channels"]] == ["ESPN", "HBO"]
        assert [channel["name"] for channel in data["sports_channels"]] == ["ESPN"]
        assert len(data["now_next"]) >= 1
        # Catalog hydration is intentionally asynchronous. Test the deterministic
        # short-EPG normalizer directly instead of racing its background thread.
        live_rows = gateway._xtream_live_channels(source)
        dynamic_guide = gateway._xtream_sports_guide(source, live_rows)
        assert any(
            (row.get("current") or {}).get("title") == "Partido de prueba"
            for row in dynamic_guide
        )
        assert [event["id"] for event in data["sports_events"]] == ["with-stream"]

        movie = gateway.resolve_movie(
            tmdb_id="101",
            title="Sample Movie",
            year="2026",
        )
        assert len(movie["sources"]) == 1

        episode = gateway.resolve_series_episode(
            tmdb_id="202",
            title="Sample Show",
            year="2025",
            season=1,
            episode=2,
        )
        assert len(episode["sources"]) == 1

        blocked_movie = gateway.resolve_movie(
            tmdb_id="999",
            title="Película XXX",
        )
        blocked_series = gateway.resolve_series_episode(
            tmdb_id="998",
            title="Serie Erótica",
            season=1,
            episode=2,
        )
        assert blocked_movie["sources"] == []
        assert blocked_series["sources"] == []

        encoded = json.dumps(
            {
                "catalog": payload,
                "movie": movie,
                "episode": episode,
            },
            ensure_ascii=False,
        )
        assert "private-user" not in encoded
        assert "private-password" not in encoded
        assert "partner.example/movie/" not in encoded
        assert "partner.example/series/" not in encoded
        assert "events.partner.example" not in encoded
        assert "Canal XXX" not in encoded
        assert "https://potv.example/api/v1/content/stream/" in encoded

        rewritten = gateway._rewrite_hls(
            "#EXTM3U\nsegment01.ts\n#EXT-X-KEY:METHOD=AES-128,URI=\"key.bin\"\n",
            "http://media.partner.example/live/master.m3u8?token=private",
            {},
        )
        assert "media.partner.example" not in rewritten
        assert "https://potv.example/api/v1/content/stream/" in rewritten

    print(
        "PASS: Xtream live/VOD/series split, adult content blocked, "
        "credentials hidden, sports integrity preserved"
    )


if __name__ == "__main__":
    run()
