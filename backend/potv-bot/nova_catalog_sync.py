"""Refresh authorized NOVA TV content into a private POTV-only snapshot.

Fetches a public, partner-authorized catalog or a provider-issued service
account; never places upstream stream URLs into a public endpoint.
"""
import hashlib
import json
import os
import sqlite3
from contextlib import closing
import ipaddress
import socket
import time
import tempfile
from concurrent.futures import ThreadPoolExecutor
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, Request, build_opener
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

from nova_partner import NovaPartner, NovaPartnerError
from nova_anime_mapping import refresh_cache, normalize_anime


SPORTS = ("sport", "deport", "fútbol", "futbol", "nfl", "nba", "mlb", "espn",
          "fox sports", "tudn", "dazn", "formula", "f1", "soccer")
EXCLUDE = ("adult", "xxx", "porn", "erotic", "18+", "argentina")
ALLOWED_REGIONS = {"latam", "mx", "mexico", "méxico", "es", "espana", "españa"}
ALLOWED_COUNTRIES = {"MX", "LATAM", "US", "ES"}


def _stream_url(value):
    if isinstance(value, dict):
        value = value.get("url") or value.get("stream_url") or value.get("primary_url")
    if not isinstance(value, str):
        return None
    try:
        parsed = urlsplit(value.strip())
        if parsed.scheme not in {"https", "http"} or not parsed.hostname or (
            parsed.username or parsed.password
        ):
            return None
    except ValueError:
        return None
    return value.strip()


def normalize_channels(items, *, limit=4500):
    results, seen = [], set()
    counts = {"skipped_adult": 0, "skipped_region": 0, "skipped_unplayable": 0}
    for item in items:
        if not isinstance(item, dict):
            continue
        country = str(item.get("country") or "").upper().strip()
        region = str(item.get("region") or "").lower().strip()
        category = str(item.get("category") or "").strip()
        name = str(item.get("name") or "").strip()
        value = f"{name} {category}".lower()
        if country == "AR" or any(w in value for w in EXCLUDE):
            counts["skipped_adult"] += 1
            continue
        sports = any(w in value for w in SPORTS)
        if (country not in ALLOWED_COUNTRIES and region not in ALLOWED_REGIONS
                and not (sports and country in {"INT", "LATAM"})):
            counts["skipped_region"] += 1
            continue
        if item.get("is_working") is False:
            counts["skipped_unplayable"] += 1
            continue
        url = _stream_url(item.get("stream_url"))
        if not url:
            counts["skipped_unplayable"] += 1
            continue
        ident = str(item.get("id") or "").strip()
        if not ident or not name or ident in seen:
            continue
        seen.add(ident)
        backup = []
        raw_backup = item.get("backup_urls")
        if isinstance(raw_backup, list):
            for candidate in raw_backup:
                v = _stream_url(candidate)
                if v and v != url and v not in backup:
                    backup.append(v)
                if len(backup) >= 4:
                    break
        results.append({
            "id": "nova:" + ident,
            "name": name,
            "group": category or "TV",
            "country": country,
            "url": url,
            "backup_urls": backup,
            "logo": _stream_url(item.get("logo_url")),
            "epg_id": str(item.get("catalog_id") or ""),
            "is_sports": sports,
            "quality": str(item.get("quality") or ""),
        })
    # Never truncate in upstream order: sports and Mexican channels may occur
    # late in a large partner catalog. Prioritize Mexico and sports first.
    def priority(item):
        country = item["country"]
        if item["is_sports"]:
            tier = 0
        elif country == "MX":
            tier = 1
        elif country == "LATAM":
            tier = 2
        elif country in {"ES", "US"}:
            tier = 4
        else:
            tier = 3
        return (tier, item["name"].casefold(), item["id"])
    results.sort(key=priority)
    counts["selected_before_limit"] = len(results)
    return results[:limit], counts


