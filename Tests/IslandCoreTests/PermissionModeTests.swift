import Testing
@testable import IslandCore

@Suite struct PermissionModeTests {
    @Test func knownModesMapToLabelAndTint() {
        #expect(PermissionMode.from("default")           == PermissionMode(label: "默认", tint: .neutral))
        #expect(PermissionMode.from("plan")              == PermissionMode(label: "计划", tint: .plan))
        #expect(PermissionMode.from("acceptEdits")       == PermissionMode(label: "接受编辑", tint: .edits))
        #expect(PermissionMode.from("auto")              == PermissionMode(label: "自动", tint: .auto))
        #expect(PermissionMode.from("dontAsk")           == PermissionMode(label: "不询问", tint: .auto))
        #expect(PermissionMode.from("bypassPermissions") == PermissionMode(label: "自动批准", tint: .full))
    }

    @Test func nilOrEmptyYieldsNoBadge() {
        #expect(PermissionMode.from(nil) == nil)
        #expect(PermissionMode.from("") == nil)
    }

    @Test func unknownModeShownVerbatimNeutral() {
        #expect(PermissionMode.from("futureMode") == PermissionMode(label: "futureMode", tint: .neutral))
    }
}
