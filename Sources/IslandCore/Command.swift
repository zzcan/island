import Foundation

public struct Command: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public init(executable: String, arguments: [String], environment: [String: String]) {
        self.executable = executable; self.arguments = arguments; self.environment = environment
    }
}

public protocol CommandRunner: Sendable {
    /// Runs the command, returning trimmed stdout. Throws on launch/non-zero exit.
    @discardableResult
    func run(_ command: Command) throws -> String
}
