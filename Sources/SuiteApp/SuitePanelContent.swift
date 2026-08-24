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
    // Collapsed modules keep their header (with the status dot) visible, so a
    // parked provider still signals its health while yielding panel space.
    @AppStorage("ImpossiBLECollapsed") private var bleCollapsed = false
    @AppStorage("CAMouflageCollapsed") private var camCollapsed = false
    @AppStorage("NFCromancerCollapsed") private var nfcCollapsed = false
    @AppStorage("SimulacrumCollapsed") private var seedCollapsed = false
    /// User-chosen height of the Bluetooth pane while both modules are
    /// expanded; the camera pane takes the remainder. Adjusted by dragging
    /// the splitter between the sections.
    @AppStorage("ImpossiBLEPaneHeight") private var blePaneHeight = 380.0
    /// The proposed height while a drag is in flight. The panes deliberately
    /// stay frozen until release: live-resizing the sections' NSScrollView-
    /// backed lists at mouse-event rate is what made the drag stutter — only
    /// the grip travels, and the layout snaps once, on release.
    @State private var dragProposal: Double?
    @State private var dragBaseHeight: Double?
    @State private var modulesHeight: CGFloat = 0
    private static let launchAgent = LaunchAtLogin(label: "de.vanille.simsalabim")
    private static let blePaneMinHeight = 220.0
    private static let camPaneMinHeight = 240.0

    private var bothExpanded: Bool { !bleCollapsed && !camCollapsed }

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

            GeometryReader { geo in
                VStack(spacing: 0) {
                    moduleHeader(
                        name: "ImpossiBLE",
                        detail: "Bluetooth LE",
                        color: ImpossiBLESection.statusColor(mode: bleController.mode, status: bleTransport.status),
                        isExpanded: $bleCollapsed.inverted
                    ) {
                        Image(nsImage: FontAwesome.brandImage(FontAwesome.bluetoothB, size: 14))
                    }
                    if !bleCollapsed {
                        blePane
                    }
                    if bothExpanded {
                        splitter
                    } else {
                        Divider()
                    }

                    moduleHeader(
                        name: "CAMouflage",
                        detail: "Camera",
                        color: CAMouflageSection.statusColor(
                            mode: camController.mode,
                            status: camTransport.status,
                            trafficActive: camServer.trafficActive
                        ),
                        isExpanded: $camCollapsed.inverted
                    ) {
                        Image(systemName: "camera.aperture")
                            .font(.caption)
                    }
                    if !camCollapsed {
                        // Scrollable so the camera content stays reachable no
                        // matter how small its pane is; with the frozen-pane
                        // drag this resizes once per release, not per tick.
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
                        name: "NFCromancer",
                        detail: "NFC",
                        color: NFCromancerSection.statusColor(mode: nfcController.mode, status: nfcTransport.status),
                        isExpanded: $nfcCollapsed.inverted
                    ) {
                        Image(systemName: "wave.3.right")
                            .font(.caption)
                    }
                    if !nfcCollapsed {
                        // The last pane is intrinsic: a fixed, scrollable height
                        // so the camera pane above keeps the flexible middle.
                        NFCromancerSection(
                            server: nfcServer,
                            transport: nfcTransport,
                            controller: nfcController,
                            showsClient: false
                        )
                        .frame(height: 280)
                    }
                    Divider()

                    moduleHeader(
                        name: "Simulacrum",
                        detail: "Seed Data",
                        color: seedStatusColor,
                        isExpanded: $seedCollapsed.inverted
                    ) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.caption)
                    }
                    if !seedCollapsed {
                        // Same intrinsic-height tail-pane treatment as
                        // NFCromancer: this module's content (device picker,
                        // short fixture list, Seed button) doesn't need
                        // flexible scrolling space, so it doesn't get its own
                        // splitter.
                        SimulacrumSection(
                            transport: seedTransport,
                            fixtureStore: fixtureStore,
                            runner: seedRunner
                        )
                        .frame(height: 280)
                    }
                    if bleCollapsed && camCollapsed && nfcCollapsed && seedCollapsed {
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .onAppear { modulesHeight = geo.size.height }
                .onChange(of: geo.size.height) { _, newValue in
                    modulesHeight = newValue
                }
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

    // MARK: - Pane sizing

    @ViewBuilder
    private var blePane: some View {
        let section = ImpossiBLESection(
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
        if bothExpanded {
            section.frame(height: clampedBLEHeight)
        } else {
            section.frame(maxHeight: .infinity)
        }
    }

    private var clampedBLEHeight: CGFloat {
        min(max(blePaneHeight, Self.blePaneMinHeight), maxBLEHeight)
    }

    /// Keeps the camera pane usable: module headers and the splitter are
    /// subtracted from what the modules region offers.
    private var maxBLEHeight: Double {
        max(Self.blePaneMinHeight, Double(modulesHeight) - Self.camPaneMinHeight - 2 * 28 - 9)
    }

    private var splitter: some View {
        ZStack {
            Divider()
            Capsule()
                .fill(dragProposal == nil ? Color.secondary.opacity(0.4) : Color.accentColor)
                .frame(width: 36, height: 4)
                // The grip travels with the cursor while the panes hold still;
                // offset moves the layer without triggering any layout.
                .offset(y: CGFloat((dragProposal ?? clampedBLEHeight) - clampedBLEHeight))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 9)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragBaseHeight == nil {
                        dragBaseHeight = clampedBLEHeight
                    }
                    let proposed = (dragBaseHeight ?? blePaneHeight) + value.translation.height
                    dragProposal = (min(max(proposed, Self.blePaneMinHeight), maxBLEHeight)).rounded()
                }
                .onEnded { _ in
                    if let dragProposal {
                        withAnimation(.easeOut(duration: 0.12)) {
                            blePaneHeight = dragProposal
                        }
                    }
                    dragProposal = nil
                    dragBaseHeight = nil
                }
        )
        .help("Drag to divide the space between the modules")
    }

    private func clientText(_ client: SocketClientInfo) -> String {
        guard let version = client.libraryVersion else { return client.displayText }
        return "\(client.displayText) · lib \(version)"
    }

    private func moduleHeader<Icon: View>(
        name: String,
        detail: String,
        color: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                icon()
                    .foregroundStyle(color)
                    .frame(width: 16, alignment: .trailing)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
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
        .accessibilityLabel("\(name), \(isExpanded.wrappedValue ? "expanded" : "collapsed")")
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

private extension Binding where Value == Bool {
    /// @AppStorage stores "collapsed" (so fresh installs start expanded), but
    /// the header reads more naturally in terms of "expanded".
    var inverted: Binding<Bool> {
        Binding(get: { !wrappedValue }, set: { wrappedValue = !$0 })
    }
}
