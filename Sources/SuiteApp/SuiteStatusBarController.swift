import AppKit
import Combine
import SwiftUI
import ImpossiBLEProviderKit
import CAMouflageProviderKit
import NFCromancerProviderKit
import SimBridgeServer
import SimBridgeShell

/// The suite's single menu bar presence. The status item and control panel
/// machinery come from SimBridgeShell; this class contributes the composite
/// icon — one glyph per active module, each in its product's state language —
/// the stacked panel content, and ImpossiBLE's document windows.
@MainActor
final class SuiteStatusBarController: NSObject, NSWindowDelegate {
    private let store: MockStore
    private let bleServer: MockServer
    private let bleController: ModeTransitionController<ProviderMode>
    private let camServer: MockCameraServer
    private let camCatalog: CameraCatalog
    private let camController: ModeTransitionController<ProviderMode>
    private let nfcServer: TagServer
    private let nfcController: ModeTransitionController<ProviderMode>
    private var panel: StatusItemPanelController!
    private var captureWindow: NSWindow?
    private var deviceWindows: [UUID: NSWindow] = [:]
    private var cancellables: Set<AnyCancellable> = []

    /// As tall as the screen comfortably allows: two stacked provider
    /// sections want vertical room, but the panel must never outgrow the
    /// menu bar screen's visible frame.
    private static var contentSize: NSSize {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 900
        let height = min(1080, max(700, visibleHeight - 60))
        return NSSize(width: 440, height: height)
    }

