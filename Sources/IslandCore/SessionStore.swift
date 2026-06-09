import Foundation

/// Pure in-memory state machine. No UI, no I/O. Not thread-safe by itself —
/// callers (AppModel) confine it to the main actor.
public final class SessionStore {
    public private(set) var sessions: [String: Session] = [:]

    public init() {}

    public var iconState: IconState {
        IconState.aggregate(Array(sessions.values))
    }

    /// Applies a message and returns a NotificationRequest when the user should be alerted.
    @discardableResult
    public func apply(_ m: HookMessage, now: Date) -> NotificationRequest? {
        if m.event == .sessionEnd {
            sessions[m.sessionId] = nil
            return nil
        }

        var s = sessions[m.sessionId] ?? Session(
            id: m.sessionId, title: m.title ?? m.sessionId, cwd: m.cwd, status: .idle,
            cmux: nil, tmux: nil, lastActivity: now)

        // Refresh fields the message carries.
        if let title = m.title { s.title = title }
        if let cwd = m.cwd { s.cwd = cwd }
        if let cmux = m.cmux { s.cmux = cmux }
        if let tmux = m.tmux { s.tmux = tmux }
        if let p = m.prompt { s.lastPrompt = p }
        if let a = m.action { s.lastAction = a }
        s.lastActivity = now

        var request: NotificationRequest? = nil
        switch m.event {
        case .sessionStart:
            s.status = .idle
        case .userPromptSubmit:
            s.status = .working
        case .notification:
            s.status = .needsInput
            request = NotificationRequest(sessionId: s.id, title: s.title,
                                          body: m.message ?? "Needs your input")
        case .stop:
            s.status = .done
            request = NotificationRequest(sessionId: s.id, title: s.title, body: "Done")
        case .postToolUse:
            s.status = .working
        case .sessionEnd:
            break // handled above
        }

        sessions[m.sessionId] = s
        return request
    }

    public func prune(olderThan interval: TimeInterval, now: Date) {
        sessions = sessions.filter { now.timeIntervalSince($0.value.lastActivity) <= interval }
    }

    public func clearAll() {
        sessions.removeAll()
    }
}
