import Foundation
import Testing
@testable import Talaria

/// #2 — read-aloud text preparation: streaming chunks buffer to sentence
/// boundaries, and markdown noise is stripped before synthesis.
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
}
