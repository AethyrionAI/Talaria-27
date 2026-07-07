import CarPlay
import Observation
import UIKit

/// Bridges `TalkStore` voice state to the CarPlay `CPVoiceControlTemplate`.
/// The current public CarPlay SDK exposes stateful voice control visuals but
/// not per-state action buttons — by design for the voice-based
/// conversational category, the app launches straight into voice (#19):
/// connect auto-starts a Talk session (gated on `canStartSession`), the mic
/// is then continuously live, and this template only reflects
/// listening/thinking/speaking. Readiness failures surface as a blocked
/// state carrying `blockedReason` — never a dead idle screen.
@MainActor
final class CarPlayVoiceManager {
    private static let maxTranscriptTitleLength = 80

    private let interfaceController: CPInterfaceController
    private var voiceTemplate: CPVoiceControlTemplate?
    /// Gate for the `withObservationTracking` re-arm loop — flipped off in
    /// tearDown so a stale onChange can't re-subscribe after disconnect.
    private var isObserving = false
    private var autoStartTask: Task<Void, Never>?
    private var currentSpeakingTitle: String?
    private var currentBlockedTitle: String?
    private var lastSyncedStateID: String?
    private var talkStore: TalkStore { AppContainer.sharedDefault().talkStore }

    // MARK: - Voice Control State Identifiers

    enum StateID {
        static let idle = "idle"
        static let listening = "listening"
        static let thinking = "thinking"
        static let speaking = "speaking"
        static let connecting = "connecting"
        static let blocked = "blocked"
    }

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    // MARK: - Lifecycle

    func configure() {
        let initialSpeakingTitle = lastAssistantText()
        currentSpeakingTitle = initialSpeakingTitle
        currentBlockedTitle = Self.blockedTitle(reason: talkStore.blockedReason)
        setTemplate(
            speakingTitle: initialSpeakingTitle,
            blockedTitle: currentBlockedTitle,
            activeStateID: currentStateIdentifier()
        )

        startObservation()
        autoStartSessionIfNeeded()
    }

    func tearDown() {
        isObserving = false
        autoStartTask?.cancel()
        autoStartTask = nil
        voiceTemplate = nil
        lastSyncedStateID = nil
        // Deliberately does NOT end the voice session — it continues on the
        // phone (CarPlaySceneDelegate contract).
    }

    // MARK: - Auto-start (#19)

    /// `CPVoiceControlTemplate` gives no tappable button by SDK design, so
    /// connect is the trigger. The phone may be cold-launched by the car —
    /// `canStartSession` is only meaningful after a readiness probe, so
    /// refresh first, then start; a not-ready result renders the blocked
    /// state with the honest reason instead of starting.
    private func autoStartSessionIfNeeded() {
        guard !talkStore.isSessionActive else { return }
        autoStartTask?.cancel()
        autoStartTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.talkStore.refreshReadiness()
            guard !Task.isCancelled else { return }
            guard !self.talkStore.isSessionActive else { return }
            guard self.talkStore.canStartSession else {
                self.syncState()
                return
            }
            await self.talkStore.startSessionDirectly()
        }
    }

    // MARK: - Observation (#19: replaces the 500ms polling Timer)

    private func startObservation() {
        isObserving = true
        observeTalkStore()
    }

    /// `withObservationTracking` is one-shot — each change hops back to the
    /// main actor, syncs the template, and re-arms.
    private func observeTalkStore() {
        guard isObserving else { return }
        withObservationTracking {
            _ = talkStore.voiceState
            _ = talkStore.connectionState
            _ = talkStore.isSessionActive
            _ = talkStore.transcriptItems
            _ = talkStore.canStartSession
            _ = talkStore.blockedReason
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isObserving else { return }
                self.syncState()
                self.observeTalkStore()
            }
        }
    }

    // MARK: - Template Construction

    private func setTemplate(speakingTitle: String?, blockedTitle: String?, activeStateID: String?) {
        let template = buildVoiceControlTemplate(speakingTitle: speakingTitle, blockedTitle: blockedTitle)
        voiceTemplate = template
        interfaceController.setRootTemplate(template, animated: false) { _, _ in
            guard let activeStateID else { return }
            template.activateVoiceControlState(withIdentifier: activeStateID)
        }
    }

    private func buildVoiceControlTemplate(speakingTitle: String?, blockedTitle: String?) -> CPVoiceControlTemplate {
        // No "Tap Start" copy — there is nothing to tap; the session
        // auto-starts on connect and idle is only a transient state.
        let idle = CPVoiceControlState(
            identifier: StateID.idle,
            titleVariants: ["Talk to Hermes"],
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

        let blocked = CPVoiceControlState(
            identifier: StateID.blocked,
            titleVariants: [blockedTitle ?? "Talk is unavailable", "Talk is unavailable"],
            image: UIImage(systemName: "exclamationmark.triangle")!,
            repeats: false
        )

        return CPVoiceControlTemplate(
            voiceControlStates: [idle, connecting, listening, thinking, speaking, blocked]
        )
    }

    // MARK: - State Sync

    private func currentStateIdentifier() -> String {
        Self.stateIdentifier(
            isSessionActive: talkStore.isSessionActive,
            canStartSession: talkStore.canStartSession,
            blockedReason: talkStore.blockedReason,
            connectionState: talkStore.connectionState,
            voiceState: talkStore.voiceState
        )
    }

    /// Pure mapping (unit-tested): TalkStore state → voice control state id.
    nonisolated static func stateIdentifier(
        isSessionActive: Bool,
        canStartSession: Bool,
        blockedReason: String?,
        connectionState: TalkConnectionState,
        voiceState: VoiceState
    ) -> String {
        guard isSessionActive else {
            // Not running: a probe/start that left a reason and no way to
            // start is the honest blocked surface; anything else is the
            // transient idle (auto-start is in flight or about to be).
            if !canStartSession, blockedReason != nil {
                return StateID.blocked
            }
            return StateID.idle
        }

        switch connectionState {
        case .connecting, .checking:
            return StateID.connecting
        default:
            break
        }

        switch voiceState {
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

    /// Car-length blocked title from a `blockedReason` (unit-tested).
    nonisolated static func blockedTitle(reason: String?) -> String? {
        guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else { return nil }
        return String(reason.prefix(maxTranscriptTitleLength))
    }

    private func syncState() {
        guard voiceTemplate != nil else { return }

        let stateID = currentStateIdentifier()
        let latestTitle = lastAssistantText()
        let latestBlockedTitle = Self.blockedTitle(reason: talkStore.blockedReason)

        // Title variants are baked into the states, so a changed speaking
        // title or blocked reason needs a template rebuild; a pure state
        // move just activates.
        if latestTitle != currentSpeakingTitle || latestBlockedTitle != currentBlockedTitle {
            currentSpeakingTitle = latestTitle
            currentBlockedTitle = latestBlockedTitle
            lastSyncedStateID = stateID
            setTemplate(speakingTitle: latestTitle, blockedTitle: latestBlockedTitle, activeStateID: stateID)
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