def normalize_media(items, *, category):
    out, seen = [], set()
    for row in items:
        if not isinstance(row, dict):
            continue
        tmdb = row.get("tmdb_id")
        title = str(row.get("title") or row.get("name") or "").strip()
        try:
            ident = int(tmdb)
        except (ValueError, TypeError):
            continue
        if ident <= 0 or not title or ident in seen:
            continue
        seen.add(ident)
        out.append({
            "tmdb_id": ident,
            "title": title,
            "year": str(row.get("year") or ""),
            "poster": _stream_url(row.get("poster_url")),
            "backdrop": _stream_url(row.get("backdrop_url")),
            "overview": str(row.get("overview") or "")[:1200],
        })
    return out


# NOVA marks a few HTML iframe landing pages as live channels. Media3 cannot
# decode HTML, and some genuine HLS sources have extensionless URLs. Probe only
# selected sports and iframe backups, never the full 11k-item provider feed.
_MEDIA_EXTENSIONS = (".m3u8", ".mpd", ".ts", ".mp4", ".mkv", ".webm", ".m4v")


def _url_format(url):
    path = urlsplit(url).path.lower()
    if path.endswith(".m3u8"):
        return "hls"
    if path.endswith(".mpd"):
        return "mpd"
    if path.endswith(".ts"):
        return "ts"
    if path.endswith((".mp4", ".mkv", ".webm", ".m4v")):
        return "mp4"
    return None


def _public_media_url(value):
    url = _stream_url(value)
    if not url:
        return False
    try:
        host = urlsplit(url).hostname
        addresses = socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
        return bool(addresses) and all(
            ipaddress.ip_address(entry[4][0]).is_global
            for entry in addresses
        )
    except (OSError, ValueError, TypeError):
        return False


class _SafeMediaRedirect(HTTPRedirectHandler):
    """Allow only bounded public CDN redirects without forwarding credentials."""

    def redirect_request(self, request, fp, code, msg, headers, newurl):
        hops = getattr(request, "potv_redirect_hops", 0)
        if code not in (301, 302, 303, 307, 308) or hops >= 3:
            return None
        if not _public_media_url(newurl):
            return None
        # Never copy upstream cookies, Authorization, Referer or Origin.
        next_request = Request(newurl, headers={
            "User-Agent": "POTV-Authorized-Stream-Check/1.0",
            "Range": "bytes=0-511",
            "Accept": "*/*",
        })
        next_request.potv_redirect_hops = hops + 1
        return next_request


def probe_stream_format(url):
    """Bounded content sniff; public-only redirects and addresses.

    Never log upstream URLs, response bodies or authorization information.
    A failed probe is *not* evidence that the provider is unlicensed.
    """
    value = _stream_url(url)
    if not value or not _public_media_url(value):
        return None
    try:
        req = Request(value, headers={
            "User-Agent": "POTV-Authorized-Stream-Check/1.0",
            "Range": "bytes=0-511",
            "Accept": "*/*",
        })
        with build_opener(_SafeMediaRedirect()).open(req, timeout=3) as response:
            kind = response.headers.get("Content-Type", "").lower().split(";")[0]
            if kind in ("application/vnd.apple.mpegurl",
                        "application/x-mpegurl", "audio/mpegurl",
                        "audio/x-mpegurl"):
                return "hls"
            if kind == "application/dash+xml":
                return "mpd"
            if kind in ("video/mp2t", "video/mpeg2"):
                return "ts"
            if kind in ("video/mp4", "video/x-matroska", "video/webm"):
                return "mp4"
            data = response.read(512).lstrip()
            if data.startswith(b"#EXTM3U"):
                return "hls"
            if data.startswith(b"<MPD") or b"<MPD " in data[:100]:
                return "mpd"
            if data and data[0] == 0x47:
                return "ts"
    except (HTTPError, URLError, OSError, TimeoutError, ValueError):
        return None
    return None


