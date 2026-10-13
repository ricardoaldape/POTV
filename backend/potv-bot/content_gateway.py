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
from urllib.parse import parse_qs, quote, urljoin, urlsplit
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
            if not name or not self._allowed_upstream(line):
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
