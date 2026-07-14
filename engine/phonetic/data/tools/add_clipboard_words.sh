#!/usr/bin/env bash
# Ingest a clipboard batch of AiCMS hard words into the offline dictionary — EXACTLY, with
# no retyping. Copy lines of the form "বাংলা, roman1, roman2, roman3, roman4, roman5" to the
# clipboard, then run this. The Bangla word (col 1) is added to the curated hard-word set and
# the whole dictionary is rebuilt; the romanization variants are kept in hardwords_raw.tsv.
set -euo pipefail
cd "$(dirname "$0")/.."            # -> engine/phonetic/data
# Source is a file path if given, else the macOS clipboard (UTF-8).
if [ -n "${1:-}" ]; then cp "$1" /tmp/_bkbatch.txt
else LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pbpaste > /tmp/_bkbatch.txt 2>/dev/null; fi

python3 - <<'PY'
import re, unicodedata
BENG = re.compile(r'^[ঀ-৿]+$')
def clean(w): return unicodedata.normalize('NFC', w.strip()).replace('‌','').replace('‍','')
seen = set()
try:
    for l in open('tools/aicms_words.tsv', encoding='utf-8'):
        if l.strip(): seen.add(l.split('\t')[0])
except OSError: pass
new = []
with open('tools/hardwords_raw.tsv', 'a', encoding='utf-8') as raw:
    for line in open('/tmp/_bkbatch.txt', encoding='utf-8'):
        line = line.rstrip('\n')
        if not line.strip(): continue
        parts = [p.strip() for p in line.split(',')]
        w = clean(parts[0])
        if len(w) < 2 or not BENG.match(w): continue
        raw.write('\t'.join([w] + parts[1:]) + '\n')     # keep word + its 5 roman variants
        if w not in seen: new.append(w); seen.add(w)
with open('tools/aicms_words.tsv', 'a', encoding='utf-8') as f:
    for w in new: f.write(f'{w}\t90\n')
print(f'batch: +{len(new)} new hard words (curated total {len(seen)})')
PY

# rebuild the dictionary = existing words + curated hard words (keep everything, dedup, NFC)
python3 - <<'PY'
import re, unicodedata
BENG = re.compile(r'^[ঀ-৿]+$'); f = {}
def add(path, default=1):
    try: fh = open(path, encoding='utf-8')
    except OSError: return
    for line in fh:
        p = line.rstrip('\n').split('\t')
        if not p or not p[0]: continue
        w = unicodedata.normalize('NFC', p[0]).replace('‌','').replace('‍','')
        if len(w) < 2 or not BENG.match(w): continue
        fr = int(p[1]) if len(p) > 1 and p[1].strip().isdigit() else default
        f[w] = max(f.get(w, 0), fr)
add('bangla-dictionary.txt'); add('tools/aicms_words.tsv', 90)
out = sorted(f.items(), key=lambda x: (-x[1], len(x[0])))
open('bangla-dictionary.txt', 'w', encoding='utf-8').write('\n'.join(f'{w}\t{c}' for w, c in out) + '\n')
print(f'dictionary now {len(out)} words')
PY
