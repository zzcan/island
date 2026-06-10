import SwiftUI
import IslandCore

/// The menu-bar dropdown: a quick session switcher. Each row shows the status-coloured
/// pixel sprite (matching the bar icon + panel avatars), the project name, and a
/// "status · elapsed" secondary line. Rows are sorted by urgency (needs-input first) so
/// the session wanting attention is on top, and the first nine get ⌘1–9 to jump.
struct MenuBarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let sessions = sortedSessions
        if sessions.isEmpty {
            Text("暂无活动会话")
        } else {
            Text("AI 会话 (\(sessions.count))")   // disabled header
            Divider()
            ForEach(Array(sessions.prefix(9).enumerated()), id: \.element.id) { idx, session in
                sessionButton(session, shortcut: idx + 1)
            }
            // Any sessions beyond the first nine still get a row, just without a shortcut.
            ForEach(Array(sessions.dropFirst(9)), id: \.id) { session in
                sessionButton(session, shortcut: nil)
            }
        }
        Divider()
        Button("设置…") { model.openSettings() }
        Button("退出") { NSApplication.shared.terminate(nil) }
    }

    @ViewBuilder
    private func sessionButton(_ session: Session, shortcut: Int?) -> some View {
        let button = Button {
            model.jump(sessionId: session.id)
        } label: {
            Label {
                Text("\(session.title)   \(statusText(session.status)) · \(elapsed(session.lastActivity))")
            } icon: {
                Image(nsImage: MenuBarIcon.image(for: [session.status]))
            }
        }
        if let shortcut, let key = KeyEquivalent(exactly: shortcut) {
            button.keyboardShortcut(key, modifiers: .command)
        } else {
            button
        }
    }

    /// needs-input → working → done → idle; ties broken by most-recent activity.
    private var sortedSessions: [Session] {
        model.sessions.sorted {
            let a = rank($0.status), b = rank($1.status)
            if a != b { return a < b }
            return $0.lastActivity > $1.lastActivity
        }
    }

    private func rank(_ s: SessionStatus) -> Int {
        switch s {
        case .needsInput: return 0
        case .working:    return 1
        case .done:       return 2
        case .idle:       return 3
        }
    }

    private func statusText(_ s: SessionStatus) -> String {
        switch s {
        case .idle:       return "空闲"
        case .working:    return "运行中"
        case .needsInput: return "需处理"
        case .done:       return "已完成"
        }
    }

    private func elapsed(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(s / 60)分钟" }
        if s < 86400 { return "\(s / 3600)小时" }
        return "\(s / 86400)天"
    }
}

private extension KeyEquivalent {
    /// 1...9 → the matching digit key; nil otherwise.
    init?(exactly n: Int) {
        guard (1...9).contains(n) else { return nil }
        self = KeyEquivalent(Character("\(n)"))
    }
}
