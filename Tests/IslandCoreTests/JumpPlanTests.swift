import Testing
import Foundation
@testable import IslandCore

@Suite struct JumpPlanTests {
    private func session(cmux: CmuxContext?, tmux: TmuxContext?,
                         terminal: TerminalContext? = nil) -> Session {
        Session(id: "s1", title: "t", cwd: nil, status: .done,
                cmux: cmux, tmux: tmux, terminal: terminal,
                lastActivity: Date(timeIntervalSince1970: 0))
    }

    @Test func noContextNoCommands() {
        #expect(JumpPlan.commands(for: session(cmux: nil, tmux: nil)) == [])
    }

    @Test func cmuxOnly() {
        let s = session(cmux: CmuxContext(workspaceId: "w1", surfaceId: nil, socketPath: "/tmp/c.sock"), tmux: nil)
        #expect(JumpPlan.commands(for: s) == [
            Command(executable: "cmux", arguments: ["select-workspace", "--workspace", "w1"],
                    environment: ["CMUX_SOCKET_PATH": "/tmp/c.sock"]),
        ])
    }

    @Test func cmuxThenTmux() {
        let s = session(
            cmux: CmuxContext(workspaceId: "w1", surfaceId: nil, socketPath: "/tmp/c.sock"),
            tmux: TmuxContext(pane: "%3", window: "1", session: "main"))
        #expect(JumpPlan.commands(for: s) == [
            Command(executable: "cmux", arguments: ["select-workspace", "--workspace", "w1"],
                    environment: ["CMUX_SOCKET_PATH": "/tmp/c.sock"]),
            Command(executable: "tmux", arguments: ["select-window", "-t", "main:1"], environment: [:]),
            Command(executable: "tmux", arguments: ["select-pane", "-t", "%3"], environment: [:]),
        ])
    }

    @Test func iterm2EmitsOsascript() {
        let s = session(cmux: nil, tmux: nil,
                        terminal: TerminalContext(kind: .iterm, itermSessionId: "GUID-9"))
        let cmds = JumpPlan.commands(for: s)
        #expect(cmds.count == 1)
        #expect(cmds.first?.executable == "osascript")
        #expect(cmds.first?.arguments.first == "-e")
        #expect(cmds.first?.arguments.last?.contains("iTerm2") == true)
        #expect(cmds.first?.arguments.last?.contains("GUID-9") == true)
    }

    @Test func appleTerminalEmitsOsascriptByTTY() {
        let s = session(cmux: nil, tmux: nil,
                        terminal: TerminalContext(kind: .appleTerminal, tty: "/dev/ttys005"))
        let cmds = JumpPlan.commands(for: s)
        #expect(cmds.count == 1)
        #expect(cmds.first?.executable == "osascript")
        #expect(cmds.first?.arguments.last?.contains("Terminal") == true)
        #expect(cmds.first?.arguments.last?.contains("/dev/ttys005") == true)
    }

    @Test func ghosttyEmitsNoCommand() {
        // Ghostty is raised via Accessibility by the app, not a CLI command.
        let s = session(cmux: nil, tmux: nil,
                        terminal: TerminalContext(kind: .ghostty, ghosttyTitle: "proj · vi:abc123"))
        #expect(JumpPlan.commands(for: s) == [])
    }

    @Test func multiplexerWinsOverTerminal() {
        // Inside cmux we don't also fire a GUI osascript jump.
        let s = session(cmux: CmuxContext(workspaceId: "w1", surfaceId: nil, socketPath: "/tmp/c.sock"),
                        tmux: nil,
                        terminal: TerminalContext(kind: .iterm, itermSessionId: "GUID-9"))
        let cmds = JumpPlan.commands(for: s)
        #expect(cmds.count == 1)
        #expect(cmds.first?.executable == "cmux")
    }
}
