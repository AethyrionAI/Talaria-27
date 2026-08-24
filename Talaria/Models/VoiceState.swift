import SwiftUI

enum VoiceState: String, Codable, Hashable, Sendable, CaseIterable {
    case idle
    case listening
    case thinking
    case speaking
    case interrupted
    case disconnected

    var displayLabel: String {
        switch self {
        case .idle: "Ready"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .interrupted: "Interrupted"
        case .disconnected: "Disconnected"
        }
    }

    var displayIcon: String {
        switch self {
        case .idle: "mic.slash"
        case .listening: "mic.fill"
        case .thinking: "brain"
        case .speaking: "speaker.wave.2.fill"
        case .interrupted: "pause.circle.fill"
        case .disconnected: "wifi.slash"
        }
    }

    var displayColor: Color {
        switch self {
        case .idle: .secondary
        case .listening: .blue
        case .thinking: .purple
        case .speaking: .green
        case .interrupted: .orange
        // Adaptive: white on the dark themes (pre-theming value), ink on
        // Paper Tape via the root preferredColorScheme.
        case .disconnected: Color.primary.opacity(0.15)
        }
    }
}

enum TalkConnectionState: String, Codable, Hashable, Sendable {
    case idle
    case checking
    case ready
    case connecting
    case connected
    case blocked
    case failed

    var displayLabel: String {
        switch self {
        case .idle: "Idle"
        case .checking: "Checking"
        case .ready: "Ready"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .blocked: "Unavailable"
        case .failed: "Failed"
        }
    }
}

/// Which speech-to-speech engine is (or would be) driving the Talk session.
/// `.realtime` is the relay-bootstrapped OpenAI Realtime path over WebRTC;
/// `.native` is the on-device pipeline (SpeechAnalyzer → active chat backend →
/// AVSpeechSynthesizer, #18). The engines are presented distinctly — local
/// voice is never silently substituted for the Realtime experience.
enum VoiceEngine: String, Codable, Hashable, Sendable {
    case realtime
    case native

    var displayLabel: String {
        switch self {
        case .realtime: "Realtime"
        case .native: "Local voice"
        }
    }

    /// HUD-style mono label for headers and settings rows.
    var monoLabel: String {
        switch self {
        case .realtime: "REALTIME (OPENAI)"
        case .native: "LOCAL (ON-DEVICE)"
        }
    }
}

enum TranscriptSpeaker: String, Codable, Hashable, Sendable {
    case user
    case hermes
    case system

    var displayLabel: String {
        switch self {
        case .user: "You"
        case .hermes: "Hermes"
        case .system: "System"
        }
    }
}

struct TranscriptItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var speaker: TranscriptSpeaker
    var text: String
    var isPartial: Bool
    var imageData: Data?  // JPEG thumbnail for display in transcript

    init(
        id: UUID = UUID(),
        speaker: TranscriptSpeaker,
        text: String,
        isPartial: Bool = false,
        imageData: Data? = nil
    ) {
        self.id = id
        self.speaker = speaker
        self.text = text
        self.isPartial = isPartial
        self.imageData = imageData
    }
}

struct TalkLatencyMetrics: Codable, Hashable, Sendable {
    var sessionStartRequestedAt: Date? = nil
    /// #383 renamed this from `relayBootstrapReceivedAt` (2026-08-23 audit
    /// residue): the bootstrap rides the talaria plugin, not the relay.
    /// Field is optional-with-default, so any old serialized key decodes
    /// harmlessly to nil.
    var hostBootstrapReceivedAt: Date? = nil
    var realtimeConnectedAt: Date? = nil
    var firstUserFinalizedAt: Date? = nil
    var firstAssistantFinalizedAt: Date? = nil

    var bootstrapLatency: TimeInterval? {
        guard let sessionStartRequestedAt, let hostBootstrapReceivedAt else { return nil }
        return hostBootstrapReceivedAt.timeIntervalSince(sessionStartRequestedAt)
    }

