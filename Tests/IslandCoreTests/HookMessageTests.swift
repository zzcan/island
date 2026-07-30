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
        let input = try AgentHookInput.decode(Data(json.utf8))
        #expect(input.session_id == "abc")
        #expect(input.cwd == "/x/proj")
        #expect(input.hook_event_name == "Notification")
        #expect(input.message == "need perms")
    }

    @Test func decodeToleratesMissingFields() throws {
        let json = #"{"hook_event_name":"Stop","session_id":"s1"}"#
        let input = try AgentHookInput.decode(Data(json.utf8))
        #expect(input.session_id == "s1")
        #expect(input.cwd == nil)
        #expect(input.message == nil)
    }

    @Test func decodeCodexFields() throws {
        let json = #"{"session_id":"thr_123","hook_event_name":"Stop","model":"gpt-5.6-sol","permission_mode":"default","last_assistant_message":"Implemented and tested."}"#
        let input = try AgentHookInput.decode(Data(json.utf8))
        #expect(input.model == "gpt-5.6-sol")
        #expect(input.permission_mode == "default")
        #expect(input.last_assistant_message == "Implemented and tested.")
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

    @Test func buildComposesAction() {
        let json = #"{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Read","tool_input":{"file_path":"/tmp/a/b.ts"}}"#
        let msg = HookMessage.build(stdin: Data(json.utf8), env: [:], tmux: nil)
        #expect(msg?.action == "Read a/b.ts")
    }

    @Test func buildComposesActionForBash() {
        let json = #"{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
        let msg = HookMessage.build(stdin: Data(json.utf8), env: [:], tmux: nil)
        #expect(msg?.action == "Bash npm test")
    }

    @Test func shortenArgTruncatesNonPath() {
        let longStr = String(repeating: "x", count: 50)
        let result = HookMessage.shortenArg(longStr)
        #expect(result.count == 40)
    }

    @Test func shortenArgLastTwoComponents() {
        #expect(HookMessage.shortenArg("/tmp/a/b.ts") == "a/b.ts")
    }

    @Test func postToolUseEventRecognized() {
        #expect(IslandEvent(claudeName: "PostToolUse") == .postToolUse)
    }

    @Test func buildCapturesPermissionMode() {
        let json = #"{"session_id":"s1","hook_event_name":"PostToolUse","permission_mode":"bypassPermissions"}"#
        let msg = HookMessage.build(stdin: Data(json.utf8), env: [:], tmux: nil)
        #expect(msg?.permissionMode == "bypassPermissions")
    }

    @Test func buildCodexMessageUsesStableHookFields() {
        let json = #"{"session_id":"thr_123","cwd":"/Users/me/proj","hook_event_name":"Stop","model":"gpt-5.6-sol","last_assistant_message":"Done."}"#
        let msg = HookMessage.build(stdin: Data(json.utf8), env: [:], tmux: nil,
                                    provider: .codex)
        #expect(msg?.provider == .codex)
        #expect(msg?.model == "gpt-5.6-sol")
        #expect(msg?.assistantText == "Done.")
    }

    @Test func codexPermissionRequestBecomesNonBlockingNotification() {
        let json = #"{"session_id":"thr_123","cwd":"/Users/me/proj","hook_event_name":"PermissionRequest","model":"gpt-5.6-sol","tool_name":"Bash","tool_input":{"command":"git push","description":"Push changes to origin"}}"#
        let input = try! AgentHookInput.decode(Data(json.utf8))
        let msg = HookMessage.codexPermissionNotification(input: input, env: [:],
                                                          tmux: nil)
        #expect(msg?.event == .notification)
        #expect(msg?.provider == .codex)
        #expect(msg?.message == "Push changes to origin")
        #expect(msg?.action == "Bash git push")
    }
}
