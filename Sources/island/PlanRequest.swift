import Foundation

/// A plan (ExitPlanMode) awaiting the user's review in the island. The blocked hook is
/// parked on its socket connection until `AppModel.resolvePlan` answers with the user's
/// decision (identified by `id`, the hook's requestId).
struct PlanRequest: Identifiable, Equatable {
    let id: String          // requestId
    let sessionId: String
    let title: String       // project name
    let cwd: String?
    let plan: String        // markdown

    static func == (a: PlanRequest, b: PlanRequest) -> Bool { a.id == b.id }
}
