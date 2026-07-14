// Native candidate engine for the system-wide popup — a Swift port of the shipping JS/C++
// suggester (engine/phonetic/worddb.hpp, macos/app/ui/index.html), so the suggestions offered
// while typing into ANY app are identical to the ones in the app's own editor.
//
// Words + their AiCMS romanization aliases are loaded from the app bundle (bangla-dictionary.txt,
// hardwords_raw.tsv) at launch and indexed by a loose phonetic key. Every word is also indexed
// under a ya-phola/ba-phola-silent key, so জন্য/বিশ্ব are recalled when typed the natural way.

import Foundation

final class Suggester {
    static let shared = Suggester()

    private var words: [String] = []
    private var index: [(key: String, wi: Int)] = []   // sorted by key, for binary search
    private(set) var ready = false

    // Bengali codepoint → roman. Mirror of B2R_C / B2R_V / B2R_K in the JS/C++ engine.
    private static let C: [UInt32: String] = [
        0x0995:"k",0x0996:"kh",0x0997:"g",0x0998:"gh",0x0999:"ng",0x099A:"c",0x099B:"ch",0x099C:"j",0x099D:"jh",0x099E:"n",
        0x099F:"T",0x09A0:"Th",0x09A1:"D",0x09A2:"Dh",0x09A3:"n",0x09A4:"t",0x09A5:"th",0x09A6:"d",0x09A7:"dh",0x09A8:"n",
        0x09AA:"p",0x09AB:"ph",0x09AC:"b",0x09AD:"bh",0x09AE:"m",0x09AF:"j",0x09B0:"r",0x09B2:"l",0x09B6:"sh",0x09B7:"sh",
        0x09B8:"s",0x09B9:"h",0x09DC:"r",0x09DD:"rh",0x09DF:"y",0x09CE:"t"]
    private static let V: [UInt32: String] = [
        0x0985:"o",0x0986:"a",0x0987:"i",0x0988:"i",0x0989:"u",0x098A:"u",0x098B:"rri",0x098F:"e",0x0990:"oi",0x0993:"o",0x0994:"ou"]
    private static let K: [UInt32: String] = [
        0x09BE:"a",0x09BF:"i",0x09C0:"i",0x09C1:"u",0x09C2:"u",0x09C3:"rri",0x09C7:"e",0x09C8:"oi",0x09CB:"o",0x09CC:"ou",0x09D7:"ou"]

    // Bengali word → roman. pholaSilent drops ya-phola (্য) / ba-phola (্ব) so জন্য→"jono", বিশ্ব→"bisho".
    private static func toRoman(_ w: [UInt32], pholaSilent: Bool) -> String {
        var out = "", prev = false, i = 0
        let n = w.count
        let HAS: UInt32 = 0x09CD
        while i < n {
            let c = w[i]
            if pholaSilent && c == HAS && i + 1 < n && (w[i+1] == 0x09AF || w[i+1] == 0x09AC) { i += 2; continue }
            if i + 2 < n && c == 0x0995 && w[i+1] == HAS && w[i+2] == 0x09B7 { if prev { out += "o" }; out += "kkh"; prev = true; i += 3; continue }
            if i + 2 < n && c == 0x099C && w[i+1] == HAS && w[i+2] == 0x099E { if prev { out += "o" }; out += "gg";  prev = true; i += 3; continue }
            if let r = C[c] { if prev { out += "o" }; out += r; prev = true;  i += 1; continue }
            if c == HAS     { prev = false; i += 1; continue }
            if let r = K[c] { out += r; prev = false; i += 1; continue }
            if let r = V[c] { if prev { out += "o" }; out += r; prev = false; i += 1; continue }
            if c == 0x0982  { out += "ng"; prev = false; i += 1; continue }
            i += 1
        }
        return out
    }

    // Collapse a romanization to a fuzzy key: v→b, z→j, drop w, y→i, drop inherent o, silent h,
    // squash doubles. Mirror of looseKey() in the JS/C++ engine.
    private static func looseKey(_ s: String) -> String {
        var a = ""
        for sc in s.unicodeScalars {
            var ch = sc
            if ch.value >= 65 && ch.value <= 90 { ch = Unicode.Scalar(ch.value + 32)! }   // lowercase
            switch ch {
            case "v": a += "b"
            case "z": a += "j"
            case "w": continue
            case "y": a += "i"
            default:  a.unicodeScalars.append(ch)
            }
        }
        var o = [Character]()
        func vow(_ c: Character) -> Bool { c == "a" || c == "e" || c == "i" || c == "u" }
        for ch in a {
            if ch < "a" || ch > "z" { continue }
            if ch == "o" { continue }
            if ch == "h", let last = o.last, !vow(last), last != "h" { continue }
            if let last = o.last, last == ch { continue }
            o.append(ch)
        }
        return String(o)
    }

