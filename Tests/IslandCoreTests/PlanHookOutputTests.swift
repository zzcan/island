import Testing
import Foundation
@testable import IslandCore

@Suite struct PlanHookOutputTests {
    private func parse(_ s: String) -> [String: Any] {
        let d = try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any]
        return d
    }
    private func decision(_ s: String) -> [String: Any] {
        let hso = parse(s)["hookSpecificOutput"] as! [String: Any]
        #expect(hso["hookEventName"] as? String == "PermissionRequest")
        return hso["decision"] as! [String: Any]
    }

    @Test func allowManualHasNoModeChange() {
        let json = PlanHookOutput.json(reply: .allow)!
        let d = decision(json)
        #expect(d["behavior"] as? String == "allow")
        #expect(d["updatedPermissions"] == nil)   // keep pre-plan mode
    }

    @Test func allowAcceptEditsSetsMode() {
        let json = PlanHookOutput.json(reply: .allow(mode: "acceptEdits"))!
        let d = decision(json)
        #expect(d["behavior"] as? String == "allow")
        let perms = d["updatedPermissions"] as! [[String: Any]]
        #expect(perms.count == 1)
        #expect(perms[0]["type"] as? String == "setMode")
        #expect(perms[0]["mode"] as? String == "acceptEdits")
        #expect(perms[0]["destination"] as? String == "session")
    }

    @Test func allowBypassSetsMode() {
        let d = decision(PlanHookOutput.json(reply: .allow(mode: "bypassPermissions"))!)
        let perms = d["updatedPermissions"] as! [[String: Any]]
        #expect(perms[0]["mode"] as? String == "bypassPermissions")
    }

    @Test func denyCarriesFeedback() {
        let json = PlanHookOutput.json(reply: .deny(reason: "改用方案 B"))!
        let d = decision(json)
        #expect(d["behavior"] as? String == "deny")
        #expect(d["permissionDecisionReason"] as? String == "改用方案 B")
        #expect(d["reason"] as? String == "改用方案 B")
    }

    @Test func deferProducesNoOutput() {
        #expect(PlanHookOutput.json(reply: .defer_) == nil)
    }

    @Test func replyRoundTripsJSON() throws {
        let r = PermissionReply.allow(mode: "acceptEdits")
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(PermissionReply.self, from: data)
        #expect(back == r)
    }
}
