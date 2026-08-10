import Foundation
import Testing
@testable import Talaria

/// #132 — THE CAPTION-LESS IMAGE FLOOR. Bars 132-A..E; see `OPEN_ITEMS.md` #132
/// (bars written before the code) and `dispatch/OPUS-T27-132-caption-less-image-floor.md`.
///
/// A caption-less image turn used to ship a lone `image_url` part with **zero
/// instruction** — the model received an image and no statement of what the user
/// wanted, which is why the host mints `[attachment]`/`[screenshot]` placeholders
/// of its own. The floor is one neutral, factual sentence stating what was sent.
///
/// **Wire-only.** It is injected at ENCODE time inside `AttachmentInlining.assemble`
/// — never into the stored `Message`, never rendered in the transcript (132-E).
/// Both host planes (`ChatTurnBody`, sessions; `RunsTurnBody`, runs) reach it
/// because both call `assemble`, which is also where the budget arithmetic lives,
/// so the floor's bytes are CHARGED rather than free (132-B).
///
/// The floor sentences below are written as LITERALS on purpose. Pinning them
/// against `AttachmentInlining.captionLessImageFloor` would be circular; this
/// wording is text every paired-host conversation silently carries, so a change
/// to it must trip a test and get a deliberate read.
struct CaptionLessImageFloorTests {

    // MARK: - The pinned wording

    /// The exact sentence for one image. Any edit here is a product decision.
    static let floorOneImage =
        "[Talaria: the user attached 1 image with no caption — examine it and respond to what it shows.]"

    /// Plural form. `N images` / `examine them` / `what they show`.
    static func floorImages(_ count: Int) -> String {
        "[Talaria: the user attached \(count) images with no caption — examine them and respond to what they show.]"
    }

    // MARK: - Fixtures

    private func image(named fileName: String = "photo.jpg", byteCount: Int = 64) -> PendingAttachment {
        PendingAttachment(
            kind: .image,
            fileName: fileName,
            mimeType: "image/jpeg",
            data: Data(repeating: 0xAB, count: byteCount),
            localStoragePath: nil,
            thumbnailData: nil
        )
    }

    private func textFile(named fileName: String = "notes.md", content: String = "alpha") -> PendingAttachment {
        PendingAttachment(
            kind: .file,
            fileName: fileName,
            mimeType: "text/markdown",
            data: Data(content.utf8),
            localStoragePath: nil,
            thumbnailData: nil
        )
    }

