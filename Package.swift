// swift-tools-version: 5.9
import PackageDescription

// The suite app builds against the submodule checkouts via path dependencies,
// so a `git clone --recursive` is all it takes — no tag-bump dance during
// co-development. The submodule pins record exactly which product versions a
// suite release ships.
let package = Package(
    name: "Simsalabim",
    platforms: [
        .macOS("15.0"),
        .iOS(.v15),
    ],
    products: [
        .library(name: "SimsalabimClient", targets: ["SimsalabimClient"]),
        .executable(name: "Simsalabim", targets: ["Simsalabim"]),
        .executable(name: "simsalabim", targets: ["simsalabim"]),
    ],
    dependencies: [
        // Simulator-side client packages. SwiftPM initializes these
        // submodules when Simsalabim itself is consumed by URL.
        .package(path: "Modules/ImpossiBLE"),
        .package(path: "Modules/CAMouflage"),
        .package(path: "Modules/NFCromancer"),

        // macOS provider packages used by the suite app.
        .package(path: "Modules/ImpossiBLE/Sources/ImpossiBLE-Mac"),
        .package(path: "Modules/CAMouflage/Sources/CAMouflage-Mac"),
        .package(path: "Modules/NFCromancer/Sources/NFCromancer-Mac"),
        .package(path: "Modules/Simulacrum/Sources/Simulacrum-Mac"),
        .package(url: "https://github.com/mickeyl/SimBridgeKit.git", from: "0.1.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "SimsalabimClient",
            dependencies: [
                .product(
                    name: "ImpossiBLE",
                    package: "ImpossiBLE",
                    condition: .when(platforms: [.iOS])
                ),
                .product(
                    name: "CAMouflage",
                    package: "CAMouflage",
                    condition: .when(platforms: [.iOS])
                ),
                .product(
                    name: "NFCromancer",
                    package: "NFCromancer",
                    condition: .when(platforms: [.iOS])
                ),
            ]
        ),
        .executableTarget(
            name: "Simsalabim",
            dependencies: [
                .product(name: "ImpossiBLEProviderKit", package: "ImpossiBLE-Mac"),
                .product(name: "CAMouflageProviderKit", package: "CAMouflage-Mac"),
                .product(name: "NFCromancerProviderKit", package: "NFCromancer-Mac"),
                .product(name: "SimulacrumProviderKit", package: "Simulacrum-Mac"),
                .product(name: "SimBridgeServer", package: "SimBridgeKit"),
                .product(name: "SimBridgeShell", package: "SimBridgeKit"),
                "SuiteControlProtocol",
            ],
            path: "Sources/SuiteApp"
        ),
        // No dependency on SimBridgeShell or any provider kit — modules and
        // modes travel as plain strings so the CLI and the suite app can be
        // built and versioned separately (see ControlProtocol.swift).
        .target(
            name: "SuiteControlProtocol",
            path: "Sources/SuiteControlProtocol"
        ),
        .executableTarget(
            name: "simsalabim",
            dependencies: [
                "SuiteControlProtocol",
                .product(name: "SimulacrumProviderKit", package: "Simulacrum-Mac"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/SimsalabimCLI"
        ),
    ]
)
