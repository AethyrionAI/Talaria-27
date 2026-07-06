@preconcurrency import AVFoundation
import Foundation
import OSLog
@preconcurrency import Speech

/// On-device FILE transcription for voice-memo attachments (#9).
///
/// Sibling of `LiveSpeechService` (live composer dictation) on the same
/// iOS 26 SpeechAnalyzer stack, with two deliberate differences:
///  - `.longDictation` preset, NOT `.progressiveShortDictation` — a memo is
///    multi-minute long-form speech, and the short preset finalizes after one
///    utterance (truncation, the #9 anti-goal).
///  - Input is the recorded `AVAudioFile` via `analyzeSequence(from:)` —
///    iOS 26 first-class file analysis. iOS 27's `AssetInputSequenceProvider`
///    is beta convenience only and is deliberately NOT used here.
///
/// Fully offline: model assets are on-device (downloaded once by
/// `prepareToAnalyze`, same as the dictation path); no network is touched.
enum VoiceMemoTranscriber {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.aethyrion.talaria",
        category: "VoiceMemoTranscriber"
    )

    /// Transcribes the recording at `url` to plain text. Throws with a real,
    /// user-presentable reason on failure; an empty transcript (no speech
    /// detected) is a failure, never an empty attachment ("real data only").
    static func transcribe(url: URL) async throws -> String {
        // Speech authorization — same ladder as LiveSpeechService.
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        let status: SFSpeechRecognizerAuthorizationStatus
        if currentStatus == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        } else {
            status = currentStatus
        }
        guard status == .authorized else {
            Self.logger.error("Voice memo transcription: speech authorization denied")
            throw TranscriberError.unauthorized
        }

        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else {
            Self.logger.error("Voice memo transcription: no supported locale")
            throw TranscriberError.unavailable
        }

        // .longDictation: the long-form dictation preset (#9 report caveat) —
        // verify the preset name against the SDK on Mac (the dictation path's
        // .progressiveShortDictation is the proven sibling).
        let transcriber = DictationTranscriber(locale: locale, preset: .longDictation)
        var reservedLocale: Locale?
        if (try? await AssetInventory.reserve(locale: locale)) == true {
            reservedLocale = locale
        }
        defer {
            if let reservedLocale {
                Task { _ = await AssetInventory.release(reservedLocale: reservedLocale) }
            }
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            Self.logger.error("Voice memo transcription: unreadable audio file: \(error.localizedDescription, privacy: .public)")
            throw TranscriberError.unreadableAudio
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        // Triggers the one-time model-asset download when needed, with
        // progress — same call the proven dictation path makes.
        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: audioFile.processingFormat
        ) ?? audioFile.processingFormat
        try await analyzer.prepareToAnalyze(in: analyzerFormat) { progress in
            Self.logger.verbose("Voice memo speech asset progress completedUnitCount=\(progress.completedUnitCount)")
        }

        // Collect EVERY finalized result — long-form emits a series of
        // finalized ranges across a multi-minute file, and stopping at the
        // first (as the live dictation loop does) would truncate the memo.
        // Started before analysis so no early result can be missed.
        async let collected: String = collectFinalizedTranscript(from: transcriber)

        do {
            // iOS 26 file-analysis API — verify against SDK on Mac:
            // analyzeSequence(from:) returns the last analyzed time when the
            // file is exhausted; finalizeAndFinish(through:) flushes the tail
            // results and ends the results sequence.
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            Self.logger.error("Voice memo transcription failed: \(error.localizedDescription, privacy: .public)")
            throw TranscriberError.analysisFailed(error.localizedDescription)
        }

        let transcript = try await collected
        guard !transcript.isEmpty else {
            Self.logger.notice("Voice memo transcription: no speech detected")
            throw TranscriberError.noSpeechDetected
        }
        return transcript
    }

    private static func collectFinalizedTranscript(from transcriber: DictationTranscriber) async throws -> String {
        var pieces: [String] = []
        for try await result in transcriber.results where result.isFinal {
            pieces.append(String(result.text.characters))
        }
        // Sequential finalized ranges carry their own spacing (Apple's file-
        // transcription sample concatenates them directly) — verify on Mac
        // with a real multi-minute recording.
        return pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum TranscriberError: LocalizedError {
        case unauthorized
        case unavailable
        case unreadableAudio
        case noSpeechDetected
        case analysisFailed(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                "Speech recognition permission is required to transcribe voice memos."
            case .unavailable:
                "On-device transcription is not available for the current language."
            case .unreadableAudio:
                "The recording could not be read back for transcription."
            case .noSpeechDetected:
                "No speech was detected in the recording."
            case .analysisFailed(let reason):
                "Transcription failed: \(reason)"
            }
        }
    }
}
