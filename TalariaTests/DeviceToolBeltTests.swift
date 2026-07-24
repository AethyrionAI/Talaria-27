import Foundation
import Testing
@testable import Talaria

/// #28 — the deterministic layer of the device tool belt: shared formatting,
/// snippet extraction, and the conversation-search report assembly. The
/// framework-facing tool calls (HealthKit, EventKit, WeatherKit, Vision, …)
/// need entitlements + permissions and are device-verified, not unit-tested.
struct DeviceToolBeltTests {

    // MARK: Formatting

    @Test func hoursMinutesFormatsFractionalHours() {
        #expect(DeviceToolFormat.hoursMinutes(fromHours: 7.4) == "7h 24m")
        #expect(DeviceToolFormat.hoursMinutes(fromHours: 8.0) == "8h")
        #expect(DeviceToolFormat.hoursMinutes(fromHours: 0.5) == "30m")
    }

    @Test func storageLineHandlesMissingValues() {
        #expect(DeviceToolFormat.storageLine(availableBytes: nil, totalBytes: nil) == "Storage: unknown free")
        let line = DeviceToolFormat.storageLine(availableBytes: 1_000_000, totalBytes: nil)
        #expect(line.hasPrefix("Storage: "))
        #expect(line.hasSuffix(" free"))
        let full = DeviceToolFormat.storageLine(availableBytes: 1_000_000, totalBytes: 128_000_000_000)
        #expect(full.contains(" free of "))
    }

    // MARK: Snippets

    @Test func snippetFindsCaseInsensitiveMatchWithEllipses() {
        let text = String(repeating: "x", count: 200) + " the TAILSCALE setup steps " + String(repeating: "y", count: 200)
        let snippet = DeviceToolFormat.snippet(around: "tailscale", in: text)
        #expect(snippet != nil)
        #expect(snippet!.localizedCaseInsensitiveContains("tailscale"))
        #expect(snippet!.hasPrefix("…"))
        #expect(snippet!.hasSuffix("…"))
    }

    @Test func snippetReturnsNilWhenTermAbsent() {
        #expect(DeviceToolFormat.snippet(around: "missing", in: "nothing to see here") == nil)
    }

    @Test func snippetFlattensNewlines() {
        let snippet = DeviceToolFormat.snippet(around: "middle", in: "line one\nthe middle line\nline three")
        #expect(snippet?.contains("\n") == false)
    }

    // MARK: Conversation search report

    private func conversation(withMessages contents: [(MessageSender, String)]) -> Conversation {
        Conversation(
            title: "Test",
            messages: contents.map { Message(sender: $0.0, content: $0.1, status: .delivered) }
        )
    }

    @Test func reportFindsHitsInCurrentConversation() {
        let convo = conversation(withMessages: [
            (.user, "How do I configure Tailscale on the Mac Mini?"),
            (.hermes, "Install Tailscale from the App Store, then sign in."),
            (.system, "Tailscale system banner — must not surface"),
        ])
        let report = ConversationSearchTool.report(
            term: "tailscale", conversation: convo, sessions: [], spotlightEnabled: true
        )
        #expect(report.contains("current conversation"))
        #expect(report.contains("You:"))
        #expect(report.contains("Hermes:"))
        #expect(!report.contains("system banner"))
    }

    @Test func reportSearchesSessionCacheTitlesAndPreviews() {
        let sessions = [
            ConversationSearchTool.CachedSession(id: "a", title: "Reverse proxy setup", preview: "Caddy on the home lab"),
            ConversationSearchTool.CachedSession(id: "b", title: "Trip planning", preview: nil),
        ]
        let report = ConversationSearchTool.report(
            term: "caddy", conversation: nil, sessions: sessions, spotlightEnabled: true
        )
        #expect(report.contains("Reverse proxy setup"))
        #expect(!report.contains("Trip planning"))
    }

    @Test func reportIsHonestWhenNothingMatches() {
        let report = ConversationSearchTool.report(
            term: "nonexistent", conversation: nil, sessions: [], spotlightEnabled: true
        )
        #expect(report.contains("No matches"))
    }

