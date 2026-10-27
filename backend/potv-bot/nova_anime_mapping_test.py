"""Offline AniList crosswalk contract: exact IDs only, no guesses."""
import io
import json
import tempfile
from pathlib import Path
from nova_anime_mapping import (
    normalize_anime, refresh_cache, select_anilist_id,
)


def media(ident, name, year=2026, synonyms=None):
    return {
        "id": ident,
        "title": {"english": name, "romaji": name, "native": None},
        "startDate": {"year": year},
        "synonyms": synonyms or [],
    }


assert select_anilist_id("Cyberpunk: Edgerunners 2", 2026,
                         [media(195539, "Cyberpunk: Edgerunners 2")]) == 195539
assert select_anilist_id("Magic Knight Rayearth (2026)", 2026,
                         [media(500, "Magic Knight Rayearth")]) == 500
assert select_anilist_id("Different title", 2026,
                         [media(100, "Other title")]) is None
assert select_anilist_id("Same title", 2026,
                         [media(100, "Same title", 2024)]) is None
assert select_anilist_id("Same title", 2026,
                         [media(100, "Same title"),
                          media(101, "Same title")]) is None
assert select_anilist_id("Aka show", 2026,
                         [media(200, "Original", synonyms=["Aka show"])]) == 200


class FakeResponse(io.BytesIO):
    status = 200
    def __enter__(self):
        return self
    def __exit__(self, *_):
        self.close()


class FakeOpener:
    def __init__(self):
        self.calls = 0
    def open(self, request, timeout=0):
        self.calls += 1
        assert request.full_url == "https://graphql.anilist.co"
        assert "Authorization" not in request.headers
        variables = json.loads(request.data)["variables"]
        pages = {}
        for i, title in enumerate(variables.values()):
            if title == "Cyberpunk: Edgerunners 2":
                matches = [media(195539, title)]
            elif title == "Dark Machine: The Animation":
                matches = [media(179876, title)]
            elif title == "Wrong year":
                matches = [media(1, title, 2024)]
            elif title == "Ambiguous":
                matches = [media(2, title), media(3, title)]
            else:
                matches = []
            pages[f"a{i}"] = {"media": matches}
        return FakeResponse(json.dumps({"data": pages}).encode())


rows = [
    {"tmdb_id": 326788, "title": "Cyberpunk: Edgerunners 2", "year": 2026,
     "poster_url": "https://cdn.example/poster.jpg"},
    {"tmdb_id": 306565, "title": "Dark Machine: The Animation", "year": 2026},
    {"tmdb_id": 444, "title": "Wrong year", "year": 2026},
    {"tmdb_id": 555, "title": "Ambiguous", "year": 2026},
    {"tmdb_id": 666, "title": "No match", "year": 2026},
]
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / "private" / "anime-map.json"
    opener = FakeOpener()
    cache, mapped = refresh_cache(rows, path, opener=opener, now=1234567890)
    assert mapped == 2, (mapped, cache)
    assert path.exists()
    assert path.stat().st_mode & 0o777 == 0o600
    assert cache["444"]["anilist_id"] is None
    assert cache["555"]["anilist_id"] is None
    mapped_rows = normalize_anime(rows, cache)
    assert len(mapped_rows) == 2
    assert [r["anilist_id"] for r in mapped_rows] == [195539, 179876]
    assert mapped_rows[0]["tmdb_id"] == 326788
    assert "url" not in mapped_rows[0]
    assert mapped_rows[0]["poster"] == "https://cdn.example/poster.jpg"
    _, second_count = refresh_cache(rows, path, opener=opener,
                                    now=1234567890 + 3600)
    assert second_count == 0
    assert opener.calls == 1, "cached IDs and negatives should not hammer AniList"
    # A stale provider title cannot accidentally reuse the old AniList ID.
    changed = [dict(rows[0], title="Cyberpunk: Wrong Show")]
    assert normalize_anime(changed, cache) == []
    _, retry_count = refresh_cache(rows, path, opener=opener,
                                   now=1234567890 + 8 * 24 * 3600)
    assert retry_count == 0
    assert opener.calls == 2, "negative entries should be refreshed after a week"
print("PASS: exact AniList IDs, year, ambiguity, privacy, cache TTL and stale title")


# A newly mapped anime must invalidate the subscriber catalog revision.
from nova_catalog_sync import snapshot_revision
channel = [{"id":"nova:1", "url":"https://fixture.example/live.m3u8",
            "format":"hls", "backup_urls":[]}]
film = [{"tmdb_id": 10, "title": "Film"}]
first = snapshot_revision(channel, film, [], [])
second = snapshot_revision(channel, film, [], mapped_rows)
assert first != second
assert second == snapshot_revision(channel, film, [], list(reversed(mapped_rows)))
assert second != snapshot_revision(channel, film + [{"tmdb_id": 11,
    "title":"New film"}], [], mapped_rows)
print("PASS: subscriber revision changes for anime and VOD catalog updates")
