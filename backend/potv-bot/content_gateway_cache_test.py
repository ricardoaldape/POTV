"""Regression tests for POTV stale-while-revalidate content catalog."""
import copy, threading, time
from urllib.parse import parse_qs, urlsplit
from content_gateway import ContentGateway

source="https://partner.example/get.php?username=smoke&password=test&type=m3u_plus"
g=ContentGateway(sources=[source],public_base="https://potv.example",signing_secret=b"testonly")
tid=g._register_target("https://cdn.example/live/video.m3u8")
u=g._proxy_url(tid,lifetime=1)
sample={"data":{"revision":"one","channels":[{"id":"one","hls_url":u}],"sports_channels":[{"id":"two","hls_url":u,"backup_urls":[u]}],"sports_events":[{"streams":[{"url":u}]}]}}
g._catalog=copy.deepcopy(sample)
g._catalog_at=time.monotonic()-g.refresh_seconds-1
called=threading.Event()
release=threading.Event()

def slow():
    called.set()
    release.wait(timeout=5)
    return sample

g._build_catalog=slow
before=time.monotonic()
snapshot=g.catalog()
elapsed=time.monotonic()-before
assert elapsed<0.5, f"stale catalog should return instantly, took {elapsed}"
assert called.wait(2),"background refresh did not start"
for row in snapshot["data"]["channels"]+snapshot["data"]["sports_channels"]:
    u2=row["hls_url"]
    p=urlsplit(u2)
    assert g._validate_signature(tid,p.query)
assert g._validate_signature(tid,urlsplit(snapshot["data"]["sports_channels"][0]["backup_urls"][0]).query)
assert g._validate_signature(tid,urlsplit(snapshot["data"]["sports_events"][0]["streams"][0]["url"]).query)
release.set()
for _ in range(30):
    if not g._catalog_refreshing:break
    time.sleep(0.01)
assert not g._catalog_refreshing
assert len(snapshot["data"]["channels"])==1
print("PASS: stale cache returns instantly; refresh singleflight; signed URLs renewed")

# Failure should retain old guide and delay expensive retries.
g._catalog_at=time.monotonic()-g.refresh_seconds-1
def failed():
    raise TimeoutError("offline")
g._build_catalog=failed
x=g.catalog()
for _ in range(40):
    if not g._catalog_refreshing:break
    time.sleep(0.01)
assert x["data"]["revision"]=="one"
assert g._catalog["data"]["revision"]=="one"
assert not g._catalog_refreshing
print("PASS: upstream outage does not erase cached catalog")
