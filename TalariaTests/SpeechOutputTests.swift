import Foundation
import Testing
@testable import Talaria

/// #2 — read-aloud text preparation: streaming chunks buffer to sentence
/// boundaries, and markdown noise is stripped before synthesis.
/// #110 — the retract decision: a finish shorter than what streamed means
/// content was retracted (the #102 loop breaker), so pending speech stops.
struct SpeechOutputTests {

    // MARK: Sentence buffering

    @Test func flushesOnlyTerminatedSentences() {
        let (sentences, remainder) = SpeechOutputService.splitFlushableSentences(
            from: "Sunny and 22 degrees. Tomorrow looks"
        )
        #expect(sentences == ["Sunny and 22 degrees."])
        #expect(remainder == "Tomorrow looks")
    }

    @Test func terminatorWithoutFollowingWhitespaceStaysBuffered() {
        // "3.14" and a trailing "." mid-stream must not flush — the next chunk
        // may continue the token ("…continues" or "14").
        let (sentences, remainder) = SpeechOutputService.splitFlushableSentences(
            from: "Pi is 3.14 and the story continues."
        )
        #expect(sentences.isEmpty)
        #expect(remainder == "Pi is 3.14 and the story continues.")
    }

    @Test func newlinesFlushImmediately() {
        let (sentences, remainder) = SpeechOutputService.splitFlushableSentences(
            from: "First line\nSecond line\nTail"
        )
        #expect(sentences == ["First line", "Second line"])
        #expect(remainder == "Tail")
    }

    @Test func multipleTerminatorsAndBlankSegments() {
        let (sentences, remainder) = SpeechOutputService.splitFlushableSentences(
            from: "Really?! Yes. \n\nOkay"
        )
        #expect(sentences == ["Really?!", "Yes."])
        #expect(remainder == "Okay")
    }

    @Test func chunkedDeltasAccumulateAcrossCalls() {
        // Simulates the streaming path: remainder + next delta re-enter the split.
        var buffer = ""
        var spoken: [String] = []
        for delta in ["Hel", "lo the", "re. How a", "re you? I", "'m fine"] {
            buffer += delta
            let (sentences, remainder) = SpeechOutputService.splitFlushableSentences(from: buffer)
            spoken.append(contentsOf: sentences)
            buffer = remainder
        }
        #expect(spoken == ["Hello there.", "How are you?"])
        #expect(buffer == "I'm fine")
    }

    // MARK: Markdown cleanup

    @Test func stripsEmphasisHeadingsAndInlineCode()  {
        let spoken = SpeechOutputService.speechText(
            from: "## Result\nThe **fix** is `xcodegen generate`, _always_."
        )
        #expect(spoken == "Result\nThe fix is xcodegen generate, always.")
    }

    @Test func stripsCodeFenceMarkersButKeepsContent() {
        let spoken = SpeechOutputService.speechText(
            from: "Run this:\n```swift\nprint(1)\n```\nDone."
        )
        #expect(!spoken.contains("```"))
        #expect(!spoken.contains("swift\n"))
        #expect(spoken.contains("print(1)"))
        #expect(spoken.contains("Done."))
    }

    @Test func linksReadTheirLabelNotTheURL() {
        let spoken = SpeechOutputService.speechText(
            from: "See [the docs](https://example.com/very/long/path) for more."
        )
        #expect(spoken == "See the docs for more.")
    }

    @Test func whitespaceOnlyInputSpeaksNothing() {
        #expect(SpeechOutputService.speechText(from: "  \n\t ").isEmpty)
        #expect(SpeechOutputService.speechText(from: "```\n```").isEmpty)
    }

    // MARK: Retract decision (#110)

