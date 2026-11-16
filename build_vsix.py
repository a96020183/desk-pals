"""把公仔櫃打包成 .vsix（不需要 vsce / npm）。
用法：python -I build_vsix.py                → dist/desk-pals-<版號>.vsix（公開版）＋ dist/desk-pals-<版號>-personal.vsix（個人版）
      python -I build_vsix.py --public       → 只打公開版（只有續命小隊＋自己做的公仔；上架、公開下載用）
      python -I build_vsix.py --personal     → 只打個人版（全部角色，含同人；自己用，不要公開）
      … --out <資料夾>                        → 輸出到別的資料夾（預設 dist）
公開版是 tools/variant.py 從原始碼減掉同人角色產生的（build/public/extension），打包前、打包後都會掃一次同人字眼，有就失敗。
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


def pack(ext, out):
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
                (".png", "image/png"), (".txt", "text/plain"),
            ]
        )
        + "</Types>"
    )
    manifest = f"""<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="{pkg['name']}" Version="{ver}" Publisher="{pkg['publisher']}"/>
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
                arc = "extension/" + os.path.relpath(full, ext).replace(os.sep, "/")
                if f.endswith(".sh"):
                    info = zipfile.ZipInfo(arc)
                    info.external_attr = 0o755 << 16
                    info.compress_type = zipfile.ZIP_DEFLATED
                    z.writestr(info, open(full, "rb").read())
                else:
                    z.write(full, arc)
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
    ver = json.load(open(os.path.join(ROOT, "extension", "package.json"), encoding="utf-8"))["version"]
    if want_pub:
        ext = variant.build_public(os.path.join(ROOT, "build", "public", "extension"))
        vsix = pack(ext, os.path.join(out_dir, f"desk-pals-{ver}.vsix"))
        if not variant.guard([vsix]):
            os.remove(vsix)
            sys.exit("public vsix has fan content (see above) — not written")
    if want_per:
        pack(os.path.join(ROOT, "extension"), os.path.join(out_dir, f"desk-pals-{ver}-personal.vsix"))


if __name__ == "__main__":
    main(sys.argv[1:])
