import Foundation
import SimBridgeShell
import SuiteControlProtocol

/// Turns a decoded `ControlRequest` into a `ControlResponse` by driving the
/// same `ModeTransitionController`s the menu-bar UI uses — no separate
/// control path, just a second caller.
@MainActor
final class SuiteControlHandler {
    private static let settleTimeout: TimeInterval = 10

    private let bleController: ModeTransitionController<ProviderMode>
    private let camController: ModeTransitionController<ProviderMode>
    private let nfcController: ModeTransitionController<ProviderMode>

    init(
        bleController: ModeTransitionController<ProviderMode>,
        camController: ModeTransitionController<ProviderMode>,
        nfcController: ModeTransitionController<ProviderMode>
    ) {
        self.bleController = bleController
        self.camController = camController
        self.nfcController = nfcController
    }

    func handle(_ request: ControlRequest) async -> ControlResponse {
        switch request.command {
            case .status:
                statusResponse()
            case .setMode:
                await setModeResponse(module: request.module, mode: request.mode)
        }
    }

    private func statusResponse() -> ControlResponse {
        ControlResponse(modules: [
            "impossible": status(of: bleController),
            "camouflage": status(of: camController),
            "nfcromancer": status(of: nfcController),
        ])
    }

    private func setModeResponse(module moduleName: String?, mode modeName: String?) async -> ControlResponse {
        guard let moduleName, let controller = controller(named: moduleName) else {
            return ControlResponse(error: .invalidModule, message: "Unknown module \"\(moduleName ?? "")\"")
        }
        guard let modeName, let mode = ProviderMode(rawValue: modeName) else {
            return ControlResponse(error: .invalidMode, message: "Unknown mode \"\(modeName ?? "")\"")
        }

        controller.select(mode)
        guard await waitForSettled(controller) else {
            return ControlResponse(error: .timeout, message: "Timed out waiting for \(moduleName) to switch to \(modeName)")
        }
        return ControlResponse(module: moduleName, mode: controller.mode.rawValue, isSwitching: controller.isSwitching)
    }

    private func controller(named moduleName: String) -> ModeTransitionController<ProviderMode>? {
        switch moduleName {
            case "impossible": bleController
            case "camouflage": camController
            case "nfcromancer": nfcController
            default: nil
        }
    }

    private func status(of controller: ModeTransitionController<ProviderMode>) -> ControlModuleStatus {
        ControlModuleStatus(mode: controller.mode.rawValue, isSwitching: controller.isSwitching)
    }

    private func waitForSettled(_ controller: ModeTransitionController<ProviderMode>) async -> Bool {
        let deadline = Date().addingTimeInterval(Self.settleTimeout)
        while controller.isSwitching {
            guard Date() < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }
}
