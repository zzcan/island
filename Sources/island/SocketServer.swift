import Foundation
import IslandCore
#if canImport(Darwin)
import Darwin
#endif

/// Writes exactly one newline-delimited reply to a client fd, then closes it — and
/// closes anyway after `timeout` if no reply ever comes (so a hook that never gets a
/// user decision doesn't leak the fd). Thread-safe; safe to call `reply` from any actor.
final class ReplyWriter: @unchecked Sendable {
    private let fd: Int32
    private var lock = os_unfair_lock()
    private var done = false

    init(fd: Int32, timeout: TimeInterval) {
        self.fd = fd
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(nil)
        }
    }

    /// Send the reply line (a newline is appended). First call wins; later calls no-op.
    func reply(_ data: Data) { finish(data) }

    private func finish(_ data: Data?) {
        os_unfair_lock_lock(&lock)
        if done { os_unfair_lock_unlock(&lock); return }
        done = true
        os_unfair_lock_unlock(&lock)

        if var payload = data {
            payload.append(0x0A)
            let bytes = [UInt8](payload)
            var sent = 0
            while sent < bytes.count {
                let n = bytes.withUnsafeBytes { raw in
                    write(fd, raw.baseAddress!.advanced(by: sent), bytes.count - sent)
                }
                if n <= 0 { break }   // hook likely gave up / closed (EPIPE)
                sent += n
            }
        }
        close(fd)
    }
}

// @unchecked Sendable: `running`/`listenFD` are written by start()/stop() on the main
// actor and read by the single detached accept thread (one-writer-then-one-reader).
/// AF_UNIX line-delimited JSON server. Fire-and-forget messages go to `onMessage`;
/// `permissionRequest` messages go to `onRequest` with a ReplyWriter to answer the
/// blocked hook once the user decides.
final class SocketServer: @unchecked Sendable {
    private let path: String
    private let onMessage: @Sendable (HookMessage) -> Void
    private let onRequest: @Sendable (HookMessage, ReplyWriter) -> Void
    private var listenFD: Int32 = -1
    private var running = false

    /// Reply window for an interactive approval — generous, but under Claude's 600s hook
    /// timeout so we close first and the hook still falls back cleanly.
    private let replyTimeout: TimeInterval = 580

    init(path: String,
         onMessage: @escaping @Sendable (HookMessage) -> Void,
         onRequest: @escaping @Sendable (HookMessage, ReplyWriter) -> Void) {
        self.path = path
        self.onMessage = onMessage
        self.onRequest = onRequest
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
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(listenFD); listenFD = -1; throw POSIXError(.ENAMETOOLONG)
        }
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
        guard bound == 0 else { close(listenFD); listenFD = -1; throw POSIXError(.EADDRINUSE) }
        guard listen(listenFD, 16) == 0 else { close(listenFD); listenFD = -1; throw POSIXError(.EADDRINUSE) }

        running = true
        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while running {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 { if running { continue } else { break } }
            // Each client on its own thread: a permissionRequest holds the connection
            // open while the user decides, which must not stall other hooks.
            Thread.detachNewThread { [weak self] in self?.handleClient(clientFD) }
        }
    }

    private func handleClient(_ fd: Int32) {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])

            // Process any complete lines we have so far.
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<nl]
                let lineData = Data(line)
                buffer.removeSubrange(buffer.startIndex...nl)
                guard !lineData.isEmpty,
                      let msg = try? JSONDecoder().decode(HookMessage.self, from: lineData)
                else { continue }

                if msg.event == .permissionRequest {
                    // Hand the connection to the request handler; it owns the fd now.
                    let writer = ReplyWriter(fd: fd, timeout: replyTimeout)
                    onRequest(msg, writer)
                    return   // do NOT close fd — the ReplyWriter will.
                }
                onMessage(msg)
            }
        }
        close(fd)
    }

    func stop() {
        running = false
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(path)
    }
}
