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
}
