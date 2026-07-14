# Releasing the Windows build

**One monorepo** — the shared phonetic engine (`engine/phonetic/`) plus per-platform
front-ends (`macos/`, `windows/`, `linux/`), separate tag namespaces. macOS ships as
the "Latest" `vX.Y.Z` release; Windows ships on a **separate `win-` tag** as a
**pre-release** so it never disturbs the macOS "Latest" release.

## Versioning — keep three files in sync
1. `windows/VERSION`
2. `windows/tray/tray.rc` (`FILEVERSION` / `PRODUCTVERSION`)
3. `windows/installer/banglakeyboard.iss` (`#define MyAppVersion`)

## 1. Build everything
On a machine with MinGW-w64 g++ (e.g. w64devkit) and a POSIX shell:
```bash
cd windows
GXX64=/path/to/g++ ./build-all.sh    # -> dist/bangla-tray.exe (+ dictionary)
```
`build-all.sh` first compiles and runs the shared phonetic engine self-test
(`wordtest`) under MinGW — the recall regression — then builds `bangla-tray.exe`
and copies the offline dictionary (`bangla-dictionary.txt`) and AiCMS romanization
aliases (`hardwords_raw.tsv`) next to it. A broken engine fails the Windows build.

## 2. Build the installer (Inno Setup 6)
```bat
cd windows\installer
iscc banglakeyboard.iss     :: -> dist\BanglaKeyboard-Setup-<ver>.exe
```
Smoke-test on a clean user: install (per-user, no admin) → tray icon appears →
Ctrl+Alt+B toggles বাংলা ⇄ English (types Bangla in any app) → uninstall removes it.

## 3. Publish CODE
```bash
git checkout main && git pull
git checkout -b windows-<topic>
# …work, scoped to windows/ (don't touch macos/, linux/, or engine/ unless it's a
#   real cross-platform fix)…
git commit -m "windows: <what> ...Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push -u origin windows-<topic>      # then PR -> merge to main
```

## 4. Cut the GitHub RELEASE — `win-v<ver>`, **pre-release**
The macOS app's release is tagged `vX.Y.Z` and marked **Latest**. Keep Windows on a
**separate `win-` tag** and **`--prerelease`** so it stays out of "Latest" (so a Mac
updater reading `releases/latest` never sees a Windows build):
```bash
gh release create win-v1.1.3 \
  windows/installer/dist/BanglaKeyboard-Setup-1.1.3.exe \
  --prerelease \
  --title "Bangla Keyboard for Windows 1.1.3" \
  --notes "…what's new… Unsigned — SmartScreen: More info -> Run anyway."
```
Attach only the installer `.exe`.

CI (`.github/workflows/build.yml`) also builds each platform on its native runner and
runs the shared engine self-test (`wordtest`) on Windows/Linux, so release assets can
be taken straight from a green CI run.

## When Windows + macOS + Linux unify (later)
Once stable, switch to one `vX.Y.Z` release per version carrying every platform's
asset (`বাঙলা কিবোর্ড.dmg` for macOS, `BanglaKeyboard-Setup-*.exe` for Windows,
`.deb` + tarball for Linux), not a pre-release — the VS Code / Obsidian model.
