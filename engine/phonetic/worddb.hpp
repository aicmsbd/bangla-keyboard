// Bangla Keyboard — large offline "Bangla Dictionary" for phonetic suggestions.
//
// Where dictionary.hpp is a small hand-curated alias list compiled into the binary, this
// is the BIG library: a word list (100k+ words harvested from Bangladeshi newspapers and
// a Bangla frequency corpus) loaded at runtime and matched by a COARSE PHONETIC KEY, so a
// word can be recalled from a loose/hard romanization and NO network is needed.
//
// The trick that makes 100k words cheap: an entry only needs its Bangla spelling. The
// "banglish" side is DERIVED by code — banglaToKey() romanizes the word to a coarse key,
// looseKey() normalizes the user's keystrokes into the same space. Both fold the things
// people vary: case, the inherent 'o', aspirate 'h' (kh↔k), sibilants, doubled letters,
// v↔b, z↔j, w, y↔i. So `ShoWchoKKHE`, `sochokke`, `sochokkhe` and the word সচক্ষে all map
// to the same key and match — and results are ranked SHORTEST WORD FIRST.
//
// Pure C++17, header-only. Uses only <fstream> (portable) for the optional file load — no
// OS headers — so it stays unit-testable headless and reusable in every shell.

#ifndef BANGLA_PHONETIC_WORDDB_HPP
#define BANGLA_PHONETIC_WORDDB_HPP

#include "phonetic.hpp"
#include <string>
#include <vector>
#include <algorithm>
#include <unordered_map>
#include <unordered_set>
#include <cstdint>
#include <fstream>
#include <sstream>

