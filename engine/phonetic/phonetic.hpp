// Bangla Keyboard — Banglish (phonetic) transliteration engine.
//
// The single shared input engine for every platform: type Bangla the way most
// Bangladeshis already type it on phones — in Roman letters ("Banglish"), phonetic
// style — "ami banglay gan gai" -> "আমি বাংলায় গান গাই".
//
// Design goals (see ../../PHONETIC.md for the full contract):
//   * Pure C++17, header-only, NO OS headers — so it compiles into every shell
//     (macOS app, Windows tray, Linux IBus) unchanged and is unit-testable
//     headless (engine/phonetic/test.cpp).
//   * std::u16string throughout: every character this engine emits is in the BMP,
//     so one UTF-16 code unit == one Unicode scalar (same trick engine.h relies on).
//   * The transliterator is a PURE FUNCTION of the whole roman buffer — the shell
//     keeps the roman keystrokes of the current word as pre-edit and re-derives the
//     Bangla on every keystroke. That makes Backspace trivially correct (pop one
//     ROMAN char, re-transliterate) and makes candidate generation easy.
//
// The scheme is the de-facto "phonetic" convention. The authoritative behaviour
// is the regression corpus in engine/phonetic/test.cpp — if a rule below and the
// corpus ever disagree, the corpus wins and the map here is the bug.

#ifndef BANGLA_PHONETIC_HPP
#define BANGLA_PHONETIC_HPP

#include <string>
#include <unordered_map>
#include <cstdint>

