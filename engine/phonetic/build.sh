#!/usr/bin/env bash
# Build + test the Bangla Keyboard phonetic engine (portable: macOS / Linux). Fully offline.
#   ./build.sh          build the test harness and demo, then run the tests
set -euo pipefail
cd "$(dirname "$0")"

CXX="${CXX:-c++}"
STD="-std=c++17"

echo "==> building regression test"
"$CXX" $STD test.cpp -o phontest

echo "==> building demo"
"$CXX" $STD demo.cpp -o bangla-phon

echo "==> building word-library test"
"$CXX" $STD -O2 wordtest.cpp -o wordtest

echo "==> running tests"
./phontest
if [ -f data/bangla-dictionary.txt ]; then ./wordtest; else echo "(skipping wordtest: data/bangla-dictionary.txt not present)"; fi
