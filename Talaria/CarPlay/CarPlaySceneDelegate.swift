import CarPlay
import UIKit

/// Manages the CarPlay scene lifecycle. When the vehicle connects,
/// we set up a `CPVoiceControlTemplate` as the root — Hermes is a
/// voice-first AI agent, so the CarPlay experience is just Voice Mode.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var voiceManager: CarPlayVoiceManager?

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController

        let manager = CarPlayVoiceManager(interfaceController: interfaceController)
        self.voiceManager = manager

        Task { @MainActor in
            manager.configure()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        // Do NOT end the voice session — it continues on the phone.
        // Just release CarPlay-specific references.
        voiceManager?.tearDown()
        voiceManager = nil
        self.interfaceController = nil
    }
}
