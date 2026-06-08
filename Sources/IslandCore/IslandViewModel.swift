import Foundation

public struct IslandRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: SessionStatus
    public let lastActivity: Date
    public let prompt: String?
    public let terminal: String
    public init(id: String, title: String, status: SessionStatus, lastActivity: Date,
                prompt: String? = nil, terminal: String = "cmux") {
        self.id = id; self.title = title; self.status = status; self.lastActivity = lastActivity
        self.prompt = prompt; self.terminal = terminal
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
                                         prompt: $0.lastPrompt, terminal: $0.tmux != nil ? "tmux" : "cmux") })
    }
}
