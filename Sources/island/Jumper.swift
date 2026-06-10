import Foundation
import AppKit
import IslandCore

/// Executes a session's JumpPlan commands, then brings the right host app forward.
///
/// - cmux / tmux: run the multiplexer CLI, then activate cmux (tmux is in-terminal).
/// - iTerm2 / Terminal.app: the osascript in the JumpPlan already activates them.
/// - Ghostty: no scripting interface — raise the exact window via Accessibility, then
///   activate the app.
struct Jumper {
    let runner: CommandRunner
    var cmuxBundleId = "com.cmuxterm.app"
    var ghosttyBundleId = "com.mitchellh.ghostty"

    init(runner: CommandRunner = ProcessRunner()) { self.runner = runner }

    func jump(to session: Session) {
        let runner = self.runner
        let cmuxId = self.cmuxBundleId
        let ghosttyId = self.ghosttyBundleId
        Task.detached {
            for cmd in JumpPlan.commands(for: session) { _ = try? runner.run(cmd) }
            await MainActor.run {
                if session.cmux != nil {
                    Jumper.activate(bundleId: cmuxId)
                } else if session.tmux != nil {
                    // tmux switched the pane in-place; no GUI app to raise reliably.
                } else if let term = session.terminal {
                    switch term.kind {
                    case .iterm, .appleTerminal:
                        break // osascript already activated the app + tab
                    case .ghostty:
                        if let title = term.ghosttyTitle {
                            GhosttyJumper.raiseWindow(titleContains: title, bundleId: ghosttyId)
                        }
                    }
                }
            }
        }
    }

    static func activate(bundleId: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }
}
