import SwiftUI
import ImpossiBLEProviderKit
import CAMouflageProviderKit
import NFCromancerProviderKit
import SimulacrumProviderKit
import SimBridgeServer
import SimBridgeShell

/// The suite panel: one section per provider, stacked under a shared header,
/// with the app-level preferences in a single footer.
struct SuitePanelContent: View {
    @ObservedObject var store: MockStore
    @ObservedObject var bleServer: MockServer
    @ObservedObject var bleTransport: ProtocolServer
    @ObservedObject var bleActivity: PassthroughActivityMonitor
    @ObservedObject var bleController: ModeTransitionController<ProviderMode>
    @ObservedObject var camServer: MockCameraServer
    @ObservedObject var camTransport: ProtocolServer
    @ObservedObject var camCatalog: CameraCatalog
    @ObservedObject var camController: ModeTransitionController<ProviderMode>
    @ObservedObject var nfcServer: TagServer
    @ObservedObject var nfcTransport: ProtocolServer
    @ObservedObject var nfcController: ModeTransitionController<ProviderMode>
    @ObservedObject var seedTransport: ProtocolServer
    @ObservedObject var fixtureStore: FixtureStore
    @ObservedObject var seedRunner: SeedRunner
    var onDismiss: (() -> Void)?
    var onOpenCapture: (() -> Void)?
    var onOpenDevice: ((UUID) -> Void)?

    @State private var dismissOnDeactivate = ShellPreferences.dismissControlWindowOnDeactivate
    @State private var launchAtLogin = SuitePanelContent.launchAgent.isEnabled
    @State private var confirmTermination = false
    /// Exactly one module is expanded at a time (or none): the accordion
    /// gives the open module the full pane — the same height its standalone
    /// app would offer — while every header stays visible, so a parked
    /// provider still signals its health via its status dot. This replaced
    /// the earlier collapse-flags-plus-splitter layout; dividing one panel
    /// between N heterogeneous panes never carried its weight (history in
    /// AGENTS.md).
    @AppStorage("ExpandedModule") private var expandedModuleRaw = Module.impossible.rawValue
    private static let launchAgent = LaunchAtLogin(label: "de.vanille.simsalabim")

    /// The suite's modules, in panel order. Raw values double as the
    /// persisted `ExpandedModule` value and the header title.
    enum Module: String {
        case impossible = "ImpossiBLE"
        case camouflage = "CAMouflage"
        case nfcromancer = "NFCromancer"
        case simulacrum = "Simulacrum"
    }

    private var expandedModule: Module? {
        get { Module(rawValue: expandedModuleRaw) }
        nonmutating set { expandedModuleRaw = newValue?.rawValue ?? "" }
    }

