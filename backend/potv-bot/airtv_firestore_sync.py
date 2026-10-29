#!/usr/bin/env python3
"""Synchronize AirTV's Firestore channels into POTV's private catalog.

Only a separate, developer-issued Firestore service account may read data.
No APK sessions, keys, or stream URLs are embedded in the Android client.
"""
import hashlib
import ipaddress
import json
import os
import re
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen

MAX_CHANNELS = 5000
MAX_BYTES = 8 * 1024 * 1024
ALLOWED_STATUS = {"", "activo", "active", "1", "true", "on", "online", "disponible"}


def field_value(raw):
    if not isinstance(raw, dict):
        return None
    if "stringValue" in raw:
        return str(raw["stringValue"])
    if "integerValue" in raw:
        return str(raw["integerValue"])
    if "booleanValue" in raw:
        return raw["booleanValue"]
    if "arrayValue" in raw:
        values = raw["arrayValue"].get("values", [])
        return [field_value(v) for v in values[:20]] if isinstance(values, list) else []
    return None


def public_url(value):
    if not isinstance(value, str) or len(value) > 2048:
        return False
    parsed = urlsplit(value.strip())
    if parsed.scheme not in ("https", "http") or not parsed.hostname:
        return False
    if parsed.username or parsed.password:
        return False
    host = parsed.hostname.lower()
    if host in ("localhost", "localhost.localdomain") or host.endswith(".local"):
        return False
    try:
        if not ipaddress.ip_address(host).is_global:
            return False
    except ValueError:
        pass
    return True


def channel_from_firestore(doc):
    if not isinstance(doc, dict):
        return None
    raw_fields = doc.get("fields") or {}
    if not isinstance(raw_fields, dict):
        return None
    f = {k: field_value(v) for k, v in raw_fields.items()}
    if str(f.get("ESTADO") or "").strip().casefold() not in ALLOWED_STATUS:
        return None
    name = str(f.get("NOMBRE") or "").strip()[:160]
    group = str(f.get("SUBMENU") or f.get("MENU") or "TV").strip()[:80]
    country = str(f.get("PAIS") or "").strip()[:60]
    if not name or any(word in (name + " " + group).casefold()
                       for word in ("adultos", "pornografía", "xxx", "18+")):
        return None
    listed = f.get("ENLACES")
    listed = listed if isinstance(listed, list) else []
    upstream = []
    for value in [f.get("URL"), *listed[:12]]:
        if public_url(value) and value not in upstream:
            upstream.append(value)
    if not upstream:
        return None
    doc_id = str(doc.get("name") or "").rsplit("/", 1)[-1].strip()
    if not re.fullmatch(r"[A-Za-z0-9_\-]{1,180}", doc_id):
        return None
    stable = "airtv:" + hashlib.sha256(doc_id.encode("utf-8")).hexdigest()[:20]
    logo = f.get("IMAGENBANER") or f.get("IMAGEN") or ""
    return {
        "id": stable, "name": name,
        "group": (group + (" | " + country if country else ""))[:140],
        "url": upstream[0], "backup_urls": upstream[1:5],
        "logo": logo if public_url(logo) and logo.startswith("https://") else "",
        "epg_id": "",
    }


def oauth_token(service, *, transport=urlopen):
    if service.get("token_uri", "https://oauth2.googleapis.com/token") != \
            "https://oauth2.googleapis.com/token":
        raise ValueError("unapproved_oauth_endpoint")
    for key in ("private_key", "client_email", "project_id"):
        if not isinstance(service.get(key), str) or not service[key]:
            raise ValueError("missing_service_account_field")
    import jwt
    now = int(time.time())
    assertion = jwt.encode({
        "iss": service["client_email"],
        "scope": "https://www.googleapis.com/auth/datastore",
        "aud": "https://oauth2.googleapis.com/token",
        "iat": now, "exp": now + 2700,
    }, service["private_key"], algorithm="RS256")
    request = Request("https://oauth2.googleapis.com/token",
                      data=urlencode({
                          "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                          "assertion": assertion,
                      }).encode("ascii"),
                      headers={"Content-Type": "application/x-www-form-urlencoded"})
    with transport(request, timeout=12) as response:
        raw = response.read(65537)
    if len(raw) > 65536:
        raise ValueError("oauth_response_too_large")
    reply = json.loads(raw)
    token = reply.get("access_token")
    if not isinstance(token, str) or not token:
        raise ValueError("oauth_token_unavailable")
    return token


