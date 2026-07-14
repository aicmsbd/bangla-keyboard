// বাঙলা কিবোর্ড (Bangla Keyboard) — native macOS app.
//
// An always-on-top toolbar window (WKWebView showing ui/index.html) + a system-wide
// CGEventTap that types Bangla into ANY app while Bangla mode is on — the macOS twin of
// the Windows app. Ctrl+B = Bangla, Ctrl+E = English. The transliteration is a Swift port
// of engine/phonetic/phonetic.hpp (verified headless by engine/phonetic/test.cpp).
//
// System-wide typing needs Accessibility permission (System Settings → Privacy &
// Security → Accessibility). Without it, the toolbar window still works on its own.

import Cocoa
import WebKit
import ApplicationServices
import Carbon    // IsSecureEventInputEnabled()

// Append a diagnostic line to ~/Library/Logs/BanglaKeyboard.log so the Accessibility /
// hook / mode state is observable from outside the app (tail -f it to confirm the fix).
func bkLog(_ msg: String) {
    let path = ("~/Library/Logs/BanglaKeyboard.log" as NSString).expandingTildeInPath
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "\(ts) \(msg)\n"
    guard let d = line.data(using: .utf8) else { return }
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(d); try? h.close() }
    else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
}

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
    let a = Array(s)                      // roman input is ASCII → 1 char per element
    var out = "", last = 0, i = 0
    let n = a.count
    while i < n {
        var rule: Rule? = nil, klen = 0
        var L = min(3, n - i)
        while L >= 1 { let key = String(a[i..<i+L]); if let u = MAP[key] { rule = u; klen = L; break }; L -= 1 }
        guard let u = rule else { out.append(a[i]); last = 3; i += 1; continue }
        i += klen
        switch u {
        case .cons(let c):      if last == 1 { out += "্" }; out += c; last = 1
        case .vowel(let iv, let kv): out += (last == 1 ? kv : iv); last = 2
        case .yphola:           out += (last == 1 ? "্য" : "য়"); last = 1
        case .wphola:           out += (last == 1 ? "্ব" : "ওয়"); last = 1
        case .sign(let sg):     out += sg; last = 3
        case .hasanta:          out += "্"; last = 1
        }
    }
    return nfc(out)
}

// ============================ system-wide phonetic hook ============================
final class Hook {
    static let shared = Hook()
    var bangla = true      // default ON (UI also defaults to bn); a dropped mode:bn must never leave a live tap inert
    private var roman = ""
    private var shown = ""                 // Bangla currently shown for the in-progress word
    // Caret anchoring for the popup. wordCaret is the real caret frozen for the current word once
    // resolved; lastCaret is the last good caret (provisional anchor while a new one resolves).
    // Caret resolution runs OFF this (main run-loop) thread so it never stalls keystroke posting.
    private var wordCaret: CaretRect? = nil
    private var lastCaret: CaretRect? = nil
    private var caretResolving = false
    private var caretGen = 0                // bumped every word/boundary; guards stale async results
    private var caretAttempts = 0
    private var lastPid: pid_t = -1
    private var tap: CFMachPort?
    private let magic: Int64 = 0xB0A61A
    private let src = CGEventSource(stateID: .privateState)

    func reset() { roman = ""; shown = ""; wordCaret = nil; caretGen &+= 1; caretAttempts = 0; CandidatePanel.shared.hide() }
    func setBangla(_ on: Bool) { bangla = on; reset() }