namespace banglaphon {

// Romanize a Bangla (NFC) word to a rough phonetic roman string. Not exact — just
// consistent enough that looseKey() collapses it to the same key as a user's typing.
inline std::string banglaToRoman(const Str& w, bool pholaSilent = false) {
    static const std::unordered_map<char16_t, const char*> C = {
        {0x0995,"k"},{0x0996,"kh"},{0x0997,"g"},{0x0998,"gh"},{0x0999,"ng"},
        {0x099A,"c"},{0x099B,"ch"},{0x099C,"j"},{0x099D,"jh"},{0x099E,"n"},
        {0x099F,"T"},{0x09A0,"Th"},{0x09A1,"D"},{0x09A2,"Dh"},{0x09A3,"n"},
        {0x09A4,"t"},{0x09A5,"th"},{0x09A6,"d"},{0x09A7,"dh"},{0x09A8,"n"},
        {0x09AA,"p"},{0x09AB,"ph"},{0x09AC,"b"},{0x09AD,"bh"},{0x09AE,"m"},
        {0x09AF,"j"},{0x09B0,"r"},{0x09B2,"l"},{0x09B6,"sh"},{0x09B7,"sh"},
        {0x09B8,"s"},{0x09B9,"h"},{0x09DC,"r"},{0x09DD,"rh"},{0x09DF,"y"},{0x09CE,"t"},
    };
    static const std::unordered_map<char16_t, const char*> V = {
        {0x0985,"o"},{0x0986,"a"},{0x0987,"i"},{0x0988,"i"},{0x0989,"u"},{0x098A,"u"},
        {0x098B,"rri"},{0x098F,"e"},{0x0990,"oi"},{0x0993,"o"},{0x0994,"ou"},
    };
    static const std::unordered_map<char16_t, const char*> K = {
        {0x09BE,"a"},{0x09BF,"i"},{0x09C0,"i"},{0x09C1,"u"},{0x09C2,"u"},{0x09C3,"rri"},
        {0x09C7,"e"},{0x09C8,"oi"},{0x09CB,"o"},{0x09CC,"ou"},{0x09D7,"ou"},
    };
    const char16_t HAS = 0x09CD;
    std::string out;
    bool prevCons = false;
    size_t i = 0, n = w.size();
    while (i < n) {
        // ya-phola ্য / ba-phola ্ব are usually silent/glide, not a full j/b (alt key only)
        if (pholaSilent && w[i] == HAS && i + 1 < n && (w[i+1] == 0x09AF || w[i+1] == 0x09AC)) { i += 2; continue; }
        // irregular-pronunciation conjuncts (as people actually type them)
        if (i + 2 < n && w[i] == 0x0995 && w[i+1] == HAS && w[i+2] == 0x09B7) {  // ক্ষ
            if (prevCons) out += 'o'; out += "kkh"; prevCons = true; i += 3; continue;
        }
        if (i + 2 < n && w[i] == 0x099C && w[i+1] == HAS && w[i+2] == 0x099E) {  // জ্ঞ
            if (prevCons) out += 'o'; out += "gg"; prevCons = true; i += 3; continue;
        }
        char16_t c = w[i];
        auto ci = C.find(c);
        if (ci != C.end()) { if (prevCons) out += 'o'; out += ci->second; prevCons = true; ++i; continue; }
        if (c == HAS)     { prevCons = false; ++i; continue; }                 // conjunct join
        auto ki = K.find(c);
        if (ki != K.end()) { out += ki->second; prevCons = false; ++i; continue; }
        auto vi = V.find(c);
        if (vi != V.end()) { if (prevCons) out += 'o'; out += vi->second; prevCons = false; ++i; continue; }
        if (c == 0x0982)  { out += "ng"; prevCons = false; ++i; continue; }    // anusvara ং
        // chandrabindu ঁ, visarga ঃ, nukta ়, ZWNJ/ZWJ, digits, etc. -> ignore
        ++i;
    }
    return out;
}

// Normalize a user's roman keystrokes into the same coarse key space as banglaToRoman.
// Aggressive by design (recall over precision — the user picks from the ranked list).
inline std::string looseKey(const std::string& s) {
    std::string a;
    for (char c : s) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
        if      (c == 'v') c = 'b';
        else if (c == 'z') c = 'j';
        else if (c == 'w') continue;         // drop w (ওয়/ba-phola noise)
        else if (c == 'y') c = 'i';
        a.push_back(c);
    }
    std::string o;
    auto vowel = [](char c) { return c == 'a' || c == 'e' || c == 'i' || c == 'u'; };
    for (char c : a) {
        if (c < 'a' || c > 'z') continue;
        if (c == 'o') continue;                                             // inherent-o ambiguity
        if (c == 'h' && !o.empty() && !vowel(o.back()) && o.back() != 'h') continue; // aspirate h
        if (!o.empty() && o.back() == c) continue;                          // doubled letters
        o.push_back(c);
    }
    return o;
}

inline std::string banglaToKey(const Str& w)    { return looseKey(banglaToRoman(w)); }
inline std::string banglaToKeyAlt(const Str& w) { return looseKey(banglaToRoman(w, true)); }

// The loaded dictionary. Entries are sorted by key so a prefix query is a binary search
// + a short contiguous scan; results are ranked shortest-word-first, then most-frequent.
class WordDB {
public:
    void addWord(const Str& w, uint32_t freq = 1) {
        if (w.empty()) return;
        const std::string k = banglaToKey(w);
        entries_.push_back({w, k, freq});
        const std::string ka = banglaToKeyAlt(w);          // ya/ba-phola-silent variant key
        if (!ka.empty() && ka != k) entries_.push_back({w, ka, freq});
        built_ = false;
    }

    // Register an explicit romanization -> word (AiCMS-curated aliases, so hard/long words are
    // recalled by the exact spellings people type). The word need not already be in the dict.
    void addAliasKey(const Str& w, const std::string& roman, uint32_t freq = 90) {
        const std::string k = looseKey(roman);
        if (!w.empty() && !k.empty()) { entries_.push_back({w, k, freq}); built_ = false; }
    }

