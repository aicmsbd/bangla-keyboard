# Bangla Keyboard — Windows tray app

The Windows build of **বাঙলা কিবোর্ড (Bangla Keyboard)** by AiCMS.BD is a background
app with a **system-tray icon + popup menu**. It's a fully offline **phonetic
("Banglish")** keyboard: type romanized (`amar` → আমার) and it becomes Bangla as you
type, with live word **suggestions**. It emits standard Unicode and uses any system
Bangla font (nothing bundled). No admin and no registration — install per-user and run.

## Phonetic input
- **One phonetic Banglish mode.** Type Latin letters, get Bangla. Toggle বাংলা ⇄ English.
- **Candidate popup:** press **1–6** to pick a suggestion. Candidates come from an
  offline index — a ~35k-word dictionary plus AiCMS romanization aliases — that ships
  next to the `.exe`.
- Suggestions recall ya-phola ্য / ba-phola ্ব words typed the natural way
  (`jonno`→জন্য, `bissho`→বিশ্ব, `dip`→দ্বীপ), and match loose / mixed-case spellings
  (`sochokke` / `ShoWchoKKHE` → সচক্ষে).

## Switching
- **Ctrl+Alt+B** → toggle **বাংলা ⇄ English**.
- Or **left-click** the tray icon, or use the **right-click menu**.
- **All English shortcuts pass through unchanged** — Ctrl+C/V/X/A (copy/paste/cut/
  select-all), Ctrl+S / Ctrl+Shift+S (save / save as), Ctrl+Z/Y, Alt+F4, Alt+Tab,
  Win+…, arrows/Home/End, etc. The hook only converts plain typing keys; anything with
  Ctrl/Alt/Win held is left for the app.

## How it works
- A global low-level keyboard hook (`WH_KEYBOARD_LL`) runs each keystroke through the
  shared phonetic engine ([`../../engine/phonetic/`](../../engine/phonetic/), a
  header-only C++17 library) and injects the result with `SendInput`, so it works in
  **any** app (Notepad, Word, browsers, chat).
- The same engine and dictionary drive the macOS and Linux builds, so typing behaviour
  and suggestions are identical across platforms.
- **No network calls at all** — the suggestion index is fully on-device. No telemetry,
  no accounts.

## Install & run
1. Build with MinGW via [`../build-all.sh`](../build-all.sh), which produces the tray
   app and an Inno Setup installer.
2. Run **`BanglaKeyboard-Setup-*.exe`** (per-user, no admin). The dictionary is
   installed next to the `.exe`.
3. It starts in **English**. Press **Ctrl+Alt+B** (or click the icon) to switch to
   **Bangla**, then type. Right-click the icon → **Close** to quit.

To start it automatically at login, drop a shortcut to the tray app in `shell:startup`
(Win+R → `shell:startup`).

## Limitations
- A global hook + `SendInput` can be blocked in password fields or some full-screen
  games.
- **x64 only** — a global hook works across all apps regardless of their bitness, so no
  separate 32-bit build is needed.
- **Code-sign before wide distribution** — a keyboard hook + unsigned exe can draw
  SmartScreen / AV attention.

## License & credit
- **AICMS Public License v1.0** — `LICENSE` + `NOTICE` are bundled in the installer.
- Required visible credit: **"powered by AiCMS.BD • Brought You By Bangla.it.com"**.
- Independent project, not affiliated with any vendor.
