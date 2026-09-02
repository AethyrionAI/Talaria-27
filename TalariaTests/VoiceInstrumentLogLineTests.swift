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
}
