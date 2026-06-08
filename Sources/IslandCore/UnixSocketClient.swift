import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Best-effort one-shot sender. Used by vibe-hook. Never throws to the caller's
/// detriment — failures are reported via the Bool return so the hook can still exit 0.
public enum UnixSocketClient {
    @discardableResult
    public static func send(_ data: Data, toPath path: String, timeoutMs: Int = 200) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { return false }
        defer { close(fd) }

        // Non-blocking connect with timeout.
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { dst in
                for (i, b) in pathBytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[pathBytes.count] = 0
            }
        }

        var tv = timeval(tv_sec: 0, tv_usec: Int32(timeoutMs * 1000))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, len)
            }
        }
        if connected != 0 { return false }

        var sent = 0
        let bytes = [UInt8](data)
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes { raw in
                write(fd, raw.baseAddress!.advanced(by: sent), bytes.count - sent)
            }
            if n <= 0 { return false }
            sent += n
        }
        return true
    }
}
