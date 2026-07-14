#!/usr/bin/env bash
# Build + install the বাঙলা কিবোর্ড macOS Input Method so it shows in
# System Settings → Keyboard → Input Sources. Needs the Xcode command-line tools.
set -e
cd "$(dirname "$0")"
APP="বাঙলা কিবোর্ড.app"
BUILD="build"; rm -rf "$BUILD"; mkdir -p "$BUILD"
APPDIR="$BUILD/$APP"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"

echo "==> compiling input method"
swiftc -O Sources/main.swift -o "$APPDIR/Contents/MacOS/BanglaIM" \
  -framework Cocoa -framework InputMethodKit

sips -s format icns assets/logo-256.png --out "$APPDIR/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 || true

cat > "$APPDIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>বাঙলা কিবোর্ড</string>
  <key>CFBundleDisplayName</key><string>বাঙলা কিবোর্ড</string>
  <key>CFBundleIdentifier</key><string>com.bangla.inputmethod</string>
  <key>CFBundleExecutable</key><string>BanglaIM</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleSignature</key><string>bkim</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSBackgroundOnly</key><string>1</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>InputMethodConnectionName</key><string>BanglaKeyboard_Connection</string>
  <key>InputMethodServerControllerClass</key><string>BanglaController</string>
  <key>tsInputMethodCharacterRepertoireKey</key><array><string>Latn</string></array>
  <key>ComponentInputModeDict</key><dict>
    <key>tsVisibleInputModeOrderedArrayKey</key><array><string>com.bangla.inputmethod.Bangla</string></array>
    <key>tsInputModeListKey</key><dict>
      <key>com.bangla.inputmethod.Bangla</key><dict>
        <key>TISInputSourceID</key><string>com.bangla.inputmethod.Bangla</string>
        <key>TISIntendedLanguage</key><string>bn</string>
        <key>tsInputModeAlternateMenuTitleKey</key><string>বাঙলা কিবোর্ড</string>
        <key>tsInputModeCharacterRepertoireKey</key><array><string>Latn</string></array>
        <key>tsInputModeDefaultStateKey</key><true/>
        <key>tsInputModeIsVisibleKey</key><true/>
        <key>tsInputModeKeyEquivalentKey</key><string></string>
        <key>tsInputModeKeyEquivalentModifiersKey</key><integer>0</integer>
        <key>tsInputModeMenuIconFileKey</key><string>AppIcon.icns</string>
        <key>tsInputModePaletteIconFileKey</key><string>AppIcon.icns</string>
        <key>tsInputModePrimaryInScriptKey</key><true/>
        <key>tsInputModeScriptKey</key><string>smUnicodeScript</string>
        <key>tsInputModeSuperScriptKey</key><integer>0</integer>
      </dict>
    </dict>
  </dict>
</dict></plist>
PLIST

echo "==> ad-hoc signing"
codesign --force --deep --sign - "$APPDIR" >/dev/null 2>&1 || echo "   (codesign skipped)"

echo "==> installing to ~/Library/Input Methods"
DEST="$HOME/Library/Input Methods"
mkdir -p "$DEST"
# stop any old copy, replace
pkill -x BanglaIM 2>/dev/null || true
rm -rf "$DEST/$APP"
cp -R "$APPDIR" "$DEST/"

echo "==> registering + launching"
swiftc register.swift -o "$BUILD/register" -framework Carbon >/dev/null 2>&1 || true
open "$DEST/$APP" 2>/dev/null || "$DEST/$APP/Contents/MacOS/BanglaIM" &
[ -x "$BUILD/register" ] && "$BUILD/register" "$DEST/$APP"

echo
echo "Installed. Add it in: System Settings → Keyboard → Input Sources → Edit → + →"
echo "search \"বাঙলা\" or Bengali → বাঙলা কিবোর্ড. Then pick it from the 🌐 input menu and type Banglish."
