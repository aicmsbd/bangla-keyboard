# Phonetic ("Banglish") engine

The single shared engine for **বাঙলা কিবোর্ড (Bangla Keyboard)** by AiCMS.BD — type Bangla
in Roman letters (phonetic "Banglish" style; `amar` → আমার) with live word suggestions, all
fully offline. Every platform shell embeds this one engine unchanged — the macOS menu-bar app
(CGEventTap), the Windows tray app (WH_KEYBOARD_LL hook), and the Linux IBus engine — so the
data and behaviour are identical everywhere. Same project rule as the rest of the repo:
**pure C++17, OS-free, header-only**, so it is unit-testable headless.

Full contract: [`../../PHONETIC.md`](../../PHONETIC.md).

## Files

| file | what |
|---|---|
| `phonetic.hpp`  | `transliterate(roman) -> Bangla` (pure) + `Phonetic` pre-edit driver + NFC |
| `worddb.hpp`    | **the big offline "Bangla Dictionary"** — loads ~35k words, coarse-phonetic-key + fuzzy match, shortest-first |
| `data/bangla-dictionary.txt` | the word list (public BD news vocabulary + AiCMS-curated hard words); see [`data/README.md`](data/README.md) |
| `suggest.hpp`   | `Suggester`: candidates = transliteration + aliases + library (fully offline) |
| `dictionary.hpp`| small curated alias list (tricky spellings) |
| `session.hpp`   | `PhoneticSession` — one object a shell drives with key events |
| `corpus.hpp` + `test.cpp` | verified transliteration corpus + headless runner |
| `wordtest.cpp`  | library regression test (asserts `ShoWchoKKHE`/`sochokke`/`sochokkhe` → সচক্ষে) |
| `demo.cpp`      | portable console demo (loads the library) |

## Build & test

```bash
./build.sh              # build test + demo, run the regression corpus
```

Or by hand:

```bash
c++ -std=c++17 test.cpp -o phontest && ./phontest
c++ -std=c++17 demo.cpp -o bangla-phon
./bangla-phon --line "ami banglay gan gai"
echo "bishwobiddaloy" | ./bangla-phon --suggest
```

## Using it in a shell

```cpp
#include "phonetic.hpp"
#include "suggest.hpp"
#include "dictionary.hpp"

banglaphon::Phonetic  eng;                                  // pre-edit driver
banglaphon::Suggester sug(banglaphon::kDictionary, banglaphon::kDictionaryN);

// on each key:  eng.typeChar(c)  -> show currentBangla() as pre-edit
// on Backspace: eng.backspace()
// on boundary:  commit eng.currentBangla(); eng.reset(); insert the boundary char
// candidates:   sug.candidates(eng.romanBuffer())   // run debounced, off the UI thread
```

The suggester is **fully offline**: candidates come only from the exact
transliteration and the bundled offline dictionary — no network access at all.
See [`../../PHONETIC.md` §Privacy](../../PHONETIC.md) and
[`../../SECURITY.md`](../../SECURITY.md).
