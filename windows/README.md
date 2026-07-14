# বাঙলা কিবোর্ড — Windows

> **Status: shipping — the tray app is released.**

A fully offline **phonetic ("Banglish")** Bangla keyboard for Windows. Type romanized
(`amar` → আমার) and it becomes Bangla as you type, with live word **suggestions**. Output is
standard Unicode — no fonts are bundled (Windows ships "Nirmala UI"; any system Bangla font renders it).

The Windows app ([`tray/`](tray/)) is a **tray app**. A `WH_KEYBOARD_LL` global hook types Bangla
into any app via `SendInput`, with a candidate popup at the caret (press **1–6** to pick a suggestion).
**Ctrl+Alt+B** (or the tray icon) toggles **বাংলা ⇄ English**. No admin needed.

## Install & use (end users)
1. Download **`BanglaKeyboard-Setup-*.exe`** from the
   [**releases page**](https://github.com/aicmsbd/bangla-keyboard/releases) and run it —
   **per-user, no admin needed**. It's unsigned, so SmartScreen shows a warning → **More info →
   Run anyway**. It installs the tray app and can start at login. The dictionary is installed
   next to the `.exe`.
2. A **tray icon** appears. Toggle **বাংলা ⇄ English** from the icon or with **Ctrl+Alt+B**, then
   type romanized text in any app. As you type, Bangla appears with a suggestion popup — press
   **1–6** to choose a word.

## Phonetic engine (shared across platforms)
All platforms share one engine: [`../engine/phonetic/`](../engine/phonetic/) — pure, header-only
**C++17** with no OS headers. It does transliteration plus an **offline suggestion index**: a
dictionary of ~35k words plus AiCMS romanization aliases, in
[`../engine/phonetic/data/`](../engine/phonetic/data/) (`bangla-dictionary.txt`,
`tools/hardwords_raw.tsv`). The same data and behaviour run on macOS, Windows, and Linux.

Suggestions recall ya-phola ্য / ba-phola ্ব words typed the natural way (`jonno`→জন্য,
`bissho`→বিশ্ব, `dip`→দ্বীপ), and mixed-case / loose spellings all match
(`sochokke` / `ShoWchoKKHE`→সচক্ষে).

The engine is unit-tested headless via `test.cpp` / `wordtest.cpp` — no Windows box required.

## Build
Build everything with **MinGW** (w64devkit):

```
windows/build-all.sh
```

This compiles the tray app and stages the installer inputs. The packaged
`BanglaKeyboard-Setup-*.exe` is produced by **Inno Setup** from
[`installer/banglakeyboard.iss`](installer/banglakeyboard.iss). CI (GitHub Actions,
[`../.github/workflows/build.yml`](../.github/workflows/build.yml)) builds the installer on a
Windows runner and runs the shared engine self-test (`wordtest`).

## Folder layout
```
windows/
├── tray/           # the shipped tray app (WH_KEYBOARD_LL hook + candidate popup)
├── installer/      # Inno Setup script (banglakeyboard.iss)
├── dist/           # build/release artifacts
├── build-all.sh    # MinGW build → Inno Setup installer
└── README.md
```

## Privacy & security
- **No network calls at all** — the app never opens a socket. No telemetry, no accounts. Fully on-device.
- No bundled or commercial fonts; the engine emits standard Unicode, so any Bangla font renders it.
- No third-party brand names anywhere.

## License
AICMS Public License v1.0. `LICENSE` + `NOTICE` are bundled in every package. Required visible credit:
**powered by AiCMS.BD • Brought You By Bangla.it.com**. Independent project, not affiliated with any vendor.
