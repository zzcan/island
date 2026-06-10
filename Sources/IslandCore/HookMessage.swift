import Foundation

/// Our own wire format: vibe-hook sends one of these as a single JSON line.
public struct HookMessage: Codable, Equatable, Sendable {
    public let event: IslandEvent
    public let sessionId: String
    public let cwd: String?
    public let title: String?
    public let message: String?
    public let cmux: CmuxContext?
    public let tmux: TmuxContext?
    public let terminal: TerminalContext?
    public let prompt: String?
    public let action: String?
    public let assistantText: String?
    public let tasks: [TaskItem]?
    public let permissionMode: String?
    public let model: String?
    // Interactive approval (permissionRequest) only:
    public let requestId: String?   // correlates the reply back to the blocked hook
    public let toolName: String?    // e.g. "ExitPlanMode"
    public let plan: String?        // the plan markdown to review

    public init(event: IslandEvent, sessionId: String, cwd: String?, title: String?,
                message: String?, cmux: CmuxContext?, tmux: TmuxContext?,
                terminal: TerminalContext? = nil,
                prompt: String? = nil, action: String? = nil,
                assistantText: String? = nil, tasks: [TaskItem]? = nil,
                permissionMode: String? = nil, model: String? = nil,
                requestId: String? = nil, toolName: String? = nil, plan: String? = nil) {
        self.event = event; self.sessionId = sessionId; self.cwd = cwd; self.title = title
        self.message = message; self.cmux = cmux; self.tmux = tmux; self.terminal = terminal
        self.prompt = prompt
        self.action = action; self.assistantText = assistantText; self.tasks = tasks
        self.permissionMode = permissionMode; self.model = model
        self.requestId = requestId; self.toolName = toolName; self.plan = plan
    }

    /// Pure builder. `tmux`/`terminal` are passed in (the caller resolves them via
    /// side-effecting CLI/tty calls) to keep this function testable. Returns nil if the
    /// event is unsupported or sessionId missing.
    public static func build(stdin: Data, env: [String: String], tmux: TmuxContext?,
                             terminal: TerminalContext? = nil,
                             assistantText: String? = nil, tasks: [TaskItem]? = nil,
                             model: String? = nil) -> HookMessage? {
        guard let input = try? ClaudeHookInput.decode(stdin) else { return nil }
        guard let name = input.hook_event_name, let event = IslandEvent(claudeName: name) else { return nil }
        guard let sid = input.session_id, !sid.isEmpty else { return nil }

        var cmux: CmuxContext? = nil
        if let ws = env["CMUX_WORKSPACE_ID"], let sock = env["CMUX_SOCKET_PATH"] {
            cmux = CmuxContext(workspaceId: ws, surfaceId: env["CMUX_SURFACE_ID"], socketPath: sock)
        }

        let title = input.cwd.map { ($0 as NSString).lastPathComponent }

        var action: String? = nil
        if event == .postToolUse, let tool = input.tool_name {
            let arg = input.tool_input?.file_path ?? input.tool_input?.command
                      ?? input.tool_input?.pattern ?? input.tool_input?.path
            if let arg, !arg.isEmpty {
                action = "\(tool) \(HookMessage.shortenArg(arg))"
            } else {
                action = tool
            }
        }

        return HookMessage(event: event, sessionId: sid, cwd: input.cwd, title: title,
                           message: input.message, cmux: cmux, tmux: tmux, terminal: terminal,
                           prompt: input.prompt,
                           action: action, assistantText: assistantText, tasks: tasks,
                           permissionMode: input.permission_mode, model: model)
    }

    /// If the string contains "/", returns the last 2 path components joined by "/".
    /// Otherwise returns the string truncated to 40 characters.
    public static func shortenArg(_ s: String) -> String {
        if s.contains("/") {
            let components = s.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            if components.count >= 2 {
                return "\(components[components.count - 2])/\(components[components.count - 1])"
            } else if let last = components.last {
                return last
            }
            return s
        } else {
            if s.count <= 40 { return s }
            return String(s.prefix(40))
        }
    }
}
