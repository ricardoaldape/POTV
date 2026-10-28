"""POTV release gate: require animated transparent brand assets and playback hooks."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
assets={
    "POTV_inicio_animado_transparente.webp":(960,640,60),
    "POTV_loader_animado_transparente.webp":(360,240,36),
}
def require(ok, reason):
    if not ok:raise SystemExit("POTV branding required: "+reason)
def check(asset, expected):
    data=(root/"assets/branding"/asset).read_bytes()
    require(data[:4]==b"RIFF" and data[8:12]==b"WEBP",asset+" not WebP")
    require(int.from_bytes(data[4:8],"little")+8==len(data),asset+" corrupted")
    flags=0; canvas=None; frames=0; pos=12
    while pos+8<=len(data):
        tag=data[pos:pos+4]
        n=int.from_bytes(data[pos+4:pos+8],"little")
        start=pos+8
        require(start+n<=len(data),asset+" malformed chunk")
        if tag==b"VP8X":
            flags=data[start]
            canvas=(int.from_bytes(data[start+4:start+7],"little")+1,
                    int.from_bytes(data[start+7:start+10],"little")+1)
        if tag==b"ANMF":frames+=1
        pos=start+n+(n%2)
    require(pos==len(data) and canvas==expected[:2],asset+" incorrect canvas")
    require(flags&0x12==0x12 and frames>=expected[2],asset+" no real transparent animation")
    print("POTV verified",asset,canvas,frames,"frames")
for name,expected in assets.items():check(name,expected)
required={
    "pubspec.yaml":["- assets/branding/"],
    "lib/main.dart":["PotvStartupSplash(child: PotvApp())"],
    "lib/app/potv_app.dart":["PotvLoadingFlag(width: 200)"],
    "lib/features/player/player_screen.dart":["if (_media3Buffering)","stream: p.stream.buffering"],
    "lib/features/player/media3_player_surface.dart":["onBuffering(call.arguments == true)"],
    "lib/features/player/secure_webview_player.dart":["if (_loading)"],
    "android/app/src/main/kotlin/com/potv/potv/Media3CastPlayerView.kt":["SHOW_BUFFERING_NEVER",'"bufferingChanged"'],
    "android/app/src/main/res/drawable/launch_background.xml":["@android:color/black"],
}
for path,needles in required.items():
    content=(root/path).read_text(encoding="utf-8")
    for needle in needles:require(needle in content,path+" missing "+needle)
for file in (root/"lib").rglob("*.dart"):
    source=file.read_text(encoding="utf-8")
    require(not re.search(r"\bCircularProgressIndicator\s*\(",source),str(file)+" reintroduced circular loader")
    require(not re.search(r"\bLinearProgressIndicator\(\s*(?:minHeight:\s*[\d.]+\s*,?\s*)?\)",source),str(file)+" reintroduced an unbranded indeterminate loader")
print("POTV permanent animated branding OK")
