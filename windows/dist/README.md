# Bangla Keyboard — Windows build artifacts

Built by [`../build-all.sh`](../build-all.sh) with MinGW g++.
The binaries themselves are git-ignored (rebuild them locally); this folder holds:

| artifact | what it is | how to use |
|---|---|---|
| **`bangla-tray.exe`** | **the phonetic Banglish keyboard** — the Windows twin of the macOS app | double-click → a tray icon appears. A global low-level keyboard hook (`WH_KEYBOARD_LL`) runs each keystroke through the shared phonetic engine and injects Bangla with `SendInput`, so you type romanized (`amar` → `আমার`) and get Bangla in **any** app. A candidate popup shows suggestions — press **1–6** to pick. **Ctrl+Alt+B** or the tray icon toggles বাংলা ⇄ English. No admin, no install. |
| `bangla-dictionary.txt` | the offline word list (~35k words) | ships next to the `.exe`; the tray loads it from its own folder at startup |
| `hardwords_raw.tsv` | AiCMS romanization aliases | loaded alongside the dictionary for hard-word recall |

The shared engine's self-test (`wordtest`) is compiled and run under MinGW during the
build — it exercises the exact headers the tray includes (`phonetic.hpp` + `worddb.hpp`)
and runs the recall regression (e.g. `jonno`→জন্য, `bissho`→বিশ্ব, `dip`→দ্বীপ), so a
broken engine fails the Windows build too.

## Install
Easiest: just run `bangla-tray.exe` from this folder — the dictionary files sit next
to it, so no install is needed.

For a proper installer, build the Inno Setup script:
```
iscc ..\installer\banglakeyboard.iss   ->   installer\dist\BanglaKeyboard-Setup-<ver>.exe
```
It installs per-user (**no admin**), bundles the dictionary, `LICENSE`, and `NOTICE`,
and adds a Start-menu / startup entry. Then use **Ctrl+Alt+B** (or the tray icon) to
switch to বাংলা and type in any app.

## Status / caveats
- ✅ Shared phonetic engine: `wordtest` recall regression passes (compiled + run under MinGW).
- ✅ `bangla-tray.exe` builds statically and types Bangla system-wide via `SendInput`.
- ⚠️ A global hook + `SendInput` can be blocked in password fields or some elevated apps.
- 🔒 **Fully offline** — no network calls, no telemetry, no accounts. On-device only.
- ⬜ **Unsigned.** Code-sign before distributing to avoid SmartScreen warnings.

Licensed under the **AICMS Public License v1.0** — free & open-source, by AiCMS.BD.
Required credit: *powered by AiCMS.BD • Brought You By Bangla.it.com*.