namespace banglaphon {

using Str = std::u16string;

// ---- classification of one Roman token -------------------------------------
enum class Kind {
    Vowel,    // has an INDEPENDENT form (word-initial / after a vowel) and a KAR form
    Cons,     // a consonant (or a fixed consonant conjunct) — "open", takes kar / conjuncts
    Sign,     // attaches to the current syllable, does not open a new consonant
              // (anusvara ং, visarga ঃ, chandrabindu ঁ, digits, danda…)
    Hasanta,  // explicit hasanta ্ (force a visible halant / manual conjunct)
    YPhola,   // 'y' — ya-phola ্য after a consonant, else য় (context sensitive)
    WPhola,   // 'w' — ba-phola ্ব after a consonant, else ওয় (context sensitive)
};

struct Unit {
    Kind kind;
    Str  a;   // Vowel: independent form. Cons/Sign/Hasanta: the output. (empty for y/w)
    Str  b;   // Vowel: the kar (dependent) form — empty for 'o' (inherent vowel).
};

// The rule table. Looked up by GREEDY LONGEST MATCH (keys up to 3 chars), and it is
// CASE-SENSITIVE (standard phonetic convention: t=ত vs T=ট, s=স vs S=শ vs Sh=ষ, o=inherent vs O=ও).
inline const std::unordered_map<std::string, Unit>& table() {
    static const std::unordered_map<std::string, Unit> t = [] {
        std::unordered_map<std::string, Unit> m;
        auto V = [&](const char* r, const char16_t* i, const char16_t* k) { m[r] = {Kind::Vowel, i, k}; };
        auto C = [&](const char* r, const char16_t* c)                    { m[r] = {Kind::Cons,  c, u""}; };
        auto S = [&](const char* r, const char16_t* s)                    { m[r] = {Kind::Sign,  s, u""}; };

        // --- vowels (independent, kar) --- longest keys win at match time ---
        V("rri", u"ঋ", u"ৃ");
        V("ee",  u"ঈ", u"ী");   V("oo", u"উ", u"ু");
        V("OI",  u"ঐ", u"ৈ");   V("OU", u"ঔ", u"ৌ");
        V("a",   u"আ", u"া");   V("A",  u"আ", u"া");
        V("i",   u"ই", u"ি");   V("I",  u"ঈ", u"ী");
        V("u",   u"উ", u"ু");   V("U",  u"ঊ", u"ূ");
        V("e",   u"এ", u"ে");
        V("o",   u"অ", u"");    // 'o' = INHERENT vowel: no kar after a consonant
        V("O",   u"ও", u"ো");

        // --- consonants (2-char romanizations first) ---
        C("kh", u"খ"); C("gh", u"ঘ"); C("Ng", u"ঙ"); C("ch", u"ছ"); C("jh", u"ঝ");
        C("NG", u"ঞ"); C("Th", u"ঠ"); C("Dh", u"ঢ"); C("th", u"থ"); C("dh", u"ধ");
        C("ph", u"ফ"); C("bh", u"ভ"); C("sh", u"শ"); C("Sh", u"ষ"); C("Rh", u"ঢ়");
        // convenience conjunct shortcuts (common phonetic spellings)
        C("kkh", u"ক্ষ"); C("kx", u"ক্ষ"); C("x", u"ক্স"); C("gg", u"জ্ঞ");
        // single consonants
        C("k", u"ক"); C("g", u"গ"); C("c", u"চ"); C("j", u"জ"); C("T", u"ট");
        C("D", u"ড"); C("N", u"ণ"); C("t", u"ত"); C("d", u"দ"); C("n", u"ন");
        C("p", u"প"); C("f", u"ফ"); C("b", u"ব"); C("v", u"ভ"); C("m", u"ম");
        C("z", u"য"); C("rr", u"র"); C("r", u"র"); C("l", u"ল"); C("s", u"স"); C("S", u"শ");
        C("h", u"হ"); C("R", u"ড়");

        // --- context-sensitive semivowels (handled in code, entries are markers) ---
        m["y"] = {Kind::YPhola, u"", u""};
        m["Y"] = {Kind::Cons,  u"য়", u""};   // Y is always the standalone ya-with-nukta
        m["w"] = {Kind::WPhola, u"", u""};

        // --- signs (attach to the current syllable) ---
        S("ng", u"ং");   // anusvara  (Ng = ঙ, ng = ং — case matters)
        S("^",  u"ঁ");   // chandrabindu
        S("H",  u"ঃ");   // visarga
        S("t``", u"ৎ");  // khanda-ta (standalone; never takes a vowel) — standard: t + ``
        S(".",  u"।");   // danda (Bengali full stop)
        m["``"] = {Kind::Hasanta, u"্", u""};   // explicit hasanta (double backtick)
        m[",,"] = {Kind::Hasanta, u"্", u""};   // …and a keyboard-friendly alias

        // --- Bangla digits ---
        S("0", u"০"); S("1", u"১"); S("2", u"২"); S("3", u"৩"); S("4", u"৪");
        S("5", u"৫"); S("6", u"৬"); S("7", u"৭"); S("8", u"৮"); S("9", u"৯");

        return m;
    }();
    return t;
}

// Canonicalize to Bengali NFC: compose e-kar+aa -> o-kar and e-kar+au-length -> au-kar.
// NOTE: ড়/ঢ়/য় (U+09DC/09DD/09DF) are Unicode composition EXCLUSIONS, so NFC keeps them
// DECOMPOSED as base+nukta (U+09A1/09A2/09AF + U+09BC). The literals above are already
// decomposed, so we must NOT recompose them — that would produce non-NFC output that
// disagrees with the Swift ports (macOS) and the offline dictionary (both decomposed).
inline Str nfc(const Str& s) {
    Str o;
    o.reserve(s.size());
    for (char16_t c : s) {
        if (!o.empty()) {
            char16_t p = o.back();
            if (p == 0x09C7 && c == 0x09BE) { o.back() = 0x09CB; continue; } // ে + া -> ো
            if (p == 0x09C7 && c == 0x09D7) { o.back() = 0x09CC; continue; } // ে + ৗ -> ৌ
        }
        o.push_back(c);
    }
    return o;
}

// State of the "last thing we emitted", used to decide kar-vs-independent and
// whether the next consonant should conjunct (insert hasanta) onto the previous one.
enum class Prev { None, Cons, Vowel, Other };

// Transliterate a whole Roman buffer to Bangla (phonetic (Banglish)). Pure; no state kept.
inline Str transliterate(const std::string& s) {
    const auto& t = table();
    Str out;
    Prev last = Prev::None;
    char16_t lastCons = 0;  // most recently emitted BARE consonant glyph (0 = none/not applicable)
    const size_t n = s.size();
    const size_t MAXK = 3;

    size_t i = 0;
    while (i < n) {
        // greedy longest match, up to MAXK chars
        const Unit* u = nullptr;
        std::string key;
        for (size_t L = (n - i < MAXK ? n - i : MAXK); L >= 1; --L) {
            key.assign(s, i, L);
            auto it = t.find(key);
            if (it != t.end()) { u = &it->second; break; }
            if (L == 1) break;
        }
        if (!u) {
            // Not part of the scheme (punctuation, space handled by caller, unknown):
            // pass the byte through as-is and treat as a hard boundary.
            out.push_back(static_cast<char16_t>(static_cast<unsigned char>(s[i])));
            last = Prev::Other;
            i += 1;
            continue;
        }
        i += key.size();

        switch (u->kind) {
            case Kind::Cons: {
                // Reph before "ল" does not occur in Bangla ("র্ল" is not a real cluster) — a bare
                // র directly followed by ল stays two separate syllables, e.g. "korlam" -> করলাম,
                // not কর্লাম. Every other adjacent bare-consonant pair still auto-conjuncts.
                bool sameSyllable = (last == Prev::Cons) && !(lastCons == u'র' && u->a == u"ল");
                if (sameSyllable) out += u"্";   // auto-conjunct
                out += u->a;
                last = Prev::Cons;
                lastCons = (u->a.size() == 1) ? u->a[0] : char16_t(0);
                break;
            }

            case Kind::Vowel:
                if (last == Prev::Cons) out += u->b;    // kar (empty for inherent 'o')
                else                    out += u->a;    // independent
                last = Prev::Vowel;
                lastCons = 0;
                break;

            case Kind::YPhola:
                if (last == Prev::Cons) out += u"্য";   // ya-phola on the consonant
                else                    out += u"য়";    // standalone ya (with nukta)
                last = Prev::Cons;
                lastCons = 0;
                break;

            case Kind::WPhola:
                if (last == Prev::Cons) out += u"্ব";   // ba-phola (বিশ্ব = "bishwo")
                else                    out += u"ওয়";  // standalone
                last = Prev::Cons;
                lastCons = 0;
                break;

            case Kind::Sign:
                out += u->a;
                last = Prev::Other;   // does not open a consonant for conjuncting
                lastCons = 0;
                break;

            case Kind::Hasanta:
                out += u"্";
                last = Prev::Cons;    // keep "open" so a following consonant joins
                lastCons = 0;         // explicit hasanta always forces the next join
                break;
        }
    }
    return nfc(out);
}

// -----------------------------------------------------------------------------
// Incremental driver for a shell's pre-edit. Buffers the ROMAN keystrokes of the
// current word; the pre-edit shown is always transliterate(buffer). On a word
// boundary the caller commits currentBangla() and calls reset().
// -----------------------------------------------------------------------------
class Phonetic {
public:
    // Append one typed ASCII character to the current word. Returns the new pre-edit.
    Str typeChar(char c) { roman_.push_back(c); return transliterate(roman_); }

