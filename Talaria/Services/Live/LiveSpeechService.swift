@preconcurrency import AVFoundation
import Foundation
import OSLog
@preconcurrency import Speech

/// On-device speech-to-text using Apple's Speech framework.
/// Used for dictation in the chat composer — not for voice mode (which uses OpenAI Realtime).
///
/// This uses the modern iOS 26 Speech analyzer/transcriber stack instead of the
/// older `SFSpeechRecognizer` live-audio callback path. The newer APIs are a much
/// better fit for Swift concurrency and are less fragile around queue ownership.
@MainActor
@Observable
final class LiveSpeechService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.aethyrion.talaria",
        category: "Dictation"
    )
    private static let startupTimeout: Duration = .seconds(4)

    private(set) var isListening = false
    private(set) var transcript = ""
    private(set) var authorizationStatus: SFSpeechRecognizerAuthorizationStatus

    var onAutoStop: ((_ finalTranscript: String) -> Void)?
    var onTranscriptChange: ((_ transcript: String) -> Void)?

    private let controller = DictationController()
    private var streamTask: Task<Void, Never>?

    init() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
        Self.logger.verbose("Initialized speech authorization status: \(String(describing: self.authorizationStatus))")
    }

    var supportsOnDevice: Bool {
        true
    }

    func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let currentStatus = SFSpeechRecognizer.authorizationStatus()
        if currentStatus != .notDetermined {
            authorizationStatus = currentStatus
            Self.logger.verbose("Speech authorization already resolved: \(String(describing: currentStatus))")
            return currentStatus
        }

        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        authorizationStatus = status
        Self.logger.verbose("Speech authorization callback returned: \(String(describing: status))")
        return status
    }

    func startListening() async throws {
        Self.logger.verbose("Dictation start requested")

        let speechAuthorized: Bool
        if authorizationStatus == .authorized {
            speechAuthorized = true
        } else {
            Self.logger.verbose("Requesting speech authorization")
            speechAuthorized = await requestAuthorization() == .authorized
        }
        guard speechAuthorized else {
            Self.logger.error("Speech authorization denied or unavailable")
            throw SpeechError.unavailable
        }
        Self.logger.verbose("Speech authorization granted")

        let microphoneStatus = AVAudioApplication.shared.recordPermission
        if microphoneStatus == .undetermined {
            Self.logger.verbose("Requesting microphone permission")
            guard await AVAudioApplication.requestRecordPermission() else {
                Self.logger.error("Microphone permission denied")
                throw SpeechError.microphoneDenied
            }
        } else if microphoneStatus != .granted {
            Self.logger.error("Microphone permission unavailable")
            throw SpeechError.microphoneDenied
        }
        Self.logger.verbose("Microphone permission granted")

        guard !isListening else { return }

        transcript = ""
        streamTask?.cancel()

        let stream: AsyncStream<DictationController.Event>
        do {
            stream = try await startControllerWithTimeout()
        } catch {
            Self.logger.error("Dictation startup failed: \(error.localizedDescription, privacy: .public)")
            Task {
                await controller.stop()
            }
            throw error
        }

        Self.logger.verbose("Dictation startup completed")
        isListening = true

        streamTask = Task { [weak self] in
            guard let self else { return }
            for await event in stream {
                await MainActor.run {
                    switch event {
                    case .partial(let text):
                        Self.logger.verbose("Dictation partial received")
                        self.transcript = text
                        self.onTranscriptChange?(text)
                    case .finished(let text):
                        Self.logger.verbose("Dictation finished")
                        self.transcript = text
                        self.isListening = false
                        self.onTranscriptChange?(text)
                        if !text.isEmpty {
                            self.onAutoStop?(text)
                        }
                    case .failed:
                        Self.logger.error("Dictation stream failed")
                        self.isListening = false
                    }
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }
        Self.logger.verbose("Dictation stop requested")
        isListening = false
        streamTask?.cancel()
        streamTask = nil

        Task {
            await controller.stop()
        }
    }

    private func startControllerWithTimeout() async throws -> AsyncStream<DictationController.Event> {
        let controller = self.controller

        return try await withThrowingTaskGroup(of: AsyncStream<DictationController.Event>.self) { group in
            group.addTask {
                try await controller.start()
            }

            group.addTask {
                try await Task.sleep(for: Self.startupTimeout)
                throw SpeechError.startupTimedOut
            }

            let stream = try await group.next()!
            group.cancelAll()
            return stream
        }
    }

    enum SpeechError: LocalizedError {
        case unavailable
        case microphoneDenied
        case startupTimedOut
        /// #82 wedge caught at the engine (degenerate input format) — a tap
        /// install would raise an uncatchable NSException. #84 wording.
        case noAudioInput

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Speech recognition is not available on this device."
            case .microphoneDenied:
                "Microphone access is required for dictation."
            case .startupTimedOut:
                "Dictation took too long to start."
            case .noAudioInput:
                TalkMicPreflight.noMicInputMessage
            }
        }
    }
}