    func install() -> Bool {
        if tap != nil { return true }        // already installed
        let mask = (1 << CGEventType.keyDown.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                        callback: { _, type, event, _ in Hook.shared.handle(type, event) },
                                        userInfo: nil) else { return false }
        tap = t
        let rl = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), rl, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    private func post(unicode s: String) {
        if s.isEmpty { return }
        // One UTF-16 code unit per keyDown/keyUp pair: some apps (Chrome/Blink, Electron)
        // drop multi-character synthetic events, so emit each unit as its own keystroke.
        for unit in Array(s.utf16) {
            var one = [unit]
            for down in [true, false] {
                if let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down) {
                    e.keyboardSetUnicodeString(stringLength: 1, unicodeString: &one)
                    e.setIntegerValueField(.eventSourceUserData, value: magic)
                    e.post(tap: .cgSessionEventTap)
                }
            }
        }
    }
    private func backspaces(_ n: Int) {
        if n <= 0 { return }
        for _ in 0..<n { for down in [true, false] {
            if let e = CGEvent(keyboardEventSource: src, virtualKey: 0x33, keyDown: down) { // 0x33 = delete
                e.setIntegerValueField(.eventSourceUserData, value: magic); e.post(tap: .cgSessionEventTap)
            } } }
    }
    private func repaint() {
        let bn = transliterate(roman)
        let a = Array(bn.unicodeScalars), b = Array(shown.unicodeScalars)
        var common = 0
        while common < a.count && common < b.count && a[common] == b[common] { common += 1 }
        backspaces(b.count - common)
        var tail = ""; tail.unicodeScalars.append(contentsOf: a[common...] as ArraySlice)
        post(unicode: tail)
        shown = bn
        updateCandidates()
    }

    // Show the system-wide suggestion popup for the word currently being typed.
    private func updateCandidates() {
        guard bangla, !roman.isEmpty, Suggester.shared.ready else { CandidatePanel.shared.hide(); return }
        let cands = Suggester.shared.suggest(roman, 6)
        if cands.isEmpty { CandidatePanel.shared.hide(); return }
        // Anchor: the frozen real caret if we have one, else the last good caret (close, in the same
        // field), else just under the mouse. The precise caret snaps in when the async resolve lands.
        let anchor = wordCaret ?? lastCaret ?? CaretRect(point: NSEvent.mouseLocation, height: 0)
        CandidatePanel.shared.show(cands, caret: anchor)
        kickCaretResolve()
    }

    // Resolve the real caret rect off the tap thread (AX can block on a busy app), then freeze it
    // for this word and snap the popup onto it. Re-fires each keystroke until it resolves, so the
    // first word after switching to Chrome still lands correctly once Blink's a11y tree warms up.
    private func kickCaretResolve() {
        if caretResolving || wordCaret != nil { return }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != getpid() else { return }
        caretResolving = true
        let gen = caretGen
        let attempt = caretAttempts; caretAttempts += 1
        DispatchQueue.global(qos: .userInitiated).async {
            ensureAppAccessibility(pid, reassert: attempt > 0)   // re-warm in case Chromium idled off
            let raw = resolveCaretRaw(pid)
            DispatchQueue.main.async {
                self.caretResolving = false
                guard gen == self.caretGen, !self.roman.isEmpty, let raw = raw else { return }
                let c = flipToCaret(raw)
                self.wordCaret = c; self.lastCaret = c
                CandidatePanel.shared.reposition(to: c)
            }
        }
    }

    // Replace the in-progress transliteration with a chosen dictionary word, then commit.
    private func commitCandidate(_ w: String) {
        let a = Array(w.unicodeScalars), b = Array(shown.unicodeScalars)
        var common = 0
        while common < a.count && common < b.count && a[common] == b[common] { common += 1 }
        backspaces(b.count - common)
        var tail = ""; tail.unicodeScalars.append(contentsOf: a[common...] as ArraySlice)
        post(unicode: tail)
        reset()
    }

    private func isScheme(_ c: Character) -> Bool {
        // In-word scheme chars, matching the C++ reference engine's word-boundary contract:
        // ASCII letters/digits, '^' (chandrabindu), '.' (danda ।) and '`' (hasanta / khanda-ta).
        return (c.isLetter && c.isASCII) || (c.isNumber && c.isASCII) || c == "^" || c == "." || c == "`"
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == magic { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let kc = event.getIntegerValueField(.keyboardEventKeycode)

        // Ctrl+B / Ctrl+E → mode (global)
        if flags.contains(.maskControl) {
            if kc == 11 { DispatchQueue.main.async { App.shared.setMode(true)  }; return nil }  // B
            if kc == 14 { DispatchQueue.main.async { App.shared.setMode(false) }; return nil }  // E
        }
        if !bangla { return Unmanaged.passUnretained(event) }

        // don't transliterate into our own toolbar (its WebView does that itself)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() {
            return Unmanaged.passUnretained(event)
        }
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        if pid != lastPid {
            reset(); lastPid = pid
            lastCaret = nil                                             // stale for the new field
            ensureAppAccessibility(pid)                                 // warm Chromium/Electron a11y
        }

        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            reset(); return Unmanaged.passUnretained(event)              // let shortcuts run
        }
        if kc == 0x33 {                                                 // Backspace
            if !roman.isEmpty { roman.removeLast(); repaint(); return nil }
            reset(); return Unmanaged.passUnretained(event)
        }
        if kc == 0x35 && CandidatePanel.shared.visible {                // Escape → just dismiss popup
            CandidatePanel.shared.hide(); return nil
        }
        // the character this key would type
        var len = 0; var buf = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &buf)
        if len == 1, let sc = Unicode.Scalar(buf[0]), sc.isASCII {
            let ch = Character(sc)
            // While the popup is up, a digit 1..N picks that suggestion (like Avro / any IME).
            if CandidatePanel.shared.visible, let d = ch.wholeNumberValue,
               d >= 1 && d <= CandidatePanel.shared.items.count {
                commitCandidate(CandidatePanel.shared.items[d - 1]); return nil
            }
            if isScheme(ch) { roman.append(ch); repaint(); return nil }  // swallow, show Bangla
        }
        reset(); return Unmanaged.passUnretained(event)                 // boundary / other key
    }
}

