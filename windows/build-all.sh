#!/usr/bin/env bash
# Build the Windows artifacts into windows/dist/ with MinGW g++.
#   GXX64 = x64 g++ (default: g++)
#
# Produces the phonetic tray keyboard (the twin of the macOS app) + its offline dictionary:
#   bangla-tray.exe        — English <-> বাংলা (Banglish), types Bangla in any app with suggestions
#   bangla-dictionary.txt  — offline word list (ships next to the .exe)
#   hardwords_raw.tsv      — AiCMS romanization aliases
set -euo pipefail
cd "$(dirname "$0")"
GXX64="${GXX64:-${GXX:-g++}}"
mkdir -p dist
tooldir() { dirname "$(command -v "$1" 2>/dev/null || echo "$1")"; }
B64="$(tooldir "$GXX64")"

# The tray uses the SHARED phonetic engine (../engine/phonetic, header-only). Verifying wordtest
# here compiles the exact headers the tray includes (phonetic.hpp + worddb.hpp) under MinGW and
# runs the recall regression, so a broken engine fails the Windows build too.
echo "[test] shared phonetic engine (compile + run under MinGW)"
( cd ../engine/phonetic
  "$GXX64" -B"$B64" -std=c++17 -O2 -static wordtest.cpp -o wordtest.exe
  ./wordtest.exe )

echo "[x64] bangla-tray (phonetic Banglish + live suggestions)"
"$B64/windres" tray/tray.rc -o tray/tray_res.o   # app icon + version info
"$GXX64" -B"$B64" -std=c++17 -O2 -static -mwindows -municode -finput-charset=UTF-8 \
  tray/tray.cpp tray/tray_res.o -o dist/bangla-tray.exe -lgdi32 -luser32 -lshell32

echo "[data] offline dictionary + AiCMS aliases (shipped next to the .exe)"
cp ../engine/phonetic/data/bangla-dictionary.txt   dist/bangla-dictionary.txt
cp ../engine/phonetic/data/tools/hardwords_raw.tsv dist/hardwords_raw.tsv

# The preview-panel window (WebView2) — the editor-UI twin of the macOS/Linux windows. The UI
# (ui/index.html) is a self-contained web app, so the panel is just a native WebView2 host.
# The WebView2 SDK is a NuGet .zip: fetch it and use ONLY the classic-COM header + the x64 loader.
echo "[x64] preview-panel window (WebView2) — fetch SDK"
WV2_VER=1.0.4078.44
WV2_DIR="$PWD/vendor/webview2"
mkdir -p "$WV2_DIR"
if [ ! -f "$WV2_DIR/build/native/include/WebView2.h" ]; then
  curl -fL --retry 3 -o "$WV2_DIR/webview2.nupkg" \
    "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/${WV2_VER}"
  unzip -o -q "$WV2_DIR/webview2.nupkg" \
    'build/native/include/*' 'build/native/x64/*' 'LICENSE.txt' -d "$WV2_DIR"
fi

echo "[x64] bangla-panel (WebView2 host loading ui/index.html)"
cp tray/banglakeyboard.ico panel/banglakeyboard.ico   # the app icon (real logo)
"$B64/windres" panel/panel.rc -o panel/panel_res.o
"$GXX64" -B"$B64" -std=c++17 -O2 -static -mwindows -municode -DUNICODE -D_UNICODE -finput-charset=UTF-8 \
  -I "$WV2_DIR/build/native/include" \
  panel/panel.cpp panel/panel_res.o -o dist/bangla-panel.exe \
  -lole32 -lshlwapi -lshell32 -luser32 -lgdi32
cp "$WV2_DIR/build/native/x64/WebView2Loader.dll" dist/WebView2Loader.dll
cp "$WV2_DIR/LICENSE.txt"                          dist/WebView2Loader-LICENSE.txt
mkdir -p dist/ui
cp ../macos/app/ui/index.html   dist/ui/index.html
cp ../macos/app/ui/logo-256.png dist/ui/logo-256.png

echo "Done -> windows/dist/"
ls -la dist
