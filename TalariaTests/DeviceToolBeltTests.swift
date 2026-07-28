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
        // 176C Part 2: the armed branch no longer enumerates the belt in
        // prose — tool-awareness shows as the scoped use-tools sentence.
        let armed = LocalChatBackend.instructionsText(deviceContext: "Device: test.", hasTools: true)
        #expect(armed.contains("Use the tools for the user's own data"))
        #expect(armed.contains("never invent a value"))
    }

    @Test func instructionsCarryNoToolRosterRegardlessOfVision() {
        // 176C Part 2 (#194): the prose belt roster was the convicted
        // creative suppressor — the tools' native `Tool.description` metadata
        // is now the ONLY enumeration, so the instructions can never claim a
        // tool this session wasn't given. The #176/#148 vision gate lives
        // structurally in `DeviceToolBelt.offeredTools` (tested below), not
        // in prose.
        let seeing = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true, hasImageTools: true
        )
        let blind = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", hasTools: true, hasImageTools: false
        )
        for text in [seeing, blind] {
            #expect(!text.contains("image text/barcode reading"))
            #expect(!text.contains("You also have device tools"))
            // The kept sentences still stand.
            #expect(text.contains("the user's own data"))
            #expect(text.contains("never invent a value"))
        }
    }

    // MARK: Belt-truth instructions (#176B / #194)

    @Test func armedInstructionsLicenseAnsweringAndCreatingWithoutATool() {
        // The tool-LESS branch always authorized "say so plainly instead of
        // guessing"; the armed branch had no answering clause at all, and the
        // device read the belt as a job description — "write a poem" deflected
        // to reminders/weather (#194). The license must come with the belt.
        let armed = LocalChatBackend.instructionsText(deviceContext: "Device: test.", hasTools: true)
        #expect(armed.contains("need no tool"))
        #expect(armed.contains("facts you know are not guesses"))
        // Generation, not only recall (#194): creative work is first-class.
        #expect(armed.contains("writing and composing"))
        #expect(armed.contains("summarizing"))
        // "Use tools instead of guessing" is scoped to device data, not the world.
        #expect(armed.contains("the user's own data"))
        #expect(armed.contains("general knowledge is not device data"))
    }

    @Test func armedInstructionsCarryTheRecoveryClause() {
        // The absorbing state (#176B): one permission denial became every
        // later turn's answer. A failed tool is information about the tool.
        let armed = LocalChatBackend.instructionsText(deviceContext: "Device: test.", hasTools: true)
        #expect(armed.contains("never the answer"))
        #expect(armed.contains("repeat a denial"))
        // The honesty half stays: recovery must not license invention.
        #expect(armed.contains("never invent a value"))
    }

    // MARK: Session-shape instrument (#196, reworked from #194/176C)

    /// A fixed date so the two texts under comparison can never straddle a
    /// day boundary mid-test.
    private static let shapeDate = Date(timeIntervalSince1970: 1_753_600_000)

    @Test func armedDirectVariantAddsOnlyTheDirectnessSentence() {
        let armed = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", date: Self.shapeDate, hasTools: true
        )
        let direct = LocalChatBackend.instructionsText(
            for: .armedDirect, deviceContext: "Device: test.",
            date: Self.shapeDate, hasTools: true
        )
        // The anti-preface sentence is whole and in the cell only —
        // production armed is the control and must not carry it. (Part 2
        // flips exactly this pin if the device A/B clears armed-direct.)
        #expect(!armed.contains("never begin a reply"))
        #expect(direct.contains("Answer directly — never begin a reply by saying you can't do something you are then going to do."))
        // Placed with the licensing clause: the insertion took exactly one
        // sentence and neither neighbor moved.
        #expect(direct.contains("general knowledge is not device data. Answer directly"))
        #expect(direct.contains("going to do. Use the tools for the user's own data"))
        // Every production sentence survives (#176/#194 hard constraints):
        #expect(direct.contains("need no tool"))                 // licensing
        #expect(direct.contains("writing and composing"))        // licensing (#194)
        #expect(direct.contains("confirmation card first"))      // action confirmation
        #expect(direct.contains("never invent a value"))         // honesty
        #expect(direct.contains("never the answer"))             // recovery
        #expect(direct.contains("repeat a denial"))              // recovery
    }

    @Test func noNegVariantDropsOnlyTheHonestyAndRecoveryClauses() {
        // The thermometer cell (#196): production minus the negative-flavored
        // clauses suspected of priming "can't" prefaces. NEVER shippable —
        // without them a denied permission is again free to become every
        // later turn's answer (#176's absorbing state).
        let noNeg = LocalChatBackend.instructionsText(
            for: .armedNoNeg, deviceContext: "Device: test.",
            date: Self.shapeDate, hasTools: true
        )
        // Both clauses gone — honesty and recovery, all their anchors.
        #expect(!noNeg.contains("relay that honestly"))
        #expect(!noNeg.contains("never invent a value"))
        #expect(!noNeg.contains("never the answer"))
        #expect(!noNeg.contains("repeat a denial"))
        // The removal took exactly the tail after the action-confirmation
        // sentence — nothing else moved.
        #expect(noNeg.hasSuffix("if they decline, accept it gracefully."))
        // The kept sentences survive:
        #expect(noNeg.contains("need no tool"))                  // licensing
        #expect(noNeg.contains("writing and composing"))         // licensing (#194)
        #expect(noNeg.contains("the user's own data"))           // scoped use-tools
        #expect(noNeg.contains("confirmation card first"))       // action confirmation
    }

    @Test func armedShapeIsProductionVerbatimAndToollessIsTheBareBranch() {
        for hasImageTools in [false, true] {
            let production = LocalChatBackend.instructionsText(
                deviceContext: "Device: test.", date: Self.shapeDate,
                hasTools: true, hasImageTools: hasImageTools
            )
            let control = LocalChatBackend.instructionsText(
                for: .armed, deviceContext: "Device: test.",
                date: Self.shapeDate, hasTools: true, hasImageTools: hasImageTools
            )
            #expect(control == production)
        }
        let bare = LocalChatBackend.instructionsText(
            deviceContext: "Device: test.", date: Self.shapeDate, hasTools: false
        )
        let farControl = LocalChatBackend.instructionsText(
            for: .toolless, deviceContext: "Device: test.",
            date: Self.shapeDate, hasTools: true
        )
        #expect(farControl == bare)
    }

    @Test func sessionShapeCellsParseFromLaunchEnvValuesAndGateTools() {
        // The four spellings, exactly as the desk A/B checklist uses them.
        #expect(LocalChatBackend.SessionShape(rawValue: "armed") == .armed)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-direct") == .armedDirect)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-noneg") == .armedNoNeg)
        #expect(LocalChatBackend.SessionShape(rawValue: "toolless") == .toolless)
        // Unknown values must fall back to production, never crash or guess —
        // including the RETIRED 176C cell names a phone may still carry in
        // the persisted Diagnostics override from the last A/B.
        #expect(LocalChatBackend.SessionShape(rawValue: "bogus") == nil)
        #expect(LocalChatBackend.SessionShape(rawValue: "armed-noprose") == nil)
        #expect(LocalChatBackend.SessionShape(rawValue: "prose-notools") == nil)
        // Which cells hand the session a belt at all.
        #expect(LocalChatBackend.SessionShape.armed.registersTools)
        #expect(LocalChatBackend.SessionShape.armedDirect.registersTools)
        #expect(LocalChatBackend.SessionShape.armedNoNeg.registersTools)
        #expect(!LocalChatBackend.SessionShape.toolless.registersTools)
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

    @Test @MainActor func conversationSearchDescriptionStatesWhenItApplies() {
        // #176B Part B: the selector searched the literal string "2+2"
        // because the old description read like a general memory tool. The
        // corrected text follows the #148 pattern — when it applies (finding
        // a specific past mention), and that the recent thread needs no tool.
        let search = ConversationSearchTool(
            relay: ToolEventRelay(),
            conversationProvider: { nil },
            sessionCacheProvider: { [] },
            spotlightEnabledProvider: { false }
        )
        #expect(search.description.localizedCaseInsensitiveContains("only"))
        #expect(search.description.localizedCaseInsensitiveContains("past"))
        #expect(search.description.contains("without any tool"))
    }
}
