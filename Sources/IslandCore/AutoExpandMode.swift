/// Policy for event-driven auto-expansion of the floating island panel.
/// Raw values are persisted in UserDefaults (s.autoExpandMode) — keep them stable.
public enum AutoExpandMode: Int, Sendable {
    /// Every notifying event flashes the panel open (legacy behaviour).
    case all = 0
    /// Only events that need the user: approval (needsInput) and plan review.
    case actionable = 1
    /// Events never auto-expand; hover proximity still works.
    case never = 2

    /// Whether an event leaving the session in `status` should flash the panel open.
    public func shouldExpand(for status: SessionStatus) -> Bool {
        switch self {
        case .all: return status == .needsInput || status == .done
        case .actionable: return status == .needsInput
        case .never: return false
        }
    }

    /// Whether an incoming plan-review request should flash the panel open.
    /// (The pendingPlan pin keeps the panel open regardless — this only governs
    /// the eventTick flash.)
    public var expandsForPlanReview: Bool { self != .never }
}
