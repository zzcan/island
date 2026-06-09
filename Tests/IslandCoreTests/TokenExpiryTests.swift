import Testing
import Foundation
@testable import IslandCore

@Suite struct TokenExpiryTests {
    @Test func normalizesMillisecondsAndSeconds() {
        let ms = TokenExpiry.date(fromEpoch: 1_780_000_000_000)   // ms
        let s  = TokenExpiry.date(fromEpoch: 1_780_000_000)       // s
        #expect(ms == s)
        #expect(ms == Date(timeIntervalSince1970: 1_780_000_000))
    }

    @Test func unknownExpiryIsUsable() {
        #expect(TokenExpiry.isExpired(nil, now: Date()) == false)
    }

    @Test func futureTokenNotExpired() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(TokenExpiry.isExpired(now.addingTimeInterval(3600), now: now) == false)
    }

    @Test func pastTokenExpired() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(TokenExpiry.isExpired(now.addingTimeInterval(-1), now: now) == true)
    }

    @Test func withinSkewCountsExpired() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // Expires in 5s, skew 10s → treat as expired now.
        #expect(TokenExpiry.isExpired(now.addingTimeInterval(5), now: now, skew: 10) == true)
        // Expires in 30s, skew 10s → still usable.
        #expect(TokenExpiry.isExpired(now.addingTimeInterval(30), now: now, skew: 10) == false)
    }
}
