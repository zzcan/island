import Testing
import Foundation
@testable import IslandCore

@Suite struct HookMessageTests {
    @Test func islandEventRawValues() {
        #expect(IslandEvent(claudeName: "SessionStart") == .sessionStart)
        #expect(IslandEvent(claudeName: "UserPromptSubmit") == .userPromptSubmit)
        #expect(IslandEvent(claudeName: "Notification") == .notification)
        #expect(IslandEvent(claudeName: "Stop") == .stop)
        #expect(IslandEvent(claudeName: "SessionEnd") == .sessionEnd)
        #expect(IslandEvent(claudeName: "PreToolUse") == nil)
    }

    @Test func decodeClaudeInput() throws {
        let json = #"{"session_id":"abc","cwd":"/x/proj","hook_event_name":"Notification","message":"need perms"}"#
        let input = try ClaudeHookInput.decode(Data(json.utf8))
        #expect(input.session_id == "abc")
        #expect(input.cwd == "/x/proj")
        #expect(input.hook_event_name == "Notification")
        #expect(input.message == "need perms")
    }

    @Test func decodeToleratesMissingFields() throws {
        let json = #"{"hook_event_name":"Stop","session_id":"s1"}"#
        let input = try ClaudeHookInput.decode(Data(json.utf8))
        #expect(input.session_id == "s1")
        #expect(input.cwd == nil)
        #expect(input.message == nil)
    }
}
