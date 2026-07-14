// Bangla Keyboard — headless regression test for the phonetic engine.
//
// Follows the repo's own testing rule (SPEC §9): prove the engine as a pure module
// with a console test BEFORE wiring any OS shell. Feeds each Banglish input through
// transliterate() and compares NFC-normalized output against the adversarially
// verified corpus in corpus.hpp.
//
//   c++ -std=c++17 test.cpp -o phontest && ./phontest
//
// Exit code is non-zero if any case fails (usable in CI).

#include "phonetic.hpp"
#include "corpus.hpp"
#include <cstdio>

using namespace banglaphon;

int main() {
    int pass = 0, fail = 0;
    for (size_t i = 0; i < kCorpusN; ++i) {
        const Str got = transliterate(kCorpus[i].input);          // already NFC
        const Str exp = nfc(fromUtf8(kCorpus[i].expected));
        if (got == exp) {
            ++pass;
        } else {
            ++fail;
            printf("FAIL  %-18s got=%-24s exp=%-24s %s\n",
                   kCorpus[i].input,
                   toUtf8(got).c_str(),
                   toUtf8(exp).c_str(),
                   kCorpus[i].note ? kCorpus[i].note : "");
        }
    }
    printf("\n%d passed, %d failed, %zu total\n", pass, fail, kCorpusN);
    return fail ? 1 : 0;
}
