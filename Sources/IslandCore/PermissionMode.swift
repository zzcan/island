import Foundation

/// Colour category for a permission-mode badge, ordered roughly by how much
/// authority the mode grants. The UI layer maps each case to a concrete colour
/// (kept out of IslandCore so this stays SwiftUI-free and unit-testable).
public enum PermissionTint: String, Equatable, Sendable {
    case neutral   // default — asks every time
    case plan      // plan — read-only planning
    case edits     // acceptEdits — auto-accepts file edits
    case auto      // auto / dontAsk
    case full      // bypassPermissions — auto-approves everything
}

/// A localized label + tint derived from Claude Code or Codex `permission_mode`.
public struct PermissionMode: Equatable, Sendable {
    public let label: String
    public let tint: PermissionTint

    public init(label: String, tint: PermissionTint) {
        self.label = label
        self.tint = tint
    }

    /// Maps the raw `permission_mode` string to a badge. Returns nil when the mode
    /// is unknown to us yet (no permission-aware event received) so the UI hides the
    /// badge. An unrecognized non-empty value is shown verbatim (forward-compat).
    public static func from(_ raw: String?) -> PermissionMode? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case "default":           return PermissionMode(label: "默认",     tint: .neutral)
        case "plan":              return PermissionMode(label: "计划",     tint: .plan)
        case "acceptEdits":       return PermissionMode(label: "接受编辑", tint: .edits)
        case "auto":              return PermissionMode(label: "自动",     tint: .auto)
        case "dontAsk":           return PermissionMode(label: "不询问",   tint: .auto)
        case "bypassPermissions": return PermissionMode(label: "自动批准", tint: .full)
        default:                  return PermissionMode(label: raw,        tint: .neutral)
        }
    }
}
