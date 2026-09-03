import ArgumentParser
import Foundation
import SimulacrumProviderKit

struct SeedCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "seed",
        abstract: "Seed a booted simulator with the stored Contacts/Calendar/Reminders/Photos/Health fixture.",
        discussion: """
        With no category flag, seeds every category. Simsalabim.app must not
        be running — it already owns /tmp/simulacrum.sock.

        Examples:
          simsalabim seed
          simsalabim seed --contacts --calendar --device 1E2C3B4A-...
        """
    )

    @Flag(help: "Seed contacts.")
    var contacts = false

    @Flag(help: "Seed calendar events.")
    var calendar = false

    @Flag(help: "Seed reminders.")
    var reminders = false

    @Flag(help: "Seed photos.")
    var photos = false

    @Flag(help: "Seed Health history and workouts.")
    var health = false

    @Option(name: .customLong("device"), help: "UDID of the target simulator. Defaults to the single booted simulator.")
    var device: String?

    @Flag(help: "Print a JSON summary instead of plain text.")
    var json = false

    @MainActor
    func run() async throws {
        let categoriesRequested = contacts || calendar || reminders || photos || health
        let includeAll = !categoriesRequested

        let udid = try resolveDevice()
        let stored = FixtureStore().fixture
        let fixture = Fixture(
            contacts: (includeAll || contacts) ? stored.contacts : [],
            events: (includeAll || calendar) ? stored.events : [],
            reminders: (includeAll || reminders) ? stored.reminders : [],
            photos: (includeAll || photos) ? stored.photos : [],
            health: (includeAll || health) ? stored.health : nil
        )

        let seedServer = SeedServer()
        await withCheckedContinuation { continuation in
            seedServer.start { continuation.resume() }
        }
        defer { seedServer.stop() }

        if case .blocked(let message) = seedServer.transport.status {
            try fail(
                "Simsalabim.app is already running and owns /tmp/simulacrum.sock (\(message)) — quit it first.",
                code: 70
            )
        }

        let runner = SeedRunner(server: seedServer)
        runner.seed(fixture: fixture, udid: udid)
        try await waitForCompletion(of: runner)
    }

    @MainActor
    private func waitForCompletion(of runner: SeedRunner) async throws -> Never {
        var lastDescription = ""
        while true {
            switch runner.state {
                case .idle:
                    break
                case .running(let category, let index, let total):
                    let description = "\(category ?? "?") \(index + 1)/\(total)"
                    if description != lastDescription {
                        note("Seeding \(description)…")
                        lastDescription = description
                    }
                case .finished(let summary):
                    printSummary(summary)
                    throw ExitCode(summary.isClean ? 0 : 70)
                case .failed(let message):
                    try fail(message, code: 70)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func printSummary(_ summary: SeedRunner.Summary) {
        if json {
            let payload: [String: Any] = [
                "contacts": summary.contacts,
                "events": summary.events,
                "reminders": summary.reminders,
                "photos": summary.photos,
                "healthSamples": summary.healthSamples,
                "workouts": summary.workouts,
                "fallEvents": summary.fallEvents,
                "errors": summary.errors,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                print(String(decoding: data, as: UTF8.self))
            }
        } else {
            print("contacts=\(summary.contacts) events=\(summary.events) reminders=\(summary.reminders) photos=\(summary.photos) healthSamples=\(summary.healthSamples) workouts=\(summary.workouts) fallEvents=\(summary.fallEvents)")
            for error in summary.errors {
                note("Error: \(error)")
            }
        }
    }

    private func resolveDevice() throws -> String {
        if let device { return device }
        let devices = try BootedDevices.list()
        switch devices.count {
            case 0:
                try fail("No booted simulator found — boot one or pass --device <udid>.", code: 70)
            case 1:
                return devices[0].udid
            default:
                let list = devices.map { "  \($0.udid)  \($0.name)" }.joined(separator: "\n")
                try fail("Multiple booted simulators found — pass --device <udid>:\n\(list)", code: 64)
        }
    }
}
