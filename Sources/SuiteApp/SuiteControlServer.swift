import Darwin
import Foundation
import SuiteControlProtocol

/// A lightweight control channel for external tooling (the `simsalabim`
/// CLI): unlike the four provider sockets, every connection is independent
/// and short-lived — concurrent CLI invocations must not evict each other —
/// so this deliberately skips `ProtocolServer`'s single-current-client model
/// rather than reusing it.
final class SuiteControlServer {
    private static let socketPath = "/tmp/simsalabim.sock"
    private static let maxRequestBytes = 64 * 1024

    private let ioQueue = DispatchQueue(label: "simsalabim.control.io")
    private let handler: SuiteControlHandler

    private var serverFd: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    // Guarded by ioQueue: keeps each in-flight connection's read source alive
    // until its one line has arrived (or the connection is torn down).
    private var pendingConnections: [Int32: DispatchSourceRead] = [:]

    init(handler: SuiteControlHandler) {
        self.handler = handler
    }

    func start() {
        ioQueue.async { [self] in
            guard serverFd < 0 else { return }

            // Ownership guard, same rationale as ProtocolServer's: only a
            // stale file nobody answers on is unlinked and rebound.
            if access(Self.socketPath, F_OK) == 0, Self.probeListener(at: Self.socketPath) {
                NSLog("SuiteControlServer: another instance already serves \(Self.socketPath) — refusing to start")
                return
            }

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                NSLog("SuiteControlServer: socket() failed")
                return
            }

            unlink(Self.socketPath)

            guard Self.bind(fd: fd, to: Self.socketPath) else {
                NSLog("SuiteControlServer: bind() failed: \(errno)")
                close(fd)
                return
            }

            guard listen(fd, 8) == 0 else {
                NSLog("SuiteControlServer: listen() failed")
                close(fd)
                return
            }

            serverFd = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ioQueue)
            source.setEventHandler { [weak self] in self?.acceptConnection() }
            source.setCancelHandler { close(fd) }
            source.resume()
            acceptSource = source
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        ioQueue.async { [self] in
            for (fd, source) in pendingConnections {
                source.cancel()
                close(fd)
            }
            pendingConnections.removeAll()

            acceptSource?.cancel()
            acceptSource = nil
            let hadServer = serverFd >= 0
            serverFd = -1
            if hadServer {
                unlink(Self.socketPath)
            }

            if let completion {
                DispatchQueue.main.async(execute: completion)
            }
        }
    }

    // MARK: - Connections (ioQueue)

    private func acceptConnection() {
        let fd = accept(serverFd, nil, nil)
        guard fd >= 0 else { return }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var buffer = Data()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ioQueue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else {
                self.closeConnection(fd: fd)
                return
            }
            buffer.append(contentsOf: chunk[0..<n])
            guard buffer.count <= Self.maxRequestBytes else {
                self.closeConnection(fd: fd)
                return
            }
            guard let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) else { return }
            let lineData = Data(buffer[buffer.startIndex..<newlineIndex])
            self.pendingConnections[fd]?.cancel()
            self.pendingConnections[fd] = nil
            self.handle(lineData: lineData, fd: fd)
        }
        source.setCancelHandler { }
        pendingConnections[fd] = source
        source.resume()
    }

    private func closeConnection(fd: Int32) {
        pendingConnections[fd]?.cancel()
        pendingConnections[fd] = nil
        close(fd)
    }

    private func handle(lineData: Data, fd: Int32) {
        guard let request = try? JSONDecoder().decode(ControlRequest.self, from: lineData) else {
            reply(ControlResponse(error: .malformedRequest, message: "Could not decode request"), fd: fd)
            return
        }
        Task { [self] in
            let response = await handler.handle(request)
            reply(response, fd: fd)
        }
    }

    private func reply(_ response: ControlResponse, fd: Int32) {
        ioQueue.async {
            defer { close(fd) }
            guard let data = try? response.encodedLine() else { return }
            _ = data.withUnsafeBytes { ptr -> Bool in
                guard let base = ptr.baseAddress else { return false }
                var written = 0
                while written < data.count {
                    let n = Darwin.write(fd, base.advanced(by: written), data.count - written)
                    if n <= 0 { return false }
                    written += n
                }
                return true
            }
        }
    }

    // MARK: - Socket plumbing (mirrors ProtocolServer's Darwin sockaddr_un construction)

    private static func bind(fd: Int32, to path: String) -> Bool {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: min(buf.count, 104))
            }
        }
        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        } == 0
    }

    /// True when a live listener answers on the socket path. A stale file
    /// left by a crashed process refuses the connection and may be unlinked.
    private static func probeListener(at path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: min(buf.count, 104))
            }
        }
        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        } == 0
    }
}
