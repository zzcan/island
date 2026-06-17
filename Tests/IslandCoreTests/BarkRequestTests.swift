import Testing
import Foundation
@testable import IslandCore

@Suite struct BarkRequestTests {
    /// 把请求体 JSON 解回字典，避开 JSONSerialization 的键序不确定。
    private func body(_ req: URLRequest) -> [String: String] {
        guard let data = req.httpBody,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return obj
    }

    @Test func buildsPostToPushEndpoint() {
        let req = BarkRequest.build(server: "https://api.day.app", deviceKey: "abc",
                                    title: "hi", body: "there", group: nil, level: .active)
        #expect(req?.url?.absoluteString == "https://api.day.app/push")
        #expect(req?.httpMethod == "POST")
        #expect(req?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func trimsTrailingSlashOnServer() {
        let req = BarkRequest.build(server: "https://x.example.com/", deviceKey: "abc",
                                    title: "hi", body: "", group: nil, level: .active)
        #expect(req?.url?.absoluteString == "https://x.example.com/push")
    }

    @Test func stripsMultipleTrailingSlashes() {
        let req = BarkRequest.build(server: "https://x.example.com//", deviceKey: "abc",
                                    title: "hi", body: "", group: nil, level: .active)
        #expect(req?.url?.absoluteString == "https://x.example.com/push")
    }

    @Test func defaultsServerWhenEmpty() {
        let req = BarkRequest.build(server: "  ", deviceKey: "abc",
                                    title: "hi", body: "", group: nil, level: .active)
        #expect(req?.url?.absoluteString == "https://api.day.app/push")
    }

    @Test func encodesFieldsIncludingChineseAndGroup() {
        let req = BarkRequest.build(server: "https://api.day.app", deviceKey: "abc",
                                    title: "需要输入", body: "项目X：等你回复",
                                    group: "island", level: .timeSensitive)
        let b = body(req!)
        #expect(b["device_key"] == "abc")
        #expect(b["title"] == "需要输入")
        #expect(b["body"] == "项目X：等你回复")
        #expect(b["group"] == "island")
        #expect(b["level"] == "timeSensitive")
    }

    @Test func omitsGroupWhenNilOrEmpty() {
        let req = BarkRequest.build(server: "https://api.day.app", deviceKey: "abc",
                                    title: "hi", body: "", group: "", level: .active)
        #expect(body(req!)["group"] == nil)
    }

    @Test func returnsNilForEmptyKeyOrTitle() {
        #expect(BarkRequest.build(server: "https://api.day.app", deviceKey: "  ",
                                  title: "hi", body: "", group: nil, level: .active) == nil)
        #expect(BarkRequest.build(server: "https://api.day.app", deviceKey: "abc",
                                  title: "  ", body: "", group: nil, level: .active) == nil)
    }
}
