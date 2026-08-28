import Foundation

/// The wire contract for `/tmp/simsalabim.sock`: one newline-delimited JSON
/// request per connection, one newline-delimited JSON response, then close.
/// Deliberately independent of `SimBridgeShell`'s `ProviderMode` — modules
/// and modes travel as plain strings so the CLI and the suite app can be
/// built and versioned separately.

public enum ControlCommand: String, Codable, Sendable {
    case status
    case setMode
}

public enum ControlErrorCode: String, Codable, Sendable {
    case invalidModule
    case invalidMode
    case timeout
    case malformedRequest
}

public struct ControlRequest: Codable, Sendable {
    public var command: ControlCommand
    public var module: String?
    public var mode: String?

    public init(command: ControlCommand, module: String? = nil, mode: String? = nil) {
        self.command = command
        self.module = module
        self.mode = mode
    }
}

public struct ControlModuleStatus: Codable, Equatable, Sendable {
    public var mode: String
    public var isSwitching: Bool

    public init(mode: String, isSwitching: Bool) {
        self.mode = mode
        self.isSwitching = isSwitching
    }
}

public struct ControlResponse: Codable, Sendable {
    public var ok: Bool
    public var modules: [String: ControlModuleStatus]?
    public var module: String?
    public var mode: String?
    public var isSwitching: Bool?
    public var error: ControlErrorCode?
    public var message: String?

    public init(modules: [String: ControlModuleStatus]) {
        self.ok = true
        self.modules = modules
        self.module = nil
        self.mode = nil
        self.isSwitching = nil
        self.error = nil
        self.message = nil
    }

    public init(module: String, mode: String, isSwitching: Bool) {
        self.ok = true
        self.modules = nil
        self.module = module
        self.mode = mode
        self.isSwitching = isSwitching
        self.error = nil
        self.message = nil
    }

    public init(error: ControlErrorCode, message: String) {
        self.ok = false
        self.modules = nil
        self.module = nil
        self.mode = nil
        self.isSwitching = nil
        self.error = error
        self.message = message
    }
}

extension ControlRequest {
    public func encodedLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        data.append(UInt8(ascii: "\n"))
        return data
    }
}

extension ControlResponse {
    public func encodedLine() throws -> Data {
        var data = try JSONEncoder().encode(self)
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
