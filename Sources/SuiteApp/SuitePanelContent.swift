import SwiftUI
import ImpossiBLEProviderKit
import CAMouflageProviderKit
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
    var onDismiss: (() -> Void)?
    var onOpenCapture: (() -> Void)?
    var onOpenDevice: ((UUID) -> Void)?

    @State private var dismissOnDeactivate = ShellPreferences.dismissControlWindowOnDeactivate
    @State private var launchAtLogin = SuitePanelContent.launchAgent.isEnabled
    @State private var confirmTermination = false
    private static let launchAgent = LaunchAtLogin(label: "de.vanille.simsalabim")

    var body: some View {
        VStack(spacing: 0) {
            header
            clientRow
            Divider()

            moduleHeader(
                name: "ImpossiBLE",
                detail: "Bluetooth LE",
                color: ImpossiBLESection.statusColor(mode: bleController.mode, status: bleTransport.status)
            ) {
                Image(nsImage: FontAwesome.brandImage(FontAwesome.bluetoothB, size: 14))
            }
            // Flexible: the BLE device/activity lists absorb whatever height
            // the panel has to spare; the camera section below is intrinsic.
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
            .frame(minHeight: 280, maxHeight: .infinity)
            Divider()

            moduleHeader(
                name: "CAMouflage",
                detail: "Camera",
                color: CAMouflageSection.statusColor(
                    mode: camController.mode,
                    status: camTransport.status,
                    trafficActive: camServer.trafficActive
                )
            ) {
                Image(systemName: "camera.aperture")
                    .font(.caption)
            }
            CAMouflageSection(
                server: camServer,
                transport: camTransport,
                catalog: camCatalog,
                controller: camController,
                showsClient: false
            )
            .padding(12)
            Divider()

            footer
        }
        .background(Color.clear)
    }

    private var header: some View {
        HStack {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("Simsalabim")
                    .font(.headline)
                Text(appVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 26, height: 26)
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
        let ble = bleTransport.connectedClient
        let cam = camTransport.connectedClient

        HStack(spacing: 6) {
            Image(systemName: "iphone")
                .font(.caption)
                .foregroundStyle(ble == nil && cam == nil ? Color.secondary : .green)

            VStack(alignment: .leading, spacing: 1) {
                if ble == nil && cam == nil {
                    Text("No simulator client connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let ble, let cam, ble.pid == cam.pid {
                    Text(clientText(ble))
                        .font(.caption)
                } else {
                    if let ble {
                        Text("Bluetooth: \(clientText(ble))")
                            .font(.caption)
                    }
                    if let cam {
                        Text("Camera: \(clientText(cam))")
                            .font(.caption)
                    }
                }
            }
            .lineLimit(1)

            Spacer()

            if ble != nil || cam != nil {
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
                        if ble != nil { bleTransport.terminateConnectedClient() }
                        if cam != nil, cam?.pid != ble?.pid { camTransport.terminateConnectedClient() }
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

    private func clientText(_ client: SocketClientInfo) -> String {
        guard let version = client.libraryVersion else { return client.displayText }
        return "\(client.displayText) · lib \(version)"
    }

    private func moduleHeader<Icon: View>(
        name: String,
        detail: String,
        color: Color,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 6) {
            icon()
                .foregroundStyle(color)
            Text(name)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
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
