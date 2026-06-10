import AppKit
import ApplicationServices

/// Ghostty exposes no AppleScript or URL scheme for selecting a window/tab, so we
/// locate the target window through the Accessibility API. The vibe-hook stamps each
/// session's Ghostty window with a unique title via OSC 2 (`TerminalDetect.ghosttyTitle`);
/// here we find the window whose AXTitle contains that marker and raise it.
///
/// Requires Accessibility (AXIsProcessTrusted) permission — we prompt for it lazily on
/// the first Ghostty jump.
enum GhosttyJumper {
    @MainActor
    static func raiseWindow(titleContains marker: String, bundleId: String) {
        ensureTrusted()

        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId).first else { return }

        // Bring the app forward first; raising a specific window still picks the tab.
        app.activate(options: [])

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }

        for win in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else { continue }
            if title.contains(marker) {
                AXUIElementPerformAction(win, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
                return
            }
        }
    }

    /// Triggers the system Accessibility permission prompt the first time it's needed.
    /// No-op once granted.
    @MainActor
    private static func ensureTrusted() {
        // Literal value of kAXTrustedCheckOptionPrompt — referencing the global CFStringRef
        // directly trips Swift 6 strict-concurrency (it's a non-Sendable mutable global).
        let key = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