def enrich_stream_formats(rows, upstream, *, probe=probe_stream_format,
                          previous=None, now=None, max_probes=80,
                          recheck_failures=False):
    """Classify native sources incrementally without hammering NOVA's CDN.

    Probe iframe backups and unknown sports first, then other extensionless
    channels. Reuse a known format while its URL is unchanged; back off
    unsuccessful checks for two hours. This converges over periodic syncs.
    """
    now = int(time.time() if now is None else now)
    original = {str(row.get("id")): row for row in upstream
                if isinstance(row, dict)}
    cached = {str(row.get("id")): row for row in (previous or [])
              if isinstance(row, dict)}
    tasks = []
    reused = {}
    for row in rows:
        ident, url = row["id"], row["url"]
        source = original.get(str(ident)[5:]) or {}
        if source.get("is_iframe") is True:
            for backup in (row.get("backup_urls") or [])[:5]:
                tasks.append((ident, backup))
            continue
        if _url_format(url):
            continue
        old = cached.get(ident) or {}
        if old.get("url") == url:
            old_format = old.get("format")
            if old_format in ("hls", "mpd", "ts", "mp4"):
                reused[ident] = (old_format, old.get("format_probe_at"))
                continue
            try:
                last_checked = int(old.get("format_probe_at") or 0)
            except (ValueError, TypeError):
                last_checked = 0
            if last_checked > now - 7200 and not recheck_failures:
                reused[ident] = (None, last_checked)
                continue
        tasks.append((ident, url))
    # Probe iframe backups before sports and general channels, with O(1)
    # category lookups rather than scanning the 7k-row catalog per task.
    sports_ids = {row["id"] for row in rows if row.get("is_sports")}
    iframe_ids = {row["id"] for row in rows if
                  (original.get(str(row["id"])[5:]) or {}).get("is_iframe") is True}
    tasks.sort(key=lambda entry: (
        0 if entry[0] in iframe_ids else
        1 if entry[0] in sports_ids else 2
    ))
    tasks = list(dict.fromkeys(tasks))[:max(0, max_probes)]
    results = {}
    if tasks:
        with ThreadPoolExecutor(max_workers=8) as pool:
            outcomes = pool.map(lambda entry: probe(entry[1]), tasks)
            for (ident, url), result in zip(tasks, outcomes):
                if result in ("hls", "mpd", "ts", "mp4"):
                    results[(ident, url)] = result
    checked = set(tasks)
    clean = []
    dropped_iframes = 0
    for row in rows:
        item = dict(row)
        ident, url = row["id"], row["url"]
        source = original.get(str(ident)[5:]) or {}
        if source.get("is_iframe") is True:
            playable = [(backup, results[(ident, backup)])
                        for backup in (row.get("backup_urls") or [])[:5]
                        if (ident, backup) in results]
            if not playable:
                dropped_iframes += 1
                continue
            item["url"], item["format"] = playable[0]
            item["backup_urls"] = [backup for backup, _ in playable[1:]]
            item["backup_formats"] = [fmt for _, fmt in playable[1:]]
            item["format_probe_at"] = now
        elif ident in reused:
            fmt, checked_at = reused[ident]
            if fmt:
                item["format"] = fmt
            if checked_at:
                item["format_probe_at"] = checked_at
        elif (ident, url) in checked:
            fmt = results.get((ident, url))
            if fmt:
                item["format"] = fmt
            item["format_probe_at"] = now
        clean.append(item)
    return clean, {
        "format_probes": len(tasks),
        "format_identified": len(results),
        "format_cached": sum(bool(fmt) for fmt, _ in reused.values()),
        "iframe_without_native_backup": dropped_iframes,
    }


def fetch_media_pages(service, method, *, cap=500, start=0):
    """Read a bounded page window; never request an entire partner VOD feed."""
    rows = []
    for offset in range(start, start + cap, 100):
        try:
            batch = method(skip=offset, limit=min(100, start + cap - offset))
        except (NovaPartnerError, ValueError, TypeError):
            break
        if not isinstance(batch, list) or not batch:
            break
        rows.extend(batch)
        if len(batch) < 100:
            break
    return rows


