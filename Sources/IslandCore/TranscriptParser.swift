import Foundation

public enum TranscriptParser {
    /// Single pass over a Claude Code JSONL transcript returning the last non-empty
    /// assistant text block and the model id of the most recent assistant message
    /// (reflects a mid-session /model switch). `model` is captured from every assistant
    /// message that carries it — independent of text — so a tool-use-only final turn
    /// still updates it.
    public static func latest(jsonl: String) -> (text: String?, model: String?) {
        var text: String? = nil
        var model: String? = nil
        for line in jsonl.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let message = obj["message"] as? [String: Any] else { continue }
            if let m = (message["model"] as? String), !m.isEmpty { model = m }
            guard let content = message["content"] as? [[String: Any]] else { continue }
            for block in content where (block["type"] as? String) == "text" {
                if let t = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    text = t
                }
            }
        }
        return (text, model)
    }

    /// Returns the last non-empty assistant text block from a Claude Code JSONL transcript.
    public static func latestAssistantText(jsonl: String) -> String? {
        latest(jsonl: jsonl).text
    }

    /// Returns the model id of the most recent assistant message, e.g. "claude-opus-4-8".
    public static func latestAssistantModel(jsonl: String) -> String? {
        latest(jsonl: jsonl).model
    }
}
