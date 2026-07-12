import Foundation
import FoundationModels
import Testing
@testable import Talaria

/// #26 — the deterministic layer of LocalChatBackend: cumulative-snapshot
/// diffing, prompt composition with attachments, history → transcript-turn
/// mapping, the context-budget split, and the honest failure strings. The
/// FoundationModels generation path requires Apple Intelligence hardware and
/// is device-verified, not unit-tested — these tests pin down everything
/// around it.
struct LocalChatBackendTests {

    // MARK: Cumulative snapshot → incremental delta

    @Test func streamDeltaEmitsSuffixOfGrowingSnapshot() {
        #expect(LocalChatBackend.streamDelta(from: "", to: "Hel") == "Hel")
        #expect(LocalChatBackend.streamDelta(from: "Hel", to: "Hello, wor") == "lo, wor")
        #expect(LocalChatBackend.streamDelta(from: "Hello, wor", to: "Hello, world.") == "ld.")
    }

    @Test func streamDeltaReturnsNilWhenSnapshotAddsNothing() {
        #expect(LocalChatBackend.streamDelta(from: "same", to: "same") == nil)
        #expect(LocalChatBackend.streamDelta(from: "text", to: "") == nil)
        #expect(LocalChatBackend.streamDelta(from: "", to: "") == nil)
    }

    @Test func streamDeltaReturnsNilOnRewrite() {
        // A snapshot that rewrote earlier text has no safe increment — the
        // finished message carries the authoritative final text instead.
        #expect(LocalChatBackend.streamDelta(from: "Hello there", to: "Goodbye") == nil)
    }

    // MARK: Chat generation options (#102)

    @Test func chatGenerationOptionsBoundAndRetuneEveryTurn() {
        // Explicit config replaces the undocumented SDK defaults: without a
        // cap the model may fill the whole context window (the #102
        // phrase-loop + thermal mechanism), and without explicit non-greedy
        // sampling the temperature could be a no-op.
        let onDevice = LocalChatBackend.chatGenerationOptions(for: .onDevice)
        #expect(onDevice.maximumResponseTokens == LocalChatBackend.responseHeadroomTokens(for: .onDevice))
        #expect(onDevice.maximumResponseTokens == 1024)
        #expect(onDevice.temperature == 0.7)
        #expect(onDevice.samplingMode != nil)
        // PCC exists for long-form output — its cap follows its own headroom,
        // not the on-device 1024.
        let privateCloud = LocalChatBackend.chatGenerationOptions(for: .privateCloud)
        #expect(privateCloud.maximumResponseTokens == LocalChatBackend.responseHeadroomTokens(for: .privateCloud))
        #expect(privateCloud.maximumResponseTokens == 4096)
        #expect(privateCloud.temperature == 0.7)
        #expect(privateCloud.samplingMode != nil)
    }

    // MARK: Tail-repetition breaker (#102)

    @Test func tailRepetitionTripsOnLoopedPhrase() {
        let looped = "Let me check that for you. "
            + String(repeating: "I can absolutely help with that. ", count: 8)
        #expect(LocalChatBackend.hasDegenerateTailRepetition(looped))
    }

    @Test func tailRepetitionTripsRegardlessOfSnapshotAlignment() {
        // Stream snapshots cut mid-unit — a periodic tail must still match
        // at its period from any phase.
        let midUnit = String(repeating: "I can absolutely help with that. ", count: 8) + "I can abso"
        #expect(LocalChatBackend.hasDegenerateTailRepetition(midUnit))
    }

