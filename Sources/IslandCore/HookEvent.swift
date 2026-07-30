import Foundation

public enum AgentProvider: String, Codable, Equatable, Sendable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

public enum IslandEvent: String, Codable, Equatable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case notification = "Notification"
    case stop = "Stop"
    case sessionEnd = "SessionEnd"
    case postToolUse = "PostToolUse"
    /// Interactive approval (e.g. ExitPlanMode). Travels the request/response path, not
    /// the fire-and-forget session feed — so it is intentionally NOT produced by
    /// `init?(claudeName:)`; the hook constructs it directly.
    case permissionRequest = "PermissionRequest"

    public init?(claudeName: String) {
        if claudeName == "PermissionRequest" { return nil }
        self.init(rawValue: claudeName)
    }
}

public struct ToolInput: Codable, Equatable, Sendable {
    public let file_path: String?
    public let command: String?
    public let pattern: String?
    public let path: String?
    public let plan: String?   // ExitPlanMode carries the plan markdown here
    public let description: String? // Codex approval reason, when available
}

/// The shared subset of Claude Code and Codex lifecycle-hook stdin JSON that island uses.
public struct AgentHookInput: Codable, Equatable, Sendable {
    public let session_id: String?
    public let cwd: String?
    public let hook_event_name: String?
    public let message: String?
    public let prompt: String?
    public let tool_name: String?
    public let tool_input: ToolInput?
    public let transcript_path: String?
    public let permission_mode: String?
    public let turn_id: String?
    public let model: String?                  // stable Codex hook field
    public let last_assistant_message: String? // stable Codex Stop hook field

    public static func decode(_ data: Data) throws -> AgentHookInput {
        try JSONDecoder().decode(AgentHookInput.self, from: data)
    }
}
