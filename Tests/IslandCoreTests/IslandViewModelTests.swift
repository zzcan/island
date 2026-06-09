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
        #expect(d.rows.first == IslandRow(id: "a", title: "proj", status: .needsInput, lastActivity: Date(timeIntervalSince1970: 1)))
    }

    @Test func rowsMapscwdAndAction() {
        var s = Session(id: "s1", title: "proj", cwd: "/Users/me/proj", status: .working,
                        cmux: nil, tmux: nil, lastActivity: Date(timeIntervalSince1970: 1),
                        lastAction: "Read src/main.ts")
        let d = IslandDisplay.from([s])
        #expect(d.rows.first?.cwd == "/Users/me/proj")
        #expect(d.rows.first?.action == "Read src/main.ts")
    }
}
