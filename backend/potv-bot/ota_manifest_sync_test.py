"""Offline regression: legacy OTA must not announce unverified or older APKs."""
import copy
import json
import tempfile
from pathlib import Path
from ota_manifest_sync import release_manifest, select_manifest, update_manifest

def release(code=20, tag="v1.0.0-beta.7"):
    name=f"POTV-{tag}.apk"
    return {
        "draft":False,"tag_name":tag,"prerelease":"-beta." in tag,
        "published_at":"2026-10-27T19:00:00Z",
        "body":f"Correcciones de reproducción.\n\nPOTV-Version-Code: {code}",
        "assets":[{"name":name,
                   "browser_download_url":f"https://github.com/ricardoaldape/POTV/releases/download/{tag}/{name}",
                   "digest":"sha256:"+"a"*64,"size":110000000}],
    }

valid=release()
assert release_manifest(valid,allow_beta=True)["versionCode"]==20
assert release_manifest(valid) is None
for mutation in [
    lambda x:x.update(draft=True),
    lambda x:x.update(prerelease=False),
    lambda x:x.update(tag_name="v1.0.0-beta.7/../../evil"),
    lambda x:x.update(body="Missing version code"),
    lambda x:x.update(body="POTV-Version-Code: 20\nPOTV-Version-Code: 21"),
    lambda x:x["assets"][0].update(digest=""),
    lambda x:x["assets"][0].update(size=0),
    lambda x:x["assets"][0].update(browser_download_url="https://evil.example/apk"),
    lambda x:x["assets"][0].update(browser_download_url="https://github.com/ricardoaldape/POTV/releases/download/v1.0.0-beta.7/POTV-v1.0.0-beta.7.apk?token=secret"),
]:
    sample=copy.deepcopy(valid)
    mutation(sample)
    assert release_manifest(sample,allow_beta=True) is None, sample

stable=release(21,"v1.0.1")
assert select_manifest([valid,stable],allow_beta=False)["versionCode"]==21
assert select_manifest([valid,stable],allow_beta=True)["versionCode"]==21
assert select_manifest([valid],current_code=20,allow_beta=True) is None

try:
    select_manifest([valid,valid],allow_beta=True)
    raise AssertionError("Duplicate release code accepted")
except ValueError as exc:
    assert str(exc)=="duplicate_release_version_code"

with tempfile.TemporaryDirectory() as tmp:
    target=Path(tmp)/"version.json"
    target.write_text(json.dumps({
        "version":"0.8.0","versionCode":13,
        "apk_url":"https://github.com/ricardoaldape/POTV/releases/download/v0.8.0/POTV-v0.8.0.apk",
    }),encoding="utf8")
    before=target.read_bytes()
    assert update_manifest(target,[valid],allow_beta=False) is None
    assert target.read_bytes()==before
    selected=update_manifest(target,[valid],allow_beta=True,dry_run=True)
    assert selected["versionCode"]==20 and target.read_bytes()==before
    selected=update_manifest(target,[valid],allow_beta=True)
    assert selected["version"]=="1.0.0-beta.7"
    assert json.loads(target.read_text())["versionCode"]==20
    assert update_manifest(target,[release(19,"v1.0.0-beta.6")],
                           allow_beta=True) is None
    assert json.loads(target.read_text())["versionCode"]==20
print("PASS: signed official release metadata, monotonic version codes, atomic legacy OTA")

