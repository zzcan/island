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
    public let prompt: String?

    public init(event: IslandEvent, sessionId: String, cwd: String?, title: String?,
                message: String?, cmux: CmuxContext?, tmux: TmuxContext?,
                prompt: String? = nil) {
        self.event = event; self.sessionId = sessionId; self.cwd = cwd; self.title = title
        self.message = message; self.cmux = cmux; self.tmux = tmux; self.prompt = prompt
    }

    /// Pure builder. `tmux` is passed in (the caller resolves it via a side-effecting CLI call)
    /// to keep this function testable. Returns nil if the event is unsupported or sessionId missing.
    public static func build(stdin: Data, env: [String: String], tmux: TmuxContext?) -> HookMessage? {
        guard let input = try? ClaudeHookInput.decode(stdin) else { return nil }
        guard let name = input.hook_event_name, let event = IslandEvent(claudeName: name) else { return nil }
        guard let sid = input.session_id, !sid.isEmpty else { return nil }

        var cmux: CmuxContext? = nil
        if let ws = env["CMUX_WORKSPACE_ID"], let sock = env["CMUX_SOCKET_PATH"] {
            cmux = CmuxContext(workspaceId: ws, surfaceId: env["CMUX_SURFACE_ID"], socketPath: sock)
        }

        let title = input.cwd.map { ($0 as NSString).lastPathComponent }

        return HookMessage(event: event, sessionId: sid, cwd: input.cwd, title: title,
                           message: input.message, cmux: cmux, tmux: tmux, prompt: input.prompt)
    }
}