def progressive_media(service, method, *, category, previous=None,
                      previous_offset=0, scan_limit=5000, batch=500):
    """Grow a VOD shelf over consecutive partner syncs, not only first 500.

    The schedule re-reads new releases on the first window of each cycle and
    continues deeper in subsequent cycles. Preserve the previous shelf during
    transient API failures; don't turn a provider outage into a catalog wipe.
    Memory and payloads are bounded so the Android catalog remains responsive.
    """
    cached = [x for x in (previous or [])
              if isinstance(x, dict) and isinstance(x.get("tmdb_id"), int)]
    start = max(0, min(int(previous_offset or 0), scan_limit))
    if start >= scan_limit:
        start = 0
    rows = fetch_media_pages(service, method,
                             cap=min(batch, scan_limit - start), start=start)
    if not rows:
        return cached[:scan_limit], (0 if start else start), 0
    fresh = normalize_media(rows, category=category)
    seen = set()
    combined = []
    for row in [*fresh, *cached]:
        ident = row["tmdb_id"]
        if ident not in seen:
            seen.add(ident)
            combined.append(row)
        if len(combined) >= scan_limit:
            break
    next_offset = start + len(rows)
    if len(rows) < min(batch, scan_limit - start) or next_offset >= scan_limit:
        next_offset = 0
    return combined, next_offset, len(rows)


def channel_guide(service, channels, *, max_channels=6000,
                  sports_only=False, workers=4):
    """Guide for every published channel with an EPG ID, not just sports.

    NOVA 1.2.9 supports batches of 40 IDs; capped concurrent requests keep
    the twice-hourly sync bounded. Never invent programs or URLs.
    """
    from datetime import timedelta

    eligible = []
    seen = set()
    for row in channels:
        if not isinstance(row, dict) or (sports_only and not row.get("is_sports")):
            continue
        raw_id, epg_id = str(row.get("id") or ""), str(row.get("epg_id") or "")
        if not raw_id.startswith("nova:") or not epg_id or epg_id in seen:
            continue
        try:
            upstream_id = int(raw_id[5:])
        except ValueError:
            continue
        if upstream_id <= 0:
            continue
        seen.add(epg_id)
        eligible.append((row, upstream_id))

    def priority(pair):
        row = pair[0]
        name = str(row.get("name") or "").lower()
        region = row.get("country") or ""
        tier = 0 if region == "MX" else 1 if region == "LATAM" else 2
        sports = 0 if any(word in name for word in (
            "espn", "tudn", "fox sports", "nfl", "nba", "claro sports",
            "dsports", "dazn",
        )) else 1
        return (tier, sports, name)

    eligible.sort(key=priority)
    eligible = eligible[:max(0, min(max_channels, 6000))]
    result = []
    now = datetime.now(timezone.utc)

    def safe_program(raw):
        if not isinstance(raw, dict):
            return None
        title = str(raw.get("title") or "").strip()[:160]
        if not title:
            return None
        start = str(raw.get("start_time") or raw.get("starts_at") or "")
        end = str(raw.get("end_time") or raw.get("ends_at") or "")
        try:
            first = datetime.fromisoformat(start.replace("Z", "+00:00"))
            last = datetime.fromisoformat(end.replace("Z", "+00:00"))
            if first.tzinfo is None or last.tzinfo is None:
                return None
            first, last = first.astimezone(timezone.utc), last.astimezone(timezone.utc)
            if not (first < last <= first + timedelta(hours=16)):
                return None
            if last < now - timedelta(hours=3) or first > now + timedelta(hours=36):
                return None
        except (ValueError, TypeError, OverflowError):
            return None
        description = str(raw.get("description") or "").strip()[:160]
        return {
            "title": title,
            "starts_at": first.isoformat(),
            "ends_at": last.isoformat(),
            **({"description": description} if description else {}),
        }

    def fetch_batch(batch):
        try:
            responses = service.sports_now_next([up_id for _, up_id in batch])
        except (NovaPartnerError, ValueError, TypeError):
            # EPG is supplementary; an absent provider must not take TV down.
            return []
        by_id = {str(upstream_id): row for row, upstream_id in batch}
        clean = []
        for raw in responses:
            if not isinstance(raw, dict):
                continue
            row = by_id.get(str(raw.get("channel_id") or ""))
            if row is None:
                continue
            current = safe_program(raw.get("now"))
            next_program = safe_program(raw.get("next"))
            if not current and not next_program:
                continue
            clean.append({
                "channel_id": str(row["epg_id"]),
                **({"now": current} if current else {}),
                **({"next": next_program} if next_program else {}),
            })
        return clean

    batches = [eligible[i:i + 40] for i in range(0,len(eligible),40)]
    if not batches:
        return []
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=max(1,min(workers,4))) as pool:
        for rows in pool.map(fetch_batch,batches):
            result.extend(rows)
    return result


