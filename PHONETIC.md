# Bangla Keyboard — phonetic ("Banglish") engine specification

**বাঙলা কিবোর্ড (Bangla Keyboard)** by **AiCMS.BD** is a fully offline **phonetic
(Banglish)** Bangla keyboard for macOS, Windows and Linux. You type Bangla the way most
Bangladeshis already do on phones — in Roman letters — and it becomes Bangla as you type,
with live word suggestions:

```
ami banglay gan gai   ->   আমি বাংলায় গান গাই
```

There is one input mode: **phonetic Banglish**. It gives you three things without giving up
the project's zero-network stance:

1. **Banglish phonetic typing** — forgiving, longest-match transliteration to standard
   Unicode (no bundled fonts; it uses any system Bangla font).
2. **Smart suggestions / recommended input** — fully offline word completion from the exact
   transliteration plus the bundled dictionary.
3. **Easy hard/long words** — the offline word library turns the first few letters of a
   painful conjunct-heavy word into one tap.

The reference implementation is [`engine/phonetic/phonetic.hpp`](engine/phonetic/phonetic.hpp)
(header-only, no OS deps, `std::u16string`) with the candidate layer in
[`engine/phonetic/suggest.hpp`](engine/phonetic/suggest.hpp) and the shell glue in
[`engine/phonetic/session.hpp`](engine/phonetic/session.hpp). The authoritative behaviour is
the regression corpus in [`engine/phonetic/test.cpp`](engine/phonetic/test.cpp) — if a rule
here and the corpus disagree, **the corpus wins**.

---

## 1. Architecture — one shared engine, three thin shells

The whole product is one pure, OS-free C++17 engine plus a thin per-OS shell. Every platform
runs the **same** transliteration and the **same** offline suggestion data:

```
        ┌───────────────────────────────────────────────┐
        │  PHONETIC ENGINE  (phonetic.hpp)               │
        │  transliterate(roman) -> Bangla  (pure)        │
        │  buffers roman keystrokes = preedit            │
        └───────────────────────────────────────────────┘
                              │
        ┌───────────────────────────────────────────────┐
        │  SUGGESTER  (suggest.hpp / worddb.hpp)         │
        │  candidates = translit + offline dictionary    │
        │  fully offline — no network path at all        │
        └───────────────────────────────────────────────┘
              ▲                ▲                 ▲
   macOS menu-bar app   Windows tray app    Linux IBus engine
   (CGEventTap +        (LL keyboard hook   (preedit + IBus
    caret popup)         + candidate popup)  lookup table)
```

The phonetic driver keeps the **Roman keystrokes of the current word** as the pre-edit and
re-derives the Bangla on every keystroke. That makes Backspace trivial (pop one Roman char,
re-transliterate) and makes candidate generation a pure function of the buffer.

---

## 2. Transliteration algorithm (`transliterate(roman)`)

Pure function, no state. Walk the Roman string left to right:

1. **Greedy longest match** (keys up to 3 chars) against the **case-sensitive** rule map
   (§3). Case matters: `t`=ত vs `T`=ট, `s`=স vs `S`=শ vs `Sh`=ষ, `o`=inherent vs `O`=ও.