    // Remove one ROMAN char (Backspace). Returns the new pre-edit (empty if none).
    Str backspace() {
        if (!roman_.empty()) roman_.pop_back();
        return transliterate(roman_);
    }

    Str   currentBangla() const { return transliterate(roman_); }
    const std::string& romanBuffer() const { return roman_; }
    bool  empty() const { return roman_.empty(); }
    void  reset() { roman_.clear(); }

    // True for characters that end a word (space, tab, newline, ASCII punctuation).
    // The caller flushes currentBangla() before inserting the boundary character.
    static bool isBoundary(char c) {
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') return true;
        // ASCII punctuation that is not part of the phonetic scheme.
        // NOTE: '.' is intentionally NOT a boundary — it maps to danda ("।") inside
        // transliterate(); '^', 'H', ',,' and '``' are scheme characters too.
        switch (c) {
            case ',': case '?': case '!': case ';':
            case '(': case ')': case '[': case ']': case '{': case '}':
            case '"': case '/': case '\\': case '|': case '-':
                return true;
            default: return false;
        }
    }

private:
    std::string roman_;   // the raw Roman keystrokes of the word in progress
};

// -----------------------------------------------------------------------------
// UTF-8 <-> UTF-16 helpers (BMP-only, which is all Bangla needs). Handy for the
// network/JSON layer (suggest.hpp) and the test harness.
// -----------------------------------------------------------------------------
inline std::string toUtf8(const Str& s) {
    std::string o;
    for (char16_t c : s) {
        unsigned cp = c;
        if (cp < 0x80) o += static_cast<char>(cp);
        else if (cp < 0x800) { o += static_cast<char>(0xC0 | (cp >> 6)); o += static_cast<char>(0x80 | (cp & 0x3F)); }
        else { o += static_cast<char>(0xE0 | (cp >> 12)); o += static_cast<char>(0x80 | ((cp >> 6) & 0x3F)); o += static_cast<char>(0x80 | (cp & 0x3F)); }
    }
    return o;
}

inline Str fromUtf8(const std::string& s) {
    Str o;
    size_t i = 0, n = s.size();
    while (i < n) {
        unsigned char b = s[i];
        unsigned cp; int len;
        if (b < 0x80)        { cp = b; len = 1; }
        else if ((b >> 5) == 0x6) { cp = b & 0x1F; len = 2; }
        else if ((b >> 4) == 0xE) { cp = b & 0x0F; len = 3; }
        else if ((b >> 3) == 0x1E){ cp = b & 0x07; len = 4; }
        else { i += 1; continue; }
        if (i + len > n) break;
        for (int k = 1; k < len; ++k) cp = (cp << 6) | (s[i + k] & 0x3F);
        i += len;
        if (cp <= 0xFFFF) o.push_back(static_cast<char16_t>(cp));
        // (astral chars can't occur in Bangla text; dropped intentionally)
    }
    return o;
}

} // namespace banglaphon

#endif // BANGLA_PHONETIC_HPP
