#!/usr/bin/env python3
"""Authorized POTV content gateway.

Partner source URLs and credentials are loaded only from protected server
configuration. The Flutter client receives opaque, short-lived HTTPS proxy
URLs and never receives the upstream credentials.
"""
import base64
import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import threading
import time
import unicodedata
from datetime import datetime, timezone
from http.cookiejar import CookieJar
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, urlencode, urljoin, urlsplit, urlunsplit
from urllib.request import (
    HTTPCookieProcessor,
    Request,
    build_opener,
)

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
        self.opener = opener or build_opener(HTTPCookieProcessor(CookieJar()))
        self._lock = threading.RLock()
        self._targets = {}
        self._catalog = None
        self._catalog_at = 0.0
        self._xtream_cache = {}
        self._m3u_cache = {}
        self._sports_guide_cache = []
        self._sports_guide_at = 0.0
        self._sports_guide_refreshing = False

    @property
    def configured(self):
        return bool(self.sources)

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
            if (
                ip.is_private
                or ip.is_loopback
                or ip.is_link_local
                or ip.is_multicast
                or ip.is_reserved
                or ip.is_unspecified
            ):
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

        query = {
            "username": config["username"],
            "password": config["password"],
            "action": action,
        }
        query.update(extra or {})
        url = config["base"] + "/player_api.php?" + urlencode(query)
        data = self._fetch_json(url)
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

    def resolve_movie(self, *, tmdb_id=None, title=None, year=None):
        sources = []
        seen_targets = set()
        for source in self.sources:
            upstream = None
            headers = {}
            quality = None

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

            if upstream is None:
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
        return {"sources": sources}

    def resolve_series_episode(
        self,
        *,
        tmdb_id=None,
        title=None,
        year=None,
        season=1,
        episode=1,
    ):
        sources = []
        seen_targets = set()
        for source in self.sources:
            upstream = None
            headers = {}
            quality = None

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

            if upstream is None:
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
        return target_id

    def _signature(self, target_id, expires):
        raw = f"{target_id}|{expires}".encode("utf-8")
        return hmac.new(self.secret, raw, hashlib.sha256).hexdigest()

    def _proxy_url(self, target_id, *, lifetime=900):
        expires = int(time.time()) + int(lifetime)
        sig = self._signature(target_id, expires)
        return (
            f"{self.public_base}/api/v1/content/stream/{quote(target_id)}"
            f"?e={expires}&s={sig}"
        )

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
        attrs = {
            key.lower(): value.strip()
            for key, value in _EXTINF_ATTR.findall(line)
        }
        name = line.split(",", 1)[1].strip() if "," in line else ""
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

        with self._fetch(source, timeout=35) as response:
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

    def _guide_payload(self, metadata):
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
                title = str(value.get("title") or value.get("name") or "").strip()
                start = str(value.get("starts_at") or value.get("start") or "").strip()
                end = str(value.get("ends_at") or value.get("end") or "").strip()
                if title and start and end:
                    clean["current" if slot in ("current", "now") else "next"] = {
                        "title": title,
                        "starts_at": start,
                        "ends_at": end,
                        **(
                            {"description": str(value.get("description")).strip()}
                            if value.get("description")
                            else {}
                        ),
                    }
            if len(clean) > 1:
                result.append(clean)
        return result

    def _events_payload(self, metadata):
        raw = metadata.get("sports_events") or []
        if not isinstance(raw, list):
            return []
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
            values = row.get("streams") or []
            if not isinstance(values, list):
                values = [values]
            direct = row.get("stream_url") or row.get("primary_url")
            if direct:
                values.insert(0, direct)
            streams = []
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
                streams.append({"url": self._proxy_url(target_id)})
            if not streams:
                # Never advertise an event as playable without an explicit stream.
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
            if parsed and self.source_mode == "failover":
                break

        sports = self._merge_sports_variants([
            channel
            for channel in all_channels
            if _SPORTS.search(
                f"{channel.get('name', '')} {channel.get('group', '')}"
            )
        ])
        metadata = self._metadata()
        guide = [
            *self._guide_payload(metadata),
            *xtream_guide,
        ]
        events = self._events_payload(metadata)
        revision_material = "|".join(sorted(channel["id"] for channel in all_channels))
        revision_material += f"|{len(guide)}|{len(events)}"
        revision = hashlib.sha256(revision_material.encode("utf-8")).hexdigest()[:20]
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

    def catalog(self, *, force=False):
        if not self.configured:
            raise ContentGatewayError(503, "content_gateway_unconfigured")
        now = time.monotonic()
        with self._lock:
            if (
                not force
                and self._catalog is not None
                and now - self._catalog_at < self.refresh_seconds
            ):
                return self._catalog
        payload = self._build_catalog()
        with self._lock:
            # The async short-EPG worker can finish between _build_catalog()
            # taking its cache snapshot and this assignment. Reconcile the
            # newest cache here so the first catalog response cannot lose a
            # completed guide refresh due to that race.
            latest_guide = list(self._sports_guide_cache)
            if latest_guide:
                existing = payload["data"].get("now_next") or []
                seen = {
                    (
                        str(row.get("channel_id") or ""),
                        str((row.get("current") or {}).get("title") or ""),
                        str((row.get("next") or {}).get("title") or ""),
                    )
                    for row in existing
                    if isinstance(row, dict)
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
                payload["data"]["now_next"] = existing
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
                    try:
                        return 'URI="' + proxied(match.group(1)) + '"'
                    except ContentGatewayError:
                        return match.group(0)
                output.append(_HLS_URI_ATTR.sub(repl, raw_line))
            else:
                try:
                    output.append(proxied(line))
                except ContentGatewayError:
                    output.append(line)
        return "\n".join(output) + "\n"

    def _json_error(self, handler, status, code):
        raw = json.dumps({"ok": False, "error": code}).encode("utf-8")
        handler.send_response(status)
        handler.send_header("Content-Type", "application/json")
        handler.send_header("Content-Length", str(len(raw)))
        handler.send_header("Cache-Control", "no-store")
        handler.end_headers()
        handler.wfile.write(raw)

    def serve_target(self, handler, target_id, query):
        if not self._validate_signature(target_id, query):
            self._json_error(handler, 403, "invalid_or_expired_stream")
            return
        try:
            # Rebuild lazy state after a process restart so stable channel IDs
            # become available again before lookup.
            if target_id not in self._targets:
                self.catalog(force=True)
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
                if is_hls:
                    body = response.read(4 * 1024 * 1024 + 1)
                    if len(body) > 4 * 1024 * 1024:
                        raise ContentGatewayError(413, "playlist_too_large")
                    text = body.decode("utf-8", errors="replace")
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