    // Load the dictionary + alias resources from the bundle and build the index off the main thread.
    func loadFromBundle() {
        guard let dictURL = Bundle.main.url(forResource: "bangla-dictionary", withExtension: "txt"),
              let dict = try? String(contentsOf: dictURL, encoding: .utf8) else {
            bkLog("suggester: bangla-dictionary.txt not found in bundle"); return
        }
        let alias = Bundle.main.url(forResource: "hardwords_raw", withExtension: "tsv")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        DispatchQueue.global(qos: .userInitiated).async {
            let (w, i) = Suggester.buildIndex(dict, alias)
            DispatchQueue.main.async {
                self.words = w; self.index = i; self.ready = true
                bkLog("suggester ready: \(w.count) words, \(i.count) keys")
            }
        }
    }

    // Load synchronously from strings — used by the standalone parity test.
    func loadSync(dictText: String, aliasText: String) {
        let (w, i) = Suggester.buildIndex(dictText, aliasText)
        words = w; index = i; ready = true
    }

    private static func buildIndex(_ dictText: String, _ aliasText: String) -> ([String], [(key: String, wi: Int)]) {
        var ws = [String](); ws.reserveCapacity(40000)
        var pos = [String: Int]()
        for line in dictText.split(separator: "\n", omittingEmptySubsequences: true) {
            let w = String(line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)[0])
                .trimmingCharacters(in: .whitespaces)
            if !w.isEmpty && pos[w] == nil { pos[w] = ws.count; ws.append(w) }
        }
        var idx = [(String, Int)](); idx.reserveCapacity(ws.count * 2)
        for (i, w) in ws.enumerated() {
            let sc = w.unicodeScalars.map { $0.value }
            let k1 = Suggester.looseKey(Suggester.toRoman(sc, pholaSilent: false)); if !k1.isEmpty { idx.append((k1, i)) }
            let k2 = Suggester.looseKey(Suggester.toRoman(sc, pholaSilent: true));  if !k2.isEmpty && k2 != k1 { idx.append((k2, i)) }
        }
        for line in aliasText.split(separator: "\n", omittingEmptySubsequences: true) {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let first = cols.first, let wi = pos[String(first)] else { continue }
            for j in 1..<cols.count {
                let k = Suggester.looseKey(String(cols[j])); if !k.isEmpty { idx.append((k, wi)) }
            }
        }
        idx.sort { $0.0 < $1.0 }
        return (ws, idx.map { (key: $0.0, wi: $0.1) })
    }

    // Words whose phonetic key has looseKey(input) as a prefix. EXACT-key matches first (by
    // frequency = dictionary order), then completions shortest-word-first. Mirror of suggest().
    func suggest(_ input: String, _ maxN: Int = 6) -> [String] {
        if !ready { return [] }
        let qk = Suggester.looseKey(input)
        if qk.isEmpty { return [] }
        var lo = 0, hi = index.count
        while lo < hi { let m = (lo + hi) >> 1; if index[m].key < qk { lo = m + 1 } else { hi = m } }
        var exact = [Int](), pre = [Int]()
        let qlen = qk.count
        var i = lo
        while i < index.count {
            let k = index[i].key
            if !k.hasPrefix(qk) { break }
            if k.count == qlen { exact.append(index[i].wi) } else { pre.append(index[i].wi) }
            i += 1
        }
        exact.sort { $0 < $1 }
        // Shortest word first (UTF-16 length, matching the JS/C++ reference), then by frequency.
        pre.sort { words[$0].utf16.count != words[$1].utf16.count
                     ? words[$0].utf16.count < words[$1].utf16.count : $0 < $1 }
        var out = [String](), seen = Set<String>()
        for arr in [exact, pre] {
            for wi in arr {
                let w = words[wi]
                if seen.insert(w).inserted { out.append(w); if out.count >= maxN { return out } }
            }
        }
        return out
    }
}