// ============================ app + toolbar window ============================
final class App: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = App()
    var window: NSWindow!
    var web: WKWebView!

    func setMode(_ bangla: Bool) {
        Hook.shared.setBangla(bangla)
        web?.evaluateJavaScript("window.__hostSetMode && window.__hostSetMode('\(bangla ? "bn" : "en")')", completionHandler: nil)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(self, name: "host")
        let frame = NSRect(x: 0, y: 0, width: 560, height: 440)
        web = WKWebView(frame: frame, configuration: cfg)
        web.navigationDelegate = self
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "বাঙলা কিবোর্ড"
        window.level = .floating                          // always-on-top toolbar
        window.contentView = web
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let ui = Bundle.main.resourceURL?.appendingPathComponent("ui/index.html") {
            web.loadFileURL(URL(string: "\(ui.absoluteString)?native=1")!, allowingReadAccessTo: ui.deletingLastPathComponent())
        }

        // Load the native suggestion engine (used by the system-wide candidate popup).
        Suggester.shared.loadFromBundle()

        // Warm each app's accessibility tree as it becomes frontmost (Chromium/Electron build their
        // web a11y tree lazily; doing it on app-switch means the caret is queryable by the time the
        // user types). Clear the cache when an app quits so a relaunch (new pid) re-warms.
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            // Only warm while Bangla mode is on — no reason to pay a target app's a11y cost otherwise.
            guard Hook.shared.bangla,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            ensureAppAccessibility(app.processIdentifier, reassert: true)
        }
        wsnc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                forgetApp(app.processIdentifier)
            }
        }

        // Accessibility → system-wide typing (Bangla ON = type Bangla in ANY app).
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)              // shows the system prompt if needed
        installHookIfPossible()
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in self.installHookIfPossible() }
    }

    // Keep the UI's mode toggle/banner in sync once the page has loaded (the hook's mode is
    // the source of truth — this covers a dropped/late mode message from the page).
    func webView(_ w: WKWebView, didFinish nav: WKNavigation!) {
        setMode(Hook.shared.bangla)
        installHookIfPossible()
    }

    // Footer credit links (aicms.bd / bangla.it.com) open in the default browser instead of
    // navigating away from the toolbar UI inside the WebView.
    func webView(_ w: WKWebView, decidePolicyFor navAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navAction.navigationType == .linkActivated, let url = navAction.request.url,
           url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private var hookOn = false
    private var lastLoggedLine = ""
    func installHookIfPossible() {
        let trusted = AXIsProcessTrusted()
        if trusted && !hookOn {
            hookOn = Hook.shared.install()
            if hookOn { setMode(Hook.shared.bangla) }        // push current mode to the now-live tap's UI
        }
        let secure = IsSecureEventInputEnabled()
        // Log only when the state changes so `tail -f ~/Library/Logs/BanglaKeyboard.log`
        // shows the transition to trusted=true hookOn=true without per-poll spam.
        let line = "trusted=\(trusted) hookOn=\(hookOn) bangla=\(Hook.shared.bangla) secureInput=\(secure)"
        if line != lastLoggedLine { bkLog(line); lastLoggedLine = line }
        web?.evaluateJavaScript("window.__hostSecure&&window.__hostSecure(\(secure))", completionHandler: nil)
        web?.evaluateJavaScript("window.__hostHook&&window.__hostHook(\(hookOn))", completionHandler: nil)
    }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let s = m.body as? String else { return }
        if s == "mode:bn" { Hook.shared.setBangla(true) }
        else if s == "mode:en" { Hook.shared.setBangla(false) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = App.shared
app.delegate = delegate
app.run()
