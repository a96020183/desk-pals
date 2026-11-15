#!/bin/bash
# 公仔櫃 Desk Pals：macOS 獨立版打包 → dist/DeskPals-<版號>.dmg（裡面是「Desk Pals.app」＋「應用程式」捷徑）
# 用法（在 Mac 上、repo 根目錄）：packaging/mac/build_app.sh [輸出資料夾]
# 需要：Xcode Command Line Tools（swiftc、lipo、iconutil、codesign、hdiutil）、Python 3 + Pillow（畫圖示；可用 PYTHON=... 指定）
#
# 預設：universal（arm64＋x86_64）、ad-hoc 簽章（codesign -s -，Apple Silicon 一定要有簽章才能跑）。
# 有 Developer ID 之後（之後再開，不用改這支）：
#   MAC_SIGN_IDENTITY="Developer ID Application: 你的名字 (TEAMID)"   → 用 hardened runtime 簽 .app 和 DMG
#   再加 APPLE_ID、APPLE_TEAM_ID、APPLE_APP_PASSWORD（App 專用密碼）     → 送 Apple 公證（notarize）＋ staple
# 其他：MAC_BUNDLE_ID（預設 io.github.a96020183.deskpals）、MAC_MIN_MACOS（預設 13.0：程式用到 macOS 13 的 API）
# VARIANT=public（預設；公開下載、上架用：只有續命小隊＋自己做的公仔，tools/variant.py 產生並掃過同人字眼）
#        personal（全部角色，含同人；自己用，不要公開）→ dist/DeskPals-<版號>-personal.dmg
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
OUT="${1:-$ROOT/dist}"
PY="${PYTHON:-python3}"
VERSION="$("$PY" -c 'import json,sys; print(json.load(open("extension/package.json", encoding="utf-8"))["version"])')"
VARIANT="${VARIANT:-public}"
case "$VARIANT" in public) SUFFIX="" ;; personal) SUFFIX="-personal" ;; *) echo "VARIANT must be public or personal" >&2; exit 2 ;; esac
BUILD="$ROOT/build/mac$SUFFIX"
BUNDLE_ID="${MAC_BUNDLE_ID:-io.github.a96020183.deskpals}"
MIN_MACOS="${MAC_MIN_MACOS:-13.0}"
APP_NAME="Desk Pals"
APP="$BUILD/$APP_NAME.app"
DMG="$OUT/DeskPals-$VERSION$SUFFIX.dmg"
echo "Desk Pals $VERSION $VARIANT ($BUNDLE_ID, macOS $MIN_MACOS+)"

rm -rf "$BUILD" && mkdir -p "$BUILD" "$OUT"

# ---------- 原始碼、圖示 ----------
if [ "$VARIANT" = personal ]; then
  "$PY" mac/assemble.py
  SRC="$ROOT/extension/desktop"
else
  "$PY" -I tools/variant.py public   # build/public/extension（公開版原始碼），有同人字眼就失敗
  SRC="$ROOT/build/public/extension/desktop"
fi
"$PY" -I packaging/icons/make_icons.py "$ROOT/build/icons"
iconutil -c icns "$ROOT/build/icons/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

# ---------- universal binary ----------
for arch in arm64 x86_64; do
  echo "swiftc ${arch} ..."
  xcrun swiftc -O -target "$arch-apple-macos$MIN_MACOS" "$SRC/DeskPals.swift" -o "$BUILD/DeskPals-$arch"
done
lipo -create -output "$BUILD/DeskPals" "$BUILD/DeskPals-arm64" "$BUILD/DeskPals-x86_64"
lipo -info "$BUILD/DeskPals"

# ---------- .app ----------
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/DeskPals" "$APP/Contents/MacOS/DeskPals"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$SRC/claude-hook.js" "$SRC/ci-watch.js" "$APP/Contents/Resources/"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$VERSION/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" -e "s/__MIN_MACOS__/$MIN_MACOS/g" \
  packaging/mac/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ "$VARIANT" = public ]; then "$PY" -I tools/variant.py guard "$APP"; fi   # 執行檔、資源裡不能有同人字眼

# ---------- 簽章 ----------
NOTARIZE=0
if [ -n "${MAC_SIGN_IDENTITY:-}" ]; then
  echo "signing with Developer ID (hardened runtime)"
  codesign --force --options runtime --timestamp --sign "$MAC_SIGN_IDENTITY" "$APP"
  if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then NOTARIZE=1; fi
else
  echo "ad-hoc signing (no Developer ID yet)"
  codesign --force --sign - "$APP"
fi
codesign --verify --strict --verbose=2 "$APP"

notarize() {   # $1 = 要送的檔（zip 或 dmg）
  xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait --timeout 30m
}
if [ "$NOTARIZE" = 1 ]; then
  echo "notarizing the app…"
  ditto -c -k --keepParent "$APP" "$BUILD/app.zip"
  notarize "$BUILD/app.zip"
  xcrun stapler staple "$APP"
fi

# ---------- DMG ----------
STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
if [ "$NOTARIZE" != 1 ]; then
  cat > "$STAGE/第一次打開請看我.txt" <<'TXT'
公仔櫃 Desk Pals — 安裝

1. 把「Desk Pals」拖到旁邊的「Applications（應用程式）」資料夾。
2. 到「應用程式」資料夾打開 Desk Pals。

這一版還沒有 Apple 的開發者簽章，第一次打開 macOS 會擋下來，照下面做一次就好：

● macOS 15（Sequoia）以後
  1. 雙擊 Desk Pals，看到「無法打開」時按「完成」。
  2. 打開「系統設定」→「隱私權與安全性」，往下捲到「安全性」，
     會看到「已阻擋 "Desk Pals" 以保護你的 Mac」，按旁邊的「仍要打開」。
  3. 輸入登入密碼，再按一次「仍要打開」。

● macOS 14（Sonoma）以前
  1. 在「應用程式」資料夾裡，對 Desk Pals 按右鍵（或按住 Control 再點一下）→ 選「打開」。
  2. 跳出的視窗再按一次「打開」。

之後就跟一般 App 一樣：公仔櫃會出現在螢幕右下角，開機也會自動出現。
（要關掉開機自動出現：「系統設定」→「一般」→「登入項目」。）
TXT
fi
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
if [ -n "${MAC_SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$MAC_SIGN_IDENTITY" "$DMG"
  if [ "$NOTARIZE" = 1 ]; then
    echo "notarizing the dmg…"
    notarize "$DMG"
    xcrun stapler staple "$DMG"
  fi
fi
ls -l "$DMG"
echo "built $DMG"