    @Test func tailRepetitionStaysBelowConservativeThresholds() {
        // A phrase said a few times is emphasis, not a loop (span guard).
        let three = String(repeating: "I can absolutely help with that. ", count: 3)
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(three))
        let five = String(repeating: "I can absolutely help with that. ", count: 5)
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(five))
        // Four copies of a long sentence clear the span but not the repeat
        // count — still not a loop.
        let fourLong = String(repeating: "The quick brown fox jumps over the lazy dog once again. ", count: 4)
        #expect(fourLong.count >= 192)
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(fourLong))
    }

    @Test func tailRepetitionIgnoresLists() {
        let list = "Here is the plan:\n"
            + (1...15).map { "\($0). Review item number \($0) in the queue" }.joined(separator: "\n")
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(list))
    }

    @Test func tailRepetitionIgnoresCodeAndSeparators() {
        // The indented brace run ("    }\n", 6-char fundamental period) DOES
        // match the scan at unit lengths 12, 18, … with qualifying
        // repeats/span — it is the unit qualification that rejects it: no
        // letter/digit, and self-periodic at divisor period 6.
        let braces = "struct A {\n    struct B {\n        let x = 1\n"
            + String(repeating: "    }\n", count: 40)
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(braces))
        // Separator art carries no words.
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(String(repeating: "-", count: 300)))
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(String(repeating: "|---|---|---|\n", count: 30)))
    }

    @Test func tailRepetitionIgnoresShortSyllableRefrains() {
        // Fundamental period 3 ("la ") is below the minimum unit; its
        // 9-character multiple must not qualify in its place.
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(String(repeating: "la ", count: 100)))
    }

    @Test func tailRepetitionOnlyTripsWhileTheLoopIsAtTheTail() {
        // The model escaped the loop and moved on — never cut a recovered
        // reply.
        let recovered = String(repeating: "I can absolutely help with that. ", count: 8)
            + "Anyway — here is the actual answer, which moves on to the real substance of the question."
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(recovered))
    }

    @Test func tailRepetitionIgnoresShortText() {
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(""))
        #expect(!LocalChatBackend.hasDegenerateTailRepetition("Sure, happy to help with that."))
    }

    @Test func tailRepetitionCatchesSentenceLengthLoops() {
        // Full-sentence loops are a common small-model degeneration shape —
        // this unit is 111 characters, above the old 96 cap.
        let sentence = "I'm sorry, but I can't seem to find the answer to that question in the information I have available right now. "
        #expect(LocalChatBackend.hasDegenerateTailRepetition(String(repeating: sentence, count: 7)))
    }

    @Test func tailRepetitionCatchesCJKPhraseLoops() {
        // CJK packs a whole phrase into a few characters — a 5-character Han
        // phrase loop qualifies through the CJK exception…
        #expect(LocalChatBackend.hasDegenerateTailRepetition(String(repeating: "我明白了。", count: 40)))
        // …while a same-period Latin syllable run stays below the floor.
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(String(repeating: "stop ", count: 50)))
    }

    // MARK: Breaker hysteresis (#102)

    @Test func breakerNeverAbandonsBoundedRepetition() {
        // Twelve identical code rows are legitimate output. Cumulative
        // snapshots make prefixes of them tail-repetitive — the breaker must
        // arm, watch the run END (closing bracket), disarm, and never abandon.
        let rows = "let rows = [\n"
            + String(repeating: "    (\"Lorem ipsum\", 42),\n", count: 12)
            + "]"
        var breaker = LocalChatBackend.RepetitionBreaker()
        var abandoned = false
        for length in 1...rows.count {
            let snapshot = String(rows.prefix(length))
            if breaker.shouldAbandon(afterObserving: LocalChatBackend.degenerateTailRepetitionRun(in: snapshot)) {
                abandoned = true
                break
            }
        }
        #expect(!abandoned)
        // And the finished text is healthy on its own.
        #expect(!LocalChatBackend.hasDegenerateTailRepetition(rows))
    }

    @Test func breakerAbandonsARunThatKeepsGrowing() {
        // A genuinely stuck loop keeps growing past twice its armed size.
        let unit = "I can absolutely help with that. "
        var breaker = LocalChatBackend.RepetitionBreaker()
        var abandonedAtCopies: Int?
        for copies in 1...24 {
            let snapshot = String(repeating: unit, count: copies)
            if breaker.shouldAbandon(afterObserving: LocalChatBackend.degenerateTailRepetitionRun(in: snapshot)) {
                abandonedAtCopies = copies
                break
            }
        }
        // Armed at 6 copies (detection floor), escalates at the absolute
        // floor of 12.
        #expect(abandonedAtCopies == LocalChatBackend.repetitionEscalationRepeats)
    }

    @Test func breakerDisarmsWhenTheTailRecovers() {
        // Mutating calls hoisted out of #expect — the macro captures the
        // receiver immutably ('$0' is immutable).
        var breaker = LocalChatBackend.RepetitionBreaker()
        let run = LocalChatBackend.TailRepetitionRun(unitLength: 33, repeats: 6)
        let armed = breaker.shouldAbandon(afterObserving: run)                       // arms
        #expect(!armed)
        let disarmed = breaker.shouldAbandon(afterObserving: nil)                    // disarms
        #expect(!disarmed)
        // Re-armed fresh: the old baseline must not carry over.
        let rearmed = breaker.shouldAbandon(afterObserving: run)
        #expect(!rearmed)
        let belowFloor = breaker.shouldAbandon(afterObserving: LocalChatBackend.TailRepetitionRun(unitLength: 33, repeats: 11))
        #expect(!belowFloor)
        let atFloor = breaker.shouldAbandon(afterObserving: LocalChatBackend.TailRepetitionRun(unitLength: 33, repeats: 12))
        #expect(atFloor)
    }

    @Test func breakerTripsAtTheWindowCeilingWhenArmedHigh() {
        // A coarse snapshot can arm the breaker above half the scan window's
        // observation ceiling (2048 / 128 = 16 copies max). Escalation must
        // clamp to that ceiling or a stuck loop would never be seen to
        // double and the breaker would never fire.
        // Mutating calls hoisted out of #expect (see above).
        var breaker = LocalChatBackend.RepetitionBreaker()
        let armedHigh = breaker.shouldAbandon(afterObserving: LocalChatBackend.TailRepetitionRun(unitLength: 128, repeats: 9))
        #expect(!armedHigh)
        let atCeiling = breaker.shouldAbandon(afterObserving: LocalChatBackend.TailRepetitionRun(unitLength: 128, repeats: 16))
        #expect(atCeiling)
    }

    // MARK: Degenerate-tail collapse (#102)

    @Test func collapsingDegenerateTailKeepsExactlyOneCopy() {
        let prefix = "Let me check. "
        let unit = "I can absolutely help with that. "
        let looped = prefix + String(repeating: unit, count: 12)
        #expect(LocalChatBackend.collapsingDegenerateTail(looped) == prefix + unit)
    }

    @Test func collapsingDegenerateTailReachesBeyondTheScanWindow() {
        // 100 copies of a 33-char unit span 3300 chars — well past the
        // 2048-char detection window. The collapse must walk the full text,
        // not just the window, or dozens of copies survive into history.
        let prefix = "Let me check. "
        let unit = "I can absolutely help with that. "
        let looped = prefix + String(repeating: unit, count: 100)
        #expect(LocalChatBackend.collapsingDegenerateTail(looped) == prefix + unit)
    }

    @Test func collapsingDegenerateTailLeavesHealthyTextAlone() {
        let healthy = "Here's the answer you asked for, with no funny business at the end."
        #expect(LocalChatBackend.collapsingDegenerateTail(healthy) == healthy)
    }

    // MARK: Prompt composition

    @Test func composePromptPassesPlainMessageThrough() {
        #expect(LocalChatBackend.composePrompt(message: "  What's up?  ", attachments: []) == "What's up?")
    }

    @Test func composePromptInlinesTextAttachmentsWithSharedDelimiters() {
        let file = PendingAttachment(
            kind: .file,
            fileName: "notes.md",
            mimeType: "text/markdown",
            data: Data("- remember the milk".utf8),
            localStoragePath: nil,
            thumbnailData: nil
        )
        let prompt = LocalChatBackend.composePrompt(message: "Summarize this", attachments: [file])
        #expect(prompt.hasPrefix("Summarize this"))
        #expect(prompt.contains("===== BEGIN FILE: notes.md"))
        #expect(prompt.contains("- remember the milk"))
        #expect(prompt.contains("===== END FILE: notes.md"))
    }

    @Test func composePromptReplacesImagesWithHonestNote() {
        let image = PendingAttachment(
            kind: .image,
            fileName: "photo.jpg",
            mimeType: "image/jpeg",
            data: Data([0xFF, 0xD8, 0xFF]),
            localStoragePath: nil,
            thumbnailData: nil
        )
        let prompt = LocalChatBackend.composePrompt(message: "What's in this?", attachments: [image])
        #expect(prompt.contains("photo.jpg"))
        #expect(prompt.contains("cannot view images"))
        // Never inline image bytes into an on-device text prompt.
        #expect(!prompt.contains("base64"))
    }

    @Test func composePromptFlagsNonInlinableFilesInsteadOfDroppingThem() {
        let binary = PendingAttachment(
            kind: .file,
            fileName: "scan.pdf",
            mimeType: "application/pdf",
            data: Data("%PDF-1.7".utf8),
            localStoragePath: nil,
            thumbnailData: nil
        )
        let prompt = LocalChatBackend.composePrompt(message: "Read this", attachments: [binary])
        #expect(prompt.contains("scan.pdf"))
        #expect(prompt.contains("was not delivered"))
    }

    // MARK: History → transcript turns

    @Test func transcriptTurnsKeepDeliveredChatAndVoiceTurns() {
        let messages = [
            Message(sender: .user, content: "Hi", status: .delivered),
            Message(sender: .hermes, content: "Hello!", status: .delivered),
            Message(sender: .voiceUser, content: "Spoken question", status: .delivered),
            Message(sender: .voiceHermes, content: "Spoken answer", status: .delivered),
        ]
        let turns = LocalChatBackend.transcriptTurns(from: messages)
        #expect(turns.map(\.role) == [.user, .assistant, .user, .assistant])
        #expect(turns.map(\.text) == ["Hi", "Hello!", "Spoken question", "Spoken answer"])
    }

    @Test func transcriptTurnsSkipSystemFailedStreamingAndEmpty() {
        let messages = [
            Message(sender: .system, content: "[Voice session ended]", status: .delivered),
            Message(sender: .user, content: "failed send", status: .failed),
            Message(sender: .user, content: "in flight", status: .sending),
            Message(sender: .hermes, content: "", status: .delivered),
            Message(sender: .hermes, content: "streaming", status: .sending, isStreaming: true),
            Message(sender: .user, content: "kept", status: .delivered),
        ]
        let turns = LocalChatBackend.transcriptTurns(from: messages)
        #expect(turns.count == 1)
        #expect(turns.first?.text == "kept")
    }

    @Test func transcriptTurnsExcludeTheMessageBeingSent() {
        let sendingID = UUID()
        let messages = [
            Message(sender: .user, content: "earlier", status: .delivered),
            Message(id: sendingID, clientMessageID: sendingID, sender: .user, content: "the live prompt", status: .delivered),
        ]
        let turns = LocalChatBackend.transcriptTurns(from: messages, excludingClientMessageID: sendingID)
        #expect(turns.map(\.text) == ["earlier"])
    }

    // MARK: Context-budget split

    @Test func verbatimSplitIndexIsZeroWhenEverythingFits() {
        #expect(LocalChatBackend.verbatimSplitIndex(turnTokenCounts: [100, 200, 300], availableBudget: 1000) == 0)
        #expect(LocalChatBackend.verbatimSplitIndex(turnTokenCounts: [], availableBudget: 10) == 0)
    }

    @Test func verbatimSplitIndexKeepsNewestTurnsWithinHalfBudget() {
        // Budget 1000 → verbatim share 500. Newest-first accumulation keeps
        // [300, 150] (450 ≤ 500) and cuts before the 400-token turn.
        let split = LocalChatBackend.verbatimSplitIndex(
            turnTokenCounts: [500, 400, 150, 300],
            availableBudget: 1000
        )
        #expect(split == 2)
    }

    @Test func verbatimSplitIndexAlwaysKeepsTheNewestTurn() {
        // The newest turn alone exceeds the verbatim share — it must survive
        // anyway (the model needs the turn it is being asked to continue).
        let counts = [500, 400, 4000]
        let split = LocalChatBackend.verbatimSplitIndex(turnTokenCounts: counts, availableBudget: 1000)
        #expect(split == 2)
        #expect(split < counts.count)
    }

    // MARK: Instructions + model-switch surface

    @Test func instructionsTextCarriesDateAndDeviceContext() {
        let text = LocalChatBackend.instructionsText(
            deviceContext: "Device: iPhone running iOS 27.0.",
            date: Date(timeIntervalSince1970: 1_750_000_000)
        )
        #expect(text.contains("Device: iPhone running iOS 27.0."))
        #expect(text.contains("2025")) // 2025-06-15 UTC — formatted with the year
        #expect(text.contains("Hermes"))
    }

    @Test func modelSwitchResponseParsesWithChatStoreContextRegex() {
        // The CTX meter's denominator comes from ChatStore's parse of the
        // switch response (#4) — the local backend's text must satisfy it
        // with the RUNTIME context size it was given.
        let response = LocalChatBackend.modelSwitchResponseText(modelID: "on-device", contextSize: 8192)
        #expect(ChatStore.reportedContextWindow(in: response) == 8192)
    }

    // MARK: Session info mapping

    @Test func sessionInfoMapsConversationForTheDrawer() {
        let conversation = Conversation(
            title: "Trip planning",
            messages: [
                Message(sender: .user, content: "Plan a trip", status: .delivered),
                Message(sender: .hermes, content: "Where to?", status: .delivered),
            ],
            lastActivity: Date(timeIntervalSince1970: 1_750_000_000),
            generatedPreview: "Planning a trip somewhere warm"
        )
        let info = LocalChatBackend.sessionInfo(for: conversation)
        #expect(info.id == conversation.id.uuidString)
        #expect(info.title == "Trip planning")
        #expect(info.preview == "Planning a trip somewhere warm")
        #expect(info.model == "on-device")
        #expect(info.source == "local")
        #expect(info.messageCount == 2)
        #expect(info.isActive)
    }

    @Test func sessionInfoLeavesPlaceholderTitleNil() {
        let conversation = Conversation(
            title: Conversation.defaultTitle,
            messages: [Message(sender: .user, content: "Hi", status: .delivered)]
        )
        let info = LocalChatBackend.sessionInfo(for: conversation)
        #expect(info.title == nil)
        #expect(info.preview == "Hi") // falls back to the last message
    }

    // MARK: Honest failure states

    @Test func unavailabilityMessagesAreDistinctAndActionable() {
        let messages = [
            LocalChatBackend.unavailabilityMessage(for: .deviceNotEligible),
            LocalChatBackend.unavailabilityMessage(for: .appleIntelligenceNotEnabled),
            LocalChatBackend.unavailabilityMessage(for: .modelNotReady),
        ]
        #expect(Set(messages).count == 3)
        for message in messages {
            #expect(!message.isEmpty)
        }
        #expect(messages[1].contains("Apple Intelligence"))
    }

    @Test func failureMessageFallsBackToDescriptionForForeignErrors() {
        struct FakeError: LocalizedError {
            var errorDescription: String? { "Something specific broke." }
        }
        #expect(LocalChatBackend.failureMessage(for: FakeError()) == "Something specific broke.")
        #expect(!LocalChatBackend.isContextOverflow(FakeError()))
    }
}
