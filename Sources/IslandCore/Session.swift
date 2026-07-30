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
    public var terminal: TerminalContext?
    public var lastActivity: Date
    public var lastPrompt: String?
    public var lastAction: String?
    public var lastAssistant: String?
    public var tasks: [TaskItem]
    public var permissionMode: String?
    public var model: String?
    public var provider: AgentProvider

    public init(id: String, title: String, cwd: String?, status: SessionStatus,
                cmux: CmuxContext?, tmux: TmuxContext?, terminal: TerminalContext? = nil,
                lastActivity: Date,
                lastPrompt: String? = nil, lastAction: String? = nil,
                lastAssistant: String? = nil, tasks: [TaskItem] = [],
                permissionMode: String? = nil, model: String? = nil,
                provider: AgentProvider = .claude) {
        self.id = id; self.title = title; self.cwd = cwd; self.status = status
        self.cmux = cmux; self.tmux = tmux; self.terminal = terminal
        self.lastActivity = lastActivity
        self.lastPrompt = lastPrompt; self.lastAction = lastAction
        self.lastAssistant = lastAssistant; self.tasks = tasks
        self.permissionMode = permissionMode; self.model = model
        self.provider = provider
    }
}
