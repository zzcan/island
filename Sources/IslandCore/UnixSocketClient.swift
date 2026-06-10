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

    /// Request/response over the same connection. Sends `data` (which must be
    /// newline-terminated), then blocks reading a single newline-delimited reply line.
    /// Used by vibe-hook for interactive approvals — it must wait for the user's decision.
    /// Returns the reply bytes (without the trailing newline) or nil on connect/IO error
    /// or timeout, so the hook can fall back gracefully.
    public static func request(_ data: Data, toPath path: String,
                               connectTimeoutMs: Int = 500, replyTimeoutMs: Int) -> Data? {
        let fd = connectFD(path: path, sendTimeoutMs: connectTimeoutMs)
        if fd < 0 { return nil }
        defer { close(fd) }

        var rcv = timeval(tv_sec: replyTimeoutMs / 1000,
                          tv_usec: Int32((replyTimeoutMs % 1000) * 1000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &rcv, socklen_t(MemoryLayout<timeval>.size))

        var sent = 0
        let bytes = [UInt8](data)
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes { raw in
                write(fd, raw.baseAddress!.advanced(by: sent), bytes.count - sent)
            }
            if n <= 0 { return nil }
            sent += n
        }

        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return reply.isEmpty ? nil : reply }   // EOF/timeout
            if let nl = chunk[0..<n].firstIndex(of: 0x0A) {
                reply.append(contentsOf: chunk[0..<nl])
                return reply
            }
            reply.append(contentsOf: chunk[0..<n])
        }
    }

    /// Connects an AF_UNIX stream socket with a send timeout. Returns fd or -1.
    private static func connectFD(path: String, sendTimeoutMs: Int) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 { return -1 }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return -1 }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count + 1) { dst in
                for (i, b) in pathBytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[pathBytes.count] = 0
            }
        }
        var tv = timeval(tv_sec: 0, tv_usec: Int32(sendTimeoutMs * 1000))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
        }
        if connected != 0 { close(fd); return -1 }
        return fd
    }
}
