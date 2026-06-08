import Foundation

public enum SocketPath {
    /// ~/Library/Application Support/island/run.sock — overridable via ISLAND_SOCKET.
    public static func resolve(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = env["ISLAND_SOCKET"], !override.isEmpty { return override }
        let home = env["HOME"] ?? NSHomeDirectory()
        return "\(home)/Library/Application Support/island/run.sock"
    }
}
