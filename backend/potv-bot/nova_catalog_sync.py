"""Refresh authorized NOVA TV content into a private POTV-only snapshot.

Fetches a public, partner-authorized catalog or a provider-issued service
account; never places upstream stream URLs into a public endpoint.
"""
import hashlib
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

from nova_partner import NovaPartner, NovaPartnerError


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


def synchronize(*, service, destination, limit=4500):
    channels = service.channels()
    rows, counts = normalize_channels(channels, limit=limit)
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
    body = {
        "source": "nova",
        "movies": movies,
        "series": series,
        "upstream_app_version": version,
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "revision": hashlib.sha256(json.dumps(
            [(r["id"], r["url"]) for r in rows], separators=(",", ":")
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
        summary = synchronize(service=service, destination=output_file, limit=limit)
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
        summary = synchronize(service=service,destination=output_file,limit=limit)
        origin = "backup"
    summary["feed"] = origin
    # Counts only: upstream and snapshot URLs are sensitive.
    print("NOVA SYNC:", json.dumps(summary))


if __name__ == "__main__":
    main()
