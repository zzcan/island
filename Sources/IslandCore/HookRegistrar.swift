import Foundation

/// Keeps vibe-hook registered in Claude Code and Codex JSON hook configurations.
/// Stale copies (old build/install paths) are replaced by the current hook command,
/// so registration self-heals when the app moves.
public enum HookRegistrar {
    public static let coreEvents = ["SessionStart", "UserPromptSubmit", "Notification",
                                    "Stop", "SessionEnd", "PostToolUse"]
    public static let planReviewEvent = "PermissionRequest"
    public static let codexEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse",
                                     "Stop", "SessionEnd", "PermissionRequest"]

    /// Pure transform: returns the updated settings object, or nil when nothing changed.
    public static func updated(settings: [String: Any], hookPath: String,
                               planReview: Bool) -> [String: Any]? {
        update(document: settings,
               events: coreEvents + (planReview ? [planReviewEvent] : []),
               removing: planReview ? [] : [planReviewEvent],
               command: hookPath)
    }

    /// Pure transform for ~/.codex/hooks.json. PermissionRequest is always installed,
    /// but the hook only notifies island and returns no decision, preserving Codex's
    /// native approval flow.
    public static func updatedCodex(hooksFile: [String: Any],
                                    hookPath: String) -> [String: Any]? {
        update(document: hooksFile, events: codexEvents, removing: [],
               command: "\(shellQuote(hookPath)) --provider codex")
    }

    /// File-level sync: read settings.json (missing → empty, unparseable → untouched),
    /// apply the transform, back up and atomically rewrite when something changed.
    /// Returns true if the file was written.
    @discardableResult
    public static func sync(settingsPath: String, hookPath: String, planReview: Bool) -> Bool {
        syncFile(path: settingsPath) { updated(settings: $0, hookPath: hookPath,
                                               planReview: planReview) }
    }

    @discardableResult
    public static func syncCodex(hooksPath: String, hookPath: String) -> Bool {
        syncFile(path: hooksPath) { updatedCodex(hooksFile: $0, hookPath: hookPath) }
    }

    // MARK: - transforms

    private static func update(document: [String: Any], events: [String],
                               removing: [String], command: String) -> [String: Any]? {
        var hooks = document["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            if ensureRegistered(in: &groups, command: command) { changed = true }
            hooks[event] = groups
        }
        for event in removing where hooks[event] != nil {
            var groups = hooks[event] as? [[String: Any]] ?? []
            if removeOurs(from: &groups) { changed = true }
            hooks[event] = groups.isEmpty ? nil : groups
        }

        guard changed else { return nil }
        var out = document
        out["hooks"] = hooks
        return out
    }

    // MARK: - file sync

    private static func syncFile(path: String,
                                 transform: ([String: Any]) -> [String: Any]?) -> Bool {
        let fm = FileManager.default
        var settings: [String: Any] = [:]
        let exists = fm.fileExists(atPath: path)
        if exists, let data = fm.contents(atPath: path), !data.isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            settings = parsed
        }

        guard let updated = transform(settings),
              let out = try? JSONSerialization.data(withJSONObject: updated,
                                                    options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }

        if exists {
            let bak = path + ".island.bak"
            try? fm.removeItem(atPath: bak)
            try? fm.copyItem(atPath: path, toPath: bak)
        } else {
            try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                    withIntermediateDirectories: true)
        }
        do {
            try out.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            return false
        }
        return true
    }

    // MARK: - helpers

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        guard let cmd = entry["command"] as? String else { return false }
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        let executable: String
        if let quote = trimmed.first, quote == "'" || quote == "\"",
           let end = trimmed.dropFirst().firstIndex(of: quote) {
            executable = String(trimmed[trimmed.index(after: trimmed.startIndex)..<end])
        } else {
            executable = String(trimmed.prefix { !$0.isWhitespace })
        }
        return (executable as NSString).lastPathComponent == "vibe-hook"
    }

    /// Remove stale/duplicate vibe-hook entries and make sure `hookPath` is present
    /// exactly once. Groups emptied by the cleanup are dropped.
    private static func ensureRegistered(in groups: inout [[String: Any]], command: String) -> Bool {
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
                if (entry["command"] as? String) == command, !present {
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
                entries.append(["type": "command", "command": command])
                result[idx]["hooks"] = entries
            } else {
                result.append(["hooks": [["type": "command", "command": command]]])
            }
            changed = true
        }
        groups = result
        return changed
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
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
