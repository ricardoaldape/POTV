"""Verify unreachable Xtream providers fail fast without repeated blocking calls."""
from content_gateway import ContentGateway,ContentGatewayError
from time import monotonic

source="http://partner.example:8880/get.php?username=test&password=secret&type=m3u_plus"
g=ContentGateway(sources=[source], public_base="https://potv.example",signing_secret=b"local-test")
calls=[]
def offline(url, *, timeout=25):
    calls.append((url,timeout))
    raise TimeoutError("offline")
g._fetch_json=offline
before=monotonic()
for i in range(2):
    try:
        g._xtream_json(source,"get_vod_categories")
        assert False,"Unreachable provider was treated as available"
    except (TimeoutError,ContentGatewayError):
        pass
assert len(calls)==1,f"Unexpected repeat calls to offline provider: {len(calls)}"
assert calls[0][1]==6,"Xtream request should have short timeout"
assert monotonic()-before<1,"Offline provider must return quickly"
print("PASS: Xtream timeout=6s and 90s failure circuit breaker")

# A partner API failure must not re-fetch its equally inaccessible M3U.
g._fallback_movie_entry=lambda *a,**k: (_ for _ in ()).throw(AssertionError("unexpected movie M3U retry"))
g._fallback_series_entry=lambda *a,**k: (_ for _ in ()).throw(AssertionError("unexpected series M3U retry"))
assert g.resolve_movie(tmdb_id="550",title="Movie")["sources"]==[]
assert g.resolve_series_episode(tmdb_id="1",title="Series",season=1,episode=1)["sources"]==[]
print("PASS: VOD endpoints terminate fast and do not repeat failed M3U calls")
