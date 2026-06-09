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
    @Published private(set) var usage: Usage?

    private let store = SessionStore()
    private let notifier = Notifier()
    private let jumper = Jumper()
    private var server: SocketServer?
    private var started = false
    private var pruneTimer: Timer?
    private var usageTimer: Timer?

    /// A done/idle session whose lastActivity is older than this is treated as
    /// residual (its process likely died without firing SessionEnd) and pruned.
    /// Active sessions (working / needsInput) are kept regardless of age — see
    /// SessionStore.prune. Self-healing: a pruned session that is actually alive
    /// reappears on its next hook event.
    private static let staleInterval: TimeInterval = 30 * 60
    /// How often the prune sweep runs.
    private static let pruneTick: TimeInterval = 60
    /// How often subscription usage is refreshed (changes slowly).
    private static let usageTick: TimeInterval = 120

    // pruneTimer holds a weak self and AppModel lives for the whole app lifetime, so
    // there's nothing to tear down here (and Timer isn't Sendable / accessible from a
    // nonisolated deinit anyway).
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

        // Periodically drop residual sessions (process gone, no SessionEnd received).
        let timer = Timer(timeInterval: Self.pruneTick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneStale() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer

        // Poll subscription usage now and on an interval.
        refreshUsage()
        let usageT = Timer(timeInterval: Self.usageTick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshUsage() }
        }
        RunLoop.main.add(usageT, forMode: .common)
        usageTimer = usageT
    }

    private func refreshUsage() {
        Task {
            let fetched = await UsageClient.fetch()
            guard let fetched else { return }   // keep last value on failure
            await MainActor.run { self.usage = fetched }
        }
    }

    private func pruneStale() {
        let before = store.sessions.count
        store.prune(olderThan: Self.staleInterval, now: Date())
        if store.sessions.count != before { refresh() }
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
