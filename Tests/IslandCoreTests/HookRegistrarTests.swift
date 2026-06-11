import Foundation
import Testing
@testable import IslandCore

private let hook = "/Applications/island.app/Contents/MacOS/vibe-hook"

private func commands(_ settings: [String: Any], _ event: String) -> [String] {
    let hooks = settings["hooks"] as? [String: Any] ?? [:]
    let groups = hooks[event] as? [[String: Any]] ?? []
    return groups.flatMap { group in
        (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
    }
}

@Suite struct HookRegistrarTransformTests {
    @Test func registersAllCoreEventsIntoEmptySettings() {
        let result = HookRegistrar.updated(settings: [:], hookPath: hook, planReview: false)
        let updated = try! #require(result)
        for event in HookRegistrar.coreEvents {
            #expect(commands(updated, event) == [hook])
        }
        #expect(commands(updated, "PermissionRequest").isEmpty)
    }

    @Test func planReviewOnRegistersPermissionRequest() {
        let result = HookRegistrar.updated(settings: [:], hookPath: hook, planReview: true)
        let updated = try! #require(result)
        #expect(commands(updated, "PermissionRequest") == [hook])
    }

    @Test func planReviewOffRemovesOurPermissionRequestEntry() {
        let withPermission = HookRegistrar.updated(settings: [:], hookPath: hook, planReview: true)!
        let result = HookRegistrar.updated(settings: withPermission, hookPath: hook, planReview: false)
        let updated = try! #require(result)
        #expect(commands(updated, "PermissionRequest").isEmpty)
        // The emptied event key is dropped entirely, not left as [].
        let hooks = updated["hooks"] as? [String: Any] ?? [:]
        #expect(hooks["PermissionRequest"] == nil)
    }

    @Test func idempotentWhenAlreadyRegistered() {
        let once = HookRegistrar.updated(settings: [:], hookPath: hook, planReview: true)!
        #expect(HookRegistrar.updated(settings: once, hookPath: hook, planReview: true) == nil)
    }

    @Test func preservesForeignKeysAndForeignHooks() {
        let settings: [String: Any] = [
            "model": "opus",
            "hooks": [
                "Stop": [
                    ["hooks": [["type": "command", "command": "/usr/local/bin/other-tool"]]],
                ],
            ],
        ]
        let updated = try! #require(HookRegistrar.updated(settings: settings, hookPath: hook, planReview: false))
        #expect(updated["model"] as? String == "opus")
        #expect(commands(updated, "Stop").contains("/usr/local/bin/other-tool"))
        #expect(commands(updated, "Stop").contains(hook))
    }

    @Test func replacesStaleVibeHookPaths() {
        let stale = "/Users/me/code/island/build/island.app/Contents/MacOS/vibe-hook"
        var settings: [String: Any] = [:]
        settings = HookRegistrar.updated(settings: settings, hookPath: stale, planReview: true)!
        let updated = try! #require(HookRegistrar.updated(settings: settings, hookPath: hook, planReview: true))
        for event in HookRegistrar.coreEvents + ["PermissionRequest"] {
            #expect(commands(updated, event) == [hook], "event \(event)")
        }
    }
}

@Suite struct HookRegistrarSyncTests {
    private func tempDir() -> String {
        let dir = NSTemporaryDirectory() + "hook-registrar-test-" + UUID().uuidString
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func createsSettingsFileWhenMissing() {
        let path = tempDir() + "/settings.json"
        let wrote = HookRegistrar.sync(settingsPath: path, hookPath: hook, planReview: false)
        #expect(wrote)
        let data = try! Data(contentsOf: URL(fileURLWithPath: path))
        let parsed = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(commands(parsed, "SessionStart") == [hook])
    }

    @Test func secondSyncIsNoOpAndLeavesNoBackupChurn() {
        let path = tempDir() + "/settings.json"
        #expect(HookRegistrar.sync(settingsPath: path, hookPath: hook, planReview: false))
        #expect(!HookRegistrar.sync(settingsPath: path, hookPath: hook, planReview: false))
    }

    @Test func backsUpExistingFileBeforeRewriting() {
        let path = tempDir() + "/settings.json"
        let original = #"{"model":"opus"}"#
        try! original.write(toFile: path, atomically: true, encoding: .utf8)
        #expect(HookRegistrar.sync(settingsPath: path, hookPath: hook, planReview: false))
        let backup = try! String(contentsOfFile: path + ".island.bak", encoding: .utf8)
        #expect(backup == original)
    }

    @Test func unparseableFileIsLeftUntouched() {
        let path = tempDir() + "/settings.json"
        try! "not json {".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(!HookRegistrar.sync(settingsPath: path, hookPath: hook, planReview: false))
        #expect(try! String(contentsOfFile: path, encoding: .utf8) == "not json {")
    }
}
