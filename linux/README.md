# Bangla Keyboard — Linux port (IBus)

> **Status: shipping — `linux-v1.1.1`.** An **IBus engine** that reuses the shared C++17 **phonetic
> engine** (`../engine/phonetic`) — the same Banglish transliteration + offline suggestion index as
> macOS + Windows, so input and word suggestions are identical across platforms. One engine:
> **বাংলা (Banglish)** — type romanized (`amar` → আমার) and it becomes Bangla as you type. Built +
> tested on **Ubuntu 24.04** (GNOME/IBus); should work on any distro with IBus (Debian, Fedora, Arch, …).

Verified end-to-end via `linux/test.sh` (real key events → IBus → committed Bangla), plus the shared
engine's own headless self-test (`wordtest`) run during every build.

## How it works
- **One engine, reused.** `ibus-bangla.cpp` is a thin IBus `IBusEngine` subclass; the actual Banglish
  logic is the shared header-only [`../engine/phonetic`](../engine/phonetic) (pure C++17, no OS deps) —
  so there is **one** transliterator + dictionary across all three platforms.
- **Preedit + lookup table.** The romanized syllables transliterate live into the **preedit**
  (underlined); the offline dictionary + AiCMS romanization aliases fill IBus's native **candidate
  lookup table**. It commits on a word boundary / candidate selection / focus-out. All Ctrl/Alt/Super
  shortcuts pass through untouched.
- **Keys.** Keys arrive as ordinary US-QWERTY keyvals — no scan-code mapping needed.

## Requirements
```sh
# Debian/Ubuntu:
sudo apt install build-essential pkg-config libibus-1.0-dev ibus
# Fedora:  sudo dnf install gcc-c++ pkgconf-pkg-config ibus-devel ibus
# Arch:    sudo pacman -S base-devel ibus
```

## Install — Debian / Ubuntu (`.deb`, easiest)
Download `bangla-keyboard-ibus_<ver>_amd64.deb` from the
[**latest release**](https://github.com/aicmsbd/bangla-keyboard/releases), then:
```sh
sudo apt install ./bangla-keyboard-ibus_*.deb   # pulls in ibus if needed
```
**Log out and back in** (GNOME reads new IBus engines at login), then add the input source (below).
The dictionary installs to `/usr/share/bangla-keyboard`. Build your own `.deb` with `./build-deb.sh`
(a generic `.tar.gz` for any distro is produced by CI).

## Build & install from source (any IBus distro)
```sh
cd linux
./build.sh              # -> linux/dist/ibus-engine-bangla (+ shared-engine self-test)
sudo ./install.sh       # installs the binary + dictionary + IBus component, system-wide
ibus restart            # or log out / back in
```
Then add it as an input source:
- **GNOME:** Settings → Keyboard → Input Sources → **+** → **Bangla** → **বাংলা (Banglish)**.
- Switch inputs with **Super+Space**; type on a US-QWERTY layout.

`./test.sh` runs the end-to-end key→commit test (needs the engine installed).
`sudo ./uninstall.sh` removes it.

## Typing
Fully **phonetic (Banglish)**: type romanized and it transliterates into the underlined preedit
(`amar` → আমার), committing on space / word boundary. While typing, the candidate lookup table shows
suggested words — press **1–6** to pick one, or **↑/↓** then **space**.

Suggestions recall ya-phola (`্য`) / ba-phola (`্ব`) words typed the natural way (`jonno` → জন্য,
`bissho` → বিশ্ব, `dip` → দ্বীপ); mixed-case and loose spellings all match
(`sochokke` / `ShoWchoKKHE` → সচক্ষে).

Output is **standard Unicode** — no bundled fonts. Use any Bangla Unicode font (most distros ship one;
e.g. `sudo apt install fonts-beng`).

## Files
- `ibus-bangla.cpp` — the IBus engine (reuses `../engine/phonetic`).
- `ibus-selftest.cpp` — end-to-end key→commit test client.
- `build.sh` / `install.sh` / `uninstall.sh` / `test.sh` / `build-deb.sh`.
- `icons/` — engine icon.
- `dist/` — build output (git-ignored).

## Notes
- **Privacy.** No network calls at all — the engine never opens a socket. No telemetry, no accounts;
  everything (transliteration + suggestions) runs on-device.
- **License.** AICMS Public License v1.0. `LICENSE` + `NOTICE` are bundled in the `.deb` and tarball;
  required visible credit: *"powered by AiCMS.BD • Brought You By Bangla.it.com"*. Independent project,
  not affiliated with any vendor.
- **Wayland & X11** both work (IBus handles both). Under Wayland, IBus is the standard input-method
  path for GTK/Qt apps.
- Not building a Fcitx5 addon yet — IBus covers GNOME (the most common default) and is available
  everywhere. Fcitx5 can be added later reusing the same phonetic engine.
