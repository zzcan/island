import Foundation
import IslandCore

// vibe-hook: invoked by Claude Code or Codex per event. Reads JSON on stdin, enriches with
// cmux env + tmux context, sends one JSON line to the island socket. ALWAYS exits 0.

/// Controlling tty of `pid` via `ps`, read from the process table — independent of
/// whether any fd is a tty. Returns ("/dev/ttysNNN" or nil, parent pid).
func ttyViaPS(pid: Int32) -> (tty: String?, ppid: Int32?) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-o", "tty=", "-o", "ppid=", "-p", String(pid)]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    guard (try? p.run()) != nil else { return (nil, nil) }
    p.waitUntilExit()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let fields = out.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    guard fields.count >= 2 else { return (nil, nil) }
    let ttyField = fields[0]
    let ppid = Int32(fields[1])
    let tty: String? = (ttyField == "??" || ttyField == "?")
        ? nil : (ttyField.hasPrefix("/dev/") ? ttyField : "/dev/\(ttyField)")
    return (tty, ppid)
}

/// The controlling terminal device of the session (e.g. "/dev/ttys003").
///
/// The hook is spawned by the CLI (Claude/Codex) with all three std fds piped, and —
/// critically — usually WITHOUT its own controlling terminal, so `isatty`/`/dev/tty`
/// both fail. The session's tty lives on an ancestor (the CLI / shell), so we walk the
/// process tree and return the first ancestor that has one. This is the same device the
/// GUI terminal reports as its tab's tty.
func resolveTTY() -> String? {
    // Fast paths: a tty directly on our fds, or a controlling /dev/tty if we have one.
    for fd in Int32(0)...2 {
        if isatty(fd) != 0, let name = ttyname(fd) { return String(cString: name) }
    }
    let fd = open("/dev/tty", O_RDONLY | O_NOCTTY)
    if fd >= 0 {
        defer { close(fd) }
        if let name = ttyname(fd) { return String(cString: name) }
    }
    // Fallback: read the controlling tty from the process table, walking up to the CLI.
    var pid = getpid()
    for _ in 0..<8 {
        let (tty, ppid) = ttyViaPS(pid: pid)
        if let tty { return tty }
        guard let ppid, ppid > 1 else { break }
        pid = ppid
    }
    return nil
}

/// Handles a PermissionRequest hook invocation. For ExitPlanMode, sends the plan to the
/// island and blocks for the user's decision, then prints Claude's expected stdout JSON.
/// Prints nothing (→ Claude's own terminal prompt) for unhandled tools, missing data, or
/// when the island isn't reachable / times out.
func handlePermissionRequest(stdin: Data, input: AgentHookInput?, env: [String: String]) {
    guard let input, let sid = input.session_id, !sid.isEmpty else { return }
    guard input.tool_name == "ExitPlanMode",
          let plan = input.tool_input?.plan, !plan.isEmpty else { return }

    let requestId = UUID().uuidString
    let title = input.cwd.map { ($0 as NSString).lastPathComponent }
    let msg = HookMessage(event: .permissionRequest, sessionId: sid, cwd: input.cwd, title: title,
                          message: nil, cmux: nil, tmux: nil,
                          requestId: requestId, toolName: input.tool_name, plan: plan)
    guard let line = try? JSONEncoder().encode(msg) else { return }
    var payload = line
    payload.append(0x0A)

    // Block until the app returns the user's decision (or times out → terminal prompt).
    guard let replyData = UnixSocketClient.request(payload, toPath: SocketPath.resolve(env: env),
                                                   replyTimeoutMs: 585_000),
          let reply = try? JSONDecoder().decode(PermissionReply.self, from: replyData),
          let out = PlanHookOutput.json(reply: reply) else {
        return
    }
    print(out)
}

/// Ghostty has no scripting interface, so we stamp its window with a unique title via an
/// OSC 2 escape written to the session's tty device. The app later finds that window by
/// title through Accessibility. Best-effort; no-ops if the tty isn't known/writable.
func emitGhosttyTitle(_ title: String, ttyPath: String?) {
    guard let ttyPath else { return }
    let osc = "\u{1B}]2;\(title)\u{07}"
    guard let data = osc.data(using: .utf8) else { return }
    let fd = open(ttyPath, O_WRONLY | O_NOCTTY)
    guard fd >= 0 else { return }
    defer { close(fd) }
    data.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
}

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

/// Load task items from ~/.claude/tasks/<session_id>/ — returns nil if dir missing or empty.
func loadTasks(sessionId: String, home: String) -> [TaskItem]? {
    let dir = "\(home)/.claude/tasks/\(sessionId)"
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
    var items: [TaskItem] = []
    for name in contents {
        // Skip dotfiles (.lock, .highwatermark, etc.)
        guard !name.hasPrefix("."), name.hasSuffix(".json") else { continue }
        let path = "\(dir)/\(name)"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
        if let item = try? JSONDecoder().decode(TaskItem.self, from: data) {
            items.append(item)
        }
    }
    guard !items.isEmpty else { return nil }
    // Sort numerically by id, fallback to lexicographic
    items.sort { (Int($0.id) ?? 0) < (Int($1.id) ?? 0) }
    return items
}

