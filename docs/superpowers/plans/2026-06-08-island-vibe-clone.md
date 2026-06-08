# island — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A self-use macOS menu-bar app that listens to Claude Code hook events and, on "done / needs input", shows a notification whose click jumps to the cmux workspace (and tmux pane) running that agent.

**Architecture:** One SwiftPM package, three targets. `IslandCore` is a pure-logic library (event model, session state machine, message builder, jump-command builder) covered by `swift test`. `vibe-hook` is a tiny CLI registered in Claude Code hooks that reads stdin+env and sends one JSON line over a unix socket. `island` is the SwiftUI `MenuBarExtra` app that listens on the socket, drives the icon, posts notifications, and performs jumps. A `bundle.sh` wraps the app executable into `island.app` with an `Info.plist` (bundle id for notifications + `LSUIElement` to hide the dock icon).

**Tech Stack:** Swift 5.9, SwiftUI (`MenuBarExtra`, macOS 13+), `UserNotifications`, POSIX `AF_UNIX` sockets, `Process` for cmux/tmux CLI, ad-hoc `codesign`.

---

## Spec reference

Design spec: `docs/superpowers/specs/2026-06-08-island-clone-design.md`. Read it first.

## File Structure

```
island/                                  (SwiftPM root; git already initialized)
├─ Package.swift
├─ Sources/
│  ├─ IslandCore/                         pure logic — fully unit-tested
│  │  ├─ HookEvent.swift                  IslandEvent enum + ClaudeHookInput decode
│  │  ├─ Contexts.swift                   CmuxContext, TmuxContext
│  │  ├─ HookMessage.swift                wire struct + buildMessage(stdin,env,tmux)
│  │  ├─ Session.swift                    Session struct, SessionStatus, title derivation
│  │  ├─ IconState.swift                  IconState enum + aggregate(sessions)
│  │  ├─ SessionStore.swift               state machine: apply(message) -> NotificationRequest?
│  │  ├─ NotificationRequest.swift        value type returned by the store
│  │  ├─ Command.swift                    Command value type + CommandRunner protocol
│  │  ├─ JumpPlan.swift                   jumpCommands(for:) -> [Command]
│  │  └─ SocketPath.swift                 defaultSocketPath()
│  ├─ vibe-hook/
│  │  ├─ main.swift                       stdin+env -> HookMessage -> socket
│  │  ├─ ProcessRunner.swift              CommandRunner impl (also used by island)
│  │  └─ UnixSocketClient.swift           connect+send with timeout, always best-effort
│  └─ island/
│     ├─ main.swift                       @main App + MenuBarExtra wiring
│     ├─ AppModel.swift                   @MainActor ObservableObject over SessionStore
│     ├─ SocketServer.swift               AF_UNIX listener -> AppModel
│     ├─ Notifier.swift                   UNUserNotificationCenter wrapper + click handler
│     ├─ Jumper.swift                     JumpPlan + ProcessRunner + NSWorkspace activate
│     └─ MenuBarView.swift                dropdown UI
├─ Tests/IslandCoreTests/
│  ├─ HookMessageTests.swift
│  ├─ SessionStoreTests.swift
│  ├─ IconStateTests.swift
│  └─ JumpPlanTests.swift
├─ Scripts/
│  ├─ bundle.sh                           build release + assemble island.app + adhoc sign
│  └─ install-hooks.sh                    merge vibe-hook into ~/.claude/settings.json
└─ docs/superpowers/...
```

