import Foundation
import Testing
@testable import Talaria

/// #17: the pure edges of Spotlight donation — entity mapping, agent-file
/// extraction, and the default-OFF privacy posture. Index writes themselves
/// are system-side and stay out of unit scope.
struct SpotlightIndexingTests {

    @Test func sessionEntityMapsHermesInfo() async throws {
        let info = HermesSessionInfo(
            id: "sess-42",
            title: "  Roadmap chat  ",
            preview: "Talked through Wave 4",
            model: "gpt-5.4-mini",
            source: nil,
            messageCount: 12,
            lastActive: Date(timeIntervalSince1970: 1_700_000_000),
            isActive: false
        )
        let entity = ChatSessionEntity(info: info)
        #expect(entity.id == "sess-42")
        #expect(entity.title == "Roadmap chat")
        #expect(entity.preview == "Talked through Wave 4")

        let untitled = ChatSessionEntity(info: HermesSessionInfo(
            id: "sess-43", title: "   ", preview: nil, model: nil,
            source: nil, messageCount: 0, lastActive: nil, isActive: false
        ))
        #expect(untitled.title == "Hermes Session", "blank titles fall back to a real label, not whitespace")
    }

    @Test func agentFilesComeOnlyFromHermesMessages() async throws {
        let agentFile = MessageAttachment(
            kind: "file", fileName: "notes.md", mimeType: "text/markdown",
            localStoragePath: "/tmp/staged/notes.md"
        )
        let userUpload = MessageAttachment(
            kind: "file", fileName: "mine.txt", mimeType: "text/plain",
            localStoragePath: "/tmp/staged/mine.txt"
        )
        let unstagedImage = MessageAttachment(kind: "image", fileName: "pic.png", mimeType: "image/png")

        let conversation = Conversation(title: "Test", messages: [
            Message(sender: .user, content: "here you go", attachments: [userUpload]),
            Message(sender: .hermes, content: "wrote it", attachments: [agentFile, unstagedImage]),
        ])

        let entities = SpotlightIndexingService.agentFileEntities(in: conversation)
        #expect(entities.count == 1)
        #expect(entities.first?.fileName == "notes.md")
        #expect(entities.first?.id == agentFile.id.uuidString)
        #expect(SpotlightIndexingService.agentFileEntities(in: nil).isEmpty)
    }

    @Test @MainActor
    func donationIsGatedByTheToggle() async throws {
        let service = SpotlightIndexingService()
        service.isEnabled = { false }
        service.donateSessions([
            HermesSessionInfo(id: "sess-1", title: "T", preview: nil, model: nil,
                              source: nil, messageCount: 1, lastActive: nil, isActive: true),
        ])
        #expect(service.sessionEntities.isEmpty, "disabled toggle must block donation entirely")
    }

    @Test func spotlightIndexingDefaultsOff() async throws {
        #expect(UserSettings().spotlightIndexingEnabled == false)

        // A pre-#17 persisted settings blob (no key) must also decode to OFF.
        let decoded = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        #expect(decoded.spotlightIndexingEnabled == false)
    }
}
