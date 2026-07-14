# বাঙলা কিবোর্ড (Bangla Keyboard) for macOS

A free, **fully-offline phonetic ("Banglish") Bangla keyboard** for macOS (Apple
Silicon & Intel). Type romanized — `amar` → **আমার** — and it becomes Bangla as you
go, with live word **suggestions**. It emits standard Unicode, so **no font is
bundled** — text renders with any system Bangla font (macOS ships Bengali support
out of the box).

> A **menu-bar app**, part of the cross-platform [Bangla Keyboard](../README.md) project.
> Built and maintained by **[AiCMS.BD](https://bangla.it.com)**.

## What you get

- **Phonetic typing (Banglish), system-wide.** A `CGEventTap` transliterates your
  keystrokes with the shared engine and injects Bangla into **any** app — browser,
  editor, chat.
- **Live suggestions at the caret.** A native candidate popup appears at the text
  cursor; press **1–6** to pick a word. Long, conjunct-heavy words complete from the
  first few letters.
- **Matches however you spell it.** Loose and mixed-case spellings resolve to the same
  word — `ShoWchoKKHE` / `sochokke` → **সচক্ষে**. ya-phola (`্য`) and ba-phola (`্ব`)
  words typed the natural way work too: `jonno` → জন্য, `bissho` → বিশ্ব, `dip` → দ্বীপ.
- **One toggle.** **⌃B** = বাংলা, **⌃E** = English (or use the menu-bar item).

## Install

1. From the [**latest release**](https://github.com/aicmsbd/bangla-keyboard/releases/latest)
   download **`বাঙলা কিবোর্ড.dmg`** and open it.
2. **Drag the app onto Applications.**
3. First launch: the build is self-signed but **not notarized** (no paid Apple
   Developer ID), so Gatekeeper blocks a plain double-click — **right-click the app →
   Open → Open**.
4. Grant **System Settings → Privacy & Security → Accessibility** and enable
   **বাঙলা কিবোর্ড** — this is what lets it type into other apps. The app polls for the
   grant and turns on automatically; no restart needed.

Then press **⌃B**, type Banglish anywhere, and press **1–6** to pick a suggestion.

### "App is damaged and can't be opened"?

That's **Gatekeeper on a non-notarized download — not real damage** (common on Apple
Silicon). Drag the app out of the disk image to (say) your Desktop, then in
**Terminal** run:

```bash
xattr -dr com.apple.quarantine ~/Desktop/"বাঙলা কিবোর্ড.app"
```

…and open it.

### Re-granting Accessibility after an update

The app is signed with a **stable self-signed certificate**, so the Accessibility
grant normally **survives rebuilds and updates**. If system-wide typing ever stops
after replacing the app, remove **বাঙলা কিবোর্ড** from **Privacy & Security →
Accessibility** and add it back.

## How it works

- **Engine:** the shared, portable phonetic engine — transliteration plus an **offline
  suggestion index** built from a **~35k-word dictionary + AiCMS romanization aliases**
  (`../engine/phonetic/data/`). Same data and behaviour as the Windows and Linux
  builds. See [`../PHONETIC.md`](../PHONETIC.md).
- **Typing:** [`app/Sources/main.swift`](app/Sources/main.swift) installs a
  `CGEventTap`, transliterates keystrokes, and injects Bangla into the focused app; the
  candidate popup renders at the caret.
- **Privacy:** **no network calls at all — the app never opens a socket.** No telemetry,
  no accounts. Everything runs on-device.

## Build from source

```bash
cd macos/app
./build_dmg.sh        # → dist/বাঙলা কিবোর্ড.dmg  (drag-to-Applications installer)
```

`./build.sh` builds just the `.app`. Requirements: the Xcode command-line tools
(`swiftc`, `hdiutil`, `codesign`). Run **`./setup-signing.sh`** once to create the
stable self-signed identity (`Bangla Keyboard Dev`) so the Accessibility grant persists
across rebuilds; without it the app falls back to ad-hoc signing and the grant is
revoked on each build.

CI builds the DMG on a macOS runner via
[`.github/workflows/build.yml`](../.github/workflows/build.yml).

## Licensing

- Released under the **[AICMS Public License v1.0](../LICENSE)**. `LICENSE` and `NOTICE`
  are bundled inside the app. Required visible credit:

  > **powered by AiCMS.BD • Brought You By Bangla.it.com**

- **No fonts are bundled** — the keyboard emits standard Unicode, so there is no font
  license to carry.
- Independent community project — **not affiliated with any commercial keyboard or font
  vendor** (see [`../DISCLAIMER.md`](../DISCLAIMER.md)).

## Notes

- Works on **macOS 11 (Big Sur) and later**, Apple Silicon and Intel.
- Non-notarized build: Gatekeeper asks you to right-click → Open the first time.

---

Made with care by **[AiCMS.BD](https://bangla.it.com)** 🇧🇩
