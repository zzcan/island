import Foundation
import Combine
import IslandCore

/// Main-actor bridge between the pure SessionStore and SwiftUI. Owns the store,
/// the notifier, and the jumper; wires socket messages -> store -> UI/notifications.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var icon: IconState = .idle
    @Published private(set) var display: IslandDisplay = .from([])
    @Published private(set) var eventTick: Int = 0
    /// The plan currently awaiting the user's review (one at a time; extras queue).
    @Published private(set) var pendingPlan: PlanRequest?

    private var planQueue: [PlanRequest] = []
    private var planWriters: [String: ReplyWriter] = [:]

    private let store = SessionStore()
    private let notifier = Notifier()
    private let jumper = Jumper()
    private let synth = SoundSynthesizer.shared
    private lazy var settingsController = SettingsWindowController()
    private var server: SocketServer?
    private var started = false
    private var pruneTimer: Timer?
    private var settingsCancellable: AnyCancellable?

    /// A done/idle session whose lastActivity is older than the configured retention
    /// (Settings.sessionRetentionMinutes) is treated as residual (its process likely
    /// died without firing SessionEnd) and pruned. Active sessions (working /
    /// needsInput) are kept regardless of age — see SessionStore.prune. Self-healing:
    /// a pruned session that is actually alive reappears on its next hook event.
    /// How often the prune sweep runs.
    private static let pruneTick: TimeInterval = 60

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
        let server = SocketServer(path: path, onMessage: { [weak self] msg in
            Task { @MainActor in self?.handle(msg) }
        }, onRequest: { [weak self] msg, writer in
            Task { @MainActor in self?.handleRequest(msg, writer) }
        })
        do { try server.start() } catch { NSLog("island: socket start failed: \(error)") }
        self.server = server

        // Periodically drop residual sessions (process gone, no SessionEnd received).
        let timer = Timer(timeInterval: Self.pruneTick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneStale() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer

        // Re-derive the display when filters (or any setting) change, so editing a
        // hide-rule updates the island immediately.
        settingsCancellable = Settings.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Sessions the island should show — drops any hidden by the cwd / prompt filters.
    private func visibleSessions() -> [Session] {
        let s = Settings.shared
        let cwds = s.cwdFilters.filter { !$0.isEmpty }
        let prompts = s.promptFilters.filter { !$0.isEmpty }
        guard !cwds.isEmpty || !prompts.isEmpty else { return Array(store.sessions.values) }
        return store.sessions.values.filter { sess in
            if let c = sess.cwd, cwds.contains(where: { c.localizedCaseInsensitiveContains($0) }) { return false }
            if let p = sess.lastPrompt, prompts.contains(where: { p.hasPrefix($0) }) { return false }
            return true
        }
    }

    private func pruneStale() {
        let before = store.sessions.count
        store.prune(olderThan: Settings.shared.sessionRetentionMinutes * 60, now: Date())
        if store.sessions.count != before { refresh() }
    }

    func handle(_ msg: HookMessage) {
        let request = store.apply(msg, now: Date())
        refresh()
        let s = Settings.shared
        // Sounds are suppressed entirely during quiet hours.
        let soundOn = s.soundEnabled && !s.isQuietNow()
        if soundOn {
            synth.masterVolume = Float(s.soundVolume)
            // Session-start fires on its own event (no notification request is produced).
            if msg.event == .sessionStart, s.soundSessionStart { synth.play(.sessionStart) }
        }
        if let request {
            eventTick &+= 1
            if s.notificationsEnabled { notifier.post(request) }
            // Per-event 8-bit blip, chosen by the session's resulting status — each
            // category individually toggleable in Settings.
            if soundOn, let status = store.sessions[request.sessionId]?.status {
                switch status {
                case .needsInput: if s.soundInputRequired { synth.play(.needsInput) }
                case .done:       if s.soundTaskComplete { synth.play(.done) }
                case .working, .idle: break
                }
            }
        }
    }

    /// A blocked hook is asking the user to review a plan (ExitPlanMode). Surface it and
    /// alert; the hook stays parked until `resolvePlan` answers (or it times out).
    func handleRequest(_ msg: HookMessage, _ writer: ReplyWriter) {
        // Feature off, or malformed payload — hand back to the terminal's own prompt.
        guard Settings.shared.planReviewEnabled,
              let rid = msg.requestId, let plan = msg.plan, !plan.isEmpty else {
            if let data = try? JSONEncoder().encode(PermissionReply.defer_) { writer.reply(data) }
            return
        }
        let req = PlanRequest(id: rid, sessionId: msg.sessionId,
                              title: msg.title ?? msg.sessionId, cwd: msg.cwd, plan: plan)
        planWriters[rid] = writer
        planQueue.append(req)
        if pendingPlan == nil { pendingPlan = req }

        eventTick &+= 1
        let s = Settings.shared
        if s.notificationsEnabled {
            notifier.post(NotificationRequest(sessionId: msg.sessionId, title: req.title,
                                              body: "计划待审阅"))
        }
        if s.soundEnabled, !s.isQuietNow(), s.soundInputRequired {
            synth.masterVolume = Float(s.soundVolume); synth.play(.needsInput)
        }
    }

    /// Answer the parked hook with the user's decision and advance the queue.
    func resolvePlan(_ req: PlanRequest, _ reply: PermissionReply) {
        if let writer = planWriters.removeValue(forKey: req.id),
           let data = try? JSONEncoder().encode(reply) {
            writer.reply(data)
        }
        planQueue.removeAll { $0.id == req.id }
        pendingPlan = planQueue.first
    }

    func openSettings() { settingsController.show() }

    func jump(sessionId: String) {
        guard let session = store.sessions[sessionId] else { return }
        jumper.jump(to: session)
    }

    /// Remove a session from the panel (user clicked the clear icon). Transient — it
    /// returns if the session emits another event; done/idle ones stay gone.
    func dismiss(sessionId: String) {
        store.remove(sessionId)
        refresh()
    }

    private func refresh() {
        let visible = visibleSessions()
        sessions = visible.sorted { $0.lastActivity > $1.lastActivity }
        icon = store.iconState
        display = IslandDisplay.from(visible)
    }
}
