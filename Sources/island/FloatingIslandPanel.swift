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
/// the hosting view's coordinate space). IslandView writes it as the island grows and
/// shrinks; PassthroughContainer reads it to decide which clicks to swallow.
@MainActor final class IslandHitRegion {
    var rect: CGRect = .zero
}

/// The panel's content view. The panel canvas is a big fixed rectangle but only the
/// capsule/expanded panel is drawn; the rest is transparent. Without this, the whole
/// canvas would sit above the menu bar and could intercept clicks meant for apps (or
/// menu-bar items) behind the transparent area. We hit-test ONLY the island's current
/// rect and return nil elsewhere, so clicks outside the island pass straight through.
private final class PassthroughContainer: NSView {
    var hitRegion: IslandHitRegion?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let region = hitRegion, !region.rect.isEmpty else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        // region.rect uses SwiftUI's top-left origin; flip if this view is bottom-left.
        let p = isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
        return region.rect.contains(p) ? super.hitTest(point) : nil
    }
}

/// Borderless, non-activating floating panel that hosts the IslandView at the
/// top-center of the main screen. Non-activating so hovering/clicking it never
/// steals focus from the user's terminal.
@MainActor
final class FloatingIslandPanel {
    private let panel: NSPanel

    private let hitRegion = IslandHitRegion()

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
        // z-order: notch > island > menu bar.
        // The notch is a hardware cutout (no pixels), so it is ALWAYS on top and the
        // capsule's middle is simply clipped by it — its wider ears peek out around
        // it. We only need the island ABOVE the menu bar (vs .floating, which sits
        // below it and let the menu bar swallow hover events, hiding the island).
        // CGShieldingWindowLevel composites over the menu bar so the ears are visible
        // and hoverable. (NotchPanel.constrainFrameRect keeps it pinned to the top.)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        // Wrap the hosting view in a passthrough container that only accepts clicks
        // landing on the island itself.
        let container = PassthroughContainer()
        container.hitRegion = region
        panel.contentView = container
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        reposition()
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
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
