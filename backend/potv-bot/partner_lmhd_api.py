"""Opt-in LMHD-style partner integration; credentials never leave POTV backend.

Protocol documented from partner-supplied APK interfaces. No authentication
bypass, embedded secrets, or scraping of other users' sessions. The partner
must provision a POTV service account and authorize API redistribution.
"""
import ipaddress
import json
import os
import threading
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urljoin, urlsplit
from urllib.request import Request, urlopen


class PartnerAccessError(RuntimeError):
    pass


def _public_https(value):
    parsed = urlsplit(str(value).strip())
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        return False
    host = parsed.hostname.lower()
    if host == "localhost" or host.endswith((".local", ".internal")):
        return False
    try:
        ip = ipaddress.ip_address(host)
        return ip.is_global
    except ValueError:
        return True


class LMHDPartnerAdapter:
    """LMHD TV/VOD/series API client. No access without partner credentials."""

    def __init__(self, *, base_url, username, password, device, opener=None):
        base = str(base_url or "").strip().rstrip("/") + "/"
        if not _public_https(base) or urlsplit(base).query or urlsplit(base).fragment:
            raise PartnerAccessError("partner_https_base_required")
        if not all(str(x).strip() for x in (username, password, device)):
            raise PartnerAccessError("partner_service_credentials_missing")
        self.base = base
        self._username = str(username)
        self._password = str(password)
        self._device = str(device)
        self._opener = opener or urlopen
        self._lock = threading.RLock()
        self._token = None
        self._token_at = 0.0

    @classmethod
    def from_environment(cls):
        keys = ("POTV_LMHD_API_BASE_URL", "POTV_LMHD_SERVICE_USERNAME",
                "POTV_LMHD_SERVICE_PASSWORD", "POTV_LMHD_SERVICE_DEVICE")
        vals = [os.getenv(key, "").strip() for key in keys]
        if not any(vals):
            return None
        if not all(vals):
            raise PartnerAccessError("partner_configuration_incomplete")
        return cls(base_url=vals[0], username=vals[1], password=vals[2], device=vals[3])

    def _json(self, route, params=None, form=None):
        if route not in {"login.php", "heartbeat.php", "channels.php",
                         "tv.php", "vod.php", "series.php", "stream.php"}:
            raise PartnerAccessError("unknown_partner_endpoint")
        url = urljoin(self.base, route)
        if params:
            url += "?" + urlencode(params)
        req = Request(url, data=(urlencode(form).encode("utf-8") if form is not None else None),
                      headers={"Accept": "application/json",
                               "Content-Type": "application/x-www-form-urlencoded",
                               "User-Agent": "POTV-AuthorizedPartner/1.0"})
        try:
            with self._opener(req, timeout=9) as response:
                raw = response.read(2_000_001)
                if len(raw) > 2_000_000:
                    raise PartnerAccessError("partner_response_too_large")
                value = json.loads(raw.decode("utf-8"))
        except (HTTPError, URLError, TimeoutError, ValueError, OSError) as exc:
            # Never expose request URLs (which may contain bearer tokens).
            raise PartnerAccessError("partner_request_failed") from None
        if not isinstance(value, dict):
            raise PartnerAccessError("partner_invalid_json")
        return value

    def _login(self):
        data = self._json("login.php", form={
            "username": self._username, "password": self._password})
        if data.get("ok") is False:
            raise PartnerAccessError("partner_login_rejected")
        token = data.get("token")
        if not isinstance(token, str) or not token.strip():
            raise PartnerAccessError("partner_token_missing")
        self._token = token
        self._token_at = time.monotonic()
        return token

    def _authenticated(self, route, extra=None):
        with self._lock:
            token = self._token if time.monotonic() - self._token_at < 3600 else None
            if token is None:
                token = self._login()
            params = {"token": token, "device": self._device}
            params.update(extra or {})
            data = self._json(route, params=params)
            if data.get("ok") is False:
                self._token = None
                raise PartnerAccessError("partner_authorization_rejected")
            return data

    def raw_channels(self):
        return self._authenticated("tv.php")

    def raw_live_guide(self):
        return self._authenticated("channels.php")

    def raw_movies(self):
        return self._authenticated("vod.php")

    def raw_series(self):
        return self._authenticated("series.php")

    def movie_detail(self, partner_item_id):
        if not str(partner_item_id).isdigit():
            raise PartnerAccessError("invalid_movie_id")
        return self._authenticated("vod.php", {"id": str(partner_item_id)})

    def series_detail(self, partner_item_id):
        if not str(partner_item_id).isdigit():
            raise PartnerAccessError("invalid_series_id")
        return self._authenticated("series.php", {"id": str(partner_item_id)})

    @staticmethod
    def normalize_tv(raw):
        """Flatten category/canales rows with valid HTTPS video URLs only.

        Entries with only opaque IDs are retained by the adapter's raw API
        but not falsely advertised as playable to Android.
        """
        categories = raw.get("categorias") or raw.get("categories") or []
        if not isinstance(categories, list):
            return []
        result = []
        seen = set()
        for group in categories[:120]:
            if not isinstance(group, dict):
                continue
            name = str(group.get("nombre") or group.get("name") or "").strip()
            feeds = group.get("canales") or group.get("channels") or []
            if not isinstance(feeds, list):
                continue
            for item in feeds[:400]:
                if not isinstance(item, dict):
                    continue
                title = str(item.get("nombre") or item.get("name") or item.get("title") or "").strip()
                media = item.get("media")
                if isinstance(media, dict):
                    direct = media.get("url") or media.get("stream_url")
                elif isinstance(media, str):
                    direct = media
                else:
                    direct = item.get("url") or item.get("stream_url")
                if not title or not direct or not _public_https(direct):
                    continue
                key = (title.casefold(), str(direct))
                if key in seen:
                    continue
                seen.add(key)
                result.append({
                    "name": title, "group": name or "TV",
                    "url": str(direct),
                    "logo": str(item.get("logo") or "") if _public_https(item.get("logo")) else "",
                    "epg_id": str(item.get("epg") or ""),
                })
        return result
