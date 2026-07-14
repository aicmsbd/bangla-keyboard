// Floating candidate popup for system-wide suggestions. A borderless, NON-ACTIVATING panel
// (it must never steal focus from the app being typed into) that shows the current word's
// suggestions with 1..N selectors, positioned at the text caret. Selection is by number key,
// handled in the CGEventTap (see Hook) — the panel itself takes no input.

import Cocoa

final class CandidatePanel {
    static let shared = CandidatePanel()

    private var panel: NSPanel?
    private var field: NSTextField?
    private(set) var items: [String] = []

    var visible: Bool { panel?.isVisible ?? false }

    private func ensurePanel() {
        if panel != nil { return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 28),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .popUpMenu                                   // above ordinary + floating windows
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.isMovableByWindowBackground = false
        p.ignoresMouseEvents = true                            // selection is keyboard-only
        p.hasShadow = true
        p.backgroundColor = .clear
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let bg = NSView(frame: p.contentView!.bounds)
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.15, alpha: 0.97).cgColor
        bg.layer?.cornerRadius = 8
        bg.autoresizingMask = [.width, .height]

        let f = NSTextField(labelWithString: "")
        f.isBezeled = false; f.isEditable = false; f.drawsBackground = false
        f.font = NSFont.systemFont(ofSize: 15)
        bg.addSubview(f)
        p.contentView?.addSubview(bg)
        panel = p; field = f
    }

    // Render "1 জন্য   2 জন   3 জন্যও" — numbers dimmed, words light — and size the panel to fit.
    private func render(_ cands: [String]) {
        guard let f = field else { return }
        let dim = NSColor(white: 0.62, alpha: 1)
        let fg  = NSColor(white: 0.98, alpha: 1)
        let numFont = NSFont.systemFont(ofSize: 11)
        let wFont   = NSFont.systemFont(ofSize: 15)
        let s = NSMutableAttributedString()
        for (i, w) in cands.enumerated() {
            if i > 0 { s.append(NSAttributedString(string: "   ", attributes: [.font: wFont])) }
            s.append(NSAttributedString(string: "\(i+1) ", attributes: [.font: numFont, .foregroundColor: dim]))
            s.append(NSAttributedString(string: w, attributes: [.font: wFont, .foregroundColor: fg]))
        }
        f.attributedStringValue = s
        f.sizeToFit()
        let pad: CGFloat = 10
        let w = f.frame.width + pad * 2, h = f.frame.height + pad
        f.frame.origin = NSPoint(x: pad, y: pad / 2)
        panel?.setContentSize(NSSize(width: w, height: h))
    }

    // Show `cands`, anchored at `caret`.
    func show(_ cands: [String], caret: CaretRect) {
        if cands.isEmpty { hide(); return }
        ensurePanel()
        items = cands
        render(cands)
        place(caret)
        panel?.orderFrontRegardless()                          // show without activating our app
    }

    // Move an already-visible popup to a freshly-resolved caret (no re-render).
    func reposition(to caret: CaretRect) {
        guard visible else { return }
        place(caret)
    }

    func hide() {
        if let p = panel, p.isVisible { p.orderOut(nil) }
        items = []
    }

    // Position the panel just below the caret, on the screen that actually contains it, clamped
    // to that screen. `caret.point` is the caret's bottom-left in Cocoa coords, `caret.height`
    // its extent (used when flipping the popup above the caret if there is no room below).
    private func place(_ caret: CaretRect) {
        guard let p = panel else { return }
        let P = caret.point, H = max(caret.height, 0)
        let panelW = p.frame.width, panelH = p.frame.height, gap: CGFloat = 2
        let screen = NSScreen.screens.first(where: { $0.frame.contains(P) })
            ?? NSScreen.screens.min(by: { edgeDist($0.frame, P) < edgeDist($1.frame, P) })
            ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = min(max(P.x, vf.minX + 4), vf.maxX - panelW - 4)
        var y = P.y - gap - panelH                             // prefer BELOW the caret
        if y < vf.minY + 4 { y = P.y + H + gap }               // no room below → flip ABOVE (true top)
        y = min(max(y, vf.minY + 4), vf.maxY - panelH - 4)     // two-sided clamp
        p.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func edgeDist(_ r: NSRect, _ p: NSPoint) -> CGFloat {
        let dx = p.x - min(max(p.x, r.minX), r.maxX)
        let dy = p.y - min(max(p.y, r.minY), r.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
