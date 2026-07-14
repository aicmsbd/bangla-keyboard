# বাঙলা কিবোর্ড — macOS Input Method (shows in Input Sources)

This is the **proper macOS input source** — an InputMethodKit (IMK) input method. Once
installed it appears in **System Settings → Keyboard → Input Sources**, and you pick it
from the input (🌐) menu like any keyboard. Type Banglish → it shows the Bangla as
underlined pre-edit; a space/punctuation commits the word.

> Why the earlier `macos/app/` didn't show in Input Sources: that one is a **background
> app with a global key-tap** (system-tray style) — it works via Ctrl+B but, by macOS design,
> never appears in Input Sources. THIS component is the one that does.

## Install

```bash
cd macos/inputmethod
./build.sh
```

`build.sh` compiles it, bundles `বাঙলা কিবোর্ড.app`, installs it to
`~/Library/Input Methods/`, and registers it (`TISRegisterInputSource`).

**Then — log out and back in.** macOS only picks up a *newly installed* input method after
a session restart (this is a macOS requirement, not a bug — `TISRegisterInputSource`
returns success immediately, but the Input Sources list is built at login). After logging
back in:

1. **System Settings → Keyboard → Input Sources → Edit → `+`**
2. Search **বাঙলা** or **Bengali** → pick **বাঙলা কিবোর্ড** → **Add**.
3. Switch to it from the **🌐 / flag menu** (or ⌃Space) and type Banglish in any app.

## How it works

- [`Sources/main.swift`](Sources/main.swift): an `IMKServer` + an `IMKInputController`
  (`BanglaController`). On each key it grows a Roman buffer, transliterates with the shared
  engine (Swift port of `engine/phonetic/phonetic.hpp`), and shows the Bangla as **marked
  text** (underlined pre-edit). Space / punctuation / Return **commits** it; Backspace edits
  the pre-edit; Cmd/Ctrl/Opt chords pass through.
- The `Info.plist` `ComponentInputModeDict` + `InputMethodServerControllerClass` +
  `InputMethodConnectionName` are what register it as a `bn` input source.

## Verified vs. needs-relogin

- **Verified here:** compiles, `Info.plist` lints, the `@objc(BanglaController)` class is in
  the binary, code-signs, installs, and `TISRegisterInputSource` returns `0` (success).
- **Needs your login session:** appearing in the Input Sources list + typing — because
  macOS rebuilds that list at login. Log out/in once, then add it as above.

The transliteration it will produce is the same engine verified headless by
`engine/phonetic/test.cpp` (156/156) — e.g. `ami`→আমি, `kormo`→কর্ম, `kkh`→ক্ষ, `bidya`→বিদ্যা.
