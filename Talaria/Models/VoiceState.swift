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
        case .disconnected: Color.white.opacity(0.15)
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
    var relayBootstrapReceivedAt: Date? = nil
    var realtimeConnectedAt: Date? = nil
    var firstUserFinalizedAt: Date? = nil
    var firstAssistantFinalizedAt: Date? = nil

    var bootstrapLatency: TimeInterval? {
        guard let sessionStartRequestedAt, let relayBootstrapReceivedAt else { return nil }
        return relayBootstrapReceivedAt.timeIntervalSince(sessionStartRequestedAt)
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

/// Read-only detail from the relay's talk/readiness probe. All fields are
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
}

enum TalkSessionEvent: Hashable, Sendable {
    case snapshot(TalkSessionSnapshot)
}
