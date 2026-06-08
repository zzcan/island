import Foundation

public struct ProcessError: Error { public let code: Int32; public let stderr: String }

/// Real CommandRunner. Resolves the executable via /usr/bin/env so PATH is honored.
public struct ProcessRunner: CommandRunner, Sendable {
    public init() {}

    @discardableResult
    public func run(_ command: Command) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [command.executable] + command.arguments
        var env = ProcessInfo.processInfo.environment
        for (k, v) in command.environment { env[k] = v }
        proc.environment = env

        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out; proc.standardError = err
        try proc.run()
        proc.waitUntilExit()

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        if proc.terminationStatus != 0 {
            throw ProcessError(code: proc.terminationStatus,
                               stderr: String(decoding: errData, as: UTF8.self))
        }
        return String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
