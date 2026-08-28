import ArgumentParser

@main
struct Simsalabim: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "simsalabim",
        abstract: "Headless control for the Simsalabim suite.",
        subcommands: [StatusCommand.self, ModeCommand.self, SeedCommand.self]
    )
}
