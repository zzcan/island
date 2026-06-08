import Testing
import Foundation
@testable import IslandCore

@Suite struct JumpPlanTests {
    private func session(cmux: CmuxContext?, tmux: TmuxContext?) -> Session {
        Session(id: "s1", title: "t", cwd: nil, status: .done,
                cmux: cmux, tmux: tmux, lastActivity: Date(timeIntervalSince1970: 0))
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
}
