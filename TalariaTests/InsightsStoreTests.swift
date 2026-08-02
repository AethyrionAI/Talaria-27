import Foundation
import Testing
@testable import Talaria

/// #156d D5 — store behavior over a fixtured service (no network): the four
/// content-state inputs, the truncation flag's ride-along, and the one hard
/// display rule shared with Tasks and Skills — **a failed refresh never
/// replaces content that already exists**.
@MainActor
struct InsightsStoreTests {

    @MainActor
    final class FixtureInsightsService: InsightsServiceProtocol {
        var fetchResult: Result<SessionStatsFetch, Error> = .success(SessionStatsFetch(rows: [], isTruncated: false))
        private(set) var fetchCallCount = 0

        func fetchRecentSessions() async throws -> SessionStatsFetch {
            fetchCallCount += 1
            return try fetchResult.get()
        }
    }

    private func fetch(_ ids: [String], truncated: Bool = false) -> SessionStatsFetch {
        SessionStatsFetch(
            rows: ids.map {
                SessionStatsRow(id: $0, usage: SessionUsage(inputTokens: 10, outputTokens: 5))
            },
            isTruncated: truncated
        )
    }

    @Test func refreshPopulatesRowsSummaryAndStamp() async {
        let service = FixtureInsightsService()
        service.fetchResult = .success(fetch(["a", "b"]))
        let store = InsightsStore(service: service)

        #expect(!store.hasLoaded)
        #expect(store.summary == nil)
        await store.refresh()

        #expect(store.hasLoaded)
        #expect(store.rows.map(\.id) == ["a", "b"])
        #expect(store.summary?.totals.sessionCount == 2)
        #expect(store.summary?.totals.inputTokens == 20)
        #expect(!store.isTruncated)
        #expect(store.lastErrorMessage == nil)
        #expect(store.lastRefreshedAt != nil)
    }

    @Test func truncationFlagRidesTheFetch() async {
        let service = FixtureInsightsService()
        service.fetchResult = .success(fetch(["a"], truncated: true))
        let store = InsightsStore(service: service)

        await store.refresh()
        #expect(store.isTruncated)

        service.fetchResult = .success(fetch(["a"], truncated: false))
        await store.refresh()
        #expect(!store.isTruncated)
    }

    @Test func failureBeforeFirstLoadSurfacesErrorOnly() async {
        let service = FixtureInsightsService()
        service.fetchResult = .failure(InsightsServiceError.timeout)
        let store = InsightsStore(service: service)

        await store.refresh()

        #expect(!store.hasLoaded)
        #expect(store.rows.isEmpty)
        #expect(store.summary == nil)
        #expect(store.lastErrorMessage == InsightsServiceError.timeout.errorDescription)
    }

    /// The hard rule: numbers on screen survive a failed refresh.
    @Test func failedRefreshKeepsExistingNumbers() async {
        let service = FixtureInsightsService()
        service.fetchResult = .success(fetch(["a"]))
        let store = InsightsStore(service: service)
        await store.refresh()
        let firstFetchAt = store.lastRefreshedAt
        let firstSummary = store.summary

        service.fetchResult = .failure(InsightsServiceError.unreachable("Host offline."))
        await store.refresh()

        #expect(store.rows.map(\.id) == ["a"])
        #expect(store.summary == firstSummary)
        #expect(store.hasLoaded)
        #expect(store.lastErrorMessage == "Host offline.")
        // The as-of stamp still describes the numbers actually on screen.
        #expect(store.lastRefreshedAt == firstFetchAt)
    }

    @Test func successAfterFailureClearsError() async {
        let service = FixtureInsightsService()
        service.fetchResult = .failure(InsightsServiceError.unreachable("down"))
        let store = InsightsStore(service: service)
        await store.refresh()
        #expect(store.lastErrorMessage != nil)

        service.fetchResult = .success(fetch(["a"]))
        await store.refresh()

        #expect(store.lastErrorMessage == nil)
        #expect(store.rows.count == 1)
    }

    @Test func successfulEmptyFetchIsLoadedNotError() async {
        // Empty + loaded is the "no sessions recorded on this host" state —
        // distinct from never-loaded.
        let service = FixtureInsightsService()
        service.fetchResult = .success(SessionStatsFetch(rows: [], isTruncated: false))
        let store = InsightsStore(service: service)

        await store.refresh()

        #expect(store.hasLoaded)
        #expect(store.rows.isEmpty)
        #expect(store.summary?.totals.sessionCount == 0)
        #expect(store.lastErrorMessage == nil)
    }

    // MARK: - #180: profile-scoped reset

    /// #180 — the store is host-fed and therefore profile-scoped: a profile
    /// switch must return it to never-loaded. The summary and truncation
    /// flag are derived from host rows and reset with them.
    @Test func resetReturnsTheStoreToNeverLoaded() async {
        let service = FixtureInsightsService()
        service.fetchResult = .success(fetch(["a"], truncated: true))
        let store = InsightsStore(service: service)
        await store.refresh()
        #expect(store.hasLoaded)
        #expect(store.isTruncated)

        store.reset()

        #expect(store.rows.isEmpty)
        #expect(store.summary == nil)
        #expect(!store.isTruncated)
        #expect(!store.hasLoaded)
        #expect(store.lastErrorMessage == nil)
        #expect(store.lastRefreshedAt == nil)
    }

    /// #180, the racy variant — a fetch already in flight against the OLD
    /// host when reset() lands must not deliver the old host's rows into
    /// the reset store (same supersede family as #136's bootstrap cancel).
    @Test func resetDiscardsAnInFlightFetchFromTheOldHost() async {
        let service = GatedInsightsService()
        service.fetchResult = .success(fetch(["old-host-session"]))
        let store = InsightsStore(service: service)

        let fetchTask = Task { await store.refresh() }
        var spins = 0
        while service.pendingCount == 0, spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        #expect(service.pendingCount == 1)

        store.reset()
        service.release()
        await fetchTask.value

        #expect(store.rows.isEmpty)
        #expect(store.summary == nil)
        #expect(!store.hasLoaded)
        #expect(store.lastRefreshedAt == nil)
    }

    /// Parks each fetch on a continuation until released, so a test can
    /// order reset() against an in-flight fetch deterministically.
    @MainActor
    final class GatedInsightsService: InsightsServiceProtocol {
        var fetchResult: Result<SessionStatsFetch, Error> = .success(SessionStatsFetch(rows: [], isTruncated: false))
        private var continuations: [CheckedContinuation<Void, Never>] = []
        var pendingCount: Int { continuations.count }

        func release() {
            let held = continuations
            continuations = []
            for continuation in held { continuation.resume() }
        }

        func fetchRecentSessions() async throws -> SessionStatsFetch {
            await withCheckedContinuation { continuations.append($0) }
            return try fetchResult.get()
        }
    }
}
