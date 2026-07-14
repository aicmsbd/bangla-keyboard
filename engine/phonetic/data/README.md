# Bangla Dictionary — the offline word library

`bangla-dictionary.txt` is the offline library the phonetic mode recalls words from (loaded
at runtime by [`../worddb.hpp`](../worddb.hpp)). Format: one `word<TAB>freq` per line,
NFC-normalized, Bengali-only, deduped, frequency-sorted.

**AiCMS.BD's own compilation** — built entirely from public factual sources, with no
third-party word list bundled or derived:

| Source | What | Words |
|---|---|---|
| **Live news vocabulary** | `scrape_news.sh` harvests a **word-frequency list** (never article text) from the public RSS feeds + front pages of major Bangladeshi dailies | ~18.8k |
| **AiCMS-curated hard words** | `tools/aicms_words.tsv` — a hand-verified set of hard/formal Bangla words (each an individual language fact, spell-checked) | grows over time |

Individual words in a language are facts, not copyrightable; only a **word-frequency list**
is extracted from the news sources (no article text is reproduced), so nothing third-party
is redistributed. The list grows every time the scrape is re-run — add your own corpus via
`--curated` / `--extra` to expand it further.

## Regenerate

```bash
cd engine/phonetic/data/tools
./scrape_news.sh .                    # -> news_words.tsv (live public BD news vocabulary)
python3 build_dictionary.py --news news_words.tsv --curated aicms_words.tsv \
        --out ../bangla-dictionary.txt
```

## How matching works (why loose spelling is fine)

Each word only needs its Bangla spelling; the "banglish" side is derived by code.
`worddb.hpp` computes a **coarse phonetic key** for every word (`banglaToKey`) and
normalizes the user's keystrokes the same way (`looseKey`) — folding case, the inherent
`o`, aspirate `h` (kh↔k), sibilants, doubled letters, `v↔b`, `z↔j`, `w`, `y↔i`. So
`ShoWchoKKHE`, `sochokke`, `sochokkhe` and **সচক্ষে** all share the key `scke` and match.
Results are ranked: exact-key matches (by frequency) first, then shorter completions
(shortest word first), then frequency.
