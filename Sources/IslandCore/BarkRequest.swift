import Foundation

/// Bark 通知优先级。https://bark.day.app
public enum BarkLevel: String, Sendable {
    case active, timeSensitive, passive, critical
}

/// 把一条 Bark 推送组装成 POST /push 的 URLRequest。纯函数，不发网络，便于单测。
public enum BarkRequest {
    /// deviceKey / title 去空白后为空时返回 nil（无意义的推送不发）。
    /// server 为空回退到官方 https://api.day.app，并规整尾部 `/`。
    public static func build(
        server: String,
        deviceKey: String,
        title: String,
        body: String,
        group: String?,
        level: BarkLevel
    ) -> URLRequest? {
        let key = deviceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !trimmedTitle.isEmpty else { return nil }

        let base = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = base.isEmpty ? "https://api.day.app" : base
        // Strip any number of trailing slashes so "host//" doesn't yield "host//push".
        let trimmed = String(root.reversed().drop(while: { $0 == "/" }).reversed())
        guard let url = URL(string: trimmed + "/push") else { return nil }

        var payload: [String: String] = [
            "device_key": key, "title": trimmedTitle, "body": body, "level": level.rawValue,
        ]
        if let group, !group.isEmpty { payload["group"] = group }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        return req
    }
}
