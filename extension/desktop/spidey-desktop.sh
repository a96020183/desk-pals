#!/bin/bash
# Spidey desktop launcher (macOS)
# usage: spidey-desktop.sh <name>
# Compiles SpideyDesktop.swift next to this script (only when the source is newer), then runs it.
NAME="${1:-spidey-pet}"
DIR="$(cd "$(dirname "$0")" && pwd)"
APPDIR="$HOME/Library/Application Support/SpideyDesktop"
LOG="$HOME/Library/Logs/spidey-desktop.log"
SRC="$DIR/SpideyDesktop.swift"
BIN="$DIR/SpideyDesktop"
SOCK="$APPDIR/spidey.sock"

mkdir -p "$HOME/Library/Logs" "$APPDIR"
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S') sh[$NAME]: $*" >> "$LOG"; }

if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
  if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    log "swiftc not found (Command Line Tools missing)"
    /usr/bin/osascript -e 'display dialog "Spidey 小夥伴需要 Apple 的 Command Line Tools 才能啟動。\n\n請打開「終端機」執行：\nxcode-select --install\n\n裝好之後重新開 VS Code（或登出再登入）就會出現。" buttons {"好"} default button 1 with title "Spidey 小夥伴"' >/dev/null 2>&1
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

exec "$BIN" "$SOCK"
