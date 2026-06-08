# island v1.1 Floating Island — Implementation Plan

> **For agentic workers:** implement task-by-task. `IslandCore` logic is TDD with Swift Testing; the panel/view glue is verified by `swift build` + manual smoke (no unit tests), same as v1's glue layer.

**Goal:** Add a Dynamic-Island-style floating overlay (top-center capsule that hover-expands into a session list, click to jump), bound to the existing `AppModel`.

**Build env:** `SW=/opt/homebrew/opt/swift/bin/swift` (see docs/superpowers/ENVIRONMENT.md). Package is Swift 6 / macOS 15. Tests use Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-08-floating-island-design.md`.

---

### Task A: IslandViewModel (IslandCore, pure, TDD)

**Files:**
- Create: `Sources/IslandCore/IslandViewModel.swift`
- Test: `Tests/IslandCoreTests/IslandViewModelTests.swift`

- [ ] **Step 1: Write failing tests (Swift Testing)**

`Tests/IslandCoreTests/IslandViewModelTests.swift`:
```swift
import Testing
import Foundation
@testable import IslandCore

@Suite struct IslandViewModelTests {
    private func session(_ id: String, _ status: SessionStatus, _ t: TimeInterval, title: String = "t") -> Session {
        Session(id: id, title: title, cwd: nil, status: status,
                cmux: nil, tmux: nil, lastActivity: Date(timeIntervalSince1970: t))
    }

    @Test func emptyIsHidden() {
        let d = IslandDisplay.from([])
        #expect(d.hidden == true)
        #expect(d.pillCount == 0)
        #expect(d.rows.isEmpty)
        #expect(d.pillSymbol == IconState.idle.symbolName)
    }

    @Test func pillReflectsAggregate() {
        let d = IslandDisplay.from([session("a", .working, 1), session("b", .done, 2)])
        #expect(d.hidden == false)
        #expect(d.pillCount == 2)
        #expect(d.pillSymbol == IconState.attention.symbolName) // a .done present
    }

    @Test func rowsSortedByLastActivityDesc() {
        let d = IslandDisplay.from([session("old", .idle, 1), session("new", .idle, 9)])
        #expect(d.rows.map(\.id) == ["new", "old"])
    }

    @Test func rowsMapTitleAndStatus() {
        let d = IslandDisplay.from([session("a", .needsInput, 1, title: "proj")])
        #expect(d.rows.first == IslandRow(id: "a", title: "proj", status: .needsInput))
    }
}
```

- [ ] **Step 2: Run, verify fail** — `$SW test --filter IslandViewModelTests` → fail (types undefined).

- [ ] **Step 3: Implement** `Sources/IslandCore/IslandViewModel.swift`:
```swift
import Foundation

public struct IslandRow: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: SessionStatus
    public init(id: String, title: String, status: SessionStatus) {
        self.id = id; self.title = title; self.status = status
    }
}

public struct IslandDisplay: Equatable, Sendable {
    public let hidden: Bool
    public let pillSymbol: String
    public let pillCount: Int
    public let rows: [IslandRow]
    public init(hidden: Bool, pillSymbol: String, pillCount: Int, rows: [IslandRow]) {
        self.hidden = hidden; self.pillSymbol = pillSymbol; self.pillCount = pillCount; self.rows = rows
    }

    /// Pure mapping from sessions to the floating-island display model. Sorts by recency.
    public static func from(_ sessions: [Session]) -> IslandDisplay {
        let sorted = sessions.sorted { $0.lastActivity > $1.lastActivity }
        return IslandDisplay(
            hidden: sorted.isEmpty,
            pillSymbol: IconState.aggregate(sorted).symbolName,
            pillCount: sorted.count,
            rows: sorted.map { IslandRow(id: $0.id, title: $0.title, status: $0.status) })
    }
}
```

- [ ] **Step 4: Run, verify pass** — `$SW test --filter IslandViewModelTests` → 4 pass. Then `$SW test` → 29 total.

- [ ] **Step 5: Commit**
```bash
git add Sources/IslandCore/IslandViewModel.swift Tests/IslandCoreTests/IslandViewModelTests.swift
git commit -m "feat(core): IslandViewModel (IslandDisplay/IslandRow) pure mapping"
```

---

### Task B: AppModel exposes display + auto-expand tick

**Files:**
- Modify: `Sources/island/AppModel.swift`

- [ ] **Step 1: Add published properties + update logic**

In `AppModel`, add stored published properties:
```swift
    @Published private(set) var display: IslandDisplay = .from([])
    @Published private(set) var eventTick: Int = 0
```
In `refresh()`, after updating `sessions`/`icon`, add:
```swift
        display = IslandDisplay.from(Array(store.sessions.values))
```
In `handle(_:)`, when a notification request is produced, bump the tick:
```swift
    func handle(_ msg: HookMessage) {
        let request = store.apply(msg, now: Date())
        refresh()
        if let request {
            eventTick &+= 1
            notifier.post(request)
        }
    }
```

- [ ] **Step 2: Build** — `$SW build` → clean.

- [ ] **Step 3: Commit**
```bash
git add Sources/island/AppModel.swift
git commit -m "feat(app): AppModel publishes IslandDisplay + eventTick for floating island"
```

---

### Task C: FloatingIslandPanel + IslandView + wiring

**Files:**
- Create: `Sources/island/FloatingIslandPanel.swift`
- Create: `Sources/island/IslandView.swift`
- Modify: `Sources/island/IslandApp.swift`

This is GUI glue (no unit tests) — verify by `$SW build` and the Task D smoke. The code below is a working baseline; you may make minimal adjustments to satisfy the Swift 6 concurrency checker or AppKit reality — note any deviation.

- [ ] **Step 1: `IslandView.swift`**
```swift
import SwiftUI
import IslandCore

