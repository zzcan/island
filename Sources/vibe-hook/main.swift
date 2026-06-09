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

// Decode hook input to get session_id and transcript_path for enrichment
let hookInput = try? ClaudeHookInput.decode(stdin)
let home = env["HOME"] ?? NSHomeDirectory()

// Load tasks if session_id is available
let tasks: [TaskItem]? = hookInput?.session_id.flatMap { loadTasks(sessionId: $0, home: home) }

// Load assistant text + model id if transcript_path is available
let transcript: (text: String?, model: String?) =
    hookInput?.transcript_path.map { loadTranscript(path: $0) } ?? (text: nil, model: nil)

if let msg = HookMessage.build(stdin: stdin, env: env, tmux: tmux,
                               assistantText: transcript.text, tasks: tasks,
                               model: transcript.model),
   let line = try? JSONEncoder().encode(msg) {
    var payload = line
    payload.append(0x0A) // newline-delimited
    UnixSocketClient.send(payload, toPath: SocketPath.resolve(env: env))
}

exit(0)
