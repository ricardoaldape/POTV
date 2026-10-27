"""Refresh authorized NOVA TV content into a private POTV-only snapshot.

Fetches a public, partner-authorized catalog or a provider-issued service
account; never places upstream stream URLs into a public endpoint.
"""
import hashlib
import json
import os
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


class _NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def probe_stream_format(url):
    """Bounded content sniff; no redirects or access to nonpublic addresses.

    Never log upstream URLs, response bodies or authorization information.
    A failed probe is *not* evidence that the provider is unlicensed.
    """
    value = _stream_url(url)
    if not value:
        return None
    host = urlsplit(value).hostname
    try:
        addresses = socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
        if not addresses or any(
            not ipaddress.ip_address(entry[4][0]).is_global
            for entry in addresses
        ):
            return None
    except (OSError, ValueError, TypeError):
        return None
    try:
        req = Request(value, headers={
            "User-Agent": "POTV-Authorized-Stream-Check/1.0",
            "Range": "bytes=0-511",
            "Accept": "*/*",
        })
        with build_opener(_NoRedirect()).open(req, timeout=3) as response:
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
                          previous=None, now=None, max_probes=80):
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
            if last_checked > now - 7200:
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


def fetch_media_pages(service, method, *, cap=500):
    rows=[]
    for offset in range(0, cap, 100):
        try:
            batch=method(skip=offset,limit=min(100,cap-offset))
        except (NovaPartnerError,ValueError,TypeError):
            break
        if not isinstance(batch,list) or not batch:
            break
        rows.extend(batch)
        if len(batch)<100:
            break
    return rows


def synchronize(*, service, destination, limit=4500, anime_map_file=None):
    channels = service.channels()
    rows, counts = normalize_channels(channels, limit=limit)
    destination = Path(destination)
    previous = []
    try:
        if destination.stat().st_size < 12 * 1024 * 1024:
            old = json.loads(destination.read_text(encoding="utf-8"))
            if isinstance(old.get("channels"), list):
                previous = old["channels"]
    except (OSError, ValueError, TypeError, AttributeError):
        pass
    rows, format_counts = enrich_stream_formats(
        rows, channels, previous=previous
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
    movies = normalize_media(
        fetch_media_pages(service, service.movies), category="movie"
    )
    series = normalize_media(
        fetch_media_pages(service, service.series), category="series"
    )
    anime = []
    if anime_map_file:
        # AniList is the canonical anime identifier in POTV. A provider TMDb
        # ID must never be sent to the Android anime UI as an AniList ID.
        try:
            anime_rows = fetch_media_pages(service, service.anime)
            anime_map, _ = refresh_cache(anime_rows, anime_map_file)
            anime = normalize_anime(anime_rows, anime_map)
        except (NovaPartnerError, OSError, ValueError, TypeError):
            # Keep TV, movies and series synchronized if AniList is down.
            pass
    body = {
        "source": "nova",
        "movies": movies,
        "series": series,
        "anime": anime,
        "upstream_app_version": version,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "revision": hashlib.sha256(json.dumps(
            [(r["id"], r["url"], r.get("format"),
              r.get("backup_urls")) for r in rows], separators=(",", ":")
        ).encode()).hexdigest()[:20],
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
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)
    return {
        "received": len(channels),
        "published_for_subscribers": len(rows),
        "movie_catalog_sample": len(movies),
        "series_catalog_sample": len(series),
        "anime_catalog_mapped": len(anime),
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
