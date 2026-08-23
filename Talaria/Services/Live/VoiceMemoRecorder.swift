@preconcurrency import AVFoundation
import Foundation
import OSLog

/// Records a voice memo to a local `.m4a` for the attachment path (#9).
///
/// Thin `AVAudioRecorder` wrapper: the audio never leaves the device — the
/// recording is transcribed on-device (`VoiceMemoTranscriber`) and only the
/// TRANSCRIPT ships, as a delimited text part through the #8 inlining branch.
/// The file itself stays staged locally for playback, including after send.
///
/// Audio-session ownership: the `.playAndRecord` session is claimed only for
/// the duration of the recording and released with
/// `.notifyOthersOnDeactivation` — TalkStore (WebRTC) and SpeechOutputService
/// (read-aloud) own the session at other times, so callers must refuse to
/// record while a Talk session is live (`TalkStore.isSessionActive`).
@MainActor
@Observable
final class VoiceMemoRecorder {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.aethyrion.talaria",
        category: "VoiceMemoRecorder"
    )

    private(set) var isRecording = false
    /// Elapsed recording time, updated ~10×/s while recording.
    private(set) var elapsed: TimeInterval = 0
    /// Normalized mic level 0…1 from `averagePower` metering — real signal,
    /// not a decorative animation ("real data only").
    private(set) var level: Double = 0

    private var recorder: AVAudioRecorder?

    /// **#399/#84** — the same guard the player grew, for the same reason: the
    /// voice engines share the ONE `AVAudioSession`, and `finishRecorder()`
    /// released it unconditionally. Recording is already refused while Talk is
    /// live (`VoiceMemoRecorderSheet`), so this is defence in depth rather
    /// than a demonstrated failure — but the sibling site is the one #383-G's
    /// lesson says to fix in the same pass, not to leave for the grep that
    /// finds it later.
    @ObservationIgnored private var didActivateAudioSession = false

    /// harness-visible (#216): the deactivation effect, injectable so a test
    /// drives `discard()` and observes whether the guard let it through.
    @ObservationIgnored var deactivateAudioSession: () -> Void = {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private var meterTask: Task<Void, Never>?
    private(set) var fileURL: URL?

    /// AAC mono at 44.1 kHz — speech-appropriate, small on disk, and a format
    /// `AVAudioFile` reads straight back for transcription and playback.
    private static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    func startRecording() async throws {
        guard !isRecording else { return }

        // Mic permission — same ladder LiveSpeechService uses for dictation.
        let microphoneStatus = AVAudioApplication.shared.recordPermission
        if microphoneStatus == .undetermined {
            guard await AVAudioApplication.requestRecordPermission() else {
                Self.logger.error("Voice memo: microphone permission denied at prompt")
                throw RecorderError.microphoneDenied
            }
        } else if microphoneStatus != .granted {
            Self.logger.error("Voice memo: microphone permission unavailable")
            throw RecorderError.microphoneDenied
        }

        let destination = Self.makeRecordingURL()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            didActivateAudioSession = true
            let recorder = try AVAudioRecorder(url: destination, settings: Self.settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                Self.logger.error("Voice memo: AVAudioRecorder.record() returned false")
                releaseAudioSessionIfOwned()
                throw RecorderError.recordingFailed
            }
            self.recorder = recorder
            fileURL = destination
        } catch let error as RecorderError {
            throw error
        } catch {
            Self.logger.error("Voice memo: recording setup failed: \(error.localizedDescription, privacy: .public)")
            releaseAudioSessionIfOwned()
            throw RecorderError.recordingFailed
        }

        isRecording = true
        elapsed = 0
        level = 0
        Self.logger.verbose("Voice memo recording started")

        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let recorder = self.recorder, self.isRecording else { break }
                recorder.updateMeters()
                self.elapsed = recorder.currentTime
                // averagePower is dBFS (−160…0); map to a 0…1 amplitude.
                let db = recorder.averagePower(forChannel: 0)
                self.level = Double(pow(10, max(db, -60) / 20))
            }
        }
    }

    /// Stops and returns the recorded file URL plus its duration.
    /// Returns nil if nothing was recorded.
    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        guard isRecording, let recorder, let fileURL else { return nil }
        let duration = recorder.currentTime
        finishRecorder()
        Self.logger.verbose("Voice memo recording stopped (\(Int(duration))s)")
        return (fileURL, duration)
    }

    /// Stops (if needed) and deletes the recording file.
    func discard() {
        finishRecorder()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        elapsed = 0
        level = 0
    }

    private func finishRecorder() {
        meterTask?.cancel()
        meterTask = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
        releaseAudioSessionIfOwned()
    }

    /// The #84 release, guarded — see `VoiceMemoPlayer` for the full note.
    @discardableResult
    private func releaseAudioSessionIfOwned() -> Bool {
        guard Self.shouldReleaseAudioSession(didActivate: didActivateAudioSession) else {
            return false
        }
        didActivateAudioSession = false
        deactivateAudioSession()
        return true
    }

    /// The #84 decision, pure for tests: never deactivate a session this
    /// instance did not activate.
    nonisolated static func shouldReleaseAudioSession(didActivate: Bool) -> Bool {
        didActivate
    }

    /// Recordings live beside the other staged attachments so the existing
    /// storage location (App Support/Talaria/Attachments) covers cleanup.
    private static func makeRecordingURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base
            .appendingPathComponent("Talaria", isDirectory: true)
            .appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("VoiceMemo-\(UUID().uuidString).m4a")
    }

    enum RecorderError: LocalizedError {
        case microphoneDenied
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                "Microphone access is required to record a voice memo."
            case .recordingFailed:
                "Recording could not be started."
            }
        }
    }
}
