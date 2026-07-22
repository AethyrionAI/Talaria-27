import Foundation
import Testing
@testable import Talaria

/// #156d D5 — wire-shape tolerance for the Insights fetch: the row decode
/// (id required, everything else degrades), the flat-sibling usage read
/// through the ONE existing `SessionUsage` decoder, and the page envelope's
/// row-skip + `has_more` posture.
struct SessionStatsDecodingTests {

    private func decodePage(_ json: String) throws -> SessionStatsPage {
        try JSONDecoder().decode(SessionStatsPage.self, from: Data(json.utf8))
    }

    @Test func fullRowDecodesEveryField() throws {
        let page = try decodePage("""
        {"object": "list", "has_more": false, "limit": 200, "offset": 0, "data": [{
            "id": "sess-abc123",
            "title": "Relay probe",
            "model": "claude-sonnet-5",
            "source": "api_server",
            "started_at": 1752000000,
            "ended_at": 1752000180,
            "last_active": 1752000180,
            "message_count": 12,
            "input_tokens": 66400,
            "output_tokens": 1200,
            "cache_read_tokens": 500,
            "cache_write_tokens": 250,
            "reasoning_tokens": 90,
            "api_call_count": 5,
            "tool_call_count": 7,
            "estimated_cost_usd": 0.42,
            "actual_cost_usd": null,
            "parent_session_id": null
        }]}
        """)
        try #require(page.rows.count == 1)
        let row = page.rows[0]
        #expect(row.id == "sess-abc123")
        #expect(row.title == "Relay probe")
        #expect(row.model == "claude-sonnet-5")
        #expect(row.source == "api_server")
        #expect(row.startedAt == Date(timeIntervalSince1970: 1_752_000_000))
        #expect(row.endedAt == Date(timeIntervalSince1970: 1_752_000_180))
        #expect(row.lastActive == Date(timeIntervalSince1970: 1_752_000_180))
        #expect(row.messageCount == 12)
        #expect(row.usage?.inputTokens == 66_400)
        #expect(row.usage?.outputTokens == 1_200)
        #expect(row.usage?.cacheReadTokens == 500)
        #expect(row.usage?.cacheWriteTokens == 250)
        #expect(row.usage?.reasoningTokens == 90)
        #expect(row.usage?.apiCallCount == 5)
        #expect(row.usage?.toolCallCount == 7)
        #expect(row.usage?.estimatedCostUSD == 0.42)
        #expect(row.usage?.actualCostUSD == nil)
        #expect(page.hasMore == false)
        #expect(page.skippedRowCount == 0)
    }

    /// The honest-absence rule at the decode layer: no usage key on the row
    /// → `usage` is nil, never an all-zero struct.
    @Test func rowWithoutUsageKeysDecodesNilUsage() throws {
        let page = try decodePage("""
        {"has_more": false, "data": [{"id": "sess-1", "title": "Sparse", "message_count": 3}]}
        """)
        try #require(page.rows.count == 1)
        #expect(page.rows[0].usage == nil)
        #expect(page.rows[0].messageCount == 3)
    }

    @Test func idLessAndBlankIdRowsAreSkippedNotFatal() throws {
        let page = try decodePage("""
        {"has_more": false, "data": [
            {"title": "No id at all"},
            {"id": "   ", "title": "Blank id"},
            {"id": "sess-keep", "title": "Kept"}
        ]}
        """)
        #expect(page.rows.map(\.id) == ["sess-keep"])
        #expect(page.skippedRowCount == 2)
    }

    @Test func wrongTypedFieldsDegradeToNilNotThrow() throws {
        let page = try decodePage("""
        {"has_more": false, "data": [{
            "id": "sess-odd",
            "title": 42,
            "model": ["not", "a", "string"],
            "started_at": "not-an-epoch",
            "message_count": "twelve",
            "input_tokens": 100
        }]}
        """)
        try #require(page.rows.count == 1)
        let row = page.rows[0]
        #expect(row.title == nil)
        #expect(row.model == nil)
        #expect(row.startedAt == nil)
        #expect(row.messageCount == nil)
        // The tolerable field still lands.
        #expect(row.usage?.inputTokens == 100)
    }

    /// A missing or malformed `has_more` reads as false — the crawl stops
    /// rather than looping on a shape it doesn't understand.
    @Test func missingOrMalformedHasMoreReadsFalse() throws {
        let missing = try decodePage("""
        {"data": [{"id": "sess-1"}]}
        """)
        #expect(missing.hasMore == false)

        let malformed = try decodePage("""
        {"has_more": "yes", "data": [{"id": "sess-1"}]}
        """)
        #expect(malformed.hasMore == false)
    }

    @Test func hasMoreTrueDecodes() throws {
        let page = try decodePage("""
        {"has_more": true, "data": [{"id": "sess-1"}]}
        """)
        #expect(page.hasMore == true)
    }

    @Test func emptyDataDecodesEmptyPage() throws {
        let page = try decodePage("""
        {"object": "list", "has_more": false, "data": []}
        """)
        #expect(page.rows.isEmpty)
        #expect(page.skippedRowCount == 0)
    }

    // MARK: - Derived row fields

    @Test func durationRequiresOrderedEnds() {
        let start = Date(timeIntervalSince1970: 1_752_000_000)
        let end = Date(timeIntervalSince1970: 1_752_000_180)
        #expect(SessionStatsRow(id: "a", startedAt: start, endedAt: end).duration == 180)
        #expect(SessionStatsRow(id: "b", startedAt: start, endedAt: nil).duration == nil)
        #expect(SessionStatsRow(id: "c", startedAt: nil, endedAt: end).duration == nil)
        // Clock skew (end before start) shows nothing, not a negative span.
        #expect(SessionStatsRow(id: "d", startedAt: end, endedAt: start).duration == nil)
    }

    @Test func recencyPrefersLastActiveThenEndThenStart() {
        let start = Date(timeIntervalSince1970: 1)
        let end = Date(timeIntervalSince1970: 2)
        let active = Date(timeIntervalSince1970: 3)
        #expect(SessionStatsRow(id: "a", startedAt: start, endedAt: end, lastActive: active).recency == active)
        #expect(SessionStatsRow(id: "b", startedAt: start, endedAt: end).recency == end)
        #expect(SessionStatsRow(id: "c", startedAt: start).recency == start)
        #expect(SessionStatsRow(id: "d").recency == nil)
    }

    @Test func displayTitleFallsBackToIdPrefix() {
        #expect(SessionStatsRow(id: "abcdef1234567890", title: "Named").displayTitle == "Named")
        #expect(SessionStatsRow(id: "abcdef1234567890", title: "  ").displayTitle == "abcdef12")
        #expect(SessionStatsRow(id: "short", title: nil).displayTitle == "short")
    }
}
