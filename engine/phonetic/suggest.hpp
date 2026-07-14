// Bangla Keyboard — phonetic candidate / suggestion layer.
//
// Given the Roman buffer the user is typing, produce a ranked candidate list:
//   1. the exact phonetic (Banglish) transliteration            (always first)
//   2. completions from the embedded hard/long-word dictionary  (offline)
//
// ZERO TELEMETRY BY CONSTRUCTION. This module never opens a socket and makes no network
// request at all — every suggestion comes from the bundled offline dictionary.
//
// Pure C++17, header-only, no OS headers — unit-tested headless in test.cpp.

#ifndef BANGLA_PHONETIC_SUGGEST_HPP
#define BANGLA_PHONETIC_SUGGEST_HPP

#include "phonetic.hpp"
#include "worddb.hpp"
#include <vector>
#include <string>
#include <algorithm>

namespace banglaphon {

// A lenient "fuzzy key" for the dictionary so approximate Banglish still matches the
// right word OFFLINE. Folds the spellings people mix up: case (T/t, S/s, N/n…), v↔b, z↔j,
// w→o, y→i, drops the 'h' of aspirate/sibilant digraphs (kh→k, sh→s, borsha↔borsa), and
// collapses doubled letters (opekkha↔opekha↔opeka). Deliberately over-merges for recall —
// the user still picks from the candidate list.
inline std::string fuzzyKey(const std::string& s) {
    std::string a;
    for (char c : s) {
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
        if      (c == 'v') c = 'b';
        else if (c == 'z') c = 'j';
        else if (c == 'w') c = 'o';
        else if (c == 'y') c = 'i';
        a.push_back(c);
    }
    auto vowel = [](char c) { return c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u'; };
    std::string o;
    for (char c : a) {
        if (c == 'h' && !o.empty() && !vowel(o.back()) && o.back() != 'h') continue; // aspirate h
        if (!o.empty() && o.back() == c) continue;                                    // double letter
        o.push_back(c);
    }
    return o;
}

// ---- candidate ranking ------------------------------------------------------

struct DictEntry { const char* banglish; const char16_t* bangla; };

struct Candidate {
    enum Source { Transliteration, Dictionary, Library };
    Str    text;
    Source source;
};

class Suggester {
public:
    Suggester(const DictEntry* dict = nullptr, size_t dictN = 0)
        : dict_(dict), dictN_(dictN) {}

    void setWordDB(const WordDB* db) { wordDB_ = db; }   // the big offline library (optional)
    void setMaxDict(int n)           { maxDict_ = n; }
    void setMaxLibrary(int n)        { maxLibrary_ = n; }

    // Offline candidate list (transliteration + dictionary). Never touches the net.
    std::vector<Candidate> offlineCandidates(const std::string& roman) const {
        std::vector<Candidate> out;
        if (roman.empty()) return out;
        const Str primary = transliterate(roman);
        push(out, {primary, Candidate::Transliteration});
        addDictionary(out, roman, primary);       // small curated alias list
        addLibrary(out, roman);                   // big offline "Bangla Dictionary"
        return out;
    }

    // The full candidate list is the offline list — there is no network source.
    std::vector<Candidate> candidates(const std::string& roman) const {
        return offlineCandidates(roman);
    }

private:
    const DictEntry* dict_;
    size_t           dictN_;
    const WordDB*    wordDB_     = nullptr;
    int              maxDict_    = 6;
    int              maxLibrary_ = 8;

    static bool startsWith(const std::string& s, const std::string& p) {
        return s.size() >= p.size() && std::equal(p.begin(), p.end(), s.begin());
    }
    static bool startsWith16(const Str& s, const Str& p) {
        return s.size() >= p.size() && std::equal(p.begin(), p.end(), s.begin());
    }
    // append if not already present; returns true if it was added
    static bool push(std::vector<Candidate>& v, Candidate c) {
        if (c.text.empty()) return false;
        for (const auto& e : v) if (e.text == c.text) return false;
        v.push_back(std::move(c));
        return true;
    }

    void addDictionary(std::vector<Candidate>& out, const std::string& roman, const Str& primary) const {
        if (!dict_ || dictN_ == 0) return;
        const std::string fk = fuzzyKey(roman);
        struct Hit { Str bn; int tier; };            // tier 0 exact > 1 Bangla-prefix > 2 fuzzy
        std::vector<Hit> hits;
        for (size_t i = 0; i < dictN_; ++i) {
            const std::string bl = dict_[i].banglish;
            const Str bn = u16(dict_[i].bangla);
            int tier = -1;
            if (startsWith(bl, roman))                        tier = 0;   // exact roman prefix
            else if (startsWith16(bn, primary))               tier = 1;   // Bangla prefix
            else if (fk.size() >= 2 && startsWith(fuzzyKey(bl), fk)) tier = 2;   // fuzzy
            if (tier >= 0) hits.push_back({bn, tier});
        }
        std::sort(hits.begin(), hits.end(), [](const Hit& a, const Hit& b) {
            return a.tier != b.tier ? a.tier < b.tier : a.bn.size() < b.bn.size();
        });
        int added = 0;
        for (const Hit& h : hits) {
            if (added >= maxDict_) break;
            if (push(out, {h.bn, Candidate::Dictionary})) ++added;
        }
    }

    // Completions from the big offline library (worddb.hpp), shortest word first.
    void addLibrary(std::vector<Candidate>& out, const std::string& roman) const {
        if (!wordDB_) return;
        for (const Str& w : wordDB_->lookup(roman, maxLibrary_))
            push(out, {w, Candidate::Library});
    }

    static Str u16(const char16_t* s) { return s ? Str(s) : Str(); }
};

} // namespace banglaphon

#endif // BANGLA_PHONETIC_SUGGEST_HPP