/// #360: the transcript-assembly policy, extracted pure so it is testable.
/// Correct under BOTH readings of the SDK contract
/// (`SpeechModuleResult.range` + progressive finalization): a result whose
/// text starts with everything finalized so far is a cumulative snapshot
/// (the #4.15 hedge, one layer down); anything else is the text of the
/// unfinalized range and concatenates as-is — the recognizer owns token
/// spacing (continuation ranges carry their own leading whitespace; a range
/// boundary can split a word), so no separator is ever invented or removed.
struct DictationTranscriptAssembler: Equatable {
    private(set) var finalized = ""
    private(set) var volatileTail = ""

    var transcript: String { finalized + volatileTail }

    mutating func acceptVolatile(_ text: String) {
        if !finalized.isEmpty, text.hasPrefix(finalized) {
            volatileTail = String(text.dropFirst(finalized.count))
        } else {
            volatileTail = text
        }
    }

    mutating func acceptFinal(_ text: String) {
        if !finalized.isEmpty, text.hasPrefix(finalized) {
            finalized = text
        } else {
            finalized += text
        }
        volatileTail = ""
    }
}

private actor DictationController {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "org.aethyrion.talaria",
        category: "DictationController"
    )

    enum Event: Sendable {
        case partial(String)
        case finished(String)
        case failed
    }

    private let audioEngine = AVAudioEngine()

    private var transcriber: DictationTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var audioConverter: AVAudioConverter?
    private var reservedLocale: Locale?
    private var analyzerTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    // #360: armed by a final result, cancelled by any later result — fires
    // `.finished` when the recognizer goes quiet after finalizing, so
    // auto-stop survives whether or not the results stream ends on its own.
    private var finishGraceTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var outputContinuation: AsyncStream<Event>.Continuation?

    func start() async throws -> AsyncStream<Event> {
        stop()
        Self.logger.verbose("Preparing dictation controller")

        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: .current) else {
            Self.logger.error("No supported locale equivalent to current locale")
            throw LiveSpeechService.SpeechError.unavailable
        }

        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        self.transcriber = transcriber
        if try await AssetInventory.reserve(locale: locale) {
            reservedLocale = locale
            Self.logger.verbose("Reserved speech locale: \(locale.identifier)")
        }

        let assetStatus = await AssetInventory.status(forModules: [transcriber])
        Self.logger.verbose("Speech asset status: \(String(describing: assetStatus))")

        let session = AVAudioSession.sharedInstance()
        Self.logger.verbose("Configuring audio session")
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        // #82 wedge backstop: refuse the tap install on a degenerate format
        // (uncatchable NSException otherwise); surface #84 reboot guidance.
        guard TalkMicPreflight.isViableCaptureFormat(
            sampleRate: inputFormat.sampleRate,
            channelCount: inputFormat.channelCount
        ) else {
            Self.logger.error("capture format degenerate (rate=\(inputFormat.sampleRate) ch=\(inputFormat.channelCount)) — #82 wedge shape; refusing tap install")
            throw LiveSpeechService.SpeechError.noAudioInput
        }
        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: inputFormat
        ) ?? inputFormat
        let formatsMatch =
            inputFormat.sampleRate == analyzerFormat.sampleRate &&
            inputFormat.channelCount == analyzerFormat.channelCount &&
            inputFormat.commonFormat == analyzerFormat.commonFormat &&
            inputFormat.isInterleaved == analyzerFormat.isInterleaved
        let converter = formatsMatch ? nil : AVAudioConverter(from: inputFormat, to: analyzerFormat)
        converter?.primeMethod = .none
        audioConverter = converter
        Self.logger.verbose(
            "Using analyzer format sampleRate=\(analyzerFormat.sampleRate) channels=\(analyzerFormat.channelCount)"
        )

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        Self.logger.verbose("Preparing speech analyzer")
        try await analyzer.prepareToAnalyze(in: analyzerFormat) { progress in
            Self.logger.verbose("Speech asset progress totalUnitCount=\(progress.totalUnitCount) completedUnitCount=\(progress.completedUnitCount)")
        }
        self.analyzer = analyzer

        var localInputContinuation: AsyncStream<AnalyzerInput>.Continuation?
        let inputStream = AsyncStream<AnalyzerInput> { continuation in
            localInputContinuation = continuation
            self.inputContinuation = continuation
        }

        let outputStream = AsyncStream<Event> { continuation in
            self.outputContinuation = continuation
        }

        Self.logger.verbose("Installing audio tap")
        // #198: the iOS 27 installer reports failure instead of raising, so
        // the #82 preflight above is no longer the only thing between a bad
        // capture format and a crash. The preflight STAYS — it prevents the
        // failure; this makes whatever it doesn't catch survivable.
        try AudioNodeTap.install(on: inputNode, bufferSize: 1024, format: inputFormat) { buffer, _ in
            if let convertedBuffer = Self.convertBuffer(buffer, using: converter, outputFormat: analyzerFormat) {
                localInputContinuation?.yield(AnalyzerInput(buffer: convertedBuffer))
            }
        }

        Self.logger.verbose("Starting audio engine")
        audioEngine.prepare()
        try audioEngine.start()
        Self.logger.verbose("Audio engine started")

        analyzerTask = Task { [weak self] in
            do {
                Self.logger.verbose("Speech analyzer start(inputSequence:) entered")
                try await analyzer.start(inputSequence: inputStream)
            } catch {
                Self.logger.error("Speech analyzer failed: \(error.localizedDescription, privacy: .public)")
                await self?.emit(.failed)
                await self?.stop()
            }
        }

        resultsTask = Task { [weak self] in
            var assembler = DictationTranscriptAssembler()
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        Self.logger.verbose("Received final dictation result")
                        assembler.acceptFinal(text)
                    } else {
                        Self.logger.verbose("Received partial dictation result")
                        assembler.acceptVolatile(text)
                    }
                    await self?.emit(.partial(assembler.transcript))
                    // #360: a mid-stream `isFinal` only finalizes a range and
                    // must not stop the session (the pre-#360 truncation).
                    // But whether the results stream ends on its own after
                    // the LAST final is unverified on device, and auto-stop
                    // rides `.finished` — so a final arms a short grace that
                    // finishes the utterance if the recognizer goes quiet,
                    // and any later result disarms it.
                    if result.isFinal {
                        await self?.armFinishGrace(transcript: assembler.transcript)
                    } else {
                        await self?.disarmFinishGrace()
                    }
                }
                if !Task.isCancelled {
                    Self.logger.verbose("Dictation results stream ended")
                    await self?.emit(.finished(assembler.transcript))
                }
                await self?.stop()
            } catch {
                // A cancelled results task is the user's own stop, not a
                // failure — stopListening() already owns the teardown.
                if error is CancellationError { return }
                Self.logger.error("Transcriber results failed: \(error.localizedDescription, privacy: .public)")
                await self?.emit(.failed)
                await self?.stop()
            }
        }

        return outputStream
    }

    private static let finishGrace: Duration = .seconds(1)

    private func armFinishGrace(transcript: String) {
        finishGraceTask?.cancel()
        finishGraceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.finishGrace)
            guard !Task.isCancelled else { return }
            await self?.finishAfterGrace(transcript: transcript)
        }
    }

    private func disarmFinishGrace() {
        finishGraceTask?.cancel()
        finishGraceTask = nil
    }

    private func finishAfterGrace(transcript: String) {
        Self.logger.verbose("Dictation finish grace elapsed after a final result")
        emit(.finished(transcript))
        stop()
    }

    func stop() {
        Self.logger.verbose("Stopping dictation controller")
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputContinuation?.finish()
        inputContinuation = nil
        finishGraceTask?.cancel()
        finishGraceTask = nil

        analyzerTask?.cancel()
        resultsTask?.cancel()
        analyzerTask = nil
        resultsTask = nil

        let analyzer = analyzer
        self.analyzer = nil
        self.transcriber = nil
        self.audioConverter = nil
        let reservedLocale = self.reservedLocale
        self.reservedLocale = nil
        if let analyzer {
            Task {
                await analyzer.cancelAndFinishNow()
            }
        }
        if let reservedLocale {
            Task {
                _ = await AssetInventory.release(reservedLocale: reservedLocale)
            }
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        outputContinuation?.finish()
        outputContinuation = nil
    }

    private func emit(_ event: Event) {
        outputContinuation?.yield(event)
    }

    nonisolated private static func convertBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter?,
        outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        final class ConversionState: @unchecked Sendable {
            var didProvideInput = false
        }

        guard let converter else { return inputBuffer }

        let frameRatio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let outputFrameCapacity = max(
            inputBuffer.frameLength,
            AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * frameRatio)) + 32
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            Self.logger.error("Failed to allocate converted audio buffer")
            return nil
        }

        let state = ConversionState()
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if state.didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            } else {
                state.didProvideInput = true
                outStatus.pointee = .haveData
                return inputBuffer
            }
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return outputBuffer.frameLength > 0 ? outputBuffer : nil
        case .error:
            if let conversionError {
                Self.logger.error("Audio conversion failed: \(conversionError.localizedDescription, privacy: .public)")
            } else {
                Self.logger.error("Audio conversion failed with unknown error")
            }
            return nil
        @unknown default:
            Self.logger.error("Audio conversion returned unknown status")
            return nil
        }
    }
}
