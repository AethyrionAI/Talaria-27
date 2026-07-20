@preconcurrency import AVFoundation
import Foundation
import os

/// Local text-to-speech for Hermes replies (#2). Wraps `AVSpeechSynthesizer`
/// with an utterance queue: whole messages via `speak(_:messageID:)` (the
/// per-bubble speaker toggle), and streaming replies via
/// `enqueueStreamChunk` / `finishStream`, which buffer `assistant.delta`
/// chunks to sentence boundaries and enqueue per-sentence utterances —
/// there is no streaming-text TTS API, so sentence-buffering is the design,
/// not a workaround.
///
/// Read-aloud is gated off while a Talk session is active: Talk owns the
/// `.playAndRecord` audio session and re-categorizing it here would break
/// the realtime pipe. The gate is wired by AppContainer.
@MainActor
@Observable
final class SpeechOutputService: NSObject {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "SpeechOutput")

    /// The message currently being spoken — drives the speaker toggle in
    /// `MessageBubble`. Nil when idle.
    private(set) var speakingMessageID: UUID?
    var isSpeaking: Bool { speakingMessageID != nil }

    /// Mirrors `AVSpeechSynthesizer.personalVoiceAuthorizationStatus` so the
    /// Voice settings screen can render the opt-in state reactively.
    private(set) var personalVoiceAuthorization: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus

    /// True while a Talk session owns the audio session (wired by AppContainer).
    /// All entry points are no-ops while blocked.
    var isBlocked: (@MainActor () -> Bool)?
    /// When false, this instance never touches AVAudioSession — for the
    /// native voice pipeline (#18), which owns a `.playAndRecord` session
    /// that a `.playback` re-categorization here would break. The shared
    /// read-aloud instance keeps the default (true).
    var managesAudioSession = true
    /// True only between a successful `setActive(true)` here and our own
    /// release. The device log behind this flag (#84, 2026-07-16): the voice
    /// engines share the ONE AVAudioSession, and this instance was deactivating
    /// it dozens of times a minute during native voice sessions via
    /// `stop() -> releaseAudioSessionIfIdle()` even though it had never spoken
    /// or activated -- killing the live mic. Rule: never deactivate a session
    /// this instance did not activate.
    private var didActivateAudioSession = false
    /// Persisted voice identifier from UserSettings; nil = best system voice.
    var voiceIdentifierProvider: (@MainActor () -> String?)?
    /// Persisted speech rate from UserSettings (AVSpeechUtterance 0…1 scale).
    var rateProvider: (@MainActor () -> Double)?

    private let synthesizer = AVSpeechSynthesizer()
    /// Utterances enqueued and not yet finished/cancelled. Identity-keyed so a
    /// stale delegate callback from a stopped queue can never clear state that
    /// belongs to a newer playback.
    private var activeUtterances: Set<ObjectIdentifier> = []
    private var streamMessageID: UUID?
    private var streamBuffer = ""
    /// Everything streamed for the current message, raw deltas — what
    /// `finishStream` compares a shortened finish against to detect that
    /// content was retracted after enqueueing (#110).
    private var streamedText = ""

    override init() {
        personalVoiceAuthorization = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Whole-message playback

    func speak(_ text: String, messageID: UUID) {
        guard isBlocked?() != true else { return }
        stop()
        let spoken = Self.speechText(from: text)
        guard !spoken.isEmpty else { return }
        speakingMessageID = messageID
        enqueue(spoken)
    }

    /// Halts playback immediately and clears the queue and any stream buffer.
    func stop() {
        streamBuffer = ""
        streamMessageID = nil
        streamedText = ""
        activeUtterances.removeAll()
        _ = synthesizer.stopSpeaking(at: .immediate)
        speakingMessageID = nil
        releaseAudioSessionIfIdle()
    }

    // MARK: - Streaming playback (sentence-buffered)

    /// Feeds one `assistant.delta` chunk. Complete sentences are flushed to the
    /// synthesizer as individual utterances; the tail stays buffered until the
    /// next chunk or `finishStream`.
    func enqueueStreamChunk(_ delta: String, messageID: UUID) {
        guard isBlocked?() != true else { return }
        if streamMessageID != messageID {
            stop()
            streamMessageID = messageID
            speakingMessageID = messageID
        }
        streamBuffer += delta
        streamedText += delta
        let (sentences, remainder) = Self.splitFlushableSentences(from: streamBuffer)
        streamBuffer = remainder
        for sentence in sentences {
            let spoken = Self.speechText(from: sentence)
            guard !spoken.isEmpty else { continue }
            enqueue(spoken)
        }
    }

    /// Flushes whatever remains in the buffer and closes the stream. When
    /// `finishedContent` is passed and is SHORTER than what streamed
    /// (whitespace-folded), content was retracted after enqueueing — the #102
    /// loop breaker collapsing a degenerate run to one copy — so the pending
    /// queue is dropped instead of flushed: the ears must not finish a loop
    /// the transcript no longer shows (#110).
    func finishStream(messageID: UUID, finishedContent: String? = nil) {
        guard streamMessageID == messageID else { return }
        if let finishedContent,
           Self.shouldRetractSpeech(finishedContent: finishedContent, streamedText: streamedText) {
            stop()
            return
        }
        let tail = Self.speechText(from: streamBuffer)
        streamBuffer = ""
        streamMessageID = nil
        streamedText = ""
        if !tail.isEmpty {
            enqueue(tail)
        } else if activeUtterances.isEmpty {
            speakingMessageID = nil
            releaseAudioSessionIfIdle()
        }
    }

    /// Drops the stream without speaking the buffered tail (failed/interrupted
    /// runs). Utterances already enqueued finish naturally.
    func cancelStream(messageID: UUID) {
        guard streamMessageID == messageID else { return }
        streamBuffer = ""
        streamMessageID = nil
        streamedText = ""
        if activeUtterances.isEmpty {
            speakingMessageID = nil
            releaseAudioSessionIfIdle()
        }
    }

    // MARK: - Voices

    /// Speaks a short sample with the current voice/rate settings.
    func previewVoice() {
        speak("This is how Hermes replies will sound.", messageID: UUID())
    }

    /// #129: which instance auditions a voice from Settings. Mid-session the
    /// preview must ride the native pipeline's session-less instance — the
    /// chat instance re-categorizing the shared session `.playAndRecord →
    /// .playback` under a live capture engine was the #128 trigger. Outside
    /// a session the chat instance keeps previews at full `.playback`
    /// fidelity (#130). Selection only — neither instance's session
    /// management changes here (#106).
    static func previewInstance(
        sessionActive: Bool,
        chat: SpeechOutputService,
        native: SpeechOutputService
    ) -> SpeechOutputService {
        sessionActive ? native : chat
    }

    /// Personal Voice is opt-in (iOS 17+, physical device, user must have
    /// created one and enabled "Allow Apps to Request to Use"). Once
    /// authorized, personal voices simply appear in `availableVoices()`.
    func requestPersonalVoiceAuthorization() async {
        let status = await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        personalVoiceAuthorization = status
    }

    /// Voices for the picker: current-language voices (novelty voices
    /// excluded), best quality first. Personal voices ride along once
    /// authorized.
    nonisolated static func availableVoices() -> [AVSpeechSynthesisVoice] {
        let languagePrefix = String(AVSpeechSynthesisVoice.currentLanguageCode().prefix(2))
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languagePrefix) && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted {
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.name < $1.name
            }
    }

    /// Default when no voice is persisted: the highest-quality installed voice
    /// for the exact current language (premium > enhanced > default — premium
    /// voices are user-downloaded in Settings; bundled defaults are robotic).
    nonisolated static func defaultVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
        return best ?? AVSpeechSynthesisVoice(language: language)
    }

    // MARK: - Queue plumbing

    private func enqueue(_ text: String) {
        configurePlaybackAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        if let identifier = voiceIdentifierProvider?(),
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        } else {
            utterance.voice = Self.defaultVoice()
        }
        utterance.rate = Float(rateProvider?() ?? Double(AVSpeechUtteranceDefaultSpeechRate))
        activeUtterances.insert(ObjectIdentifier(utterance))
        synthesizer.speak(utterance)
    }

    private func utteranceCompleted(_ id: ObjectIdentifier) {
        activeUtterances.remove(id)
        guard activeUtterances.isEmpty, streamMessageID == nil else { return }
        speakingMessageID = nil
        releaseAudioSessionIfIdle()
    }

    /// `.playback` + `.spokenAudio` so replies read out over the silent switch
    /// and duck other audio. Never reached while Talk is active (gate above).
    ///
    /// Deliberately synchronous (the setActive off-main rider skips this
    /// service): activation must complete before `synthesizer.speak` on the
    /// same tick, and the release below is interlocked with the #106
    /// `didActivateAudioSession` gate — hopping either off-main could reorder
    /// activate/deactivate across a `stop()` → `speak()` boundary. Voice
    /// sessions never reach these calls anyway (the native pipeline's
    /// instance has `managesAudioSession == false`; the shared instance is
    /// gated off while Talk is active).
    private func configurePlaybackAudioSession() {
        guard managesAudioSession else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            didActivateAudioSession = true
        } catch {
            Self.logger.notice("audio session configure failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func releaseAudioSessionIfIdle() {
        guard Self.shouldReleaseAudioSession(
            managesSession: managesAudioSession,
            didActivate: didActivateAudioSession,
            utterancesIdle: activeUtterances.isEmpty,
            streamIdle: streamMessageID == nil
        ) else { return }
        didActivateAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The #84 release decision, pure for tests. `didActivate` is the
    /// load-bearing guard: a `stop()` from any caller (the AppContainer talk
    /// callback most of all) must be a session no-op unless THIS instance
    /// holds the activation -- otherwise it deactivates the voice engine's
    /// `.playAndRecord` session out from under a live mic.
    nonisolated static func shouldReleaseAudioSession(
        managesSession: Bool,
        didActivate: Bool,
        utterancesIdle: Bool,
        streamIdle: Bool
    ) -> Bool {
        managesSession && didActivate && utterancesIdle && streamIdle
    }

    // MARK: - Text preparation (pure — unit-tested)

    /// The #110 retract decision: true when the finished reply is shorter than
    /// the text that actually streamed — a shorter finish means content was
    /// retracted after the fact (the #102 degenerate-loop breaker rewriting
    /// "phrase phrase phrase" to one "phrase"), so pending speech must stop
    /// rather than flush. Whitespace-folded so chunk-join artifacts can never
    /// fake a length difference; a finish equal to or LONGER than the streamed
    /// text is a normal completion.
    nonisolated static func shouldRetractSpeech(finishedContent: String, streamedText: String) -> Bool {
        whitespaceFolded(finishedContent).count < whitespaceFolded(streamedText).count
    }

    /// Collapses every whitespace run (spaces, tabs, newlines) to a single
    /// space and trims the ends.
    private nonisolated static func whitespaceFolded(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Splits a streaming buffer into fully terminated sentences plus the
    /// still-accumulating remainder. A sentence flushes on a newline, or on a
    /// terminator (. ! ? …) followed by whitespace — "followed by" is the
    /// signal that the sentence actually ended and not mid-token ("3.14").
    nonisolated static func splitFlushableSentences(from buffer: String) -> (sentences: [String], remainder: String) {
        var sentences: [String] = []
        var current = ""
        var previousWasTerminator = false

        func flushCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sentences.append(trimmed) }
            current = ""
            previousWasTerminator = false
        }

        for character in buffer {
            if character == "\n" {
                flushCurrent()
                continue
            }
            if previousWasTerminator, character == " " || character == "\t" {
                flushCurrent()
                continue
            }
            current.append(character)
            previousWasTerminator = ".!?…".contains(character)
        }
        return (sentences, current)
    }

    /// Light markdown cleanup so the synthesizer doesn't read formatting
    /// tokens aloud. Deliberately shallow — code read aloud is awkward no
    /// matter what; this only strips the noise (fences, emphasis, headings,
    /// link URLs).
    nonisolated static func speechText(from markdown: String) -> String {
        var text = markdown
        // [label](url) → label
        text = text.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        // ``` fence lines (with optional language tag)
        text = text.replacingOccurrences(
            of: #"(?m)^\s*```[^\n]*$"#,
            with: "",
            options: .regularExpression
        )
        // inline code / emphasis / heading markers
        text = text.replacingOccurrences(
            of: #"[`*_#]+"#,
            with: "",
            options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechOutputService: AVSpeechSynthesizerDelegate {
    // Delegate callbacks arrive off the main actor under strict concurrency;
    // hop back with only the Sendable utterance identity.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceCompleted(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceCompleted(id) }
    }
}
