import Foundation

/// The user's decision, sent app → hook over the socket in response to a
/// `permissionRequest` HookMessage. The hook turns it into the JSON Claude Code
/// expects on stdout via `PlanHookOutput.json`.
public struct PermissionReply: Codable, Equatable, Sendable {
    /// "allow" | "deny" | "defer" ("defer" → hand back to the terminal's own prompt).
    public let behavior: String
    /// On allow: the session permission mode to set going forward —
    /// "default" | "acceptEdits" | "bypassPermissions". nil keeps the pre-plan mode.
    public let mode: String?
    /// On deny: the feedback shown to Claude so it can revise the plan.
    public let reason: String?

    public init(behavior: String, mode: String? = nil, reason: String? = nil) {
        self.behavior = behavior; self.mode = mode; self.reason = reason
    }

    public static let allow = PermissionReply(behavior: "allow")
    public static func allow(mode: String) -> PermissionReply { PermissionReply(behavior: "allow", mode: mode) }
    public static func deny(reason: String) -> PermissionReply { PermissionReply(behavior: "deny", reason: reason) }
    public static let defer_ = PermissionReply(behavior: "defer")
}

/// Builds the stdout JSON a `PermissionRequest` hook prints so Claude Code applies the
/// decision. Returns nil for "defer" (the hook then prints nothing, and Claude falls
/// back to its own terminal prompt).
///
/// Shape (per Claude Code hook docs):
///   {"hookSpecificOutput":{"hookEventName":"PermissionRequest",
///     "decision":{"behavior":"allow",
///       "updatedPermissions":[{"type":"setMode","mode":"acceptEdits","destination":"session"}]}}}
/// For deny, the feedback is emitted under both `permissionDecisionReason` (documented)
/// and `reason` (belt-and-suspenders for version drift; unknown fields are ignored).
public enum PlanHookOutput {
    public static func json(reply: PermissionReply) -> String? {
        var decision: [String: Any] = ["behavior": reply.behavior]
        switch reply.behavior {
        case "allow":
            if let mode = reply.mode {
                decision["updatedPermissions"] = [
                    ["type": "setMode", "mode": mode, "destination": "session"]
                ]
            }
        case "deny":
            if let reason = reply.reason, !reason.isEmpty {
                decision["permissionDecisionReason"] = reason
                decision["reason"] = reason
            }
        default:
            return nil // defer
        }
        let obj: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision,
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
