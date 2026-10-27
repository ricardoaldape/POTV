"""Progressive VOD pagination in a bounded, recurring NOVA sync."""
from nova_catalog_sync import progressive_media

class Service:
    def __init__(self):
        self.catalog = [{"tmdb_id": i, "title": f"Movie {i}",
                         "year": "2026", "overview":"demo"}
                        for i in range(1,1202)]
        self.fail = False
    def movies(self, *, skip, limit):
        if self.fail:
            raise ValueError("Upstream temporarily unavailable")
        return self.catalog[skip:skip+limit]

service=Service()
items=[]
offset=0
for expected_offset in (500, 1000, 0):
    items,offset,received=progressive_media(
        service,service.movies,category="movie",
        previous=items,previous_offset=offset,scan_limit=2000,batch=500
    )
    assert offset==expected_offset,(offset,expected_offset)
assert len(items)==1201,len(items)
assert len({x["tmdb_id"] for x in items})==1201
# Refresh the first page and avoid old duplicates when provider edits titles.
service.catalog[0]["title"]="Newest naming"
items,offset,received=progressive_media(
    service,service.movies,category="movie",previous=items,
    previous_offset=0,scan_limit=2000,batch=500)
assert received==500 and offset==500
assert next(x for x in items if x["tmdb_id"]==1)["title"]=="Newest naming"
# An upstream failure preserves the last successful shelf.
service.fail=True
held,offset2,received=progressive_media(
    service,service.movies,category="movie",previous=items,
    previous_offset=offset,scan_limit=2000,batch=500)
assert received==0 and held==items
print("PASS: progressive VOD pagination, dedupe, updates, and outage retention")
