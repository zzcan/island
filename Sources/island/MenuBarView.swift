import SwiftUI
import IslandCore

struct MenuBarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.sessions.isEmpty {
            Text("No active sessions")
        } else {
            ForEach(model.sessions) { session in
                Button(action: { model.jump(sessionId: session.id) }) {
                    Text("\(statusEmoji(session.status))  \(session.title)")
                }
            }
        }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
    }

    private func statusEmoji(_ s: SessionStatus) -> String {
        switch s {
        case .idle: return "⚪️"
        case .working: return "🟡"
        case .needsInput: return "🔵"
        case .done: return "🟢"
        }
    }
}
