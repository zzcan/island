import AppKit
import SwiftUI

/// Hosts the SwiftUI SettingsView in a normal titled window. Because the app is an
/// accessory (LSUIElement) with no Dock icon, we temporarily switch to a regular
/// activation policy while the window is open so it can take keyboard focus, then
/// revert when it closes.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window {
            present(window)
            return
        }
        let host = NSHostingController(rootView: SettingsView())
        let w = NSWindow(contentViewController: host)
        w.title = "Island 设置"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.setContentSize(NSSize(width: 720, height: 600))
        window = w
        present(w)
    }

    private func present(_ w: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        centerOnMainScreen(w)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// `NSWindow.center()` misbehaves for an accessory app whose window resizes after
    /// creation (it placed the window partly off the top of the screen). Center it
    /// explicitly within the active screen's visible frame instead.
    private func centerOnMainScreen(_ w: NSWindow) {
        guard let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        let size = w.frame.size
        w.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2))
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu-bar-only accessory once settings is dismissed.
        NSApp.setActivationPolicy(.accessory)
    }
}
