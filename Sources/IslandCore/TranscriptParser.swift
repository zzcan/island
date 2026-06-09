import Foundation

public enum TranscriptParser {
    /// Returns the last non-empty assistant text block from a Claude Code JSONL transcript.
    public static func latestAssistantText(jsonl: String) -> String? {
        var result: String? = nil
        for line in jsonl.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else { continue }
            for block in content where (block["type"] as? String) == "text" {
                if let t = (block["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    result = t
                }
            }
        }
        return result
    }
}
