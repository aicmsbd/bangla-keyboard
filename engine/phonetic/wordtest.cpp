// Bangla Keyboard — regression test for the offline "Bangla Dictionary" (worddb.hpp).
//
// Loads data/bangla-dictionary.txt and asserts that loose / hard / mixed-case
// romanizations recall the right word — the property the whole library exists for:
// `ShoWchoKKHE`, `sochokke`, `sochokkhe` must all find সচক্ষে.
//
//   c++ -O2 -std=c++17 wordtest.cpp -o wordtest && ./wordtest [data/bangla-dictionary.txt]

#include "worddb.hpp"
#include <cstdio>
#include <string>
#include <vector>

using namespace banglaphon;

static int pass = 0, fail = 0;

// expect `want` (UTF-8) to be the #1 result for `query`
static void top1(const WordDB& db, const char* query, const char* want) {
    auto r = db.lookup(query, 5);
    std::string got = r.empty() ? "" : toUtf8(r[0]);
    if (got == want) { ++pass; }
    else { ++fail; printf("FAIL top1  %-16s want=%s  got=%s\n", query, want, got.c_str()); }
}

// expect `want` to appear anywhere in the top `n`
static void within(const WordDB& db, const char* query, const char* want, int n) {
    auto r = db.lookup(query, n);
    bool ok = false;
    for (auto& w : r) if (toUtf8(w) == want) { ok = true; break; }
    if (ok) { ++pass; }
    else { ++fail; printf("FAIL within%-2d %-16s want=%s\n", n, query, want); }
}

int main(int argc, char** argv) {
    const char* path = argc > 1 ? argv[1] : "data/bangla-dictionary.txt";
    WordDB db;
    size_t n = db.loadFile(path);
    if (n == 0) { printf("ERROR: could not load %s (run from engine/phonetic/)\n", path); return 2; }
    size_t a = db.loadAliases("data/tools/hardwords_raw.tsv");   // AiCMS curated romanizations
    printf("loaded %zu words from %s (+%zu alias keys)\n", n, path, a);

    // the headline requirement: hard/loose/mixed-case all recall the same word, #1
    top1(db, "sochokke",    "সচক্ষে");
    top1(db, "sochokkhe",   "সচক্ষে");
    top1(db, "ShoWchoKKHE", "সচক্ষে");

    // common hard words, exact-match should lead
    top1(db, "opekkha",   "অপেক্ষা");
    top1(db, "opekha",    "অপেক্ষা");
    top1(db, "protigga",  "প্রতিজ্ঞা");
    top1(db, "biggan",    "বিজ্ঞান");
    top1(db, "gonotontro","গণতন্ত্র");

    // these should at least be present near the top
    within(db, "porikkha", "পরীক্ষা", 5);
    within(db, "borsa",    "বর্ষা",   6);
    within(db, "kkhoma",   "ক্ষমা",   5);
    within(db, "songbidhan", "সংবিধান", 6);

    // ya-phola ্য / ba-phola ্ব typed silent/glide (the natural spelling) must recall — the
    // phola-silent alternate key. These were unreachable before the fix.
    within(db, "jonno",    "জন্য",    6);
    within(db, "onno",     "অন্য",    6);
    within(db, "bissho",   "বিশ্ব",   6);
    within(db, "bishsho",  "বিশ্ব",   6);
    within(db, "bishshas", "বিশ্বাস", 6);
    within(db, "shagotom", "স্বাগতম", 6);
    within(db, "shash",    "শ্বাস",   6);

    printf("\n%d passed, %d failed\n", pass, fail);
    return fail ? 1 : 0;
}
