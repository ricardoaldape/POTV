"""Opt-in NOVA interoperability client.

Only use the HTTPS provider API with a POTV-issued service session. Never reuse
APK-embedded credentials or publish raw partner tokens into client catalogs.
"""
import json
import ipaddress
import re
from pathlib import Path
from urllib.parse import urlencode, urljoin, urlsplit
from urllib.error import HTTPError
from urllib.request import Request, build_opener, HTTPRedirectHandler


def _private_ip(host):
    try:
        address = ipaddress.ip_address(host)
        return not address.is_global
    except ValueError:
        return False


class _NoPartnerRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        # Never forward a service Authorization header to redirected domains.
        return None


class NovaPartnerError(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


class NovaPartner:
    def __init__(self, *, base_url, access_token=None,
                 allow_anonymous_catalog=False, opener=None, timeout=8):
        raw = str(base_url).strip()
        uri = urlsplit(raw)
        if (
            uri.scheme != "https" or not uri.hostname
            or uri.username or uri.password or uri.query or uri.fragment
            or not raw.endswith("/")
            or uri.hostname.lower() == "localhost"
            or uri.hostname.endswith(".local")
            or _private_ip(uri.hostname)
        ):
            raise ValueError("NOVA service requires a clean HTTPS API root ending /")
        self.base_url = raw
        self.host = uri.hostname.lower()
        token = str(access_token or "").strip()
        if "\n" in token or "\r" in token:
            raise ValueError("Invalid service access token")
        if not token and not allow_anonymous_catalog:
            raise ValueError("Service token or explicitly allowed public provider feed required")
        self._token = token
        self._opener = opener or build_opener(_NoPartnerRedirects())
        self.timeout = min(15, max(1, int(timeout)))

    @classmethod
    def from_file(cls, path, *, opener=None):
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError("Invalid NOVA service JSON")
        return cls(
            base_url=data.get("api_base_url", ""),
            access_token=data.get("service_access_token", ""),
            allow_anonymous_catalog=data.get("allow_anonymous_catalog") is True,
            opener=opener,
        )

    def _get(self, route, query=None):
        if not route or route.startswith("/") or ".." in route:
            raise NovaPartnerError("invalid_route")
        target = urljoin(self.base_url, route)
        uri = urlsplit(target)
        if uri.scheme != "https" or uri.hostname.lower() != self.host:
            raise NovaPartnerError("unexpected_upstream")
        if query:
            target += "?" + urlencode(query)
        req = Request(target, headers={
            "Accept": "application/json",
            **({"Authorization": "Bearer " + self._token} if self._token else {}),
            "User-Agent": "POTV-Nova-Connector/1.0",
        })
        try:
            with self._opener.open(req, timeout=self.timeout) as response:
                if getattr(response, "status", 200) != 200:
                    raise NovaPartnerError("upstream_status")
                cap = (24 if route == "channels/all_lite" else 4) * 1024 * 1024
                raw = response.read(cap + 1)
            if len(raw) > cap:
                raise NovaPartnerError("payload_too_large")
            return json.loads(raw)
        except NovaPartnerError:
            raise
        except HTTPError as exc:
            # Never retry or fall back around an upstream 401/402/403 decision.
            if exc.code in (401, 402, 403):
                raise NovaPartnerError("upstream_denied") from None
            raise NovaPartnerError("upstream_unavailable") from None
        except Exception as exc:
            # Never log the request headers, bearer token or signed media URLs.
            raise NovaPartnerError("upstream_unavailable") from exc

    @staticmethod
    def _payload(raw):
        if isinstance(raw, dict):
            return raw.get("data", raw)
        return raw

    @classmethod
    def _rows(cls, raw):
        data = cls._payload(raw)
        if isinstance(data, list):
            return data
        if isinstance(data, dict):
            for key in ("items", "results", "channels", "movies", "series",
                        "anime", "content", "sources", "streams", "data"):
                if isinstance(data.get(key), list):
                    return data[key]
        return []

    @staticmethod
    def _valid_media_url(value):
        if not isinstance(value, str):
            return None
        p = urlsplit(value.strip())
        if p.scheme != "https" or not p.hostname or p.username or p.password:
            return None
        return value.strip()

    @classmethod
    def _source_urls(cls, raw):
        payload = cls._payload(raw)
        if isinstance(payload, dict):
            first = (payload.get("primary_url") or payload.get("stream_url")
                     or payload.get("hls_url") or payload.get("url")
                     or payload.get("real_url"))
            backup = payload.get("backup_urls") or payload.get("alternatives") or []
            candidates = [first, *backup] if isinstance(backup, list) else [first]
            if not first:
                candidates.extend(cls._rows(raw))
        elif isinstance(payload, list):
            candidates = payload
        else:
            candidates = []
        result = []
        for item in candidates:
            if isinstance(item, dict):
                item = (item.get("url") or item.get("stream_url")
                        or item.get("primary_url") or item.get("real_url"))
            url = cls._valid_media_url(item)
            if url and url not in result:
                result.append(url)
        return result

    @staticmethod
    def _positive_id(value):
        number = int(value)
        if number <= 0:
            raise ValueError("Invalid media ID")
        return number

    def movies(self, *, skip=0, limit=100):
        return self._rows(self._get("movies/", {
            "skip": max(0, int(skip)), "limit": min(100, max(1, int(limit)))
        }))

    def series(self, *, skip=0, limit=100):
        return self._rows(self._get("series/", {
            "skip": max(0, int(skip)), "limit": min(100, max(1, int(limit)))
        }))

    def anime(self, *, skip=0, limit=100):
        return self._rows(self._get("anime/", {
            "skip": max(0, int(skip)), "limit": min(100, max(1, int(limit)))
        }))

    def channels(self):
        return self._rows(self._get("channels/all_lite"))

    def channel_streams(self, channel_id):
        identifier = str(channel_id or "")
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,80}", identifier):
            raise ValueError("Invalid channel identifier")
        return self._source_urls(self._get("channels/stream/" + identifier))

    def _source_items_from_routes(self, routes, query):
        """Prefer the current VOD API, then NOVA's documented legacy route.

        A 401/402/403 is an entitlement decision and must never be retried
        against a second endpoint. Only unsupported or empty route responses
        can trigger the known compatible fallback.
        """
        for route in routes:
            try:
                response = self._get(route, query)
            except NovaPartnerError as exc:
                if exc.code == "upstream_denied":
                    raise
                continue
            rows = self._rows(response)
            if rows:
                return rows
            payload = self._payload(response)
            if isinstance(payload, dict):
                # A direct stream response is valid; empty catalogs are not.
                if any(payload.get(key) for key in (
                    "primary_url", "stream_url", "hls_url", "url",
                    "real_url", "embed_url",
                )):
                    return [payload]
        return []

    def sports_now_next(self, channel_ids, *, timezone="America/Mexico_City"):
        """NOVA 1.2.9 POST guide/now-next using only approved channel IDs.

        Return only provider program metadata, not authorization headers or
        playback URLs. Never attempt alternate endpoints after a denial.
        """
        if (not isinstance(channel_ids, (tuple, list)) or
                not 1 <= len(channel_ids) <= 40 or
                any(type(value) is not int or value <= 0 for value in channel_ids)):
            raise ValueError("Invalid guide channel identifiers")
        if timezone not in ("America/Mexico_City", "UTC"):
            raise ValueError("Unexpected guide timezone")
        path = "channels/guide/now-next"
        target = urljoin(self.base_url, path)
        parsed = urlsplit(target)
        if parsed.scheme != "https" or parsed.hostname != self.host:
            raise NovaPartnerError("unexpected_upstream")
        payload = json.dumps({
            "channel_ids": list(dict.fromkeys(channel_ids)),
            "timezone": timezone,
        }, separators=(",", ":")).encode("utf-8")
        request = Request(target, data=payload, method="POST", headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "POTV-Nova-Connector/1.0",
            **({"Authorization": "Bearer " + self._token}
               if self._token else {}),
        })
        try:
            with self._opener.open(request, timeout=self.timeout) as response:
                if getattr(response, "status", 200) != 200:
                    raise NovaPartnerError("upstream_status")
                raw = response.read(1024 * 1024 + 1)
            if len(raw) > 1024 * 1024:
                raise NovaPartnerError("payload_too_large")
            rows = self._rows(json.loads(raw))
            return rows[:40]
        except NovaPartnerError:
            raise
        except HTTPError as exc:
            if exc.code in (401, 402, 403):
                raise NovaPartnerError("upstream_denied") from None
            raise NovaPartnerError("upstream_unavailable") from None
        except (OSError, ValueError, TypeError):
            raise NovaPartnerError("upstream_unavailable") from None

    def movie_source_items(self, tmdb_id, *, title=None, year=None):
        item_id = str(self._positive_id(tmdb_id))
        query = {"language": "es-MX",
                 **({"title": title} if title else {}),
                 **({"year": str(year)} if year else {})}
        return self._source_items_from_routes(
            ("vod/sources/movie/" + item_id, "sources/movie/" + item_id),
            query,
        )

    def movie_sources(self, tmdb_id, *, title=None, year=None):
        return self._source_urls(self.movie_source_items(
            tmdb_id, title=title, year=year
        ))

    def episode_source_items(self, tmdb_id, season, episode, *,
                             title=None, year=None, is_anime=False):
        a,b,c = (self._positive_id(v) for v in (tmdb_id,season,episode))
        query = {"language": "es-MX",
                 **({"title": title} if title else {}),
                 **({"year": str(year)} if year else {}),
                 **({"is_anime": "true"} if is_anime else {})}
        routes = [f"vod/sources/tv/{a}/{b}/{c}"]
        if is_anime:
            routes.append(f"sources/anime/{a}/{b}/{c}")
        routes.append(f"sources/tv/{a}/{b}/{c}")
        return self._source_items_from_routes(routes, query)

    def episode_sources(self, tmdb_id, season, episode, *,
                        title=None, year=None, is_anime=False):
        return self._source_urls(self.episode_source_items(
            tmdb_id, season, episode, title=title, year=year,
            is_anime=is_anime,
        ))

    def app_version(self):
        return self._payload(self._get("app/version"))
