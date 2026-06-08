import Foundation
import IslandCore

/// Main-actor bridge between the pure SessionStore and SwiftUI. Owns the store,
/// the notifier, and the jumper; wires socket messages -> store -> UI/notifications.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var icon: IconState = .idle
    @Published private(set) var display: IslandDisplay = .from([])
    @Published private(set) var eventTick: Int = 0

    private let store = SessionStore()
    private let notifier = Notifier()
    private let jumper = Jumper()
    private var server: SocketServer?
    private var started = false

    deinit { server?.stop() }

    func start() {
        guard !started else { return }
        started = true

        store.clearAll()
        notifier.onClick = { [weak self] sid in
            Task { @MainActor in self?.jump(sessionId: sid) }
        }
        notifier.start()

        let path = SocketPath.resolve()
        let server = SocketServer(path: path) { [weak self] msg in
            Task { @MainActor in self?.handle(msg) }
        }
        do { try server.start() } catch { NSLog("island: socket start failed: \(error)") }
        self.server = server
    }

    func handle(_ msg: HookMessage) {
        let request = store.apply(msg, now: Date())
        refresh()
        if let request {
            eventTick &+= 1
            notifier.post(request)
        }
    }

    func jump(sessionId: String) {
        guard let session = store.sessions[sessionId] else { return }
        jumper.jump(to: session)
    }

    private func refresh() {
        sessions = store.sessions.values.sorted { $0.lastActivity > $1.lastActivity }
        icon = store.iconState
        display = IslandDisplay.from(Array(store.sessions.values))
    }
}