    @Test func shorterFinishRetracts() {
        #expect(SpeechOutputService.shouldRetractSpeech(
            finishedContent: "Short answer.",
            streamedText: "Short answer. Plus a tail the breaker cut."
        ))
    }

    @Test func equalFinishDoesNotRetract() {
        #expect(!SpeechOutputService.shouldRetractSpeech(
            finishedContent: "Same reply, start to finish.",
            streamedText: "Same reply, start to finish."
        ))
    }

    @Test func longerFinishDoesNotRetract() {
        // A final message carrying MORE than what streamed is not a
        // retraction — flush the queue as usual.
        #expect(!SpeechOutputService.shouldRetractSpeech(
            finishedContent: "The reply plus server-side additions.",
            streamedText: "The reply"
        ))
    }

    @Test func emptyFinishWithStreamedTextRetracts() {
        #expect(SpeechOutputService.shouldRetractSpeech(
            finishedContent: "",
            streamedText: "Anything at all streamed."
        ))
    }

    @Test func degenerateLoopCollapseRetracts() {
        // The #102 shape: the breaker rewrites N copies of the looped phrase
        // down to one.
        #expect(SpeechOutputService.shouldRetractSpeech(
            finishedContent: "phrase",
            streamedText: "phrase phrase phrase"
        ))
    }

    @Test func whitespaceJoinArtifactsDoNotFakeARetract() {
        // Chunk joins can differ from the final content in whitespace only —
        // folding must see these as equal, never as a retraction.
        #expect(!SpeechOutputService.shouldRetractSpeech(
            finishedContent: "One line.\nAnother line.",
            streamedText: "One line. \n Another  line.\n"
        ))
        #expect(!SpeechOutputService.shouldRetractSpeech(
            finishedContent: "",
            streamedText: "  \n\t "
        ))
    }

    // MARK: Stream finish behavior (#110)

    @MainActor @Test func shortenedFinishDropsThePendingQueue() {
        let service = SpeechOutputService()
        service.managesAudioSession = false
        let id = UUID()
        // No sentence terminator → the whole run stays buffered as pending speech.
        service.enqueueStreamChunk("phrase phrase phrase", messageID: id)
        #expect(service.speakingMessageID == id)
        service.finishStream(messageID: id, finishedContent: "phrase")
        // Retract: the queue is dropped, not flushed — nothing left speaking.
        #expect(service.speakingMessageID == nil)
    }

    @MainActor @Test func matchingFinishFlushesTheTail() {
        let service = SpeechOutputService()
        service.managesAudioSession = false
        let id = UUID()
        service.enqueueStreamChunk("All good", messageID: id)
        service.finishStream(messageID: id, finishedContent: "All good")
        // Normal completion: the buffered tail was flushed as an utterance,
        // so playback is still attributed to this message.
        #expect(service.speakingMessageID == id)
        service.stop()
    }

    // MARK: - #84 audio-session release decision

    /// The load-bearing case: an instance that never activated the session
    /// (never spoke) must NEVER release it, no matter how many stop() calls
    /// arrive -- releasing here deactivates the voice engine's live
    /// .playAndRecord session (the 2026-07-16 flatline).
    @Test func neverReleasesASessionItDidNotActivate() {
        #expect(SpeechOutputService.shouldReleaseAudioSession(
            managesSession: true, didActivate: false,
            utterancesIdle: true, streamIdle: true
        ) == false)
    }

    @Test func releasesOwnActivationWhenFullyIdle() {
        #expect(SpeechOutputService.shouldReleaseAudioSession(
            managesSession: true, didActivate: true,
            utterancesIdle: true, streamIdle: true
        ) == true)
    }

    @Test func holdsSessionWhileSpeechIsInFlight() {
        #expect(SpeechOutputService.shouldReleaseAudioSession(
            managesSession: true, didActivate: true,
            utterancesIdle: false, streamIdle: true
        ) == false)
        #expect(SpeechOutputService.shouldReleaseAudioSession(
            managesSession: true, didActivate: true,
            utterancesIdle: true, streamIdle: false
        ) == false)
    }

    /// The native pipeline's dedicated TTS instance (managesAudioSession ==
    /// false) never touches the session in either direction.
    @Test func nonManagingInstanceNeverReleases() {
        #expect(SpeechOutputService.shouldReleaseAudioSession(
            managesSession: false, didActivate: true,
            utterancesIdle: true, streamIdle: true
        ) == false)
    }

    // MARK: - #129 preview instance selection

    /// Mid-session, a voice preview must ride the native pipeline's
    /// session-less instance: the chat instance re-categorizing the shared
    /// session `.playAndRecord → .playback` under a live capture engine was
    /// the #128 trigger.
    @MainActor @Test func sessionActivePreviewsThroughNativeInstance() {
        let chat = SpeechOutputService()
        chat.managesAudioSession = false
        let native = SpeechOutputService()
        native.managesAudioSession = false
        #expect(SpeechOutputService.previewInstance(
            sessionActive: true, chat: chat, native: native
        ) === native)
    }

    /// No session → the chat instance previews, unchanged (#130: previews
    /// keep full `.playback` fidelity outside sessions).
    @MainActor @Test func noSessionPreviewsThroughChatInstance() {
        let chat = SpeechOutputService()
        chat.managesAudioSession = false
        let native = SpeechOutputService()
        native.managesAudioSession = false
        #expect(SpeechOutputService.previewInstance(
            sessionActive: false, chat: chat, native: native
        ) === chat)
    }
}