/// Read the last assistant text + model id from a JSONL transcript file.
/// Reads the last 128 KB to avoid loading giant files; drops the first partial line.
func loadTranscript(path: String) -> (text: String?, model: String?) {
    guard FileManager.default.fileExists(atPath: path) else { return (nil, nil) }
    let url = URL(fileURLWithPath: path)
    guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, nil) }
    defer { try? handle.close() }

    let tailSize: UInt64 = 128 * 1024
    let fileSize = (try? handle.seekToEnd()) ?? 0

    let jsonl: String
    if fileSize <= tailSize {
        // Small file — read all
        try? handle.seek(toOffset: 0)
        guard let data = try? handle.readToEnd(), let s = String(data: data, encoding: .utf8) else { return (nil, nil) }
        jsonl = s
    } else {
        // Large file — tail last 128 KB, drop first partial line
        let offset = fileSize - tailSize
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), let s = String(data: data, encoding: .utf8) else { return (nil, nil) }
        // Drop everything up to (and including) the first newline, which may be partial
        if let newlineRange = s.range(of: "\n") {
            jsonl = String(s[s.index(after: newlineRange.lowerBound)...])
        } else {
            jsonl = s
        }
    }

    return TranscriptParser.latest(jsonl: jsonl)
}

let env = ProcessInfo.processInfo.environment
let stdin = FileHandle.standardInput.readDataToEndOfFile()
let tmux = resolveTmux(env: env, runner: ProcessRunner())
let arguments = CommandLine.arguments
let provider: AgentProvider = {
    guard let idx = arguments.firstIndex(of: "--provider"), arguments.indices.contains(idx + 1),
          let parsed = AgentProvider(rawValue: arguments[idx + 1]) else { return .claude }
    return parsed
}()

// Decode hook input to get session_id and transcript_path for enrichment
let hookInput = try? AgentHookInput.decode(stdin)
let home = env["HOME"] ?? NSHomeDirectory()

// Resolve jump context before dispatching PermissionRequest: Codex approvals are sent
// as ordinary needs-input notifications, so their rows must still jump to the terminal.
let resolvedTTY = resolveTTY()
let terminal: TerminalContext? = hookInput?.session_id.flatMap { sid in
    TerminalDetect.detect(env: env, cwd: hookInput?.cwd, sessionId: sid, tty: resolvedTTY)
}
if let term = terminal, term.kind == .ghostty, let title = term.ghosttyTitle {
    emitGhosttyTitle(title, ttyPath: resolvedTTY)
}

// PermissionRequest: interactive approval. We currently own only ExitPlanMode (plan
// review) — block on the island for the user's decision and print Claude's expected
// stdout. Anything we don't handle prints nothing → Claude shows its own terminal prompt.
if hookInput?.hook_event_name == "PermissionRequest" {
    if provider == .codex {
        // Notification only: send and exit with no stdout so Codex immediately shows
        // its native approval prompt. Island never becomes an approval bottleneck.
        if let input = hookInput,
           let msg = HookMessage.codexPermissionNotification(input: input, env: env,
                                                              tmux: tmux, terminal: terminal),
           let line = try? JSONEncoder().encode(msg) {
            var payload = line
            payload.append(0x0A)
            UnixSocketClient.send(payload, toPath: SocketPath.resolve(env: env))
        }
    } else {
        handlePermissionRequest(stdin: stdin, input: hookInput, env: env)
    }
    exit(0)
}

// Load tasks if session_id is available
let tasks: [TaskItem]? = provider == .claude
    ? hookInput?.session_id.flatMap { loadTasks(sessionId: $0, home: home) }
    : nil

// Claude currently needs transcript enrichment. Codex provides stable top-level model
// and Stop.last_assistant_message fields, and its transcript format is explicitly unstable.
let transcript: (text: String?, model: String?) =
    provider == .claude
        ? (hookInput?.transcript_path.map { loadTranscript(path: $0) } ?? (text: nil, model: nil))
        : (text: nil, model: nil)

if let msg = HookMessage.build(stdin: stdin, env: env, tmux: tmux, terminal: terminal,
                               assistantText: transcript.text, tasks: tasks,
                               model: transcript.model, provider: provider),
   let line = try? JSONEncoder().encode(msg) {
    var payload = line
    payload.append(0x0A) // newline-delimited
    UnixSocketClient.send(payload, toPath: SocketPath.resolve(env: env))
}

exit(0)
