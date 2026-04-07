import CarPlay
import UIKit

/// Bridges `TalkStore` voice state to the CarPlay `CPVoiceControlTemplate`.
/// Provides interactive controls: start session, mute, end, and interrupt.
/// Per iOS 26.4 Voice-Based Conversational category, `CPVoiceControlTemplate`
/// is the primary interface with action buttons below the voice visualization.
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
        setTemplate(speakingTitle: initialSpeakingTitle)

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

    private func setTemplate(speakingTitle: String?) {
        let template = buildVoiceControlTemplate(speakingTitle: speakingTitle)
        voiceTemplate = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
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

        let template = CPVoiceControlTemplate(
            voiceControlStates: [idle, connecting, listening, thinking, speaking]
        )

        // Action buttons appear below the voice visualization.
        // Which buttons are visible depends on current state — rebuilt on each sync.
        template.actionButtons = buildActionButtons()

        return template
    }

    // MARK: - Action Buttons

    /// Builds context-appropriate action buttons for the current voice state.
    /// - Idle: Start button
    /// - Active session: Mute toggle + End Session
    /// - Speaking: Interrupt button + Mute + End
    private func buildActionButtons() -> [CPButton] {
        if !talkStore.isSessionActive {
            return [startButton()]
        }

        var buttons: [CPButton] = []

        // Interrupt button when assistant is speaking
        if talkStore.voiceState == .speaking {
            buttons.append(interruptButton())
        }

        // Mute toggle
        buttons.append(muteButton())

        // End session
        buttons.append(endButton())

        return buttons
    }

    private func startButton() -> CPButton {
        let button = CPButton(
            image: UIImage(systemName: "play.fill")!,
            handler: { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.talkStore.startSessionDirectly()
                }
            }
        )
        button.title = "Start"
        return button
    }

    private func muteButton() -> CPButton {
        let isMuted = talkStore.isMuted
        let button = CPButton(
            image: UIImage(systemName: isMuted ? "mic.slash.fill" : "mic.fill")!,
            handler: { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.talkStore.toggleMute()
                    // Rebuild buttons to reflect new mute state
                    self.voiceTemplate?.actionButtons = self.buildActionButtons()
                }
            }
        )
        button.title = isMuted ? "Unmute" : "Mute"
        return button
    }

    private func endButton() -> CPButton {
        let button = CPButton(
            image: UIImage(systemName: "xmark.circle.fill")!,
            handler: { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    await self.talkStore.endSession()
                }
            }
        )
        button.title = "End"
        return button
    }

    private func interruptButton() -> CPButton {
        let button = CPButton(
            image: UIImage(systemName: "hand.raised.fill")!,
            handler: { [weak self] _ in
                guard let self else { return }
                self.talkStore.interruptAssistant()
            }
        )
        button.title = "Stop"
        return button
    }

    // MARK: - State Sync

    private func syncState() {
        guard let template = voiceTemplate else { return }

        var stateID: String
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

        // Override with connection state if still connecting
        if talkStore.isSessionActive {
            switch talkStore.connectionState {
            case .connecting, .checking:
                stateID = StateID.connecting
            default:
                break
            }
        }

        // Only update if state actually changed to avoid unnecessary redraws
        if stateID != lastSyncedStateID {
            lastSyncedStateID = stateID
            template.actionButtons = buildActionButtons()
            template.activateVoiceControlState(withIdentifier: stateID)
        }
    }

    private func updateSpeakingTitleIfNeeded() {
        let latestTitle = lastAssistantText()
        guard latestTitle != currentSpeakingTitle else { return }

        currentSpeakingTitle = latestTitle
        setTemplate(speakingTitle: latestTitle)
        lastSyncedStateID = nil // Force re-sync after template rebuild
    }

    private func lastAssistantText() -> String {
        let lastAssistant = talkStore.transcriptItems.reversed().first(where: { $0.speaker == .hermes })
        let trimmed = lastAssistant?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "Hermes is speaking" }
        return String(trimmed.prefix(Self.maxTranscriptTitleLength))
    }
}
