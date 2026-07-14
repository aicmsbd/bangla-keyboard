#!/usr/bin/env bash
# Build a polished "drag to Applications" DMG (Chrome-style) for বাঙলা কিবোর্ড.
# Assumes build/বাঙলা কিবোর্ড.app already exists (run build.sh first, or this calls it).
set -e
cd "$(dirname "$0")"
APP="বাঙলা কিবোর্ড.app"
VOL="বাঙলা কিবোর্ড"
DIST="dist"; mkdir -p "$DIST"

[ -d "build/$APP" ] || ./build.sh >/dev/null

WORK="build/dmgwork"; rm -rf "$WORK"; mkdir -p "$WORK"
cp -R "build/$APP" "$WORK/"
ln -s /Applications "$WORK/Applications"
mkdir "$WORK/.background"; cp dmg-assets/dmg-bg.png "$WORK/.background/bg.png"

RW="build/rw.dmg"; rm -f "$RW"
hdiutil create -srcfolder "$WORK" -volname "$VOL" -fs HFS+ -format UDRW -size 80m "$RW" >/dev/null
DEV=$(hdiutil attach "$RW" -nobrowse -noverify -noautoopen | grep '/Volumes' | awk '{print $1}')
VP="/Volumes/$VOL"

# arrange the window: background image + icon positions (needs Finder automation).
# Skippable for headless/CI runs (BK_SKIP_DMG_LAYOUT=1) where Finder automation isn't
# authorised and could stall — the DMG is fully functional either way, just default layout.
if [ -n "${BK_SKIP_DMG_LAYOUT:-}" ]; then
  echo "   (BK_SKIP_DMG_LAYOUT set — DMG uses default layout)"
else
osascript <<OSA 2>/dev/null || echo "   (Finder layout automation unavailable — DMG still works, default layout)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 540}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set background picture of opts to file ".background:bg.png"
    set position of item "$APP" of container window to {165, 215}
    set position of item "Applications" of container window to {475, 215}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
fi

sync
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true
rm -f "$DIST/$VOL.dmg"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DIST/$VOL.dmg" >/dev/null
rm -f "$RW"
echo "Built: $DIST/$VOL.dmg ($(du -h "$DIST/$VOL.dmg" | cut -f1))"
