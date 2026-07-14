// বাঙলা কিবোর্ড — macOS Input Method (InputMethodKit).
//
// A proper macOS input source: it appears in System Settings → Keyboard → Input Sources,
// and you pick it from the input (🌐) menu like any keyboard. Type Banglish and it shows
// the Bangla as underlined marked text (pre-edit); a word boundary commits it. Uses a
// Swift port of the shared engine (engine/phonetic/phonetic.hpp), verified by test.cpp.
//
// Install: build.sh copies the app to ~/Library/Input Methods/ and registers it. Then add
// it in System Settings → Keyboard → Input Sources → + (search "বাঙলা" / Bengali).

import Cocoa
import InputMethodKit

// ============================ transliteration engine ============================
enum Rule { case vowel(String, String); case cons(String); case sign(String); case hasanta; case yphola; case wphola }

let MAP: [String: Rule] = {
    var m = [String: Rule]()
    func V(_ r: String, _ i: String, _ k: String) { m[r] = .vowel(i, k) }
    func C(_ r: String, _ c: String) { m[r] = .cons(c) }
    func S(_ r: String, _ s: String) { m[r] = .sign(s) }
    V("rri","ঋ","ৃ"); V("ee","ঈ","ী"); V("oo","উ","ু"); V("OI","ঐ","ৈ"); V("OU","ঔ","ৌ")
    V("a","আ","া"); V("A","আ","া"); V("i","ই","ি"); V("I","ঈ","ী"); V("u","উ","ু"); V("U","ঊ","ূ")
    V("e","এ","ে"); V("o","অ",""); V("O","ও","ো")
    C("kh","খ"); C("gh","ঘ"); C("Ng","ঙ"); C("ch","ছ"); C("jh","ঝ"); C("NG","ঞ"); C("Th","ঠ"); C("Dh","ঢ")
    C("th","থ"); C("dh","ধ"); C("ph","ফ"); C("bh","ভ"); C("sh","শ"); C("Sh","ষ"); C("Rh","ঢ়")
    C("kkh","ক্ষ"); C("kx","ক্ষ"); C("x","ক্স"); C("gg","জ্ঞ")
    C("k","ক"); C("g","গ"); C("c","চ"); C("j","জ"); C("T","ট"); C("D","ড"); C("N","ণ"); C("t","ত"); C("d","দ"); C("n","ন")
    C("p","প"); C("f","ফ"); C("b","ব"); C("v","ভ"); C("m","ম"); C("z","য"); C("rr","র"); C("r","র"); C("l","ল"); C("s","স"); C("S","শ")
    C("h","হ"); C("R","ড়")
    m["y"] = .yphola; m["Y"] = .cons("য়"); m["w"] = .wphola
    S("ng","ং"); S("^","ঁ"); S("H","ঃ"); S("t``","ৎ"); S(".","।")
    m["``"] = .hasanta; m[",,"] = .hasanta
    for (i, d) in Array("০১২৩৪৫৬৭৮৯").enumerated() { S(String(i), String(d)) }
    return m
}()

func nfc(_ s: String) -> String {
    var out = [Unicode.Scalar]()
    for sc in s.unicodeScalars {
        if let p = out.last {
            if p.value == 0x09C7 && sc.value == 0x09BE { out[out.count-1] = Unicode.Scalar(0x09CB)!; continue }
            if p.value == 0x09C7 && sc.value == 0x09D7 { out[out.count-1] = Unicode.Scalar(0x09CC)!; continue }
        }
        out.append(sc)
    }
    var r = ""; r.unicodeScalars.append(contentsOf: out); return r
}

func transliterate(_ s: String) -> String {
    let a = Array(s)
    var out = "", last = 0, i = 0
    let n = a.count
    while i < n {
        var rule: Rule? = nil, klen = 0
        var L = min(3, n - i)
        while L >= 1 { let key = String(a[i..<i+L]); if let u = MAP[key] { rule = u; klen = L; break }; L -= 1 }
        guard let u = rule else { out.append(a[i]); last = 3; i += 1; continue }
        i += klen
        switch u {
        case .cons(let c):           if last == 1 { out += "্" }; out += c; last = 1
        case .vowel(let iv, let kv): out += (last == 1 ? kv : iv); last = 2
        case .yphola:                out += (last == 1 ? "্য" : "য়"); last = 1
        case .wphola:                out += (last == 1 ? "্ব" : "ওয়"); last = 1
        case .sign(let sg):          out += sg; last = 3
        case .hasanta:               out += "্"; last = 1
        }
    }
    return nfc(out)
}

// ============================ IMK input controller ============================
@objc(BanglaController)
class BanglaController: IMKInputController {
    private var roman = ""

    private func isScheme(_ c: Character) -> Bool {
        // In-word scheme chars, matching the C++ reference engine's word-boundary contract:
        // ASCII letters/digits, '^' (chandrabindu), '.' (danda ।) and '`' (hasanta / khanda-ta).
        return (c.isLetter && c.isASCII) || (c.isNumber && c.isASCII) || c == "^" || c == "." || c == "`"
    }
    private func here() -> NSRange { NSRange(location: NSNotFound, length: 0) }

    private func updateMarked(_ client: IMKTextInput) {
        let bn = transliterate(roman)
        let attr = NSAttributedString(string: bn, attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        client.setMarkedText(attr, selectionRange: NSRange(location: (bn as NSString).length, length: 0), replacementRange: here())
    }
    private func commit(_ client: IMKTextInput) {
        if !roman.isEmpty { client.insertText(transliterate(roman), replacementRange: here()); roman = "" }
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        let flags = event.modifierFlags
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            commit(client); return false                       // let shortcuts run
        }
        let kc = event.keyCode
        if kc == 51 {                                          // Backspace
            if !roman.isEmpty { roman.removeLast(); updateMarked(client); return true }
            return false
        }
        if kc == 36 || kc == 76 {                              // Return / Enter
            commit(client); return false
        }
        guard let chars = event.characters, chars.count == 1, let c = chars.first else {
            commit(client); return false
        }
        if isScheme(c) { roman.append(c); updateMarked(client); return true }   // pre-edit grows
        // boundary (space / punctuation): commit the word, then insert the boundary char
        commit(client)
        client.insertText(String(c), replacementRange: here())
        return true
    }

    override func commitComposition(_ sender: Any!) {
        if let client = sender as? IMKTextInput { commit(client) }
    }
    override func deactivateServer(_ sender: Any!) {
        if let client = sender as? IMKTextInput { commit(client) }
    }
}

// ============================ IMK server ============================
let bundleId = Bundle.main.bundleIdentifier ?? "com.bangla.inputmethod"
let connName = (Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String) ?? "BanglaKeyboard_Connection"
let server = IMKServer(name: connName, bundleIdentifier: bundleId)
_ = server   // keep alive
NSApplication.shared.run()
