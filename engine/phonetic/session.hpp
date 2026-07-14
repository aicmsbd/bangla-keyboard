// Bangla Keyboard — phonetic session glue.
//
// One small stateful object a shell drives with key events; it returns exactly what a
// shell needs to render: the pre-edit (marked) text, any text to commit now, whether the
// key was consumed, and the (offline, instant) candidate list. Fully offline — no network.
//
// Pure C++17, header-only, no OS deps — unit-tested in test.cpp.

#ifndef BANGLA_PHONETIC_SESSION_HPP
#define BANGLA_PHONETIC_SESSION_HPP

#include "phonetic.hpp"
#include "suggest.hpp"
#include <vector>

namespace banglaphon {

struct KeyResult {
    bool consumed = false;                 // did phonetic mode handle this key?
    Str  preedit;                          // current marked/composing text
    Str  commit;                           // text to insert as final right now
    std::vector<Candidate> candidates;     // offline candidates for the candidate window
};

class PhoneticSession {
public:
    explicit PhoneticSession(Suggester& sug) : sug_(sug) {}

    // A printable ASCII key. Boundary chars (space, tab, most punctuation) commit the
    // word and pass through; '.' etc. are part of the scheme (see Phonetic::isBoundary).
    KeyResult key(char c) {
        KeyResult r;
        r.consumed = true;
        if (Phonetic::isBoundary(c)) {
            r.commit = eng_.currentBangla();
            r.commit.push_back(static_cast<char16_t>(static_cast<unsigned char>(c)));
            eng_.reset();
            return r;                       // preedit now empty, no candidates
        }
        eng_.typeChar(c);
        r.preedit    = eng_.currentBangla();
        r.candidates = sug_.offlineCandidates(eng_.romanBuffer());
        return r;
    }

    // Backspace. If nothing is composing, we do NOT consume it (host deletes normally).
    KeyResult backspace() {
        KeyResult r;
        if (eng_.empty()) { r.consumed = false; return r; }
        r.consumed   = true;
        eng_.backspace();
        r.preedit    = eng_.currentBangla();
        if (!eng_.empty()) r.candidates = sug_.offlineCandidates(eng_.romanBuffer());
        return r;
    }

    // User picked a candidate from the window: commit it and clear the buffer.
    KeyResult chooseCandidate(const Str& chosen) {
        KeyResult r;
        r.consumed = true;
        r.commit   = chosen;
        eng_.reset();
        return r;
    }

    // Commit whatever is composing (focus loss, mode switch, Ctrl/Cmd chord, Enter…).
    Str flush() {
        Str s = eng_.currentBangla();
        eng_.reset();
        return s;
    }

    bool composing() const { return !eng_.empty(); }
    const std::string& romanBuffer() const { return eng_.romanBuffer(); }

private:
    Phonetic   eng_;
    Suggester& sug_;
};

} // namespace banglaphon

#endif // BANGLA_PHONETIC_SESSION_HPP
