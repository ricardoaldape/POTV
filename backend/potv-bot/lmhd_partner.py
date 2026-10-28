"""Authorized LMHD REST API bridge for POTV.

Implements the API shapes confirmed in the partner-supplied LMHD Android APK.
This module never imports app-embedded credentials, retries denied sessions,
or exposes service tokens. A dedicated provider-issued token and device ID
must be installed separately as an access-restricted server JSON file.

The module performs NO work unless explicitly configured by POTV operations.
"""
import ipaddress
import json
import re
import unicodedata
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class PartnerApiError(Exception):
    """Sanitized error code: never contains URLs, tokens or partner responses."""

    def __init__(self, code):
        self.code = str(code)
        super().__init__(self.code)


class _NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        # Never forward a token in the query string to an unapproved host.
        return None


def _clean(value):
    return str(value or "").strip()


def _normalized(value):
    value = unicodedata.normalize("NFKD", _clean(value)).lower()
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", value)).strip()


def _year(value):
    text = _clean(value)
    return text[:4] if re.fullmatch(r"(?:19|20)\d{2}", text[:4]) else ""


def _valid_endpoint(url):
    try:
        parsed = urlsplit(url)
    except ValueError:
        return False
    if (
        parsed.scheme != "https"
        or not parsed.hostname
        or parsed.username
        or parsed.password
        or parsed.query
        or parsed.fragment
    ):
        return False
    try:
        ip = ipaddress.ip_address(parsed.hostname)
        if not ip.is_global:
            return False
    except ValueError:
        if parsed.hostname.lower() in ("localhost", "localhost.localdomain"):
            return False
    return parsed.path.endswith("/")


def _media_items(item):
    if not isinstance(item, dict):
        return []
    result = []
    qualities = item.get("qualities")
    if isinstance(qualities, list):
        for entry in qualities:
            if isinstance(entry, dict) and isinstance(entry.get("media"), dict):
                media = dict(entry["media"])
                media["quality"] = _clean(entry.get("label"))
                result.append(media)
    if isinstance(item.get("media"), dict):
        result.append(item["media"])
    return result