    /// Simulacrum has no Off/Mock/Passthrough mode to report — the dot
    /// reflects the current run instead: quiet until a seed is in flight,
    /// then blue while running, orange/red if the last one didn't finish
    /// clean.
    private var seedStatusColor: Color {
        switch seedRunner.state {
            case .idle:
                .secondary
            case .running:
                .blue
            case .finished(let summary):
                summary.isClean ? .secondary : .orange
            case .failed:
                .red
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            clientRow
            Divider()

            moduleHeader(
                .impossible,
                detail: "Bluetooth LE",
                controller: bleController,
                color: ImpossiBLESection.statusColor(mode: bleController.mode, status: bleTransport.status)
            ) {
                Image(nsImage: FontAwesome.brandImage(FontAwesome.bluetoothB, size: 14))
            }
            if expandedModule == .impossible {
                ImpossiBLESection(
                    store: store,
                    server: bleServer,
                    transport: bleTransport,
                    activity: bleActivity,
                    controller: bleController,
                    showsClient: false,
                    onDismiss: onDismiss,
                    onOpenCapture: onOpenCapture,
                    onOpenDevice: onOpenDevice
                )
                .frame(maxHeight: .infinity)
            }
            Divider()

            moduleHeader(
                .camouflage,
                detail: "Camera",
                controller: camController,
                color: CAMouflageSection.statusColor(
                    mode: camController.mode,
                    status: camTransport.status,
                    trafficActive: camServer.trafficActive
                )
            ) {
                Image(systemName: "camera.aperture")
                    .font(.caption)
            }
            if expandedModule == .camouflage {
                // Scrollable because the camera content can outgrow even a
                // full pane on small screens.
                ScrollView {
                    CAMouflageSection(
                        server: camServer,
                        transport: camTransport,
                        catalog: camCatalog,
                        controller: camController,
                        showsClient: false
                    )
                    .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            Divider()

            moduleHeader(
                .nfcromancer,
                detail: "NFC",
                controller: nfcController,
                color: NFCromancerSection.statusColor(mode: nfcController.mode, status: nfcTransport.status)
            ) {
                Image(systemName: "wave.3.right")
                    .font(.caption)
            }
            if expandedModule == .nfcromancer {
                NFCromancerSection(
                    server: nfcServer,
                    transport: nfcTransport,
                    controller: nfcController,
                    showsClient: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()

            moduleHeader(
                .simulacrum,
                detail: "Seed Data",
                color: seedStatusColor
            ) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.caption)
            }
            if expandedModule == .simulacrum {
                SimulacrumSection(
                    transport: seedTransport,
                    fixtureStore: fixtureStore,
                    runner: seedRunner
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if expandedModule == nil {
                Spacer(minLength: 0)
            }
            Divider()

            footer
        }
        .background(Color.clear)
    }

    private var header: some View {
        HStack {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Simsalabim")
                    .font(.title2.weight(.semibold))
                Text(appVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onDismiss?()
            } label: {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .help("Close this panel")
            .accessibilityLabel("Close this panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    // MARK: - Connected client (suite level)

    /// The connected simulator client lives above the modules: each provider
    /// socket has its own client slot, but it is usually the same app on both,
    /// so one line covers it — and only diverging clients fan out per module.
    @ViewBuilder
    private var clientRow: some View {
        let connected = allClients.filter { $0.client != nil }
        let uniquePids = Set(connected.compactMap { $0.client?.pid })

        HStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.caption)
                .foregroundStyle(connected.isEmpty ? Color.secondary : .green)

            VStack(alignment: .leading, spacing: 1) {
                if connected.isEmpty {
                    Text("No simulator client connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if uniquePids.count == 1, let client = connected.first?.client {
                    // The usual case: the same app on every provider socket.
                    Text(clientText(client))
                        .font(.caption)
                } else {
                    // Different apps per module — fan out.
                    ForEach(connected, id: \.label) { entry in
                        if let client = entry.client {
                            Text("\(entry.label): \(clientText(client))")
                                .font(.caption)
                        }
                    }
                }
            }
            .lineLimit(1)

            Spacer()

            if !connected.isEmpty {
                Button {
                    confirmTermination = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Terminate connected client")
                .accessibilityLabel("Terminate connected client")
                .confirmationDialog(
                    "Terminate the connected simulator client?",
                    isPresented: $confirmTermination,
                    titleVisibility: .visible
                ) {
                    Button("Terminate", role: .destructive) {
                        for entry in connected { entry.terminate() }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("The simulator app will be disconnected from all providers.")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private struct ClientEntry {
        let label: String
        let client: SocketClientInfo?
        let terminate: () -> Void
    }

    private var allClients: [ClientEntry] {
        [
            ClientEntry(label: "Bluetooth", client: bleTransport.connectedClient) { bleTransport.terminateConnectedClient() },
            ClientEntry(label: "Camera", client: camTransport.connectedClient) { camTransport.terminateConnectedClient() },
            ClientEntry(label: "NFC", client: nfcTransport.connectedClient) { nfcTransport.terminateConnectedClient() },
        ]
    }

    private func clientText(_ client: SocketClientInfo) -> String {
        guard let version = client.libraryVersion else { return client.displayText }
        return "\(client.displayText) · lib \(version)"
    }

    /// `controller` is nil for modules without an Off mode (Simulacrum).
    private func moduleHeader<Icon: View>(
        _ module: Module,
        detail: String,
        controller: ModeTransitionController<ProviderMode>? = nil,
        color: Color,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let isExpanded = expandedModule == module
        // A running provider that is parked in a collapsed section would
        // otherwise need two clicks to switch off; the overlay sits above
        // the header button, so it takes the hit itself.
        let showsQuickOff = !isExpanded && controller.map { $0.mode != .off } == true
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedModule = isExpanded ? nil : module
            }
        } label: {
            HStack(spacing: 6) {
                icon()
                    .foregroundStyle(color)
                    .frame(width: 16, alignment: .trailing)
                Text(module.rawValue)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(module.rawValue), \(isExpanded ? "expanded" : "collapsed")")
        .overlay(alignment: .trailing) {
            if showsQuickOff, let controller {
                Button {
                    controller.select(.off)
                } label: {
                    Image(systemName: "power")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(controller.isSwitching)
                .help("Switch \(module.rawValue) off")
                .accessibilityLabel("Switch \(module.rawValue) off")
                // Clears the status dot and chevron the header draws at its
                // trailing edge.
                .padding(.trailing, 43)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            IconToggle(
                systemImage: "power",
                help: "Launch Simsalabim automatically at login",
                isOn: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { _, newValue in
                Self.launchAgent.setEnabled(newValue)
            }

            IconToggle(
                systemImage: "eye.slash",
                help: "Hide this panel when you switch to another app",
                isOn: $dismissOnDeactivate
            )
            .onChange(of: dismissOnDeactivate) { _, newValue in
                ShellPreferences.dismissControlWindowOnDeactivate = newValue
            }

            Spacer()

            // The app delegate stops both providers on any quit path.
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}
