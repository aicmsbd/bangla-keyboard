#!/usr/bin/env bash
# End-to-end test: feed real key events through IBus to the engine and check the
# committed Bangla. Requires the engine to be INSTALLED first (sudo ./install.sh)
# so the IBus daemon can launch it. Runs in a throwaway dbus session — safe to run
# on a headless box.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p dist
echo "[build] ibus-selftest"
g++ -std=c++17 -O2 $(pkg-config --cflags ibus-1.0) ibus-selftest.cpp \
    -o dist/ibus-selftest $(pkg-config --libs ibus-1.0)
echo "[run] (throwaway dbus session + ibus-daemon)"
BIN="$(pwd)/dist/ibus-selftest"
dbus-run-session -- bash -c "ibus-daemon -drx; sleep 3; '$BIN'; rc=\$?; ibus exit 2>/dev/null; exit \$rc"
