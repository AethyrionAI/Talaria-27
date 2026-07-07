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
}
