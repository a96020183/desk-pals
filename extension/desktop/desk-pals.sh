#!/bin/bash
# 公仔櫃 Desk Pals desktop launcher (macOS)
# usage: desk-pals.sh <name> [pet] [lineup]
# Runs the compiled DeskPals binary next to this script. If only the Swift source is shipped
# (DeskPals.swift, no bundled binary), compiles it first (when the source is newer), then runs.
NAME="${1:-desk-pals}"
PET="${2:-}"
LINEUP="${3:-}"
DIR="$(cd "$(dirname "$0")" && pwd)"
APPDIR="$HOME/Library/Application Support/DeskPals"
LOG="$HOME/Library/Logs/desk-pals.log"
SRC="$DIR/DeskPals.swift"
BIN="$DIR/DeskPals"
SOCK="$APPDIR/desk-pals.sock"

mkdir -p "$HOME/Library/Logs" "$APPDIR"
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S') sh[$NAME]: $*" >> "$LOG"; }

# vsix 附了編好的 binary（沒有 .swift）就直接跑它；只有帶原始碼時才需要 swiftc 即時編譯
if [ ! -x "$BIN" ] || { [ -f "$SRC" ] && [ "$SRC" -nt "$BIN" ]; }; then
  if [ ! -f "$SRC" ]; then
    log "no DeskPals binary and no DeskPals.swift to compile"
    exit 1
  fi
  if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    log "swiftc not found (Command Line Tools missing)"
    /usr/bin/osascript -e 'display dialog "公仔櫃需要 Apple 的 Command Line Tools 才能啟動。\n\n請打開「終端機」執行：\nxcode-select --install\n\n裝好之後重新開 VS Code（或登出再登入）就會出現。" buttons {"好"} default button 1 with title "WoWo Pals"' >/dev/null 2>&1
    exit 1
  fi
  log "compiling $SRC"
  TMP="$BIN.tmp.$$"
  if ! /usr/bin/xcrun swiftc -O "$SRC" -o "$TMP" >>"$LOG" 2>&1; then
    log "compile failed (see errors above)"
    rm -f "$TMP"
    exit 1
  fi
  mv -f "$TMP" "$BIN"
  log "compiled ok"
fi

exec "$BIN" "$SOCK" "$PET" "$LINEUP"
