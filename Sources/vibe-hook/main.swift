import Foundation
import IslandCore

// vibe-hook: invoked by Claude Code per event. Reads JSON on stdin, enriches with
// cmux env + tmux context, sends one JSON line to the island socket. ALWAYS exits 0.

func resolveTmux(env: [String: String], runner: CommandRunner) -> TmuxContext? {
    guard env["TMUX"] != nil else { return nil }
    let cmd = Command(executable: "tmux",
                      arguments: ["display-message", "-p", "#{pane_id}\t#{window_index}\t#{session_name}"],
                      environment: [:])
    guard let out = try? runner.run(cmd) else { return nil }
    let parts = out.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 3 else { return nil }
    return TmuxContext(pane: parts[0], window: parts[1], session: parts[2])
}

let env = ProcessInfo.processInfo.environment
let stdin = FileHandle.standardInput.readDataToEndOfFile()
let tmux = resolveTmux(env: env, runner: ProcessRunner())

if let msg = HookMessage.build(stdin: stdin, env: env, tmux: tmux),
   let line = try? JSONEncoder().encode(msg) {
    var payload = line
    payload.append(0x0A) // newline-delimited
    UnixSocketClient.send(payload, toPath: SocketPath.resolve(env: env))
}

exit(0)
