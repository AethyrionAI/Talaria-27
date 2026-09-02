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

    /// #198B: drop a second `startRecording` that lands during the first's
    /// transition — `guard !isRecording` alone cannot cover it, because
    /// `isRecording` is set only after the whole setup and the function
    /// suspends (permission prompt, off-main activation) before that. #128's
    /// class: two interleaved capture starts double-installed a tap and
    /// crashed a device.
    @ObservationIgnored private var isTransitioning = false

    /// #198B, the #397 generation pattern: a `discard()`/`finishRecorder()`
    /// that lands INSIDE a start's await window must end that start, not race
    /// it — the start re-checks its generation after every suspension and
    /// backs out (releasing anything it activated) when the world moved on.
    @ObservationIgnored private var startGeneration: UInt64 = 0

    /// harness-visible (#216): the deactivation effect, injectable so a test
    /// drives `discard()` and observes whether the guard let it through.
    ///
    /// #198B: async and AWAITED — see `VoiceMemoPlayer.deactivateAudioSession`
    /// for the ordering rule; off-main via `AudioSessionOffMain` because the
    /// sync spelling was the `AVAudioSession_iOS.mm:978` main-thread fault.
    @ObservationIgnored var deactivateAudioSession: () async -> Void = {
        try? await AudioSessionOffMain.setActive(
            false,
            options: .notifyOthersOnDeactivation,
            reason: "memo-record-stop"
        )
    }

    /// #198B: the activation half, seamed — see `VoiceMemoPlayer`'s twin.
    @ObservationIgnored var activateForRecording: () async throws -> Void = {
        try await AudioSessionOffMain.run(activating: true, reason: "memo-record-start") { session in
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        }
    }

    /// #198B: the mic-permission ladder, seamed so unit tests can drive the
    /// start TRANSITION without a real TCC prompt parking the suite forever
    /// (the lane gate's founding hang class — a brand-new sim has no record
    /// at all, so the request blocks instead of failing). The default is the
    /// REAL ladder — same shape LiveSpeechService uses for dictation — and
    /// is structurally pinned as the only spelling in this file.
    @ObservationIgnored var requestRecordPermission: () async -> Bool = {
        let status = AVAudioApplication.shared.recordPermission
        if status == .undetermined {
            return await AVAudioApplication.requestRecordPermission()
        }
        return status == .granted
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
        // #198B: both guards — `isRecording` for the steady state,
        // `isTransitioning` for the await windows below it cannot see.
        guard !isRecording, !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        startGeneration &+= 1
        let generation = startGeneration

        guard await requestRecordPermission() else {
            Self.logger.error("Voice memo: microphone permission denied or unavailable")
            throw RecorderError.microphoneDenied
        }
        // #198B: a discard landed while the permission prompt was up — the
        // sheet is gone; nothing was activated yet, so just back out.
        guard startGeneration == generation else { return }

        let destination = Self.makeRecordingURL()
        do {
            try await activateForRecording()
            didActivateAudioSession = true
            // #198B: a discard landed during the activation hop — release
            // what this start just activated and back out.
            guard startGeneration == generation else {
                await releaseAudioSessionIfOwned()
                return
            }
            let recorder = try AVAudioRecorder(url: destination, settings: Self.settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                Self.logger.error("Voice memo: AVAudioRecorder.record() returned false")
                await releaseAudioSessionIfOwned()
                throw RecorderError.recordingFailed
            }
            self.recorder = recorder
            fileURL = destination
        } catch let error as RecorderError {
            throw error
        } catch {
            Self.logger.error("Voice memo: recording setup failed: \(error.localizedDescription, privacy: .public)")
            await releaseAudioSessionIfOwned()
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
    func stopRecording() async -> (url: URL, duration: TimeInterval)? {
        guard isRecording, let recorder, let fileURL else { return nil }
        let duration = recorder.currentTime
        await finishRecorder()
        Self.logger.verbose("Voice memo recording stopped (\(Int(duration))s)")
        return (fileURL, duration)
    }

    /// Stops (if needed) and deletes the recording file.
    ///
    /// #198B: unguarded on purpose — a dismissal's discard must never be
    /// dropped; it ends any in-flight start via the generation bump instead.
    func discard() async {
        await finishRecorder()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        elapsed = 0
        level = 0
    }

    private func finishRecorder() async {
        // #198B: end any in-flight start's license before tearing down.
        startGeneration &+= 1
        meterTask?.cancel()
        meterTask = nil
        recorder?.stop()
        recorder = nil
        isRecording = false
        level = 0
        await releaseAudioSessionIfOwned()
    }

    /// The #84 release, guarded — see `VoiceMemoPlayer` for the full note.
    @discardableResult
    private func releaseAudioSessionIfOwned() async -> Bool {
        guard Self.shouldReleaseAudioSession(didActivate: didActivateAudioSession) else {
            return false
        }
        didActivateAudioSession = false
        await deactivateAudioSession()
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