def firestore_channels(project, token, *, transport=urlopen):
    if not re.fullmatch(r"[a-z][a-z0-9-]{2,100}", project):
        raise ValueError("invalid_project_id")
    rows, next_page, visited = [], "", set()
    for _ in range(25):
        query = {"pageSize": "250"}
        if next_page:
            query["pageToken"] = next_page
        url = ("https://firestore.googleapis.com/v1/projects/" + project +
               "/databases/(default)/documents/channels?" + urlencode(query))
        request = Request(url, headers={
            "Authorization": "Bearer " + token, "Accept": "application/json",
        })
        with transport(request, timeout=20) as response:
            raw = response.read(4 * 1024 * 1024 + 1)
        if len(raw) > 4 * 1024 * 1024:
            raise ValueError("firestore_page_too_large")
        data = json.loads(raw)
        if not isinstance(data, dict):
            raise ValueError("invalid_firestore_response")
        docs = data.get("documents") or []
        if not isinstance(docs, list):
            raise ValueError("invalid_firestore_documents")
        for doc in docs:
            channel = channel_from_firestore(doc)
            if channel and channel["id"] not in visited:
                visited.add(channel["id"])
                rows.append(channel)
            if len(rows) >= MAX_CHANNELS:
                break
        if len(rows) >= MAX_CHANNELS:
            break
        future_page = data.get("nextPageToken") or ""
        if not future_page:
            break
        if future_page == next_page:
            raise ValueError("repeating_firestore_page")
        next_page = str(future_page)
    return rows


def write_snapshot(output, channels):
    if not isinstance(channels, list):
        raise ValueError("invalid_airtv_catalog")
    rows = channels[:MAX_CHANNELS]
    revision = hashlib.sha256(
        json.dumps(rows, ensure_ascii=False, sort_keys=True, separators=(",", ":")
                   ).encode("utf-8")).hexdigest()[:20]
    payload = {
        "version": 1, "provider": "airtv",
        "updated_at": datetime.now(timezone.utc).isoformat(),
        "revision": revision, "channels": rows,
    }
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(body) > MAX_BYTES:
        raise ValueError("airtv_catalog_too_large")
    target = Path(output)
    target.parent.mkdir(parents=True, exist_ok=True)
    path = ""
    try:
        with tempfile.NamedTemporaryFile(mode="wb", dir=target.parent,
                                         prefix=".airtv-", delete=False) as handle:
            path = handle.name
            os.chmod(path, 0o600)
            handle.write(body)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(path, target)
        os.chmod(target, 0o600)
    finally:
        if path and os.path.exists(path):
            os.unlink(path)
    return len(rows)


def run():
    service_path = os.getenv("POTV_AIRTV_SERVICE_FILE", "").strip()
    output = os.getenv("POTV_AIRTV_SYNC_FILE", "").strip()
    if not service_path or not output or not Path(service_path).is_file():
        print("AIRTV_SYNC_NOT_CONFIGURED")
        return 0
    try:
        service = json.loads(Path(service_path).read_text(encoding="utf-8"))
        if service.get("type") != "service_account":
            raise ValueError("airtv_service_account_required")
        token = oauth_token(service)
        rows = firestore_channels(service["project_id"], token)
        print("AIRTV_SYNC_OK channels=%d" % write_snapshot(output, rows))
        return 0
    except Exception as error:
        print("AIRTV_SYNC_FAILED type=%s" % type(error).__name__)
        return 1


if __name__ == "__main__":
    raise SystemExit(run())
