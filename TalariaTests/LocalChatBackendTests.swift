import Foundation
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
