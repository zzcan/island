public struct NotificationRequest: Equatable, Sendable {
    public let sessionId: String
    public let title: String
    public let body: String
    public init(sessionId: String, title: String, body: String) {
        self.sessionId = sessionId; self.title = title; self.body = body
    }
}
