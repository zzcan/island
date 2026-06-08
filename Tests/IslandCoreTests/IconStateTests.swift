import Testing
import Foundation
@testable import IslandCore

@Suite struct IconStateTests {
    private func session(_ status: SessionStatus) -> Session {
        Session(id: UUID().uuidString, title: "t", cwd: nil, status: status,
                cmux: nil, tmux: nil, lastActivity: Date(timeIntervalSince1970: 0))
    }

    @Test func emptyIsIdle() {
        #expect(IconState.aggregate([]) == .idle)
    }

    @Test func anyWorkingIsBusy() {
        #expect(IconState.aggregate([session(.idle), session(.working)]) == .busy)
    }

    @Test func needsInputBeatsWorking() {
        #expect(IconState.aggregate([session(.working), session(.needsInput)]) == .attention)
    }

    @Test func doneIsAttention() {
        #expect(IconState.aggregate([session(.done)]) == .attention)
    }
}
