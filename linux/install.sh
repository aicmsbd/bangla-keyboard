#!/usr/bin/env bash
# Install the বাঙলা কিবোর্ড IBus engine system-wide (Debian/Ubuntu and most distros with IBus).
# Builds first, copies the binary + dictionary + component XML, restarts IBus. Run with sudo:
#   sudo ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

BIN=/usr/lib/ibus/ibus-engine-bangla
XML=/usr/share/ibus/component/bangla.xml
DATADIR=/usr/share/bangla-keyboard

if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo: sudo ./install.sh"; exit 1; fi

echo "[1/4] build"
# build as the invoking (non-root) user if possible, else here
if [ -n "${SUDO_USER:-}" ]; then sudo -u "$SUDO_USER" bash build.sh; else bash build.sh; fi

echo "[2/4] install engine + panel + dictionary + UI + icon + launcher"
install -Dm755 dist/ibus-engine-bangla "$BIN"
install -Dm644 icons/bangla-unicode.png /usr/share/ibus/icons/bangla-unicode.png
install -Dm644 dist/bangla-dictionary.txt "$DATADIR/bangla-dictionary.txt"
install -Dm644 dist/hardwords_raw.tsv     "$DATADIR/hardwords_raw.tsv"
# editor-window app (preview panel) + its UI + launcher + app icon
install -Dm755 dist/bangla-panel                /usr/bin/bangla-panel
install -Dm644 dist/ui/index.html               "$DATADIR/ui/index.html"
install -Dm644 dist/ui/logo-256.png             "$DATADIR/ui/logo-256.png"
install -Dm644 panel/bangla-keyboard.desktop    /usr/share/applications/bangla-keyboard.desktop
install -Dm644 icons/bangla-unicode.png         /usr/share/icons/hicolor/128x128/apps/bangla-keyboard.png

echo "[3/4] install component -> $XML"
install -d "$(dirname "$XML")"
cat > "$XML" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<component>
  <name>org.freedesktop.IBus.Bangla</name>
  <description>বাঙলা কিবোর্ড — Bangla phonetic keyboard (Banglish)</description>
  <exec>$BIN --ibus</exec>
  <version>1.1.6</version>
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
EOF

echo "[4/4] restart IBus registry"
if [ -n "${SUDO_USER:-}" ]; then sudo -u "$SUDO_USER" ibus write-cache --system 2>/dev/null || true; fi

cat <<'MSG'

Installed. To finish:
  1) ibus restart                (or log out/in)
  2) Add the input source: GNOME Settings -> Keyboard -> Input Sources -> +
     -> Bangla -> "বাংলা (Banglish)".
  3) Switch with Super+Space and type phonetically (amar -> আমার).
     While typing, press 1-6 to pick a suggested word.
MSG
