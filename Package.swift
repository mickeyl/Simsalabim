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
    ],
    dependencies: [
        .package(path: "Modules/ImpossiBLE/Sources/ImpossiBLE-Mock"),
        .package(path: "Modules/CAMouflage/Sources/CAMouflage-Mock"),
        .package(path: "Modules/NFCromancer/Sources/NFCromancer-Mock"),
        .package(url: "https://github.com/mickeyl/SimBridgeKit.git", from: "0.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "Simsalabim",
            dependencies: [
                .product(name: "ImpossiBLEProviderKit", package: "ImpossiBLE-Mock"),
                .product(name: "CAMouflageProviderKit", package: "CAMouflage-Mock"),
                .product(name: "NFCromancerProviderKit", package: "NFCromancer-Mock"),
                .product(name: "SimBridgeServer", package: "SimBridgeKit"),
                .product(name: "SimBridgeShell", package: "SimBridgeKit"),
            ],
            path: "Sources/SuiteApp"
        )
    ]
)
