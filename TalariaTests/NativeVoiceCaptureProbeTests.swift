@preconcurrency import AVFoundation
import Foundation
import os
@preconcurrency import Speech
import Testing
@testable import Talaria

/// #428 — **Task 0(b): the simulator premises.** TEMPORARY measurement file.
///
/// This suite asserts almost nothing. It PRINTS what the iOS 27 simulator
/// actually does at three places the #428 plan rests on, so later tasks pin
/// their bars against measurement rather than against a guess:
///
///  1. Does `NativeVoicePipelineService.startSession()` clear its mic/speech
///     preflight in the test host, or does it block (or hang on a TCC prompt
///     `simctl privacy` has no service for)? The answer decides whether the
///     service-level tests may drive the real `startSession()` or need a
///     `// harness-visible` connected-capture door.
///  2. Does the REAL `NativeVoiceCaptureController.start(muted:)` get past the
///     `setCategory` / `setActive(true)` pair, and where does it stop — and,
///     with the analyzer assembly short-circuited, does `AVAudioEngine.start()`
///     actually run on a simulator? This decides 428-B's control-arm assertion.
///  3. Does a hand-posted `AVAudioSession.routeChangeNotification` reach
///     `handleRouteChange` → `restartCapture`, and does the 750 ms
///     `audioSessionConfigurationCooldown` gate it?
///
/// **Failure policy.** A probe that observes the platform must not go red just
/// because the answer is "no" — the answer IS the deliverable. `Issue.record`
/// is used ONLY for harness faults (a wait that never reached the parked
/// point). Everything else prints under the `[428-T0b]` prefix.
///
/// **Every wait is bounded (≤ 5 s).** There is no `simctl privacy` service for
/// speech recognition, so `SFSpeechRecognizer.requestAuthorization` can park
/// forever behind an undismissed system alert; an unbounded wait would hang the
/// suite with no message (the CLAUDE.md "no TCC record HANGS the suite"
/// hazard). A hang here is recorded as a finding, not suffered.
///
/// Deleted by #428 Task 4 together with the `// harness-visible` widenings in
/// `NativeVoicePipelineService.swift`.
@Suite(.serialized)
@MainActor
struct NativeVoiceCaptureProbeTests {

    // MARK: - Harness

    private static let logger = Logger(
        subsystem: "org.aethyrion.talaria", category: "428probe")

    /// Prints AND os_logs, so the finding survives either channel being lost.
    private func say(_ line: String) {
        print("[428-T0b] \(line)")
        Self.logger.notice("[428-T0b] \(line, privacy: .public)")
    }

    /// Settle box for bounded polling — never a `CheckedContinuation`, which
    /// strands silently when the awaited framework call never calls back.
    @MainActor
    private final class ProbeBox {
        var settled = false
        var note = "(never settled)"
    }

