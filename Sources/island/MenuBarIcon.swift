import AppKit
import IslandCore

/// Draws the menu-bar status glyph: a small pixel "crab" whose colour reflects the
/// highest-priority active status across visible sessions
/// (needs-input > working > done > idle).
enum MenuBarIcon {
    private static let crab = [
        "..X.....X..", "...X...X...", "..XXXXXXX..", ".XX.XXX.XX.",
        "XXXXXXXXXXX", "X.XXXXXXX.X", "X.X.....X.X", "...XX.XX...",
    ]

    static func color(for statuses: [SessionStatus]) -> NSColor {
        let set = Set(statuses)
        if set.contains(.needsInput) { return NSColor(red: 1.0, green: 0.82, blue: 0.20, alpha: 1) }
        if set.contains(.working)    { return NSColor(red: 0.35, green: 0.70, blue: 1.0, alpha: 1) }
        if set.contains(.done)       { return NSColor(red: 0.30, green: 1.0, blue: 0.55, alpha: 1) }
        return .secondaryLabelColor
    }

    static func image(for statuses: [SessionStatus]) -> NSImage {
        let rows = crab.count, cols = crab[0].count
        let px: CGFloat = 2                       // crisp 2pt cells → 16pt tall
        let w = px * CGFloat(cols), h = px * CGFloat(rows)
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        color(for: statuses).setFill()
        for (r, line) in crab.enumerated() {
            for (c, ch) in line.enumerated() where ch != "." {
                let x = CGFloat(c) * px
                let y = CGFloat(rows - 1 - r) * px   // flip: row 0 is the top
                NSBezierPath(rect: NSRect(x: x, y: y, width: px, height: px)).fill()
            }
        }
        img.unlockFocus()
        img.isTemplate = false                    // keep the status colour
        return img
    }
}
