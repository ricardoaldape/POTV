"""Authenticated VOD metadata pagination keeps private provider fields private."""
import json
import os
import tempfile
from content_gateway import ContentGateway, ContentGatewayError

with tempfile.TemporaryDirectory() as folder:
    path = os.path.join(folder, "nova.json")
    movies = [
        {"tmdb_id": i + 1, "title": f"Movie {i + 1}",
         "year": "2026", "overview": "Sample", "poster": "https://image.tmdb.org/t/p/w500/cover.jpg",
         "url": "https://private.example/movie?password=secret", "token": "secret"}
        for i in range(2200)
    ]
    movies[1490]["poster"] = "https://private.example/poster?password=secret"
    movies[1491]["backdrop"] = "https://image.tmdb.org/t/p/w500/backdrop.jpg"
    snapshot = {"revision": "fixture-revision", "channels": [],
                "movies": movies, "series": [], "anime": []}
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(snapshot, fh)
    gateway = ContentGateway(sources=[], public_base="https://potv.example",
                             signing_secret=b"test-secret")
    gateway.nova_live_enabled = True
    gateway.nova_sync_file = path

    first = gateway.media_page(kind="movies", offset=0, limit=500)["data"]
    assert first["total"] == 2200
    assert first["revision"] == "fixture-revision"
    assert len(first["items"]) == 500
    assert first["has_more"]
    page = gateway.media_page(kind="movies", offset=1490, limit=200)["data"]
    assert len(page["items"]) == 200
    assert page["items"][0]["tmdb_id"] == 1491
    assert page["items"][-1]["tmdb_id"] == 1690
    assert "poster" not in page["items"][0]
    assert "backdrop" in page["items"][1]
    assert "url" not in page["items"][0]
    assert "token" not in page["items"][0]
    assert "private.example" not in json.dumps(page)
    last = gateway.media_page(kind="movies", offset=2190, limit=200)["data"]
    assert len(last["items"]) == 10 and not last["has_more"]
    assert gateway.media_page(kind="series")["data"]["items"] == []
    for kwargs in ({"kind": "videos"}, {"kind": "movies", "offset": -1},
                   {"kind": "movies", "limit": 501},
                   {"kind": "movies", "limit": 0}):
        try:
            gateway.media_page(**kwargs)
            raise AssertionError("Invalid media request allowed")
        except ContentGatewayError as exc:
            assert exc.status == 400
    gateway.nova_live_enabled = False
    try:
        gateway.media_page(kind="movies")
        raise AssertionError("Disabled private catalog allowed")
    except ContentGatewayError as exc:
        assert exc.status == 503
print("PASS: private media pages >1500, bounded cursor, safe metadata and errors")
