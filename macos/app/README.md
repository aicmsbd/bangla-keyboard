# বাঙলা কিবোর্ড (Bangla Keyboard) — native macOS app

A real, "drag-to-install" Mac app: a **single styled DMG** (like Chrome's) → drag onto
**Applications** → launch. It's an always-on-top toolbar with your logo, a **বাংলা / English**
toggle, live suggestions, and a **system-wide phonetic hook** so
typing Banglish becomes Bangla in **any** app.

```
Ctrl+B → Bangla     Ctrl+E → English
```

## Build

```bash
cd macos/app
./build_dmg.sh        # -> dist/বাঙলা কিবোর্ড.dmg  (styled drag-to-Applications installer)
```

Requirements: Xcode command-line tools (`swiftc`, `hdiutil`, `codesign`). `./build.sh` builds
just the `.app`.

## Install & first run

1. Open **`বাঙলা কিবোর্ড.dmg`** → **drag the app onto Applications**.
2. Launch it (unsigned build → right-click → **Open** the first time).
3. Grant the one thing macOS requires of *any* third-party keyboard (one-time):
   - **Accessibility** (Privacy & Security → Accessibility → enable বাঙলা কিবোর্ড) → type into
     other apps. The app polls for the grant and turns on automatically — no restart.

## How it works

- **UI** ([`ui/index.html`](ui/index.html)) in a `WKWebView`: logo, mode toggle, candidates
  — self-contained (logo + engine + dictionary inline, no network).
- **Typing** ([`Sources/main.swift`](Sources/main.swift), `Hook`): a `CGEventTap`
  transliterates keystrokes with the shared engine and injects Bangla into the focused app.
  **Zero telemetry:** nothing is sent anywhere.

## Verified vs. needs your machine

- **Verified here:** the **full app compiles + links + launches**; the styled DMG
  builds/mounts with the drag-to-Applications layout; the transliteration matches the C++
  tests (156/156).
- **Needs your Mac + a grant (can't auto-test headless):** system-wide typing (Accessibility).
