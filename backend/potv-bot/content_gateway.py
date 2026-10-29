#!/usr/bin/env python3
"""Authorized POTV content gateway.

Partner source URLs and credentials are loaded only from protected server
configuration. The Flutter client receives opaque, short-lived HTTPS proxy
URLs and never receives the upstream credentials.
"""
import base64
import copy
import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import sqlite3
from contextlib import closing
import threading
import time
import unicodedata
from datetime import datetime, timedelta, timezone
from http.cookiejar import CookieJar
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, unquote, urlencode, urljoin, urlsplit, urlunsplit
from urllib.request import (
    HTTPCookieProcessor,
    HTTPRedirectHandler,
    Request,
    build_opener,
)

from lmhd_partner import LmhdPartner, LmhdLoginPartner, PartnerApiError
from partner_lmhd_api import PartnerAccessError
from nova_partner import NovaPartner, NovaPartnerError
from nova_snapshot_limits import MAX_NOVA_SNAPSHOT_BYTES

_EXTINF_ATTR = re.compile(r'([A-Za-z0-9_-]+)="([^"]*)"')
_HLS_URI_ATTR = re.compile(r'URI="([^"]+)"')
_SPORTS = re.compile(
    r'(?i)\b(sport|deport|futbol|fútbol|soccer|football|nfl|nba|mlb|'
    r'baseball|beisbol|béisbol|basket|tenis|tennis|formula|f1|motor|'
    r'boxing|boxeo|mma|ufc|wrestling|lucha|golf|hockey|espn|tudn|'
    r'fox sports|dazn)\b'
)


class ContentGatewayError(Exception):
    def __init__(self, status, code):
        super().__init__(code)
        self.status = int(status)
        self.code = str(code)




class _SafeUpstreamRedirect(HTTPRedirectHandler):
    """Allow CDN redirects, never redirect media fetches to local services.

    Initial URLs are checked by ContentGateway._allowed_upstream, but urllib
    otherwise follows Location headers without checking their destinations.
    """

    def __init__(self, allow_url):
        self._allow_url = allow_url

    def redirect_request(self, request, fp, code, msg, headers, newurl):
        destination = urlsplit(newurl)
        source = urlsplit(request.full_url)
        if (
            not self._allow_url(newurl)
            or destination.username is not None
            or destination.password is not None
            or (source.scheme == "https" and destination.scheme != "https")
        ):
            raise ContentGatewayError(400, "upstream_not_allowed")
        redirected = super().redirect_request(
            request, fp, code, msg, headers, newurl
        )
        if redirected is not None:
            # A redirect to another CDN must not receive origin credentials.
            for key in tuple(redirected.headers):
                if key.lower() in (
                    "authorization", "proxy-authorization", "cookie",
                    "x-api-key",
                ):
                    del redirected.headers[key]
        return redirected


def _load_source_urls():
    urls = []
    source_file = os.getenv("POTV_CONTENT_SOURCES_FILE", "").strip()
    source_json = os.getenv("POTV_CONTENT_SOURCES_JSON", "").strip()

    if source_file:
        try:
            with open(source_file, "r", encoding="utf-8") as fh:
                raw = fh.read().strip()
            if raw.startswith("["):
                values = json.loads(raw)
                if isinstance(values, list):
                    urls.extend(str(value).strip() for value in values)
            else:
                for line in raw.splitlines():
                    line = line.strip()
                    if line and not line.startswith("#"):
                        urls.append(line)
        except (OSError, ValueError):
            pass

    if source_json:
        try:
            values = json.loads(source_json)
            if isinstance(values, list):
                urls.extend(str(value).strip() for value in values)
        except ValueError:
            pass

    result = []
    seen = set()
    for value in urls:
        if value and value not in seen:
            seen.add(value)
            result.append(value)
    return result


