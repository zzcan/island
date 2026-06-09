import Testing
import Foundation
@testable import IslandCore

@Suite struct TaskAndTranscriptTests {

    // MARK: - TaskItem decoding

    @Test func taskItemDecodesFromFullJSON() throws {
        let json = #"""
        {"id":"34","subject":"Fix the bug","description":"Long desc","status":"in_progress","blocks":[],"blockedBy":[]}
        """#
        let item = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        #expect(item.id == "34")
        #expect(item.subject == "Fix the bug")
        #expect(item.status == "in_progress")
    }

    @Test func taskItemDecodesExtraKeysIgnored() throws {
        let json = #"""
        {"id":"1","subject":"Setup project","status":"completed","blocks":["2"],"blockedBy":[],"description":"Do the thing","extra":"ignored"}
        """#
        let item = try JSONDecoder().decode(TaskItem.self, from: Data(json.utf8))
        #expect(item.id == "1")
        #expect(item.subject == "Setup project")
        #expect(item.status == "completed")
    }

    // MARK: - TaskSummary

    @Test func taskSummaryCounts() {
        let tasks: [TaskItem] = [
            TaskItem(id: "1", subject: "A", status: "completed"),
            TaskItem(id: "2", subject: "B", status: "completed"),
            TaskItem(id: "3", subject: "C", status: "in_progress"),
            TaskItem(id: "4", subject: "D", status: "pending"),
            TaskItem(id: "5", subject: "E", status: "pending"),
        ]
        let summary = TaskSummary.from(tasks)
        #expect(summary.completed == 2)
        #expect(summary.inProgress == 1)
        #expect(summary.pending == 2)
    }

    @Test func taskSummaryEmptyArray() {
        let summary = TaskSummary.from([])
        #expect(summary.completed == 0)
        #expect(summary.inProgress == 0)
        #expect(summary.pending == 0)
    }

    // MARK: - TranscriptParser

    @Test func latestAssistantTextReturnsLastOfTwo() {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"First response"}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Follow up"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Second response"}]}}
        """
        let result = TranscriptParser.latestAssistantText(jsonl: jsonl)
        #expect(result == "Second response")
    }

    @Test func latestAssistantTextNilWhenOnlyUserLines() {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Hello"}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"Are you there?"}]}}
        """
        let result = TranscriptParser.latestAssistantText(jsonl: jsonl)
        #expect(result == nil)
    }

    @Test func latestAssistantTextSkipsToolUseOnlyLines() {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Before tool"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"ls"}}]}}
        """
        // The tool_use-only assistant line has no text block, so last text remains "Before tool"
        let result = TranscriptParser.latestAssistantText(jsonl: jsonl)
        #expect(result == "Before tool")
    }

    @Test func latestAssistantTextSkipsEmptyText() {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Real content"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"   "}]}}
        """
        // Whitespace-only text trimmed to empty → skipped
        let result = TranscriptParser.latestAssistantText(jsonl: jsonl)
        #expect(result == "Real content")
    }

    @Test func latestAssistantTextNilOnEmptyInput() {
        let result = TranscriptParser.latestAssistantText(jsonl: "")
        #expect(result == nil)
    }

    @Test func latestAssistantModelReturnsMostRecent() {
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-6","content":[{"type":"text","text":"hi"}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"switch"}]}}
        {"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-8","content":[{"type":"text","text":"ok"}]}}
        """
        #expect(TranscriptParser.latestAssistantModel(jsonl: jsonl) == "claude-opus-4-8")
    }

    @Test func latestAssistantModelFromToolUseOnlyTurn() {
        // The newest assistant turn has only a tool_use block but still carries a model.
        let jsonl = """
        {"type":"assistant","message":{"role":"assistant","model":"claude-sonnet-4-6","content":[{"type":"text","text":"hi"}]}}
        {"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-8","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}
        """
        let latest = TranscriptParser.latest(jsonl: jsonl)
        #expect(latest.model == "claude-opus-4-8")   // model updates from the tool-use turn
        #expect(latest.text == "hi")                 // text stays at the last text block
    }

    @Test func latestAssistantModelNilWhenAbsent() {
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"no model field"}]}}"#
        #expect(TranscriptParser.latestAssistantModel(jsonl: jsonl) == nil)
    }
}
