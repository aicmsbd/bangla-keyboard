// Text-caret location via the Accessibility API, for anchoring the suggestion popup in ANY app.
//
// The hard case is Chromium/Blink (Chrome, Edge, Brave, Arc) and Electron: they build NO
// web-content accessibility tree by default, so the caret query fails and the popup would land
// at the page footer. The fix is to force the tree on with the "AXManualAccessibility" opt-in
// (the side-effect-free automation flag Chromium added — unlike AXEnhancedUserInterface, which
// visibly moves/resizes windows). Enabling is asynchronous, so we warm it on app-switch and
// re-query each keystroke until the real caret resolves.
//
// EVERYTHING here except flipToCaret() is safe to call off the main thread and MUST be, because
// the CGEventTap callback runs on the main run loop — a synchronous AX call to a busy app would
// otherwise stall system-wide typing. flipToCaret() touches NSScreen and must run on main.

import Cocoa
import ApplicationServices

// Caret in Cocoa screen coords: `point` is the caret's BOTTOM-LEFT, `height` its vertical extent.
struct CaretRect { var point: NSPoint; var height: CGFloat }

private let warmLock = NSLock()
private var warmedPids = Set<pid_t>()

// Turn on a Chromium/Electron app's accessibility tree so it will answer caret queries. Cheap and
// idempotent; cached per-pid. `reassert` bypasses the cache to recover from Chromium auto-disabling
// its tree after idle. Safe to call from any thread.
func ensureAppAccessibility(_ pid: pid_t, reassert: Bool = false) {
    if pid <= 0 || pid == getpid() { return }
    warmLock.lock()
    let already = warmedPids.contains(pid)
    if !already { warmedPids.insert(pid) }
    warmLock.unlock()
    if already && !reassert { return }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.25)
    // Value is a CFBoolean; the attribute has no kAX… constant — pass the literal string.
    // Ignore the AXError: some builds return unsupported/not-writable yet still enable the tree.
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
}

func forgetApp(_ pid: pid_t) { warmLock.lock(); warmedPids.remove(pid); warmLock.unlock() }

// The raw caret rect in AX global (top-left-origin) coordinates, or nil if this app/field exposes
// no real caret. NEVER returns a container/element frame — only a genuine caret shape — so the
// popup can't get anchored to the whole web area. Call OFF the tap thread.
func resolveCaretRaw(_ pid: pid_t) -> CGRect? {
    guard let el = focusedElement(pid) else { return nil }
    AXUIElementSetMessagingTimeout(el, 0.1)
    if let r = caretViaSelectedRange(el) { return r }   // plain inputs, NSTextView, omnibox
    if let r = caretViaTextMarker(el)   { return r }    // contenteditable (Slack/Gmail/Notion)
    return nil
}

private func focusedElement(_ pid: pid_t) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.1)
    var f: CFTypeRef?
    if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &f) == .success,
       let f = f, CFGetTypeID(f) == AXUIElementGetTypeID() {
        return (f as! AXUIElement)
    }
    let sys = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(sys, 0.1)
    if AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &f) == .success,
       let f = f, CFGetTypeID(f) == AXUIElementGetTypeID() {
        return (f as! AXUIElement)
    }
    return nil
}

// A caret rect must be a thin, line-height sliver — not a whole element/page frame. Rejecting
// oversized/degenerate rects is what stops the popup from anchoring to the web-area footer.
private func looksLikeCaret(_ r: CGRect) -> Bool {
    if r.isNull || r.isInfinite { return false }
    if r.width == 0 && r.height == 0 && r.origin == .zero { return false }   // all-zero sentinel
    if r.height <= 0 || r.height > 80 { return false }                       // line-scale only
    if r.width > 8 { return false }                                          // caret is ~0–2pt wide
    return true
}

private func caretViaSelectedRange(_ el: AXUIElement) -> CGRect? {
    var rangeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
          let rr = rangeRef, CFGetTypeID(rr) == AXValueGetTypeID() else { return nil }
    var cf = CFRange()
    guard AXValueGetValue(rr as! AXValue, .cfRange, &cf) else { return nil }
    if let rect = boundsForRange(el, CFRange(location: cf.location, length: 0)), looksLikeCaret(rect) {
        return rect
    }
    // End-of-text / empty-field builds can return an empty collapsed rect: use the neighbouring
    // character's box and take its trailing (or leading, at offset 0) edge as the caret.
    if cf.location > 0, let rect = boundsForRange(el, CFRange(location: cf.location - 1, length: 1)), rect.height > 0, rect.height <= 80 {
        return CGRect(x: rect.maxX, y: rect.minY, width: 1, height: rect.height)
    }
    if let rect = boundsForRange(el, CFRange(location: cf.location, length: 1)), rect.height > 0, rect.height <= 80 {
        return CGRect(x: rect.minX, y: rect.minY, width: 1, height: rect.height)
    }
    return nil
}

private func boundsForRange(_ el: AXUIElement, _ range: CFRange) -> CGRect? {
    var r = range
    guard let rv = AXValueCreate(.cfRange, &r) else { return nil }
    var boundsRef: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                      rv, &boundsRef) == .success,
          let br = boundsRef, CFGetTypeID(br) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    return AXValueGetValue(br as! AXValue, .cgRect, &rect) ? rect : nil
}

private func caretViaTextMarker(_ el: AXUIElement) -> CGRect? {
    var smr: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, "AXSelectedTextMarkerRange" as CFString, &smr) == .success,
          let smr = smr else { return nil }
    var boundsRef: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(el, "AXBoundsForTextMarkerRange" as CFString,
                                                      smr, &boundsRef) == .success,
          let br = boundsRef, CFGetTypeID(br) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue(br as! AXValue, .cgRect, &rect), looksLikeCaret(rect) else { return nil }
    return rect
}

// Flip an AX global (top-left-origin) rect to a Cocoa (bottom-left-origin) caret. The flip constant
// is the PRIMARY screen height (the one whose frame.origin == .zero) — NOT NSScreen.main, which on a
// multi-monitor setup is the key screen and would introduce a (mainH - primaryH) vertical error.
// MUST run on the main thread (NSScreen).
func flipToCaret(_ rect: CGRect) -> CaretRect {
    let primaryH = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.height ?? rect.maxY
    return CaretRect(point: NSPoint(x: rect.minX, y: primaryH - rect.maxY), height: rect.height)
}
