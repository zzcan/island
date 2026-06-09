import Foundation

public struct IslandRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: SessionStatus
    public let lastActivity: Date
    public let prompt: String?
    public let terminal: String
    public let cwd: String?
    public let action: String?
    public let assistant: String?
    public let tasks: [TaskItem]
    public let permissionMode: String?
    public init(id: String, title: String, status: SessionStatus, lastActivity: Date,
                prompt: String? = nil, terminal: String = "cmux",
                cwd: String? = nil, action: String? = nil,
                assistant: String? = nil, tasks: [TaskItem] = [],
                permissionMode: String? = nil) {
        self.id = id; self.title = title; self.status = status; self.lastActivity = lastActivity
        self.prompt = prompt; self.terminal = terminal; self.cwd = cwd; self.action = action
        self.assistant = assistant; self.tasks = tasks; self.permissionMode = permissionMode
    }
}

public struct IslandDisplay: Equatable, Sendable {
    public let hidden: Bool
    public let pillSymbol: String
    public let pillCount: Int
    public let rows: [IslandRow]
    public init(hidden: Bool, pillSymbol: String, pillCount: Int, rows: [IslandRow]) {
        self.hidden = hidden; self.pillSymbol = pillSymbol; self.pillCount = pillCount; self.rows = rows
    }

    /// Pure mapping from sessions to the floating-island display model. Sorts by recency.
    public static func from(_ sessions: [Session]) -> IslandDisplay {
        let sorted = sessions.sorted { $0.lastActivity > $1.lastActivity }
        return IslandDisplay(
            hidden: sorted.isEmpty,
            pillSymbol: IconState.aggregate(sorted).symbolName,
            pillCount: sorted.count,
            rows: sorted.map { IslandRow(id: $0.id, title: $0.title, status: $0.status, lastActivity: $0.lastActivity,
                                         prompt: $0.lastPrompt, terminal: $0.tmux != nil ? "tmux" : "cmux",
                                         cwd: $0.cwd, action: $0.lastAction,
                                         assistant: $0.lastAssistant, tasks: $0.tasks,
                                         permissionMode: $0.permissionMode) })
    }
}
