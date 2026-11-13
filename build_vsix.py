"""把一隻小夥伴打包成 .vsix（不需要 vsce / npm）。
用法：python -I build_vsix.py   → dist/<name>-<版號>.vsix
"""
import json
import os
import zipfile
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.join(ROOT, "extension")
SKIP_NAMES = {"SpideyDesktop", ".DS_Store"}  # mac 編譯產物、雜檔不打包

pkg = json.load(open(os.path.join(EXT, "package.json"), encoding="utf-8"))
ver = pkg["version"]

content_types = (
    '<?xml version="1.0" encoding="utf-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    + "".join(
        f'<Default Extension="{e}" ContentType="{t}"/>'
        for e, t in [
            (".json", "application/json"), (".js", "application/javascript"), (".html", "text/html"),
            (".svg", "image/svg+xml"), (".vsixmanifest", "text/xml"), (".cs", "text/plain"),
            (".ps1", "text/plain"), (".swift", "text/plain"), (".sh", "text/plain"), (".md", "text/markdown"),
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

os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
out = os.path.join(ROOT, "dist", f"{pkg['name']}-{ver}.vsix")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("[Content_Types].xml", content_types)
    z.writestr("extension.vsixmanifest", manifest)
    for base, _, files in os.walk(EXT):
        for f in sorted(files):
            if f in SKIP_NAMES:
                continue
            full = os.path.join(base, f)
            arc = "extension/" + os.path.relpath(full, EXT).replace(os.sep, "/")
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
