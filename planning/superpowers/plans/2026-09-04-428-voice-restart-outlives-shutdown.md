# 428 — The Native Voice Restart Cannot Outlive Session Shutdown Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After the UI says a native voice session has ended, the microphone cannot go HOT again. Today a route/interruption restart (`restartTask`) is created, awaited and nilled but never cancelled or joined by teardown, and the capture actor's startup suspends at four framework awaits with no check before it installs the tap and starts the engine — so a Bluetooth/CarPlay route change followed by End (or #415's cover park, which ends through the same teardown) can leave an abandoned startup that reinstalls the tap on a session the user believes is over. This plan makes shutdown INVALIDATE startup (a capture generation the controller checks after every suspension and immediately before install/start), makes teardown cancel AND join the restart, and makes the controller testable with a controllably suspended startup.

**Architecture:** Two layers, each with its own bar. (1) **Controller:** `NativeVoiceCaptureController` gains a monotonic `captureGeneration` that `stop()` bumps; `start()` captures a ticket after its own leading `stop()` and re-checks it after every `await` and immediately before `AudioNodeTap.install` / `audioEngine.start()`; a stale ticket throws `CaptureError.superseded` and emits a `.notice` line the device pass can read. The framework awaits (locale probe, asset reservation, format negotiation, `prepareToAnalyze` with its no-VAD retry) move behind ONE injectable `SpeechAnalysisAssembling` seam so a test can park the startup at exactly the point the defect lives. (2) **Service:** `NativeVoicePipelineService.teardownSessionResources()` cancels `restartTask` first and joins it (bounded — decision 1) before the rest of the teardown; the restart task re-checks `isEndingSession` after its `capture.stop()` and after `beginCapture()` returns; a `.superseded` restart never repaints an ended session as `.failed`. The controller becomes injectable behind `NativeVoiceCapturing` so the service-level ordering is a unit test, driven through the REAL route-change notification path.

**Tech Stack:** Swift 6.4 / AVFoundation (`AVAudioEngine`, `AVAudioSession`) / Speech (`SpeechAnalyzer`, `SpeechTranscriber`, `DictationTranscriber`, `AssetInventory`) / Swift Testing / `scripts/mac/lane-gate.sh` / device: same-day `log collect` scored on the `#302-A` HOT/COLD markers.

