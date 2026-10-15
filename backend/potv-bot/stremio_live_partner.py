"""Opt-in, licensed Stremio Live API reader compatible with Kino's addons.

Reads Stremio JSON manifests/catalogs/streams. No execution of third-party JS,
no extraction of APK secrets, no automatic import of every channel, and no
redistribution until content owners approve the explicit channel ID allowlist.
"""
import ipaddress
import json
import re
import time
from pathlib import Path
from urllib.parse import quote, urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from urllib.error import HTTPError, URLError


class StremioLiveError(Exception):
    pass


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _https_public(url):
    try:
        u = urlsplit(str(url or "").strip())
    except ValueError:
        return False
    if u.scheme != "https" or not u.hostname or u.username or u.password:
        return False
    try:
        if not ipaddress.ip_address(u.hostname).is_global:
            return False
    except ValueError:
        if u.hostname.lower() in ("localhost", "localhost.localdomain"):
            return False
    return True


class StremioLivePartner:
    def __init__(self, *, manifest_url, catalog_id, allowed_ids,
                 allowed_stream_hosts, group="TV", opener=None, ttl=300):
        if not _https_public(manifest_url) or not urlsplit(manifest_url).path.endswith("/manifest.json"):
            raise ValueError("approved_stremio_manifest_https_required")
        if not re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", str(catalog_id)):
            raise ValueError("catalog_id_invalid")
        ids = [str(x).strip() for x in allowed_ids if str(x).strip()]
        if not ids or len(ids)>40:
            raise ValueError("explicit_channel_allowlist_required_max40")
        hosts = {
            str(x).lower().strip()
            for x in allowed_stream_hosts
            if str(x).strip()
        }
        if not hosts or any("/" in x or ":" in x or x.startswith(".") for x in hosts):
            raise ValueError("approved_stream_hosts_required")
        self.manifest_url = manifest_url
        self.catalog_id = str(catalog_id)
        self.allowed_ids = set(ids)
        self.allowed_stream_hosts = hosts
        self.group = str(group or "TV")[:90]
        self.opener = opener or build_opener(NoRedirects())
        self.ttl = max(30, int(ttl))
        self._cache = ()
        self._cache_at = 0.0

    @classmethod
    def from_file(cls, path, *, opener=None):
        if not path:
            return None
        f = Path(path)
        if not f.is_absolute() or not f.is_file():
            raise ValueError("approved_stremio_config_missing")
        raw = json.loads(f.read_text(encoding="utf8"))
        if not isinstance(raw, dict) or raw.get("enabled") is not True:
            return None
        return cls(
            manifest_url=raw["manifest_url"],
            catalog_id=raw["catalog_id"],
            allowed_ids=raw["allowed_ids"],
            allowed_stream_hosts=raw["allowed_stream_hosts"],
            group=raw.get("group") or "TV",
            opener=opener,
        )

    def _json(self, url):
        if not _https_public(url):
            raise StremioLiveError("invalid_provider_url")
        try:
            req = Request(url, headers={
                "Accept": "application/json",
                "User-Agent": "POTV-Authorized-Stremio-Bridge/1.0",
            })
            with self.opener.open(req, timeout=7) as response:
                original=urlsplit(url)
                actual=urlsplit(response.geturl())
                if original.hostname != actual.hostname:
                    raise StremioLiveError("provider_redirect_rejected")
                body = response.read(3*1024*1024+1)
            if len(body)>3*1024*1024:
                raise StremioLiveError("provider_response_too_large")
            parsed=json.loads(body.decode("utf8"))
            if not isinstance(parsed, dict):
                raise StremioLiveError("invalid_provider_data")
            return parsed
        except (OSError,HTTPError,URLError,TimeoutError,ValueError):
            raise StremioLiveError("provider_api_unavailable") from None

    def channels(self, *, force=False):
        now=time.monotonic()
        if not force and self._cache_at and now-self._cache_at<self.ttl:
            return [dict(x) for x in self._cache]
        manifest = self._json(self.manifest_url)
        supported = manifest.get("resources") or []
        resources = {str(x.get("name") if isinstance(x,dict) else x)
                     for x in supported}
        if not {"catalog","stream"}.issubset(resources) or "tv" not in (manifest.get("types") or []):
            raise StremioLiveError("unsupported_stremio_addon")
        cats = manifest.get("catalogs") or []
        if not any(isinstance(c,dict) and c.get("id")==self.catalog_id and c.get("type")=="tv"
                   for c in cats):
            raise StremioLiveError("catalog_id_not_in_manifest")
        root=self.manifest_url.rsplit("manifest.json",1)[0]
        catalog=self._json(urljoin(root, "catalog/tv/"+quote(self.catalog_id,safe="")+".json"))
        metas=catalog.get("metas")
        if not isinstance(metas,list):
            raise StremioLiveError("stremio_catalog_missing")
        result=[]
        seen_ids=set()
        # A sick addon must not hold POTV's entire TV catalog refresh.
        deadline=time.monotonic()+20
        for meta in metas[:5000]:
            if time.monotonic()>deadline:
                break
            if not isinstance(meta,dict):
                continue
            channel_id=str(meta.get("id") or "")
            if (channel_id not in self.allowed_ids or channel_id in seen_ids
                    or meta.get("type") not in (None,"tv")):
                continue
            seen_ids.add(channel_id)
            name=str(meta.get("name") or "").strip()
            if not name:continue
            try:
                streams=self._json(urljoin(root, "stream/tv/"+quote(channel_id,safe="")+".json")).get("streams",[])
            except StremioLiveError:
                continue
            if not isinstance(streams,list):continue
            urls=[]
            for item in streams:
                if not isinstance(item,dict):continue
                url=str(item.get("url") or "").strip()
                parsed=urlsplit(url)
                if not _https_public(url) or parsed.hostname.lower() not in self.allowed_stream_hosts:
                    continue
                if url not in urls:
                    urls.append(url)
            if not urls:continue
            logo=str(meta.get("poster") or meta.get("logo") or "")
            result.append({
                "name":name[:150],
                "group":self.group,
                "url":urls[0],
                "backups":urls[1:4],
                "logo":logo if _https_public(logo) else "",
                "language":str(meta.get("language") or "").strip()[:24],
                "headers":{},
                "epg_id":"",
            })
            if len(result)>=40:break
        self._cache=tuple(result)
        self._cache_at=now
        return [dict(x) for x in result]