    /// The minimal chat backend `startSession()`'s `backendProvider` guard
    /// needs. Same shape as `RunsApprovalTests`' `ScriptedVoiceBackend`.
    @MainActor
    private final class ProbeBackend: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        func connect() async {}
        func disconnect() async {}
        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "", status: .delivered)
        }
        func sendStreaming(message: String, attachments: [PendingAttachment], clientMessageID: UUID) -> AsyncStream<StreamingUpdate> {
            AsyncStream { $0.finish() }
        }
        func loadConversation() async -> Conversation { Conversation(title: "428-probe") }
        func clearConversation() async throws -> Conversation { Conversation(title: "428-probe") }
    }

    private func makeService() -> (NativeVoicePipelineService, ProbeBackend) {
        let backend = ProbeBackend()
        let speech = SpeechOutputService()
        speech.managesAudioSession = false
        let voice = NativeVoicePipelineService(backendProvider: { backend }, speechOutput: speech)
        return (voice, backend)
    }

    private func postRouteChange(_ reason: AVAudioSession.RouteChangeReason) {
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        )
    }

    /// Polls `condition` every 5 ms up to `seconds`. Returns the elapsed time
    /// and whether it ever became true. Bounded by construction.
    @discardableResult
    private func waitUntil(
        _ seconds: Double,
        _ condition: () async -> Bool
    ) async -> (met: Bool, elapsed: Double) {
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            if await condition() { return (true, Date().timeIntervalSince(start)) }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return (await condition(), Date().timeIntervalSince(start))
    }

    private func describeSession() -> String {
        let s = AVAudioSession.sharedInstance()
        return "category=\(s.category.rawValue) mode=\(s.mode.rawValue) "
            + "isInputAvailable=\(s.isInputAvailable) sampleRate=\(s.sampleRate) "
            + "inputChannels=\(s.inputNumberOfChannels) "
            + "inputs=\(s.currentRoute.inputs.map(\.portType.rawValue)) "
            + "outputs=\(s.currentRoute.outputs.map(\.portType.rawValue))"
    }

    // MARK: - Probe 1 — does startSession() clear its preflight on the sim?

    @Test func probe1StartSessionPreflight() async {
        say("=== PROBE 1: startSession() preflight on this host ===")
        say("P1 recordPermission=\(String(describing: AVAudioApplication.shared.recordPermission))")
        say("P1 speechAuthorizationStatus=\(String(describing: SFSpeechRecognizer.authorizationStatus()))")
        say("P1 session BEFORE: \(describeSession())")
        say("P1 TalkMicPreflight.isMicInputAvailable=\(TalkMicPreflight.isMicInputAvailable())")

        let (voice, _) = makeService()
        let box = ProbeBox()
        let start = Date()
        let task = Task { @MainActor in
            await voice.startSession()
            box.settled = true
        }
        let outcome = await waitUntil(5.0) { box.settled }
        let elapsed = Date().timeIntervalSince(start)

        if outcome.met {
            say("P1 startSession() RETURNED after \(String(format: "%.3f", elapsed)) s")
        } else {
            say("P1 🔴 startSession() DID NOT RETURN within 5.000 s — parked "
                + "(the speech-authorization prompt is the prime suspect; there is "
                + "no `simctl privacy` service for speech recognition)")
            task.cancel()
        }
        say("P1 connectionState=\(String(describing: voice.connectionState))")
        say("P1 voiceState=\(String(describing: voice.voiceState))")
        say("P1 canStartSession=\(voice.canStartSession)")
        say("P1 blockedReason=\(voice.blockedReason ?? "nil")")
        say("P1 statusMessage=\(voice.statusMessage ?? "nil")")
        say("P1 speechAuthorizationStatus AFTER=\(String(describing: SFSpeechRecognizer.authorizationStatus()))")
        say("P1 session AFTER: \(describeSession())")

        // Leave the host in a sane state for the next probe.
        if outcome.met {
            await voice.endSession()
        }
        say("=== PROBE 1 END ===")
    }

    // MARK: - Probe 2 — the real controller, and the engine on its own

    @Test func probe2RealControllerAndEngine() async {
        say("=== PROBE 2: real controller start + engine-only shortcut ===")

        // --- Step A: the session configuration the controller performs,
        // replicated in the test host so its result is separable from the
        // controller's later failure.
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            say("P2-A setCategory(.playAndRecord/.voiceChat) OK")
        } catch {
            say("P2-A setCategory THREW \(type(of: error)) \(error)")
        }
        do {
            try session.setActive(true)
            say("P2-A setActive(true) OK")
        } catch {
            say("P2-A setActive(true) THREW \(type(of: error)) \(error)")
        }
        say("P2-A session after config: \(describeSession())")

        // --- Step B: the REAL controller with the REAL assembler.
        let controller = NativeVoiceCaptureController()
        let box = ProbeBox()
        let startB = Date()
        let taskB = Task { @MainActor in
            do {
                _ = try await controller.start(muted: true)
                box.note = "start(muted:) RETURNED a stream (no throw)"
            } catch let error as NativeVoiceCaptureController.CaptureError {
                box.note = "start(muted:) THREW CaptureError.\(error) — \(error.localizedDescription)"
            } catch {
                box.note = "start(muted:) THREW \(type(of: error)) — \(error) / \(error.localizedDescription)"
            }
            box.settled = true
        }
        let outcomeB = await waitUntil(5.0) { box.settled }
        say("P2-B elapsed=\(String(format: "%.3f", Date().timeIntervalSince(startB))) s settled=\(outcomeB.met)")
        say("P2-B outcome: \(box.note)")
        if !outcomeB.met {
            say("P2-B 🔴 the real controller's start(muted:) did not settle within 5 s")
            taskB.cancel()
        }
        say("P2-B controller.isEngineRunning=\(await controller.isEngineRunning)")
        say("P2-B controller.probeStartCount=\(await controller.probeStartCount)")
        say("P2-B SpeechTranscriber.isAvailable=\(SpeechTranscriber.isAvailable)")
        // Bounded, because `supportedLocale` spawns an XPC speech service that
        // can be slow or silent on a simulator.
        let supportBox = ProbeBox()
        let probeController = NativeVoiceCaptureController()
        let taskSupport = Task { @MainActor in
            supportBox.note = "isTranscriptionSupported()=\(await probeController.isTranscriptionSupported())"
            supportBox.settled = true
        }
        let supportSettled = await waitUntil(5.0) { supportBox.settled }
        say("P2-B \(supportSettled.met ? supportBox.note : "isTranscriptionSupported() did NOT settle within 5 s")")
        if !supportSettled.met { taskSupport.cancel() }
        if outcomeB.met { await controller.stop() }

        // --- Step C: the assembler-equivalent shortcut. Task 1's
        // `SpeechAnalysisAssembling` seam does not exist yet, so instead of a
        // fake assembler this drives `startAnalyzer`'s ENGINE steps directly,
        // in the same order and through the same production tap wrapper:
        // voice processing → format read → viability gate → AudioNodeTap
        // .install → prepare → start. Everything the analyzer contributes is
        // simply skipped, which is exactly what a returns-immediately fake
        // assembler would do.
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        // Read the format BEFORE voice processing too, so a degenerate format
        // afterwards can be attributed: "this simulator has no engine-level
        // mic input at all" vs "setVoiceProcessingEnabled(true) zeroed it".
        let preVPOut = inputNode.outputFormat(forBus: 0)
        let preVPIn = inputNode.inputFormat(forBus: 0)
        say("P2-C BEFORE voice processing: outputFormat rate=\(preVPOut.sampleRate) ch=\(preVPOut.channelCount) | "
            + "inputFormat rate=\(preVPIn.sampleRate) ch=\(preVPIn.channelCount)")
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            say("P2-C setVoiceProcessingEnabled(true) OK")
        } catch {
            say("P2-C setVoiceProcessingEnabled THREW \(type(of: error)) \(error)")
        }
        inputNode.removeTap(onBus: 0)
        let format = inputNode.outputFormat(forBus: 0)
        let viable = TalkMicPreflight.isViableCaptureFormat(
            sampleRate: format.sampleRate, channelCount: format.channelCount)
        say("P2-C inputFormat sampleRate=\(format.sampleRate) channels=\(format.channelCount) "
            + "commonFormat=\(format.commonFormat.rawValue) interleaved=\(format.isInterleaved) viable=\(viable)")
        if viable {
            do {
                try AudioNodeTap.install(on: inputNode, bufferSize: 1024, format: format) { _, _ in }
                say("P2-C AudioNodeTap.install OK")
                engine.prepare()
                do {
                    try engine.start()
                    say("P2-C ✅ audioEngine.start() OK — isRunning=\(engine.isRunning)")
                } catch {
                    say("P2-C 🔴 audioEngine.start() THREW \(type(of: error)) — \(error) / \(error.localizedDescription)")
                }
            } catch {
                say("P2-C 🔴 AudioNodeTap.install THREW \(type(of: error)) — \(error)")
            }
        } else {
            say("P2-C 🔴 degenerate capture format — production refuses the tap install here (CaptureError.noAudioInput)")
        }
        engine.stop()
        inputNode.removeTap(onBus: 0)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        say("=== PROBE 2 END ===")
    }

    // MARK: - Probe 3 — the route-change fixture and the 750 ms gate

    @Test func probe3RouteChangeFixture() async {
        say("=== PROBE 3: route-change fixture + configuration cooldown ===")

        // --- Arm A: connected, gate OPEN. Does the posted notification reach
        // handleRouteChange and then restartCapture?
        let (voiceA, _) = makeService()
        voiceA.connectionState = .connected
        voiceA.voiceState = .listening
        voiceA.statusMessage = "Listening"
        // #428 Task 1: `capture` is now `any NativeVoiceCapturing`, so the
        // probe door hands back the production controller as an optional.
        guard let captureA = voiceA.probeCaptureController else {
            Issue.record("harness: voiceA's capture is not the production controller")
            return
        }
        let beforeA = await captureA.probeStartCount
        say("P3-A gate isConfiguringAudioSession=\(voiceA.probeIsConfiguringAudioSession) startCountBefore=\(beforeA)")

        postRouteChange(.newDeviceAvailable)
        let sawA = await waitUntil(5.0) {
            await captureA.probeStartCount > beforeA
        }
        let afterA = await captureA.probeStartCount
        say("P3-A restart observed=\(sawA.met) after \(String(format: "%.3f", sawA.elapsed)) s "
            + "startCount \(beforeA) → \(afterA)")
        say("P3-A connectionState=\(String(describing: voiceA.connectionState)) "
            + "voiceState=\(String(describing: voiceA.voiceState)) "
            + "statusMessage=\(voiceA.statusMessage ?? "nil")")
        if !sawA.met {
            say("P3-A 🔴 the posted route change did NOT produce a capture restart — "
                + "statusMessage says whether handleRouteChange ran at all")
        }

        // --- Arm B: gate CLOSED. The same post must be swallowed, then the
        // same post with the gate reopened must go through. Two arms, because
        // one silent arm proves nothing.
        let (voiceB, _) = makeService()
        voiceB.connectionState = .connected
        voiceB.voiceState = .listening
        voiceB.statusMessage = "Listening"
        voiceB.probeSetConfiguringAudioSession(true)
        guard let captureB = voiceB.probeCaptureController else {
            Issue.record("harness: voiceB's capture is not the production controller")
            return
        }
        let beforeB = await captureB.probeStartCount
        postRouteChange(.newDeviceAvailable)
        let blockedB = await waitUntil(1.0) {
            await captureB.probeStartCount > beforeB
        }
        say("P3-B gate CLOSED: restart observed=\(blockedB.met) (expected false) "
            + "startCount=\(await captureB.probeStartCount) "
            + "statusMessage=\(voiceB.statusMessage ?? "nil")")

        voiceB.probeSetConfiguringAudioSession(false)
        postRouteChange(.newDeviceAvailable)
        let openedB = await waitUntil(5.0) {
            await captureB.probeStartCount > beforeB
        }
        say("P3-B gate REOPENED: restart observed=\(openedB.met) after "
            + "\(String(format: "%.3f", openedB.elapsed)) s "
            + "startCount=\(await captureB.probeStartCount) "
            + "statusMessage=\(voiceB.statusMessage ?? "nil")")
        if blockedB.met || !openedB.met {
            say("P3-B 🔴 the cooldown gate did not discriminate — closed=\(blockedB.met) opened=\(openedB.met)")
        }

        // --- Arm C: the REAL cooldown, armed by the REAL beginCapture().
        // This is the arm that says whether a service-level test must WAIT
        // 750 ms after connect or whether the sim never arms the window at all.
        let (voiceC, _) = makeService()
        let boxC = ProbeBox()
        let startC = Date()
        let taskC = Task { @MainActor in
            do {
                try await voiceC.probeBeginCapture()
                boxC.note = "beginCapture() RETURNED (no throw) — the cooldown Task is armed"
            } catch {
                boxC.note = "beginCapture() THREW \(type(of: error)) — \(error.localizedDescription)"
            }
            boxC.settled = true
        }
        let settledC = await waitUntil(5.0) { boxC.settled }
        say("P3-C \(boxC.note) (settled=\(settledC.met) after \(String(format: "%.3f", Date().timeIntervalSince(startC))) s)")
        if !settledC.met { taskC.cancel() }
        say("P3-C isConfiguringAudioSession immediately after=\(voiceC.probeIsConfiguringAudioSession)")
        if voiceC.probeIsConfiguringAudioSession {
            let cleared = await waitUntil(3.0) { !voiceC.probeIsConfiguringAudioSession }
            say("P3-C cooldown cleared=\(cleared.met) after \(String(format: "%.3f", cleared.elapsed)) s "
                + "(declared audioSessionConfigurationCooldown = 750 ms)")
        } else {
            say("P3-C the cooldown was NEVER armed on this host — beginCapture() cleared "
                + "the flag on its throw path, so no post-connect wait is required here")
        }
        await voiceC.endSession()
        say("=== PROBE 3 END ===")
    }
}
