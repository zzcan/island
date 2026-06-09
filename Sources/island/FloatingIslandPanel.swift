import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that hosts the IslandView at the
/// top-center of the main screen. Non-activating so hovering/clicking it never
/// steals focus from the user's terminal.
@MainActor
final class FloatingIslandPanel {
    private let panel: NSPanel

    init(appModel: AppModel) {
        let hosting = NSHostingView(rootView: IslandView().environmentObject(appModel))
        // Fixed generous canvas; the island draws top-center, the rest is transparent.
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
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
        // visibleFrame excludes the menu bar so the capsule sits just below it.
        let vf = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2,
                                     y: vf.maxY - size.height))
    }
}
