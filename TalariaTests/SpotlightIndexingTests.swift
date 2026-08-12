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

    /// The gate: a disabled toggle records NOTHING, whatever it is offered.
    ///
    /// **#332-b (2026-08-12).** This used to assert
    /// `service.sessionEntities.isEmpty` — global index emptiness as a stand-in
    /// for the gate holding. That is true on a fresh simulator and false on a
    /// phone anyone has used: the service rehydrates its session cache from
    /// `UserDefaults` in `init`, and a device log from the first device suite
    /// run read `donated 108 session entities`. Real system state bled into the
    /// precondition and red-ed a passing gate.
    ///
    /// So assert the gate's BEHAVIOUR instead — a delta, not an absolute. The
    /// offered id is unique per run, so no pre-existing donation can satisfy or
    /// defeat the check: with the gate holding, that id is absent afterwards and
    /// the donated set is byte-for-byte the one we found; if the gate stops
    /// gating, the id appears and the set moves, on a clean simulator and on a
    /// phone with 108 donations alike.
    ///
    /// Deliberately NOT done: clearing the cache first to manufacture the empty
    /// world the old assertion wanted. The test host IS the app, so on a device
    /// that would delete the owner's real donations to make a test convenient.
    @Test @MainActor
    func donationIsGatedByTheToggle() async throws {
        let service = SpotlightIndexingService()
        service.isEnabled = { false }

        let before = Set(service.sessionEntities.keys)
        // Printed so a DEVICE run evidences its own precondition instead of it
        // being inferred: bar 332-b(1) is "green on a device with pre-existing
        // donations", and only this number says whether the run exercised a
        // dirty index or an empty one. On a fresh simulator it reads 0, which
        // is honest rather than a failure — the delta below is what is scored.
        print("#332-b PRE-EXISTING DONATED SESSION ENTITIES ON THIS HOST: \(before.count)")
        let offeredID = "gate-probe-\(UUID().uuidString)"
        #expect(!before.contains(offeredID),
                "the probe id must not already be donated, or this check proves nothing")

        service.donateSessions([
            HermesSessionInfo(id: offeredID, title: "T", preview: nil, model: nil,
                              source: nil, messageCount: 1, lastActive: nil, isActive: true),
        ])

        #expect(service.sessionEntities[offeredID] == nil,
                "disabled toggle must block donation entirely — the offered session was recorded anyway")
        #expect(Set(service.sessionEntities.keys) == before,
                "a disabled toggle must leave the donated set exactly as it found it")
    }

    @Test func spotlightIndexingDefaultsOff() async throws {
        #expect(UserSettings().spotlightIndexingEnabled == false)

        // A pre-#17 persisted settings blob (no key) must also decode to OFF.
        let decoded = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        #expect(decoded.spotlightIndexingEnabled == false)
    }
}