    init(
        store: MockStore,
        bleServer: MockServer,
        bleController: ModeTransitionController<ProviderMode>,
        camServer: MockCameraServer,
        camCatalog: CameraCatalog,
        camController: ModeTransitionController<ProviderMode>,
        nfcServer: TagServer,
        nfcController: ModeTransitionController<ProviderMode>
    ) {
        self.store = store
        self.bleServer = bleServer
        self.bleController = bleController
        self.camServer = camServer
        self.camCatalog = camCatalog
        self.camController = camController
        self.nfcServer = nfcServer
        self.nfcController = nfcController
        super.init()
        panel = StatusItemPanelController(
            title: "Simsalabim",
            toolTip: "Simsalabim",
            contentSize: Self.contentSize
        ) { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(SuitePanelContent(
                store: self.store,
                bleServer: self.bleServer,
                bleTransport: self.bleServer.transport,
                bleActivity: self.bleServer.passthroughActivity,
                bleController: self.bleController,
                camServer: self.camServer,
                camTransport: self.camServer.transport,
                camCatalog: self.camCatalog,
                camController: self.camController,
                nfcServer: self.nfcServer,
                nfcTransport: self.nfcServer.transport,
                nfcController: self.nfcController,
                onDismiss: { [weak self] in self?.panel.hidePanel() },
                onOpenCapture: { [weak self] in self?.openCaptureWindow() },
                onOpenDevice: { [weak self] deviceId in self?.openDeviceEditor(deviceId) }
            ))
        }
        observeIconState()
        updateIcon()
        // Selecting a different Mac camera while Passthrough is active must
        // switch the live source, mirroring the standalone app.
        camCatalog.$selectedDeviceID
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] deviceID in
                guard let self, self.camController.mode == .passthrough else { return }
                self.camServer.selectPassthroughDevice(deviceID)
            }
            .store(in: &cancellables)
    }

    private func observeIconState() {
        // @Published emits in willSet; hop through the main queue so
        // updateIcon() runs after didSet.
        let triggers: [AnyPublisher<Void, Never>] = [
            bleServer.transport.$status.map { _ in }.eraseToAnyPublisher(),
            bleServer.transport.$trafficActive.map { _ in }.eraseToAnyPublisher(),
            bleServer.passthroughActivity.$trafficActive.map { _ in }.eraseToAnyPublisher(),
            bleController.$mode.map { _ in }.eraseToAnyPublisher(),
            camServer.transport.$status.map { _ in }.eraseToAnyPublisher(),
            camServer.$trafficActive.map { _ in }.eraseToAnyPublisher(),
            camController.$mode.map { _ in }.eraseToAnyPublisher(),
            nfcServer.transport.$status.map { _ in }.eraseToAnyPublisher(),
            nfcServer.transport.$trafficActive.map { _ in }.eraseToAnyPublisher(),
            nfcController.$mode.map { _ in }.eraseToAnyPublisher(),
        ]
        for trigger in triggers {
            trigger
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.updateIcon() }
                .store(in: &cancellables)
        }
    }

    /// Wand as the brand anchor, plus one glyph per active module carrying its
    /// product's state language: dot-badged when mocking, plain when
    /// forwarding, flashing on traffic.
    private func updateIcon() {
        var segments: [NSImage] = []

        if let wand = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Simsalabim")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)) {
            segments.append(wand)
        }

        if bleController.mode != .off {
            segments.append(FontAwesome.brandImage(
                FontAwesome.bluetoothB,
                size: 14,
                active: bleServer.transport.trafficActive || bleServer.passthroughActivity.trafficActive,
                mode: bleController.mode == .passthrough ? .passthrough : .mock
            ))
        }

        if camController.mode != .off {
            let name = camServer.trafficActive ? "video.fill" : "video"
            if let video = NSImage(systemSymbolName: name, accessibilityDescription: "CAMouflage")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)) {
                segments.append(video)
            }
        }

        if nfcController.mode != .off {
            let name = nfcServer.transport.trafficActive ? "wave.3.right.circle.fill" : "wave.3.right"
            if let nfc = NSImage(systemSymbolName: name, accessibilityDescription: "NFCromancer")?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)) {
                segments.append(nfc)
            }
        }

        panel.setIcon(Self.compose(segments))
    }

    private static func compose(_ segments: [NSImage]) -> NSImage {
        let gap: CGFloat = 3
        let height: CGFloat = 18
        let width = segments.reduce(0) { $0 + $1.size.width } + gap * CGFloat(max(0, segments.count - 1))
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        var x: CGFloat = 0
        for segment in segments {
            let y = (height - segment.size.height) / 2
            segment.draw(in: NSRect(x: x, y: y, width: segment.size.width, height: segment.size.height))
            x += segment.size.width + gap
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Document windows (ImpossiBLE capture and device editors)

    private func openCaptureWindow() {
        panel.hidePanel()
        if let captureWindow {
            captureWindow.makeKeyAndOrderFront(nil)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            return
        }

        let root = CaptureSheet(
            store: store,
            onClose: { [weak self] in self?.captureWindow?.close() }
        )
        .background(DeviceEditorWindowActivator())

        let window = makeDocumentWindow(
            title: "Capture Nearby Devices",
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            rootView: root
        )
        window.identifier = NSUserInterfaceItemIdentifier("capture")
        window.delegate = self
        captureWindow = window
        showDocumentWindow(window)
    }

    private func openDeviceEditor(_ deviceId: UUID) {
        panel.hidePanel()
        if let window = deviceWindows[deviceId] {
            showDocumentWindow(window)
            return
        }

        let root = NavigationStack {
            DeviceEditorWindowContent(deviceId: deviceId, store: store)
        }
        .background(DeviceEditorWindowActivator())
        .frame(minWidth: 720, minHeight: 760)

        let window = makeDocumentWindow(
            title: "Device Editor",
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 820),
            rootView: root
        )
        window.identifier = NSUserInterfaceItemIdentifier("device-\(deviceId.uuidString)")
        window.delegate = self
        deviceWindows[deviceId] = window
        showDocumentWindow(window)
    }

    private func makeDocumentWindow<Content: View>(
        title: String,
        contentRect: NSRect,
        rootView: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(rootView: rootView)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func showDocumentWindow(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApplication.shared.activate()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            guard let window = notification.object as? NSWindow else { return }
            if window === self.captureWindow {
                self.captureWindow = nil
                return
            }
            guard let identifier = window.identifier?.rawValue,
                  identifier.hasPrefix("device-")
            else { return }
            let uuidString = String(identifier.dropFirst("device-".count))
            if let uuid = UUID(uuidString: uuidString) {
                self.deviceWindows[uuid] = nil
            }
        }
    }
}
