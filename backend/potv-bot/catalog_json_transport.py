"""Bounded, opt-in HTTP compression for large first-party TV catalogs.

Only the catalog route uses this helper. Authentication, account and VOD
responses retain their existing uncompressed behavior. Compression is based
on Accept-Encoding and does not touch signed upstream media streams.
"""
import gzip
import json


def accepts_gzip(header):
    for token in str(header or "").split(","):
        parts = [part.strip() for part in token.split(";")]
        if not parts or parts[0].lower() != "gzip":
            continue
        quality = 1.0
        for part in parts[1:]:
            if part.lower().startswith("q="):
                try:
                    quality = float(part[2:])
                except ValueError:
                    quality = 0.0
        return quality > 0
    return False


def encode_catalog(obj, accept_encoding, *, min_bytes=96 * 1024):
    raw = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(raw) < min_bytes or not accepts_gzip(accept_encoding):
        return raw, False
    packed = gzip.compress(raw, compresslevel=1, mtime=0)
    if len(packed) >= len(raw):
        return raw, False
    return packed, True
