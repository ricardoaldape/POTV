"""Signed live playlists remain usable through full sports events.

This is a synthetic gateway test with no account information and no network.
"""
from unittest.mock import patch
from urllib.parse import urlsplit
from content_gateway import ContentGateway

gw = ContentGateway(sources=[], public_base="https://potv.example",
                    signing_secret=b"test-signing-only")

with patch("content_gateway.time.time", return_value=1_800_000_000):
    live = gw._channel_payload({
        "name": "Canal de prueba",
        "url": "https://cdn.example/live/master.m3u8",
        "group": "Deportes",
    })
    stream = live["hls_url"]
    target = stream.split("/stream/")[-1].split("?", 1)[0]
    assert gw._validate_signature(target, urlsplit(stream).query)
    playlist = gw._rewrite_hls(
        "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=600000\n"
        "sub/playlist.m3u8\n#EXTINF:6,\nvideo/00001.ts\n",
        "https://cdn.example/live/master.m3u8", {},
    )
    nested = [x for x in playlist.splitlines()
              if x.startswith("https://potv.example/api/v1/content/stream/")]
    assert len(nested) == 2

with patch("content_gateway.time.time", return_value=1_800_003_600):
    assert gw._validate_signature(target, urlsplit(stream).query)
    variant_id = nested[0].split("/stream/")[-1].split("?", 1)[0]
    segment_id = nested[1].split("/stream/")[-1].split("?", 1)[0]
    assert gw._validate_signature(variant_id, urlsplit(nested[0]).query)
    assert not gw._validate_signature(segment_id, urlsplit(nested[1]).query)

with patch("content_gateway.time.time", return_value=1_800_022_000):
    assert not gw._validate_signature(target, urlsplit(stream).query)
    assert not gw._validate_signature(variant_id, urlsplit(nested[0]).query)

print("PASS: signed live HLS manifests last through matches; short-lived media segments expire")
