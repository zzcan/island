import Foundation

public struct CmuxContext: Codable, Equatable, Sendable {
    public let workspaceId: String
    public let surfaceId: String?
    public let socketPath: String
    public init(workspaceId: String, surfaceId: String?, socketPath: String) {
        self.workspaceId = workspaceId; self.surfaceId = surfaceId; self.socketPath = socketPath
    }
}

public struct TmuxContext: Codable, Equatable, Sendable {
    public let pane: String
    public let window: String
    public let session: String
    public init(pane: String, window: String, session: String) {
        self.pane = pane; self.window = window; self.session = session
    }
}

/// Identifies the GUI terminal hosting a session so we can jump to the exact
/// window/tab. Only set when the session is NOT inside tmux/cmux (those win and
/// scrub the env we'd need anyway).
public struct TerminalContext: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case iterm          // iTerm2 — jump by session GUID via AppleScript
        case appleTerminal  // Terminal.app — jump by tty via AppleScript
        case ghostty        // Ghostty — no scripting; jump by window title via Accessibility
    }
    public let kind: Kind
    public let itermSessionId: String?   // iTerm2 session GUID (ITERM_SESSION_ID after ':')
    public let tty: String?              // Apple Terminal: matches `tty of tab`
    public let ghosttyTitle: String?     // Ghostty: unique window title we set via OSC 2

    public init(kind: Kind, itermSessionId: String? = nil, tty: String? = nil,
                ghosttyTitle: String? = nil) {
        self.kind = kind; self.itermSessionId = itermSessionId
        self.tty = tty; self.ghosttyTitle = ghosttyTitle
    }
}

/// Pure classification of the host terminal from environment + resolved tty.
public enum TerminalDetect {
    /// A stable, human-ish window title we ask Ghostty to display (via OSC 2) so the
    /// app can find that exact window later through Accessibility. Stable per session
    /// so re-jumps keep working.
    public static func ghosttyTitle(cwd: String?, sessionId: String) -> String {
        let base = cwd.map { ($0 as NSString).lastPathComponent } ?? "session"
        return "\(base) · vi:\(sessionId.prefix(6))"
    }

    public static func detect(env: [String: String], cwd: String?, sessionId: String,
                              tty: String?) -> TerminalContext? {
        // Inside a multiplexer the GUI env is unreliable (and tmux/cmux jumps win),
        // so don't classify a GUI terminal — OSC titles would land in the wrong place.
        if env["TMUX"] != nil { return nil }

        // iTerm2 exports ITERM_SESSION_ID = "w0t2p0:GUID"; the GUID is the AppleScript id.
        if let iterm = env["ITERM_SESSION_ID"],
           let guid = iterm.split(separator: ":").last.map(String.init), !guid.isEmpty {
            return TerminalContext(kind: .iterm, itermSessionId: guid)
        }
        let prog = env["TERM_PROGRAM"]
        if prog == "Apple_Terminal" {
            return TerminalContext(kind: .appleTerminal, tty: tty)
        }
        if prog == "ghostty" || env["TERM"] == "xterm-ghostty" {
            return TerminalContext(kind: .ghostty,
                                   ghosttyTitle: ghosttyTitle(cwd: cwd, sessionId: sessionId))
        }
        return nil
    }
}
