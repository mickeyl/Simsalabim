import Foundation
import SuiteControlProtocol

/// Starts Simsalabim.app when `mode --launch` finds it not running, and
/// polls the control socket until it answers.
enum LaunchHelper {
    static let bundleID = "de.vanille.simsalabim"

    static func launchAndWaitUntilReachable(timeout: TimeInterval = 15) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleID]
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? ControlClient.send(ControlRequest(command: .status))) != nil {
                return true
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }
}
