<h1 align="center">বাঙলা কিবোর্ড — Bangla Keyboard</h1>

<p align="center">
  A free, fully-offline <b>phonetic ("Banglish") Bangla keyboard</b> for <b>macOS, Windows, and Linux</b>.<br>
  Type the way you already do — <code>amar bangla</code> → <b>আমার বাংলা</b> — with live word suggestions.<br>
  One shared engine, one offline dictionary, identical behaviour on every platform. Emits standard Unicode.
</p>

<p align="center"><i>powered by <a href="https://aicms.bd">AiCMS.BD</a> • Brought You By <a href="https://bangla.it.com">Bangla.it.com</a> 🇧🇩</i></p>

---

## What it does

- **Phonetic typing (Banglish).** Type romanized and it becomes Bangla as you go — `amar` → আমার,
  `kormo` → কর্ম, `prem` → প্রেম, `biddaloy` → বিদ্যালয়, `bishwo` → বিশ্ব, `jNGan` → জ্ঞান.
- **Live suggestions from an offline dictionary.** A built-in **“Bangla Dictionary”** (~35k words +
  an AiCMS-curated hard-word set) completes long, conjunct-heavy words from the first few letters and
  matches **however you spell it** — `ShoWchoKKHE` / `sochokke` / `sochokkhe` all find **সচক্ষে**;
  `jonno` → জন্য, `bissho` → বিশ্ব, `opekkha` → অপেক্ষা. Press **1–6** to pick a word.
- **Works in any app, system-wide.** Type Bangla into your browser, editor, chat — anywhere.
- **Fully offline.** No network calls, no telemetry, no accounts. Nothing you type ever leaves your machine.
- **No bundled fonts.** Emits standard Unicode; renders with any system Bangla font.

## Platforms

| OS | What it is | Download | Folder |
|----|-----------|----------|--------|
| 🍎 **macOS** | Menu-bar app — types Bangla system-wide via a global hook, with a suggestion popup at the cursor | `বাঙলা কিবোর্ড.dmg` | [`macos/`](macos/) |
| 🪟 **Windows** | Tray app — a keyboard hook types Bangla in any app via `SendInput`, with a suggestion popup | `BanglaKeyboard-Setup-*.exe` | [`windows/`](windows/) |
| 🐧 **Linux** | IBus engine — phonetic preedit + native candidate list | `bangla-keyboard-ibus_*.deb` + tarball | [`linux/`](linux/) |

## Install & use

Grab your platform's build from the [**releases page**](https://github.com/aicmsbd/bangla-keyboard/releases).

### 🍎 macOS
1. Open **`বাঙলা কিবোর্ড.dmg`** and drag the app to **Applications**. Launch it (first run: **right-click → Open**).
2. Grant **System Settings → Privacy & Security → Accessibility** (needed to type into other apps).
3. **⌃B** = বাংলা, **⌃E** = English. Type Banglish anywhere; press **1–6** to pick a suggestion.

More: [`macos/README.md`](macos/README.md).

### 🪟 Windows
1. Run **`BanglaKeyboard-Setup-*.exe`** (per-user, no admin; SmartScreen → *More info → Run anyway*).
2. A **tray icon** appears. **Ctrl+Alt+B** (or click the icon) toggles **বাংলা ⇄ English**.
3. Type Banglish in any app; press **1–6** to pick a suggestion.

More: [`windows/README.md`](windows/README.md).

### 🐧 Linux (Debian / Ubuntu + any IBus distro)
1. `sudo apt install ./bangla-keyboard-ibus_*.deb`  (other distros: `cd linux && sudo ./install.sh`).
2. Log out/in, then **Settings → Keyboard → Input Sources → `+` → Bangla → বাংলা (Banglish)**.
3. Switch with **Super+Space** and type phonetically; press **1–6** to pick a suggestion.

More: [`linux/README.md`](linux/README.md).

## How it works — one engine, three thin shells

All three platforms share **one phonetic engine** and wrap it in a thin OS-specific shell:

- **[`engine/phonetic/`](engine/phonetic/)** — the canonical engine (pure C++17, header-only, unit-tested
  headless: `cd engine/phonetic && ./build.sh`). Transliteration + the offline suggestion index.
- **[`PHONETIC.md`](PHONETIC.md)** — the spec: transliteration rules, the suggestion algorithm, and the
  test corpus every shell must pass.
- The macOS app ports the transliteration to Swift for its hook; Windows and Linux compile the C++ engine
  directly. Same dictionary + aliases everywhere, so suggestions are identical across platforms.

## Repository layout
```
.
├── PHONETIC.md      # phonetic (Banglish) engine + suggestions spec — the contract
├── engine/phonetic/ # canonical engine (portable C++17) + offline dictionary/aliases
├── macos/app/       # shipping macOS menu-bar app (Swift) + suggestion popup
├── windows/tray/    # Windows tray app (global hook) + suggestion popup
├── linux/           # Linux IBus engine + native candidate list
├── LICENSE          # AICMS Public License v1.0
├── NOTICE           # required attribution
├── DISCLAIMER.md    # independent project — not affiliated with any vendor
└── SECURITY.md
```

## License & attribution
AICMS Public License v1.0 — see [`LICENSE`](LICENSE). Required visible credit (see [`NOTICE`](NOTICE)):

> **powered by AiCMS.BD • Brought You By Bangla.it.com**

If you distribute a modified version or a new project built from this repository, keep it open source and
retain this credit. Independent project — not affiliated with any commercial Bangla keyboard or font vendor
(see [`DISCLAIMER.md`](DISCLAIMER.md)).

<p align="center">powered by <a href="https://aicms.bd">AiCMS.BD</a> • Brought You By <a href="https://bangla.it.com">Bangla.it.com</a> 🇧🇩</p>
