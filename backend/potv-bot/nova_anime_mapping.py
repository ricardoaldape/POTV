"""Conservative NOVA(TMDb) -> AniList anime ID crosswalk.

POTV's anime screens use AniList IDs; a NOVA TMDb ID must never be passed as
an AniList ID. Only exact title + compatible release year matches are accepted.
Unmatched/ambiguous items stay out of the anime shelf rather than opening the
wrong series. No upstream account, token or media URL is sent to AniList.
"""
import json
import os
import re
import tempfile
import time
import unicodedata
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener, HTTPRedirectHandler


ANILIST_URL = "https://graphql.anilist.co"
MAX_BATCH = 12
NEGATIVE_TTL = 7 * 24 * 3600


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def _title(value):
    raw = unicodedata.normalize("NFKD", str(value or "").casefold())
    raw = "".join(c for c in raw if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", " ", raw).strip()


def _year(value):
    try:
        number = int(value)
        return number if 1900 <= number <= 2100 else None
    except (TypeError, ValueError):
        return None


def _title_for_match(title, year):
    # NOVA sometimes includes the same release year in the title.
    value = str(title or "").strip()
    if year:
        value = re.sub(r"\s*\(" + str(year) + r"\)\s*$", "", value)
    return _title(value)


def select_anilist_id(title, year, candidates):
    """Return an ID only for a single exact, year-compatible AniList entry."""
    target = _title_for_match(title, _year(year))
    expected_year = _year(year)
    if not target or not isinstance(candidates, list):
        return None
    ids = set()
    for row in candidates:
        if not isinstance(row, dict):
            continue
        ident = row.get("id")
        if not isinstance(ident, int) or ident <= 0:
            continue
        date = row.get("startDate")
        actual_year = _year(date.get("year")) if isinstance(date, dict) else None
        if expected_year is not None and actual_year != expected_year:
            continue
        titles = row.get("title") if isinstance(row.get("title"), dict) else {}
        aliases = list(titles.values())
        if isinstance(row.get("synonyms"), list):
            aliases.extend(row["synonyms"])
        if any(_title(alias) == target for alias in aliases):
            ids.add(ident)
    return next(iter(ids)) if len(ids) == 1 else None


def _load(path):
    try:
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
        if raw.get("version") == 1 and isinstance(raw.get("entries"), dict):
            return raw["entries"]
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    return {}


def _save(path, entries):
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temp = tempfile.mkstemp(prefix=".nova-anime-", dir=target.parent)
    try:
        os.chmod(temp, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"version": 1, "entries": entries}, fh,
                      ensure_ascii=False, separators=(",", ":"))
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def refresh_cache(items, path, *, batch_size=MAX_BATCH, opener=None, now=None):
    """Map at most 12 *uncached* titles per call; never block catalog sync.

    A negative result is retried after seven days. Upstream errors are not
    cached as negatives. Reused entries must match title and year exactly.
    """
    entries = _load(path)
    stamp = int(time.time() if now is None else now)
    pending, seen = [], set()
    for row in items:
        if not isinstance(row, dict):
            continue
        tmdb = row.get("tmdb_id")
        title = str(row.get("title") or "").strip()
        year = _year(row.get("year"))
        try:
            key = str(int(tmdb))
        except (TypeError, ValueError):
            continue
        if not title or key in seen or int(key) <= 0:
            continue
        seen.add(key)
        old = entries.get(key) if isinstance(entries.get(key), dict) else {}
        if old.get("title") == title and old.get("year") == year:
            if isinstance(old.get("anilist_id"), int) and old["anilist_id"] > 0:
                continue
            try:
                last_checked = int(old.get("checked_at") or 0)
            except (TypeError, ValueError):
                last_checked = 0
            if stamp - last_checked < NEGATIVE_TTL:
                continue
        pending.append((key, title, year))
        if len(pending) >= max(1, min(MAX_BATCH, int(batch_size))):
            break
    if not pending:
        return entries, 0
    args = ",".join(f"$q{i}:String!" for i in range(len(pending)))
    fields = "id title{romaji english native} synonyms startDate{year}"
    blocks = " ".join(
        f"a{i}:Page(perPage:5){{media(search:$q{i},type:ANIME,isAdult:false){{{fields}}}}}"
        for i in range(len(pending))
    )
    payload = json.dumps({
        "query": "query(" + args + "){" + blocks + "}",
        "variables": {f"q{i}": title for i, (_, title, _) in enumerate(pending)},
    }).encode("utf-8")
    req = Request(ANILIST_URL, data=payload, headers={
        "Content-Type": "application/json",
        "Accept": "application/json",
        "User-Agent": "POTV-Anime-Interoperability/1.0",
    })
    client = opener or build_opener(_NoRedirect())
    try:
        with client.open(req, timeout=12) as response:
            if getattr(response, "status", 200) != 200:
                return entries, 0
            body = response.read(512 * 1024 + 1)
        if len(body) > 512 * 1024:
            return entries, 0
        parsed = json.loads(body)
        if (not isinstance(parsed, dict) or parsed.get("errors")
                or not isinstance(parsed.get("data"), dict)):
            return entries, 0
    except (HTTPError, URLError, OSError, ValueError, TypeError, TimeoutError):
        return entries, 0

    mapped = 0
    for i, (key, title, year) in enumerate(pending):
        page = parsed["data"].get(f"a{i}")
        if not isinstance(page, dict) or not isinstance(page.get("media"), list):
            continue
        ident = select_anilist_id(title, year, page["media"])
        entries[key] = {
            "title": title,
            "year": year,
            "anilist_id": ident,
            "checked_at": stamp,
        }
        if ident:
            mapped += 1
    _save(path, entries)
    return entries, mapped


def normalize_anime(items, entries):
    result, seen = [], set()
    for row in items:
        if not isinstance(row, dict) or row.get("is_adult") is True:
            continue
        title = str(row.get("title") or "").strip()
        year = _year(row.get("year"))
        try:
            tmdb = int(row.get("tmdb_id"))
        except (TypeError, ValueError):
            continue
        if tmdb <= 0 or not title:
            continue
        cache = entries.get(str(tmdb))
        if not isinstance(cache, dict):
            cache = {}
        if (cache.get("title") == title and cache.get("year") == year):
            ident = cache.get("anilist_id")
        else:
            ident = row.get("anilist_id")
        try:
            ident = int(ident)
        except (TypeError, ValueError):
            continue
        if ident <= 0 or ident in seen:
            continue
        seen.add(ident)
        # No upstream playback links or account credentials in this shelf.
        result.append({
            "anilist_id": ident,
            "tmdb_id": tmdb,
            "title": title,
            "year": str(year or ""),
            "poster": str(row.get("poster_url") or ""),
            "backdrop": str(row.get("backdrop_url") or ""),
            "overview": str(row.get("overview") or "")[:1200],
        })
    return result
