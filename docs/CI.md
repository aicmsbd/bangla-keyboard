# Building all platforms with GitHub Actions

A single dev machine can't cross-compile macOS + Windows + Linux, so the build runs on
GitHub's native runners. The workflow is [`.github/workflows/build.yml`](../.github/workflows/build.yml).

## What it produces (per run, as downloadable artifacts)

| Artifact | Platform | Built by |
|---|---|---|
| `বাঙলা কিবোর্ড.dmg` | macOS | `macos/app/build.sh` + `build_dmg.sh` on `macos-13` |
| `BanglaKeyboard-Setup-*.exe` | Windows | tray keyboard via MinGW + Inno Setup installer |
| `bangla-keyboard-ibus_*.deb` + `*-linux-x86_64.tar.gz` | Linux | `linux/build-deb.sh` on `ubuntu-latest` (.deb for Debian/Ubuntu; tarball for any distro) |

## Running the build

The workflow runs automatically on every push to `main`, on pull requests, and can be
started manually from the repo's **Actions** tab (**build → Run workflow**). Download the
built packages from the run's **Artifacts** section.

## Cutting a release (attach packages to a GitHub Release)

Push a version tag and the `release` job attaches all artifacts to a new Release:

```bash
git tag v1.0.0    # or win-v1.0.0 / linux-v1.0.0
git push origin v1.0.0
```

## Optional: persistent macOS signing

Without secrets, CI ad-hoc-signs the DMG — it works, but each released version needs its
own Accessibility grant. To sign every release with the **same** stable certificate (so the
grant persists for users across updates), export your local signing cert and add it as two
repo secrets (**Settings → Secrets and variables → Actions**):

```bash
macos/app/setup-signing.sh --export     # prints the two secret values
```

- `MACOS_SIGN_P12_BASE64` — the base64 blob it prints
- `MACOS_SIGN_P12_PASSWORD` — the random password it prints (unique each run)

The `macos` job imports it into the keychain path `build.sh` expects and signs with the
`Bangla Keyboard Dev` identity automatically. (This cert is self-signed — it makes the
Accessibility grant stable; it does **not** provide Apple notarization, so Gatekeeper still
shows the usual first-run "unidentified developer" prompt.)

## Notes

- Every platform shares one phonetic ("Banglish") engine (`engine/phonetic`, header-only
  C++17). The Windows and Linux jobs compile and run its headless self-test (`wordtest`)
  before packaging, so a broken engine fails the build.
- On Windows the Inno Setup installer packages the system-tray keyboard (`windows/tray`),
  a pure Win32 app with no third-party runtime dependency.
- The Linux `.deb` targets Debian/Ubuntu; the tarball (binary + IBus component XML + icons +
  `install.sh`) covers Fedora/Arch/other distros.
