import Foundation
import Security
import IslandCore

/// Reads the Claude Code OAuth access token from the login keychain. The generic
/// password item is created by Claude Code (service "Claude Code-credentials") and
/// holds a JSON blob; we pull `claudeAiOauth.accessToken`. The FIRST read from this
/// (separately-signed) app triggers a macOS keychain-access prompt — "Always Allow"
/// silences it thereafter.
enum KeychainReader {
    static func claudeAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        return token
    }
}

/// Fetches subscription usage from Anthropic's (undocumented) /api/oauth/usage —
/// the same endpoint Claude Code's /usage uses. Returns nil on any failure (no
/// token, network error, non-200, unparseable body); callers keep their last value.
enum UsageClient {
    private static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async -> Usage? {
        guard let token = KeychainReader.claudeAccessToken() else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 8
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Usage.decode(data)
    }
}
