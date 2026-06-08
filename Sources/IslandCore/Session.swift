import Foundation

public enum SessionStatus: String, Codable, Equatable, Sendable {
    case idle, working, needsInput, done
}

public struct Session: Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var cwd: String?
    public var status: SessionStatus
    public var cmux: CmuxContext?
    public var tmux: TmuxContext?
    public var lastActivity: Date

    public init(id: String, title: String, cwd: String?, status: SessionStatus,
                cmux: CmuxContext?, tmux: TmuxContext?, lastActivity: Date) {
        self.id = id; self.title = title; self.cwd = cwd; self.status = status
        self.cmux = cmux; self.tmux = tmux; self.lastActivity = lastActivity
    }
}