def sports_guide(service, channels, *, max_channels=160):
    """Compatibility wrapper for sports-only clients and tests."""
    return channel_guide(service, channels,
                         max_channels=max_channels, sports_only=True)


def all_channel_guide(service, channels, *, max_channels=6000):
    return channel_guide(service, channels,max_channels=max_channels)



def retain_recent_guide(fresh, previous, channels, *, now=None):
    """Keep still-valid EPG entries for at most 45 minutes during partial outages.

    Only channel IDs still present in the new authorized snapshot are eligible.
    Revalidate cached dates and copy only public EPG fields, never stream URLs.
    A missing/old timestamp fails closed instead of displaying stale schedules.
    """
    from datetime import timedelta

    now = now or datetime.now(timezone.utc)
    allowed = {str(row.get("epg_id") or "") for row in channels
               if isinstance(row, dict) and row.get("epg_id")}
    # Validate fresh provider metadata as rigorously as cached EPG. A stale
    # "now" from an upstream outage must not hide a still-valid cached entry,
    # and a fresh response must never carry a playback URL into the guide.

    def recent(channel_id):
        # A snapshot can be rewritten every 30 minutes with cached entries.
        # Per-channel source timestamps prevent that from extending their TTL.
        stamp_text = previous_seen_at.get(
            channel_id, previous.get("updated_at"))
        try:
            stamp = datetime.fromisoformat(
                str(stamp_text or "").replace("Z", "+00:00"))
            if stamp.tzinfo is None:
                return False
            age = now - stamp.astimezone(timezone.utc)
            return -timedelta(minutes=2) <= age <= timedelta(minutes=45)
        except (ValueError, TypeError, OverflowError):
            return False

    def valid_program(value):
        if not isinstance(value, dict):
            return None
        title = str(value.get("title") or "").strip()[:160]
        try:
            start = datetime.fromisoformat(
                str(value.get("starts_at") or "").replace("Z", "+00:00"))
            end = datetime.fromisoformat(
                str(value.get("ends_at") or "").replace("Z", "+00:00"))
            if start.tzinfo is None or end.tzinfo is None:
                return None
            start, end = start.astimezone(timezone.utc), end.astimezone(timezone.utc)
            if not title or not (start < end <= start + timedelta(hours=16)):
                return None
            if end <= now or start > now + timedelta(hours=36):
                return None
        except (ValueError, TypeError, OverflowError):
            return None
        description = str(value.get("description") or "").strip()[:160]
        return {"title": title, "starts_at": start.isoformat(),
                "ends_at": end.isoformat(),
                **({"description": description} if description else {})}

    result = []
    seen = set()
    for row in fresh:
        if not isinstance(row, dict):
            continue
        channel_id = str(row.get("channel_id") or "")
        if channel_id not in allowed or channel_id in seen:
            continue
        current = valid_program(row.get("now"))
        next_program = valid_program(row.get("next"))
        if not current and not next_program:
            continue
        result.append({"channel_id": channel_id,
                       **({"now": current} if current else {}),
                       **({"next": next_program} if next_program else {})})
        seen.add(channel_id)
    if not isinstance(previous, dict):
        return result
    previous_seen_at = previous.get("guide_seen_at")
    if not isinstance(previous_seen_at, dict):
        previous_seen_at = {}

    old_guide = previous.get("now_next")
    if not isinstance(old_guide, list):
        return result
    for row in old_guide:
        if not isinstance(row, dict):
            continue
        channel_id = str(row.get("channel_id") or "")
        if channel_id not in allowed or channel_id in seen or not recent(channel_id):
            continue
        current = valid_program(row.get("now"))
        next_program = valid_program(row.get("next"))
        if not current and not next_program:
            continue
        result.append({"channel_id": channel_id,
                       **({"now": current} if current else {}),
                       **({"next": next_program} if next_program else {})})
        seen.add(channel_id)
    return result


