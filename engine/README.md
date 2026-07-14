# engine/ — the shared phonetic engine (source of truth)

[`phonetic/`](phonetic/) is the **one** engine behind বাঙলা কিবোর্ড on every platform. It is
**pure C++17, header-only, with no OS dependencies**, so each platform shell embeds it unchanged
and it is unit-testable headless.

It does two things, offline:

- **Transliteration** — romanized ("Banglish") input becomes Bangla as you type
  (`amar` → আমার), emitting standard Unicode (no bundled fonts; uses any system Bangla font).
- **Suggestions** — an offline index over a ~35k-word dictionary plus AiCMS romanization aliases.
  It recalls ya-phola (্য) / ba-phola (্ব) words typed the natural way (`jonno` → জন্য,
  `bissho` → বিশ্ব, `dip` → দ্বীপ), and matches loose / mixed-case spellings
  (`sochokke`, `ShoWchoKKHE` → সচক্ষে). No network access at all.

The data lives in [`phonetic/data/`](phonetic/data/): `bangla-dictionary.txt` and
`tools/hardwords_raw.tsv`. Every platform ships the same data and gets the same behaviour.

The platform shells are thin wrappers around this engine:
[`../macos/app/`](../macos/app/) (Swift menu-bar app, CGEventTap),
[`../windows/tray/`](../windows/tray/) (tray app, WH_KEYBOARD_LL hook), and
[`../linux/`](../linux/) (IBus engine).

## Build & test

```bash
cd phonetic && ./build.sh     # builds phontest + wordtest, runs the headless self-test
```

See [`phonetic/README.md`](phonetic/README.md) for the file map, the embedding API, and how to
run the transliteration corpus (`test.cpp`) and the dictionary regression (`wordtest.cpp`).
