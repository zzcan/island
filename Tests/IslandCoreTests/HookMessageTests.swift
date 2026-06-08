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

    @Test func buildMessageReadsCmuxFromEnv() throws {
        let json = #"{"session_id":"s1","cwd":"/Users/me/proj","hook_event_name":"UserPromptSubmit"}"#
        let env = [
            "CMUX_WORKSPACE_ID": "ws1",
            "CMUX_SURFACE_ID": "sf1",
            "CMUX_SOCKET_PATH": "/tmp/cmux.sock",
        ]
        let msg = HookMessage.build(stdin: Data(json.utf8), env: env, tmux: nil)
        #expect(msg?.event == .userPromptSubmit)
        #expect(msg?.sessionId == "s1")
        #expect(msg?.title == "proj")              // last path component of cwd
        #expect(msg?.cmux?.workspaceId == "ws1")
        #expect(msg?.cmux?.surfaceId == "sf1")
        #expect(msg?.cmux?.socketPath == "/tmp/cmux.sock")
        #expect(msg?.tmux == nil)
    }

    @Test func buildMessageNilWhenNoSessionId() {
        let json = #"{"hook_event_name":"Stop"}"#
        #expect(HookMessage.build(stdin: Data(json.utf8), env: [:], tmux: nil) == nil)
    }

    @Test func buildMessageNilWhenUnknownEvent() {
        let json = #"{"session_id":"s1","hook_event_name":"PreToolUse"}"#
        #expect(HookMessage.build(stdin: Data(json.utf8), env: [:], tmux: nil) == nil)
    }

    @Test func buildMessageNilWhenNoCmuxEnv() {
        // No CMUX_* env -> cmux nil but message still built (jump just won't work).
        let json = #"{"session_id":"s1","hook_event_name":"Stop"}"#
        let msg = HookMessage.build(stdin: Data(json.utf8), env: [:], tmux: nil)
        #expect(msg != nil)
        #expect(msg?.cmux == nil)
    }

    @Test func hookMessageRoundTripsJSON() throws {
        let original = HookMessage(event: .stop, sessionId: "s1", cwd: "/a/b", title: "b",
                                   message: nil,
                                   cmux: CmuxContext(workspaceId: "w", surfaceId: nil, socketPath: "/tmp/c.sock"),
                                   tmux: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HookMessage.self, from: data)
        #expect(decoded == original)
    }

    @Test func buildCapturesPrompt() {
        let json = #"{"session_id":"s1","hook_event_name":"UserPromptSubmit","prompt":"hello world"}"#
        let msg = HookMessage.build(stdin: Data(json.utf8), env: [:], tmux: nil)
        #expect(msg?.prompt == "hello world")
    }
}
