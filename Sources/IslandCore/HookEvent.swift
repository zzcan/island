import Foundation

public enum IslandEvent: String, Codable, Equatable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case notification = "Notification"
    case stop = "Stop"
    case sessionEnd = "SessionEnd"

    public init?(claudeName: String) {
        self.init(rawValue: claudeName)
    }
}

/// The raw JSON Claude Code writes to a hook's stdin (subset we use).
public struct ClaudeHookInput: Codable, Equatable, Sendable {
    public let session_id: String?
    public let cwd: String?
    public let hook_event_name: String?
    public let message: String?

    public static func decode(_ data: Data) throws -> ClaudeHookInput {
        try JSONDecoder().decode(ClaudeHookInput.self, from: data)
    }
}