class LmhdPartner:
    """Provider-session client. No login bypass and no shared end-user secrets."""

    def __init__(self, *, base_url, token, device, user_agent="POTV-Partner/1.0",
                 opener=None):
        if not _valid_endpoint(base_url):
            raise ValueError("partner_base_must_be_https_directory")
        if not _clean(token) or not _clean(device):
            raise ValueError("dedicated_partner_token_and_device_required")
        self.base_url = base_url
        self.token = _clean(token)
        self.device = _clean(device)
        self.user_agent = _clean(user_agent)[:150] or "POTV-Partner/1.0"
        self.opener = opener or build_opener(_NoRedirects())

    @classmethod
    def from_file(cls, filename, *, opener=None):
        if not filename:
            return None
        path = Path(filename)
        if not path.is_absolute() or not path.is_file():
            raise ValueError("approved_partner_configuration_not_found")
        config = json.loads(path.read_text(encoding="utf8"))
        if not isinstance(config, dict) or config.get("enabled") is not True:
            return None
        # A provider may issue a named service account rather than a
        # long-lived token. Follow the app's public login contract and
        # refresh the session server-side; no APK/session scraping required.
        if config.get("username") and config.get("password"):
            return SessionLmhdPartner(
                base_url=config["base_url"],
                username=config["username"],
                password=config["password"],
                device=config["device"],
                opener=opener,
            )
        return cls(
            base_url=config["base_url"],
            token=config["token"],
            device=config["device"],
            user_agent=config.get("user_agent") or "POTV-Partner/1.0",
            opener=opener,
        )

    def _request(self, filename, **fields):
        if filename not in {
            "tv.php", "channels.php", "vod.php", "series.php",
            "stream.php", "heartbeat.php",
        }:
            raise PartnerApiError("unsupported_partner_route")
        params = {"token": self.token, "device": self.device}
        params.update(fields)
        base = urlsplit(self.base_url)
        # The app sends GET parameters to these routes. Keep credentials on
        # the server, never in an APK, logged exception, or public response.
        endpoint = urlunsplit((
            "https", base.netloc, base.path + filename, urlencode(params), ""
        ))
        try:
            request = Request(
                endpoint,
                headers={"User-Agent": self.user_agent, "Accept": "application/json"},
                method="GET",
            )
            with self.opener.open(request, timeout=8) as response:
                final = urlsplit(response.geturl())
                if final.hostname != base.hostname or final.scheme != "https":
                    raise PartnerApiError("partner_redirect_rejected")
                raw = response.read(4 * 1024 * 1024 + 1)
            if len(raw) > 4 * 1024 * 1024:
                raise PartnerApiError("partner_response_too_large")
            data = json.loads(raw.decode("utf8"))
        except HTTPError as error:
            if error.code in (401, 403):
                raise PartnerApiError("partner_session_denied") from None
            raise PartnerApiError("partner_http_unavailable") from None
        except (OSError, URLError, TimeoutError, ValueError):
            raise PartnerApiError("partner_network_unavailable") from None
        if not isinstance(data, dict):
            raise PartnerApiError("partner_response_invalid")
        if data.get("ok") is not True:
            raise PartnerApiError("partner_authorization_or_api_error")
        return data

    @staticmethod
    def _match(items, title, year=None):
        if not isinstance(items, list):
            return None
        target = _normalized(title)
        if not target:
            return None
        found = [
            entry for entry in items
            if isinstance(entry, dict)
            and _normalized(entry.get("title") or entry.get("name")) == target
        ]
        if year:
            matches = [x for x in found if _year(x.get("year")) == _year(year)]
            if matches:
                found = matches
            elif any(_year(x.get("year")) for x in found):
                return None
        # Do not silently play the wrong remake or a vaguely matching title.
        return found[0] if len(found) == 1 else None

    @staticmethod
    def _playable_media(media):
        if not isinstance(media, dict):
            return None
        url = _clean(media.get("url"))
        try:
            parsed = urlsplit(url)
        except ValueError:
            return None
        if parsed.scheme not in ("https", "http") or not parsed.hostname:
            return None
        if parsed.username or parsed.password:
            return None
        return {
            "url": url, "quality": _clean(media.get("quality")),
            "format": _clean(media.get("format")),
            "language": _clean(media.get("language")),
        }

    def tv_channels(self):
        """Map the separate TV-category endpoint into gateway TV rows."""
        payload = self._request("tv.php")
        categories = payload.get("categorias")
        if not isinstance(categories, list):
            return []
        channels = []
        for group in categories[:150]:
            if not isinstance(group, dict):
                continue
            group_name = _clean(group.get("nombre")) or "Televisión"
            rows = group.get("canales")
            if not isinstance(rows, list):
                continue
            for row in rows[:600]:
                if not isinstance(row, dict):
                    continue
                media = self._playable_media({"url": row.get("media")})
                name = _clean(row.get("nombre"))
                if not name or media is None:
                    continue
                provider_id = _clean(row.get("id"))
                epg_id = ("lmhd:" + provider_id) if (
                    provider_id.isdecimal() and int(provider_id) > 0
                ) else ""
                epg = []
                for program in (row.get("epg") or [])[:32]:
                    if not isinstance(program, dict):
                        continue
                    try:
                        start = int(program.get("s"))
                        end = int(program.get("e"))
                    except (TypeError, ValueError, OverflowError):
                        continue
                    title = _clean(program.get("t"))[:160]
                    # APK TvApi uses Unix seconds (EpgProg.start/stop).
                    # Reject invalid timestamps before converting to UTC.
                    if not (title and 946684800 <= start < end <= 4102444800
                            and end - start <= 16 * 3600):
                        continue
                    epg.append({
                        "title": title,
                        "starts_at": datetime.fromtimestamp(
                            start, timezone.utc).isoformat(),
                        "ends_at": datetime.fromtimestamp(
                            end, timezone.utc).isoformat(),
                    })
                channels.append({
                    "name": name,
                    "group": group_name,
                    "url": media["url"],
                    "logo": _clean(row.get("logo")),
                    "epg_id": epg_id,
                    "provider_id": provider_id,
                    "epg": epg,
                    "headers": {},
                })
        return channels

    def sports_events(self):
        """Only explicit events carrying a stream URL are playable."""
        payload = self._request("channels.php")
        result = []
        for row in payload.get("channels") or []:
            if not isinstance(row, dict):
                continue
            media = self._playable_media({"url": row.get("url")})
            name = _clean(row.get("name"))
            event_id = _clean(row.get("id"))
            if media is None or not name or not event_id or row.get("finalizado") in (1, True):
                continue
            kickoff = row.get("kickoff")
            try:
                if float(kickoff) <= 0:
                    continue
                when = datetime.fromtimestamp(float(kickoff), tz=timezone.utc)
                if not (2020 <= when.year <= 2100):
                    continue
            except (ValueError, TypeError, OverflowError):
                continue
            parts = re.split(r"\s+(?:vs?\.?)\s+|\s+-\s+", name, maxsplit=1, flags=re.I)
            if len(parts) != 2:
                continue
            result.append({
                "id": "lmhd:" + event_id,
                "sport": "Deportes",
                "competition": _clean(row.get("competencia")) or "Evento deportivo",
                "home": parts[0].strip(),
                "away": parts[1].strip(),
                "starts_at": when.isoformat(),
                "is_live": datetime.now(timezone.utc) >= when,
                "streams": [{"url": media["url"]}],
            })
        return result

    def movie_sources(self, *, title, year=None):
        """Search by exact title/year, then obtain current licensed media."""
        listing = self._request("vod.php", q=_clean(title))
        item = self._match(listing.get("items"), title, year)
        if item is None:
            return []
        try:
            provider_id = int(item.get("id"))
        except (TypeError, ValueError):
            return []
        if provider_id <= 0:
            return []
        detail = self._request("vod.php", id=provider_id).get("item")
        if not isinstance(detail, dict):
            return []
        if _normalized(detail.get("title")) != _normalized(title):
            return []
        if year and _year(detail.get("year")) not in ("", _year(year)):
            return []
        result = []
        unique = set()
        for media in _media_items(detail):
            candidate = self._playable_media(media)
            if candidate is not None and candidate["url"] not in unique:
                unique.add(candidate["url"])
                result.append(candidate)
        # Time-sensitive media tokens should be requested again for playback.
        if not result:
            refreshed = self._request("vod.php", tok=provider_id, q=0)
            candidate = self._playable_media(refreshed.get("media"))
            if candidate is not None:
                result.append(candidate)
        return result

    def episode_sources(self, *, title, season, episode, year=None):
        listing = self._request("series.php", q=_clean(title))
        item = self._match(listing.get("items"), title, year)
        if item is None:
            return []
        try:
            provider_id = int(item.get("id"))
            season = int(season)
            episode = int(episode)
            if min(provider_id, season, episode) <= 0:
                return []
        except (ValueError, TypeError):
            return []
        detail = self._request("series.php", id=provider_id).get("item")
        if not isinstance(detail, dict):
            return []
        if _normalized(detail.get("title")) != _normalized(title):
            return []
        for group in detail.get("seasons") or []:
            if not isinstance(group, dict) or group.get("n") != season:
                continue
            for row in group.get("episodes") or []:
                if not isinstance(row, dict) or row.get("n") != episode:
                    continue
                if row.get("locked") is True:
                    return []
                try:
                    ep_id = int(row.get("id"))
                except (ValueError, TypeError):
                    return []
                refreshed = self._request("series.php", tok=ep_id)
                candidate = self._playable_media(refreshed.get("media"))
                return [candidate] if candidate else []
        return []


class SessionLmhdPartner(LmhdPartner):
    """Dynamic service login through the LMHD API's normal login endpoint.

    Preserve the same TV/VOD/events normalization used for static tokens.
    Session renewal is delegated to the existing authorized-login client.
    """

    def __init__(self, *, base_url, username, password, device, opener=None):
        from partner_lmhd_api import LMHDPartnerAdapter
        self._session = LMHDPartnerAdapter(
            base_url=base_url, username=username, password=password,
            device=device, opener=opener.open if hasattr(opener, "open") else opener,
        )

    def _request(self, filename, **fields):
        from partner_lmhd_api import PartnerAccessError
        if filename not in {
            "tv.php", "channels.php", "vod.php", "series.php",
            "stream.php", "heartbeat.php",
        }:
            raise PartnerApiError("unsupported_partner_route")
        try:
            return self._session._authenticated(filename, fields)
        except PartnerAccessError:
            raise PartnerApiError("partner_session_denied") from None
