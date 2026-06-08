import Foundation
import AppKit
import IslandCore

/// Executes the JumpPlan commands then brings cmux to the front.
struct Jumper {
    let runner: CommandRunner
    var cmuxBundleId = "com.cmuxterm.app"

    init(runner: CommandRunner = ProcessRunner()) { self.runner = runner }

    func jump(to session: Session) {
        for cmd in JumpPlan.commands(for: session) {
            _ = try? runner.run(cmd)   // best-effort; failures are logged by ProcessRunner caller if desired
        }
        activateCmux()
    }

    private func activateCmux() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cmuxBundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }
}
