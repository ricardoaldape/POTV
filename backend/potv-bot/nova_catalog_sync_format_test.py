"""Regression for native playback of NOVA extensionless and iframe feeds."""
from nova_catalog_sync import enrich_stream_formats

rows = [
    {"id":"nova:1","name":"ESPN","url":"https://media.example/live",
     "is_sports":True,"backup_urls":[]},
    {"id":"nova:2","name":"MLB Network","url":"https://iframe.example/page",
     "is_sports":True,"backup_urls":["https://iframe.example/backup",
                                      "https://media.example/mlb"]},
    {"id":"nova:3","name":"Bad iframe","url":"https://iframe.example/bad",
     "is_sports":True,"backup_urls":["https://iframe.example/bad-backup"]},
    {"id":"nova:4","name":"Ordinary","url":"https://media.example/tv.ts",
     "is_sports":False,"backup_urls":[]},
]
upstream = [
    {"id":"1","is_iframe":False},
    {"id":"2","is_iframe":True},
    {"id":"3","is_iframe":True},
    {"id":"4","is_iframe":False},
]
checked=[]
def probe(url):
    checked.append(url)
    return {
        "https://media.example/live":"hls",
        "https://media.example/mlb":"ts",
    }.get(url)

out, metrics = enrich_stream_formats(rows, upstream, probe=probe)
assert len(out)==3, out
assert out[0]["format"]=="hls"
assert out[1]["url"]=="https://media.example/mlb"
assert out[1]["format"]=="ts"
assert out[1]["backup_urls"]==[]
assert out[2]["url"]=="https://media.example/tv.ts"
assert len(checked)==4, checked
assert metrics["iframe_without_native_backup"]==1
print("PASS: native iframe backup promotion and extensionless HLS detection")


# The first sync probes unknown channels, later syncs reuse their format.
general=[{"id":"nova:20","name":"General channel",
          "url":"https://media.example/extensionless",
          "is_sports":False,"backup_urls":[]}]
general_source=[{"id":"20","is_iframe":False}]
count=[]
def general_probe(url):
    count.append(url)
    return "ts"
first, _=enrich_stream_formats(general,general_source,probe=general_probe,now=10000)
assert first[0]["format"]=="ts" and len(count)==1
second, info=enrich_stream_formats(general,general_source,probe=general_probe,
                                   previous=first,now=10050)
assert second[0]["format"]=="ts" and len(count)==1
assert info["format_cached"]==1
# A changed upstream URL must invalidate the cached transport.
changed=[{**general[0],"url":"https://media.example/new-stream"}]
third, info=enrich_stream_formats(changed,general_source,probe=general_probe,
                                  previous=first,now=10070)
assert third[0]["format"]=="ts" and len(count)==2
# A failed probe is not retried on every 30-minute sync.
def failed_probe(url):
    count.append(url)
    return None
failed, _=enrich_stream_formats(general,general_source,probe=failed_probe,
                                now=20000)
retry, _=enrich_stream_formats(general,general_source,probe=failed_probe,
                               previous=failed,now=20060)
assert len(count)==3
assert retry[0]["format_probe_at"]==20000
print("PASS: incremental general-TV format cache, URL invalidation and backoff")


# CDN redirects are common for legitimate MPEG-TS live channels. Reject
# private IP redirects and never forward any original credentials.
from unittest.mock import patch
from urllib.request import Request
from nova_catalog_sync import _SafeMediaRedirect
handler=_SafeMediaRedirect()
request=Request("https://media.example/original",headers={
    "Authorization":"Bearer do-not-forward",
    "Cookie":"private-session=abc",
})
assert handler.redirect_request(request,None,302,"Found",{},
                                "http://127.0.0.1/admin") is None
with patch("nova_catalog_sync._public_media_url",return_value=True):
    nxt=handler.redirect_request(request,None,302,"Found",{},
                                 "https://cdn.example/live")
    assert nxt is not None
    assert nxt.get_header("Authorization") is None
    assert nxt.get_header("Cookie") is None
    assert nxt.potv_redirect_hops==1
    nxt.potv_redirect_hops=3
    assert handler.redirect_request(nxt,None,302,"Found",{},
                                    "https://cdn.example/again") is None
print("PASS: public CDN redirects permitted, private redirects denied")


# A detector upgrade must recheck recent failures instead of retaining a
# stale backoff that prevents NFL Network from gaining format=ts.
new_retry,_=enrich_stream_formats(general,general_source,probe=general_probe,
                                  previous=failed,now=20070,
                                  recheck_failures=True)
assert new_retry[0]["format"]=="ts"
assert len(count)==4
print("PASS: detector upgrade invalidates failed-probe backoff")
