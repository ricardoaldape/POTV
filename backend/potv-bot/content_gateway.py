#!/usr/bin/env python3
"""Authorized POTV content gateway.

Partner source URLs and credentials are loaded only from protected server
configuration. The Flutter client receives opaque, short-lived HTTPS proxy
URLs and never receives the upstream credentials.
"""
import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import threading
import time
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
        channels = []
        for row in raw:
            if not isinstance(row, dict):
                continue
            name = str(row.get("name") or "").strip()
            category_id = str(row.get("category_id") or "").strip()
            group = categories.get(category_id, "")
            if (
                not name
                or self._is_promotional_name(name)
                or self._is_adult_entry(name, group)
            ):
                continue
            direct = str(row.get("direct_source") or "").strip()
            if direct and self._allowed_upstream(direct):
                url = direct
            else:
                try:
                    url = self._xtream_stream_url(
                        source,
                        "live",
                        row.get("stream_id"),
                        row.get("container_extension") or "ts",
                    )
                except ContentGatewayError:
                    continue
            channels.append({
                "name": name,
                "url": url,
                "group": group,
                "epg_id": str(row.get("epg_channel_id") or "").strip(),
                "logo": str(row.get("stream_icon") or "").strip(),
                "language": "",
                "headers": {},
            })
        return channels

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
        for source in self.sources:
            if self._xtream_config(source) is None:
                continue
            try:
                categories = self._category_map(source, "get_vod_categories")
                rows = self._xtream_json(source, "get_vod_streams", ttl=600)
                row = self._match_xtream_item(
                    rows,
                    tmdb_id=tmdb_id,
                    title=title,
                    year=year,
                    categories=categories,
                )
                if row is None:
                    continue
                direct = str(row.get("direct_source") or "").strip()
                if direct and self._allowed_upstream(direct):
                    upstream = direct
                else:
                    upstream = self._xtream_stream_url(
                        source,
                        "movie",
                        row.get("stream_id"),
                        row.get("container_extension") or "mp4",
                    )
                target_id = self._register_target(upstream)
                sources.append({
                    "provider": "POTV",
                    "real_url": self._proxy_url(target_id),
                    "language": "es-MX",
                    "quality": str(row.get("quality") or "").strip() or None,
                })
            except Exception:
                continue
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
        for source in self.sources:
            if self._xtream_config(source) is None:
                continue
            try:
                categories = self._category_map(source, "get_series_categories")
                rows = self._xtream_json(source, "get_series", ttl=600)
                series = self._match_xtream_item(
                    rows,
                    tmdb_id=tmdb_id,
                    title=title,
                    year=year,
                    categories=categories,
                )
                if series is None:
                    continue
                series_id = series.get("series_id")
                info = self._xtream_json(
                    source,
                    "get_series_info",
                    extra={"series_id": series_id},
                    ttl=600,
                )
                episodes = info.get("episodes") if isinstance(info, dict) else None
                if not isinstance(episodes, dict):
                    continue
                season_rows = episodes.get(str(int(season))) or episodes.get(int(season))
                if not isinstance(season_rows, list):
                    continue
                selected = None
                for row in season_rows:
                    if not isinstance(row, dict):
                        continue
                    row_episode = row.get("episode_num") or row.get("episode") or row.get("num")
                    try:
                        if int(row_episode) == int(episode):
                            selected = row
                            break
                    except (TypeError, ValueError):
                        continue
                if selected is None:
                    continue
                upstream = self._xtream_stream_url(
                    source,
                    "series",
                    selected.get("id") or selected.get("stream_id"),
                    selected.get("container_extension") or "mp4",
                )
                target_id = self._register_target(upstream)
                sources.append({
                    "provider": "POTV",
                    "real_url": self._proxy_url(target_id),
                    "language": "es-MX",
                    "quality": str(selected.get("quality") or "").strip() or None,
                })
            except Exception:
                continue
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
        return re.sub(r"[^a-z0-9+]+", " ", str(value).lower()).strip()

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
        seen = set()
        failures = 0
        for source in self.sources:
            if not self._allowed_upstream(source):
                failures += 1
                continue
            try:
                if self._xtream_config(source) is not None:
                    parsed = self._xtream_live_channels(source)
                else:
                    parsed = self._parse_m3u(self._source_document(source))
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

        sports = [
            channel
            for channel in all_channels
            if _SPORTS.search(
                f"{channel.get('name', '')} {channel.get('group', '')}"
            )
        ]
        metadata = self._metadata()
        guide = self._guide_payload(metadata)
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
