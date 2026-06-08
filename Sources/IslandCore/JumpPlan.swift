public enum JumpPlan {
    /// CLI commands to focus the right cmux workspace and (if present) tmux pane.
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
        return cmds
    }
}
