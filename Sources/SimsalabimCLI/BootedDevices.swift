import Foundation

struct BootedDevice {
    let udid: String
    let name: String
}

enum BootedDevicesError: Error, CustomStringConvertible {
    case simctlFailed

    var description: String { "\"xcrun simctl list devices booted\" failed" }
}

/// A standalone `simctl` wrapper: `SimCtl` (used by Simulacrum's own UI for
/// the same lookup) is internal to `SimulacrumProviderKit`, not exposed, so
/// this small duplicate stands in for it here.
enum BootedDevices {
    static func list() throws -> [BootedDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "list", "devices", "booted", "-j"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BootedDevicesError.simctlFailed
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesByRuntime = json["devices"] as? [String: [[String: Any]]]
        else {
            return []
        }
        return devicesByRuntime.values.flatMap { devices in
            devices.compactMap { device -> BootedDevice? in
                guard let udid = device["udid"] as? String, let name = device["name"] as? String else { return nil }
                return BootedDevice(udid: udid, name: name)
            }
        }
    }
}
