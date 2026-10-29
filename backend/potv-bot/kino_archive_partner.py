"""Kino's licensed Internet Archive plugin route: opt-in, public-domain VOD.

The app's Kino plugin metadata lists kinotvapp/kino-plugin-archive. Resolve
only titles that exactly match a movie, whose item metadata explicitly carries
a public-domain/CC0 license, and one valid direct file. No APK credentials.
"""
import json
import re
import time
import unicodedata
from urllib.parse import urlencode, quote
from urllib.request import urlopen, Request

_ALLOWED_LICENSE = (
    "creativecommons.org/publicdomain/mark/1.0",
    "creativecommons.org/publicdomain/zero/1.0",
)
_VIDEO_EXTS = (".mp4", ".m4v", ".webm")


def normalized_title(value):
    value = unicodedata.normalize("NFKD", str(value or "").casefold())
    value = "".join(c for c in value if not unicodedata.combining(c))
    return " ".join(re.findall(r"[a-z0-9]+", value))[:160]


def permitted_license(value):
    value = str(value or "").strip().casefold().replace("https://", "").replace("http://", "")
    return any(value.startswith(item) for item in _ALLOWED_LICENSE)


class KinoArchivePartner:
    def __init__(self, *, transport=urlopen, ttl=600):
        self._transport = transport
        self._ttl = max(60, min(int(ttl), 1800))
        self._cache = {}

    def _json(self, url, max_bytes=600000):
        req = Request(url, headers={
            "Accept": "application/json",
            "User-Agent": "POTV-licensed-Kino-Archive/1.0",
        })
        with self._transport(req, timeout=9) as resp:
            body = resp.read(max_bytes + 1)
        if len(body) > max_bytes:
            raise ValueError("kino_archive_response_too_large")
        return json.loads(body)

    def movie_sources(self, *, title, year=None):
        needle = normalized_title(title)
        if not 3 <= len(needle) <= 120:
            return []
        year = str(year or "").strip()
        if year and not re.fullmatch(r"\d{4}", year):
            year = ""
        cache_key = needle + "|" + year
        cached = self._cache.get(cache_key)
        now = time.monotonic()
        if cached and now - cached[0] < self._ttl:
            return list(cached[1])
        # Avoid unbounded search-term cache in a continuously running gateway.
        if len(self._cache) >= 48:
            self._cache.clear()
        query = (
            'title:"' + needle.replace('"', "") +
            '" AND mediatype:movies AND (collection:feature_films OR collection:classic_tv)'
        )
        params = [
            ("q", query), ("fl[]", "identifier"), ("fl[]", "title"),
            ("fl[]", "year"), ("fl[]", "licenseurl"),
            ("rows", "14"), ("page", "1"), ("output", "json"),
        ]
        search_url = "https://archive.org/advancedsearch.php?" + urlencode(params)
        try:
            search = self._json(search_url)
            docs = search.get("response", {}).get("docs", [])
            if not isinstance(docs, list):
                return []
            # Prefer an exact title and year, never a misleading similar film.
            candidates = []
            for row in docs[:14]:
                if not isinstance(row, dict):
                    continue
                identifier = str(row.get("identifier") or "")
                if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]{1,100}", identifier):
                    continue
                if normalized_title(row.get("title")) != needle:
                    continue
                if year and str(row.get("year") or "").strip() not in ("", year):
                    continue
                if not permitted_license(row.get("licenseurl")):
                    continue
                candidates.append(identifier)
            for identifier in candidates[:3]:
                metadata = self._json("https://archive.org/metadata/" + quote(identifier), 750000)
                meta = metadata.get("metadata") or {}
                if not isinstance(meta, dict) or not permitted_license(meta.get("licenseurl")):
                    continue
                if str(meta.get("is_dark") or "").lower() in ("true", "1"):
                    continue
                files = metadata.get("files") or []
                if not isinstance(files, list):
                    continue
                playable = []
                for file in files[:450]:
                    if not isinstance(file, dict):
                        continue
                    name = str(file.get("name") or "")
                    if (not name or "/" in name or "\\" in name
                            or not name.lower().endswith(_VIDEO_EXTS)):
                        continue
                    try:
                        size = int(file.get("size", 0))
                    except (TypeError, ValueError, OverflowError):
                        continue
                    if not (100000 <= size <= 8 * 1024**3):
                        continue
                    if file.get("private") in ("true", True):
                        continue
                    playable.append((0 if name.lower().endswith(".mp4") else 1,
                                     -size, name))
                if not playable:
                    continue
                playable.sort()
                filename = playable[0][2]
                url = "https://archive.org/download/" + quote(identifier) + "/" + quote(filename)
                found = [{"url": url, "language": "und", "quality": None}]
                self._cache[cache_key] = (now, found)
                return list(found)
        except (OSError, ValueError, TypeError, KeyError, TimeoutError, json.JSONDecodeError):
            return []
        self._cache[cache_key] = (now, [])
        return []