    @Test func reportSaysWhenIndexingIsOff() {
        // With indexing off, past sessions genuinely weren't searchable —
        // the report must say so instead of implying full coverage.
        let convo = conversation(withMessages: [(.user, "find the caddy notes")])
        let withHit = ConversationSearchTool.report(
            term: "caddy", conversation: convo, sessions: [], spotlightEnabled: false
        )
        #expect(withHit.contains("indexing is off"))
        let noHit = ConversationSearchTool.report(
            term: "zzz", conversation: nil, sessions: [], spotlightEnabled: false
        )
        #expect(noHit.contains("indexing is off"))
    }

    // MARK: Tool-aware instructions (#26 → #28)

    @Test func instructionsMentionToolsOnlyWhenInstalled() {
        let bare = LocalChatBackend.instructionsText(deviceContext: "Device: test.", hasTools: false)
        #expect(bare.contains("no external tools"))
        let armed = LocalChatBackend.instructionsText(deviceContext: "Device: test.", hasTools: true)
        #expect(armed.contains("device tools"))
        #expect(armed.contains("never invent a value"))
    }

    @Test func instructionsAdvertiseImageToolsOnlyWhenTheyAreOffered() {
        // #176: the belt withholds the vision tools when there's no image, so
        // the persona must stop claiming it can read one — otherwise the
        // instructions advertise a tool this session was never given.
        let seeing = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true, hasImageTools: true
        )
        #expect(seeing.contains("image text/barcode reading"))

