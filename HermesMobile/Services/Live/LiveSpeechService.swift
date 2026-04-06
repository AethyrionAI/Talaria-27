import AVFoundation
import Foundation
import Speech

/// On-device speech-to-text using Apple's Speech framework.
/// Used for dictation in the chat composer — not for voice mode (which uses OpenAI Realtime).
@MainActor
@Observable
final class LiveSpeechService {
    private(set) var isListening = false
    private(set) var transcript = ""
    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

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

        // Cancel any previous task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session for recording — must not conflict with WebRTC
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setActive(true)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionRequest = request
        transcript = ""
        isListening = true

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal == true) {
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false

        // Deactivate the audio session so it doesn't conflict with WebRTC
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    enum SpeechError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Speech recognition is not available on this device."
        }
    }
}
