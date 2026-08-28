import ArgumentParser
import Foundation
import SuiteControlProtocol

enum CLIModule: String, CaseIterable, ExpressibleByArgument {
    case impossible
    case camouflage
    case nfcromancer
}

enum CLIMode: String, CaseIterable, ExpressibleByArgument {
    case off
    case mock
    case passthrough
}

struct ModeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mode",
        abstract: "Switch a hardware module's mode on a running Simsalabim.",
        discussion: """
        Examples:
          simsalabim mode impossible passthrough
          simsalabim mode camouflage mock --launch
        """
    )

    @Argument(help: "The module to switch.")
    var module: CLIModule

    @Argument(help: "The target mode.")
    var mode: CLIMode

    @Flag(help: "Launch Simsalabim if it isn't already running.")
    var launch = false

    func run() throws {
        if !isReachable() {
            guard launch else {
                try fail(
                    "Simsalabim is not running — pass --launch to start it, or run \"open -b \(LaunchHelper.bundleID)\" yourself.",
                    code: 69
                )
            }
            note("Simsalabim is not running — launching…")
            guard LaunchHelper.launchAndWaitUntilReachable() else {
                try fail("Timed out waiting for Simsalabim to start.", code: 69)
            }
        }

        let response: ControlResponse
        do {
            response = try ControlClient.send(ControlRequest(command: .setMode, module: module.rawValue, mode: mode.rawValue))
        } catch {
            try fail("Lost the connection to Simsalabim: \(error)", code: 70)
        }

        guard response.ok else {
            try fail(response.message ?? "Simsalabim rejected the request.", code: 70)
        }

        print("\(module.rawValue): \(response.mode ?? mode.rawValue)")
    }

    private func isReachable() -> Bool {
        (try? ControlClient.send(ControlRequest(command: .status))) != nil
    }
}
