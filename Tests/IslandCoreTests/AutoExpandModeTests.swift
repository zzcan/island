import Testing
@testable import IslandCore

@Suite struct AutoExpandModeTests {
    @Test func allExpandsForNotifyingStatuses() {
        let m = AutoExpandMode.all
        #expect(m.shouldExpand(for: .needsInput))
        #expect(m.shouldExpand(for: .done))
        #expect(!m.shouldExpand(for: .working))
        #expect(!m.shouldExpand(for: .idle))
    }

    @Test func actionableExpandsOnlyForNeedsInput() {
        let m = AutoExpandMode.actionable
        #expect(m.shouldExpand(for: .needsInput))
        #expect(!m.shouldExpand(for: .done))
        #expect(!m.shouldExpand(for: .working))
        #expect(!m.shouldExpand(for: .idle))
    }

    @Test func neverExpandsForNothing() {
        let m = AutoExpandMode.never
        #expect(!m.shouldExpand(for: .needsInput))
        #expect(!m.shouldExpand(for: .done))
        #expect(!m.shouldExpand(for: .working))
        #expect(!m.shouldExpand(for: .idle))
    }

    @Test func planReviewFollowsMode() {
        #expect(AutoExpandMode.all.expandsForPlanReview)
        #expect(AutoExpandMode.actionable.expandsForPlanReview)
        #expect(!AutoExpandMode.never.expandsForPlanReview)
    }

    @Test func rawValuesAreStable() {
        // 持久化在 UserDefaults 里的就是这些原始值，不可改动。
        #expect(AutoExpandMode(rawValue: 0) == .all)
        #expect(AutoExpandMode(rawValue: 1) == .actionable)
        #expect(AutoExpandMode(rawValue: 2) == .never)
        #expect(AutoExpandMode(rawValue: 99) == nil)
    }
}
