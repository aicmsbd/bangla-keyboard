# Security

## Reporting

Found a security issue? Please open a GitHub issue (or contact AiCMS.BD at
<https://bangla.it.com>). We'll respond promptly.

## Security posture

বাঙলা কিবোর্ড (Bangla Keyboard) is a fully offline **phonetic ("Banglish")**
Bangla keyboard for macOS, Windows, and Linux. You type romanized text
(`amar → আমার`) and it becomes Bangla as you type, with live word suggestions.
It has a deliberately small attack surface:

- **No network access, no telemetry, no analytics, no accounts, no auto-update.**
  The project never opens a socket — it makes no network calls at all.
- **No credentials handled or stored.**
- **No fonts are bundled** (the keyboard emits standard Unicode and uses any
  system Bangla font).
- **One shared engine.** All three platforms run the same pure C++17,
  header-only phonetic engine (`engine/phonetic/`): transliteration plus an
  offline suggestion index (a bundled dictionary and AiCMS romanization
  aliases). Same data, same behaviour everywhere.

## Phonetic engine — word suggestions (fully offline)

The engine (`engine/phonetic/`) transliterates Roman input to Bangla entirely
offline, and adds **recommended words** from two purely local sources: the exact
transliteration itself and a large **bundled offline dictionary**
(`engine/phonetic/data/bangla-dictionary.txt`, ~35k words, loaded by
`worddb.hpp`) plus AiCMS romanization aliases
(`engine/phonetic/data/tools/hardwords_raw.tsv`). Audit notes:

- **Every suggestion source is local.** The dictionary is a bundled word list
  read from disk into memory. Candidates come only from the exact transliteration
  plus lookups in that in-memory index — nothing sent, nothing fetched.
- **The engine never opens a socket.** `suggest.hpp` performs no network calls of
  any kind — no HTTP client, no remote endpoint, no network code anywhere in the
  path. The engine is **100% offline** and contacts nothing.
- **No third-party host, ever.** No remote service is contacted and no query
  leaves the device, so there are no cookies, no cache, no redirects, and no
  identifiers — there simply is no request.
- **Nothing is written to disk or logged.** Candidates are computed in memory,
  shown, and dropped.
- **Compile-time-constant data.** The transliteration tables are constant and the
  dictionary is a read-only bundled asset; the only runtime input is the user's
  own Roman keystrokes. The engine is unit-tested headless (`test.cpp` /
  `wordtest.cpp`) with bounded, in-memory buffers.

## macOS (menu-bar app)

The macOS build (`macos/app/`, a Swift menu-bar app) installs a `CGEventTap`
that reads keystrokes and synthesizes Bangla **system-wide** into any app, and
draws a native candidate popup at the text caret (press `1`–`6` to pick).
`⌃B` switches to বাংলা, `⌃E` back to English. Audit findings:

- **No keystroke logging, storage, or transmission.** The tap holds only the
  *current word being composed* in memory and clears it on every word boundary —
  no file, network, or telemetry in the typing path.
- **Runs as the normal user, not root.** There are no privileged install scripts:
  the app ships as a drag-to-Applications `.dmg` ("বাঙলা কিবোর্ড.dmg"), not a
  `.pkg`, and writes nothing to `/Library`.
- **Accessibility grant is the one privilege.** A `CGEventTap` needs macOS
  Accessibility permission — the same TCC grant a keylogger would need — which the
  user approves in System Settings. The app does **not** exfiltrate anything (see
  above); the grant only lets it read and inject keystrokes locally.
- **Stable signing identity.** The app is signed with a stable self-signed
  certificate (`setup-signing.sh`) so the Accessibility grant survives rebuilds.

## Windows (tray app)

The Windows build (`windows/tray/`, a system-tray app) uses a global low-level
keyboard hook (`WH_KEYBOARD_LL`) — the standard way an input method sees
keystrokes — and types Bangla into any app via `SendInput`, with a candidate
popup. `Ctrl+Alt+B` (or the tray icon) toggles বাংলা ⇄ English. Audit findings:

- **No keystroke logging, storage, or transmission.** The app holds only the
  *current word* in memory and clears it on every word boundary — no file,
  network, or telemetry in the hook/engine path. No auto-update, no analytics.
- **No DLL-hijacking surface.** The exe calls
  `SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32)` at startup, so implicit
  DLL loads resolve from `System32` only (no app-dir/CWD planting). It is
  statically linked and imports **only system DLLs** (`kernel32`, `user32`,
  `gdi32`, `shell32`, `advapi32`, `msvcrt`).
- **Least privilege.** Runs as the normal user (no elevation); the Inno Setup
  installer (`BanglaKeyboard-Setup-*.exe`) is **per-user**, so
  installing/uninstalling needs no admin. The bundled dictionary ships next to
  the `.exe`.
- **Exception-safe hook.** The hook callback is wrapped so no C++ exception can
  escape into the OS input dispatch (a crash there would affect every app); on any
  error it drops its pending state and stays alive.
- **Bounded buffers.** The in-progress run is capped so a long burst or stuck
  auto-repeat can't grow memory/CPU unbounded.
- **Engine input safety.** The only runtime input is the user's own keystrokes,
  fed into the shared offline phonetic engine; no untrusted data crosses into it.

Built with MinGW via `windows/build-all.sh`.

## Linux (IBus engine)

The Linux build (`linux/`, an IBus engine named "বাংলা (Banglish)") shows a
phonetic preedit and uses IBus's native candidate lookup table (press `1`–`6`, or
`↑`/`↓` then space). Audit findings:

- **No keystroke logging, storage, or transmission.** The typing path transliterates
  the user's input via the shared offline engine and commits the result through
  IBus — no file, network, socket, or process-exec calls anywhere in it. No
  telemetry, no network.
- **Runs as the user, not root, not setuid.** `ibus-daemon` launches the engine as
  the logged-in user; the installed binary is mode 0755 (not setuid/setgid), so it
  grants no elevated privilege.
- **Bounds-safe.** IBus passes untrusted key input, but the engine validates it
  before use and caps the in-progress preedit run against unbounded growth from a
  stuck key, so there is no out-of-bounds access.
- **Exception-safe.** The key-event handler is wrapped so no C++ exception can
  unwind into IBus's C dispatch; on any error the engine drops its pending state
  and stays alive.
- **Installer.** `install.sh` (and the `.deb`) run as root but perform only
  fixed-path file writes and emit a **static** component XML — no dynamic/user
  input flows into any command, no downloads, no remote code. The dictionary
  installs to `/usr/share/bangla-keyboard`. Built via `linux/build.sh` (needs
  `libibus-1.0-dev`); ships as a `.deb` and a generic tarball.

## Known / accepted items

- **Windows: unsigned + keylogger-shaped tech.** The tray app is not code-signed
  yet (SmartScreen warns; *More info → Run anyway*), and a global keyboard hook is
  the same Windows API a keylogger uses — so some antivirus may heuristically flag
  it. It does **not** exfiltrate anything (see the audit above); a code-signing
  certificate + reputation removes both the SmartScreen prompt and most AV noise.

- **macOS: self-signed, not notarized.** The `.dmg` is signed with a stable
  self-signed certificate rather than an Apple Developer ID, so Gatekeeper shows
  an "unidentified developer" warning and users must right-click → **Open** the
  first time (and grant Accessibility). Signing/notarizing with an Apple Developer
  ID would remove that warning. This is a trust/UX item, not a code vulnerability.
