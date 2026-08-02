import Foundation
import Testing
@testable import Talaria

/// #156b D6 — store behavior over a fixtured service (no network): the four
/// content-state inputs and the one hard display rule shared with Tasks —
/// **a failed refresh never replaces content that already exists**.
@MainActor
struct SkillsStoreTests {

    @MainActor
    final class FixtureSkillsService: SkillsServiceProtocol {
        var listResult: Result<[Skill], Error> = .success([])
        private(set) var listCallCount = 0

        func listSkills() async throws -> [Skill] {
            listCallCount += 1
            return try listResult.get()
        }
    }

    private func skill(_ name: String) -> Skill {
        Skill(name: name, description: nil, category: nil)
    }

    @Test func refreshPopulatesAndMarksLoaded() async {
        let service = FixtureSkillsService()
        service.listResult = .success([skill("alpha"), skill("beta")])
        let store = SkillsStore(service: service)

        #expect(!store.hasLoaded)
        #expect(store.lastRefreshedAt == nil)
        await store.refresh()

        #expect(store.hasLoaded)
        #expect(store.skills.map(\.name) == ["alpha", "beta"])
        #expect(store.lastErrorMessage == nil)
        #expect(store.lastRefreshedAt != nil)
    }

    @Test func failureBeforeFirstLoadSurfacesErrorOnly() async {
        let service = FixtureSkillsService()
        service.listResult = .failure(SkillsServiceError.timeout)
        let store = SkillsStore(service: service)

        await store.refresh()

        #expect(!store.hasLoaded)
        #expect(store.skills.isEmpty)
        #expect(store.lastErrorMessage == SkillsServiceError.timeout.errorDescription)
    }

    /// The hard rule: rows on screen survive a failed refresh.
    @Test func failedRefreshKeepsExistingSkills() async {
        let service = FixtureSkillsService()
        service.listResult = .success([skill("alpha")])
        let store = SkillsStore(service: service)
        await store.refresh()
        let firstFetchAt = store.lastRefreshedAt

        service.listResult = .failure(SkillsServiceError.unreachable("Host offline."))
        await store.refresh()

        #expect(store.skills.map(\.name) == ["alpha"])
        #expect(store.hasLoaded)
        #expect(store.lastErrorMessage == "Host offline.")
        // The as-of stamp still describes the data actually on screen.
        #expect(store.lastRefreshedAt == firstFetchAt)
    }

    @Test func successAfterFailureClearsError() async {
        let service = FixtureSkillsService()
        service.listResult = .failure(SkillsServiceError.unreachable("down"))
        let store = SkillsStore(service: service)
        await store.refresh()
        #expect(store.lastErrorMessage != nil)

        service.listResult = .success([skill("alpha")])
        await store.refresh()

        #expect(store.lastErrorMessage == nil)
        #expect(store.skills.count == 1)
    }

    @Test func successfulEmptyListIsLoadedNotError() async {
        // Empty + loaded is the "no skills installed on this host" state —
        // distinct from never-loaded.
        let service = FixtureSkillsService()
        service.listResult = .success([])
        let store = SkillsStore(service: service)

        await store.refresh()

        #expect(store.hasLoaded)
        #expect(store.skills.isEmpty)
        #expect(store.lastErrorMessage == nil)
    }

    // MARK: - #180: profile-scoped reset

    /// #180 — the store is host-fed and therefore profile-scoped: a profile
    /// switch must return it to never-loaded, or the cron editor's skills
    /// picker offers Host A's skills for a job that will be created on
    /// Host B.
    @Test func resetReturnsTheStoreToNeverLoaded() async {
        let service = FixtureSkillsService()
        service.listResult = .success([skill("alpha")])
        let store = SkillsStore(service: service)
        await store.refresh()
        #expect(store.hasLoaded)

        store.reset()

        #expect(store.skills.isEmpty)
        #expect(!store.hasLoaded)
        #expect(store.lastErrorMessage == nil)
        #expect(store.lastRefreshedAt == nil)
    }

    /// #180, the racy variant — a fetch already in flight against the OLD
    /// host when reset() lands must not deliver the old host's rows into
    /// the reset store. Same supersede family as #136's bootstrap cancel:
    /// without a generation guard, reset() is a control on a path the
    /// defect does not take.
    @Test func resetDiscardsAnInFlightFetchFromTheOldHost() async {
        let service = GatedSkillsService()
        service.listResult = .success([skill("old-host-skill")])
        let store = SkillsStore(service: service)

        let fetch = Task { await store.refresh() }
        var spins = 0
        while service.pendingCount == 0, spins < 10_000 {
            await Task.yield()
            spins += 1
        }
        #expect(service.pendingCount == 1)

        store.reset()
        service.release()
        await fetch.value

        #expect(store.skills.isEmpty)
        #expect(!store.hasLoaded)
        #expect(store.lastRefreshedAt == nil)
    }

    /// A service that parks each fetch on a continuation until released, so
    /// a test can order reset() against an in-flight fetch deterministically.
    @MainActor
    final class GatedSkillsService: SkillsServiceProtocol {
        var listResult: Result<[Skill], Error> = .success([])
        private var continuations: [CheckedContinuation<Void, Never>] = []
        var pendingCount: Int { continuations.count }

        func release() {
            let held = continuations
            continuations = []
            for continuation in held { continuation.resume() }
        }

        func listSkills() async throws -> [Skill] {
            await withCheckedContinuation { continuations.append($0) }
            return try listResult.get()
        }
    }
}