class ContentGateway:
    def __init__(
        self,
        *,
        sources=None,
        public_base=None,
        signing_secret=None,
        refresh_seconds=None,
        opener=None,
        metadata_file=None,
        source_mode=None,
    ):
        self.sources = list(_load_source_urls() if sources is None else sources)
        self.public_base = (
            public_base
            or os.getenv("POTV_PUBLIC_BASE_URL", "https://potv.fxqubit.com")
        ).rstrip("/")
        secret = (
            signing_secret
            or os.getenv("POTV_CONTENT_SIGNING_SECRET", "").encode("utf-8")
        )
        self.secret = secret if isinstance(secret, bytes) and secret else secrets.token_bytes(32)
        self.source_mode = (
            source_mode
            or os.getenv("POTV_CONTENT_SOURCE_MODE", "merge")
        ).strip().lower()
        raw_category_ids = os.getenv("POTV_CONTENT_LIVE_CATEGORY_IDS", "").strip()
        self.live_category_ids = {
            value.strip()
            for value in raw_category_ids.split(",")
            if value.strip()
        }
        if self.source_mode not in ("merge", "failover"):
            self.source_mode = "merge"
        # TV catalogs can be combined even when VOD sources use first-working
        # failover. This is deliberately opt-in for existing deployments.
        self.live_source_mode = os.getenv(
            "POTV_CONTENT_LIVE_SOURCE_MODE", self.source_mode
        ).strip().lower()
        if self.live_source_mode not in ("merge", "failover"):
            self.live_source_mode = self.source_mode
        self.refresh_seconds = int(
            refresh_seconds
            if refresh_seconds is not None
            else os.getenv("POTV_CONTENT_REFRESH_SECONDS", "120")
        )
        self.metadata_file = (
            metadata_file
            if metadata_file is not None
            else os.getenv("POTV_CONTENT_METADATA_FILE", "").strip()
        )
        # Optional authorized provider service config, stored ONLY on the VPS
        # (or supplied as a test fixture). Never load APK-embedded sessions.
        # Keep existing Xtream/M3U streams working if a partner configuration
        # is absent or temporarily invalid.
        self.lmhd = None
        lmhd_file = os.getenv("POTV_LMHD_SERVICE_FILE", "").strip()
        if lmhd_file:
            try:
                self.lmhd = LmhdPartner.from_file(lmhd_file)
            except (OSError, ValueError, KeyError, TypeError):
                self.lmhd = None
        if self.lmhd is None and not lmhd_file:
            # A dedicated LMHD service username/password may be issued in
            # place of a static session token. This uses the normal login API
            # with in-memory token refresh. Partial env config fails closed.
            try:
                self.lmhd = LmhdLoginPartner.from_environment()
            except (PartnerAccessError, ValueError, TypeError):
                self.lmhd = None
        # Private synchronizer publishes atomically; never expose raw upstream
        # media entries to an anonymous catalog or unentitled account.
        self.lmhd_sync_file = os.getenv("POTV_LMHD_SYNC_FILE", "").strip()
        self.lmhd_live_catalog_enabled = (
            os.getenv("POTV_LMHD_INCLUDE_LIVE_CATALOG", "").strip().lower()
            == "true"
        )
        # Both paid catalog and paid VOD remain explicitly disabled until
        # POTV's entitlement checks authorize the requesting customer.
        self.lmhd_vod_enabled = (
            os.getenv("POTV_LMHD_VOD_ENABLED", "").strip().lower() == "true"
        )
        # Enabling NOVA requires a separate provider-issued service account.
        # Paid resolution is never published by the public content catalog.
        self.nova = None
        nova_file = os.getenv("POTV_NOVA_SERVICE_FILE", "").strip()
        if nova_file:
            try:
                self.nova = NovaPartner.from_file(nova_file)
            except (OSError, ValueError, TypeError):
                self.nova = None
        self.nova_vod_enabled = (
            self.nova is not None
            and os.getenv("POTV_NOVA_VOD_ENABLED", "").strip().lower() == "true"
        )
        # AirTV Firestore is a separately licensed, opt-in subscriber source.
        # A root-owned sync process polls the provider and publishes a
        # private snapshot, never its Google account into the Android app.
        self.airtv_sync_file = os.getenv("POTV_AIRTV_SYNC_FILE", "").strip()
        self.airtv_live_enabled = (
            bool(self.airtv_sync_file)
            and os.getenv("POTV_AIRTV_LIVE_ENABLED", "").strip().lower() == "true"
        )
        self.nova_sync_file = os.getenv("POTV_NOVA_SYNC_FILE", "").strip()
        self.nova_live_enabled = (
            self.nova is not None
            and bool(self.nova_sync_file)
            and os.getenv("POTV_NOVA_LIVE_ENABLED", "").strip().lower() == "true"
        )
        self._nova_subscriber_catalog = None
        self._nova_subscriber_catalog_at = 0.0
        self._nova_subscriber_revision = None
        self.opener = opener or build_opener(
            HTTPCookieProcessor(CookieJar()),
            _SafeUpstreamRedirect(self._allowed_upstream),
        )
        self._lock = threading.RLock()
        # A cold-start stream URL may have been signed before the API
        # restarted. Rehydrate public and private targets ONCE rather than
        # rebuilding both huge catalogs in every concurrent request thread.
        self._hydrate_lock = threading.Lock()
        self._last_full_target_hydrate = 0.0
        self._targets = {}
        # HLS segments create ephemeral signed targets. Keep memory bounded
        # without interrupting already-started media transfers.
        self._target_last_signed = {}
        self._new_target_counter = 0
        self._catalog = None
        self._catalog_at = 0.0
        self._catalog_refreshing = False
        self._xtream_unreachable_until = {}
        self._xtream_cache = {}
        self._m3u_cache = {}
        self._sports_guide_cache = []
        self._sports_guide_at = 0.0
        self._sports_guide_refreshing = False

    @property
    def configured(self):
        return bool(self.sources) or self.lmhd is not None or self.airtv_live_enabled

    def _allowed_upstream(self, raw):
        try:
            uri = urlsplit(str(raw).strip())
        except Exception:
            return False
        if uri.scheme not in ("http", "https") or not uri.hostname:
            return False
        host = uri.hostname.lower()
        if host in ("localhost", "localhost.localdomain") or host.endswith(".local"):
            return False
        try:
            ip = ipaddress.ip_address(host.strip("[]"))
            # Includes CGNAT (100.64/10), private, link-local, loopback,
            # documentation and reserved IP ranges, IPv4 and IPv6.
            if not ip.is_global:
                return False
        except ValueError:
            pass
        return True

    def _fetch(self, url, *, headers=None, timeout=18):
        if not self._allowed_upstream(url):
            raise ContentGatewayError(400, "upstream_not_allowed")
        request_headers = {
            "User-Agent": "POTV-Gateway/1.0",
            "Accept": "*/*",
        }
        request_headers.update(headers or {})
        req = Request(url, headers=request_headers)
        return self.opener.open(req, timeout=timeout)

    def _xtream_config(self, source):
        try:
            uri = urlsplit(str(source).strip())
            query = parse_qs(uri.query)
            username = (query.get("username") or [""])[0].strip()
            password = (query.get("password") or [""])[0].strip()
            if (
                uri.scheme not in ("http", "https")
                or not uri.netloc
                or not username
                or not password
            ):
                return None
            base = urlunsplit((uri.scheme, uri.netloc, "", "", "")).rstrip("/")
            return {
                "base": base,
                "username": username,
                "password": password,
            }
        except Exception:
            return None

    def _fetch_json(self, url, *, timeout=25):
        with self._fetch(url, timeout=timeout) as response:
            raw = response.read(32 * 1024 * 1024 + 1)
        if len(raw) > 32 * 1024 * 1024:
            raise ContentGatewayError(413, "source_too_large")
        try:
            return json.loads(raw.decode("utf-8", errors="replace"))
        except ValueError as exc:
            raise ContentGatewayError(422, "invalid_partner_json") from exc

    def _xtream_json(self, source, action, *, extra=None, ttl=300):
        config = self._xtream_config(source)
        if config is None:
            raise ContentGatewayError(422, "not_xtream_source")
        cache_key = (source, action, json.dumps(extra or {}, sort_keys=True))
        now = time.monotonic()
        cached = self._xtream_cache.get(cache_key)
        if cached and now - cached[0] < ttl:
            return cached[1]

        # A temporarily unreachable partner must not stall every VOD request.
        if now < self._xtream_unreachable_until.get(source, 0):
            raise ContentGatewayError(503, "partner_temporarily_unreachable")
        query = {
            "username": config["username"],
            "password": config["password"],
            "action": action,
        }
        query.update(extra or {})
        url = config["base"] + "/player_api.php?" + urlencode(query)
        try:
            data = self._fetch_json(url, timeout=6)
        except (OSError, TimeoutError, HTTPError, URLError):
            self._xtream_unreachable_until[source] = time.monotonic() + 90
            raise
        self._xtream_unreachable_until.pop(source, None)
        self._xtream_cache[cache_key] = (now, data)
        return data

    def _category_map(self, source, action):
        raw = self._xtream_json(source, action, ttl=600)
        result = {}
        if isinstance(raw, list):
            for row in raw:
                if not isinstance(row, dict):
                    continue
                category_id = str(row.get("category_id") or "").strip()
                name = str(row.get("category_name") or "").strip()
                if category_id and name:
                    result[category_id] = name
        return result

    def _xtream_stream_url(self, source, kind, stream_id, extension):
        config = self._xtream_config(source)
        if config is None:
            raise ContentGatewayError(422, "not_xtream_source")
        stream_id = str(stream_id or "").strip()
        extension = re.sub(r"[^A-Za-z0-9]+", "", str(extension or "")).lower()
        if not stream_id:
            raise ContentGatewayError(422, "missing_stream_id")
        if kind == "live":
            extension = extension or "ts"
        elif kind in ("movie", "series"):
            extension = extension or "mp4"
        else:
            raise ContentGatewayError(422, "invalid_stream_kind")
        return (
            f"{config['base']}/{kind}/"
            f"{quote(config['username'], safe='')}/"
            f"{quote(config['password'], safe='')}/"
            f"{quote(stream_id, safe='')}.{extension}"
        )

    def _xtream_live_channels(self, source):
        categories = self._category_map(source, "get_live_categories")
        raw = self._xtream_json(source, "get_live_streams", ttl=180)
        if not isinstance(raw, list):
            return []

        # Some Xtream providers expose player_api.php on one hostname while
        # their generated M3U points each live stream at a different CDN.
        # Prefer the provider's own M3U URL for playback and use the API only
        # for taxonomy/EPG metadata.
        m3u_by_stream = {}
        try:
            for item in self._m3u_inventory(source)["live"]:
                path = urlsplit(str(item.get("url") or "")).path.rstrip("/")
                tail = path.rsplit("/", 1)[-1]
                stream_id = tail.split(".", 1)[0]
                if stream_id.isdigit() and stream_id not in m3u_by_stream:
                    m3u_by_stream[stream_id] = item
        except Exception:
            m3u_by_stream = {}

        channels = []
        for row in raw:
            if not isinstance(row, dict):
                continue
            name = str(row.get("name") or "").strip()
            category_id = str(row.get("category_id") or "").strip()
            group = categories.get(category_id, "")
            if self.live_category_ids and category_id not in self.live_category_ids:
                continue
            if (
                not name
                or self._is_promotional_name(name)
                or self._is_adult_entry(name, group)
                or self._is_stale_scheduled_entry(name, group)
            ):
                continue
            stream_id = str(row.get("stream_id") or "").strip()
            m3u_item = m3u_by_stream.get(stream_id)
            direct = str(row.get("direct_source") or "").strip()
            if m3u_item is not None and self._allowed_upstream(m3u_item.get("url")):
                url = m3u_item["url"]
                headers = dict(m3u_item.get("headers") or {})
            elif direct and self._allowed_upstream(direct):
                url = direct
                headers = {}
            else:
                try:
                    url = self._xtream_stream_url(
                        source,
                        "live",
                        row.get("stream_id"),
                        row.get("container_extension") or "ts",
                    )
                    headers = {}
                except ContentGatewayError:
                    continue
            channels.append({
                "name": name,
                "url": url,
                "group": group or (m3u_item or {}).get("group", ""),
                "epg_id": str(
                    row.get("epg_channel_id")
                    or (m3u_item or {}).get("epg_id")
                    or ""
                ).strip(),
                "logo": str(
                    row.get("stream_icon")
                    or (m3u_item or {}).get("logo")
                    or ""
                ).strip(),
                "language": str((m3u_item or {}).get("language") or ""),
                "headers": headers,
                "stream_id": row.get("stream_id"),
            })
        return channels

    def _decode_epg_text(self, value):
        raw = str(value or "").strip()
        if not raw:
            return ""
        try:
            padded = raw + "=" * ((4 - len(raw) % 4) % 4)
            decoded = base64.b64decode(padded, validate=True).decode("utf-8")
            if decoded and sum(char.isprintable() for char in decoded) / len(decoded) > 0.9:
                return decoded.strip()
        except Exception:
            pass
        return raw

    def _epg_slot(self, row):
        if not isinstance(row, dict):
            return None
        title = self._decode_epg_text(row.get("title"))
        description = self._decode_epg_text(row.get("description"))
        try:
            start_ts = int(row.get("start_timestamp") or 0)
            end_ts = int(row.get("stop_timestamp") or 0)
        except (TypeError, ValueError):
            start_ts = 0
            end_ts = 0
        if start_ts <= 0 or end_ts <= start_ts:
            try:
                start = datetime.strptime(
                    str(row.get("start") or ""),
                    "%Y-%m-%d %H:%M:%S",
                ).replace(tzinfo=timezone.utc)
                end = datetime.strptime(
                    str(row.get("end") or ""),
                    "%Y-%m-%d %H:%M:%S",
                ).replace(tzinfo=timezone.utc)
                start_ts = int(start.timestamp())
                end_ts = int(end.timestamp())
            except (TypeError, ValueError):
                return None
        if not title:
            return None
        return {
            "title": title,
            "starts_at": datetime.fromtimestamp(
                start_ts, timezone.utc
            ).isoformat(),
            "ends_at": datetime.fromtimestamp(
                end_ts, timezone.utc
            ).isoformat(),
            **({"description": description} if description else {}),
            "_start_ts": start_ts,
            "_end_ts": end_ts,
        }

    def _xtream_sports_guide(self, source, channels, limit=24):
        candidates = [
            channel
            for channel in channels
            if channel.get("stream_id")
            and _SPORTS.search(
                f"{channel.get('name', '')} {channel.get('group', '')}"
            )
        ]
        candidates.sort(
            key=lambda item: (
                0 if str(item.get("epg_id") or "").strip() else 1,
                str(item.get("name") or "").lower(),
            )
        )
        now = int(time.time())
        guide = []
        for channel in candidates[:limit]:
            try:
                document = self._xtream_json(
                    source,
                    "get_short_epg",
                    extra={
                        "stream_id": channel.get("stream_id"),
                        "limit": 12,
                    },
                    ttl=60,
                )
            except Exception:
                continue
            listings = (
                document.get("epg_listings")
                if isinstance(document, dict)
                else None
            )
            if not isinstance(listings, list):
                continue
            slots = [
                slot
                for slot in (self._epg_slot(row) for row in listings)
                if slot is not None
            ]
            slots.sort(key=lambda item: item["_start_ts"])
            current = next(
                (
                    slot
                    for slot in slots
                    if slot["_start_ts"] <= now < slot["_end_ts"]
                ),
                None,
            )
            upcoming = next(
                (slot for slot in slots if slot["_start_ts"] > now),
                None,
            )
            if current is None and upcoming is None:
                continue
            channel_id = str(
                channel.get("epg_id") or channel.get("name") or ""
            ).strip()
            if not channel_id:
                continue
            row = {"channel_id": channel_id}
            if current is not None:
                row["current"] = {
                    key: value
                    for key, value in current.items()
                    if not key.startswith("_")
                }
            if upcoming is not None:
                row["next"] = {
                    key: value
                    for key, value in upcoming.items()
                    if not key.startswith("_")
                }
            guide.append(row)
        return guide

    def _schedule_sports_guide(self, source, channels):
        now = time.monotonic()
        with self._lock:
            if self._sports_guide_refreshing:
                return
            if now - self._sports_guide_at < 60:
                return
            self._sports_guide_refreshing = True

        def worker():
            try:
                guide = self._xtream_sports_guide(source, channels)
            except Exception:
                guide = []
            with self._lock:
                self._sports_guide_cache = guide
                self._sports_guide_at = time.monotonic()
                self._sports_guide_refreshing = False
                if self._catalog is not None:
                    metadata = self._guide_payload(self._metadata())
                    self._catalog["data"]["now_next"] = [
                        *metadata,
                        *guide,
                    ]

        threading.Thread(
            target=worker,
            name="potv-sports-guide",
            daemon=True,
        ).start()

    def _normalize_title(self, value):
        text = str(value or "").lower().strip()
        text = re.sub(r"\([^)]*(?:19|20)\d{2}[^)]*\)", " ", text)
        text = re.sub(r"\b(?:19|20)\d{2}\b", " ", text)
        text = re.sub(r"[^a-z0-9]+", " ", text)
        return re.sub(r"\s+", " ", text).strip()

    def _year_text(self, row):
        for key in ("year", "releaseDate", "release_date", "releasedate"):
            value = str(row.get(key) or "").strip()
            match = re.search(r"(19|20)\d{2}", value)
            if match:
                return match.group(0)
        return ""

    def _match_xtream_item(self, rows, *, tmdb_id=None, title=None, year=None, categories=None):
        if not isinstance(rows, list):
            return None
        target_title = self._normalize_title(title)
        target_year = str(year or "").strip()
        target_tmdb = str(tmdb_id or "").strip()

        exact_title = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            name = str(row.get("name") or row.get("title") or "").strip()
            group = ""
            if categories is not None:
                group = categories.get(str(row.get("category_id") or "").strip(), "")
            if self._is_adult_entry(name, group) or self._is_promotional_name(name):
                continue

            provider_tmdb = str(
                row.get("tmdb") or row.get("tmdb_id") or row.get("tmdbId") or ""
            ).strip()
            if target_tmdb and provider_tmdb and provider_tmdb == target_tmdb:
                return row

            if target_title and self._normalize_title(name) == target_title:
                exact_title.append(row)

        if not exact_title:
            return None
        if target_year:
            for row in exact_title:
                if self._year_text(row) == target_year:
                    return row
        return exact_title[0] if len(exact_title) == 1 else None

    def _lmhd_candidates(self, media_type, *, title, year=None,
                         season=1, episode=1):
        # Provider IDs are not TMDB IDs. Require an exact title/year match
        # before requesting a stream; do not cross-link unrelated content.
        if self.lmhd is None or not self.lmhd_vod_enabled or not title:
            return []
        try:
            if media_type == "movie":
                rows = self.lmhd.movie_sources(title=title, year=year)
            else:
                rows = self.lmhd.episode_sources(
                    title=title, year=year, season=season, episode=episode
                )
        except (PartnerApiError, OSError, ValueError, TypeError):
            return []

        sources = []
        seen = set()
        for row in rows[:8]:
            upstream = str(row.get("url") or "").strip()
            try:
                target_id = self._register_target(upstream)
            except ContentGatewayError:
                continue
            if target_id in seen:
                continue
            seen.add(target_id)
            # Sign and proxy URLs; source auth tokens never reach Android.
            # The media MIME hint disambiguates extensionless HLS sources.
            hint = str(row.get("format") or "").strip().lower()
            url = self._proxy_url(target_id)
            if hint in ("hls", "m3u8") and "format=" not in url:
                url += "&format=hls"
            elif hint in ("dash", "mpd") and "format=" not in url:
                url += "&format=mpd"
            sources.append({
                "provider": "POTV",
                "real_url": url,
                "language": row.get("language") or None,
                "quality": row.get("quality") or None,
            })
        return sources

    def _nova_candidates(self, kind, *, tmdb_id=None, title=None, year=None,
                         season=1, episode=1, is_anime=False):
        # Called only through the subscription-gated VOD routes in app.py.
        # This opt-in is deliberately separate from the public channel catalog.
        if not self.nova_vod_enabled or not tmdb_id:
            return []
        try:
            media_id = int(tmdb_id)
            if media_id <= 0:
                return []
            if kind == "movie":
                items = self.nova.movie_source_items(
                    str(media_id), title=title, year=year
                )
            else:
                items = self.nova.episode_source_items(
                    str(media_id), season, episode, title=title, year=year,
                    is_anime=is_anime,
                )
        except (NovaPartnerError, ValueError, TypeError):
            return []
        urls = self.nova._source_urls(items)
        candidates = []
        for url in urls[:8]:
            try:
                target_id = self._register_target(url)
            except ContentGatewayError:
                continue
            candidates.append({
                "provider": "POTV",
                "real_url": self._proxy_url(target_id),
                "language": "es-MX",
            })
        # Provider embed sources are WebView alternatives, not native MP4/HLS.
        if not candidates:
            for item in items[:8]:
                if not isinstance(item, dict):
                    continue
                uri = self.nova._valid_media_url(item.get("embed_url"))
                if not uri or not self._allowed_upstream(uri):
                    continue
                candidates.append({
                    "provider": "POTV",
                    "embed_url": uri,
                    "requires_extraction": True,
                    "quality": str(item.get("quality") or ""),
                    "language": str(item.get("language") or "es-MX"),
                })
        return candidates

    def resolve_movie(self, *, tmdb_id=None, title=None, year=None):
        sources = []
        seen_targets = set()
        for source in self.sources:
            upstream = None
            headers = {}
            quality = None
            xtream_failed = False

            if self._xtream_config(source) is not None:
                try:
                    categories = self._category_map(
                        source, "get_vod_categories"
                    )
                    rows = self._xtream_json(
                        source, "get_vod_streams", ttl=600
                    )
                    row = self._match_xtream_item(
                        rows,
                        tmdb_id=tmdb_id,
                        title=title,
                        year=year,
                        categories=categories,
                    )
                    if row is not None:
                        direct = str(
                            row.get("direct_source") or ""
                        ).strip()
                        if direct and self._allowed_upstream(direct):
                            upstream = direct
                        else:
                            upstream = self._xtream_stream_url(
                                source,
                                "movie",
                                row.get("stream_id"),
                                row.get("container_extension") or "mp4",
                            )
                        quality = (
                            str(row.get("quality") or "").strip() or None
                        )
                except Exception:
                    upstream = None
                    xtream_failed = True

            if upstream is None and not xtream_failed:
                try:
                    fallback = self._fallback_movie_entry(
                        source,
                        title=title,
                        year=year,
                    )
                except Exception:
                    fallback = None
                if fallback is not None:
                    upstream = fallback["url"]
                    headers = fallback.get("headers") or {}

            if upstream is None:
                continue
            try:
                target_id = self._register_target(upstream, headers)
            except ContentGatewayError:
                continue
            if target_id in seen_targets:
                continue
            seen_targets.add(target_id)
            sources.append({
                "provider": "POTV",
                "real_url": self._proxy_url(target_id),
                "language": "es-MX",
                "quality": quality,
            })
            if self.source_mode == "failover":
                break
        # Combine NOVA's authorized alternate sources with any existing
        # POTV provider candidates instead of discarding them in failover.
        sources.extend(self._nova_candidates(
            "movie", tmdb_id=tmdb_id, title=title, year=year
        ))
        # Keep authorized alternatives even when NOVA only offers a WebView
        # embed. The Android source picker prefers native MP4/HLS and can
        # fall back to another licensed provider on a playback error.
        # Account entitlement is checked at the VOD API route, not here.
        sources.extend(self._lmhd_candidates(
            "movie", title=title, year=year
        ))
        return {"sources": sources}

    def resolve_series_episode(
        self,
        *,
        tmdb_id=None,
        title=None,
        year=None,
        season=1,
        episode=1,
        is_anime=False,
    ):
        sources = []
        seen_targets = set()
        for source in self.sources:
            upstream = None
            headers = {}
            quality = None
            xtream_failed = False

            if self._xtream_config(source) is not None:
                try:
                    categories = self._category_map(
                        source, "get_series_categories"
                    )
                    rows = self._xtream_json(
                        source, "get_series", ttl=600
                    )
                    series = self._match_xtream_item(
                        rows,
                        tmdb_id=tmdb_id,
                        title=title,
                        year=year,
                        categories=categories,
                    )
                    if series is not None:
                        info = self._xtream_json(
                            source,
                            "get_series_info",
                            extra={"series_id": series.get("series_id")},
                            ttl=600,
                        )
                        episodes = (
                            info.get("episodes")
                            if isinstance(info, dict)
                            else None
                        )
                        if isinstance(episodes, dict):
                            season_rows = (
                                episodes.get(str(int(season)))
                                or episodes.get(int(season))
                            )
                            if isinstance(season_rows, list):
                                selected = None
                                for row in season_rows:
                                    if not isinstance(row, dict):
                                        continue
                                    row_episode = (
                                        row.get("episode_num")
                                        or row.get("episode")
                                        or row.get("num")
                                    )
                                    try:
                                        if int(row_episode) == int(episode):
                                            selected = row
                                            break
                                    except (TypeError, ValueError):
                                        continue
                                if selected is not None:
                                    upstream = self._xtream_stream_url(
                                        source,
                                        "series",
                                        selected.get("id")
                                        or selected.get("stream_id"),
                                        selected.get("container_extension")
                                        or "mp4",
                                    )
                                    quality = (
                                        str(
                                            selected.get("quality") or ""
                                        ).strip()
                                        or None
                                    )
                except Exception:
                    upstream = None
                    xtream_failed = True

            if upstream is None and not xtream_failed:
                try:
                    fallback = self._fallback_series_entry(
                        source,
                        title=title,
                        season=season,
                        episode=episode,
                    )
                except Exception:
                    fallback = None
                if fallback is not None:
                    upstream = fallback["url"]
                    headers = fallback.get("headers") or {}

            if upstream is None:
                continue
            try:
                target_id = self._register_target(upstream, headers)
            except ContentGatewayError:
                continue
            if target_id in seen_targets:
                continue
            seen_targets.add(target_id)
            sources.append({
                "provider": "POTV",
                "real_url": self._proxy_url(target_id),
                "language": "es-MX",
                "quality": quality,
            })
            if self.source_mode == "failover":
                break
        sources.extend(self._nova_candidates(
            "tv", tmdb_id=tmdb_id, title=title, year=year,
            season=season, episode=episode, is_anime=is_anime
        ))
        # A working provider must not hide alternate authorized sources.
        # This matters when NOVA serves only embeds while another provider
        # has a directly playable native episode stream.
        sources.extend(self._lmhd_candidates(
            "tv", title=title, year=year, season=season, episode=episode
        ))
        return {"sources": sources}

    def _target_id(self, url, headers):
        material = url + "\n" + json.dumps(headers or {}, sort_keys=True)
        return hashlib.sha256(material.encode("utf-8")).hexdigest()[:32]

    def _register_target(self, url, headers=None):
        url = str(url).strip()
        if not self._allowed_upstream(url):
            raise ContentGatewayError(400, "upstream_not_allowed")
        safe_headers = {}
        for key, value in (headers or {}).items():
            key = str(key).strip()
            value = str(value).strip()
            if key.lower() in ("user-agent", "referer", "origin") and value:
                safe_headers[key] = value
        target_id = self._target_id(url, safe_headers)
        with self._lock:
            self._targets[target_id] = (url, safe_headers)
            self._target_last_signed[target_id] = time.monotonic()
            self._new_target_counter += 1
            if self._new_target_counter >= 512:
                self._prune_expired_targets_locked(time.monotonic())
                self._new_target_counter = 0
        return target_id

    def _prune_expired_targets_locked(self, now):
        """Discard targets only after their 15-minute signatures expire.

        Caller holds the lock. In-flight transfers retain local URL/headers.
        """
        cutoff = now - 1200.0
        expired = [
            key for key, signed_at in self._target_last_signed.items()
            if signed_at < cutoff
        ]
        for key in expired:
            self._target_last_signed.pop(key, None)
            self._targets.pop(key, None)

    def _signature(self, target_id, expires):
        raw = f"{target_id}|{expires}".encode("utf-8")
        return hmac.new(self.secret, raw, hashlib.sha256).hexdigest()

    def _proxy_url(self, target_id, *, lifetime=900):
        expires = int(time.time()) + int(lifetime)
        sig = self._signature(target_id, expires)
        url = (
            f"{self.public_base}/api/v1/content/stream/{quote(target_id)}"
            f"?e={expires}&s={sig}"
        )
        # Signed endpoints hide the original extension. Media3 cannot infer
        # whether to construct an HLS, DASH or progressive media source from
        # the proxy path alone. Include a harmless transport hint, NEVER the
        # upstream URL or credentials. The signature still validates target_id.
        with self._lock:
            target = self._targets.get(target_id)
            if target is not None:
                self._target_last_signed[target_id] = time.monotonic()
        if target is not None:
            path = urlsplit(target[0]).path.lower()
            if path.endswith(".m3u8"):
                url += "&format=hls"
            elif path.endswith(".mpd"):
                url += "&format=mpd"
            elif path.endswith(".ts"):
                url += "&format=ts"
            elif path.endswith((".mp4", ".mkv", ".webm", ".m4v")):
                url += "&format=mp4"
        return url

    def _validate_signature(self, target_id, query):
        values = parse_qs(query or "")
        try:
            expires = int((values.get("e") or ["0"])[0])
        except ValueError:
            return False
        signature = (values.get("s") or [""])[0]
        if expires < int(time.time()) or expires > int(time.time()) + 3600:
            return False
        expected = self._signature(target_id, expires)
        return bool(signature) and hmac.compare_digest(signature, expected)

    def _parse_extinf(self, line):
        # EXTINF often includes a quoted User-Agent such as
        # "Mozilla/5.0 (KHTML, like Gecko)". Splitting at the FIRST comma
        # leaks "like Gecko) ..." into the public channel name.
        quoted = False
        separator = -1
        for index, char in enumerate(line):
            if char == '"' and (index == 0 or line[index - 1] != "\\"):
                quoted = not quoted
            elif char == "," and not quoted:
                separator = index
                break

        header = line[:separator] if separator >= 0 else line
        attrs = {
            key.lower(): value.strip()
            for key, value in _EXTINF_ATTR.findall(header)
        }
        name = line[separator + 1 :].strip() if separator >= 0 else ""
        return attrs, name

    def _normalized_label(self, value):
        text = unicodedata.normalize("NFKD", str(value).lower())
        text = "".join(char for char in text if not unicodedata.combining(char))
        return re.sub(r"[^a-z0-9+]+", " ", text).strip()

    def _is_adult_entry(self, name, group=""):
        text = " " + self._normalized_label(f"{name} {group}") + " "
        blocked_phrases = (
            " adultos ",
            " adulto ",
            " adult ",
            " xxx ",
            " porno ",
            " porn ",
            " pornografia ",
            " pornografico ",
            " erotico ",
            " erotica ",
            " erotic ",
            " desnudos ",
            " desnudas ",
            " desnudo ",
            " nude ",
            " nudity ",
            " sex tv ",
            " sex channel ",
            " playboy ",
            " penthouse ",
            " hustler ",
            " brazzers ",
            " redlight ",
        )
        if any(term in text for term in blocked_phrases):
            return True
        compact = text.replace(" ", "")
        return "+18" in compact or "18+" in compact

    def _is_stale_scheduled_entry(self, name, group=""):
        """Hide provider event slots whose leading MM/DD or DD/MM date expired."""
        text = str(name or "").strip()
        if not _SPORTS.search(f"{text} {group or ''}"):
            return False
        match = re.match(r"^\s*(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b", text)
        if not match:
            return False

        first = int(match.group(1))
        second = int(match.group(2))
        explicit_year = match.group(3)
        today = datetime.now(timezone.utc).date()
        years = [today.year - 1, today.year, today.year + 1]
        if explicit_year:
            year = int(explicit_year)
            if year < 100:
                year += 2000
            years = [year]

        candidates = []
        for year in years:
            for month, day in ((first, second), (second, first)):
                try:
                    candidates.append(datetime(year, month, day).date())
                except ValueError:
                    pass
        if not candidates:
            return False
        nearest = min(candidates, key=lambda value: abs((value - today).days))
        return (today - nearest).days > 2

    def _is_promotional_name(self, name):
        text = re.sub(r"\s+", " ", str(name).lower()).strip()
        blocked = (
            "mejor proveedor",
            "proveedor de iptv",
            "iptv premium",
            "mas de 3000 canales",
            "más de 3000 canales",
            "suscripcion iptv",
            "suscripción iptv",
            "contrata iptv",
            "whatsapp",
            "telegram",
            "visita nuestro",
        )
        return any(term in text for term in blocked)

    def _parse_m3u(self, raw):
        lines = raw.replace("\ufeff", "").splitlines()
        channels = []
        pending = None
        headers = {}
        for original in lines:
            line = original.strip()
            if not line:
                continue
            if line.startswith("#EXTINF"):
                attrs, name = self._parse_extinf(line)
                pending = (attrs, name)
                headers = {}
                continue
            if line.startswith("#EXTVLCOPT:"):
                value = line[len("#EXTVLCOPT:") :]
                key, _, option = value.partition("=")
                key = key.strip().lower()
                option = option.strip()
                if key in ("http-user-agent", "user-agent") and option:
                    headers["User-Agent"] = option
                elif key in ("http-referrer", "http-referer", "referer") and option:
                    headers["Referer"] = option
                continue
            if line.startswith("#"):
                continue
            if pending is None:
                continue
            attrs, name = pending
            pending = None
            group = attrs.get("group-title") or ""
            if (
                not name
                or self._is_promotional_name(name)
                or self._is_adult_entry(name, group)
                or not self._allowed_upstream(line)
            ):
                continue
            channels.append(
                {
                    "name": name,
                    "url": line,
                    "group": attrs.get("group-title") or "",
                    "epg_id": attrs.get("tvg-id") or "",
                    "logo": attrs.get("tvg-logo") or "",
                    "language": attrs.get("tvg-language") or "",
                    "headers": dict(headers),
                }
            )
        return channels

    def _m3u_inventory(self, source, ttl=600):
        now = time.monotonic()
        cached = self._m3u_cache.get(source)
        if cached and now - cached[0] < ttl:
            return cached[1]

        inventory = {
            "live": [],
            "movies": [],
            "series": [],
        }
        pending = None
        headers = {}
        entries = 0

        with self._fetch(source, timeout=8) as response:
            for raw_line in response:
                try:
                    line = raw_line.decode("utf-8", errors="replace").strip()
                except AttributeError:
                    line = str(raw_line).strip()
                if not line:
                    continue
                if line.startswith("#EXTINF"):
                    attrs, name = self._parse_extinf(line)
                    pending = (attrs, name)
                    headers = {}
                    continue
                if line.startswith("#EXTVLCOPT:"):
                    value = line[len("#EXTVLCOPT:") :]
                    key, _, option = value.partition("=")
                    key = key.strip().lower()
                    option = option.strip()
                    if key in ("http-user-agent", "user-agent") and option:
                        headers["User-Agent"] = option
                    elif key in (
                        "http-referrer",
                        "http-referer",
                        "referer",
                    ) and option:
                        headers["Referer"] = option
                    continue
                if line.startswith("#") or pending is None:
                    continue

                attrs, name = pending
                pending = None
                group = attrs.get("group-title") or ""
                if (
                    not name
                    or self._is_promotional_name(name)
                    or self._is_adult_entry(name, group)
                    or self._is_stale_scheduled_entry(name, group)
                    or not self._allowed_upstream(line)
                ):
                    continue

                item = {
                    "name": name,
                    "url": line,
                    "group": group,
                    "epg_id": attrs.get("tvg-id") or "",
                    "logo": attrs.get("tvg-logo") or "",
                    "language": attrs.get("tvg-language") or "",
                    "headers": dict(headers),
                }
                path = urlsplit(line).path.lower()
                if "/movie/" in path:
                    inventory["movies"].append(item)
                elif "/series/" in path:
                    inventory["series"].append(item)
                else:
                    inventory["live"].append(item)

                entries += 1
                if entries >= 200000:
                    break

        self._m3u_cache[source] = (now, inventory)
        return inventory

    def _fallback_movie_entry(self, source, *, title=None, year=None):
        inventory = self._m3u_inventory(source)
        target = self._normalize_title(title)
        target_year = str(year or "").strip()
        matches = []
        for item in inventory["movies"]:
            if self._normalize_title(item.get("name")) != target:
                continue
            matches.append(item)
        if not matches:
            return None
        if target_year:
            for item in matches:
                if target_year in str(item.get("name") or ""):
                    return item
        return matches[0] if len(matches) == 1 else None

    def _series_entry_identity(self, name):
        text = str(name or "").split("|", 1)[0].strip()
        patterns = (
            re.compile(r"(?i)\bS(?:eason)?\s*0*(\d+)\s*E(?:pisode)?\s*0*(\d+)\b"),
            re.compile(r"(?i)\b(\d{1,2})x(\d{1,3})\b"),
        )
        for pattern in patterns:
            match = pattern.search(text)
            if match:
                return (
                    self._normalize_title(text[: match.start()]),
                    int(match.group(1)),
                    int(match.group(2)),
                )
        return (self._normalize_title(text), None, None)

    def _fallback_series_entry(self, source, *, title=None, season=1, episode=1):
        inventory = self._m3u_inventory(source)
        target = self._normalize_title(title)
        for item in inventory["series"]:
            base, item_season, item_episode = self._series_entry_identity(
                item.get("name")
            )
            if (
                base == target
                and item_season == int(season)
                and item_episode == int(episode)
            ):
                return item
        return None

    def _source_document(self, url):
        with self._fetch(url) as response:
            raw = response.read(24 * 1024 * 1024 + 1)
        if len(raw) > 24 * 1024 * 1024:
            raise ContentGatewayError(413, "source_too_large")
        try:
            text = raw.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = raw.decode("latin-1", errors="replace")
        if "#EXTM3U" not in text[:2048]:
            raise ContentGatewayError(422, "not_m3u")
        return text

    def _channel_payload(self, channel):
        target_id = self._register_target(channel["url"], channel.get("headers"))
        stable = hashlib.sha256(
            (channel["name"].lower().strip() + "|" + channel["url"]).encode("utf-8")
        ).hexdigest()[:20]
        payload = {
            "id": stable,
            "name": channel["name"].strip(),
            "group": channel.get("group") or None,
            "epg_id": channel.get("epg_id") or None,
            "hls_url": self._proxy_url(target_id),
            "language": channel.get("language") or None,
        }
        hint = str(channel.get("format") or "").lower().strip()
        if hint in ("hls", "mpd", "ts", "mp4") and "format=" not in payload["hls_url"]:
            payload["hls_url"] += "&format=" + hint
        logo = str(channel.get("logo") or "").strip()
        if logo.startswith("https://"):
            payload["logo"] = logo
        return {key: value for key, value in payload.items() if value is not None}

    def _clean_sports_display_name(self, value):
        name = re.sub(
            r"(?i)^\s*(?:deportes\s*[|:-]|sp\s*:\s*mx\s*:|mx\s*[|:-]|izmx\s*[|:-])\s*",
            "",
            str(value or "").strip(),
        )
        name = re.sub(
            r"(?i)\s*\((?:mexico|méxico|usa|latin(?:o)?america)\)\s*$",
            "",
            name,
        )
        name = re.sub(
            r"(?i)\s+(?:full\s*hd|fhd|uhd|hd|sd|4k|1080p|720p)\s*$",
            "",
            name,
        )
        name = re.sub(r"\s+", " ", name).strip()
        replacements = (
            (r"(?i)\bespn\b", "ESPN"),
            (r"(?i)\btudn\b", "TUDN"),
            (r"(?i)\bnba\s+tv\b", "NBA TV"),
            (r"(?i)\bfox\s+sports\b", "Fox Sports"),
            (r"(?i)\bf1\b", "F1"),
            (r"(?i)\btennis\s+chanel\b", "Tennis Channel"),
        )
        for pattern, replacement in replacements:
            name = re.sub(pattern, replacement, name)
        return name or str(value or "").strip()

    def _sports_variant_key(self, value):
        name = self._clean_sports_display_name(value)
        text = unicodedata.normalize("NFKD", name)
        text = "".join(ch for ch in text if not unicodedata.combining(ch))
        text = text.lower()
        text = re.sub(r"(?i)\b(?:mexico|mexico|usa|latinoamerica|latin america)\b", " ", text)
        text = re.sub(r"[^a-z0-9+]+", " ", text)
        return re.sub(r"\s+", " ", text).strip()

    def _merge_sports_variants(self, channels):
        merged = []
        index = {}
        for channel in channels:
            key = self._sports_variant_key(channel.get("name"))
            if not key:
                continue
            current_index = index.get(key)
            if current_index is None:
                row = dict(channel)
                row["name"] = self._clean_sports_display_name(row.get("name"))
                row["backup_urls"] = list(row.get("backup_urls") or [])
                index[key] = len(merged)
                merged.append(row)
                continue

            current = merged[current_index]
            candidates = [
                current.get("hls_url"),
                *(current.get("backup_urls") or []),
                channel.get("hls_url"),
                *(channel.get("backup_urls") or []),
            ]
            unique = []
            for url in candidates:
                if url and url not in unique:
                    unique.append(url)
            if unique:
                current["hls_url"] = unique[0]
                current["backup_urls"] = unique[1:5]
            if not current.get("logo") and channel.get("logo"):
                current["logo"] = channel["logo"]
            if not current.get("epg_id") and channel.get("epg_id"):
                current["epg_id"] = channel["epg_id"]
        return merged

    def _metadata(self):
        if not self.metadata_file:
            return {}
        try:
            with open(self.metadata_file, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def _guide_payload(self, metadata, *, now=None):
        """Normalize only currently relevant, timezone-aware NOW/NEXT slots.

        Partner snapshots and in-memory caches can outlive their EPG data.
        A stale programme must not remain marked as live when sync fails.
        """
        now = now or datetime.now(timezone.utc)
        raw = metadata.get("now_next") or metadata.get("guide") or []
        result = []
        if not isinstance(raw, list):
            return result
        for row in raw:
            if not isinstance(row, dict):
                continue
            channel_id = str(
                row.get("channel_id") or row.get("epg_id") or row.get("channel") or ""
            ).strip()
            if not channel_id:
                continue
            clean = {"channel_id": channel_id}
            for slot in ("current", "now", "next", "upcoming"):
                value = row.get(slot)
                if not isinstance(value, dict):
                    continue
                title = str(value.get("title") or value.get("name") or "").strip()[:160]
                start = str(value.get("starts_at") or value.get("start") or "").strip()
                end = str(value.get("ends_at") or value.get("end") or "").strip()
                if not title or not start or not end:
                    continue
                try:
                    starts = datetime.fromisoformat(start.replace("Z", "+00:00"))
                    ends = datetime.fromisoformat(end.replace("Z", "+00:00"))
                    if starts.tzinfo is None or ends.tzinfo is None:
                        continue
                    starts = starts.astimezone(timezone.utc)
                    ends = ends.astimezone(timezone.utc)
                    if not (starts < ends <= starts + timedelta(hours=16)):
                        continue
                    if ends <= now or starts > now + timedelta(hours=36):
                        continue
                    if slot in ("current", "now") and starts > now + timedelta(minutes=2):
                        continue
                except (ValueError, TypeError, OverflowError):
                    continue
                key = "current" if slot in ("current", "now") else "next"
                # A provider's real NEXT programme may begin between the
                # 30-minute catalog syncs. Promote its published schedule to
                # NOW when it is currently on, without inventing a title.
                if key == "next" and starts <= now:
                    if "current" in clean:
                        continue
                    key = "current"
                clean[key] = {
                    "title": title,
                    "starts_at": starts.isoformat(),
                    "ends_at": ends.isoformat(),
                    **(
                        {"description": str(value.get("description")).strip()[:160]}
                        if value.get("description") else {}
                    ),
                }
            if len(clean) > 1:
                result.append(clean)
        return result

    def _events_payload(self, metadata, *, sports_channels=()):
        """Only explicit streams or unambiguous exact sports-channel IDs play.

        A fixture's teams, competition or channel name are never sufficient to
        guess a broadcast. Channel fallbacks use already-authorized, signed
        POTV URLs, not provider credentials or unsigned upstream URLs.
        """
        raw = metadata.get("sports_events") or []
        if not isinstance(raw, list):
            return []
        by_id = {}
        ambiguous = set()
        for channel in sports_channels:
            if not isinstance(channel, dict):
                continue
            for field in ("id", "epg_id"):
                key = str(channel.get(field) or "").strip()
                if not key:
                    continue
                if key in by_id and by_id[key].get("id") != channel.get("id"):
                    ambiguous.add(key)
                else:
                    by_id[key] = channel
        result = []
        for row in raw:
            if not isinstance(row, dict):
                continue
            event_id = str(row.get("id") or "").strip()
            home = str(row.get("home") or "").strip()
            away = str(row.get("away") or "").strip()
            starts_at = str(row.get("starts_at") or row.get("startsAt") or "").strip()
            if not event_id or not home or not away or not starts_at:
                continue
            try:
                when = datetime.fromisoformat(starts_at.replace("Z", "+00:00"))
                if when.tzinfo is None or not (2020 <= when.year <= 2100):
                    continue
            except ValueError:
                continue
            values = row.get("streams") or []
            # Do not mutate a provider's cached list when prepending direct URL.
            values = list(values) if isinstance(values, list) else [values]
            direct = row.get("stream_url") or row.get("primary_url")
            if direct:
                values.insert(0, direct)
            streams = []
            seen_targets = set()
            for value in values:
                if isinstance(value, dict):
                    url = value.get("url") or value.get("stream_url") or value.get("hls_url")
                    headers = value.get("headers") if isinstance(value.get("headers"), dict) else {}
                else:
                    url = value
                    headers = {}
                if not url:
                    continue
                try:
                    target_id = self._register_target(str(url), headers)
                except ContentGatewayError:
                    continue
                if target_id in seen_targets:
                    continue
                seen_targets.add(target_id)
                streams.append({"url": self._proxy_url(target_id)})
            if not streams:
                # Link a scheduled event only to an exact ID present in the
                # authorized sports catalog. Never infer by team or channel name.
                channel_key = str(row.get("channel_id") or row.get("epg_id") or "").strip()
                channel = by_id.get(channel_key) if channel_key not in ambiguous else None
                signed = channel.get("hls_url") if channel else None
                if (isinstance(signed, str) and signed.startswith(
                        self.public_base + "/api/v1/content/stream/")):
                    streams.append({"url": signed})
            if not streams:
                continue
            result.append(
                {
                    "id": event_id,
                    "sport": str(row.get("sport") or "Deporte"),
                    "competition": str(row.get("competition") or "Evento"),
                    "home": home,
                    "away": away,
                    "starts_at": starts_at,
                    "is_live": bool(row.get("is_live") or row.get("isLive")),
                    "streams": streams,
                }
            )
        return result

    @staticmethod
    def _public_catalog_revision(channels, guide, events):
        """Change revision when real programme/source data changes, not just counts.

        Strip expiring POTV proxy query signatures before hashing. This keeps
        revisions stable across signing refreshes but detects source rotation,
        channel metadata changes, and NOW/NEXT programme changes.
        No upstream URL or credential is returned in the revision.
        """
        def normalized(row):
            copy_row = dict(row)
            if "hls_url" in copy_row:
                copy_row["hls_url"] = urlsplit(
                    str(copy_row["hls_url"] or "")).path
            if "backup_urls" in copy_row:
                copy_row["backup_urls"] = [
                    urlsplit(str(url or "")).path
                    for url in (copy_row["backup_urls"] or [])
                ]
            if "streams" in copy_row:
                copy_row["streams"] = [
                    {**stream, "url": urlsplit(
                        str(stream.get("url") or "")).path}
                    if isinstance(stream, dict) else
                    urlsplit(str(stream or "")).path
                    for stream in (copy_row["streams"] or [])
                ]
            return copy_row

        def sorted_rows(rows):
            return sorted(
                (normalized(row) for row in rows if isinstance(row, dict)),
                key=lambda row: json.dumps(
                    row, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
            )

        material = {
            "channels": sorted_rows(channels),
            "guide": sorted_rows(guide),
            "events": sorted_rows(events),
        }
        return hashlib.sha256(json.dumps(
            material, sort_keys=True, ensure_ascii=False,
            separators=(",", ":")).encode("utf-8")).hexdigest()[:20]

    def _build_catalog(self):
        all_channels = []
        with self._lock:
            xtream_guide = list(self._sports_guide_cache)
        seen = set()
        failures = 0
        for source in self.sources:
            if not self._allowed_upstream(source):
                failures += 1
                continue
            try:
                if self._xtream_config(source) is not None:
                    try:
                        parsed = self._xtream_live_channels(source)
                    except Exception:
                        parsed = self._m3u_inventory(source)["live"]
                    self._schedule_sports_guide(source, parsed)
                else:
                    parsed = self._m3u_inventory(source)["live"]
            except Exception:
                failures += 1
                continue
            for channel in parsed:
                key = (
                    channel["name"].strip().lower(),
                    channel.get("epg_id", "").strip().lower(),
                )
                if key in seen:
                    continue
                seen.add(key)
                try:
                    all_channels.append(self._channel_payload(channel))
                except ContentGatewayError:
                    continue
            if parsed and self.live_source_mode == "failover":
                break

        raw_sports = [
            channel
            for channel in all_channels
            if _SPORTS.search(
                f"{channel.get('name', '')} {channel.get('group', '')}"
            )
        ]
        sports = self._merge_sports_variants(raw_sports)
        # Replace noisy/duplicate sports rows in the general TV catalog too,
        # otherwise Sports Hub can re-import them through partnerGeneral.
        all_channels = [
            channel
            for channel in all_channels
            if channel not in raw_sports
        ] + sports
        metadata = self._metadata()
        guide = [
            *self._guide_payload(metadata),
            *xtream_guide,
        ]
        events = self._events_payload(metadata, sports_channels=sports)
        revision = self._public_catalog_revision(all_channels, guide, events)
        return {
            "data": {
                "revision": revision,
                "channels": all_channels,
                "sports_channels": sports,
                "now_next": guide,
                "sports_events": events,
                "source_failures": failures,
            }
        }

    def media_page(self, *, kind, offset=0, limit=200):
        """A bounded, metadata-only page from the licensed NOVA VOD snapshot.

        Caller MUST enforce the POTV paid/trial session before invoking this
        method. No upstream playback URL or provider credential is returned.
        """
        if kind not in ("movies", "series", "anime"):
            raise ContentGatewayError(400, "invalid_media_kind")
        if (not isinstance(offset, int) or isinstance(offset, bool)
                or offset < 0 or offset > 100000
                or not isinstance(limit, int) or isinstance(limit, bool)
                or limit < 1 or limit > 500):
            raise ContentGatewayError(400, "invalid_media_page")
        if not self.nova_live_enabled:
            raise ContentGatewayError(503, "nova_catalog_unavailable")
        # Read a tiny page from the private SQLite sidecar written atomically
        # by nova_catalog_sync. Parsing the entire multi-megabyte snapshot on
        # every page request can exceed the API service's 128 MiB cgroup.
        index_path = self.nova_sync_file + ".media.sqlite3"
        try:
            uri = "file:" + quote(index_path) + "?mode=ro"
            with closing(sqlite3.connect(uri, uri=True, timeout=3)) as db:
                meta = db.execute(
                    "SELECT revision, total FROM meta WHERE kind=?", (kind,)
                ).fetchone()
                if meta is None:
                    raise ContentGatewayError(503, "nova_media_unavailable")
                revision, total = meta
                page_rows = db.execute(
                    "SELECT payload FROM media WHERE kind=? AND position>=? "
                    "ORDER BY position LIMIT ?", (kind, offset, limit)
                ).fetchall()
            rows = [json.loads(row[0]) for row in page_rows]
        except (OSError, sqlite3.Error, ValueError, TypeError) as exc:
            raise ContentGatewayError(503, "nova_media_unavailable") from exc
        # Explicit allowlist: future provider fields such as direct links,
        # tokens, cookies or internal IDs must never reach an Android client.
        fields = ("tmdb_id", "anilist_id", "title", "year", "overview")
        allowed_image_hosts = {"image.tmdb.org", "s4.anilist.co", "tioanime.com"}
        items = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            item = {key: row[key] for key in fields if key in row}
            for field in ("poster", "backdrop"):
                value = row.get(field)
                if not isinstance(value, str):
                    continue
                # A malformed upstream poster URL (for example an unclosed
                # IPv6 bracket) must not break the entire subscriber page.
                try:
                    parsed = urlsplit(value)
                    valid_image = (parsed.scheme == "https"
                                   and parsed.hostname in allowed_image_hosts
                                   and not parsed.username and not parsed.password
                                   and not parsed.query and not parsed.fragment)
                except ValueError:
                    valid_image = False
                if valid_image:
                    item[field] = value
            items.append(item)
        return {
            "ok": True,
            "data": {
                "kind": kind,
                "revision": revision,
                "total": total,
                "offset": offset,
                "limit": limit,
                "has_more": offset + limit < total,
                "items": items,
            },
        }

    def _merge_airtv_entitled(self, payload):
        """Add only fresh, authorized AirTV channels AFTER account entitlement.

        No upstream URL or Firestore credentials appear in the client catalog.
        The private synchronizer must have completed a current successful
        read from the provider before the first channel is exposed.
        """
        if not self.airtv_live_enabled or not self.airtv_sync_file:
            return payload
        try:
            stat = os.stat(self.airtv_sync_file)
            if not (0 <= time.time() - stat.st_mtime <= 1800
                    and 0 < stat.st_size <= 8 * 1024 * 1024):
                return payload
            with open(self.airtv_sync_file, "r", encoding="utf-8") as stream:
                snapshot = json.load(stream)
            rows = snapshot.get("channels")
            if (snapshot.get("version") != 1
                    or snapshot.get("provider") != "airtv"
                    or not isinstance(rows, list)):
                return payload
        except (OSError, ValueError, TypeError, AttributeError):
            return payload
        data = payload.get("data") or {}
        original = data.get("channels") or []
        all_channels = list(original)
        known_ids = {str(r.get("id") or "") for r in original if isinstance(r, dict)}
        seen = {(str(r.get("name") or "").casefold().strip(),
                 str(r.get("epg_id") or "").casefold().strip())
                for r in original if isinstance(r, dict)}
        digests = []
        for row in rows[:5000]:
            if not isinstance(row, dict):
                continue
            ident = str(row.get("id") or "")
            name = str(row.get("name") or "").strip()
            group = str(row.get("group") or "").strip()
            if (not re.fullmatch(r"airtv:[a-f0-9]{20}", ident)
                    or not name or self._is_adult_entry(name, group)
                    or ident in known_ids):
                continue
            key = (name.casefold(), str(row.get("epg_id") or "").casefold().strip())
            if key in seen:
                continue
            try:
                channel = self._channel_payload(row)
                channel["id"] = ident
                backups = []
                for url in (row.get("backup_urls") or [])[:4]:
                    try:
                        target = self._register_target(url)
                    except (ContentGatewayError, TypeError, ValueError):
                        continue
                    backups.append(self._proxy_url(target))
                if backups:
                    channel["backup_urls"] = backups
            except (ContentGatewayError, ValueError, TypeError):
                continue
            all_channels.append(channel)
            known_ids.add(ident)
            seen.add(key)
            digests.append(hashlib.sha256((
                ident + "|" + str(row.get("url") or "") + "|" +
                json.dumps(row.get("backup_urls") or [], sort_keys=True)
            ).encode("utf-8")).hexdigest()[:20])
        if not digests:
            return payload
        sports_rows = [r for r in all_channels if _SPORTS.search(
            str(r.get("name") or "") + " " + str(r.get("group") or ""))]
        sports = self._merge_sports_variants(sports_rows)
        data["sports_channels"] = sports
        data["channels"] = [r for r in all_channels if r not in sports_rows] + sports
        data["revision"] = hashlib.sha256((
            str(data.get("revision") or "") + "|AIRTV|" +
            str(snapshot.get("revision") or "") + "|" + "|".join(sorted(digests))
        ).encode("utf-8")).hexdigest()[:20]
        return payload

    def _merge_lmhd_entitled(self, payload):
        """Add approved LMHD channels ONLY after POTV account entitlement.

        The public M3U catalog and anonymous paths must never invoke the
        partner or expose the streams. This bridge is entirely inactive
        unless a separate service-issued partner account is configured.
        """
        if self.lmhd is None or not self.lmhd_live_catalog_enabled:
            return payload
        data = payload.get("data") or {}
        channels = data.get("channels") or []
        seen = {
            (str(row.get("name") or "").strip().casefold(),
             str(row.get("epg_id") or "").strip().casefold())
            for row in channels if isinstance(row, dict)
        }
        appended = []
        partner_guide = []
        partner_events = []
        # Sync can refresh the upstream independently of active sessions.
        # Signed URLs must only be minted after POTV account entitlement.
        partner_rows = None
        snapshot_events = None
        if self.lmhd_sync_file:
            try:
                stat = os.stat(self.lmhd_sync_file)
                if (0 <= time.time() - stat.st_mtime <= 720
                        and stat.st_size <= 8 * 1024 * 1024):
                    with open(self.lmhd_sync_file, "r", encoding="utf-8") as stream:
                        approved = json.load(stream)
                    if (approved.get("version") == 1
                            and isinstance(approved.get("channels"), list)
                            and isinstance(approved.get("sports_events"), list)):
                        partner_rows = approved["channels"]
                        snapshot_events = approved["sports_events"]
            except (OSError, ValueError, TypeError, AttributeError):
                partner_rows = None
                snapshot_events = None
        try:
            if partner_rows is None:
                partner_rows = self.lmhd.tv_channels()
        except PartnerApiError as error:
            if error.code in ("partner_session_denied", "partner_authorization_or_api_error"):
                return payload
            partner_rows = []
        except (OSError, ValueError, TypeError):
            partner_rows = []
        if not isinstance(partner_rows, list):
            partner_rows = []
        source_digests = []
        for row in partner_rows[:6000]:
            if not isinstance(row, dict):
                continue
            name = str(row.get("name") or "").strip()
            group = str(row.get("group") or "").strip()
            if not name or self._is_adult_entry(name, group):
                continue
            key = (name.casefold(),
                   str(row.get("epg_id") or "").strip().casefold())
            if key in seen:
                continue
            try:
                channel = self._channel_payload(row)
            except ContentGatewayError:
                continue
            # A provider's playback URL may rotate at every refresh.
            # Keep a stable public channel ID for favourites/progress.
            provider_id = str(row.get("provider_id") or "").strip()
            if provider_id.isdecimal() and int(provider_id) > 0:
                channel["id"] = "lmhd:" + provider_id
            seen.add(key)
            appended.append(channel)
            source_digests.append(hashlib.sha256((
                str(channel.get("id") or "") + "|" +
                str(row.get("url") or "")
            ).encode("utf-8")).hexdigest()[:20])
            if channel.get("epg_id"):
                slots = []
                for entry in (row.get("epg") or [])[:32]:
                    if isinstance(entry, dict) and entry.get("title"):
                        slots.append(entry)
                # Map EpgProg time windows to currently on-air and next
                # slots; missing data remains "Sin programación".
                now_utc = datetime.now(timezone.utc)
                relevant = []
                for entry in slots:
                    try:
                        start_at = datetime.fromisoformat(
                            entry["starts_at"].replace("Z", "+00:00"))
                        end_at = datetime.fromisoformat(
                            entry["ends_at"].replace("Z", "+00:00"))
                    except (ValueError, TypeError, KeyError):
                        continue
                    if now_utc - timedelta(hours=2) <= end_at and (
                        start_at <= now_utc + timedelta(hours=36)
                    ):
                        relevant.append((start_at, end_at, entry))
                if relevant:
                    relevant.sort(key=lambda v: v[0])
                    airing = next((p[2] for p in relevant if
                                   p[0] <= now_utc < p[1]), None)
                    next_item = next((p[2] for p in relevant if
                                      p[0] > now_utc), None)
                    if airing or next_item:
                        partner_guide.append({
                            "channel_id": channel["epg_id"],
                            **({"now": airing} if airing else {}),
                            **({"next": next_item} if next_item else {}),
                        })
        try:
            partner_events = (snapshot_events if snapshot_events is not None
                              else self.lmhd.sports_events())
        except PartnerApiError as error:
            if error.code in ("partner_session_denied", "partner_authorization_or_api_error"):
                return payload
            partner_events = []
        except (OSError, ValueError, TypeError):
            partner_events = []
        if not appended and not partner_events:
            return payload
        data["channels"] = list(channels) + appended
        if partner_guide:
            data["now_next"] = [
                *(data.get("now_next") or []),
                *self._guide_payload({"now_next": partner_guide}),
            ]
        sports = self._merge_sports_variants([
            row for row in data["channels"]
            if _SPORTS.search(
                str(row.get("name") or "") + " " +
                str(row.get("group") or ""))
        ])
        data["sports_channels"] = sports
        if partner_events:
            data.setdefault("sports_events", []).extend(
                self._events_payload(
                    {"sports_events": partner_events},
                    sports_channels=sports))
        revision_piece = "|".join(
            sorted(str(row.get("id") or "") for row in appended))
        # A URL rotation must advance the catalog revision even when EPG
        # and stable channel IDs have not changed. Never expose source URLs.
        revision_piece += "|sources=" + "|".join(sorted(source_digests))
        revision_piece += "|events=" + str(len(data.get("sports_events") or []))
        revision_piece += "|guide=" + json.dumps(
            partner_guide, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        )
        data["revision"] = hashlib.sha256((
            str(data.get("revision") or "") + "|LMHD|" + revision_piece
        ).encode("utf-8")).hexdigest()[:20]
        return payload

    def catalog_for_subscriber(self):
        """A POTV-authenticated subscriber's TV catalog with authorized NOVA.

        MUST be called only after app.py confirms a valid paid/trial session.
        Never expose this snapshot from the public content/catalog route.
        """
        public = self.catalog()
        if not self.nova_live_enabled and not self.airtv_live_enabled and not (
            self.lmhd is not None and self.lmhd_live_catalog_enabled
        ):
            return public
        now = time.monotonic()
        with self._lock:
            if (
                self._nova_subscriber_catalog is not None
                and now - self._nova_subscriber_catalog_at < self.refresh_seconds
            ):
                return self._resign_cached_catalog(self._nova_subscriber_catalog)
        if not self.nova_live_enabled:
            result = self._merge_airtv_entitled(
                self._merge_lmhd_entitled(copy.deepcopy(public)))
            with self._lock:
                self._nova_subscriber_catalog = result
                self._nova_subscriber_catalog_at = now
            return result
        try:
            if os.path.getsize(self.nova_sync_file) > MAX_NOVA_SNAPSHOT_BYTES:
                raise ValueError("nova_snapshot_too_large")
            with open(self.nova_sync_file, "r", encoding="utf-8") as fh:
                snapshot = json.load(fh)
            rows = snapshot.get("channels") or []
            if not isinstance(rows, list) or not rows:
                raise ValueError("nova_snapshot_empty_channels")
        except (OSError, ValueError, TypeError, AttributeError):
            # An upstream failure must not destroy the existing TV lineup.
            with self._lock:
                if self._nova_subscriber_catalog is not None:
                    return self._resign_cached_catalog(self._nova_subscriber_catalog)
            return self._merge_airtv_entitled(
                self._merge_lmhd_entitled(copy.deepcopy(public)))

        payload = copy.deepcopy(public)
        data = payload["data"]
        base_rows = data.get("channels") or []
        all_channels = list(base_rows)
        seen = {
            (str(item.get("name") or "").lower().strip(),
             str(item.get("epg_id") or "").lower().strip())
            for item in all_channels
        }
        appended = 0
        # The source URL is not a stable channel identity: NOVA may rotate
        # signed CDN URLs on every scheduled catalog synchronization.
        # Preserve the partner-issued channel ID so user favorites survive.
        known_ids = {str(item.get("id") or "") for item in all_channels}
        for row in rows[:7000]:
            if not isinstance(row, dict):
                continue
            name = str(row.get("name") or "").strip()
            group = str(row.get("group") or "").strip()
            if not name or self._is_adult_entry(name, group):
                continue
            key = (name.lower(), str(row.get("epg_id") or "").lower())
            if key in seen:
                continue
            try:
                channel = self._channel_payload(row)
            except ContentGatewayError:
                continue
            source_id = str(row.get("id") or "").strip()
            if (re.fullmatch(r"nova:[0-9]{1,14}", source_id)
                    and source_id not in known_ids):
                channel["id"] = source_id
            known_ids.add(channel["id"])
            backups = []
            raw_backups = row.get("backup_urls")
            if isinstance(raw_backups, list):
                backup_hints = row.get("backup_formats") or []
                for backup_index, url in enumerate(raw_backups[:4]):
                    try:
                        target = self._register_target(url)
                    except (ContentGatewayError, ValueError, TypeError):
                        continue
                    signed = self._proxy_url(target)
                    hint = (backup_hints[backup_index]
                            if isinstance(backup_hints, list)
                            and backup_index < len(backup_hints) else "")
                    if hint in ("hls", "mpd", "ts", "mp4") and "format=" not in signed:
                        signed += "&format=" + hint
                    backups.append(signed)
            if backups:
                channel["backup_urls"] = backups
            seen.add(key)
            all_channels.append(channel)
            appended += 1
        raw_sports = [
            channel for channel in all_channels
            if _SPORTS.search(
                str(channel.get("name") or "") + " " +
                str(channel.get("group") or "")
            )
        ]
        sports = self._merge_sports_variants(raw_sports)
        data["channels"] = [
            channel for channel in all_channels
            if channel not in raw_sports
        ] + sports
        data["sports_channels"] = sports
        # NOVA guide is only surfaced from the authenticated catalog. Map its
        # exact provider channel IDs to POTV EPG IDs during snapshot sync.
        # Do not advertise unverified sports fixtures as playable events.
        visible_epg_ids = {
            str(channel.get("epg_id") or "").strip()
            for channel in data["channels"]
            if isinstance(channel, dict) and channel.get("epg_id")
        }
        nova_guide = self._guide_payload({
            "now_next": snapshot.get("now_next") or []
        })
        data["now_next"] = [
            *(data.get("now_next") or []),
            *(entry for entry in nova_guide
              if entry["channel_id"] in visible_epg_ids),
        ]
        for media_kind in ("movies", "series", "anime"):
            media_rows = snapshot.get(media_kind)
            if isinstance(media_rows, list):
                data[media_kind] = media_rows[:1500]
        data["revision"] = hashlib.sha256((
            str(data.get("revision") or "") +
            str(snapshot.get("revision") or "") + str(appended)
        ).encode("utf-8")).hexdigest()[:20]
        payload = self._merge_airtv_entitled(self._merge_lmhd_entitled(payload))
        with self._lock:
            self._nova_subscriber_catalog = payload
            self._nova_subscriber_catalog_at = now
        return payload

    def _resign_cached_catalog(self, payload):
        # Cached URLs have a 15-minute TTL. Refresh their signatures without
        # contacting a provider, so a temporary upstream outage never makes
        # the previously published channel guide unusable.
        result = copy.deepcopy(payload)
        data = result.get("data") or {}
        if isinstance(data.get("now_next"), list):
            data["now_next"] = self._guide_payload({"now_next": data["now_next"]})
        prefix = "/api/v1/content/stream/"

        def resign(url):
            if not isinstance(url, str):
                return url
            parsed = urlsplit(url)
            if not parsed.path.startswith(prefix):
                return url
            target_id = unquote(parsed.path[len(prefix):])
            if target_id not in self._targets:
                return url
            signed = self._proxy_url(target_id)
            # The CDN can serve HLS or MPEG-TS from an extensionless URL.
            # Preserve a previously classified transport hint when renewing
            # a 15-minute signature from the subscriber's cached catalog.
            hint = (parse_qs(parsed.query).get("format") or [""])[0]
            if hint in ("hls", "mpd", "ts", "mp4") and "format=" not in signed:
                signed += "&format=" + hint
            return signed

        for group in ("channels", "sports_channels"):
            for channel in result.get("data", {}).get(group, []):
                if "hls_url" in channel:
                    channel["hls_url"] = resign(channel["hls_url"])
                if "backup_urls" in channel:
                    channel["backup_urls"] = [
                        resign(url) for url in channel["backup_urls"]
                    ]
        for event in result.get("data", {}).get("sports_events", []):
            for stream in event.get("streams", []):
                if isinstance(stream, dict) and "url" in stream:
                    stream["url"] = resign(stream["url"])
        return result

    def _refresh_catalog_background(self):
        try:
            payload = self._build_catalog()
            payload["data"]["now_next"] = self._guide_payload(
                {"now_next": payload["data"].get("now_next") or []}
            )
            with self._lock:
                # Do not erase a useful cached catalog when the upstream
                # momentarily stops responding during a refresh.
                if payload["data"].get("channels") or self._catalog is None:
                    self._catalog = payload
                self._catalog_at = time.monotonic()
        except Exception:
            with self._lock:
                # Brief backoff prevents a dead upstream from spawning
                # another blocking refresh on every client request.
                self._catalog_at = time.monotonic() - self.refresh_seconds + 30
        finally:
            with self._lock:
                self._catalog_refreshing = False

    def catalog(self, *, force=False):
        if not self.configured:
            raise ContentGatewayError(503, "content_gateway_unconfigured")
        now = time.monotonic()
        refresh_in_background = False
        with self._lock:
            if not force and self._catalog is not None:
                if (
                    now - self._catalog_at >= self.refresh_seconds
                    and not self._catalog_refreshing
                ):
                    self._catalog_refreshing = True
                    refresh_in_background = True
                snapshot = self._resign_cached_catalog(self._catalog)
            else:
                snapshot = None
        if snapshot is not None:
            if refresh_in_background:
                threading.Thread(
                    target=self._refresh_catalog_background,
                    name="potv-catalog-refresh",
                    daemon=True,
                ).start()
            return snapshot

        # The initial cold start and force=True still hydrate synchronously.
        # A subsequent request is served from memory even when the provider
        # becomes unreachable.
        payload = self._build_catalog()
        payload["data"]["now_next"] = self._guide_payload(
            {"now_next": payload["data"].get("now_next") or []}
        )
        with self._lock:
            latest_guide = list(self._sports_guide_cache)
            if latest_guide:
                existing = payload["data"].get("now_next") or []
                seen = {
                    (
                        str(row.get("channel_id") or ""),
                        str((row.get("current") or {}).get("title") or ""),
                        str((row.get("next") or {}).get("title") or ""),
                    )
                    for row in existing if isinstance(row, dict)
                }
                for row in latest_guide:
                    key = (
                        str(row.get("channel_id") or ""),
                        str((row.get("current") or {}).get("title") or ""),
                        str((row.get("next") or {}).get("title") or ""),
                    )
                    if key not in seen:
                        existing.append(row)
                        seen.add(key)
                payload["data"]["now_next"] = self._guide_payload(
                    {"now_next": existing}
                )
            self._catalog = payload
            self._catalog_at = time.monotonic()
        return payload

    def _rewrite_hls(self, body, base_url, headers):
        def proxied(value):
            upstream = urljoin(base_url, value.strip())
            target_id = self._register_target(upstream, headers)
            return self._proxy_url(target_id)

        output = []
        for raw_line in body.splitlines():
            line = raw_line.strip()
            if not line:
                output.append("")
                continue
            if line.startswith("#"):
                def repl(match):
                    # Never return an original upstream URI to an Android
                    # client. Rejected DRM key / rendition references must
                    # fail the manifest as a whole, not leak credentials.
                    return 'URI="' + proxied(match.group(1)) + '"'
                output.append(_HLS_URI_ATTR.sub(repl, raw_line))
            else:
                # Every HLS segment must stay inside POTV's signed proxy.
                # Forwarding the raw line on upstream validation failure
                # could expose private Xtream credentials to clients.
                output.append(proxied(line))
        return "\n".join(output) + "\n"

    def _json_error(self, handler, status, code):
        raw = json.dumps({"ok": False, "error": code}).encode("utf-8")
        handler.send_response(status)
        handler.send_header("Content-Type", "application/json")
        handler.send_header("Content-Length", str(len(raw)))
        handler.send_header("Cache-Control", "no-store")
        handler.end_headers()
        handler.wfile.write(raw)

    def _hydrate_target(self, target_id):
        """Restore signed streams once after restart, not once per caller.

        Live proxies are a ThreadingHTTPServer. Concurrent requests for
        historical signed URLs previously caused simultaneous expensive
        rebuilds of both public and subscriber catalogs. Under a 128 MiB
        systemd memory ceiling that could OOM-kill the entire account API.
        Serializing and temporarily coalescing misses prevents that storm.
        """
        with self._lock:
            if target_id in self._targets:
                return
        with self._hydrate_lock:
            with self._lock:
                if target_id in self._targets:
                    return
                now = time.monotonic()
                if now - self._last_full_target_hydrate < 30:
                    return
                self._last_full_target_hydrate = now
            # RLock is not held across the network-dependent catalog build;
            # other already-registered streams can continue playing.
            self.catalog(force=True)
            if self.nova_live_enabled:
                with self._lock:
                    if target_id in self._targets:
                        return
                    self._nova_subscriber_catalog = None
                    self._nova_subscriber_catalog_at = 0
                self.catalog_for_subscriber()

    def serve_target(self, handler, target_id, query):
        if not self._validate_signature(target_id, query):
            self._json_error(handler, 403, "invalid_or_expired_stream")
            return
        try:
            # Rebuild lazy state after a process restart so stable channel IDs
            # become available again before lookup.
            if target_id not in self._targets:
                self._hydrate_target(target_id)
            target = self._targets.get(target_id)
            if target is None:
                raise ContentGatewayError(404, "stream_not_found")
            url, headers = target
            forwarded = dict(headers)
            range_header = handler.headers.get("Range")
            if range_header:
                forwarded["Range"] = range_header
            with self._fetch(url, headers=forwarded, timeout=30) as response:
                content_type = (
                    response.headers.get("Content-Type")
                    or "application/octet-stream"
                )
                is_hls = (
                    "mpegurl" in content_type.lower()
                    or urlsplit(url).path.lower().endswith(".m3u8")
                )
                # Some licensed CDNs serve extensionless HLS as text/plain
                # or application/octet-stream. Forwarding such a manifest
                # verbatim would expose its upstream segment/key URLs and
                # prevent nested requests from using the signed POTV proxy.
                # Sniff only a small prefix, preserving it for binary streams.
                prefix = b"" if is_hls else response.read(512)
                if not is_hls:
                    is_hls = prefix.lstrip(b"\xef\xbb\xbf \t\r\n").startswith(b"#EXTM3U")
                if is_hls:
                    limit = 4 * 1024 * 1024
                    body = prefix + response.read(limit + 1 - len(prefix))
                    if len(body) > limit:
                        raise ContentGatewayError(413, "playlist_too_large")
                    text = body.decode("utf-8-sig", errors="replace")
                    rewritten = self._rewrite_hls(text, url, headers).encode("utf-8")
                    handler.send_response(200)
                    handler.send_header(
                        "Content-Type", "application/vnd.apple.mpegurl"
                    )
                    handler.send_header("Content-Length", str(len(rewritten)))
                    handler.send_header("Cache-Control", "no-store")
                    handler.end_headers()
                    handler.wfile.write(rewritten)
                    return

                status = getattr(response, "status", 200)
                handler.send_response(status)
                for header in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"):
                    value = response.headers.get(header)
                    if value:
                        handler.send_header(header, value)
                handler.send_header("Cache-Control", "no-store")
                handler.end_headers()
                if prefix:
                    handler.wfile.write(prefix)
                while True:
                    chunk = response.read(64 * 1024)
                    if not chunk:
                        break
                    handler.wfile.write(chunk)
        except ContentGatewayError as exc:
            self._json_error(handler, exc.status, exc.code)
        except (HTTPError, URLError, TimeoutError, OSError, BrokenPipeError):
            # Never include upstream URLs or credentials in the response.
            try:
                self._json_error(handler, 502, "upstream_unavailable")
            except (BrokenPipeError, ConnectionResetError):
                pass