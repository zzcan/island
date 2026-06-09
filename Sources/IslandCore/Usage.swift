import Foundation

/// One rate-limit window from Anthropic's /api/oauth/usage response.
public struct UsageWindow: Equatable, Sendable {
    public let utilization: Double   // 0–100
    public let resetsAt: Date
    public init(utilization: Double, resetsAt: Date) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// Subscription usage as shown in the island's usage bar. Only the two windows the
/// UI renders (5-hour session + 7-day weekly) are modeled; the response carries more.
public struct Usage: Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    /// Decodes the GET /api/oauth/usage body. Tolerant: unknown/null windows are
    /// ignored, and a window missing utilization or resets_at decodes to nil.
    public static func decode(_ data: Data) -> Usage? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Usage(fiveHour: window(obj["five_hour"]), sevenDay: window(obj["seven_day"]))
    }

    private static func window(_ any: Any?) -> UsageWindow? {
        guard let d = any as? [String: Any],
              let u = (d["utilization"] as? NSNumber)?.doubleValue,
              let s = d["resets_at"] as? String,
              let date = parseDate(s) else { return nil }
        return UsageWindow(utilization: u, resetsAt: date)
    }

    /// Parses an ISO-8601 timestamp, with or without fractional seconds
    /// (e.g. "2026-06-09T12:00:00.180558+00:00").
    public static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Pure presentation helpers for the usage bar (kept SwiftUI-free for testing).
public enum UsageFormat {
    /// Rounded percentage label, e.g. 16.0 → "16%".
    public static func percent(_ utilization: Double) -> String {
        "\(Int(utilization.rounded()))%"
    }

    /// Compact time-until-reset, e.g. "46m", "3h12m", "5d9h", "<1m".
    public static func remaining(until resetsAt: Date, now: Date) -> String {
        let secs = Int(resetsAt.timeIntervalSince(now))
        if secs <= 60 { return "<1m" }
        let days = secs / 86_400
        let hours = (secs % 86_400) / 3_600
        let mins = (secs % 3_600) / 60
        if days > 0 { return hours > 0 ? "\(days)d\(hours)h" : "\(days)d" }
        if hours > 0 { return mins > 0 ? "\(hours)h\(mins)m" : "\(hours)h" }
        return "\(mins)m"
    }
}

/// Colour category for a utilization percentage; UI maps to a concrete colour.
public enum UsageTint: String, Equatable, Sendable {
    case ok    // plenty left
    case warn  // getting close
    case crit  // nearly exhausted

    public static func from(_ utilization: Double) -> UsageTint {
        if utilization >= 90 { return .crit }
        if utilization >= 70 { return .warn }
        return .ok
    }
}
