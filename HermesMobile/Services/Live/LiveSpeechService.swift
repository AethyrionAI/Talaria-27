@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

/// On-device speech-to-text using Apple's Speech framework.
/// Used for dictation in the chat composer — not for voice mode (which uses OpenAI Realtime).
///
/// Audio engine operations run on a dedicated background queue to avoid blocking
/// the main thread. Only `@Observable` state updates happen on `@MainActor`.
@MainActor
@Observable
final class LiveSpeechService {
    private(set) var isListening = false
    private(set) var transcript = ""
    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    var onAutoStop: ((_ finalTranscript: String) -> Void)?
    var onTranscriptChange: ((_ transcript: String) -> Void)?

    /// Dedicated queue for all AVAudioEngine operations.
    /// Core Audio hardware calls block — they must never run on the main thread.
    private nonisolated let audioQueue = DispatchQueue(label: "hermes.speech.audio", qos: .userInitiated)

    private nonisolated(unsafe) let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private nonisolated(unsafe) let audioEngine = AVAudioEngine()
    private var activeSessionID = UUID()

    var supportsOnDevice: Bool {
        speechRecognizer?.supportsOnDeviceRecognition ?? false
    }

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.authorizationStatus = status
                    continuation.resume(returning: status)
                }
            }
        }
    }

    func startListening() async throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechError.unavailable
        }
        guard !isListening else { return }

        let microphoneStatus = AVAudioApplication.shared.recordPermission
        if microphoneStatus == .undetermined {
            guard await AVAudioApplication.requestRecordPermission() else {
                throw SpeechError.microphoneDenied
            }
        } else if microphoneStatus != .granted {
            throw SpeechError.microphoneDenied
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        activeSessionID = UUID()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        transcript = ""
        let sessionID = activeSessionID
        let engine = audioEngine

        // All audio hardware work happens off the main thread.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            audioQueue.async {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
                    try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                    let inputNode = engine.inputNode
                    let recordingFormat = inputNode.outputFormat(forBus: 0)
                    inputNode.removeTap(onBus: 0)
                    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                        request.append(buffer)
                    }

                    engine.prepare()
                    try engine.start()
                    continuation.resume()
                } catch {
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    continuation.resume(throwing: error)
                }
            }
        }

        recognitionRequest = request
        isListening = true

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            let latestTranscript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let shouldFinish = error != nil || isFinal

            if shouldFinish {
                // Stop audio hardware on the audio queue, not the callback thread
                let engine = self?.audioEngine
                DispatchQueue(label: "hermes.speech.cleanup", qos: .userInitiated).async {
                    engine?.inputNode.removeTap(onBus: 0)
                    engine?.stop()
                    request.endAudio()
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            }

            Task { @MainActor [weak self] in
                guard let self, self.activeSessionID == sessionID else { return }

                if let latestTranscript {
                    self.transcript = latestTranscript
                    self.onTranscriptChange?(self.transcript)
                }

                if shouldFinish {
                    let finalTranscript = self.transcript
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.isListening = false
                    if !finalTranscript.isEmpty {
                        self.onAutoStop?(finalTranscript)
                    }
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }
        activeSessionID = UUID()
        isListening = false
        recognitionRequest = nil
        recognitionTask = nil

        // Stop audio hardware off the main thread
        let engine = audioEngine
        audioQueue.async {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    enum SpeechError: LocalizedError {
        case unavailable
        case microphoneDenied

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Speech recognition is not available on this device."
            case .microphoneDenied:
                "Microphone access is required for dictation."
            }
        }
    }
}
