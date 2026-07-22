import Foundation
import Testing
@testable import Talaria

/// #156d D5 — the pagination loop against fixture pages: offsets walk in
/// page-size steps, the crawl stops the moment `has_more` goes false, the
/// page cap holds at 3, and only stopping with rows left unseen marks the
/// window truncated.
@MainActor
struct InsightsFetchTests {

    private func rows(_ ids: [String]) -> [SessionStatsRow] {
        ids.map { SessionStatsRow(id: $0) }
    }

    @Test func singlePageStopsWithoutTruncation() async throws {
        var requestedOffsets: [Int] = []
        let fetch = try await InsightsService.collectWindow { offset in
            requestedOffsets.append(offset)
            return SessionStatsPage(rows: self.rows(["a", "b"]), hasMore: false)
        }
        #expect(requestedOffsets == [0])
        #expect(fetch.rows.map(\.id) == ["a", "b"])
        #expect(!fetch.isTruncated)
    }

    @Test func hasMoreFalseOnSecondPageStopsEarly() async throws {
        var requestedOffsets: [Int] = []
        let fetch = try await InsightsService.collectWindow(pageSize: 2) { offset in
            requestedOffsets.append(offset)
            switch offset {
            case 0: return SessionStatsPage(rows: self.rows(["a", "b"]), hasMore: true)
            default: return SessionStatsPage(rows: self.rows(["c"]), hasMore: false)
            }
        }
        #expect(requestedOffsets == [0, 2])
        #expect(fetch.rows.map(\.id) == ["a", "b", "c"])
        #expect(!fetch.isTruncated)
    }

    /// The cap: three pages fetched, a fourth never requested, and the
    /// result admits the window was cut short.
    @Test func capsAtThreePagesAndMarksTruncated() async throws {
        var requestedOffsets: [Int] = []
        let fetch = try await InsightsService.collectWindow(pageSize: 2) { offset in
            requestedOffsets.append(offset)
            let start = offset
            return SessionStatsPage(
                rows: self.rows(["s\(start)", "s\(start + 1)"]),
                hasMore: true
            )
        }
        #expect(requestedOffsets == [0, 2, 4])
        #expect(fetch.rows.count == 6)
        #expect(fetch.isTruncated)
    }

    /// A server claiming more while sending nothing must not spin — one
    /// empty page ends the crawl, honestly marked truncated because rows
    /// were left unseen.
    @Test func emptyPageWithHasMoreStopsAndMarksTruncated() async throws {
        var requestedOffsets: [Int] = []
        let fetch = try await InsightsService.collectWindow(pageSize: 2) { offset in
            requestedOffsets.append(offset)
            switch offset {
            case 0: return SessionStatsPage(rows: self.rows(["a"]), hasMore: true)
            default: return SessionStatsPage(rows: [], hasMore: true)
            }
        }
        #expect(requestedOffsets == [0, 2])
        #expect(fetch.rows.map(\.id) == ["a"])
        #expect(fetch.isTruncated)
    }

    @Test func emptyFirstPageIsAnEmptyWindow() async throws {
        let fetch = try await InsightsService.collectWindow { _ in
            SessionStatsPage(rows: [], hasMore: false)
        }
        #expect(fetch.rows.isEmpty)
        #expect(!fetch.isTruncated)
    }

    /// A mid-crawl failure propagates — no partial window masquerading as a
    /// complete fetch.
    @Test func pageErrorPropagates() async {
        await #expect(throws: InsightsServiceError.timeout) {
            _ = try await InsightsService.collectWindow(pageSize: 2) { offset in
                guard offset == 0 else { throw InsightsServiceError.timeout }
                return SessionStatsPage(rows: self.rows(["a", "b"]), hasMore: true)
            }
        }
    }
}
