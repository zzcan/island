import Foundation
import IslandCore

/// Glue between the app and HookRegistrar: silently keeps vibe-hook registered in
/// Claude Code's settings on every launch and whenever the plan-review toggle flips.
enum HookSync {
    /// No-op when the bundled vibe-hook is missing (e.g. running the bare executable
    /// from `swift run` instead of the .app bundle).
    static func sync(planReview: Bool) {
        let hookPath = Bundle.main.bundlePath + "/Contents/MacOS/vibe-hook"
        guard FileManager.default.isExecutableFile(atPath: hookPath) else { return }
        let env = ProcessInfo.processInfo.environment
        let settingsPath = env["CLAUDE_SETTINGS"] ?? (NSHomeDirectory() + "/.claude/settings.json")
        DispatchQueue.global(qos: .utility).async {
            HookRegistrar.sync(settingsPath: settingsPath, hookPath: hookPath, planReview: planReview)
        }
    }
}