`ProcessRunner.swift` and `UnixSocketClient.swift` live under `vibe-hook/` but the `island` target needs `ProcessRunner` too. To avoid duplication, both files are placed in `Sources/IslandCore/` instead (they only depend on Foundation). **Correction applied below:** `ProcessRunner.swift`, `UnixSocketClient.swift`, and `SocketPath.swift` all live in `IslandCore`. `IslandCore` therefore imports Foundation only (no AppKit/SwiftUI), staying testable.

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/IslandCore/Placeholder.swift`
- Create: `Sources/vibe-hook/main.swift`
- Create: `Sources/island/main.swift`
- Create: `Tests/IslandCoreTests/SmokeTests.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "island",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(name: "vibe-hook", dependencies: ["IslandCore"]),
        .executableTarget(name: "island", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
```

- [ ] **Step 2: Create minimal target stubs so the package compiles**

`Sources/IslandCore/Placeholder.swift`:
```swift
// Replaced by real types in later tasks.
public enum IslandCore {}
```

`Sources/vibe-hook/main.swift`:
```swift
// Filled in Task 9.
print("vibe-hook stub")
```

`Sources/island/main.swift`:
```swift
// Filled in Task 14.
print("island stub")
```

`Tests/IslandCoreTests/SmokeTests.swift`:
```swift
import XCTest
@testable import IslandCore

final class SmokeTests: XCTestCase {
    func testPackageCompiles() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 3: Build and test**

Run: `swift build && swift test`
Expected: build succeeds; 1 test passes.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "chore: SwiftPM package scaffold (IslandCore + vibe-hook + island)"
```

---

### Task 2: IconState aggregation (pure, TDD)

**Files:**
- Create: `Sources/IslandCore/IconState.swift`
- Create: `Sources/IslandCore/Session.swift` (minimal, expanded in Task 4)
- Test: `Tests/IslandCoreTests/IconStateTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/IslandCoreTests/IconStateTests.swift`:
```swift
import XCTest
@testable import IslandCore

final class IconStateTests: XCTestCase {
    private func session(_ status: SessionStatus) -> Session {
        Session(id: UUID().uuidString, title: "t", cwd: nil, status: status,
                cmux: nil, tmux: nil, lastActivity: Date(timeIntervalSince1970: 0))
    }

    func testEmptyIsIdle() {
        XCTAssertEqual(IconState.aggregate([]), .idle)
    }

    func testAnyWorkingIsBusy() {
        XCTAssertEqual(IconState.aggregate([session(.idle), session(.working)]), .busy)
    }

    func testNeedsInputBeatsWorking() {
        XCTAssertEqual(IconState.aggregate([session(.working), session(.needsInput)]), .attention)
    }

    func testDoneIsAttention() {
        XCTAssertEqual(IconState.aggregate([session(.done)]), .attention)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter IconStateTests`
Expected: FAIL — `SessionStatus` / `Session` / `IconState` not defined.

- [ ] **Step 3: Write minimal implementations**

`Sources/IslandCore/Session.swift`:
```swift
import Foundation

public enum SessionStatus: String, Codable, Equatable, Sendable {
    case idle, working, needsInput, done
}

public struct Session: Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var cwd: String?
    public var status: SessionStatus
    public var cmux: CmuxContext?
    public var tmux: TmuxContext?
    public var lastActivity: Date

    public init(id: String, title: String, cwd: String?, status: SessionStatus,
                cmux: CmuxContext?, tmux: TmuxContext?, lastActivity: Date) {
        self.id = id; self.title = title; self.cwd = cwd; self.status = status
        self.cmux = cmux; self.tmux = tmux; self.lastActivity = lastActivity
    }
}
```

`Sources/IslandCore/IconState.swift`:
```swift
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
```

Also add `Sources/IslandCore/Contexts.swift` (needed for `Session` to compile):
```swift
import Foundation

public struct CmuxContext: Codable, Equatable, Sendable {
    public let workspaceId: String
    public let surfaceId: String?
    public let socketPath: String
    public init(workspaceId: String, surfaceId: String?, socketPath: String) {
        self.workspaceId = workspaceId; self.surfaceId = surfaceId; self.socketPath = socketPath
    }
}

public struct TmuxContext: Codable, Equatable, Sendable {
    public let pane: String
    public let window: String
    public let session: String
    public init(pane: String, window: String, session: String) {
        self.pane = pane; self.window = window; self.session = session
    }
}
```

Delete the placeholder: remove `Sources/IslandCore/Placeholder.swift`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter IconStateTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git rm Sources/IslandCore/Placeholder.swift
git add Sources/IslandCore Tests/IslandCoreTests/IconStateTests.swift
git commit -m "feat(core): Session, SessionStatus, contexts, IconState.aggregate"
```

---

### Task 3: HookEvent + ClaudeHookInput decoding (pure, TDD)

**Files:**
- Create: `Sources/IslandCore/HookEvent.swift`
- Test: `Tests/IslandCoreTests/HookMessageTests.swift` (decode portion)

- [ ] **Step 1: Write the failing test**

`Tests/IslandCoreTests/HookMessageTests.swift`:
```swift
import XCTest
@testable import IslandCore

final class HookMessageTests: XCTestCase {
    func testIslandEventRawValues() {
        XCTAssertEqual(IslandEvent(claudeName: "SessionStart"), .sessionStart)
        XCTAssertEqual(IslandEvent(claudeName: "UserPromptSubmit"), .userPromptSubmit)
        XCTAssertEqual(IslandEvent(claudeName: "Notification"), .notification)
        XCTAssertEqual(IslandEvent(claudeName: "Stop"), .stop)
        XCTAssertEqual(IslandEvent(claudeName: "SessionEnd"), .sessionEnd)
        XCTAssertNil(IslandEvent(claudeName: "PreToolUse"))
    }

    func testDecodeClaudeInput() throws {
        let json = #"{"session_id":"abc","cwd":"/x/proj","hook_event_name":"Notification","message":"need perms"}"#
        let input = try ClaudeHookInput.decode(Data(json.utf8))
        XCTAssertEqual(input.session_id, "abc")
        XCTAssertEqual(input.cwd, "/x/proj")
        XCTAssertEqual(input.hook_event_name, "Notification")
        XCTAssertEqual(input.message, "need perms")
    }

    func testDecodeToleratesMissingFields() throws {
        let json = #"{"hook_event_name":"Stop","session_id":"s1"}"#
        let input = try ClaudeHookInput.decode(Data(json.utf8))
        XCTAssertEqual(input.session_id, "s1")
        XCTAssertNil(input.cwd)
        XCTAssertNil(input.message)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HookMessageTests`
Expected: FAIL — `IslandEvent` / `ClaudeHookInput` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/IslandCore/HookEvent.swift`:
```swift
import Foundation

public enum IslandEvent: String, Codable, Equatable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case notification = "Notification"
    case stop = "Stop"
    case sessionEnd = "SessionEnd"

    public init?(claudeName: String) {
        self.init(rawValue: claudeName)
    }
}

/// The raw JSON Claude Code writes to a hook's stdin (subset we use).
public struct ClaudeHookInput: Codable, Equatable, Sendable {
    public let session_id: String?
    public let cwd: String?
    public let hook_event_name: String?
    public let message: String?

    public static func decode(_ data: Data) throws -> ClaudeHookInput {
        try JSONDecoder().decode(ClaudeHookInput.self, from: data)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HookMessageTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/IslandCore/HookEvent.swift Tests/IslandCoreTests/HookMessageTests.swift
git commit -m "feat(core): IslandEvent + ClaudeHookInput decoding"
```

---

### Task 4: HookMessage wire format + buildMessage (pure, TDD)

**Files:**
- Create: `Sources/IslandCore/HookMessage.swift`
- Test: append to `Tests/IslandCoreTests/HookMessageTests.swift`

- [ ] **Step 1: Add failing tests**

Append to `Tests/IslandCoreTests/HookMessageTests.swift` (inside the class):
```swift
    func testBuildMessageReadsCmuxFromEnv() throws {
        let json = #"{"session_id":"s1","cwd":"/Users/me/proj","hook_event_name":"UserPromptSubmit"}"#
        let env = [
            "CMUX_WORKSPACE_ID": "ws1",
            "CMUX_SURFACE_ID": "sf1",
            "CMUX_SOCKET_PATH": "/tmp/cmux.sock",
        ]
        let msg = HookMessage.build(stdin: Data(json.utf8), env: env, tmux: nil)
        XCTAssertEqual(msg?.event, .userPromptSubmit)
        XCTAssertEqual(msg?.sessionId, "s1")
        XCTAssertEqual(msg?.title, "proj")              // last path component of cwd
        XCTAssertEqual(msg?.cmux?.workspaceId, "ws1")
        XCTAssertEqual(msg?.cmux?.surfaceId, "sf1")
        XCTAssertEqual(msg?.cmux?.socketPath, "/tmp/cmux.sock")
        XCTAssertNil(msg?.tmux)
    }

    func testBuildMessageNilWhenNoSessionId() {
        let json = #"{"hook_event_name":"Stop"}"#
        XCTAssertNil(HookMessage.build(stdin: Data(json.utf8), env: [:], tmux: nil))
    }

    func testBuildMessageNilWhenUnknownEvent() {
        let json = #"{"session_id":"s1","hook_event_name":"PreToolUse"}"#
        XCTAssertNil(HookMessage.build(stdin: Data(json.utf8), env: [:], tmux: nil))
    }

    func testBuildMessageNilWhenNoCmuxEnv() {
        // No CMUX_* env -> cmux nil but message still built (jump just won't work).
        let json = #"{"session_id":"s1","hook_event_name":"Stop"}"#
        let msg = HookMessage.build(stdin: Data(json.utf8), env: [:], tmux: nil)
        XCTAssertNotNil(msg)
        XCTAssertNil(msg?.cmux)
    }

    func testHookMessageRoundTripsJSON() throws {
        let original = HookMessage(event: .stop, sessionId: "s1", cwd: "/a/b", title: "b",
                                   message: nil,
                                   cmux: CmuxContext(workspaceId: "w", surfaceId: nil, socketPath: "/tmp/c.sock"),
                                   tmux: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HookMessage.self, from: data)
        XCTAssertEqual(decoded, original)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter HookMessageTests`
Expected: FAIL — `HookMessage` not defined.

- [ ] **Step 3: Implement**

`Sources/IslandCore/HookMessage.swift`:
```swift
import Foundation

/// Our own wire format: vibe-hook sends one of these as a single JSON line.
public struct HookMessage: Codable, Equatable, Sendable {
    public let event: IslandEvent
    public let sessionId: String
    public let cwd: String?
    public let title: String?
    public let message: String?
    public let cmux: CmuxContext?
    public let tmux: TmuxContext?

    public init(event: IslandEvent, sessionId: String, cwd: String?, title: String?,
                message: String?, cmux: CmuxContext?, tmux: TmuxContext?) {
        self.event = event; self.sessionId = sessionId; self.cwd = cwd; self.title = title
        self.message = message; self.cmux = cmux; self.tmux = tmux
    }

    /// Pure builder. `tmux` is passed in (the caller resolves it via a side-effecting CLI call)
    /// to keep this function testable. Returns nil if the event is unsupported or sessionId missing.
    public static func build(stdin: Data, env: [String: String], tmux: TmuxContext?) -> HookMessage? {
        guard let input = try? ClaudeHookInput.decode(stdin) else { return nil }
        guard let name = input.hook_event_name, let event = IslandEvent(claudeName: name) else { return nil }
        guard let sid = input.session_id, !sid.isEmpty else { return nil }

        var cmux: CmuxContext? = nil
        if let ws = env["CMUX_WORKSPACE_ID"], let sock = env["CMUX_SOCKET_PATH"] {
            cmux = CmuxContext(workspaceId: ws, surfaceId: env["CMUX_SURFACE_ID"], socketPath: sock)
        }

        let title = input.cwd.map { ($0 as NSString).lastPathComponent }

        return HookMessage(event: event, sessionId: sid, cwd: input.cwd, title: title,
                           message: input.message, cmux: cmux, tmux: tmux)
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter HookMessageTests`
Expected: PASS (all HookMessage tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/IslandCore/HookMessage.swift Tests/IslandCoreTests/HookMessageTests.swift
git commit -m "feat(core): HookMessage wire format + pure build(stdin,env,tmux)"
```

---

### Task 5: SessionStore state machine + NotificationRequest (pure, TDD)

**Files:**
- Create: `Sources/IslandCore/NotificationRequest.swift`
- Create: `Sources/IslandCore/SessionStore.swift`
- Test: `Tests/IslandCoreTests/SessionStoreTests.swift`

- [ ] **Step 1: Write failing tests**

`Tests/IslandCoreTests/SessionStoreTests.swift`:
```swift
import XCTest
@testable import IslandCore

final class SessionStoreTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1000)

    private func msg(_ event: IslandEvent, _ sid: String = "s1",
                     cwd: String? = "/Users/me/proj", message: String? = nil,
                     cmux: CmuxContext? = nil) -> HookMessage {
        HookMessage(event: event, sessionId: sid, cwd: cwd,
                    title: cwd.map { ($0 as NSString).lastPathComponent },
                    message: message, cmux: cmux, tmux: nil)
    }

    func testSessionStartRegistersIdle() {
        let store = SessionStore()
        let note = store.apply(msg(.sessionStart), now: t0)
        XCTAssertNil(note)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions["s1"]?.status, .idle)
        XCTAssertEqual(store.sessions["s1"]?.title, "proj")
    }

    func testUserPromptSubmitGoesWorking_AndCreatesIfMissing() {
        let store = SessionStore()
        let note = store.apply(msg(.userPromptSubmit), now: t0)   // no prior SessionStart
        XCTAssertNil(note)
        XCTAssertEqual(store.sessions["s1"]?.status, .working)
    }

    func testNotificationGoesNeedsInput_AndReturnsRequest() {
        let store = SessionStore()
        _ = store.apply(msg(.userPromptSubmit), now: t0)
        let note = store.apply(msg(.notification, message: "Allow Bash?"), now: t0)
        XCTAssertEqual(store.sessions["s1"]?.status, .needsInput)
        XCTAssertEqual(note, NotificationRequest(sessionId: "s1", title: "proj", body: "Allow Bash?"))
    }

    func testStopGoesDone_AndReturnsRequest() {
        let store = SessionStore()
        _ = store.apply(msg(.userPromptSubmit), now: t0)
        let note = store.apply(msg(.stop), now: t0)
        XCTAssertEqual(store.sessions["s1"]?.status, .done)
        XCTAssertEqual(note, NotificationRequest(sessionId: "s1", title: "proj", body: "Done"))
    }

    func testSessionEndRemoves() {
        let store = SessionStore()
        _ = store.apply(msg(.userPromptSubmit), now: t0)
        let note = store.apply(msg(.sessionEnd), now: t0)
        XCTAssertNil(note)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testCmuxContextStoredOnLatestMessage() {
        let store = SessionStore()
        let ctx = CmuxContext(workspaceId: "w1", surfaceId: nil, socketPath: "/tmp/c.sock")
        _ = store.apply(msg(.userPromptSubmit, cmux: ctx), now: t0)
        XCTAssertEqual(store.sessions["s1"]?.cmux, ctx)
    }

    func testIconStateReflectsStore() {
        let store = SessionStore()
        _ = store.apply(msg(.userPromptSubmit), now: t0)
        XCTAssertEqual(store.iconState, .busy)
        _ = store.apply(msg(.stop), now: t0)
        XCTAssertEqual(store.iconState, .attention)
    }

    func testPruneDropsStaleSessions() {
        let store = SessionStore()
        _ = store.apply(msg(.stop), now: t0)
        store.prune(olderThan: 100, now: t0.addingTimeInterval(200))
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testClearAll() {
        let store = SessionStore()
        _ = store.apply(msg(.userPromptSubmit), now: t0)
        store.clearAll()
        XCTAssertTrue(store.sessions.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter SessionStoreTests`
Expected: FAIL — `SessionStore` / `NotificationRequest` not defined.

- [ ] **Step 3: Implement**

`Sources/IslandCore/NotificationRequest.swift`:
```swift
public struct NotificationRequest: Equatable, Sendable {
    public let sessionId: String
    public let title: String
    public let body: String
    public init(sessionId: String, title: String, body: String) {
        self.sessionId = sessionId; self.title = title; self.body = body
    }
}
```

`Sources/IslandCore/SessionStore.swift`:
```swift
import Foundation

/// Pure in-memory state machine. No UI, no I/O. Not thread-safe by itself —
/// callers (AppModel) confine it to the main actor.
public final class SessionStore {
    public private(set) var sessions: [String: Session] = [:]

    public init() {}

    public var iconState: IconState {
        IconState.aggregate(Array(sessions.values))
    }

    /// Applies a message and returns a NotificationRequest when the user should be alerted.
    @discardableResult
    public func apply(_ m: HookMessage, now: Date) -> NotificationRequest? {
        if m.event == .sessionEnd {
            sessions[m.sessionId] = nil
            return nil
        }

        var s = sessions[m.sessionId] ?? Session(
            id: m.sessionId, title: m.title ?? m.sessionId, cwd: m.cwd, status: .idle,
            cmux: nil, tmux: nil, lastActivity: now)

        // Refresh fields the message carries.
        if let title = m.title { s.title = title }
        if let cwd = m.cwd { s.cwd = cwd }
        if let cmux = m.cmux { s.cmux = cmux }
        if let tmux = m.tmux { s.tmux = tmux }
        s.lastActivity = now

        var request: NotificationRequest? = nil
        switch m.event {
        case .sessionStart:
            s.status = .idle
        case .userPromptSubmit:
            s.status = .working
        case .notification:
            s.status = .needsInput
            request = NotificationRequest(sessionId: s.id, title: s.title,
                                          body: m.message ?? "Needs your input")
        case .stop:
            s.status = .done
            request = NotificationRequest(sessionId: s.id, title: s.title, body: "Done")
        case .sessionEnd:
            break // handled above
        }

        sessions[m.sessionId] = s
        return request
    }

    public func prune(olderThan interval: TimeInterval, now: Date) {
        sessions = sessions.filter { now.timeIntervalSince($0.value.lastActivity) <= interval }
    }

    public func clearAll() {
        sessions.removeAll()
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter SessionStoreTests`
Expected: PASS (all SessionStore tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/IslandCore/NotificationRequest.swift Sources/IslandCore/SessionStore.swift Tests/IslandCoreTests/SessionStoreTests.swift
git commit -m "feat(core): SessionStore state machine + NotificationRequest"
```

---

### Task 6: Command + CommandRunner + JumpPlan (pure, TDD)

**Files:**
- Create: `Sources/IslandCore/Command.swift`
- Create: `Sources/IslandCore/JumpPlan.swift`
- Test: `Tests/IslandCoreTests/JumpPlanTests.swift`

- [ ] **Step 1: Write failing tests**

`Tests/IslandCoreTests/JumpPlanTests.swift`:
```swift
import XCTest
@testable import IslandCore

final class JumpPlanTests: XCTestCase {
    private func session(cmux: CmuxContext?, tmux: TmuxContext?) -> Session {
        Session(id: "s1", title: "t", cwd: nil, status: .done,
                cmux: cmux, tmux: tmux, lastActivity: Date(timeIntervalSince1970: 0))
    }

    func testNoContextNoCommands() {
        XCTAssertEqual(JumpPlan.commands(for: session(cmux: nil, tmux: nil)), [])
    }

    func testCmuxOnly() {
        let s = session(cmux: CmuxContext(workspaceId: "w1", surfaceId: nil, socketPath: "/tmp/c.sock"), tmux: nil)
        XCTAssertEqual(JumpPlan.commands(for: s), [
            Command(executable: "cmux", arguments: ["select-workspace", "w1"],
                    environment: ["CMUX_SOCKET_PATH": "/tmp/c.sock"]),
        ])
    }

    func testCmuxThenTmux() {
        let s = session(
            cmux: CmuxContext(workspaceId: "w1", surfaceId: nil, socketPath: "/tmp/c.sock"),
            tmux: TmuxContext(pane: "%3", window: "1", session: "main"))
        XCTAssertEqual(JumpPlan.commands(for: s), [
            Command(executable: "cmux", arguments: ["select-workspace", "w1"],
                    environment: ["CMUX_SOCKET_PATH": "/tmp/c.sock"]),
            Command(executable: "tmux", arguments: ["select-window", "-t", "main:1"], environment: [:]),
            Command(executable: "tmux", arguments: ["select-pane", "-t", "%3"], environment: [:]),
        ])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter JumpPlanTests`
Expected: FAIL — `Command` / `JumpPlan` not defined.

- [ ] **Step 3: Implement**

`Sources/IslandCore/Command.swift`:
```swift
import Foundation

public struct Command: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public init(executable: String, arguments: [String], environment: [String: String]) {
        self.executable = executable; self.arguments = arguments; self.environment = environment
    }
}

public protocol CommandRunner {
    /// Runs the command, returning trimmed stdout. Throws on launch/non-zero exit.
    @discardableResult
    func run(_ command: Command) throws -> String
}
```

`Sources/IslandCore/JumpPlan.swift`:
```swift
public enum JumpPlan {
    /// CLI commands to focus the right cmux workspace and (if present) tmux pane.
    /// App activation (NSWorkspace) is handled by the caller, not here.
    public static func commands(for session: Session) -> [Command] {
        var cmds: [Command] = []
        if let cmux = session.cmux {
            cmds.append(Command(executable: "cmux",
                                arguments: ["select-workspace", cmux.workspaceId],
                                environment: ["CMUX_SOCKET_PATH": cmux.socketPath]))
        }
        if let tmux = session.tmux {
            cmds.append(Command(executable: "tmux",
                                arguments: ["select-window", "-t", "\(tmux.session):\(tmux.window)"],
                                environment: [:]))
            cmds.append(Command(executable: "tmux",
                                arguments: ["select-pane", "-t", tmux.pane],
                                environment: [:]))
        }
        return cmds
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter JumpPlanTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/IslandCore/Command.swift Sources/IslandCore/JumpPlan.swift Tests/IslandCoreTests/JumpPlanTests.swift
git commit -m "feat(core): Command, CommandRunner protocol, JumpPlan command builder"
```

---

### Task 7: SocketPath helper + ProcessRunner + UnixSocketClient (IslandCore I/O)

These are thin side-effecting helpers (verified by build + later e2e, not unit tests).

**Files:**
- Create: `Sources/IslandCore/SocketPath.swift`
- Create: `Sources/IslandCore/ProcessRunner.swift`
- Create: `Sources/IslandCore/UnixSocketClient.swift`

- [ ] **Step 1: Implement `SocketPath.swift`**

```swift
import Foundation

public enum SocketPath {
    /// ~/Library/Application Support/island/run.sock — overridable via ISLAND_SOCKET.
    public static func resolve(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = env["ISLAND_SOCKET"], !override.isEmpty { return override }
        let home = env["HOME"] ?? NSHomeDirectory()
        return "\(home)/Library/Application Support/island/run.sock"
    }
}
```

- [ ] **Step 2: Implement `ProcessRunner.swift`**

```swift
import Foundation

public struct ProcessError: Error { public let code: Int32; public let stderr: String }

/// Real CommandRunner. Resolves the executable via /usr/bin/env so PATH is honored.
public struct ProcessRunner: CommandRunner {
    public init() {}

    @discardableResult
    public func run(_ command: Command) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [command.executable] + command.arguments
        var env = ProcessInfo.processInfo.environment
        for (k, v) in command.environment { env[k] = v }
        proc.environment = env

        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out; proc.standardError = err
        try proc.run()
        proc.waitUntilExit()

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        if proc.terminationStatus != 0 {
            throw ProcessError(code: proc.terminationStatus,
                               stderr: String(decoding: errData, as: UTF8.self))
        }
        return String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 3: Implement `UnixSocketClient.swift`**

```swift
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Best-effort one-shot sender. Used by vibe-hook. Never throws to the caller's
/// detriment — failures are reported via the Bool return so the hook can still exit 0.
public enum UnixSocketClient {
    @discardableResult
    public static func send(_ data: Data, toPath path: String, timeoutMs: Int = 200) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { return false }
        defer { close(fd) }

        // Non-blocking connect with timeout.
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { dst in
                for (i, b) in pathBytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[pathBytes.count] = 0
            }
        }

        var tv = timeval(tv_sec: 0, tv_usec: Int32(timeoutMs * 1000))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, len)
            }
        }
        if connected != 0 { return false }

        var sent = 0
        let bytes = [UInt8](data)
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes { raw in
                write(fd, raw.baseAddress!.advanced(by: sent), bytes.count - sent)
            }
            if n <= 0 { return false }
            sent += n
        }
        return true
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds clean. (No new unit tests; verified by build and Task 9/15 e2e.)

- [ ] **Step 5: Commit**

```bash
git add Sources/IslandCore/SocketPath.swift Sources/IslandCore/ProcessRunner.swift Sources/IslandCore/UnixSocketClient.swift
git commit -m "feat(core): SocketPath, ProcessRunner, UnixSocketClient helpers"
```

---

### Task 8: Full IslandCore test run (regression gate)

**Files:** none (verification task).

- [ ] **Step 1: Run the whole suite**

Run: `swift test`
Expected: PASS — IconStateTests (4) + HookMessageTests (8) + SessionStoreTests (9) + JumpPlanTests (3) + SmokeTests (1).

- [ ] **Step 2: If anything fails, fix before proceeding.** Do not move to glue code on a red suite.

- [ ] **Step 3: Commit (only if fixes were needed)**

```bash
git commit -am "test: green IslandCore suite"
```

---

### Task 9: vibe-hook executable

**Files:**
- Modify: `Sources/vibe-hook/main.swift`

- [ ] **Step 1: Implement main.swift**

```swift
import Foundation
import IslandCore

// vibe-hook: invoked by Claude Code per event. Reads JSON on stdin, enriches with
// cmux env + tmux context, sends one JSON line to the island socket. ALWAYS exits 0.

func resolveTmux(env: [String: String], runner: CommandRunner) -> TmuxContext? {
    guard env["TMUX"] != nil else { return nil }
    let cmd = Command(executable: "tmux",
                      arguments: ["display-message", "-p", "#{pane_id}\t#{window_index}\t#{session_name}"],
                      environment: [:])
    guard let out = try? runner.run(cmd) else { return nil }
    let parts = out.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 3 else { return nil }
    return TmuxContext(pane: parts[0], window: parts[1], session: parts[2])
}

let env = ProcessInfo.processInfo.environment
let stdin = FileHandle.standardInput.readDataToEndOfFile()
let tmux = resolveTmux(env: env, runner: ProcessRunner())

if let msg = HookMessage.build(stdin: stdin, env: env, tmux: tmux),
   let line = try? JSONEncoder().encode(msg) {
    var payload = line
    payload.append(0x0A) // newline-delimited
    UnixSocketClient.send(payload, toPath: SocketPath.resolve(env: env))
}

exit(0)
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Manual smoke (no server yet — just confirm it never errors)**

Run:
```bash
echo '{"session_id":"s1","cwd":"/tmp/proj","hook_event_name":"Stop"}' | swift run vibe-hook; echo "exit=$?"
```
Expected: `exit=0` (socket connect fails silently because the app isn't running).

- [ ] **Step 4: Commit**

```bash
git add Sources/vibe-hook/main.swift
git commit -m "feat(hook): vibe-hook reads stdin+env -> JSON line over unix socket"
```

---

### Task 10: SocketServer (island target)

**Files:**
- Create: `Sources/island/SocketServer.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import IslandCore
#if canImport(Darwin)
import Darwin
#endif

/// AF_UNIX line-delimited JSON server. Accepts connections on a background thread,
/// decodes each line into a HookMessage, and delivers it on the main queue.
final class SocketServer {
    private let path: String
    private let onMessage: (HookMessage) -> Void
    private var listenFD: Int32 = -1
    private var running = false

    init(path: String, onMessage: @escaping (HookMessage) -> Void) {
        self.path = path
        self.onMessage = onMessage
    }

    func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        unlink(path) // remove stale socket

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POSIXError(.EADDRNOTAVAIL) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: bytes.count + 1) { dst in
                for (i, b) in bytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[bytes.count] = 0
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, len) }
        }
        guard bound == 0 else { close(listenFD); throw POSIXError(.EADDRINUSE) }
        guard listen(listenFD, 16) == 0 else { close(listenFD); throw POSIXError(.EADDRINUSE) }

        running = true
        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while running {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 { if running { continue } else { break } }
            handleClient(clientFD)
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
        }
        for line in buffer.split(separator: 0x0A) where !line.isEmpty {
            guard let msg = try? JSONDecoder().decode(HookMessage.self, from: Data(line)) else { continue }
            DispatchQueue.main.async { [weak self] in self?.onMessage(msg) }
        }
    }

    func stop() {
        running = false
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(path)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/island/SocketServer.swift
git commit -m "feat(app): AF_UNIX SocketServer delivering HookMessage on main queue"
```

---

### Task 11: Notifier (island target)

**Files:**
- Create: `Sources/island/Notifier.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import UserNotifications
import IslandCore

/// Wraps UNUserNotificationCenter. Requires the app to run from a bundle with a
/// CFBundleIdentifier (see Scripts/bundle.sh) — otherwise authorization is denied.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called with the sessionId attached to a notification the user clicked.
    var onClick: ((String) -> Void)?

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ request: NotificationRequest) {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = ["sessionId": request.sessionId]
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // Show banners even when the app is frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Handle clicks.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let sid = response.notification.request.content.userInfo["sessionId"] as? String {
            DispatchQueue.main.async { [weak self] in self?.onClick?(sid) }
        }
        completionHandler()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/island/Notifier.swift
git commit -m "feat(app): Notifier (UNUserNotificationCenter) with click -> sessionId"
```

---

### Task 12: Jumper (island target)

**Files:**
- Create: `Sources/island/Jumper.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import AppKit
import IslandCore

/// Executes the JumpPlan commands then brings cmux to the front.
struct Jumper {
    let runner: CommandRunner
    var cmuxBundleId = "com.cmuxterm.app"

    init(runner: CommandRunner = ProcessRunner()) { self.runner = runner }

    func jump(to session: Session) {
        for cmd in JumpPlan.commands(for: session) {
            _ = try? runner.run(cmd)   // best-effort; failures are logged by ProcessRunner caller if desired
        }
        activateCmux()
    }

    private func activateCmux() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cmuxBundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/island/Jumper.swift
git commit -m "feat(app): Jumper runs cmux/tmux commands + activates cmux"
```

---

### Task 13: AppModel (island target)

**Files:**
- Create: `Sources/island/AppModel.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import IslandCore

/// Main-actor bridge between the pure SessionStore and SwiftUI. Owns the store,
/// the notifier, and the jumper; wires socket messages -> store -> UI/notifications.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var icon: IconState = .idle

    private let store = SessionStore()
    private let notifier = Notifier()
    private let jumper = Jumper()
    private var server: SocketServer?

    func start() {
        store.clearAll()
        notifier.onClick = { [weak self] sid in self?.jump(sessionId: sid) }
        notifier.start()

        let path = SocketPath.resolve()
        let server = SocketServer(path: path) { [weak self] msg in
            self?.handle(msg)   // already delivered on main queue by SocketServer
        }
        do { try server.start() } catch { NSLog("island: socket start failed: \(error)") }
        self.server = server
    }

    func handle(_ msg: HookMessage) {
        let request = store.apply(msg, now: Date())
        refresh()
        if let request { notifier.post(request) }
    }

    func jump(sessionId: String) {
        guard let session = store.sessions[sessionId] else { return }
        jumper.jump(to: session)
    }

    private func refresh() {
        sessions = store.sessions.values.sorted { $0.lastActivity > $1.lastActivity }
        icon = store.iconState
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/island/AppModel.swift
git commit -m "feat(app): AppModel wires socket -> SessionStore -> UI + notifications"
```

---

### Task 14: MenuBarView + App entry point

**Files:**
- Create: `Sources/island/MenuBarView.swift`
- Modify: `Sources/island/main.swift`

- [ ] **Step 1: Add an icon symbol mapping (extend IconState in IslandCore)**

Append to `Sources/IslandCore/IconState.swift`:
```swift
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
```

- [ ] **Step 2: Implement `MenuBarView.swift`**

```swift
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
```

- [ ] **Step 3: Implement `main.swift`**

```swift
import SwiftUI
import IslandCore

@main
struct IslandApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(model)
        } label: {
            Image(systemName: model.icon.symbolName)
        }
        .menuBarExtraStyle(.menu)
    }

    init() {
        // _model is initialized; start it after launch via a one-shot.
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        DispatchQueue.main.async { model.start() }
    }
}
```

> Note: `@StateObject` cannot be assigned a captured instance and also started cleanly in `init`. If the executor hits a "model started twice" or lifecycle issue, replace the body of `init` with nothing and instead start the model from the scene using `.onAppear`/`.task` is unavailable on `MenuBarExtra` label; in that case add a hidden `Settings` scene or call `model.start()` from `AppModel`'s first `refresh`. Simplest robust fix: make `AppModel.start()` idempotent (guard with a `started` Bool) and call it from `init` as written. Apply the idempotency guard:

Append guard to `AppModel`:
```swift
// add stored property:  private var started = false
// at top of start():    guard !started else { return }; started = true
```

- [ ] **Step 4: Make `AppModel.start()` idempotent**

Modify `Sources/island/AppModel.swift`: add `private var started = false` next to the other stored properties, and make `start()` begin with:
```swift
        guard !started else { return }
        started = true
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 6: Commit**

```bash
git add Sources/island Sources/IslandCore/IconState.swift
git commit -m "feat(app): MenuBarExtra UI + App entry point (idempotent start)"
```

---

### Task 15: bundle.sh — assemble island.app

**Files:**
- Create: `Scripts/bundle.sh`

- [ ] **Step 1: Implement**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/island.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp ".build/release/island" "$APP/Contents/MacOS/island"
cp ".build/release/vibe-hook" "$APP/Contents/MacOS/vibe-hook"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>island</string>
  <key>CFBundleIdentifier</key><string>app.island.local</string>
  <key>CFBundleExecutable</key><string>island</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "vibe-hook path: $(pwd)/$APP/Contents/MacOS/vibe-hook"
```

- [ ] **Step 2: Make executable and run**

Run:
```bash
chmod +x Scripts/bundle.sh && ./Scripts/bundle.sh
```
Expected: prints `Built build/island.app` and the absolute `vibe-hook path:`.

- [ ] **Step 3: Launch and verify menu bar**

Run: `open build/island.app`
Expected: a menu bar icon appears (a circle), no dock icon. Clicking it shows "No active sessions" + Quit. On first launch macOS may prompt for notification permission — allow it.

- [ ] **Step 4: Commit**

```bash
git add Scripts/bundle.sh
git commit -m "build: bundle.sh assembles ad-hoc-signed island.app (LSUIElement)"
```

---

### Task 16: install-hooks.sh — register vibe-hook in Claude Code

**Files:**
- Create: `Scripts/install-hooks.sh`

- [ ] **Step 1: Implement (uses python3, always present on macOS)**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

HOOK="$(pwd)/build/island.app/Contents/MacOS/vibe-hook"
if [[ ! -x "$HOOK" ]]; then
  echo "vibe-hook not found at $HOOK — run ./Scripts/bundle.sh first" >&2
  exit 1
fi

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
python3 - "$SETTINGS" "$HOOK" <<'PY'
import json, sys, os, shutil

settings_path, hook = sys.argv[1], sys.argv[2]
events = ["SessionStart", "UserPromptSubmit", "Notification", "Stop", "SessionEnd"]

data = {}
if os.path.exists(settings_path):
    shutil.copy(settings_path, settings_path + ".island.bak")
    with open(settings_path) as f:
        data = json.load(f)

hooks = data.setdefault("hooks", {})
for ev in events:
    groups = hooks.setdefault(ev, [])
    # find/create a group whose hooks we own; idempotent on the command string
    target = None
    for g in groups:
        if isinstance(g, dict) and "hooks" in g:
            target = g; break
    if target is None:
        target = {"hooks": []}
        groups.append(target)
    cmds = [h.get("command") for h in target["hooks"] if isinstance(h, dict)]
    if hook not in cmds:
        target["hooks"].append({"type": "command", "command": hook})

with open(settings_path, "w") as f:
    json.dump(data, f, indent=2)
print("Updated", settings_path)
print("Backup at", settings_path + ".island.bak")
PY
```

- [ ] **Step 2: Make executable**

Run: `chmod +x Scripts/install-hooks.sh`
Expected: no output.

- [ ] **Step 3: Commit (do NOT run it yet — that mutates the user's settings)**

```bash
git add Scripts/install-hooks.sh
git commit -m "build: install-hooks.sh merges vibe-hook into ~/.claude/settings.json"
```

---

### Task 17: End-to-end smoke + verify the open items

**Files:** none (verification + possible small fixes).

This task confirms the three spec open items (§9) against the real environment.

- [ ] **Step 1: Confirm the cmux jump command**

Run (inside a cmux workspace whose id you know, or use `cmux --help` / `cmux select-workspace --help`):
```bash
cmux --help; cmux select-workspace --help 2>&1 | head -20
```
Expected: confirm the subcommand name/args. If it differs from `select-workspace <id>`, update `JumpPlan.commands(for:)` in `Sources/IslandCore/JumpPlan.swift` and its test in `Tests/IslandCoreTests/JumpPlanTests.swift`, then `swift test --filter JumpPlanTests`.

- [ ] **Step 2: Confirm hook env inheritance**

In a cmux shell (ideally with tmux running too), run:
```bash
env | grep -E 'CMUX_|^TMUX='
```
Expected: `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID`, `CMUX_SOCKET_PATH` present; `TMUX` present if inside tmux. If absent, the jump context can't be captured — note it and stop for a design discussion.

- [ ] **Step 3: Install hooks and run a real session**

Run:
```bash
./Scripts/install-hooks.sh
open build/island.app
```
Then in a cmux terminal, start `claude`, submit a prompt, and let it finish (or trigger a permission prompt).

Expected behaviors:
- Menu bar icon goes busy (`circle.dotted`) on prompt submit.
- A notification fires on Stop ("Done") and/or on a permission request.
- Menu dropdown lists the session with the right title.
- Clicking the notification (or the menu row) brings cmux to the front and selects the right workspace; if inside tmux, the right pane is focused.

- [ ] **Step 4: Capture results**

If all behaviors work, the v1 is functional. If a step fails, debug with `superpowers:systematic-debugging`:
- No socket delivery → check `SocketPath.resolve()` matches between app and hook; check `~/Library/Application Support/island/run.sock` exists while app runs.
- No notification → confirm the app is the bundled `island.app` (not `swift run`) and permission was granted.
- Jump no-op → re-check Step 1 cmux command; check `com.cmuxterm.app` is cmux's real bundle id via `osascript -e 'id of app "cmux"'` or `mdls`.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "test: e2e smoke verified for Claude Code + cmux (v1)" || echo "nothing to commit"
```

---

## Self-Review (completed during authoring)

- **Spec coverage:** §2 stack → Task 1; §3 components → Tasks 2–14; §4 events/state/icon → Tasks 3–5,14; §5 jump → Tasks 6,12,15; §6 error handling → Tasks 5(prune/clear),9(exit 0/timeout),10(unlink stale),12(best-effort); §7 testing → Tasks 2–8 (unit) + 17 (e2e); §9 open items → Task 17. All covered.
- **Placeholders:** none — every code step is complete. The two `init`-lifecycle notes in Task 14 are resolved by the idempotency guard (Step 4), not left open.
- **Type consistency:** `HookMessage.build`, `SessionStore.apply`, `JumpPlan.commands(for:)`, `Command(executable:arguments:environment:)`, `IconState.aggregate`, `SocketPath.resolve`, `CommandRunner.run` names match across all tasks and tests.
