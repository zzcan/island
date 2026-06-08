import Foundation
import IslandCore
#if canImport(Darwin)
import Darwin
#endif

/// AF_UNIX line-delimited JSON server. Accepts connections on a background thread,
/// decodes each line into a HookMessage, and delivers it on the main queue.
final class SocketServer: @unchecked Sendable {
    private let path: String
    private let onMessage: @Sendable (HookMessage) -> Void
    private var listenFD: Int32 = -1
    private var running = false

    init(path: String, onMessage: @escaping @Sendable (HookMessage) -> Void) {
        self.path = path
        self.onMessage = onMessage
    }

    func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        unlink(path) // remove stale socket

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw POSIXError(.EADDRNOTAVAIL) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: bytes.count + 1) { dst in
                for (i, b) in bytes.enumerated() { dst[i] = CChar(bitPattern: b) }
                dst[bytes.count] = 0
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, len) }
        }
        guard bound == 0 else { close(listenFD); throw POSIXError(.EADDRINUSE) }
        guard listen(listenFD, 16) == 0 else { close(listenFD); throw POSIXError(.EADDRINUSE) }

        running = true
        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while running {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 { if running { continue } else { break } }
            handleClient(clientFD)
        }
    }

    private func handleClient(_ fd: Int32) {
        defer { close(fd) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
        }
        let callback = onMessage
        for line in buffer.split(separator: 0x0A) where !line.isEmpty {
            guard let msg = try? JSONDecoder().decode(HookMessage.self, from: Data(line)) else { continue }
            Task { @MainActor in callback(msg) }
        }
    }

    func stop() {
        running = false
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(path)
    }
}
