import Darwin
import Foundation
import SuiteControlProtocol

enum ControlClientError: Error, CustomStringConvertible {
    case notReachable
    case malformedResponse

    var description: String {
        switch self {
            case .notReachable: "Simsalabim is not reachable at \(ControlClient.socketPath)"
            case .malformedResponse: "Received a malformed response from Simsalabim"
        }
    }
}

/// A minimal synchronous `AF_UNIX` client for `/tmp/simsalabim.sock`: one
/// connection per request, mirroring the low-level socket construction in
/// `SuiteControlServer`/`ProtocolServer` on the other end.
enum ControlClient {
    static let socketPath = "/tmp/simsalabim.sock"

    static func send(_ request: ControlRequest) throws -> ControlResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlClientError.notReachable }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: min(buf.count, 104))
            }
        }
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw ControlClientError.notReachable }

        let payload = try request.encodedLine()
        try payload.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            guard let base = ptr.baseAddress else { throw ControlClientError.notReachable }
            var written = 0
            while written < payload.count {
                let n = Darwin.write(fd, base.advanced(by: written), payload.count - written)
                guard n > 0 else { throw ControlClientError.notReachable }
                written += n
            }
        }

        var responseData = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while !responseData.contains(UInt8(ascii: "\n")) {
            let n = read(fd, &buf, buf.count)
            guard n > 0 else { break }
            responseData.append(contentsOf: buf[0..<n])
        }
        guard let newlineIndex = responseData.firstIndex(of: UInt8(ascii: "\n")),
              let response = try? JSONDecoder().decode(ControlResponse.self, from: responseData[responseData.startIndex..<newlineIndex])
        else {
            throw ControlClientError.malformedResponse
        }
        return response
    }
}
