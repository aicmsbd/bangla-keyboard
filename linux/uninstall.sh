#!/usr/bin/env bash
# Remove the Bangla Keyboard IBus engine.  Run with sudo:  sudo ./uninstall.sh
set -euo pipefail
if [ "$(id -u)" -ne 0 ]; then echo "Run with sudo: sudo ./uninstall.sh"; exit 1; fi
rm -f /usr/lib/ibus/ibus-engine-bangla
rm -f /usr/bin/bangla-panel
rm -f /usr/share/ibus/component/bangla.xml
rm -f /usr/share/ibus/icons/bangla-unicode.png /usr/share/ibus/icons/bangla-classic.png
rm -f /usr/share/applications/bangla-keyboard.desktop
rm -f /usr/share/icons/hicolor/128x128/apps/bangla-keyboard.png
rm -rf /usr/share/bangla-keyboard
echo "Removed. Run 'ibus restart' (or log out/in), and drop the input source in"
echo "Settings -> Keyboard -> Input Sources if it's still listed."
