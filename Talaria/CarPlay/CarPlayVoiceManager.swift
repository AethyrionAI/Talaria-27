import CarPlay
import UIKit

/// Bridges `TalkStore` voice state to the CarPlay `CPVoiceControlTemplate`.
/// The current public CarPlay SDK exposes stateful voice control visuals but
/// not per-state action buttons, so this manager presents status only.
@MainActor
final class CarPlayVoiceManager {
    private static let maxTranscriptTitleLength = 80

    private let interfaceController: CPInterfaceController
    private var voiceTemplate: CPVoiceControlTemplate?
    private var observationTask: Task<Void, Never>?
    private var currentSpeakingTitle: String?
    private var lastSyncedStateID: String?
    private var talkStore: TalkStore { AppContainer.sharedDefault().talkStore }

    // MARK: - Voice Control State Identifiers

    private enum StateID {
        static let idle = "idle"
        static let listening = "listening"
        static let thinking = "thinking"
        static let speaking = "speaking"
        static let connecting = "connecting"
    }

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    // MARK: - Lifecycle

    func configure() {
        let initialSpeakingTitle = lastAssistantText()
        currentSpeakingTitle = initialSpeakingTitle
        setTemplate(
            speakingTitle: initialSpeakingTitle,
            activeStateID: currentStateIdentifier()
        )

        if talkStore.isSessionActive {
            syncState()
        }

        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.syncState()
            }
        }
    }

    func tearDown() {
        observationTask?.cancel()
        observationTask = nil
        voiceTemplate = nil
        lastSyncedStateID = nil
    }

    // MARK: - Template Construction

    private func setTemplate(speakingTitle: String?, activeStateID: String?) {
        let template = buildVoiceControlTemplate(speakingTitle: speakingTitle)
        voiceTemplate = template
        interfaceController.setRootTemplate(template, animated: false) { _, _ in
            guard let activeStateID else { return }
            template.activateVoiceControlState(withIdentifier: activeStateID)
        }
    }

    private func buildVoiceControlTemplate(speakingTitle: String?) -> CPVoiceControlTemplate {
        let idle = CPVoiceControlState(
            identifier: StateID.idle,
            titleVariants: ["Tap Start to talk to Hermes", "Talk to Hermes"],
            image: UIImage(systemName: "brain.head.profile")!,
            repeats: false
        )

        let connecting = CPVoiceControlState(
            identifier: StateID.connecting,
            titleVariants: ["Connecting to Hermes...", "Connecting..."],
            image: UIImage(systemName: "antenna.radiowaves.left.and.right")!,
            repeats: true
        )

        let listening = CPVoiceControlState(
            identifier: StateID.listening,
            titleVariants: ["Listening...", "Go ahead"],
            image: UIImage(systemName: "waveform")!,
            repeats: true
        )

        let thinking = CPVoiceControlState(
            identifier: StateID.thinking,
            titleVariants: ["Thinking...", "Working on it"],
            image: UIImage(systemName: "gear")!,
            repeats: true
        )

        let speaking = CPVoiceControlState(
            identifier: StateID.speaking,
            titleVariants: [speakingTitle ?? "Hermes is speaking", "Hermes is speaking"],
            image: UIImage(systemName: "speaker.wave.2.fill")!,
            repeats: false
        )

        return CPVoiceControlTemplate(
            voiceControlStates: [idle, connecting, listening, thinking, speaking]
        )
    }

    // MARK: - State Sync

    private func currentStateIdentifier() -> String {
        guard talkStore.isSessionActive else { return StateID.idle }

        switch talkStore.connectionState {
        case .connecting, .checking:
            return StateID.connecting
        default:
            break
        }

        switch talkStore.voiceState {
        case .listening:
            return StateID.listening
        case .thinking:
            return StateID.thinking
        case .speaking:
            return StateID.speaking
        case .interrupted:
            return StateID.listening
        case .idle, .disconnected:
            return StateID.idle
        }
    }

    private func syncState() {
        guard voiceTemplate != nil else { return }

        let stateID = currentStateIdentifier()
        let latestTitle = lastAssistantText()

        if latestTitle != currentSpeakingTitle {
            currentSpeakingTitle = latestTitle
            lastSyncedStateID = stateID
            setTemplate(speakingTitle: latestTitle, activeStateID: stateID)
            return
        }

        if stateID != lastSyncedStateID {
            lastSyncedStateID = stateID
            voiceTemplate?.activateVoiceControlState(withIdentifier: stateID)
        }
    }

    private func lastAssistantText() -> String {
        let lastAssistant = talkStore.transcriptItems.reversed().first(where: { $0.speaker == .hermes })
        let trimmed = lastAssistant?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Hermes is speaking" }
        return String(trimmed.prefix(Self.maxTranscriptTitleLength))
    }
}
