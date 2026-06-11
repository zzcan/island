import Foundation

/// Keeps vibe-hook registered in Claude Code's settings.json. An entry is "ours" when
/// its command's last path component is `vibe-hook`; stale copies (old build/install
/// paths) are replaced by the current hook path, so the registration self-heals when
/// the app moves. The PermissionRequest event follows the plan-review setting.
public enum HookRegistrar {
    public static let coreEvents = ["SessionStart", "UserPromptSubmit", "Notification",
                                    "Stop", "SessionEnd", "PostToolUse"]
    public static let planReviewEvent = "PermissionRequest"

    /// Pure transform: returns the updated settings object, or nil when nothing changed.
    public static func updated(settings: [String: Any], hookPath: String,
                               planReview: Bool) -> [String: Any]? {
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for event in coreEvents + (planReview ? [planReviewEvent] : []) {
            var groups = hooks[event] as? [[String: Any]] ?? []
            if ensureRegistered(in: &groups, hookPath: hookPath) { changed = true }
            hooks[event] = groups
        }
        if !planReview, var groups = hooks[planReviewEvent] as? [[String: Any]] {
            if removeOurs(from: &groups) { changed = true }
            hooks[planReviewEvent] = groups.isEmpty ? nil : groups
        }

        guard changed else { return nil }
        var out = settings
        out["hooks"] = hooks
        return out
    }

    /// File-level sync: read settings.json (missing → empty, unparseable → untouched),
    /// apply the transform, back up and atomically rewrite when something changed.
    /// Returns true if the file was written.
    @discardableResult
    public static func sync(settingsPath: String, hookPath: String, planReview: Bool) -> Bool {
        let fm = FileManager.default
        var settings: [String: Any] = [:]
        let exists = fm.fileExists(atPath: settingsPath)
        if exists, let data = fm.contents(atPath: settingsPath), !data.isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            settings = parsed
        }

        guard let updated = updated(settings: settings, hookPath: hookPath, planReview: planReview),
              let out = try? JSONSerialization.data(withJSONObject: updated,
                                                    options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }

        if exists {
            let bak = settingsPath + ".island.bak"
            try? fm.removeItem(atPath: bak)
            try? fm.copyItem(atPath: settingsPath, toPath: bak)
        } else {
            try? fm.createDirectory(atPath: (settingsPath as NSString).deletingLastPathComponent,
                                    withIntermediateDirectories: true)
        }
        do {
            try out.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
        } catch {
            return false
        }
        return true
    }

    // MARK: - helpers

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        guard let cmd = entry["command"] as? String else { return false }
        return (cmd as NSString).lastPathComponent == "vibe-hook"
    }

    /// Remove stale/duplicate vibe-hook entries and make sure `hookPath` is present
    /// exactly once. Groups emptied by the cleanup are dropped.
    private static func ensureRegistered(in groups: inout [[String: Any]], hookPath: String) -> Bool {
        var changed = false
        var present = false
        var result: [[String: Any]] = []
        for var group in groups {
            guard var entries = group["hooks"] as? [[String: Any]] else {
                result.append(group)
                continue
            }
            let before = entries.count
            entries.removeAll { entry in
                guard isOurs(entry) else { return false }
                if (entry["command"] as? String) == hookPath, !present {
                    present = true
                    return false
                }
                return true // stale path or duplicate
            }
            if entries.count != before { changed = true }
            if entries.isEmpty, before > 0 { continue } // drop the group we emptied
            group["hooks"] = entries
            result.append(group)
        }
        if !present {
            if let idx = result.firstIndex(where: { $0["hooks"] is [[String: Any]] }) {
                var entries = result[idx]["hooks"] as! [[String: Any]]
                entries.append(["type": "command", "command": hookPath])
                result[idx]["hooks"] = entries
            } else {
                result.append(["hooks": [["type": "command", "command": hookPath]]])
            }
            changed = true
        }
        groups = result
        return changed
    }

    /// Strip every vibe-hook entry (used when plan review is off). Groups emptied by
    /// the cleanup are dropped.
    private static func removeOurs(from groups: inout [[String: Any]]) -> Bool {
        var changed = false
        var result: [[String: Any]] = []
        for var group in groups {
            guard var entries = group["hooks"] as? [[String: Any]] else {
                result.append(group)
                continue
            }
            let before = entries.count
            entries.removeAll(where: isOurs)
            if entries.count != before { changed = true }
            if entries.isEmpty, before > 0 { continue }
            group["hooks"] = entries
            result.append(group)
        }
        groups = result
        return changed
    }
}
