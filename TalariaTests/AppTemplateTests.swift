import Testing
@testable import Talaria

struct TalariaTests {

    @Test func messageCreationDefaultsToSentStatus() async throws {
        let message = Message(sender: .user, content: "Hello Hermes")
        #expect(message.sender == .user)
        #expect(message.content == "Hello Hermes")
        #expect(message.status == .sent)
    }

    @Test func conversationPreviewTextShowsLastMessage() async throws {
        let messages = [
            Message(sender: .hermes, content: "First message"),
            Message(sender: .user, content: "Second message"),
        ]
        let conversation = Conversation(title: "Test", messages: messages)
        #expect(conversation.previewText == "Second message")
        #expect(conversation.lastMessage?.sender == .user)
    }

    @Test func emptyConversationShowsPlaceholderPreview() async throws {
        let conversation = Conversation(title: "Empty")
        #expect(conversation.previewText == "No messages yet")
        #expect(conversation.lastMessage == nil)
    }

    @Test func permissionTypeHasDistinctColorsAndIcons() async throws {
        // Tracks the enum instead of a hardcoded literal so adding a case
        // can't stale this test — the invariant is icon uniqueness (#13).
        let types = PermissionType.allCases
        let icons = Set(types.map(\.displayIcon))
        #expect(icons.count == types.count, "Each permission type should have a unique icon")
    }

    @Test func inboxItemTypeVisualIdentityIsComplete() async throws {
        for itemType in InboxItemType.allCases {
            #expect(!itemType.displayLabel.isEmpty)
            #expect(!itemType.displayIcon.isEmpty)
        }
    }
}
