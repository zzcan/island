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

/// Borderless, non-activating floating panel that hosts the IslandView at the
/// top-center of the main screen. Non-activating so hovering/clicking it never
/// steals focus from the user's terminal.
@MainActor
final class FloatingIslandPanel {
    private let panel: NSPanel

    init(appModel: AppModel) {
        let hosting = NSHostingView(rootView: IslandView().environmentObject(appModel))
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
        // Set the level AFTER isFloatingPanel — toggling isFloatingPanel resets the
        // level back to .floating, which both sits BELOW the menu bar and lets the
        // OS clamp the frame. CGShieldingWindowLevel composites over the menu bar /
        // notch row so the capsule overlays the notch instead of hiding beneath it.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
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
        // IslandView pads its content 6pt from the panel's top edge.
        let contentTopInset: CGFloat = 6
        // The capsule is wider than the notch, so don't cover the notch — hang it
        // just BELOW it. Drop by the notch height (safeAreaInsets.top); on screens
        // without a notch, drop below the menu bar instead.
        let topInset = screen.safeAreaInsets.top > 0
            ? screen.safeAreaInsets.top
            : f.maxY - screen.visibleFrame.maxY
        panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2,
                                     y: f.maxY - topInset - size.height + contentTopInset))
    }
}
