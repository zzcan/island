import AppKit
import SwiftUI

/// NSPanel that refuses AppKit's automatic "keep the window below the menu bar"
/// constraint, so we can place the capsule flush at the very top of the display
/// (over the notch / menu-bar strip). Without this override, setFrameOrigin to a
/// point inside the menu-bar region is silently clamped back down.
private final class NotchPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Shared, mutable holder for the island's current visible rect (top-left origin, in
/// the hosting view's coordinate space, i.e. within the 500×360 canvas). IslandView
/// writes it as the island grows/shrinks; the panel uses it to decide click passthrough.
@MainActor final class IslandHitRegion {
    var rect: CGRect = .zero
}

/// Borderless, non-activating floating panel that hosts the IslandView at the
/// top-center of the main screen. Non-activating so hovering/clicking it never
/// steals focus from the user's terminal.
@MainActor
final class FloatingIslandPanel {
    private let panel: NSPanel
    private let hitRegion = IslandHitRegion()
    private var monitors: [Any] = []

    init(appModel: AppModel) {
        let region = hitRegion
        let hosting = NSHostingView(rootView: IslandView(hitRegion: region).environmentObject(appModel))
        // Fixed generous canvas; the island draws top-center, the rest is transparent.
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        // Start fully click-through; the mouse monitors enable interaction only while
        // the cursor is actually over the island (see updatePassthrough). A returned-nil
        // hitTest does NOT pass clicks through to other apps — only ignoresMouseEvents
        // does — so we toggle that per cursor position instead.
        panel.ignoresMouseEvents = true
        // z-order: notch > island > menu bar.
        // The notch is a hardware cutout (no pixels), so it is ALWAYS on top and the
        // capsule's middle is simply clipped by it — its wider ears peek out around
        // it. We only need the island ABOVE the menu bar (vs .floating, which sits
        // below it and let the menu bar swallow hover events, hiding the island).
        // CGShieldingWindowLevel composites over the menu bar so the ears are visible
        // and hoverable. (NotchPanel.constrainFrameRect keeps it pinned to the top.)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        reposition()
        installMouseMonitors()
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    /// Toggle window-level click-through based on whether the cursor is over the island.
    /// The global monitor fires while we're passthrough (events go elsewhere) → detects
    /// the cursor ENTERING the island; the local monitor fires while we own events →
    /// detects it LEAVING. Both recompute the same way.
    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.updatePassthrough()
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.updatePassthrough()
            return event
        }
        monitors = [global, local].compactMap { $0 }
        updatePassthrough()
    }

    private func updatePassthrough() {
        let r = hitRegion.rect
        guard !r.isEmpty else { panel.ignoresMouseEvents = true; return }
        // Convert the island rect (top-left, within the 500×360 canvas) to screen
        // coordinates (bottom-left, matching NSEvent.mouseLocation). The canvas top is
        // panel.frame.maxY, and the rect's y grows downward, so subtract r.maxY.
        let screenRect = CGRect(x: panel.frame.minX + r.minX,
                                y: panel.frame.maxY - r.maxY,
                                width: r.width, height: r.height)
        panel.ignoresMouseEvents = !screenRect.contains(NSEvent.mouseLocation)
    }

    private func reposition() {
        // Pin to the PRIMARY display (the one with the menu bar, origin (0,0)) —
        // not NSScreen.main, which is whichever screen currently has key focus and
        // would drift to another monitor on a multi-display setup.
        let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero })
        guard let screen = primary ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let f = screen.frame
        let size = panel.frame.size
        // IslandView pads its content 6pt from the panel's top edge; compensate so
        // the capsule's top is flush with the physical screen top — same position as
        // the notch. The notch (hardware) clips the capsule's middle, so its wider
        // ears peek out around it (see the z-order note in init).
        let contentTopInset: CGFloat = 6
        panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2,
                                     y: f.maxY - size.height + contentTopInset))
    }
}
