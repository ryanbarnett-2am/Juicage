#!/bin/bash
# Builds the drag-to-Applications disk image.
#   usage: make-dmg.sh <path-to-app> <output.dmg> <volume-name>
#
# A plain `hdiutil create` from the app works but drops the user into a window
# with a lone icon and no hint what to do with it. This lays out the familiar
# app-arrow-Applications view instead.
set -e
APP="$1"; OUT="$2"; VOL="${3:-Juicage}"
HERE="$(cd "$(dirname "$0")" && pwd)"
BG="$HERE/dmg-background.png"

TMP="$(mktemp -d)"
STAGE="$TMP/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
[ -f "$BG" ] && cp "$BG" "$STAGE/.background/background.png"

# Read/write image first — Finder can only style a mounted, writable volume.
RW="$TMP/rw.dmg"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDRW -quiet "$RW"
MNT="$(hdiutil attach "$RW" -nobrowse -noverify | tail -1 | awk '{print $NF}')"

osascript <<APPLESCRIPT >/dev/null 2>&1 || echo "  (Finder styling skipped — layout will be plain)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 12
    try
      set background picture of opts to file ".background:background.png"
    end try
    set position of item "$(basename "$APP")" of container window to {160, 205}
    set position of item "Applications" of container window to {480, 205}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MNT" -quiet || hdiutil detach "$MNT" -force -quiet
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" -quiet
rm -rf "$TMP"
