#!/usr/bin/env python3
# Regenerate the macOS app UI's embedded word list + romanization aliases from the offline
# dictionary, and inject them into index.html. Run after growing the dictionary:
#   python3 macos/app/ui/gen_words.py
#
#   WORDS = every dictionary word, frequency-sorted (pipe-joined).
#   ALI   = "word<TAB>roman1<TAB>roman2.." records from the AiCMS hard-word romanizations,
#           so hard/long words are recalled by the exact spellings people type.
import re, pathlib

HERE = pathlib.Path(__file__).resolve()
ROOT = HERE.parents[3]                       # repo root
DICT = ROOT / 'engine/phonetic/data/bangla-dictionary.txt'
RAW  = ROOT / 'engine/phonetic/data/tools/hardwords_raw.tsv'
ENG  = ROOT / 'engine/phonetic/data/english-words.txt'   # frequency-ordered English list (spell-help)
HTML = HERE.parent / 'index.html'

# 1. words in frequency order (the dictionary is already frequency-sorted)
words, seen = [], set()
for line in open(DICT, encoding='utf-8'):
    w = line.split('\t')[0].strip()
    if w and w not in seen:
        seen.add(w); words.append(w)
WORDS_JS = 'const WORDS = "' + '|'.join(words) + '".split("|");'

# 2. alias records: word + its ASCII romanizations
ali = []
if RAW.exists():
    for line in open(RAW, encoding='utf-8'):
        p = [x.strip() for x in line.rstrip('\n').split('\t')]
        if not p or not p[0] or p[0] not in seen:
            continue
        romans = [r for r in p[1:] if r and all(ord(c) < 128 for c in r)]
        if romans:
            ali.append('\t'.join([p[0]] + romans))
ALI_JS = ('const ALI = "' + '|'.join(ali) + '".split("|");') if ali else 'const ALI = [];'

# 3. English words (frequency-ordered) for the English-mode spelling suggestions
enwords = []
if ENG.exists():
    for line in open(ENG, encoding='utf-8'):
        w = line.strip()
        if w:
            enwords.append(w)
EN_JS = 'const EN_WORDS = "' + '|'.join(enwords) + '".split("|");'

# 4. inject into index.html (replace the WORDS/ALI/EN_WORDS lines)
html = open(HTML, encoding='utf-8').read()
html = re.sub(r'\n?const ALI = [^\n]*;', '', html)                        # drop old ALI
html = re.sub(r'\n?const EN_WORDS = [^\n]*;', '', html)                   # drop old EN_WORDS
html = re.sub(r'const WORDS = "[^"]*"\.split\([^)]*\);',
              lambda m: WORDS_JS + '\n' + ALI_JS + '\n' + EN_JS, html, count=1)
open(HTML, 'w', encoding='utf-8').write(html)
print(f'embedded {len(words)} bn words + {len(ali)} aliases + {len(enwords)} en words into {HTML.name}')
