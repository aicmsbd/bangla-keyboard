#!/usr/bin/env python3
# Build engine/phonetic/data/bangla-dictionary.txt ("word<TAB>freq", frequency-sorted, NFC,
# Bengali-only, deduped) from AiCMS's own sources only. See data/README.md.
#
# Inputs (pass any that exist; all optional):
#   --news    news_words.tsv    "word<TAB>count" from scrape_news.sh (public BD news vocabulary)
#   --curated aicms_words.tsv   "word<TAB>freq"  AiCMS-curated hard/formal words (language facts)
#   --extra   extra.tsv         "anything<TAB>bangla" (bangla taken from col 2)
#   --out     bangla-dictionary.txt
import re, argparse, unicodedata

BENG = re.compile(r'^[ঀ-৿]+$')
def clean(w): return unicodedata.normalize('NFC', w.strip()).replace('‌', '').replace('‍', '')

def add(freq, path, scale=1, default=1, col=0):
    if not path: return 0
    n = 0
    try: fh = open(path, encoding='utf-8')
    except OSError: return 0
    for line in fh:
        line = line.rstrip('\n')
        if not line: continue
        p = line.split('\t')
        if len(p) == 1 and ' ' in line: p = line.rsplit(' ', 1)   # "word count"
        w = clean(p[col] if col < len(p) else p[0])
        fr = default
        if col == 0 and len(p) > 1 and p[1].strip().isdigit(): fr = int(p[1].strip())
        if len(w) < 2 or not BENG.match(w): continue
        if all(0x09E6 <= ord(c) <= 0x09EF or c in '।॥ঃ' for c in w): continue  # digits/punct only
        freq[w] = freq.get(w, 0) + fr * scale
        n += 1
    return n

ap = argparse.ArgumentParser()
ap.add_argument('--news'); ap.add_argument('--curated'); ap.add_argument('--extra')
ap.add_argument('--out', default='bangla-dictionary.txt')
a = ap.parse_args()

freq = {}
nn = add(freq, a.news,    scale=25)                # boost so current news terms rank
nc = add(freq, a.curated, default=80)             # AiCMS-curated hard/formal words
ne = add(freq, a.extra,   default=60, col=1)
items = sorted(freq.items(), key=lambda kv: (-kv[1], len(kv[0])))
with open(a.out, 'w', encoding='utf-8') as o:
    for w, fr in items: o.write(f"{w}\t{fr}\n")
print(f"news:{nn} curated:{nc} extra:{ne} -> {len(items)} distinct words in {a.out}")
