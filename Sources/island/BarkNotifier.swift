import Foundation
import IslandCore

/// 把会话事件推到用户 iPhone 的 Bark。读 `Settings.shared` 取 server / key，
/// fire-and-forget：失败只 NSLog，绝不影响本地横幅 / 音效。
@MainActor
final class BarkNotifier {
    /// 按当前 Bark 设置组装并发送一条推送。key 为空则静默跳过。
    func send(title: String, body: String, group: String?, level: BarkLevel) {
        let s = Settings.shared
        guard let req = BarkRequest.build(server: s.barkServer, deviceKey: s.barkDeviceKey,
                                          title: title, body: body, group: group, level: level)
        else { return }
        Task { _ = await Self.fire(req) }
    }

    /// 发送一条测试推送，结果（成功 / 失败）回调到主线程，供设置页提示。
    func test(_ completion: @escaping @MainActor (Bool) -> Void) {
        let s = Settings.shared
        guard let req = BarkRequest.build(server: s.barkServer, deviceKey: s.barkDeviceKey,
                                          title: "island", body: "测试推送 ✓",
                                          group: "island", level: .active)
        else { completion(false); return }
        Task {
            let ok = await Self.fire(req)
            await MainActor.run { completion(ok) }
        }
    }

    /// 实际发请求。返回是否 2xx 成功。
    private static func fire(_ req: URLRequest) async -> Bool {
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(code) else {
                NSLog("island: bark push HTTP \(code)"); return false
            }
            return true
        } catch {
            NSLog("island: bark push failed: \(error)"); return false
        }
    }
}
