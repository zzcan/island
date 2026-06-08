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

extension IconState {
    /// SF Symbol name for the menu bar.
    public var symbolName: String {
        switch self {
        case .idle: return "circle"
        case .busy: return "circle.dotted"
        case .attention: return "bell.badge.fill"
        }
    }
}
