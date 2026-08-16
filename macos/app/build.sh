#!/usr/bin/env bash
# Build বাঙলা কিবোর্ড.app and a .dmg (macOS). Needs the Xcode command-line tools.
set -e
cd "$(dirname "$0")"
APP="বাঙলা কিবোর্ড.app"
DMGNAME="বাঙলা কিবোর্ড"
BUILD="build"; DIST="dist"
rm -rf "$BUILD" "$DIST"; mkdir -p "$DIST"
APPDIR="$BUILD/$APP"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources/ui"

echo "==> compiling app (universal: Apple Silicon + Intel)"
FW="-framework Cocoa -framework WebKit -framework ApplicationServices"
swiftc -O -target arm64-apple-macos11  Sources/*.swift $FW -o "$BUILD/banglakb-arm64"
swiftc -O -target x86_64-apple-macos11 Sources/*.swift $FW -o "$BUILD/banglakb-x86_64"
lipo -create "$BUILD/banglakb-arm64" "$BUILD/banglakb-x86_64" -output "$APPDIR/Contents/MacOS/banglakb"
rm -f "$BUILD/banglakb-arm64" "$BUILD/banglakb-x86_64"

echo "==> staging resources"
python3 ui/gen_words.py >/dev/null
cp ui/index.html   "$APPDIR/Contents/Resources/ui/index.html"
cp ui/logo-256.png "$APPDIR/Contents/Resources/ui/logo-256.png"
# Dictionary + AiCMS romanization aliases for the native system-wide suggestion popup.
cp ../../engine/phonetic/data/bangla-dictionary.txt      "$APPDIR/Contents/Resources/bangla-dictionary.txt"
cp ../../engine/phonetic/data/tools/hardwords_raw.tsv    "$APPDIR/Contents/Resources/hardwords_raw.tsv"
# License + attribution (bundled in every copy, per the AICMS Public License).
cp ../../LICENSE "$APPDIR/Contents/Resources/LICENSE"
cp ../../NOTICE  "$APPDIR/Contents/Resources/NOTICE"
sips -s format icns ui/logo-256.png --out "$APPDIR/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 || true

cat > "$APPDIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>বাঙলা কিবোর্ড</string>
  <key>CFBundleDisplayName</key><string>বাঙলা কিবোর্ড</string>
  <key>CFBundleIdentifier</key><string>com.bangla.keyboard.app</string>
  <key>CFBundleExecutable</key><string>banglakb</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.4</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>বাঙলা কিবোর্ড uses the microphone for voice typing (speech-to-text).</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>বাঙলা কিবোর্ড uses speech recognition to turn your voice into text.</string>
</dict></plist>
PLIST

echo "==> code signing"
# A stable self-signed identity gives a cdhash-INDEPENDENT designated requirement, so the
# macOS Accessibility (TCC) grant that powers system-wide typing survives every rebuild.
# Ad-hoc signing does NOT — its requirement is a bare cdhash that changes each build, which
# silently revokes the grant. setup-signing.sh creates the identity once (non-interactive).
SIGN_ID="Bangla Keyboard Dev"
SIGN_KC="$HOME/Library/Keychains/bangla-keyboard-signing.keychain-db"
# Locally: auto-create the stable identity (idempotent). On CI (BK_NO_AUTO_SIGN=1) do NOT —
# a throwaway per-run cert would defeat the point; CI either imports the real cert from a
# secret (so the identity is already present) or falls back to ad-hoc below.
[ -z "${BK_NO_AUTO_SIGN:-}" ] && [ -x ./setup-signing.sh ] && ./setup-signing.sh >/dev/null 2>&1 || true
[ -f "$SIGN_KC" ] && security unlock-keychain -p "banglakeyboard-local-signing" "$SIGN_KC" 2>/dev/null || true
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_ID"; then
  echo "   signing with stable identity: $SIGN_ID (Accessibility grant persists across rebuilds)"
  codesign --force --keychain "$SIGN_KC" --sign "$SIGN_ID" "$APPDIR" \
    || { echo "   ERROR: codesign with '$SIGN_ID' failed"; exit 1; }
else
  echo "   WARNING: stable identity '$SIGN_ID' not found — falling back to AD-HOC signing."
  echo "            The Accessibility grant will NOT survive the next rebuild."
  echo "            Run ./setup-signing.sh once to fix this permanently."
  codesign --force --deep --sign - "$APPDIR" || { echo "   ERROR: ad-hoc codesign failed"; exit 1; }
fi
# Print the designated requirement so a bare-cdhash regression is visible at a glance.
echo -n "   designated requirement => "
codesign -d -r- "$APPDIR" 2>&1 | sed -n 's/^designated => //p' | head -1

echo "Built app: $APPDIR"
echo "→ For the styled drag-to-Applications installer DMG, run:  ./build_dmg.sh"
