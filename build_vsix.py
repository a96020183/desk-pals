"""把公仔櫃打包成 .vsix（不需要 vsce / npm）。
用法：python -I build_vsix.py                → dist/desk-pals-<版號>.vsix（公開版）＋ dist/desk-pals-<版號>-personal.vsix（個人版）
      python -I build_vsix.py --public       → 只打公開版（只有續命小隊＋自己做的公仔；上架、公開下載用）
      python -I build_vsix.py --personal     → 只打個人版（全部角色，含同人；自己用，不要公開）
      … --out <資料夾>                        → 輸出到別的資料夾（預設 dist）
      … --target win32-x64[,win32-arm64] --exe <DeskPals.exe>
                                              → Windows 專用的 vsix（desk-pals-<版號>-<平台>[-personal].vsix）：附上編好的 DeskPals.exe
                                                （packaging/windows/build.ps1 編的；公開版給公開版的 exe、個人版給個人版的），
                                                擴充套件就直接執行它，不再用 PowerShell 即時編譯。一次只打一種版本（--public 或 --personal）。
                                                沒有 --target＝通用版（Mac 用；不帶 exe，在 Windows 上會退回 desk-pals.ps1）。
公開版是 tools/variant.py 從原始碼減掉同人角色產生的（build/public/extension），打包前、打包後都會掃一次同人字眼，有就失敗。
公開版的匿名回報 ID：有設環境變數 GA4_MEASUREMENT_ID＋GA4_API_SECRET 就由 variant.build_public 寫進 desktop/pals/ga4.txt 一起打包
（VS Code 擴充套件會把 pals 複製到桌面版旁邊；win32 版附的 exe 本身也內嵌了）；沒設＝這個 vsix 不回報。個人版不帶。
"""
import json
import os
import sys
import zipfile
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import variant  # noqa: E402

SKIP_NAMES = variant.SKIP_NAMES  # mac 編譯產物、雜檔不打包
WIN_TARGETS = {"win32-x64", "win32-arm64"}   # exe 是 AnyCPU，兩個平台同一支；VS Code 不會把 x64 的 vsix 裝到 arm64 上，所以各打一個
MAC_ONLY = {"desktop/DeskPals.swift", "desktop/desk-pals.sh"}   # Windows 專用的 vsix 不帶


def pack(ext, out, target=None, exe=None):
    pkg = json.load(open(os.path.join(ext, "package.json"), encoding="utf-8"))
    ver = pkg["version"]
    content_types = (
        '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        + "".join(
            f'<Default Extension="{e}" ContentType="{t}"/>'
            for e, t in [
                (".json", "application/json"), (".js", "application/javascript"), (".html", "text/html"),
                (".svg", "image/svg+xml"), (".vsixmanifest", "text/xml"), (".cs", "text/plain"),
                (".ps1", "text/plain"), (".swift", "text/plain"), (".sh", "text/plain"), (".md", "text/markdown"),
                (".png", "image/png"), (".txt", "text/plain"), (".exe", "application/octet-stream"),
            ]
        )
        + "</Types>"
    )
    manifest = f"""<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="{pkg['name']}" Version="{ver}" Publisher="{pkg['publisher']}"{f' TargetPlatform="{target}"' if target else ''}/>
    <DisplayName>{escape(pkg['displayName'])}</DisplayName>
    <Description xml:space="preserve">{escape(pkg['description'])}</Description>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="{pkg['engines']['vscode']}"/>
      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="ui"/>
    </Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>
"""
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("extension.vsixmanifest", manifest)
        for base, dirs, files in os.walk(ext):
            dirs.sort()
            for f in sorted(files):
                if f in SKIP_NAMES:
                    continue
                full = os.path.join(base, f)
                rel = os.path.relpath(full, ext).replace(os.sep, "/")
                if target and rel in MAC_ONLY:
                    continue
                arc = "extension/" + rel
                if f.endswith(".sh"):
                    info = zipfile.ZipInfo(arc)
                    info.external_attr = 0o755 << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    z.writestr(info, open(full, "rb").read())
                else:
                    z.write(full, arc)
        if exe:
            z.write(exe, "extension/desktop/DeskPals.exe")
    print(out)
    for n in zipfile.ZipFile(out).namelist():
        print("  ", n)
    return out


def main(argv):
    for st in (sys.stdout, sys.stderr):
        if hasattr(st, "reconfigure"):
            st.reconfigure(encoding="utf-8", errors="replace")
    want_pub = "--public" in argv or "--personal" not in argv
    want_per = "--personal" in argv or "--public" not in argv
    out_dir = argv[argv.index("--out") + 1] if "--out" in argv else os.path.join(ROOT, "dist")
    targets = [t for t in argv[argv.index("--target") + 1].split(",") if t] if "--target" in argv else [None]
    exe = argv[argv.index("--exe") + 1] if "--exe" in argv else None
    for t in targets:
        if t is not None and t not in WIN_TARGETS:
            sys.exit(f"--target {t}: only {', '.join(sorted(WIN_TARGETS))} (Mac uses the universal vsix)")
    if targets != [None]:
        if not exe:
            sys.exit("--target needs --exe <DeskPals.exe> (build it with packaging/windows/build.ps1 -Steps exe)")
        if want_pub and want_per:
            sys.exit("--target: build one variant at a time (--public with the public exe, --personal with the personal exe)")
    elif exe:
        sys.exit("--exe needs --target win32-x64[,win32-arm64]")
    if exe:
        data = open(exe, "rb").read()
        if data[:2] != b"MZ":
            sys.exit(f"{exe} is not an exe")
        # 公開版的 exe 不能有同人角色（guard 也會再掃一次整個 vsix）；個人版要的是全部角色那一支（給錯會少掉幾櫃）
        if want_pub and not variant.guard([exe]):
            sys.exit(f"{exe} has fan content: the public vsix needs the public DeskPals.exe (dist/DeskPals.exe)")
        if want_per and not variant.bin_hits(data):
            sys.exit(f"{exe} looks like the public exe: the personal vsix needs dist-personal/DeskPals-personal.exe")
    ver = json.load(open(os.path.join(ROOT, "extension", "package.json"), encoding="utf-8"))["version"]
    name = lambda t, suffix: f"desk-pals-{ver}{'-' + t if t else ''}{suffix}.vsix"
    if want_pub:
        ext = variant.build_public(os.path.join(ROOT, "build", "public", "extension"))
        for t in targets:
            vsix = pack(ext, os.path.join(out_dir, name(t, "")), t, exe)
            if not variant.guard([vsix]):
                os.remove(vsix)
                sys.exit("public vsix has fan content (see above) — not written")
    if want_per:
        for t in targets:
            pack(os.path.join(ROOT, "extension"), os.path.join(out_dir, name(t, "-personal")), t, exe)


if __name__ == "__main__":
    main(sys.argv[1:])