    private func encode(_ body: SessionsHermesClient.ChatTurnBody) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func encode(_ body: SessionsHermesClient.RunsTurnBody) throws -> [String: Any] {
        let data = try JSONEncoder().encode(body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Text values of every `{type:"text"}` part in an encoded parts array.
    private func textParts(_ parts: [[String: Any]]) -> [String] {
        parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
    }

    // MARK: - 132-A — sessions plane (RED first)

    @Test
    func captionLessSingleImageCarriesTheFloorOnTheSessionsPlane() throws {
        let body = SessionsHermesClient.ChatTurnBody.make(
            message: "",
            attachments: [image()],
            selection: nil
        )
        let parts = try #require(try encode(body)["input"] as? [[String: Any]],
                                 "a caption-less image turn must encode as a parts array")

        // The image still rides…
        #expect(parts.contains { $0["type"] as? String == "image_url" })
        // …and it is no longer alone: the floor states what was sent.
        #expect(textParts(parts) == [Self.floorOneImage])
        // Floor leads, image follows — the same shape a captioned turn has.
        // `#require` on the count, not `#expect`: without the floor there is
        // only ONE part, and a bare `parts[1]` would trap on index-out-of-range
        // and abort the whole suite instead of reporting a failure.
        try #require(parts.count == 2)
        #expect(parts[0]["type"] as? String == "text")
        #expect(parts[1]["type"] as? String == "image_url")
    }

    // MARK: - 132-B — runs plane, and the floor is CHARGED to the budget

    @Test
    func captionLessSingleImageCarriesTheFloorOnTheRunsPlane() throws {
        let body = SessionsHermesClient.RunsTurnBody.make(
            message: "",
            attachments: [image()],
            sessionID: "sess-132",
            history: [],
            selection: nil
        )
        // The runs plane wraps parts in a single user message (#283 slice 3A).
        let input = try #require(try encode(body)["input"] as? [[String: Any]])
        #expect(input.count == 1)
        let parts = try #require(input[0]["content"] as? [[String: Any]])

        #expect(parts.contains { $0["type"] as? String == "image_url" })
        #expect(textParts(parts) == [Self.floorOneImage])
    }

    /// The floor's bytes come OUT of the existing aggregate attachment budget —
    /// they do not ride on top of it (#290's uncounted-history lesson).
    ///
    /// Both planes assemble through `AttachmentInlining`, so charging it here
    /// charges it for both. Two images are sized to fit the raw budget exactly
    /// but NOT once the floor is charged; the captioned control below transmits
    /// the identical pair, which is what proves the omission comes from the
    /// floor's bytes rather than from the sizing.
    @Test
    func floorBytesAreChargedAgainstTheAttachmentBudget() throws {
        let budget = AttachmentInlining.aggregateAttachmentBudget
        let floorBytes = Self.floorImages(2).utf8.count

        // A data URL costs "data:image/jpeg;base64," (23) + 4*ceil(n/3).
        func dataURLCost(rawBytes: Int) -> Int { 23 + 4 * ((rawBytes + 2) / 3) }

        let rawA = 300 * 1024 - (300 * 1024) % 3          // divisible by 3
        let costA = dataURLCost(rawBytes: rawA)
        // Largest B that still lets the PAIR fit the raw budget.
        let rawB = 3 * ((budget - costA - 23) / 4)
        let costB = dataURLCost(rawBytes: rawB)

        // Preconditions for the knife edge — assert them, don't assume them.
        #expect(costA + costB <= budget, "the pair must fit the budget when the floor is free")
        #expect(costA + costB > budget - floorBytes, "the pair must NOT fit once the floor is charged")

        let captionLess = AttachmentInlining.assemble(
            message: "",
            attachments: [image(named: "first.jpg", byteCount: rawA),
                          image(named: "second.jpg", byteCount: rawB)]
        )
        // The floor is charged, so the second image no longer fits and ships
        // as an in-band omission stub instead of vanishing.
        #expect(captionLess.omittedForBudget == ["second.jpg"])

        // CONTROL: identical images, but a caption suppresses the floor — and
        // now the pair fits. Same bytes, different outcome ⇒ the floor was paid for.
        let captioned = AttachmentInlining.assemble(
            message: "what are these",
            attachments: [image(named: "first.jpg", byteCount: rawA),
                          image(named: "second.jpg", byteCount: rawB)]
        )
        #expect(captioned.omittedForBudget.isEmpty)
    }

    // MARK: - 132-C — a captioned turn is untouched

    @Test
    func captionedImageTurnIsUnchangedOnBothPlanes() throws {
        let chat = SessionsHermesClient.ChatTurnBody.make(
            message: "what is this",
            attachments: [image()],
            selection: nil
        )
        let chatParts = try #require(try encode(chat)["input"] as? [[String: Any]])
        // Exactly the pre-#132 shape: the user's own text, then the image.
        #expect(chatParts.count == 2)
        #expect(textParts(chatParts) == ["what is this"])
        #expect(chatParts[1]["type"] as? String == "image_url")

        let runs = SessionsHermesClient.RunsTurnBody.make(
            message: "what is this",
            attachments: [image()],
            sessionID: "s",
            history: [],
            selection: nil
        )
        let runsInput = try #require(try encode(runs)["input"] as? [[String: Any]])
        let runsParts = try #require(runsInput[0]["content"] as? [[String: Any]])
        #expect(runsParts.count == 2)
        #expect(textParts(runsParts) == ["what is this"])

        // No floor text anywhere in either encoded body.
        for body in [try encode(chat), try encode(runs)] {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
            #expect(!json.contains("with no caption"))
        }
    }

    /// Whitespace-only text is not a caption — the floor still fires. (The
    /// composer trims, and `assemble` already treats blank text as absent.)
    @Test
    func whitespaceOnlyMessageStillGetsTheFloor() {
        let assembly = AttachmentInlining.assemble(message: "   \n ", attachments: [image()])
        #expect(assembly.parts.first == .text(Self.floorOneImage))
    }

    // MARK: - 132-D — the count, and no floor without images

    @Test
    func multiImageCountIsCorrect() {
        let assembly = AttachmentInlining.assemble(
            message: "",
            attachments: [image(named: "a.jpg"), image(named: "b.jpg"), image(named: "c.jpg")]
        )
        #expect(assembly.parts.first == .text(Self.floorImages(3)))
        // Floor + three images, staged order preserved after it.
        #expect(assembly.parts.count == 4)
    }

    @Test
    func textFileOnlyTurnGetsNoImageFloor() {
        let assembly = AttachmentInlining.assemble(message: "", attachments: [textFile()])
        #expect(assembly.parts.count == 1)
        guard case .text(let only) = assembly.parts[0] else {
            Issue.record("expected the delimited file part")
            return
        }
        #expect(only.hasPrefix("===== BEGIN FILE:"))
        #expect(!only.contains("with no caption"))
    }

    /// A mixed caption-less turn counts IMAGES only — the text file is already
    /// self-describing through its BEGIN/END frame.
    @Test
    func mixedTurnCountsImagesOnly() {
        let assembly = AttachmentInlining.assemble(
            message: "",
            attachments: [image(named: "a.jpg"), textFile(named: "b.md"), image(named: "c.jpg")]
        )
        #expect(assembly.parts.first == .text(Self.floorImages(2)))
    }

    /// A caption-less turn whose only attachment has NO wire representation
    /// gets no parts at all — and therefore no floor to describe nothing.
    @Test
    func untransmittableOnlyTurnGetsNoFloor() {
        let rawPDF = PendingAttachment(
            kind: .file,
            fileName: "report.pdf",
            mimeType: "application/pdf",
            data: Data(repeating: 0x25, count: 128),
            localStoragePath: nil,
            thumbnailData: nil
        )
        let assembly = AttachmentInlining.assemble(message: "", attachments: [rawPDF])
        #expect(assembly.parts.isEmpty)
    }

    // MARK: - 132-E — wire-only: the floor never reaches the store or the bubble

    /// Records what ChatStore hands the transport, so the test can encode the
    /// REAL production body from the REAL transport arguments.
    @MainActor
    private final class RecordingClient: HermesClientProtocol {
        var connectionStatus: ConnectionStatus = .connected
        var currentConversation: Conversation?
        private(set) var sentMessage: String?
        private(set) var sentAttachments: [PendingAttachment] = []

        func connect() async {}
        func disconnect() async {}

        func send(message: String, attachments: [PendingAttachment], clientMessageID: UUID) async -> Message {
            Message(sender: .hermes, content: "ok", status: .delivered)
        }

        func sendStreaming(
            message: String,
            attachments: [PendingAttachment],
            clientMessageID: UUID
        ) -> AsyncStream<StreamingUpdate> {
            sentMessage = message
            sentAttachments = attachments
            return AsyncStream { continuation in
                continuation.yield(.finished(
                    Message(sender: .hermes, content: "Done.", status: .delivered),
                    nil,
                    nil
                ))
                continuation.finish()
            }
        }

        func loadConversation() async -> Conversation {
            if let currentConversation { return currentConversation }
            let fresh = Conversation(title: "Hermes")
            currentConversation = fresh
            return fresh
        }

        func clearConversation() async throws -> Conversation {
            let fresh = Conversation(title: "Hermes")
            currentConversation = fresh
            return fresh
        }
    }

    @MainActor private func makePersistence() -> UserDefaultsAppPersistenceStore {
        let suiteName = "caption-less-floor-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return UserDefaultsAppPersistenceStore(defaults: defaults)
    }

    /// The transcript is unchanged: the stored user row keeps its local
    /// `[1 attachment]` display text and carries the floor in NO field, while
    /// the body built from the same transport arguments DOES carry it. The
    /// bubble renders the stored row, so it cannot show the floor.
    @Test @MainActor
    func floorRidesTheWireAndNeverTheStore() async throws {
        let client = RecordingClient()
        let chatStore = ChatStore(hermesClient: client, persistence: makePersistence())

        await chatStore.sendMessage("", attachments: [image()])

        // --- the STORE side ---
        let stored = try #require(chatStore.conversation?.messages.first)
        #expect(stored.sender == .user)
        // The pre-#132 local placeholder, untouched by this lane.
        #expect(stored.content == "[1 attachment]")
        #expect(!stored.content.contains("with no caption"))
        #expect(stored.reasoning?.contains("with no caption") != true)
        // Nothing anywhere in the persisted conversation mentions the floor.
        let storedJSON = String(
            decoding: try JSONEncoder().encode(try #require(chatStore.conversation)),
            as: UTF8.self
        )
        #expect(!storedJSON.contains("with no caption"))

        // --- the WIRE side, built by the production encoder from the exact
        //     arguments ChatStore handed the transport ---
        #expect(client.sentMessage == "", "the wire gets the trimmed (empty) text, not the display placeholder")
        let body = SessionsHermesClient.ChatTurnBody.make(
            message: try #require(client.sentMessage),
            attachments: client.sentAttachments,
            selection: nil
        )
        let wireJSON = String(decoding: try JSONEncoder().encode(body), as: UTF8.self)
        #expect(wireJSON.contains("with no caption"))
    }
}