def snapshot_revision(channels, movies, series, anime, guide=()):
    """Change revision when media titles/IDs change, not only TV channels.

    Ignore transient sync timestamps so AniList incremental mapping produces
    one stable revision per distinct subscriber-visible catalog.
    """
    material = {
        "channels": sorted((
            r["id"], r["url"], r.get("format"), r.get("backup_urls")
        ) for r in channels),
        "movies": sorted(movies, key=lambda r: r["tmdb_id"]),
        "series": sorted(series, key=lambda r: r["tmdb_id"]),
        "anime": sorted(anime, key=lambda r: r["anilist_id"]),
        "guide": sorted(guide, key=lambda r: str(r.get("channel_id") or "")),
    }
    return hashlib.sha256(json.dumps(material, sort_keys=True,
        separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()[:20]


def write_media_index(destination, snapshot):
    """Atomically publish a compact, private VOD page index for the API.

    Avoid loading the full ~10 MB NOVA JSON on each Android page request;
    the POTV API process has a strict 128 MiB memory limit.
    """
    target = Path(str(destination) + ".media.sqlite3")
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".nova-media-", dir=target.parent)
    os.close(descriptor)
    try:
        os.chmod(temporary, 0o600)
        with closing(sqlite3.connect(temporary)) as db:
            db.execute("CREATE TABLE media (kind TEXT NOT NULL, position INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY (kind, position))")
            db.execute("CREATE TABLE meta (kind TEXT PRIMARY KEY, revision TEXT NOT NULL, total INTEGER NOT NULL)")
            for kind in ("movies", "series", "anime"):
                rows = snapshot.get(kind) or []
                rows = ([row for row in rows if isinstance(row, dict)]
                        if isinstance(rows, list) else [])
                db.executemany(
                    "INSERT INTO media(kind, position, payload) VALUES(?,?,?)",
                    ((kind, i, json.dumps(row, ensure_ascii=False, separators=(",", ":")))
                     for i, row in enumerate(rows)),
                )
                db.execute("INSERT INTO meta(kind, revision, total) VALUES(?,?,?)",
                           (kind, str(snapshot.get("revision") or ""), len(rows)))
            db.commit()
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.remove(temporary)


def synchronize(*, service, destination, limit=4500, anime_map_file=None):
    channels = service.channels()
    rows, counts = normalize_channels(channels, limit=limit)
    destination = Path(destination)
    previous = []
    old_snapshot = {}
    previous_probe_version = 0
    try:
        if destination.stat().st_size < 12 * 1024 * 1024:
            old = json.loads(destination.read_text(encoding="utf-8"))
            if isinstance(old, dict):
                old_snapshot = old
            if isinstance(old.get("channels"), list):
                previous = old["channels"]
            previous_probe_version = int(old.get("format_probe_version") or 0)
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    rows, format_counts = enrich_stream_formats(
        rows, channels, previous=previous,
        recheck_failures=previous_probe_version != 2,
    )
    counts.update(format_counts)
    if not rows:
        raise NovaPartnerError("empty_channel_snapshot")
    version = {}
    try:
        upstream = service.app_version()
        if isinstance(upstream, dict):
            version = {
                key: str(upstream[key])[:64]
                for key in ("latest_version_code", "latest_version_name", "min_version_code")
                if upstream.get(key) is not None
            }
    except (NovaPartnerError, ValueError, TypeError):
        pass
    old_offsets = old_snapshot.get("media_scan_offsets") or {}
    if not isinstance(old_offsets, dict):
        old_offsets = {}
    movies, movies_offset, movie_received = progressive_media(
        service, service.movies, category="movie",
        previous=old_snapshot.get("movies"),
        previous_offset=old_offsets.get("movies", 0),
    )
    series, series_offset, series_received = progressive_media(
        service, service.series, category="series",
        previous=old_snapshot.get("series"),
        previous_offset=old_offsets.get("series", 0),
    )
    anime = []
    if anime_map_file:
        # Preserve mapped AniList IDs during a temporary partner/API outage.
        # Never use provider TMDb IDs as AniList IDs.
        old_anime = old_snapshot.get("anime")
        if isinstance(old_anime, list):
            anime = [row for row in old_anime if isinstance(row, dict)
                     and isinstance(row.get("anilist_id"), int)
                     and not isinstance(row["anilist_id"], bool)
                     and row["anilist_id"] > 0]
        try:
            anime_rows = fetch_media_pages(service, service.anime)
            anime_map, _ = refresh_cache(anime_rows, anime_map_file)
            anime = normalize_anime(anime_rows, anime_map)
        except (NovaPartnerError, OSError, ValueError, TypeError):
            # Do not wipe the previous valid anime shelf on transient errors.
            pass
    fresh_guide = all_channel_guide(service, rows)
    guide = retain_recent_guide(fresh_guide, old_snapshot, rows)
    now_stamp = datetime.now(timezone.utc).isoformat()
    old_seen_at = old_snapshot.get("guide_seen_at")
    if not isinstance(old_seen_at, dict):
        old_seen_at = {}
    fresh_ids = {str(row.get("channel_id") or "") for row in fresh_guide}
    guide_seen_at = {
        str(row["channel_id"]): (
            now_stamp if str(row["channel_id"]) in fresh_ids
            else old_seen_at.get(str(row["channel_id"]),
                                 old_snapshot.get("updated_at") or ""))
        for row in guide
    }
    body = {
        "source": "nova",
        "format_probe_version": 2,
        "movies": movies,
        "series": series,
        "media_scan_offsets": {"movies": movies_offset,
                               "series": series_offset},
        "anime": anime,
        "now_next": guide,
        "guide_seen_at": guide_seen_at,
        "upstream_app_version": version,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "revision": snapshot_revision(rows, movies, series, anime, guide),
        "channels": rows,
    }
    destination = Path(destination)
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor, temp_path = tempfile.mkstemp(prefix=".nova-sync-", dir=destination.parent)
    try:
        os.chmod(temp_path, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as fh:
            json.dump(body, fh, ensure_ascii=False, separators=(",", ":"))
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(temp_path, destination)
        write_media_index(destination, body)
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)
    return {
        "received": len(channels),
        "published_for_subscribers": len(rows),
        "movie_catalog_sample": len(movies),
        "series_catalog_sample": len(series),
        "movie_page_received": movie_received,
        "series_page_received": series_received,
        "anime_catalog_mapped": len(anime),
        "guide_channels": len(guide),
        **counts,
        "revision": body["revision"],
    }


def main():
    service_file = os.getenv("POTV_NOVA_SERVICE_FILE", "").strip()
    output_file = os.getenv("POTV_NOVA_SYNC_FILE", "").strip()
    if not service_file or not output_file:
        raise SystemExit("NOVA synchronization disabled: provider config / local snapshot path missing")
    service = NovaPartner.from_file(service_file)
    limit = max(100, min(7000, int(os.getenv("POTV_NOVA_CHANNEL_LIMIT", "4500"))))
    try:
        summary = synchronize(service=service, destination=output_file, limit=limit,
                              anime_map_file=os.getenv("POTV_NOVA_ANIME_MAP_FILE") or None)
        origin = "primary"
    except NovaPartnerError as exc:
        if exc.code == "upstream_denied":
            raise
        settings = json.loads(Path(service_file).read_text(encoding="utf-8"))
        backup = settings.get("backup_api_base_url") or ""
        if not backup:
            raise
        # Independently authorized backup host: do not retry a denial.
        service = NovaPartner(
            base_url=backup,
            access_token=settings.get("service_access_token") or "",
            allow_anonymous_catalog=settings.get("allow_anonymous_catalog") is True,
        )
        summary = synchronize(service=service,destination=output_file,limit=limit,
                              anime_map_file=os.getenv("POTV_NOVA_ANIME_MAP_FILE") or None)
        origin = "backup"
    summary["feed"] = origin
    # Counts only: upstream and snapshot URLs are sensitive.
    print("NOVA SYNC:", json.dumps(summary))


if __name__ == "__main__":
    main()
