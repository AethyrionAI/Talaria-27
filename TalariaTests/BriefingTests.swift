import Foundation
import Testing
@testable import Talaria

// #126: a briefing is recognized by payload category alone — tolerant of the
// producer's kind, honest when fields are missing (#58 lesson).

@Suite("Briefing recognition")
struct BriefingRecognitionTests {

    private func item(
        type: InboxItemType = .notification,
        payload: [String: String]? = nil,
        timestamp: Date = .now,
        body: String = "Body"
    ) -> InboxItem {
        InboxItem(type: type, title: "Title", body: body, timestamp: timestamp, payload: payload)
    }

    @Test("notification + category briefing is a briefing")
    func recognizesBriefing() {
        #expect(item(payload: ["category": "briefing"]).isBriefing)
    }

    @Test("Absent category, absent payload, or another category is NOT a briefing")
    func rejectsNonBriefings() {
        #expect(!item(payload: nil).isBriefing)
        #expect(!item(payload: [:]).isBriefing)
        #expect(!item(payload: ["category": "digest"]).isBriefing)
        #expect(!item(payload: ["speakable": "hi"]).isBriefing)
    }

    @Test("Recognition keys on category alone — a briefing payload on another kind still renders richly")
    func toleratesUnexpectedKind() {
        #expect(item(type: .reminder, payload: ["category": "briefing"]).isBriefing)
    }

    @Test("latestBriefing picks the newest briefing and ignores non-briefings")
    func latestSelection() {
        let old = item(payload: ["category": "briefing"], timestamp: Date(timeIntervalSinceReferenceDate: 1_000))
        let new = item(payload: ["category": "briefing"], timestamp: Date(timeIntervalSinceReferenceDate: 2_000))
        let noise = item(payload: nil, timestamp: Date(timeIntervalSinceReferenceDate: 3_000))
        #expect(InboxItem.latestBriefing(in: [old, noise, new])?.id == new.id)
        #expect(InboxItem.latestBriefing(in: [noise]) == nil)
        #expect(InboxItem.latestBriefing(in: []) == nil)
    }
}

@Suite("Briefing speakable text")
struct BriefingSpeakableTests {

    private func briefing(speakable: String?, body: String) -> InboxItem {
        var payload = ["category": "briefing"]
        if let speakable { payload["speakable"] = speakable }
        return InboxItem(type: .notification, title: "T", body: body, payload: payload)
    }

    @Test("speakable wins when present, trimmed")
    func speakableWins() {
        #expect(briefing(speakable: "  Good morning.  ", body: "ignored").briefingSpeakableText == "Good morning.")
    }

    @Test("Blank speakable falls back to the fence-stripped body")
    func blankSpeakableFallsBack() {
        #expect(briefing(speakable: "   ", body: "Hello there.").briefingSpeakableText == "Hello there.")
        #expect(briefing(speakable: nil, body: "Hello there.").briefingSpeakableText == "Hello there.")
    }

    @Test("Fallback drops fenced blocks — markers AND contents (chart JSON is not speech)")
    func fallbackStripsFences() {
        let body = "Sleep was solid.\n```chart\n{\"type\":\"bar\"}\n```\nThree events today."
        #expect(briefing(speakable: nil, body: body).briefingSpeakableText == "Sleep was solid.\nThree events today.")
    }

    @Test("Blank lines around a fence survive — typical markdown keeps its paragraph break")
    func blankLinesAroundFenceSurvive() {
        let body = "Sleep was solid.\n\n```chart\n{\"type\":\"bar\"}\n```\n\nThree events today."
        #expect(briefing(speakable: nil, body: body).briefingSpeakableText == "Sleep was solid.\n\n\nThree events today.")
    }

    @Test("Unterminated fence drops the tail — parity with the parser, which keeps it a code block")
    func unterminatedFenceDropsTail() {
        let body = "Intro line.\n```chart\n{\"type\":"
        #expect(InboxItem.strippingFencedBlocks(from: body) == "Intro line.")
    }
}
