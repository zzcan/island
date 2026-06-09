import Foundation

public struct TaskItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let subject: String
    public let status: String   // "pending" | "in_progress" | "completed"
    public init(id: String, subject: String, status: String) {
        self.id = id; self.subject = subject; self.status = status
    }
}

public struct TaskSummary: Equatable, Sendable {
    public let completed: Int, inProgress: Int, pending: Int
    public static func from(_ tasks: [TaskItem]) -> TaskSummary {
        TaskSummary(
            completed: tasks.filter { $0.status == "completed" }.count,
            inProgress: tasks.filter { $0.status == "in_progress" }.count,
            pending: tasks.filter { $0.status == "pending" }.count)
    }
    public init(completed: Int, inProgress: Int, pending: Int) {
        self.completed = completed; self.inProgress = inProgress; self.pending = pending
    }
}
