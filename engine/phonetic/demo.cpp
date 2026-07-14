// Bangla Keyboard — phonetic mode standalone demo (NOT an IME; the shells are the IMEs).
//
// Proves the Banglish engine + suggester in a runnable, portable console app. Same
// engine the shells embed, so behaviour matches exactly. Fully offline.
//
//   c++ -std=c++17 demo.cpp -o bangla-phon
//
//   ./bangla-phon                          interactive: type Banglish, see Bangla + candidates
//   ./bangla-phon --line "ami banglay gan gai"   batch: transliterate one line
//   echo "bishwobiddaloy" | ./bangla-phon --suggest   one word -> candidate list
#include "phonetic.hpp"
#include "suggest.hpp"
#include "dictionary.hpp"
#include "worddb.hpp"

#include <cstdio>
#include <cstring>
#include <string>
#include <iostream>

using namespace banglaphon;

// Transliterate a whole line the way a shell would: word by word, boundaries verbatim.
static std::string translitLine(const std::string& line) {
    Phonetic p;
    std::string out;
    for (char c : line) {
        if (Phonetic::isBoundary(c)) {
            out += toUtf8(p.currentBangla());
            p.reset();
            out += c;
        } else {
            p.typeChar(c);
        }
    }
    out += toUtf8(p.currentBangla());
    return out;
}

static const char* srcName(Candidate::Source s) {
    switch (s) {
        case Candidate::Transliteration: return "type";
        case Candidate::Dictionary:      return "alias";
        case Candidate::Library:         return "lib";
        default:                         return "type";
    }
}
static void printCandidates(Suggester& sug, const std::string& roman) {
    printf("  %-20s -> %s\n", roman.c_str(), toUtf8(transliterate(roman)).c_str());
    int i = 1;
    for (const auto& c : sug.candidates(roman))
        printf("    %d. [%s] %s\n", i++, srcName(c.source), toUtf8(c.text).c_str());
}

int main(int argc, char** argv) {
    bool suggest = false;
    const char* line = nullptr;
    const char* dictPath = "data/bangla-dictionary.txt";   // the big offline library
    for (int i = 1; i < argc; ++i) {
        if      (!std::strcmp(argv[i], "--suggest")) suggest = true;
        else if (!std::strcmp(argv[i], "--line") && i + 1 < argc) line = argv[++i];
        else if (!std::strcmp(argv[i], "--dict") && i + 1 < argc) dictPath = argv[++i];
    }

    WordDB db;
    size_t nwords = db.loadFile(dictPath);
    if (nwords) fprintf(stderr, "loaded %zu-word Bangla Dictionary from %s\n", nwords, dictPath);

    Suggester sug(kDictionary, kDictionaryN);
    sug.setWordDB(&db);

    if (line) { printf("%s\n", translitLine(line).c_str()); }
    else if (suggest) {
        std::string w;
        while (std::getline(std::cin, w)) if (!w.empty()) printCandidates(sug, w);
    } else {
        fprintf(stderr, "Type Banglish, one word/line. Ctrl-D to quit.\n");
        std::string w;
        while (std::getline(std::cin, w)) {
            if (w.empty()) continue;
            if (suggest) printCandidates(sug, w);
            else printf("  %s\n", translitLine(w).c_str());
        }
    }
    return 0;
}