2. Emit per the matched unit's kind, tracking the *previous emitted thing*
   (`None` / `Cons` / `Vowel` / `Other`):
   - **Consonant** → if the previous was a consonant, insert hasanta `্` first
     (**auto-conjunct**), then the consonant. State → `Cons`.
   - **Vowel** → after a consonant, emit the **kar** (dependent) form; otherwise emit the
     **independent** form. State → `Vowel`. (`o`'s kar is empty — the *inherent* vowel.)
   - **`y` / `w`** (context-sensitive semivowels) → after a consonant, `্য` ya-phola /
     `্ব` ba-phola; otherwise `য়` / `ওয়`. State → `Cons`.
   - **Sign** (anusvara `ং`, visarga `ঃ`, chandrabindu `ঁ`, digits, danda) → emit; it does
     not open a consonant. State → `Other`.
   - **Hasanta** (explicit ``` `` ``` or `,,`) → emit `্`, stay `Cons`.
   - **Unmatched byte** → passthrough; state → `Other`.
3. **NFC-normalize** the result (`ে+া→ো`, `ে+ৗ→ৌ`, base+nukta→`ড়/ঢ়/য়`).

**Reph, ra-phola and ya-phola fall out of auto-conjunct for free** — you type the
letters in speech order and the conjunct forms itself:

| you type | becomes | why |
|---|---|---|
| `kormo` | কর্ম | `r`+`m` conjunct = র্ম (reph) |
| `prem` | প্রেম | `p`+`r` conjunct = প্র (ra-phola) |
| `bidya` | বিদ্যা | `d`+`y` = দ্য (ya-phola) |
| `bishwo` | বিশ্ব | `sh`+`w` = শ্ব (ba-phola) |
| `boi` | বই | `o` inherent closes `b`, then `i` is independent |

---

## 3. Rule map (phonetic Banglish, case-sensitive)

**Vowels** (independent / kar): `o`=অ/·(inherent) · `O`=ও/ো · `a`/`A`=আ/া · `i`=ই/ি ·
`I`/`ee`=ঈ/ী · `u`/`oo`=উ/ু · `U`=ঊ/ূ · `e`=এ/ে · `OI`=ঐ/ৈ · `OU`=ঔ/ৌ · `rri`=ঋ/ৃ.

**Consonants:** `k`=ক `kh`=খ `g`=গ `gh`=ঘ `Ng`=ঙ · `c`=চ `ch`=ছ `j`=জ `jh`=ঝ `NG`=ঞ ·
`T`=ট `Th`=ঠ `D`=ড `Dh`=ঢ `N`=ণ · `t`=ত `th`=থ `d`=দ `dh`=ধ `n`=ন ·
`p`=প `ph`/`f`=ফ `b`=ব `bh`/`v`=ভ `m`=ম · `z`=য `r`=র `l`=ল ·
`sh`/`S`=শ `Sh`=ষ `s`=স `h`=হ · `R`=ড় `Rh`=ঢ় `y`=য়/ya-phola `Y`=য় `w`=ওয়/ba-phola.
Shortcuts: `kkh`/`kx`=ক্ষ · `x`=ক্স · `gg`=জ্ঞ.

**Signs / control:** `ng`=ং · `^`=ঁ · `H`=ঃ · `` t`` ``=ৎ · `.`=। · ``` `` ```/`,,`=explicit `্` ·
`0`–`9`=০–৯.

> The single source of truth is the table in `phonetic.hpp`. This section is that table in
> prose; if they disagree, `phonetic.hpp` (validated by `test.cpp`) wins.

---

## 4. Suggestions / recommended input ([`suggest.hpp`](engine/phonetic/suggest.hpp))

For the current Roman buffer the `Suggester` returns a ranked candidate list. **Every
candidate is produced offline** — from the exact transliteration and the bundled word
library. No network is ever involved.

1. **Exact transliteration** — always first, always offline, always instant.
2. **Curated aliases** — a hand-tuned list ([`dictionary.hpp`](engine/phonetic/dictionary.hpp))
   for the trickiest spellings (metathesis like `portigga`→প্রতিজ্ঞা), matched by exact
   Roman-prefix, Bangla-prefix, or a fuzzy key.
3. **The Bangla dictionary — the big offline library** (~35k words plus AiCMS romanization
   aliases; [`worddb.hpp`](engine/phonetic/worddb.hpp) +
   [`data/bangla-dictionary.txt`](engine/phonetic/data/bangla-dictionary.txt), with the
   aliases sourced from [`data/tools/hardwords_raw.tsv`](engine/phonetic/data/tools/)).
   Every word needs only its Bangla spelling; the "banglish" side is derived by a **coarse
   phonetic key** (`banglaToKey`) that the user's keystrokes are normalized into
   (`looseKey`) — folding case, the inherent `o`, aspirate `h` (kh↔k), sibilants, doubled
   letters, `v↔b`, `z↔j`, `w`, `y↔i`. So `ShoWchoKKHE`, `sochokke`, `sochokkhe` and
   **সচক্ষে** all share the key `scke` and match. Ranked **exact-key first (by frequency),
   then shortest word first**. The library loads once at startup; lookups are microseconds.

Recall also covers ya-phola `্য` / ba-phola `্ব` words typed the natural way
(`jonno`→জন্য, `bissho`→বিশ্ব, `dip`→দ্বীপ). `Suggester::offlineCandidates()` composes the
exact transliteration with the dictionary matches and returns an instant, network-free result
on every keystroke — there is no online path and nothing to debounce.

---

## 5. Privacy — zero telemetry, by construction

The suggestion feature keeps the project's stance (see [`SECURITY.md`](SECURITY.md)):

- **The app never opens a socket.** There is no network path and no online mode — the
  keyboard is **100% offline** and contacts nothing. No telemetry, no accounts.
- **Every candidate comes from the exact transliteration and the bundled offline
  dictionary** — nothing about what you type ever leaves the device.
- **Nothing is written to disk or logged** for suggestions — no keystroke stream, no ids,
  no history, no on-disk cache.
- The transliteration engine and dictionary are **compile-time-constant / bundled data**;
  no untrusted input crosses into them.

Because suggestions are entirely local, there is no network setting to configure — the
keyboard is offline by construction.

---

## 6. Shell integration (per OS)

The engine + suggester are portable; only the pre-edit + candidate UI is platform code. Each
shell drives one `PhoneticSession` (`session.hpp`): feed it key events and it returns the
`preedit` (marked/composing text), any `commit` string, whether the key was `consumed`, and
the offline `candidates` list. `backspace()`, `chooseCandidate()` and `flush()` cover the
rest.

- **macOS** — [`macos/app/`](macos/app/): a menu-bar app (Swift). A **CGEventTap** types
  Bangla **system-wide into any app**, with a native candidate popup at the text caret
  (press **1–6** to pick). Needs Accessibility permission. **⌃B** = বাংলা, **⌃E** = English.
  Ships as `বাঙলা কিবোর্ড.dmg` (drag-to-Applications), signed with a stable self-signed cert
  so the Accessibility grant survives rebuilds.
- **Windows** — [`windows/tray/`](windows/tray/): a tray app. A **WH_KEYBOARD_LL** global
  hook types Bangla in any app via **SendInput**, with a candidate popup. **Ctrl+Alt+B** (or
  the tray icon) toggles বাংলা ⇄ English. Ships as an Inno Setup installer
  `BanglaKeyboard-Setup-*.exe` (per-user, no admin); the dictionary ships next to the `.exe`.
- **Linux** — [`linux/`](linux/): an IBus engine. Phonetic preedit + IBus's native candidate
  **lookup table** (press **1–6**, or ↑/↓ then space). One engine named
  **"বাংলা (Banglish)"**. Ships as a `.deb` + a generic tarball; the dictionary installs to
  `/usr/share/bangla-keyboard`.
- **Threading**: candidates are computed synchronously and instantly — there is no network
  call to debounce or move off the UI thread.

---

## 7. Testing

```bash
cd engine/phonetic
./build.sh          # builds phontest + wordtest + demo, then runs the tests
```

`build.sh` compiles `test.cpp` → `phontest` (engine vs. verified corpus) and
`wordtest.cpp` → `wordtest` (offline word-library lookups). The corpus (`corpus.hpp`) is
generated and **adversarially spell-checked** by native-level review (two independent passes;
only confirmed pairs are kept). Add a new word by adding its `{input, expected, note}` row.

CI ([`.github/workflows/build.yml`](.github/workflows/build.yml)) builds each platform on its
native runner (macOS `.dmg`, Windows installer, Linux `.deb` + tarball) and runs the shared
engine self-test (`wordtest`) on Windows and Linux.
