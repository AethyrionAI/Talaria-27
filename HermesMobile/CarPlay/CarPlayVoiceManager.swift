import CarPlay
import UIKit

/// Bridges `TalkStore` voice state to the CarPlay `CPVoiceControlTemplate`.
/// The manager observes voice state changes and activates the matching
/// CarPlay voice control state. Action buttons provide mute and end controls.
@MainActor
final class CarPlayVoiceManager {
    private static let maxTranscriptTitleLength = 80

    private let interfaceController: CPInterfaceController
    private var voiceTemplate: CPVoiceControlTemplate?
    private var observationTask: Task<Void, Never>?
    private var currentSpeakingTitle: String?

    // Reference to the shared app container
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

    /// Sets up the CPVoiceControlTemplate and starts observing TalkStore state.
    func configure() {
        let initialSpeakingTitle = lastAssistantText()
        currentSpeakingTitle = initialSpeakingTitle
        let template = buildVoiceControlTemplate(speakingTitle: initialSpeakingTitle)
        voiceTemplate = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)

        // If a voice session is already active (started on phone), pick it up
        if talkStore.isSessionActive {
            syncState()
        }

        // Observe voice state changes
        observationTask = Task { [weak self] in
            // Poll state at a reasonable interval — CPVoiceControlTemplate
            // doesn't support AsyncSequence observation, so we check periodically.
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
    }

    // MARK: - Template Construction

    private func buildVoiceControlTemplate(speakingTitle: String?) -> CPVoiceControlTemplate {
        let idle = CPVoiceControlState(
            identifier: StateID.idle,
            titleVariants: ["Tap to talk to Hermes", "Talk to Hermes"],
            image: UIImage(systemName: "brain.head.profile")!,
            repeats: false
        )

        let connecting = CPVoiceControlState(
            identifier: StateID.connecting,
            titleVariants: ["Connecting...", "Starting..."],
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

    private func syncState() {
        guard let template = voiceTemplate else { return }

        let stateID: String
        if !talkStore.isSessionActive {
            stateID = StateID.idle
        } else {
            switch talkStore.voiceState {
            case .idle, .disconnected:
                stateID = StateID.idle
            case .listening:
                stateID = StateID.listening
            case .thinking:
                stateID = StateID.thinking
            case .speaking:
                updateSpeakingTitleIfNeeded()
                stateID = StateID.speaking
            case .interrupted:
                stateID = StateID.listening
            }
        }

        // Also check connection state
        if talkStore.isSessionActive {
            switch talkStore.connectionState {
            case .connecting, .checking:
                template.activateVoiceControlState(withIdentifier: StateID.connecting)
                return
            default:
                break
            }
        }

        template.activateVoiceControlState(withIdentifier: stateID)
    }

    private func updateSpeakingTitleIfNeeded() {
        let latestTitle = lastAssistantText()
        guard latestTitle != currentSpeakingTitle else { return }

        currentSpeakingTitle = latestTitle
        let template = buildVoiceControlTemplate(speakingTitle: latestTitle)
        voiceTemplate = template
        interfaceController.setRootTemplate(template, animated: false) { [weak template] _, _ in
            guard let template else { return }
            template.activateVoiceControlState(withIdentifier: StateID.speaking)
        }
    }

    private func lastAssistantText() -> String {
        let lastAssistant = talkStore.transcriptItems.reversed().first(where: { $0.speaker == .hermes })
        let trimmed = lastAssistant?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Hermes is speaking" }
        return String(trimmed.prefix(Self.maxTranscriptTitleLength))
    }
}