    var connectLatency: TimeInterval? {
        guard let sessionStartRequestedAt, let realtimeConnectedAt else { return nil }
        return realtimeConnectedAt.timeIntervalSince(sessionStartRequestedAt)
    }

    var firstAssistantLatency: TimeInterval? {
        guard let sessionStartRequestedAt, let firstAssistantFinalizedAt else { return nil }
        return firstAssistantFinalizedAt.timeIntervalSince(sessionStartRequestedAt)
    }
}

/// #396: the coarse voice-sensitivity pick — three vetted presets, resolved
/// to concrete `turn_detection` values HOST-side (the app never composes the
/// block). Raw values are persisted in the settings blob — never rename.
/// **The honest asymmetry (Owen's ruled scope):** this binds real knobs on
/// the REALTIME engine only; on the local engine room-noise has no knob and
/// only end-of-turn timing could ever respond, and the picker's caption says
/// so rather than implying effect.
enum VoiceSensitivity: String, Codable, CaseIterable, Sendable {
    case quiet
    case normal
    case noisy

    var displayLabel: String {
        switch self {
        case .quiet: "QUIET"
        case .normal: "NORMAL"
        case .noisy: "NOISY"
        }
    }
}

/// Read-only detail from the voice readiness probe — the talaria plugin's
/// `talk_readiness` verb since #383, the relay's `talk/readiness` before it.
/// All fields are
/// optional — nil means the probe hasn't answered (or failed), rendered as
/// "—" per the real-data-only rule. Model + voice are server-managed; the
/// iOS surface has no set-voice, so these are display-only (#35).
struct TalkReadinessInfo: Hashable, Sendable {
    var hostOnline: Bool? = nil
    var configured: Bool? = nil
    var ready: Bool? = nil
    var selectedModel: String? = nil
    var voice: String? = nil
    var voiceContextUpdatedAt: Date? = nil
    /// #396: the tuning names the host's plugin accepts on the mint. nil =
    /// the host predates tuning (UNKNOWN, never empty) — the picker's
    /// footnote states that instead of implying effect.
    var tunings: [String]? = nil
}

struct TalkSessionSnapshot: Hashable, Sendable {
    var voiceState: VoiceState
    var connectionState: TalkConnectionState
    var transcriptItems: [TranscriptItem]
    var sessionDuration: TimeInterval
    var isMuted: Bool
    var blockedReason: String?
    var statusMessage: String?
    var canStartSession: Bool
    var latencyMetrics: TalkLatencyMetrics
    var voiceSessionID: UUID?
    var readiness: TalkReadinessInfo = TalkReadinessInfo()
    /// #180 lane 180-L (bar 180-C) — **nil means NO ENGINE HAS BEEN SELECTED
    /// YET, and that is a real state rather than a missing value.**
    ///
    /// ~~Defaults to `.realtime` — the historical engine — so existing snapshot
    /// construction sites read unchanged (#18).~~ That default was the
    /// optimistic-default form of `HostFedListPresentation`'s rule 5: a stored
    /// property whose declared default is the affirmative value, corrected only
    /// if a producer bothers to stamp it. `NativeVoicePipelineService` is the
    /// ONLY producer that ever stamped it, so every realtime-path and
    /// pre-session snapshot silently claimed the Realtime engine and the
    /// overlay header printed "VOICE LINK · CONNECTING" in states where nothing
    /// had chosen an engine at all — including the up-to-12s realtime start
    /// budget that ends in a fallback to native. That is #139's unasserted
    /// residual, and it turned out to be this line rather than a runtime
    /// routing question.
    var engine: VoiceEngine? = nil
    /// #84: non-fatal mic-health warning from the flatline tripwire — the
    /// session is connected but no speech evidence has arrived. nil = healthy
    /// or not yet evaluated.
    var micHealthHint: String? = nil
    /// #84: human-readable current audio route ("iPhone Microphone →
    /// Speaker"). nil when no session has populated it.
    var audioRouteSummary: String? = nil
}

enum TalkSessionEvent: Hashable, Sendable {
    case snapshot(TalkSessionSnapshot)
}
