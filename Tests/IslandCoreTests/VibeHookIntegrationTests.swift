import Foundation
import Testing
@testable import IslandCore
#if canImport(Darwin)
import Darwin
#endif

@Suite(.serialized) struct VibeHookIntegrationTests {
    private struct HookRun {
        let message: HookMessage
        let stdout: Data
        let exitCode: Int32
    }

    @Test func codexStopUsesStableFieldsWithoutClaudeEnrichment() throws {
        let input = #"{"session_id":"thr_integration","cwd":"/tmp/project","hook_event_name":"Stop","model":"gpt-5.6-sol","last_assistant_message":"Done from Codex.","transcript_path":"/definitely/missing/transcript.jsonl"}"#
        let run = try runCodexHook(input)

        #expect(run.exitCode == 0)
        #expect(run.stdout.isEmpty)
        #expect(run.message.provider == .codex)
        #expect(run.message.model == "gpt-5.6-sol")
        #expect(run.message.assistantText == "Done from Codex.")
        #expect(run.message.tasks == nil)
    }

    @Test func codexPermissionNotifiesWithoutTakingApproval() throws {
        let input = #"{"session_id":"thr_approval","cwd":"/tmp/project","hook_event_name":"PermissionRequest","model":"gpt-5.6-sol","permission_mode":"default","tool_name":"Bash","tool_input":{"command":"git push","description":"Push changes to origin"}}"#
        let run = try runCodexHook(input)

        #expect(run.exitCode == 0)
        #expect(run.stdout.isEmpty, "no hook decision means Codex keeps its native approval UI")
        #expect(run.message.event == .notification)
        #expect(run.message.message == "Push changes to origin")
        #expect(run.message.action == "Bash git push")
    }

    private func runCodexHook(_ input: String) throws -> HookRun {
        let fm = FileManager.default
        let hook = fm.currentDirectoryPath + "/.build/debug/vibe-hook"
        #expect(fm.isExecutableFile(atPath: hook), "swift test must build the vibe-hook target")

        let suffix = UUID().uuidString.prefix(8)
        let socketPath = "/tmp/island-hook-\(getpid())-\(suffix).sock"
        let listener = try makeListener(path: socketPath)
        defer { close(listener); unlink(socketPath) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: hook)
        process.arguments = ["--provider", "codex"]
        var environment = ProcessInfo.processInfo.environment
        environment["ISLAND_SOCKET"] = socketPath
        process.environment = environment
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()

        var pollState = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
        guard poll(&pollState, 1, 2_000) > 0 else {
            throw POSIXError(.ETIMEDOUT)
        }
        let client = accept(listener, nil, nil)
        guard client >= 0 else { throw POSIXError(.ECONNABORTED) }
        defer { close(client) }

        var payload = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 { break }
            if let newline = buffer[0..<count].firstIndex(of: 0x0A) {
                payload.append(contentsOf: buffer[0..<newline])
                break
            }
            payload.append(contentsOf: buffer[0..<count])
        }

        return HookRun(message: try JSONDecoder().decode(HookMessage.self, from: payload),
                       stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
                       exitCode: process.terminationStatus)
    }

    private func makeListener(path: String) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EADDRNOTAVAIL) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw POSIXError(.ENAMETOOLONG)
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: bytes.count + 1) { destination in
                for (index, byte) in bytes.enumerated() { destination[index] = CChar(bitPattern: byte) }
                destination[bytes.count] = 0
            }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        guard result == 0, listen(fd, 1) == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        return fd
    }
}
