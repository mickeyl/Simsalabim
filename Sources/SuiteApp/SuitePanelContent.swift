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
    private static let launchAgent = LaunchAtLogin(label: "de.vanille.simsalabim")

    var body: some View {
        VStack(spacing: 0) {
            header
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
                controller: camController
            )
            .padding(12)
            Divider()

            footer
        }
        .background(Color.clear)
    }

    private var header: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("Simsalabim")
                    .font(.headline)
                Text(appVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
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
