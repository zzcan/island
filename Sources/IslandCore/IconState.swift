public enum IconState: String, Equatable, Sendable {
    case idle, busy, attention

    public static func aggregate(_ sessions: [Session]) -> IconState {
        if sessions.contains(where: { $0.status == .needsInput || $0.status == .done }) {
            return .attention
        }
        if sessions.contains(where: { $0.status == .working }) {
            return .busy
        }
        return .idle
    }
}
