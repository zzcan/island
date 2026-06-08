import Testing
import Foundation
@testable import IslandCore

@Suite struct SessionStoreTests {
    let t0 = Date(timeIntervalSince1970: 1000)

    private func msg(_ event: IslandEvent, _ sid: String = "s1",
                     cwd: String? = "/Users/me/proj", message: String? = nil,
                     cmux: CmuxContext? = nil) -> HookMessage {
        HookMessage(event: event, sessionId: sid, cwd: cwd,
                    title: cwd.map { ($0 as NSString).lastPathComponent },
                    message: message, cmux: cmux, tmux: nil)
    }

    @Test func sessionStartRegistersIdle() {
        let store = SessionStore()
        let note = store.apply(msg(.sessionStart), now: t0)
        #expect(note == nil)
        #expect(store.sessions.count == 1)
        #expect(store.sessions["s1"]?.status == .idle)
        #expect(store.sessions["s1"]?.title == "proj")
    }

    @Test func userPromptSubmitGoesWorking_AndCreatesIfMissing() {
        let store = SessionStore()
        let note = store.apply(msg(.userPromptSubmit), now: t0)   // no prior SessionStart
        #expect(note == nil)
        #expect(store.sessions["s1"]?.status == .working)
    }

    @Test func notificationGoesNeedsInput_AndReturnsRequest() {
        let store = SessionStore()
        _ = store.apply(msg(.userPromptSubmit), now: t0)
        let note = store.apply(msg(.notification, message: "Allow Bash?"), now: t0)
        #expect(store.sessions["s1"]?.status == .needsInput)
        #expect(note == NotificationRequest(sessionId: "s1", title: "proj", body: "Allow Bash?"))
    }

    @Test func stopGoesDone_AndReturnsRequest() {
        let store = SessionStore()
        _ = store.apply(msg(.userPromptSubmit), now: t0)
        let note = store.apply(msg(.stop), now: t0)
        #expect(store.sessions["s1"]?.status == .done)
        #expect(note == NotificationRequest(sessionId: "s1", title: "proj", body: "Done"))
    }

    @Test func sessionEndRemoves() {
        let store = SessionStore()
        _ = store.apply(msg(.userPromptSubmit), now: t0)
        let note = store.apply(msg(.sessionEnd), now: t0)
        #expect(note == nil)
        #expect(store.sessions.isEmpty)
    }

    @Test func cmuxContextStoredOnLatestMessage() {
        let store = SessionStore()
        let ctx = CmuxContext(workspaceId: "w1", surfaceId: nil, socketPath: "/tmp/c.sock")
        _ = store.apply(msg(.userPromptSubmit, cmux: ctx), now: t0)
        #expect(store.sessions["s1"]?.cmux == ctx)
    }

    @Test func iconStateReflectsStore() {
        let store = SessionStore()
        _ = store.apply(msg(.userPromptSubmit), now: t0)
        #expect(store.iconState == .busy)
        _ = store.apply(msg(.stop), now: t0)
        #expect(store.iconState == .attention)
    }

    @Test func pruneDropsStaleSessions() {
        let store = SessionStore()
        _ = store.apply(msg(.stop), now: t0)
        store.prune(olderThan: 100, now: t0.addingTimeInterval(200))
        #expect(store.sessions.isEmpty)
    }

    @Test func clearAll() {
        let store = SessionStore()
        _ = store.apply(msg(.userPromptSubmit), now: t0)
        store.clearAll()
        #expect(store.sessions.isEmpty)
    }

    @Test func applyingPromptStoresLastPrompt() {
        let store = SessionStore()
        let m = HookMessage(event: .userPromptSubmit, sessionId: "s1", cwd: "/Users/me/proj",
                            title: "proj", message: nil, cmux: nil, tmux: nil, prompt: "do X")
        _ = store.apply(m, now: t0)
        #expect(store.sessions["s1"]?.lastPrompt == "do X")
    }
}
