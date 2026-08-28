import ArgumentParser
import Foundation
import SuiteControlProtocol

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show each hardware module's current mode.",
        discussion: """
        Examples:
          simsalabim status
          simsalabim status --json
        """
    )

    @Flag(help: "Print machine-readable JSON instead of a table.")
    var json = false

    func run() throws {
        let response: ControlResponse
        do {
            response = try ControlClient.send(ControlRequest(command: .status))
        } catch {
            try fail("Simsalabim is not running — start it, or pass --launch to \"simsalabim mode\".", code: 69)
        }

        guard response.ok, let modules = response.modules else {
            try fail(response.message ?? "Simsalabim returned an unexpected response.", code: 70)
        }

        if json {
            let data = try JSONEncoder().encode(modules)
            print(String(decoding: data, as: UTF8.self))
        } else {
            for name in ["impossible", "camouflage", "nfcromancer"] {
                guard let status = modules[name] else { continue }
                let suffix = status.isSwitching ? " (switching…)" : ""
                print("\(name): \(status.mode)\(suffix)")
            }
        }
    }
}
