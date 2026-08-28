// swift-tools-version: 5.9
import PackageDescription

// The suite app builds against the submodule checkouts via path dependencies,
// so a `git clone --recursive` is all it takes — no tag-bump dance during
// co-development. The submodule pins record exactly which product versions a
// suite release ships.
let package = Package(
    name: "Simsalabim",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "Simsalabim", targets: ["Simsalabim"]),
        .executable(name: "simsalabim", targets: ["simsalabim"]),
    ],
    dependencies: [
        .package(path: "Modules/ImpossiBLE/Sources/ImpossiBLE-Mac"),
        .package(path: "Modules/CAMouflage/Sources/CAMouflage-Mac"),
        .package(path: "Modules/NFCromancer/Sources/NFCromancer-Mac"),
        .package(path: "Modules/Simulacrum/Sources/Simulacrum-Mac"),
        .package(url: "https://github.com/mickeyl/SimBridgeKit.git", from: "0.1.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
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