struct IslandView: View {
    @EnvironmentObject var model: AppModel
    @State private var hovering = false
    @State private var autoExpand = false

    private var expanded: Bool { hovering || autoExpand }

    var body: some View {
        VStack(spacing: 0) {
            if !model.display.hidden { island }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: model.eventTick) { _, _ in
            autoExpand = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if !hovering { autoExpand = false }
            }
        }
    }

    private var island: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: model.display.pillSymbol)
                if model.display.pillCount > 1 {
                    Text("\(model.display.pillCount)").font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)

            if expanded {
                VStack(spacing: 2) {
                    ForEach(model.display.rows) { row in
                        Button { model.jump(sessionId: row.id) } label: {
                            HStack(spacing: 8) {
                                Circle().fill(color(row.status)).frame(width: 8, height: 8)
                                Text(row.title).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .frame(width: 280, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.white)
        .fixedSize()
        .onHover { h in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { hovering = h }
            if !h {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if !hovering { autoExpand = false }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: expanded)
    }

    private func color(_ s: SessionStatus) -> Color {
        switch s {
        case .idle: return .gray
        case .working: return .yellow
        case .needsInput: return .blue
        case .done: return .green
        }
    }
}
```

- [ ] **Step 2: `FloatingIslandPanel.swift`**
```swift
import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that hosts the IslandView at the
/// top-center of the main screen. Non-activating so hovering/clicking it never
/// steals focus from the user's terminal.
@MainActor
final class FloatingIslandPanel {
    private let panel: NSPanel

    init(appModel: AppModel) {
        let hosting = NSHostingView(rootView: IslandView().environmentObject(appModel))
        // Fixed generous canvas; the island draws top-center, the rest is transparent.
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 360),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        hosting.frame = panel.contentLayoutRect
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        reposition()
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2,
                                     y: vf.maxY - size.height))
    }
}
```

> **Open item (implementer judgment, verify in Task D):** With a fixed 360×360 transparent panel, the transparent region may intercept clicks meant for apps behind it near the top-center of the screen. If Task D's smoke shows this is a problem, switch to a **dynamic-resize** approach: report the island's rendered size out of `IslandView` (e.g. via a `GeometryReader` + preference key or an `onChange` callback) and have `FloatingIslandPanel` shrink the panel to just the island's bounds (and `reposition()` after each resize). Prefer the simplest thing that doesn't block background clicks. Note what you chose.

- [ ] **Step 3: Wire into `IslandApp.swift` via an AppDelegate (owns model + panel for app lifetime)**

Replace `Sources/island/IslandApp.swift` with:
```swift
import SwiftUI
import IslandCore

@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(delegate.model)
        } label: {
            Image(systemName: delegate.model.icon.symbolName)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var islandPanel: FloatingIslandPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        let panel = FloatingIslandPanel(appModel: model)
        panel.show()
        islandPanel = panel
    }
}
```

> Note: this supersedes v1's `init()`-based start. The idempotency guard in `AppModel.start()` stays. If the MenuBarExtra `label` does not update live with `delegate.model.icon` (a known SwiftUI quirk when the model isn't directly observed by the scene), that's acceptable for v1.1 — the floating island (which observes the model via `@EnvironmentObject`) is the primary live surface. Do not over-engineer the menu-bar label reactivity; note it as a known limitation if it doesn't update.

- [ ] **Step 4: Build** — `$SW build` → clean. Resolve any Swift 6 concurrency error minimally (e.g. `MainActor` annotations) and note it.

- [ ] **Step 5: Commit**
```bash
git add Sources/island/FloatingIslandPanel.swift Sources/island/IslandView.swift Sources/island/IslandApp.swift
git commit -m "feat(app): floating Dynamic-Island-style panel (top capsule, hover-expand)"
```

---

### Task D: Rebundle + manual smoke

**Files:** none (verification).

- [ ] **Step 1: Full suite + build**
Run: `$SW test` (expect 29 passing) and `./Scripts/bundle.sh` (expect "Built build/island.app").

- [ ] **Step 2: Launch + synthetic events**
```bash
open build/island.app; sleep 2
HOOK=build/island.app/Contents/MacOS/vibe-hook
echo '{"session_id":"isl-1","cwd":"/tmp/alpha","hook_event_name":"UserPromptSubmit"}' | "$HOOK"
echo '{"session_id":"isl-2","cwd":"/tmp/beta","hook_event_name":"Stop"}' | "$HOOK"
```
Expected (visual): a capsule appears top-center of the main screen showing the aggregate status; on a new event it auto-expands ~3s; hovering it expands into rows "alpha"/"beta"; clicking a row attempts a cmux jump. The capsule hides when no sessions remain (send `SessionEnd` for both to verify).

- [ ] **Step 3: Record results.** If the transparent panel blocks background clicks (open item in Task C Step 2), apply the dynamic-resize fix and re-verify. Note the outcome.

- [ ] **Step 4: Commit any fixes** with a descriptive message.

---

## Self-Review (authoring)
- Spec coverage: IslandViewModel → Task A; AppModel display/tick → Task B; panel+view+wiring → Task C; smoke + open items → Task D. Covered.
- Placeholders: none; Task A has full TDD code. Tasks B/C are concrete code; the two GUI open items (click-through, label reactivity) are explicitly delegated to implementer judgment with Task D verification, consistent with v1's glue handling.
- Type consistency: `IslandDisplay.from(_:)`, `IslandRow(id:title:status:)`, `AppModel.display`/`eventTick`, `IconState.symbolName`, `AppModel.jump(sessionId:)` match v1 APIs.