        let blind = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true, hasImageTools: false
        )
        #expect(!blind.contains("image text/barcode reading"))
        // The rest of the belt is still advertised — only the vision claim goes.
        #expect(blind.contains("device tools"))
        #expect(blind.contains("conversation search"))
        #expect(blind.contains("never invent a value"))
    }

    // MARK: Vision-tool availability gating (#176)

    /// The SHIPPING read belt, filtered the way `LocalChatBackend` filters it.
    /// Deliberately the real `makeReadTools` output rather than a stand-in —
    /// the gate is only worth anything if it acts on what actually ships.
    /// Every tool's framework store (HealthKit, EventKit, Contacts) is
    /// constructed inside `call()`, so assembling the belt is inert here.
    @MainActor
    private func offeredNames(hasImageInContext: Bool) -> [String] {
        let belt = DeviceToolBelt.makeReadTools(
            relay: ToolEventRelay(),
            conversationProvider: { nil },
            sessionCacheProvider: { [] },
            spotlightEnabledProvider: { false }
        )
        return DeviceToolBelt.offeredTools(from: belt, hasImageInContext: hasImageInContext).map(\.name)
    }

    @Test @MainActor func visionToolsAreWithheldWhenNoImageIsInContext() {
        // The structural half of #176: the model cannot pick what it is not
        // given. A haiku prompt is never offered an OCR tool.
        let offered = offeredNames(hasImageInContext: false)
        #expect(!offered.contains("readImageText"))
        #expect(!offered.contains("readBarcode"))
    }

    @Test @MainActor func visionToolsAreOfferedWhenAnImageIsInContext() {
        let offered = offeredNames(hasImageInContext: true)
        #expect(offered.contains("readImageText"))
        #expect(offered.contains("readBarcode"))
    }

    @Test @MainActor func gatingRemovesOnlyTheVisionToolsAndPreservesBeltOrder() {
        // #176 narrows selection; it does not redesign the belt. The 4-call
        // health/motion turn that prompted the item was APPROPRIATE — every
        // non-vision tool must survive the gate untouched, in place.
        let armed = offeredNames(hasImageInContext: true)
        let gated = offeredNames(hasImageInContext: false)
        #expect(gated == armed.filter { $0 != "readImageText" && $0 != "readBarcode" })
        #expect(gated.count == armed.count - 2)
        for survivor in ["readHealth", "readMotion", "currentLocation", "searchConversations"] {
            #expect(gated.contains(survivor))
        }
    }

    @Test @MainActor func everyOfferedToolKeepsItsNameAndDescription() {
        // Description tightening must not cost a tool its schema surface —
        // the belt still serializes with or without the gate.
        for hasImage in [true, false] {
            let belt = DeviceToolBelt.makeReadTools(
                relay: ToolEventRelay(),
                conversationProvider: { nil },
                sessionCacheProvider: { [] },
                spotlightEnabledProvider: { false }
            )
            for tool in DeviceToolBelt.offeredTools(from: belt, hasImageInContext: hasImage) {
                #expect(!tool.name.isEmpty)
                #expect(!tool.description.isEmpty)
            }
        }
    }

    // MARK: Image presence (#176)

    private func imageAttachment(
        thumbnailBase64: String? = nil,
        localStoragePath: String? = nil
    ) -> MessageAttachment {
        MessageAttachment(
            kind: "image",
            fileName: "shot.png",
            mimeType: "image/png",
            thumbnailBase64: thumbnailBase64,
            localStoragePath: localStoragePath
        )
    }

    @Test @MainActor func hasImageIsFalseForATextOnlyConversation() {
        let convo = conversation(withMessages: [(.user, "Write a haiku about rain.")])
        #expect(!ConversationImageSource.hasImage(in: convo))
    }

    @Test @MainActor func hasImageIsFalseForNilConversation() {
        #expect(!ConversationImageSource.hasImage(in: nil))
    }

    @Test @MainActor func hasImageSeesAThumbnailBackedAttachment() {
        var convo = conversation(withMessages: [(.user, "what does this say?")])
        convo.messages[0].attachments = [imageAttachment(thumbnailBase64: "Zm9v")]
        #expect(ConversationImageSource.hasImage(in: convo))
    }

    @Test @MainActor func hasImageSeesAnAttachmentWhoseBytesAreStillOnDisk() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("t27-176-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        var convo = conversation(withMessages: [(.user, "read this")])
        convo.messages[0].attachments = [imageAttachment(localStoragePath: url.path)]
        #expect(ConversationImageSource.hasImage(in: convo))
    }

    @Test @MainActor func hasImageIsFalseWhenTheImageBytesAreGone() {
        // A staged image whose file was reaped leaves a record but nothing to
        // read — offering OCR for it buys the model a dead end.
        var convo = conversation(withMessages: [(.user, "read this")])
        convo.messages[0].attachments = [
            imageAttachment(localStoragePath: "/var/tmp/t27-176-definitely-not-here.png")
        ]
        #expect(!ConversationImageSource.hasImage(in: convo))
    }

    @Test @MainActor func hasImageIgnoresNonImageAttachments() {
        var convo = conversation(withMessages: [(.user, "here are my notes")])
        convo.messages[0].attachments = [
            MessageAttachment(
                kind: "file",
                fileName: "notes.txt",
                mimeType: "text/plain",
                thumbnailBase64: "Zm9v",
                localStoragePath: nil
            )
        ]
        #expect(!ConversationImageSource.hasImage(in: convo))
    }

    @Test @MainActor func hasImageSeesTheIncomingTurnBeforeItLandsInHistory() {
        // The ordering trap this gate has to clear: every send path prepares
        // the session BEFORE appending the user turn, so a gate reading only
        // stored history would withhold OCR on the exact turn that attaches
        // the image — the tool's primary use case.
        let pending = PendingAttachment(
            kind: .image,
            fileName: "receipt.jpg",
            mimeType: "image/jpeg",
            data: Data([0xFF, 0xD8]),
            localStoragePath: nil,
            thumbnailData: nil
        )
        #expect(ConversationImageSource.hasImage(in: nil, incoming: [pending]))
        #expect(!ConversationImageSource.hasImage(in: nil, incoming: []))
    }

    @Test @MainActor func hasImageIgnoresIncomingNonImageAttachments() {
        let pending = PendingAttachment(
            kind: .file,
            fileName: "notes.txt",
            mimeType: "text/plain",
            data: Data("hello".utf8),
            localStoragePath: nil,
            thumbnailData: nil
        )
        #expect(!ConversationImageSource.hasImage(in: nil, incoming: [pending]))
    }

    // MARK: Vision-tool descriptions (#176)

    @Test @MainActor func visionToolDescriptionsStateWhenTheyApply() {
        // Gating covers "no image anywhere". This covers the other half: an
        // image from twenty turns ago keeps the tools offered, so each one
        // has to say what it is FOR, not just what it does.
        let ocr = ImageTextTool(relay: ToolEventRelay(), conversationProvider: { nil })
        #expect(ocr.description.localizedCaseInsensitiveContains("only"))
        let barcode = BarcodeReaderTool(relay: ToolEventRelay(), conversationProvider: { nil })
        #expect(barcode.description.localizedCaseInsensitiveContains("only"))
    }
}
