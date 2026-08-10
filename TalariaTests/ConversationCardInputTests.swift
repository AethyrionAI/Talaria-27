import Foundation
import Testing
@testable import Talaria

/// #280 — the inputs the on-device conversation-card generator runs on.
///
/// **These start life as CHARACTERIZATION tests, written against the DEFECT
/// before any fix.** `voiceOnlyThreadYieldsNoCardInputs` PASSES as written:
/// today a voice-only thread returns nil from this function, which is what
/// blocker B2 (`generateConversationCardIfNeeded`'s eligibility guard matching
/// `.hermes` only, while a spoken reply is `.voiceHermes`) looks like from the
/// outside. Recording the defect in executable form first is what makes the
/// later RED honest evidence rather than a test pinned to text the fix never
/// touched.
///
/// Note what the tracker got wrong and these tests must not repeat: an EMPTY
/// user side is not the bug. `LocalIntelligenceService.fallbackCard` is built
/// for it — it borrows the reply's first line for the title and steps the
/// preview to the reply's second line so the two never echo.
struct ConversationCardInputTests {

    // MARK: - Builders

    private func message(
        _ sender: MessageSender,
        _ content: String,
        status: MessageStatus = .delivered,
        attachments: [MessageAttachment] = []
    ) -> Message {
        Message(sender: sender, content: content, status: status, attachments: attachments)
    }

    private func conversation(_ messages: [Message]) -> Conversation {
        Conversation(title: Conversation.defaultTitle, messages: messages)
    }

    /// The exact shape `ChatStore.voiceTranscriptMessages` produces: a
    /// `.system` banner, then one row per finalized spoken turn.
    private func voiceOnlyConversation() -> Conversation {
        conversation([
            message(.system, "[Voice session ended]"),
            message(.voiceUser, "Remind me what we decided about the trip to Lisbon."),
            message(.voiceHermes, "You settled on the first week of October, flying out of Gatwick."),
        ])
    }

    // MARK: - The defect, in executable form

    /// **CHARACTERIZATION — passes against the defect.** A thread whose only
    /// turns were spoken yields no card inputs at all, so the generator
    /// early-returns at its guard and the title stays `Conversation.defaultTitle`
    /// forever. Inverted by Task 2 into `voiceOnlyThreadYieldsTheSpokenExchange`.
    @Test func voiceOnlyThreadYieldsNoCardInputs() {
        #expect(ChatStore.conversationCardInputs(for: voiceOnlyConversation()) == nil)
    }

    // MARK: - The working cases these must not disturb (280-D)

    @Test func typedThreadYieldsUserAndReply() {
        let conv = conversation([
            message(.user, "  How do I renew the certificate?  "),
            message(.hermes, "Run the renew command from the deploy host."),
        ])

        let inputs = ChatStore.conversationCardInputs(for: conv)

        #expect(inputs?.userText == "How do I renew the certificate?")
        #expect(inputs?.assistantText == "Run the renew command from the deploy host.")
    }

    /// 280-D's deliberate case. `"[2 attachment(s)]"` is a DISPLAY
    /// placeholder, not user words — it must never become the title, and the
    /// card derives everything from the reply instead. **This row is the one
    /// that must NOT be "fixed".**
    @Test func attachmentPlaceholderNormalizesToEmptyUserText() {
        let attachment = MessageAttachment(kind: "image", fileName: "screenshot.png", mimeType: "image/png")
        let conv = conversation([
            message(.user, "[2 attachment(s)]", attachments: [attachment]),
            message(.hermes, "That's the login screen after the redirect."),
        ])

        let inputs = ChatStore.conversationCardInputs(for: conv)

        #expect(inputs?.userText == "")
        #expect(inputs?.assistantText == "That's the login screen after the redirect.")
    }

    /// A reply that has not been delivered is not a completed exchange.
    @Test func undeliveredReplyIsNotAnExchange() {
        let conv = conversation([
            message(.user, "Still there?"),
            message(.hermes, "", status: .sending),
        ])

        #expect(ChatStore.conversationCardInputs(for: conv) == nil)
    }

    /// A whitespace-only reply is not one either — a tool-shell row carries
    /// no content to label the thread with.
    @Test func whitespaceOnlyReplyIsNotAnExchange() {
        let conv = conversation([
            message(.user, "Run the check."),
            message(.hermes, "   \n  "),
        ])

        #expect(ChatStore.conversationCardInputs(for: conv) == nil)
    }

    /// No reply at all — the thread has nothing to label yet.
    @Test func userOnlyThreadYieldsNoInputs() {
        #expect(ChatStore.conversationCardInputs(for: conversation([message(.user, "Hello?")])) == nil)
    }
}
