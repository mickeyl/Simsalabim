import ArgumentParser
import Foundation

/// Prints a human-readable error to stderr and throws the given exit code —
/// call as `try fail(...)` so the compiler sees the `Never` return.
func fail(_ message: String, code: Int32) throws -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    throw ExitCode(code)
}

/// Progress/diagnostic output — never mixed into stdout's machine-readable
/// output.
func note(_ message: String) {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
}
