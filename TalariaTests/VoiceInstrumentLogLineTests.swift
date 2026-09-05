import Foundation
import Testing
@testable import Talaria

/// **#418/#419 — the two voice log-line formatters are pure and pinned.**
///
/// Both instruments exist because the 2026-08-30 AirPods archive (#413's
/// probe) exposed questions no existing log line could answer: which route
/// and sample rate the capture actually rode (#418), and what zeroes the
/// assistant-playback counter mid-utterance (#419 — every recorded reading
/// of `audio.stopped after Nms` is 0). An instrument that under-specifies
/// its own discriminator is #419's defect all over again, so the load-bearing
/// parts of each line are pinned here rather than trusted.
@Suite("Voice instrument log lines (#418/#419)")
struct VoiceInstrumentLogLineTests {

    // MARK: - #419 assistant item arrival

    @Test("mid-playback arrival names the elapsed being destroyed")
    func midPlaybackArrivalNamesTheDestroyedElapsed() {
        let line = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.added",
            itemID: "item_B",
            currentItemID: "item_A",
            playbackElapsedMs: 2160
        )
        #expect(line.contains("MID-PLAYBACK"))
        #expect(line.contains("2160ms"))
    }

    @Test("idle arrival says idle and carries no mid-playback marker")
    func idleArrivalSaysIdle() {
        let line = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.added",
            itemID: "item_B",
            currentItemID: "item_A",
            playbackElapsedMs: nil
        )
        #expect(line.contains("assistant idle"))
        #expect(!line.contains("MID-PLAYBACK"))
    }

    @Test("same item re-announced is distinguished from a new item")
    func sameItemReannouncementIsDistinguished() {
        let same = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.added",
            itemID: "item_A",
            currentItemID: "item_A",
            playbackElapsedMs: nil
        )
        let new = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.added",
            itemID: "item_B",
            currentItemID: "item_A",
            playbackElapsedMs: nil
        )
        #expect(same.contains("same item re-announced"))
        #expect(!same.contains("new item"))
        #expect(new.contains("new item"))
        #expect(new.contains("item_A"))  // the replaced id is named
        #expect(!new.contains("same item re-announced"))
    }

    @Test("the session's first assistant item says so")
    func firstItemOfTheSessionSaysSo() {
        let line = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.created",
            itemID: "item_A",
            currentItemID: nil,
            playbackElapsedMs: nil
        )
        #expect(line.contains("first assistant item"))
    }

    @Test("the event type rides the line — beta/GA double-fire is readable")
    func eventTypeRidesTheLine() {
        let line = LiveVoiceSessionService.assistantItemArrivalLogDetail(
            eventType: "conversation.item.created",
            itemID: "item_A",
            currentItemID: nil,
            playbackElapsedMs: nil
        )
        #expect(line.contains("conversation.item.created"))
    }

    // MARK: - #418 audio route

    @Test("route line carries every port type, port name, and the sample rate")
    func routeLineCarriesPortsAndSampleRate() {
        let line = LiveVoiceSessionService.audioRouteLogDetail(
            inputs: [(portType: "BluetoothHFP", portName: "AirPods Pro")],
            outputs: [(portType: "BluetoothA2DPOutput", portName: "AirPods Pro")],
            sampleRateHz: 16000.0
        )
        #expect(line.contains("BluetoothHFP"))
        #expect(line.contains("BluetoothA2DPOutput"))
        #expect(line.contains("AirPods Pro"))
        #expect(line.contains("16000Hz"))
    }

    @Test("multiple ports are all listed, none silently dropped")
    func multiplePortsAllListed() {
        let line = LiveVoiceSessionService.audioRouteLogDetail(
            inputs: [
                (portType: "MicrophoneBuiltIn", portName: "iPhone Microphone"),
                (portType: "BluetoothHFP", portName: "AirPods Pro"),
            ],
            outputs: [(portType: "Speaker", portName: "Speaker")],
            sampleRateHz: 48000.0
        )
        #expect(line.contains("MicrophoneBuiltIn"))
        #expect(line.contains("BluetoothHFP"))
        #expect(line.contains("48000Hz"))
    }

    @Test("an empty input list is stated, not rendered as blank")
    func emptyInputListIsStated() {
        let line = LiveVoiceSessionService.audioRouteLogDetail(
            inputs: [],
            outputs: [(portType: "Speaker", portName: "Speaker")],
            sampleRateHz: 48000.0
        )
        #expect(line.contains("in=[none]"))
    }

    // MARK: - #198B-M audio-session transition (the memo path's positive control)

    /// **Why this line exists.** #198B-A's device bar is an ABSENCE bar — zero
    /// `AVAudioSession_iOS.mm` fault lines across a memo record→play→discard
    /// session — and an absence bar with no positive control passes on an
    /// empty log. The 198B-BAR lane (PR #408) could only find ONE app-emitted
    /// marker on that path: a `.debug` line, verbose-gated, on the RECORD leg
    /// alone, which `log collect` does not persist. So the control could not
    /// see play or discard at all.
    ///
    /// This line is emitted from `AudioSessionOffMain` — the single off-main
    /// choke point every memo transition funnels through — at `.notice`,
    /// un-gated. Present ⇒ the path ran; absent ⇒ the run did not exercise it
    /// and the verdict is INVALID rather than PASS.

    @Test("an activation names its direction, its reason, and the item")
    func activationNamesDirectionReasonAndItem() {
        let line = AudioSessionOffMain.setActiveLogDetail(
            active: true,
            reason: "memo-playback-start"
        )
        #expect(line.contains("setActive(true)"))
        #expect(line.contains("reason=memo-playback-start"))
        #expect(line.contains("off-main"))
        #expect(line.contains("#198B"))
    }

    /// The control has to separate the two halves of a transition: a
    /// stop-then-start emits BOTH, and a line that could not say which is
    /// which would re-open the ordering question 198B-B closed.
    @Test("a deactivation is distinguishable from an activation")
    func deactivationIsDistinguishableFromActivation() {
        let off = AudioSessionOffMain.setActiveLogDetail(
            active: false,
            reason: "memo-playback-stop"
        )
        #expect(off.contains("setActive(false)"))
        #expect(!off.contains("setActive(true)"))
        #expect(off.contains("reason=memo-playback-stop"))
    }

    /// The reason is what lets one predicate attribute a line to the RECORD,
    /// the PLAY or the DISCARD leg — without it the control proves only that
    /// *something* touched the session.
    @Test("each leg's reason rides its own line verbatim")
    func eachLegsReasonRidesItsOwnLine() {
        let record = AudioSessionOffMain.setActiveLogDetail(
            active: true,
            reason: "memo-record-start"
        )
        let discard = AudioSessionOffMain.setActiveLogDetail(
            active: false,
            reason: "memo-record-stop"
        )
        #expect(record.contains("reason=memo-record-start"))
        #expect(!record.contains("reason=memo-record-stop"))
        #expect(discard.contains("reason=memo-record-stop"))
    }

    // MARK: - #396-Q the tuning preset the app mints with

    /// **Why this line exists.** #413's 2026-08-26 device pass measured a
    /// per-session phantom rate while Owen switched between the Noisy and
    /// Normal voice-tuning presets — and the archive cannot attribute those
    /// sessions to a preset, because the app never logged the tuning it minted
    /// with. The pick reaches the plugin as a request field and vanishes from
    /// the phone's own record.
    ///
    /// **The app sends a NAME, not numbers.** Vetted `server_vad` values are
    /// resolved HOST-side (396-P's ruled design — the app never composes
    /// `turn_detection`), so the line says `values=host` rather than inventing
    /// a threshold the app did not send.

    @Test("the tuning line names the preset, the engine, and where the values live")
    func tuningLineNamesPresetEngineAndValueOwner() {
        let line = LiveVoiceSessionService.sessionTuningLogDetail(
            preset: "noisy",
            engine: "realtime",
            hostTunings: ["quiet", "normal", "noisy"]
        )
        #expect(line.contains("#396"))
        #expect(line.contains("preset=noisy"))
        #expect(line.contains("engine=realtime"))
        #expect(line.contains("values=host"))
    }

    /// `.normal` is the default, so it is exactly the case an absent line
    /// would be confused with — it must be logged like any other pick.
    @Test("the default pick is logged too, so absence stays unambiguous")
    func theDefaultPickIsLoggedToo() {
        let line = LiveVoiceSessionService.sessionTuningLogDetail(
            preset: "normal",
            engine: "realtime",
            hostTunings: ["quiet", "normal", "noisy"]
        )
        #expect(line.contains("preset=normal"))
    }

    /// A host whose plugin predates tuning ignores the field, so the pick
    /// does NOT bind. The line has to say the difference rather than imply
    /// effect — the same honesty the picker's own footnote carries.
    @Test("a host that predates tuning is stated, never implied to have bound")
    func aHostThatPredatesTuningIsStated() {
        let unknown = LiveVoiceSessionService.sessionTuningLogDetail(
            preset: "noisy",
            engine: "realtime",
            hostTunings: nil
        )
        let bound = LiveVoiceSessionService.sessionTuningLogDetail(
            preset: "noisy",
            engine: "realtime",
            hostTunings: ["quiet", "normal", "noisy"]
        )
        #expect(unknown.contains("hostAccepts=unknown"))
        #expect(bound.contains("hostAccepts=[quiet,normal,noisy]"))
        #expect(!bound.contains("unknown"))
    }

    // MARK: - #138-M the segment instrument (card V3)

    /// **Why these three lines exist.** #138's 2026-09-01 escalation synthesis
    /// left H3 — *the server's `prefix_padding_ms` shapes the fragment the
    /// transcriber sees* — with no instrument. The archives can say WHEN a
    /// phantom `speech_started` fired relative to `audio.started`, and they can
    /// show the bubble it produced, but nothing in the log says how much audio
    /// the server actually committed. H3 predicts 300–700 ms segments at onset
    /// offsets ≤0.6 s carrying a cjk/other script class; a phantom segment
    /// ≥1.5 s would falsify "onset" and take H1's shape with it. None of that
    /// is scoreable without these lines.
    ///
    /// **The transcript's TEXT is never logged**, and that is pinned rather
    /// than trusted — a device archive is collected wholesale and shared, so
    /// an instrument that leaks what the user said would be a privacy defect
    /// shipped in the name of a measurement.

    @Test("a speech_stopped segment names its length and its offset from playback")
    func speechStoppedNamesSegmentLengthAndOffset() {
        let line = LiveVoiceSessionService.speechStoppedSegmentLogDetail(
            audioStartMs: 1200,
            audioEndMs: 1700,
            offsetFromPlaybackMs: 520
        )
        #expect(line.hasPrefix("#138 segment "))
        #expect(line.contains("speech_stopped"))
        #expect(line.contains("segmentMs=500"))
        #expect(line.contains("offsetFromPlaybackMs=520"))
        // The WHOLE shape, because the runbook's Record step and every archive
        // grep are written against it — a reordered or extra field breaks a
        // reader that never runs this suite.
        #expect(line == "#138 segment speech_stopped segmentMs=500 offsetFromPlaybackMs=520")
    }

    /// `none` and `0` are opposite readings — `0` would say the segment landed
    /// exactly at playback onset, which is the single most incriminating value
    /// this instrument can print. A session that has played no audio at all
    /// must never be able to render it.
    @Test("no playback yet reads none, never zero")
    func noPlaybackYetReadsNoneNeverZero() {
        let line = LiveVoiceSessionService.speechStoppedSegmentLogDetail(
            audioStartMs: 0,
            audioEndMs: 400,
            offsetFromPlaybackMs: nil
        )
        #expect(line.contains("offsetFromPlaybackMs=none"))
        #expect(!line.contains("offsetFromPlaybackMs=0"))
    }

    /// A `speech_stopped` with no preceding `speech_started` (or a server that
    /// omits the field) has no segment length. Printing `segmentMs=0` there
    /// would manufacture the very reading H3 is being tested on.
    @Test("a missing audio_start_ms is stated, never rendered as a zero-length segment")
    func missingAudioStartIsStatedNotZeroed() {
        let line = LiveVoiceSessionService.speechStoppedSegmentLogDetail(
            audioStartMs: nil,
            audioEndMs: 1700,
            offsetFromPlaybackMs: 300
        )
        #expect(line.contains("segmentMs=unknown"))
        #expect(!line.contains("segmentMs=0"))
    }

    /// The commit is what the transcriber is handed, so its offset is the
    /// second half of the onset reading — and the item id is the only key that
    /// joins this line to the transcript line that follows it.
    @Test("a committed buffer carries the offset and the item it commits to")
    func committedCarriesOffsetAndItem() {
        let line = LiveVoiceSessionService.bufferCommittedSegmentLogDetail(
            offsetFromPlaybackMs: 340,
            itemID: "item_9"
        )
        #expect(line.hasPrefix("#138 segment "))
        #expect(line.contains("committed"))
        #expect(line.contains("offsetFromPlaybackMs=340"))
        #expect(line.contains("itemId=item_9"))
        #expect(line == "#138 segment committed offsetFromPlaybackMs=340 itemId=item_9")
    }

    /// **The privacy pin.** A CJK transcript is used deliberately: none of its
    /// characters can appear incidentally in the line's own field names, so a
    /// leak of even one character is unambiguous.
    @Test("the transcript line carries length and script class and NEVER the text")
    func theTranscriptLineNeverCarriesTheText() {
        let text = "\u{55E8}\u{3002}\u{518D}\u{8003}"  // 嗨。再考
        let line = LiveVoiceSessionService.transcriptSegmentLogDetail(
            transcript: text,
            itemID: "item_9"
        )
        #expect(line.hasPrefix("#138 segment "))
        #expect(line.contains("transcript"))
        #expect(line.contains("chars=4"))
        #expect(line.contains("script=cjk"))
        #expect(line.contains("itemId=item_9"))
        #expect(!line.contains(text))
        for character in text {
            #expect(!line.contains(character), "the transcript leaked into the log line")
        }
        #expect(line == "#138 segment transcript chars=4 script=cjk itemId=item_9")
    }

    /// The CJK signature is the whole point of the class — every recorded
    /// phantom text so far is a short non-English token — but a class that
    /// could only say "cjk" would prove nothing. All four arms are pinned,
    /// including the Cyrillic case that must NOT read as latin.
    @Test("the script class separates latin, cjk, other and empty")
    func theScriptClassSeparatesAllFourCases() {
        func script(_ transcript: String) -> String {
            LiveVoiceSessionService.transcriptSegmentLogDetail(
                transcript: transcript,
                itemID: nil
            )
        }
        #expect(script("Good afternoon.").contains("script=latin"))
        #expect(script("Echt?").contains("script=latin"))
        #expect(script("\u{55E8}").contains("script=cjk"))              // 嗨
        #expect(script("\u{3053}\u{3093}").contains("script=cjk"))      // こん
        #expect(script("\u{30AB}\u{30CA}").contains("script=cjk"))      // カナ
        #expect(script("\u{C548}\u{B155}").contains("script=cjk"))      // 안녕
        #expect(script("\u{041F}\u{0440}\u{0438}").contains("script=other"))  // При
        #expect(script("   ").contains("script=empty"))
        #expect(script("").contains("script=empty"))
        #expect(script("").contains("chars=0"))
    }

    // MARK: - #138-O the onset gate (card V5)

    /// **Why these lines exist.** The gate is a SILENT behaviour change on the
    /// one path #138 is about: it disables the local uplink for the first
    /// milliseconds of every assistant playback. Without a line per arming, a
    /// device pass that sees zero `#138 BARGE-IN` cannot tell "the gate held"
    /// from "the server never sent a `speech_started`" — an absence bar with no
    /// positive control, which is exactly the trap #198B-A was built to close
    /// and which V2's Record step already had to add for #138-M.
    ///
    /// The window is printed rather than assumed, because the constant is the
    /// one tunable this fix has (138-O-A) and a log that named no number would
    /// leave every archive ambiguous about which build produced it.

    @Test("the arming line names the window in milliseconds")
    func theArmingLineNamesTheWindow() {
        let line = LiveVoiceSessionService.onsetGateArmedLogDetail(
            windowMs: LiveVoiceSessionService.onsetGateWindowMilliseconds
        )
        #expect(line.contains("800ms"))
        // The WHOLE shape, because the runbook's Record step and every archive
        // grep are written against it — a reordered or extra field breaks a
        // reader that never runs this suite.
        #expect(line == "#138 onset gate: uplink muted 800ms")
    }

    /// The constant is the fix's one tunable, so the line must read it rather
    /// than restate it: a build with a different window has to say so.
    @Test("the arming line reads the constant, it does not hardcode 800")
    func theArmingLineReadsTheConstant() {
        #expect(
            LiveVoiceSessionService.onsetGateArmedLogDetail(windowMs: 1234)
                == "#138 onset gate: uplink muted 1234ms"
        )
        #expect(LiveVoiceSessionService.onsetGateWindowMilliseconds == 800)
    }

    /// The release line is the arming line's other half. An archive showing a
    /// `muted` with no `restored` means the window was still open when the
    /// session ended — a reading the gate must not be able to fake.
    @Test("the release line is the arming line's counterpart")
    func theReleaseLineIsTheArmingLineCounterpart() {
        #expect(LiveVoiceSessionService.onsetGateRestoredLogLine == "#138 onset gate: uplink restored")
    }

    /// The suppression line is the positive control for 138-O-E's absence bar:
    /// it says the gate CAUGHT something, which "no BARGE-IN in the log" alone
    /// can never distinguish from "nothing arrived".
    @Test("a suppressed speech_started names its offset and the window it fell inside")
    func theSuppressionLineNamesOffsetAndWindow() {
        let line = LiveVoiceSessionService.onsetGateSuppressedLogDetail(offsetMs: 312, windowMs: 800)
        #expect(line.contains("312ms"))
        #expect(line.contains("800ms"))
        #expect(line == "#138 onset gate: speech_started suppressed 312ms into the 800ms window")
    }

    // MARK: - #428 the abandoned capture start (bar 428-B)

    /// **Why this line exists.** #428's fix is an ABSENCE: a capture start that
    /// a `stop()` interleaved with installs nothing. An archive cannot tell
    /// "the ticket caught a superseded start" from "no restart was ever
    /// attempted" unless the abandonment says so itself — the same
    /// absence-bar-needs-a-positive-control trap #198B-A was built to close.
    ///
    /// It rides at `.notice`, `privacy: .public` and un-gated (#302-A's rule
    /// for the capture chain), alongside that instrument's own HOT/COLD pair:
    /// an ABANDONED between a COLD and no following HOT is the whole fix,
    /// visible in one grep.
    @Test("the abandoned-start line names where the generation moved and that nothing installed")
    func theAbandonedStartLineNamesThePointAndTheAbsence() {
        let line = NativeVoiceCaptureController.abandonedStartLogDetail(point: "assembled")
        #expect(line.contains("ABANDONED"))
        #expect(line.contains("assembled"))
        #expect(line.contains("nothing installed"))
        #expect(line.contains("#428"))
        // The WHOLE shape, because a device archive is read by grep and not by
        // this suite — a reordered or reworded line breaks that reader silently.
        #expect(
            line
                == "capture start ABANDONED — capture generation moved during startup at assembled; nothing installed (#428)"
        )
    }

    /// The point is the line's only variable, and it exists for the day a
    /// second suspension point returns to the startup path: a line that could
    /// not say WHERE the generation moved would leave the next archive
    /// ambiguous about which window the stop landed in.
    @Test("a different point renders a different line")
    func aDifferentAbandonPointRendersADifferentLine() {
        #expect(
            NativeVoiceCaptureController.abandonedStartLogDetail(point: "prepared")
                == "capture start ABANDONED — capture generation moved during startup at prepared; nothing installed (#428)"
        )
    }

    // MARK: - #428 the abandoned capture RESTART (bar 428-A, fix round 1)

    /// **Why this line exists.** The primary 428-A path — the user ends the
    /// session while a route-change restart is parked inside `capture.start`
    /// — is the fix WORKING. Until fix round 1 that path fell into
    /// `restartCapture`'s generic catch and wrote
    /// `capture restart failed: … (Swift.CancellationError error 1.)` at
    /// `Logger.warning`, which OSLog records at ERROR severity. So the
    /// designed-correct teardown left an error row naming a failure — every
    /// time, not as a race — and dragged a raw Swift error description into
    /// every collected archive with it.
    ///
    /// The typed `catch is CancellationError` arm replaces that with a
    /// `.notice` that says what actually happened. Its text is pinned here
    /// because a device archive is read by grep, not by this suite.
    @Test("an abandoned restart reads as an abandonment, never as a failure")
    func theAbandonedRestartLineReadsAsAnAbandonment() {
        let line = NativeVoicePipelineService.restartAbandonedLogDetail(sessionEnding: true)
        #expect(line.contains("abandoned"))
        #expect(line.contains("#428"))
        #expect(!line.lowercased().contains("failed"))
        // The raw error description is what the old warning carried. This
        // formatter takes no error at all, and that is the pin.
        #expect(!line.contains("CancellationError"))
        #expect(!line.contains("couldn't be completed"))
        // The WHOLE shape, because the archive reader is a grep.
        #expect(
            line
                == "capture restart abandoned by teardown — the session is ending; nothing installed, nothing painted (#428)"
        )
    }

    /// A cancellation with the session still live is a different event from a
    /// clean shutdown. An instrument that rendered both identically would be
    /// #419's under-specified-discriminator defect over again.
    @Test("a live-session cancellation is distinguished from an ending session")
    func aLiveSessionCancellationIsDistinguishedFromAnEndingSession() {
        let live = NativeVoicePipelineService.restartAbandonedLogDetail(sessionEnding: false)
        #expect(live.contains("still live"))
        #expect(!live.contains("the session is ending"))
        #expect(
            live
                == "capture restart abandoned by teardown — the restart task was cancelled with the session still live; nothing installed, nothing painted (#428)"
        )
    }

    /// **The wiring pin, and it is here because nothing behavioural can stand
    /// in for it.** The call site's value is swallowed by `Logger.notice`, and
    /// the typed arm's STATE outcome is identical to the generic catch's
    /// (`isEndingSession` guard ⇒ return) — so deleting the arm leaves both
    /// tests above green, leaves `NativeVoiceRestartTeardownTests` green, and
    /// silently restores the warning-severity error row this fix exists to
    /// remove. The arm is therefore pinned structurally: it must exist, it
    /// must call the formatter above, and it must sit AHEAD of the generic
    /// catch — a typed arm placed after the generic one never runs.
    ///
    /// Fails LOUDLY when it cannot read the file: a check that did not run
    /// must say so rather than pass (`NamingSweepTests`' rule).
    @Test("the typed cancellation arm is wired, and sits ahead of the generic catch")
    func theTypedCancellationArmIsWiredAheadOfTheGenericCatch() throws {
        let source = try Self.pipelineServiceSource()
        let typedArm = try #require(
            source.range(of: "} catch is CancellationError {"),
            "the `catch is CancellationError` arm is gone — a restart abandoned by teardown logs `capture restart failed` at warning severity again (#428 fix round 1)"
        )
        let genericArm = try #require(
            source.range(of: "Self.logger.warning(\"capture restart failed:"),
            "the generic catch's warning line is gone — this pin can no longer prove the ordering it asserts"
        )
        #expect(
            typedArm.lowerBound < genericArm.lowerBound,
            "the typed arm must precede the generic catch, or a CancellationError never reaches it"
        )
        #expect(
            source.contains("Self.restartAbandonedLogDetail(sessionEnding: self.isEndingSession)"),
            "the typed arm no longer calls the pinned formatter — the two shape pins above are pinned to nothing"
        )
    }

    // MARK: - #428 the CANCELLED join, and the LIVE-session supersession
    //         (final review, Critical 1 and Important 3)

    /// **Two over-bound exits, two different events.** `joinRestart` can leave
    /// its poll because the 3 s bound elapsed (a capture stack that stopped
    /// answering) or because its CALLER was cancelled — the cover watch task,
    /// the overlay's `.task` — which is not a wait at all. The bound-elapsed
    /// line says "after 3.0 seconds"; saying that on a join cut short at
    /// 40 ms would misreport the shutdown that produced it, which is #419's
    /// under-specified-discriminator defect in the other direction.
    @Test("a cancelled join reports the cancel, never the bound")
    func theCancelledJoinLineReportsTheCancelNotTheBound() {
        let line = NativeVoicePipelineService.restartJoinAbandonedLogDetail(
            elapsed: .milliseconds(120)
        )
        #expect(line.contains("caller cancelled"))
        #expect(!line.contains("still in flight"))
        #expect(line.contains("#428"))
        // The whole shape, because the archive reader is a grep — and the
        // elapsed value is rendered, so a join cut short at 40 ms cannot be
        // mistaken for one that waited the bound out.
        #expect(
            line
                == "restart join abandoned — caller cancelled after 120 ms; the capture generation covers the straggler (#428)"
        )
        #expect(
            NativeVoicePipelineService.restartJoinAbandonedLogDetail(elapsed: .milliseconds(2_500))
                == "restart join abandoned — caller cancelled after 2500 ms; the capture generation covers the straggler (#428)"
        )
    }

    /// The wiring pin for the cancelled exit, structural for the same reason
    /// the abandoned-restart one is: `Logger.notice` swallows its argument, so
    /// nothing behavioural can see which of the two branches ran. The
    /// behavioural test (`aCancelledCallerDoesNotBusyWaitOutTheJoinBound`)
    /// pins the BREAK; this pins that the break's exit is instrumented, and
    /// that the bound line is not what reports it.
    ///
    /// **Positional, not `contains`.** `if Task.isCancelled { break }` already
    /// appears elsewhere in this file (the turn-stream loop), so a whole-file
    /// `contains` would stay green with `joinRestart`'s break deleted — a pin
    /// that cannot fail. It is bounded to the method's own body instead.
    @Test("the join's cancelled exit is wired to its own line")
    func theJoinsCancelledExitIsWiredToItsOwnLine() throws {
        let source = try Self.pipelineServiceSource()
        let joinStart = try #require(
            source.range(of: "private func joinRestart(within bound: Duration) async {"),
            "`joinRestart` is gone or renamed — this pin can no longer say where it is looking"
        )
        let formatterCall = try #require(
            source.range(of: "Self.restartJoinAbandonedLogDetail(elapsed:"),
            "the cancelled exit no longer calls the pinned formatter — the shape pin above is pinned to nothing (#428 Critical 1)"
        )
        let body = source[joinStart.upperBound..<formatterCall.lowerBound]
        #expect(
            body.contains("if Task.isCancelled { break }"),
            "the cancelled-caller break is gone from `joinRestart` — a cancelled `Task.sleep` throws instantly and the poll busy-waits the MainActor out to its bound (#428 Critical 1)"
        )
        // The bound line must not be what reports a cancelled exit.
        let boundLine = try #require(
            source.range(of: "restart still in flight after \\("),
            "the bound-elapsed line is gone — this pin can no longer prove the two exits are distinguished"
        )
        #expect(
            formatterCall.lowerBound < boundLine.lowerBound,
            "the cancelled exit must be reported before, and separately from, the bound-elapsed line"
        )
    }

    /// **A positive control for an absence.** On the live-session arm the
    /// `.superseded` catch returns silently and can leave `.connected` /
    /// `.listening` with no capture chain behind it (the old analyzer's
    /// `.failed` event is yielded into a continuation `capture.stop()` already
    /// finished, so it is dropped). Narrow, but with no line at all an archive
    /// cannot tell that session from one where no restart was ever attempted.
    @Test("the live-session supersession names the ordering, not a fault")
    func theLiveSessionSupersessionLineNamesTheOrdering() {
        let line = NativeVoicePipelineService.restartSupersededOnLiveSessionLogDetail()
        #expect(line.contains("LIVE session"))
        #expect(line.contains("#428"))
        // It is an ordering, not a device fault: no failure vocabulary, and no
        // claim the user must act on.
        #expect(!line.lowercased().contains("failed"))
        #expect(!line.contains("could not resume"))
        #expect(
            line
                == "capture restart superseded on a LIVE session — a stop ran during the restart's startup; no capture chain until the next route change (#428)"
        )
    }

    /// The wiring pin, and it must pin the line INSIDE the `.superseded` arm:
    /// the same call placed in the generic catch or after the arm would log
    /// the wrong event. Pinned by offset between the two catch markers, the
    /// established pattern of the ordering pin above.
    @Test("the live-session line is emitted from the .superseded arm itself")
    func theLiveSessionLineIsEmittedFromTheSupersededArm() throws {
        let source = try Self.pipelineServiceSource()
        let supersededArm = try #require(
            source.range(of: "} catch NativeVoiceCaptureController.CaptureError.superseded {"),
            "the typed `.superseded` arm is gone — this pin can no longer prove where the line is emitted"
        )
        let cancellationArm = try #require(
            source.range(of: "} catch is CancellationError {"),
            "the `catch is CancellationError` arm is gone — this pin can no longer bound the `.superseded` arm"
        )
        let call = try #require(
            source.range(of: "Self.restartSupersededOnLiveSessionLogDetail()"),
            "the live-session supersession is silent again — a session left with no capture chain emits nothing (#428 Important 3)"
        )
        #expect(
            call.lowerBound > supersededArm.upperBound && call.upperBound < cancellationArm.lowerBound,
            "the line must be emitted from INSIDE the `.superseded` arm, or it names an event that did not happen"
        )
        #expect(
            source.contains("if !self.isEndingSession {"),
            "the line is no longer gated on a LIVE session — an ordinary shutdown would emit it too (#428 decision 2)"
        )
    }

    private static func pipelineServiceSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TalariaTests/
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Talaria/Services/Live/NativeVoicePipelineService.swift")
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "cannot read NativeVoicePipelineService.swift at \(url.path) — this check did not run"
        )
    }
}
