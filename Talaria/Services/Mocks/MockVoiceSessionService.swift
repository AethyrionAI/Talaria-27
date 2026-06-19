import Foundation

@MainActor
@Observable
final class MockVoiceSessionService: VoiceSessionServiceProtocol {
    var voiceState: VoiceState = .idle { didSet { publishSnapshot() } }
    var connectionState: TalkConnectionState = .ready { didSet { publishSnapshot() } }
    var transcriptItems: [TranscriptItem] = [] { didSet { publishSnapshot() } }
    var sessionDuration: TimeInterval = 0 { didSet { publishSnapshot() } }
    var isMuted: Bool = false { didSet { publishSnapshot() } }
    var blockedReason: String? { didSet { publishSnapshot() } }
    var statusMessage: String? = "Mock talk mode is ready." { didSet { publishSnapshot() } }
    var canStartSession: Bool = true { didSet { publishSnapshot() } }
    var latencyMetrics = TalkLatencyMetrics() { didSet { publishSnapshot() } }

    var snapshot: TalkSessionSnapshot {
        TalkSessionSnapshot(
            voiceState: voiceState,
            connectionState: connectionState,
            transcriptItems: transcriptItems,
            sessionDuration: sessionDuration,
            isMuted: isMuted,
            blockedReason: blockedReason,
            statusMessage: statusMessage,
            canStartSession: canStartSession,
            latencyMetrics: latencyMetrics,
            voiceSessionID: nil
        )
    }

    private let eventHub = TalkSessionEventHub()
    private var sessionTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?

    func events() -> AsyncStream<TalkSessionEvent> {
        eventHub.stream(initial: snapshot)
    }

    func refreshReadiness() async {}

    func startSession() async {
        latencyMetrics = TalkLatencyMetrics(sessionStartRequestedAt: .now)
        connectionState = .connected
        voiceState = .listening
        sessionDuration = 0
        transcriptItems = []
        blockedReason = nil
        statusMessage = "Mock session connected."

        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled {
                    sessionDuration += 1
                }
            }
        }

        sessionTask = Task {
            transcriptItems = [
                TranscriptItem(speaker: .user, text: "What should I focus on today?", isPartial: false),
            ]

            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            voiceState = .thinking
            statusMessage = "Hermes is thinking."

            transcriptItems.append(
                TranscriptItem(
                    speaker: .hermes,
                    text: "You have one important follow-up waiting and a fresh location summary available.",
                    isPartial: true
                )
            )

            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            voiceState = .speaking
            statusMessage = "Hermes is speaking."
            transcriptItems[transcriptItems.count - 1].isPartial = false

            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            voiceState = .listening
            statusMessage = "Listening"
        }
    }

    func endSession() async {
        sessionTask?.cancel()
        timerTask?.cancel()
        sessionTask = nil
        timerTask = nil
        voiceState = .idle
        connectionState = .idle
        statusMessage = "Talk session ended."
    }

    func toggleMute() async {
        isMuted.toggle()
    }

    func manuallyInterruptAssistantOutput() {
        voiceState = .listening
        statusMessage = "Listening"
    }

    @discardableResult
    func sendImage(_ imageData: Data, mimeType: String = "image/jpeg", triggerResponse: Bool = true) -> Bool {
        return true
    }

    private func publishSnapshot() {
        eventHub.publish(snapshot: snapshot)
    }
}
