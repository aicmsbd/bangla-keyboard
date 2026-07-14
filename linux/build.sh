#!/usr/bin/env bash
# Build the Linux IBus engine into linux/dist/. Reuses the SHARED phonetic engine from
# ../engine/phonetic (the SAME engine + dictionary as macOS + Windows), so Banglish input and
# suggestions are identical across platforms.
#
# Needs: build-essential, pkg-config, libibus-1.0-dev  (Debian/Ubuntu:
#   sudo apt install build-essential pkg-config libibus-1.0-dev)
set -euo pipefail
cd "$(dirname "$0")"                     # linux/
ENGINE=../engine/phonetic                # the shared phonetic engine (header-only)
DATA=../engine/phonetic/data
mkdir -p dist
DIST="$(pwd)/dist"

echo "[1/4] engine self-test (shared phonetic engine on Linux)"
g++ -std=c++17 -O2 -I"$ENGINE" "$ENGINE/wordtest.cpp" -o "$DIST/wordtest"
( cd "$ENGINE" && "$DIST/wordtest" | grep -E '^[0-9]+ passed' | sed 's/^/      /' )

echo "[2/4] ibus-engine-bangla (phonetic Banglish + suggestions)"
g++ -std=c++17 -O2 -I"$ENGINE" $(pkg-config --cflags ibus-1.0) \
    ibus-bangla.cpp \
    -o dist/ibus-engine-bangla $(pkg-config --libs ibus-1.0)

echo "[3/5] offline dictionary + AiCMS aliases (loaded at runtime)"
cp "$DATA/bangla-dictionary.txt"   dist/bangla-dictionary.txt
cp "$DATA/tools/hardwords_raw.tsv" dist/hardwords_raw.tsv

echo "[4/5] preview-panel window (WebKitGTK) + shared UI"
# The editor-window app — same UI as macOS/Windows (ui/index.html is a self-contained web app,
# so the panel is just a native WebView host). webkit2gtk-4.1 on newer distros, 4.0 on older.
WK=webkit2gtk-4.1; pkg-config --exists "$WK" || WK=webkit2gtk-4.0
cc -O2 panel/panel.c $(pkg-config --cflags gtk+-3.0 "$WK") \
    -o dist/bangla-panel $(pkg-config --libs gtk+-3.0 "$WK")
mkdir -p dist/ui
cp ../macos/app/ui/index.html   dist/ui/index.html
cp ../macos/app/ui/logo-256.png dist/ui/logo-256.png

echo "[5/5] local component XML (standalone test)"
cat > dist/bangla.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<component>
  <name>org.freedesktop.IBus.Bangla</name>
  <description>বাঙলা কিবোর্ড — Bangla phonetic keyboard (Banglish)</description>
  <exec>$(pwd)/dist/ibus-engine-bangla --ibus</exec>
  <version>1.1.4</version>
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
      <icon>$(pwd)/icons/bangla-unicode.png</icon>
      <rank>1</rank>
    </engine>
  </engines>
</component>
EOF

echo "Done -> linux/dist/ (ibus-engine-bangla + dictionary + bangla.xml)"
