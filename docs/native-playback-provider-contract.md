# POTV: partner-compatible native player contract

POTV owns the player UI. A third-party HTML/iframe page cannot be
reliably controlled by POTV, and must not be mistaken for a video source.

## Source response

An authorized provider adapter may return:

~~~json
{
  "streams": [{
    "name": "Partner stream",
    "stream_url": "https://cdn.example.test/master.m3u8",
    "content_type": "application/vnd.apple.mpegurl",
    "language": "es-419",
    "quality": "adaptive",
    "headers": {},
    "embed_url": "https://player.example.test/embed/123"
  }]
}
~~~

- Direct HLS, DASH, MP4, or other supported, authorized streams play
  through Media3 / media_kit with POTV controls.
- Expiring URLs and request headers come from the provider's approved
  playback API and must never be logged or persisted as credentials.
- The distinct embed URL becomes a last-resort HTML fallback, but CDN
  Authorization headers are NOT forwarded to that HTML origin.
- Quality, language and subtitle options depend on the available tracks.
- HTML-only cross-origin iframes require a supported provider SDK/API for
  truly controllable playback. Otherwise they remain a limited fallback.
- Do not defeat DRM/access controls or extract signed credentials from a
  third-party player; use a licensor-approved playback interface.

## Playback policy

1. Rank native sources before embedded HTML pages.
2. Try the next native source on error and retain VOD playback position.
3. Reserve WebView for degraded fallback; avoid claiming unavailable controls.
4. For a strict commercial policy, exclude HTML-only sources and show
   a clear unavailable-source message instead of a fake controller.
