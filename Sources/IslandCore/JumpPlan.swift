public enum JumpPlan {
    /// CLI commands to focus the right session: cmux workspace, then tmux pane, or —
    /// when neither multiplexer is involved — an `osascript` call that drives the GUI
    /// terminal (iTerm2 / Terminal.app) to its exact window+tab.
    ///
    /// Ghostty has no scripting interface, so it is NOT represented here; the caller
    /// raises its window via Accessibility instead (see `session.terminal.kind == .ghostty`).
    /// App activation (NSWorkspace) is handled by the caller, not here.
    public static func commands(for session: Session) -> [Command] {
        var cmds: [Command] = []
        if let cmux = session.cmux {
            // Real cmux CLI syntax (verified against cmux 1.x):
            //   cmux select-workspace --workspace <id|ref|index>
            cmds.append(Command(executable: "cmux",
                                arguments: ["select-workspace", "--workspace", cmux.workspaceId],
                                environment: ["CMUX_SOCKET_PATH": cmux.socketPath]))
        }
        if let tmux = session.tmux {
            cmds.append(Command(executable: "tmux",
                                arguments: ["select-window", "-t", "\(tmux.session):\(tmux.window)"],
                                environment: [:]))
            cmds.append(Command(executable: "tmux",
                                arguments: ["select-pane", "-t", tmux.pane],
                                environment: [:]))
        }

        // GUI terminal jump only when not inside a multiplexer (the env we'd need is
        // scrubbed there, and the multiplexer jump already does the right thing).
        if session.cmux == nil, session.tmux == nil, let term = session.terminal {
            switch term.kind {
            case .iterm:
                if let guid = term.itermSessionId {
                    cmds.append(Command(executable: "osascript",
                                        arguments: ["-e", itermScript(sessionGUID: guid)],
                                        environment: [:]))
                }
            case .appleTerminal:
                if let tty = term.tty {
                    cmds.append(Command(executable: "osascript",
                                        arguments: ["-e", appleTerminalScript(tty: tty)],
                                        environment: [:]))
                }
            case .ghostty:
                break // raised by the app via Accessibility, not a CLI command
            }
        }
        return cmds
    }

    /// AppleScript that selects the iTerm2 session whose `id` matches the GUID, then
    /// brings its window/tab forward and activates iTerm2.
    public static func itermScript(sessionGUID: String) -> String {
        """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if id of s is "\(sessionGUID)" then
                  select w
                  select t
                  select s
                  activate
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
    }

    /// AppleScript that selects the Terminal.app tab whose `tty` matches, then raises
    /// its window and activates Terminal.
    public static func appleTerminalScript(tty: String) -> String {
        """
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(tty)" then
                set selected tab of w to t
                set frontmost of w to true
                activate
                return
              end if
            end repeat
          end repeat
        end tell
        """
    }
}
