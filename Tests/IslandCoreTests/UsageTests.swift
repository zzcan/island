import Testing
import Foundation
@testable import IslandCore

@Suite struct UsageTests {
    // Real shape captured from GET /api/oauth/usage.
    let sample = #"""
    {
      "five_hour": { "utilization": 16.0, "resets_at": "2026-06-09T12:00:00.180558+00:00" },
      "seven_day": { "utilization": 11.0, "resets_at": "2026-06-13T21:00:00.180584+00:00" },
      "seven_day_opus": null,
      "seven_day_sonnet": { "utilization": 2.0, "resets_at": "2026-06-13T21:00:01.180593+00:00" },
      "extra_usage": { "is_enabled": false, "monthly_limit": null }
    }
    """#

    @Test func decodesFiveHourAndSevenDay() {
        let usage = Usage.decode(Data(sample.utf8))
        #expect(usage?.fiveHour?.utilization == 16.0)
        #expect(usage?.sevenDay?.utilization == 11.0)
        // resets_at parsed into a real Date.
        #expect(usage?.fiveHour?.resetsAt == Usage.parseDate("2026-06-09T12:00:00.180558+00:00"))
    }

    @Test func decodeToleratesNullAndMissingWindows() {
        let json = #"{"five_hour": null, "extra_usage": {}}"#
        let usage = Usage.decode(Data(json.utf8))
        #expect(usage?.fiveHour == nil)
        #expect(usage?.sevenDay == nil)
    }

    @Test func decodeNilOnGarbage() {
        #expect(Usage.decode(Data("not json".utf8)) == nil)
    }

    @Test func parseDateWithAndWithoutFractionalSeconds() {
        #expect(Usage.parseDate("2026-06-13T21:00:00+00:00") != nil)
        #expect(Usage.parseDate("2026-06-13T21:00:00.123456+00:00") != nil)
        #expect(Usage.parseDate("garbage") == nil)
    }

    @Test func percentRounds() {
        #expect(UsageFormat.percent(16.0) == "16%")
        #expect(UsageFormat.percent(11.4) == "11%")
        #expect(UsageFormat.percent(89.6) == "90%")
    }

    @Test func remainingFormatting() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        #expect(UsageFormat.remaining(until: base.addingTimeInterval(46 * 60), now: base) == "46m")
        #expect(UsageFormat.remaining(until: base.addingTimeInterval(3 * 3600 + 12 * 60), now: base) == "3h12m")
        #expect(UsageFormat.remaining(until: base.addingTimeInterval(5 * 86_400 + 9 * 3600), now: base) == "5d9h")
        #expect(UsageFormat.remaining(until: base.addingTimeInterval(2 * 86_400), now: base) == "2d")
        #expect(UsageFormat.remaining(until: base.addingTimeInterval(30), now: base) == "<1m")
        #expect(UsageFormat.remaining(until: base, now: base) == "<1m")
    }

    @Test func tintThresholds() {
        #expect(UsageTint.from(0) == .ok)
        #expect(UsageTint.from(69.9) == .ok)
        #expect(UsageTint.from(70) == .warn)
        #expect(UsageTint.from(89.9) == .warn)
        #expect(UsageTint.from(90) == .crit)
        #expect(UsageTint.from(100) == .crit)
    }
}
