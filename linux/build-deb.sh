#!/usr/bin/env bash
# Build a Debian/Ubuntu .deb of the Bangla Keyboard IBus engine.
#   ./build-deb.sh [version]      -> linux/dist/bangla-keyboard-ibus_<ver>_<arch>.deb
# Needs: dpkg-deb (dpkg-dev) + the build deps (see build.sh).
set -euo pipefail
cd "$(dirname "$0")"
VER="${1:-1.1.5}"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

./build.sh                                    # -> dist/ibus-engine-bangla (+ self-test)

# Assemble in a NATIVE-fs temp dir: a Windows/WSL /mnt mount is always mode 777,
# which dpkg-deb rejects for the DEBIAN control dir.
SRC_ICONS="$(pwd)/icons"
BIN_BUILT="$(pwd)/dist/ibus-engine-bangla"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/bangla-keyboard-ibus_${VER}_${ARCH}"
install -Dm755 "$BIN_BUILT"                    "$ROOT/usr/lib/ibus/ibus-engine-bangla"
install -Dm644 "$SRC_ICONS/bangla-unicode.png" "$ROOT/usr/share/ibus/icons/bangla-unicode.png"
# offline dictionary + AiCMS aliases — the engine loads these from /usr/share/bangla-keyboard
install -Dm644 "$(pwd)/dist/bangla-dictionary.txt" "$ROOT/usr/share/bangla-keyboard/bangla-dictionary.txt"
install -Dm644 "$(pwd)/dist/hardwords_raw.tsv"     "$ROOT/usr/share/bangla-keyboard/hardwords_raw.tsv"
# license + attribution (bundled in every copy, per the AICMS Public License)
install -Dm644 "$(pwd)/../LICENSE" "$ROOT/usr/share/doc/bangla-keyboard-ibus/LICENSE"
install -Dm644 "$(pwd)/../NOTICE"  "$ROOT/usr/share/doc/bangla-keyboard-ibus/NOTICE"
# preview-panel window app (editor UI) + its shared UI files + launcher + icon
install -Dm755 "$(pwd)/dist/bangla-panel"       "$ROOT/usr/bin/bangla-panel"
install -Dm644 "$(pwd)/dist/ui/index.html"      "$ROOT/usr/share/bangla-keyboard/ui/index.html"
install -Dm644 "$(pwd)/dist/ui/logo-256.png"    "$ROOT/usr/share/bangla-keyboard/ui/logo-256.png"
install -Dm644 "$(pwd)/panel/bangla-keyboard.desktop" "$ROOT/usr/share/applications/bangla-keyboard.desktop"
install -Dm644 "$SRC_ICONS/bangla-unicode.png"  "$ROOT/usr/share/icons/hicolor/128x128/apps/bangla-keyboard.png"

install -d "$ROOT/usr/share/ibus/component"
cat > "$ROOT/usr/share/ibus/component/bangla.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<component>
  <name>org.freedesktop.IBus.Bangla</name>
  <description>বাঙলা কিবোর্ড — Bangla phonetic keyboard (Banglish)</description>
  <exec>/usr/lib/ibus/ibus-engine-bangla --ibus</exec>
  <version>1.1.5</version>
  <author>AiCMS.BD</author>
  <license>AICMS-1.0</license>
  <homepage>https://github.com/aicmsbd/bangla-keyboard</homepage>
  <textdomain>ibus-bangla</textdomain>
  <engines>
    <engine>
      <name>bangla</name>
      <language>bn</language><license>AICMS-1.0</license><author>AiCMS.BD</author><layout>us</layout>
      <longname>বাংলা (Banglish)</longname>
      <description>Bangla phonetic (Banglish) — type "amar" → আমার, with live suggestions</description>
      <icon>/usr/share/ibus/icons/bangla-unicode.png</icon>
      <rank>1</rank>
    </engine>
  </engines>
</component>
XML

install -d "$ROOT/DEBIAN"
cat > "$ROOT/DEBIAN/control" <<CTL
Package: bangla-keyboard-ibus
Version: ${VER}
Architecture: ${ARCH}
Maintainer: AiCMS.BD <mail@aicms.bd>
Depends: ibus, libstdc++6, libc6, libgtk-3-0, libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37
Section: utils
Priority: optional
Homepage: https://github.com/aicmsbd/bangla-keyboard
Description: Bangla Keyboard - phonetic "Banglish" input method + editor (IBus)
 Type Bangla phonetically (amar -> আমার) in any app, with live word suggestions
 from an offline dictionary. The same phonetic engine + dictionary as the macOS and
 Windows Bangla Keyboard. US-QWERTY based, fully offline, AICMS Public License v1.0.
 .
 Includes "বাঙলা কিবোর্ড" — an editor-window app (launch it from your apps menu) with
 the same UI as the macOS/Windows build: type Banglish, pick suggestions, and copy.
 .
 After install: log out and back in, then add "বাংলা (Banglish)" in
 Settings -> Keyboard -> Input Sources, and switch with Super+Space. While typing,
 press 1-6 to pick a suggested word.
CTL

# No maintainer scripts: `ibus write-cache` needs the user session (fails under
# dpkg's root context); a log out / back in rebuilds the IBus registry anyway.

mkdir -p dist
dpkg-deb --build --root-owner-group "$ROOT" "$TMP/pkg.deb" >/dev/null
cp "$TMP/pkg.deb" "dist/bangla-keyboard-ibus_${VER}_${ARCH}.deb"
echo "built -> linux/dist/bangla-keyboard-ibus_${VER}_${ARCH}.deb"
