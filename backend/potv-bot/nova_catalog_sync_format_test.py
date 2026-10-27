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
