import Foundation
import IslandCore

/// Keeps vibe-hook registered for Claude Code and Codex on every app launch.
enum HookSync {
    /// No-op when the bundled vibe-hook is missing (e.g. running the bare executable
    /// from `swift run` instead of the .app bundle).
    static func sync(planReview: Bool) {
        let hookPath = Bundle.main.bundlePath + "/Contents/MacOS/vibe-hook"
        guard FileManager.default.isExecutableFile(atPath: hookPath) else { return }
        let env = ProcessInfo.processInfo.environment
        let claudePath = env["CLAUDE_SETTINGS"] ?? (NSHomeDirectory() + "/.claude/settings.json")
        let codexHome = env["CODEX_HOME"] ?? (NSHomeDirectory() + "/.codex")
        let codexPath = codexHome + "/hooks.json"
        DispatchQueue.global(qos: .utility).async {
            HookRegistrar.sync(settingsPath: claudePath, hookPath: hookPath, planReview: planReview)
            HookRegistrar.syncCodex(hooksPath: codexPath, hookPath: hookPath)
        }
    }
}
