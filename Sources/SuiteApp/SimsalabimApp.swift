import SwiftUI
import AppKit
import ImpossiBLEProviderKit
import CAMouflageProviderKit
import NFCromancerProviderKit
import SimulacrumProviderKit
import SimBridgeShell

/// One process, all providers: each module keeps its own socket, server, and
/// mode selection; the suite binds them under a single menu bar presence.
@MainActor
final class SuiteRuntime {
    let store: MockStore
    let bleServer: MockServer
    let bleController: ModeTransitionController<ProviderMode>
    let camServer: MockCameraServer
    let camCatalog: CameraCatalog
    let camController: ModeTransitionController<ProviderMode>
    let nfcServer: TagServer
    let nfcController: ModeTransitionController<ProviderMode>
    let seedServer: SeedServer
    let liveHealthServer: LiveEventServer
    let fixtureStore: FixtureStore
    let seedRunner: SeedRunner
    let controlServer: SuiteControlServer
    let statusBar: SuiteStatusBarController

    static var shared: SuiteRuntime?

    init() {
        store = MockStore()
        let bleServer = MockServer(autoStart: false)
        self.bleServer = bleServer
        bleServer.store = store
        // The suite has its own defaults domain, so these keys never collide
        // with the standalone apps' persisted modes.
        bleController = ModeTransitionController(
            initial: ProviderMode.persisted(key: "ImpossiBLEMode"),
            persist: { $0.persist(key: "ImpossiBLEMode") }
        ) { mode, completion in
            switch mode {
                case .off:
                    bleServer.stop(completion: completion)
                case .mock:
                    bleServer.stop {
                        bleServer.start(mode: .mock, completion: completion)
                    }
                case .passthrough:
                    bleServer.stop {
                        bleServer.start(mode: .passthrough, completion: completion)
                    }
            }
        }

        let camServer = MockCameraServer()
        self.camServer = camServer
        let camCatalog = CameraCatalog()
        self.camCatalog = camCatalog
        camController = ModeTransitionController(
            initial: ProviderMode.persisted(key: "CAMouflageMode"),
            persist: { $0.persist(key: "CAMouflageMode") }
        ) { mode, completion in
            switch mode {
                case .off:
                    camServer.stop(completion: completion)
                case .mock:
                    camServer.useMock(completion: completion)
                case .passthrough:
                    camCatalog.activate()
                    camServer.usePassthrough(deviceID: camCatalog.selectedDeviceID, completion: completion)
            }
        }

        let nfcServer = TagServer()
        self.nfcServer = nfcServer
        nfcController = ModeTransitionController(
            initial: ProviderMode.persisted(key: "NFCromancerMode"),
            persist: { $0.persist(key: "NFCromancerMode") }
        ) { mode, completion in
            switch mode {
                case .off:
                    nfcServer.stop(completion: completion)
                case .mock:
                    nfcServer.stop {
                        nfcServer.start(mode: .mock, completion: completion)
                    }
                case .passthrough:
                    nfcServer.stop {
                        nfcServer.start(mode: .passthrough, completion: completion)
                    }
            }
        }

        // Unlike the other three, there's no mode to switch — the server just
        // listens for a seed agent to connect, same as its standalone-app
        // counterpart (Simulacrum's own StatusBarController.init).
        let seedServer = SeedServer()
        self.seedServer = seedServer
        seedServer.start()
        let liveHealthServer = LiveEventServer()
        self.liveHealthServer = liveHealthServer
        liveHealthServer.start()
        fixtureStore = FixtureStore()
        seedRunner = SeedRunner(server: seedServer, liveEventServer: liveHealthServer)

        // Lets external tooling (the `simsalabim` CLI) drive the same
        // ModeTransitionControllers the menu bar UI does, live.
        controlServer = SuiteControlServer(
            handler: SuiteControlHandler(bleController: bleController, camController: camController, nfcController: nfcController)
        )
        controlServer.start()

        statusBar = SuiteStatusBarController(
            store: store,
            bleServer: bleServer,
            bleController: bleController,
            camServer: camServer,
            camCatalog: camCatalog,
            camController: camController,
            nfcServer: nfcServer,
            nfcController: nfcController,
            seedServer: seedServer,
            fixtureStore: fixtureStore,
            seedRunner: seedRunner
        )
    }
}

/// Shuts both providers down before the process exits so their socket files
/// are unlinked cleanly. Handles every quit path (footer button and ⌘Q).
final class SuiteAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let runtime = SuiteRuntime.shared else {
            return .terminateNow
        }

        runtime.bleServer.stop {
            runtime.camServer.stop {
                runtime.nfcServer.stop {
                    runtime.seedServer.stop {
                        runtime.liveHealthServer.stop {
                            runtime.controlServer.stop {
                                sender.reply(toApplicationShouldTerminate: true)
                            }
                        }
                    }
                }
            }
        }
        return .terminateLater
    }
}

@main
struct SimsalabimApp: App {
    @NSApplicationDelegateAdaptor(SuiteAppDelegate.self) private var appDelegate

    init() {
        if SuiteRuntime.shared == nil {
            SuiteRuntime.shared = SuiteRuntime()
        }
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
