# Bangla Keyboard — Windows installer

> **Status: shipping.** The tray app ([`../tray/`](../tray/)) is packaged into a
> branded **`BanglaKeyboard-Setup-<ver>.exe`** by **Inno Setup 6**.

The installer is defined in [`banglakeyboard.iss`](banglakeyboard.iss). It's a
**per-user** install (`PrivilegesRequired=lowest`): no admin/UAC, lands in
`%LocalAppData%\Programs\Bangla Keyboard`, with a per-user Start Menu entry and an
optional "start at sign-in" shortcut.

## Build
1. Build the tray app + dictionary with **MinGW** (w64devkit) — from `windows/`:
   ```bash
   ./build-all.sh     # -> dist/bangla-tray.exe (+ bangla-dictionary.txt, hardwords_raw.tsv)
   ```
2. Package the installer with **Inno Setup 6** — from `windows/installer/`:
   ```bat
   iscc banglakeyboard.iss     :: -> dist\BanglaKeyboard-Setup-<ver>.exe
   ```

The package bundles the tray app, its offline dictionary + AiCMS romanization aliases
(`bangla-dictionary.txt`, `hardwords_raw.tsv` — loaded next to the `.exe` to power the
Banglish suggestion popup), the app icon, `USAGE.txt`, and `LICENSE.txt` + `NOTICE.txt`.
No fonts are bundled — the keyboard emits standard Unicode and renders with any system
Bangla font (Windows ships "Nirmala UI" with Bengali coverage).

## Versioning — keep three files in sync
`windows/VERSION`, `windows/tray/tray.rc` (`FILEVERSION`/`PRODUCTVERSION`), and
`#define MyAppVersion` in [`banglakeyboard.iss`](banglakeyboard.iss).

## Code signing / SmartScreen
The installer is **unsigned** for now, so SmartScreen shows a warning on first run —
users click **More info → Run anyway**. To sign it later:
```bat
signtool sign /fd SHA256 /a /tr http://timestamp.digicert.com /td SHA256 dist\BanglaKeyboard-Setup-<ver>.exe
```

## Checklist
- [ ] Bump the version in all three files above.
- [ ] `windows/build-all.sh` (compiles + runs the shared engine self-test `wordtest`, then builds the tray).
- [ ] `iscc banglakeyboard.iss` → `dist\BanglaKeyboard-Setup-<ver>.exe`.
- [ ] Test on a clean user: install (per-user, no admin) → tray icon appears →
      **Ctrl+Alt+B** toggles বাংলা ⇄ English (types Bangla in any app) → uninstall removes it.
