import Foundation

public struct CmuxContext: Codable, Equatable, Sendable {
    public let workspaceId: String
    public let surfaceId: String?
    public let socketPath: String
    public init(workspaceId: String, surfaceId: String?, socketPath: String) {
        self.workspaceId = workspaceId; self.surfaceId = surfaceId; self.socketPath = socketPath
    }
}

public struct TmuxContext: Codable, Equatable, Sendable {
    public let pane: String
    public let window: String
    public let session: String
    public init(pane: String, window: String, session: String) {
        self.pane = pane; self.window = window; self.session = session
    }
}