**Why this is the shape (read before touching anything):** the archive's #128 block records four restart-vs-start defences and the caution that *"a guard naming the right failure is not proof the failure is covered."* All four defences serialize restarts against EACH OTHER; none of them relates a restart to SHUTDOWN. `#302`/`#415` fixed the start-vs-cover ordering one level up, in `TalkStore` (`sessionGeneration` + `beginCoverWatch`, `TalkStore.swift:234-266`) — and #415's park path ends via `discardAbandonedStart()` → `voiceService.endSession()` (`TalkStore.swift:359-361`), which is the same teardown that ignores `restartTask`. The comment at the install site already states the premise (*"actor serialization does not survive awaits"*, `NativeVoicePipelineService.swift:1150-1152`) and enforces it only against a double INSTALL (remove adjacent to install), never against a stop. The generation ticket is the house pattern (`TalkStore.sessionGeneration`, `ChatStore.finalStatusReadGeneration` for #322-D — *"a cancellation request alone is insufficient — the task may already be past its cancellation check"*), applied inside the actor where the awaits actually are.

**Evidence level, honestly:** the audit calls A3 *"a timing risk established by source inspection, not a newly observed recording incident."* Task 0 measures whether the ordering reproduces on hardware BEFORE the bars are pinned; if it never fires in the measured trials, the structural bars (428-A/B/C) still carry the fix and 428-D becomes a no-regression bar with the ABANDONED line as positive evidence whenever the ordering does fire.

## Global Constraints

- **STOP FIRST, then everything else** — #415's own bar wording. Teardown's new first act is `restartTask?.cancel()` + join; `capture.stop()` (which bumps the generation) stays in teardown and is what makes any straggler start `.superseded`.
- **Never widen the wait the user feels.** The join is BOUNDED (decision 1, default 3 s): a wedged `prepareToAnalyze` (#82's wedge shape) must not turn End into a hang. Past the bound, teardown proceeds and logs it; the generation ticket is what makes the straggler harmless.
- **The instruments stay `.notice`, `.public`, un-gated** (#302-A's rule): the new `capture start ABANDONED` line joins `capture chain HOT`/`COLD` at the same level, pinned by a pure formatter test like `VoiceInstrumentLogLineTests`.
- **No new mechanism where a house one exists:** the ticket is `TalkStore.sessionGeneration`'s shape; the fake-with-a-parked-start is `ParkedStartVoiceService`'s shape (`TalkStoreBackgroundRevokeTests.swift:40-70` — polling, bounded, never a stranded `CheckedContinuation`).
- **`private actor` → `// harness-visible (#428)`:** the controller and its event enum become internal so the tests can reach them; the tag means "private in spirit" (CLAUDE.md #216).
- **Both engines are NOT in scope:** `LiveVoiceSessionService` (realtime) has no `restartTask`; only the native pipeline is touched. #415-D's card re-runs on the fix build because its path inherits this teardown.
- **Measurement discipline (#398-A):** every device number carries build, `osVersion`, thermal; device rows are scored from the ARCHIVE (HOT/COLD/ABANDONED lines), never from what the UI showed.
- **Gate + merge protocol:** worktree isolation; RED-first with the mutation named per bar; `xcodegen generate` after adding files; `TALARIA_SIM_NAME=CC-lane-N scripts/mac/lane-gate.sh` from the fixed pool, ≤ 3 booted, kill only the PID you recorded; positive `GATE: PASS`; merge on green (Owen's standing grant); RESULT block in entry 428; device numbers carry build · `osVersion` · thermal.
- **Plan-authored code is unreviewed code.** The sketches below are INTERFACES. Task 0's sim probes decide whether the controller-level control arm can assert an engine start on the simulator at all; the lane's reviewer checks the verbatim move of the assembler code.

## Decisions for Owen (one AskUserQuestion round — recommended arm first)

> **✅ BALLOT RULED 2026-09-04 (Owen, AskUserQuestion, the same night the plan was written):** 1 = **3 s bounded join** · 2 = **silent** (one `.notice` line) · 3 = **Task 0 on hardware FIRST** (the five-trial card goes on the Device Runbook §04 for the next device evening) · 4 = **injectable assembler behind a protocol**. Every recommended arm below is now a ruling; the lane builds them without re-asking.

1. **Teardown joins the restart with a 3 s bound (recommended):** `endSession()` waits for an in-flight restart to settle, up to 3 s, then proceeds and logs `restart still in flight after 3 s — proceeding; the capture generation covers the straggler`. Alternative: unbounded join (End waits as long as the restart takes — a wedged analyzer prep would hang End). Alternative: cancel only, no join (relies on the ticket alone; the audit asked for cancel AND join).
2. **A restart superseded by End is SILENT (recommended):** no `.failed` repaint, no `"Audio capture could not resume."`, the session reads `.idle` as End left it; one `.notice` line records that the abandoned start was refused. Alternative: surface a one-line status ("Ended during an audio route change") — rejected by default; it describes an internal ordering the user never asked about.
3. **Task 0 on hardware BEFORE the lane (recommended):** ~10 minutes of Owen's evening — five AirPods-connect-then-End trials on the CURRENT build with the existing HOT/COLD instrument, so the lane knows whether it is fixing a measured ordering or a source-inferred one. Alternative: skip and pin 428-D as no-regression only.
4. **Controller seam = an injectable assembler behind a protocol (recommended):** the four framework awaits move verbatim behind `SpeechAnalysisAssembling`; the test's fake parks there. Alternative: a `#if DEBUG` suspension hook inside the actor (test code in production; rejected by default).

## Session contract

1. Read `OPEN_ITEMS.md` entry 428 (the audit's A3 evidence block), entry 415's fix bars and RESULT (`:10761-10900`, the 415-D card at `:10849`), entry 302's supersession, and `OPEN_ITEMS-ARCHIVE.md` #128 (`:3300-3318`, the defence table). Pre-register bars 428-A..GATE in entry 428, in the shape below, BEFORE any code.
2. Task 0 first: (a) the hardware measurement is Owen's evening (decision 3); (b) the sim premise probes are the lane's own first hour. Both results are filed in the entry before Task 1's bars are pinned as written.
3. One worktree lane (Opus), Tasks 1–4, RED-first, mutations named per bar, gate, merge on green, RESULT block. Fable only for a falsified bar.
4. Device evening: 428-D (three cards, ~25 min, Debug build, same-day collect). Claude scores from the archive.

## File structure

**Create:**
- `Talaria/Services/Live/NativeVoiceCapturing.swift` — `protocol NativeVoiceCapturing: Actor`, `enum NativeVoiceCaptureEvent` (lifted from the actor's nested `Event`), `protocol SpeechAnalysisAssembling`, `struct SpeechAnalysisAssembly`, `enum TranscriberChoice`, and `struct SpeechTranscriberAssembler: SpeechAnalysisAssembling` (the four awaits, moved VERBATIM from `start(muted:)` `:1013-1030` and `startAnalyzer` `:1085-1121`).
- `TalariaTests/NativeVoiceCaptureGenerationTests.swift` — bar 428-B (controller level, fake assembler).
- `TalariaTests/NativeVoiceRestartTeardownTests.swift` — bars 428-A and 428-C (service level, fake capture, real route-change notification).
- `TalariaTests/NativeVoiceCaptureProbeTests.swift` — Task 0's sim probes (TEMPORARY; deleted at the end of the lane, results filed).

**Modify:**
- `Talaria/Services/Live/NativeVoicePipelineService.swift`
  - `:84` `private let capture = NativeVoiceCaptureController()` → `private let capture: any NativeVoiceCapturing`, injected; `:126` init gains `capture:`; a second init keeps the two existing call sites (`AppContainer`, `RunsApprovalTests.swift:931`) compiling unchanged.
  - `:92-98` `restartTask` gains a sibling `private var restartInFlight = false` (set in the task body, cleared in its `defer`) — the join waits on the flag, never on `Task.value` (memory: `task-value-not-cancellable`).
  - `:301-322` `beginCapture()` — after `capture.start` returns, `guard !isEndingSession else { await capture.stop(); throw CancellationError() }` (belt).
  - `:335-384` `restartCapture()` — inside the task: after `await self.capture.stop()`, `guard !self.isEndingSession, !Task.isCancelled else { return }`; `catch NativeVoiceCaptureController.CaptureError.superseded { /* ended underneath — nothing to paint (decision 2) */ }`; the generic catch gains `guard !self.isEndingSession else { return }` before painting `.failed`.
  - `:386-401` `teardownSessionResources()` — FIRST: `restartTask?.cancel()` then `await joinRestart(within: .seconds(3))` (decision 1); then the existing cancels; `await capture.stop()` stays (it bumps the generation).
  - `:916-1030` the actor: `private actor` → `actor` + `// harness-visible (#428)`; `Event` → the lifted `NativeVoiceCaptureEvent`; `private var captureGeneration = 0` bumped in `stop()`; `start(muted:)` captures `let ticket = captureGeneration` right after its leading `stop()`, awaits `assembler.assemble(inputFormat:)`, then `try checkTicket(ticket, at: "assembled")` before the remove/install/start stretch; `CaptureError.superseded(point: String)`; `init(assembler: any SpeechAnalysisAssembling = SpeechTranscriberAssembler())`.
  - `:1163-1176` the install/start stretch is unchanged EXCEPT the ticket check immediately above `inputNode.removeTap(onBus: 0)` — the #128 adjacency invariant (remove-then-install in one synchronous stretch) is preserved by construction because the check sits BEFORE the remove.
- `TalariaTests/VoiceInstrumentLogLineTests.swift` — the `abandonedStartLogDetail(point:)` pin.

**Interfaces (the names every task uses):**

```swift
enum NativeVoiceCaptureEvent: Sendable { case volatile(String), finalized(String), failed(String) }

protocol NativeVoiceCapturing: Actor {
    func isTranscriptionSupported() async -> Bool
    func setMuted(_ muted: Bool)
    func start(muted: Bool) async throws -> AsyncStream<NativeVoiceCaptureEvent>
    func stop()
}

enum TranscriberChoice: Sendable { case speech(SpeechTranscriber), dictation(DictationTranscriber) }

struct SpeechAnalysisAssembly: @unchecked Sendable {
    let analyzer: SpeechAnalyzer
    let analyzerFormat: AVAudioFormat
    let reservedLocale: Locale?
    let transcriber: TranscriberChoice
}

/// Everything between audio-session activation and the tap install — the
/// locale probe, asset reservation, format negotiation, and prepareToAnalyze
/// with the no-VAD retry. EVERY suspension point the startup has lives here.
protocol SpeechAnalysisAssembling: Sendable {
    func assemble(inputFormat: AVAudioFormat) async throws -> SpeechAnalysisAssembly
}

extension NativeVoiceCaptureController {
    enum CaptureError: LocalizedError {
        case transcriptionUnavailable
        case noAudioInput
        /// #428: the capture generation moved (a stop ran) while startup was
        /// suspended. The start is refused; nothing was installed.
        case superseded(point: String)
    }
    /// Pure, pinned: the `.notice` line the device pass greps for.
    nonisolated static func abandonedStartLogDetail(point: String) -> String {
        "capture start ABANDONED — capture generation moved during startup at \(point); nothing installed (#428)"
    }
}
```

## Bars (paste into entry 428 as a dated block BEFORE Task 0)

- **428-A — teardown cancels AND joins the restart (service, unit, fake capture).** With a fake `NativeVoiceCapturing` whose SECOND `start` parks: connect, post `AVAudioSession.routeChangeNotification` (`newDeviceAvailable`) so the REAL `handleRouteChange` → `restartCapture` path runs, wait until the fake is inside its parked start, call `endSession()` — it must not return until the parked start has been released and settled (or the 3 s bound elapsed — the test releases at 200 ms so the bound is never the reason); the fake's call log ends `[…, "start", "stop"]` (a stop AFTER the abandoned start returned); `connectionState == .idle`, `voiceState == .idle`. Mutation: delete the `joinRestart` call → `endSession` returns with the fake still parked → RED. Negative control in the same file: no `endSession` → the restart completes and the service reads `.listening`.
- **428-B — a start abandoned by an intervening stop never installs (controller, unit, fake assembler).** With a fake `SpeechAnalysisAssembling` that parks in `assemble`: `Task { try await controller.start(muted: false) }`, wait until parked, `await controller.stop()`, release → `start` throws `.superseded(point: "assembled")`, `audioEngine.isRunning == false` afterwards, and the ABANDONED formatter is byte-pinned. Control arm (Task 0 decides its assertion): the same fixture WITHOUT the stop reaches the install stretch — asserted as "did not throw `.superseded`" plus whatever the sim measurably does at `audioEngine.start()` (Task 0 (b)). Mutation: remove the `checkTicket` before the install stretch → the superseded arm reds.
- **428-C — an ended session is never repainted by a superseded restart (service, unit).** After 428-A's sequence: `blockedReason == nil`, `statusMessage != "Audio capture could not resume."`, `connectionState == .idle` — the `.failed` paint in `restartCapture`'s catch did not fire on a session that was ending. Mutation: remove the `guard !self.isEndingSession` in the catch → RED.
- **428-D — device (Owen's hands, Debug build, same-day collect), three cards.** D1 route churn: native engine, connect AirPods (or CarPlay) mid-session, then End within ~1 s, ×5. D2 interruption-resume: native engine, trigger a system interruption (a timer alarm or a phone call), decline/resume, End within ~1 s of the resumption line, ×3. D3: the 415-D card exactly as written (`OPEN_ITEMS.md:10849`) on the fix build. **Scoring, per session, from the archive:** after the session's `AudioSessionOffMain: setActive(false) off-main (#198B) reason=native-pipeline-stop` line, NO `capture chain HOT` line for the rest of the archive; every `capture chain HOT` has a matching `capture chain COLD` within the session; a `capture start ABANDONED` line, when present, sits between the End and the next session's start. **Prediction written first:** on the FIX build, 0 HOT-after-stop in 8/8; ABANDONED appears in ≥ 1 of the D1 trials IF Task 0 (a) reproduced the ordering, else D1/D2 are no-regression rows and say so. Each row carries build · `osVersion` · thermal.
- **428-GATE** — `TALARIA_SIM_NAME=CC-lane-N scripts/mac/lane-gate.sh`, positive `GATE: PASS`, Swift Testing count moved by exactly the tests this lane adds.

## Task 0: Measure the premises (no production code)

### 0(a) — hardware, Owen's evening, the CURRENT build (decision 3)

- [ ] **Card (Device Runbook §04):** native engine, phone unlocked, AirPods paired. Start a voice session; when `Listening`, put the AirPods in (route change); the moment the status reads `Audio route changed.` / `Listening`, tap End. ×5. Then `log collect` the same evening (or sysdiagnose + Taildrop — memory `uncorded-log-collect-sysdiagnose-taildrop`).
- [ ] **Read:** for each trial, the sequence of `capture chain HOT` / `capture chain COLD` / `native-pipeline-stop` lines with timestamps. The question is one bit per trial: **is there a HOT after the stop?** Also record the gap between the route-change line and the End line — it says how wide the window is in practice.
- [ ] **File** the five rows in entry 428 as `428-T0a`. Either outcome is a finding: reproduced ⇒ 428-D1's prediction is "ABANDONED appears ≥ 1/5 on the fix build"; not reproduced in 5 ⇒ 428-D1 is a no-regression row and the entry says the ordering is source-established and structurally closed.

### 0(b) — simulator premises, the lane's first hour (`NativeVoiceCaptureProbeTests.swift`, temporary)

- [ ] **Probe 1 — does `startSession()` clear its preflight on `CC-lane-N`?** Construct `NativeVoicePipelineService(backendProvider: { fakeBackend }, speechOutput: speech)` exactly as `RunsApprovalTests.swift:931` does, call `startSession()` with a 5 s bounded wait, print `connectionState`/`blockedReason`. If the mic/speech TCC prompt blocks (the CLAUDE.md "no TCC record HANGS the suite" hazard — `simctl privacy grant microphone` + `speech-recognition` on the lane's UDID first, and note whether that suffices), the service-level tests use a `// harness-visible` `beginConnectedCaptureForHarness()` that runs `beginCapture()` and sets `connectionState = .connected` without the preflight — `#if DEBUG`, with a Release grep pin.
- [ ] **Probe 2 — does the real controller pass `setCategory`/`setActive(true)` in the test host, and does `AVAudioEngine` start with an input tap on the sim?** Call the REAL controller's `start(muted:)` with the REAL assembler and print the thrown error (expected on a sim without speech assets: `transcriptionUnavailable`, BEFORE any install). Then, with a fake assembler that returns immediately (a `SpeechTranscriber(locale: .current, preset: .progressiveTranscription)` inside a `SpeechAnalyzer(modules:)`, never prepared), print whether `start` reaches `audioEngine.start()` and what happens (`isRunning`, or the thrown engine error). **This decides 428-B's control-arm assertion** — "engine running" if the sim can, "an engine error rather than `.superseded`" if it cannot.
- [ ] **Probe 3 — the route-change fixture.** After connect, post `NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil, userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])` and confirm the fake capture saw a second `start`. **Known gate:** `handleRouteChange` ignores route changes while `isConfiguringAudioSession` is true, and `beginCapture` holds that flag for `audioSessionConfigurationCooldown = 750 ms` (`:120-124`, `:317-321`) — the test either waits > 750 ms after connect or the cooldown becomes a `// harness-visible` instance knob. Record which.
- [ ] **File** the three probe outputs in entry 428 as `428-T0b`; pin 428-B's control assertion accordingly; delete the probe file before the PR (its results live in the entry, not the tree).

## Task 1: The seams — `NativeVoiceCapturing` + `SpeechAnalysisAssembling` (no behaviour change; the refactor that makes 428-B possible)

**Files:** create `Talaria/Services/Live/NativeVoiceCapturing.swift`; modify `NativeVoicePipelineService.swift` (`:84`, `:126`, `:916`, `:985-1030`, `:1085-1121`).

- [ ] **Step 1 — RED (compile):** write `NativeVoiceCaptureGenerationTests.swift` with a `FakeAssembler: SpeechAnalysisAssembling` (bounded polling gate, `ParkedStartVoiceService`'s idiom) and ONE test that constructs `NativeVoiceCaptureController(assembler: fake)` — it does not compile.
- [ ] **Step 2 — move, do not rewrite:** `SpeechTranscriberAssembler.assemble(inputFormat:)` is the existing code from `start(muted:)` (`if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current)` … `reserveLocaleIfPossible` … the `DictationTranscriber` fallback, `:1013-1030`) followed by the existing analyzer assembly (`SpeechDetector` modules, `bestAvailableAudioFormat`, `prepareToAnalyze`, the no-VAD retry, `:1097-1121`), returning `SpeechAnalysisAssembly`. `reserveLocaleIfPossible` moves with it (it is the reservation's only caller). The actor keeps: session config, the #302-A activation line, `inputNode.setVoiceProcessingEnabled`, the degenerate-format guard, the converter, the tap install, engine start, the HOT line, `analyzerTask`/`resultsTask`, and both consume loops (they switch on `assembly.transcriber`).
- [ ] **Step 3 — the service seam:** `init(backendProvider:speechOutput:capture:)` + `convenience init(backendProvider:speechOutput:)` = `self.init(…, capture: NativeVoiceCaptureController())`. `RunsApprovalTests.swift:931` and `AppContainer`'s call site compile unchanged (grep `NativeVoicePipelineService(` — two sites).
- [ ] **Step 4 — GREEN on the whole `NativeVoicePipelineTests` + `RunsApprovalTests` suites** (no behaviour changed; the counts must not move). `xcodegen generate`. **Commit:** `428-seam: NativeVoiceCapturing + SpeechAnalysisAssembling — the four startup awaits behind one injectable seam (pure move)`.

## Task 2: The capture generation (bar 428-B)

**Files:** modify `NativeVoicePipelineService.swift` (the actor); create/extend `TalariaTests/NativeVoiceCaptureGenerationTests.swift`; extend `VoiceInstrumentLogLineTests.swift`.

- [ ] **Step 1 — RED tests:**

```swift
@Suite("428-B capture generation")
struct NativeVoiceCaptureGenerationTests {
    /// Parks inside `assemble` until released. Polling, bounded — never a
    /// stranded CheckedContinuation (TalkStoreBackgroundRevokeTests' rule).
    final class ParkedAssembler: SpeechAnalysisAssembling, @unchecked Sendable {
        private let lock = NSLock()
        private var entered = false, released = false
        var isParked: Bool { lock.withLock { entered && !released } }
        func release() { lock.withLock { released = true } }
        func assemble(inputFormat: AVAudioFormat) async throws -> SpeechAnalysisAssembly {
            lock.withLock { entered = true }
            for _ in 0..<400 where !(lock.withLock { released }) { try? await Task.sleep(for: .milliseconds(10)) }
            let transcriber = SpeechTranscriber(locale: .current, preset: .progressiveTranscription)
            return SpeechAnalysisAssembly(analyzer: SpeechAnalyzer(modules: [transcriber]),
                                          analyzerFormat: inputFormat, reservedLocale: nil,
                                          transcriber: .speech(transcriber))
        }
    }

    @Test func aStopDuringAssemblySupersedesTheStartAndInstallsNothing() async throws {
        let assembler = ParkedAssembler()
        let controller = NativeVoiceCaptureController(assembler: assembler)
        let start = Task { try await controller.start(muted: false) }
        for _ in 0..<200 where !assembler.isParked { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(assembler.isParked, "fixture never reached the suspension point — the assertion below would be vacuous")
        await controller.stop()                       // the interleaved teardown
        assembler.release()
        do {
            _ = try await start.value
            Issue.record("a start whose generation moved must not return a stream")
        } catch NativeVoiceCaptureController.CaptureError.superseded(let point) {
            #expect(point == "assembled")
        }
        #expect(await controller.isEngineRunning == false)   // `// harness-visible` read of audioEngine.isRunning
    }

    @Test func theAbandonedStartLineIsPinned() {
        #expect(NativeVoiceCaptureController.abandonedStartLogDetail(point: "assembled")
                == "capture start ABANDONED — capture generation moved during startup at assembled; nothing installed (#428)")
    }
    // Control arm: same fixture, no stop — assertion per Task 0 probe 2.
}
```

- [ ] **Step 2 — RED** (no `captureGeneration`, no `.superseded`, no `isEngineRunning`). Run: `xcodebuild test … -only-testing:TalariaTests/NativeVoiceCaptureGenerationTests` (Swift Testing: a single-test filter needs the trailing `()`; the suite filter does not).
- [ ] **Step 3 — implement:** `private var captureGeneration = 0`; `stop()` does `captureGeneration &+= 1` as its FIRST line; `start(muted:)`: `stop()` (existing) → `let ticket = captureGeneration` → session config (unchanged, no await between) → `let assembly = try await assembler.assemble(inputFormat: inputNode.outputFormat(forBus: 0))` → `try checkTicket(ticket, at: "assembled")` → the existing synchronous stretch (`removeTap` → `AudioNodeTap.install` → `prepare` → `start` → HOT line). `checkTicket` throws `.superseded(point:)` and logs `Self.logger.notice("\(Self.abandonedStartLogDetail(point: point), privacy: .public)")`. If the lane finds any OTHER `await` remaining between the ticket and the install (there must be none after Task 1 — `setVoiceProcessingEnabled` and the format read are synchronous), it gets its own `checkTicket` with its own point name.
- [ ] **Step 4 — GREEN + mutation:** delete the `checkTicket` line → the superseded test reds (the start returns a stream, or the control-arm behaviour appears). Restore. **Commit:** `428-B: capture generation — a stop during startup supersedes the start; nothing installs (RED-first)`.

## Task 3: Teardown cancels AND joins; the restart respects the ending session (bars 428-A, 428-C)

**Files:** modify `NativeVoicePipelineService.swift` (`:92-98`, `:301-322`, `:335-401`); create `TalariaTests/NativeVoiceRestartTeardownTests.swift`.

- [ ] **Step 1 — RED tests:**

```swift
@Suite("428-A/C restart vs teardown")
@MainActor
struct NativeVoiceRestartTeardownTests {
    /// A capture whose Nth `start` parks. Records every call in order.
    actor FakeCapture: NativeVoiceCapturing {
        private(set) var calls: [String] = []
        private var parkOnStart: Int
        private var released = false
        init(parkOnStart: Int) { self.parkOnStart = parkOnStart }
        var isParked: Bool { calls.filter { $0 == "start" }.count == parkOnStart && !released }
        func release() { released = true }
        func isTranscriptionSupported() async -> Bool { true }
        func setMuted(_ muted: Bool) {}
        func start(muted: Bool) async throws -> AsyncStream<NativeVoiceCaptureEvent> {
            calls.append("start")
            if calls.filter({ $0 == "start" }).count == parkOnStart {
                for _ in 0..<400 where !released { try? await Task.sleep(for: .milliseconds(10)) }
            }
            calls.append("start-returned")
            return AsyncStream { _ in }
        }
        func stop() { calls.append("stop") }
    }

    private func connectedService(_ capture: FakeCapture) async -> NativeVoicePipelineService {
        let speech = SpeechOutputService(); speech.managesAudioSession = false
        let service = NativeVoicePipelineService(backendProvider: { /* a stub HermesClientProtocol */ }, speechOutput: speech, capture: capture)
        // Task 0 probe 1 decides: `await service.startSession()` or the harness door.
        return service
    }

    private func postRouteChange() {
        NotificationCenter.default.post(name: AVAudioSession.routeChangeNotification, object: nil,
            userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue])
    }

    @Test func endSessionJoinsAParkedRestartAndTheLastWordIsStop() async throws {   // 428-A
        let capture = FakeCapture(parkOnStart: 2)
        let service = await connectedService(capture)
        try? await Task.sleep(for: .milliseconds(800))       // past the 750 ms configuration cooldown (Task 0 probe 3)
        postRouteChange()
        for _ in 0..<200 where !(await capture.isParked) { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(await capture.isParked, "the restart never reached the parked start — nothing below is evidence")
        let ended = Task { await service.endSession() }
        try? await Task.sleep(for: .milliseconds(200))
        await capture.release()
        await ended.value
        let calls = await capture.calls
        #expect(calls.suffix(2) == ["start-returned", "stop"], "teardown must run its stop AFTER the abandoned start returns: \(calls)")
        #expect(service.connectionState == .idle)
        #expect(service.voiceState == .idle)
    }

    @Test func aSupersededRestartNeverRepaintsAnEndedSession() async throws {     // 428-C
        // same drive as above; the fake's parked start THROWS `.superseded` on release
        // (a second fake flag), then:
        // #expect(service.blockedReason == nil); #expect(service.statusMessage != "Audio capture could not resume.")
    }

    @Test func withoutAnEndTheRestartCompletesAndListens() async throws {        // negative control
        // route change → parked → release (no endSession) → `.listening`, calls end with "start-returned"
    }
}
```

- [ ] **Step 2 — RED:** today `endSession` returns while the fake is parked (no join), and the released start is followed by nothing (`calls.suffix(1) == ["start-returned"]`).
- [ ] **Step 3 — implement:** `restartInFlight` set/cleared around the task body (`defer`); `joinRestart(within:)` = cancel, then poll `restartInFlight` every 25 ms until false or the bound; teardown calls it FIRST; the post-`capture.stop()` and post-`beginCapture()` guards; the `.superseded` catch; the `isEndingSession` guard before the `.failed` paint. The bound elapsing logs `Self.logger.notice("restart still in flight after \(bound) — proceeding; the capture generation covers the straggler (#428)")`.
- [ ] **Step 4 — GREEN + mutations:** (A) delete the `joinRestart` call → `endSessionJoinsAParkedRestart…` reds (`endSession` returns first; suffix is wrong). (C) delete the `guard !self.isEndingSession` in the catch → `aSupersededRestart…` reds. Restore both. **Commit:** `428-A/C: teardown cancels and joins the restart (3 s bound); a superseded restart is silent (RED-first)`.

## Task 4: Gate, PR, RESULT block, runbook cards

- [ ] `xcodegen generate`; delete `NativeVoiceCaptureProbeTests.swift` (results are in the entry); `TALARIA_SIM_NAME=CC-lane-N scripts/mac/lane-gate.sh` (background, poll by the PID you recorded); positive `GATE: PASS`; count moved by exactly the tests added (3 files' worth).
- [ ] PR; merge on green; RESULT block in entry 428: bars A/B/C met with RED + mutation outputs; Task 0 rows; the join bound and Owen's decisions as ruled.
- [ ] `scripts/mac/ota-stage.sh main Debug`; three §04 runbook cards (D1/D2/D3 as written in 428-D) with the scoring recipe (the three grep strings: `capture chain HOT`, `capture chain COLD`, `capture start ABANDONED`, plus `reason=native-pipeline-stop`).
- [ ] **Close-out rule:** entry 415's "the same teardown that ignores `restartTask`" clause and #302's supersession get a dated pointer to this RESULT; the `#128` archive block gets an append-only dated pointer (a fifth row in its defence table's spirit: *restart vs SHUTDOWN*), never an edit of its bytes (#317(a)).

## DEVICE EVENING (Owen's hands)

Three cards, ~25 min total, Debug build, Verbose ON, thermal read before and after; same-day collect. Claude scores 428-D from the archive with the recipe above. **Stop rule:** any `capture chain HOT` after a session's `native-pipeline-stop` line on the fix build is a MISSED bar — file it verbatim with the surrounding 20 lines; the consequence (a second ordering this plan did not see) is a new dated block, not a redefinition of 428-D.

## Out of scope, and why

- The realtime engine (`LiveVoiceSessionService`) — no restart task; #415-C already gave it the #302-A instrument.
- The #82 wedge itself (a degenerate format / thrashing route storm) — the breaker at `:349-360` is untouched; this plan only makes its teardown honest.
- `TalkStore`'s generation (`#302`/`#415`) — untouched; this plan closes the layer beneath it.

## Self-review (2026-09-04, at plan-writing time)

- Every line number was read tonight, not recalled: `restartTask` at `:94 :342 :381 :383` (never cancelled — grep confirmed), teardown `:386-401`, the actor `:916`, `start(muted:)` `:985-1030` with its awaits at `:1013 :1015 :1022`, `startAnalyzer` `:1085-1121` (`bestAvailableAudioFormat` ×2, `prepareToAnalyze` ×2), install/start `:1158-1176`, the #128 adjacency comment `:1150-1156`, the route-change observer `:829-841` reading only the raw reason (postable from a test), the 750 ms cooldown `:124`/`:317-321`, `TalkStore.discardAbandonedStart` `:359-361`.
- The controller is `private` today and constructed inline (`:84`) — verified; no seam exists, which is why Task 1 is a task and not a note.
- What this plan does NOT claim: that the ordering has ever been observed on hardware (Task 0 (a) measures it), or that the simulator can start the audio engine under the test host (Task 0 (b) measures it and 428-B's control arm is pinned to the answer).
- Type consistency: `NativeVoiceCapturing.start/stop/setMuted/isTranscriptionSupported`; `NativeVoiceCaptureEvent`; `SpeechAnalysisAssembling.assemble(inputFormat:)`; `SpeechAnalysisAssembly.analyzer/analyzerFormat/reservedLocale/transcriber`; `TranscriberChoice.speech/.dictation`; `NativeVoiceCaptureController.init(assembler:)`, `.captureGeneration`, `.checkTicket(_:at:)`, `.isEngineRunning`, `CaptureError.superseded(point:)`, `.abandonedStartLogDetail(point:)`; `NativeVoicePipelineService.init(backendProvider:speechOutput:capture:)`, `.restartInFlight`, `.joinRestart(within:)` — used consistently across Tasks 1–3.
