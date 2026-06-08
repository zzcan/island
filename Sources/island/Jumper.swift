import Foundation
import AppKit
import IslandCore

/// Executes the JumpPlan commands then brings cmux to the front.
struct Jumper {
    let runner: CommandRunner
    var cmuxBundleId = "com.cmuxterm.app"

    init(runner: CommandRunner = ProcessRunner()) { self.runner = runner }

    func jump(to session: Session) {
        let runner = self.runner
        let bundleId = self.cmuxBundleId
        Task.detached {
            for cmd in JumpPlan.commands(for: session) { _ = try? runner.run(cmd) }
            await MainActor.run { Jumper.activateCmux(bundleId: bundleId) }
        }
    }

    static func activateCmux(bundleId: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }
}
