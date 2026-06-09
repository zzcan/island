import Foundation

public enum IslandEvent: String, Codable, Equatable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case notification = "Notification"
    case stop = "Stop"
    case sessionEnd = "SessionEnd"
    case postToolUse = "PostToolUse"

    public init?(claudeName: String) {
        self.init(rawValue: claudeName)
    }
}

public struct ToolInput: Codable, Equatable, Sendable {
    public let file_path: String?
    public let command: String?
    public let pattern: String?
    public let path: String?
}

/// The raw JSON Claude Code writes to a hook's stdin (subset we use).
public struct ClaudeHookInput: Codable, Equatable, Sendable {
    public let session_id: String?
    public let cwd: String?
    public let hook_event_name: String?
    public let message: String?
    public let prompt: String?
    public let tool_name: String?
    public let tool_input: ToolInput?
    public let transcript_path: String?

    public static func decode(_ data: Data) throws -> ClaudeHookInput {
        try JSONDecoder().decode(ClaudeHookInput.self, from: data)
    }
}
