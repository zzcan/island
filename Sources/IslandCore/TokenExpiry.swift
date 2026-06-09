import Foundation

/// Pure helpers for reasoning about the Claude Code OAuth token's expiry. The island
/// app does NOT refresh the token itself (that would rotate Claude Code's refresh
/// token and risk logging the user out); it only reads the keychain. These helpers let
/// it skip a doomed request when the stored token is already expired and keep the last
/// usage value until Claude Code refreshes the keychain.
public enum TokenExpiry {
    /// Normalizes an epoch that may be in seconds or milliseconds to a Date.
    /// Claude Code stores `expiresAt` in milliseconds; tolerate seconds too.
    public static func date(fromEpoch value: Double) -> Date {
        let secs = value > 1_000_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: secs)
    }

    /// True when expiry is known and at/near `now`. `skew` treats a token that expires
    /// within the next few seconds as already expired (avoids using a token that dies
    /// mid-request). Unknown expiry (nil) is treated as usable.
    public static func isExpired(_ expiresAt: Date?, now: Date, skew: TimeInterval = 10) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSince(now) <= skew
    }
}