    // Load "word<TAB>roman1<TAB>roman2.." records; every romanization becomes a lookup key.
    // Returns the number of alias keys added. Lines are assumed NFC-normalizable.
    size_t loadAliases(const std::string& path) {
        std::ifstream in(path);
        if (!in) return 0;
        std::string line;
        size_t added = 0;
        while (std::getline(in, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.empty()) continue;
            std::vector<std::string> cols;
            size_t s = 0, t;
            while ((t = line.find('\t', s)) != std::string::npos) { cols.push_back(line.substr(s, t - s)); s = t + 1; }
            cols.push_back(line.substr(s));
            if (cols.empty() || cols[0].empty()) continue;
            Str w = nfc(fromUtf8(cols[0]));
            for (size_t i = 1; i < cols.size(); ++i)
                if (!cols[i].empty()) { addAliasKey(w, cols[i]); ++added; }
        }
        build();
        return added;
    }

    // Load "word<TAB>freq" (or just "word") per line, UTF-8, one word per line.
    // Returns the number of words loaded. Lines are assumed NFC.
    size_t loadFile(const std::string& path) {
        std::ifstream in(path);
        if (!in) return 0;
        std::string line;
        size_t before = entries_.size();
        while (std::getline(in, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.empty()) continue;
            size_t tab = line.find('\t');
            std::string wtok = tab == std::string::npos ? line : line.substr(0, tab);
            uint32_t freq = 1;
            if (tab != std::string::npos) {
                std::string ftok = line.substr(tab + 1);
                freq = static_cast<uint32_t>(std::strtoul(ftok.c_str(), nullptr, 10));
                if (freq == 0) freq = 1;
            }
            addWord(nfc(fromUtf8(wtok)), freq);
        }
        build();
        return entries_.size() - before;
    }

    void build() {
        std::sort(entries_.begin(), entries_.end(),
                  [](const E& a, const E& b) { return a.key < b.key; });
        built_ = true;
    }

    size_t size() const { return entries_.size(); }
    bool   empty() const { return entries_.empty(); }

    // Words whose phonetic key has looseKey(input) as a prefix, shortest word first.
    std::vector<Str> lookup(const std::string& romanInput, int maxN = 8) const {
        std::vector<Str> res;
        const std::string qk = looseKey(romanInput);
        if (qk.empty() || entries_.empty()) return res;

        auto lo = std::lower_bound(entries_.begin(), entries_.end(), qk,
                                   [](const E& e, const std::string& k) { return e.key < k; });
        std::vector<const E*> hits;
        for (auto it = lo; it != entries_.end(); ++it) {
            if (it->key.size() < qk.size() || it->key.compare(0, qk.size(), qk) != 0) break;
            hits.push_back(&*it);
            if (hits.size() >= 20000) break;   // safety cap for 1-2 char prefixes
        }
        // Rank in two bands:
        //  1. EXACT key matches — words the input actually spells. Ranked by frequency,
        //     so the intended common word wins over rare homophones (kkhoma → ক্ষমা, not কমা).
        //  2. PREFIX completions — the user is still typing; SHORTEST WORD FIRST (as
        //     requested) so a few letters complete to the shortest word, then by frequency.
        const size_t qlen = qk.size();
        std::sort(hits.begin(), hits.end(), [qlen](const E* a, const E* b) {
            bool ax = a->key.size() == qlen, bx = b->key.size() == qlen;
            if (ax != bx) return ax;                              // exact band first
            if (ax) {                                            // both exact: frequency
                if (a->freq != b->freq) return a->freq > b->freq;
                return a->word.size() < b->word.size();
            }
            if (a->word.size() != b->word.size()) return a->word.size() < b->word.size();
            return a->freq > b->freq;                            // both prefix: shortest, then freq
        });
        std::unordered_set<std::u16string> seen;
        for (const E* e : hits) {
            if (seen.insert(e->word).second) res.push_back(e->word);
            if (static_cast<int>(res.size()) >= maxN) break;
        }
        return res;
    }

private:
    struct E { Str word; std::string key; uint32_t freq; };
    std::vector<E> entries_;
    bool built_ = false;
};

} // namespace banglaphon

#endif // BANGLA_PHONETIC_WORDDB_HPP
