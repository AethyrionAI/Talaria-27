import Foundation
import Testing
@testable import Talaria

/// #156a D3/D6 — the store's list↔detail mutation propagation and the one
/// hard display rule: a failed refresh never replaces content that already
/// exists. Fixtured service, no network.
@MainActor
struct CronJobsStoreTests {

    // MARK: - Fixture service

    @MainActor
    final class FixtureCronJobService: CronJobServiceProtocol {
        var listResult: Result<[CronJob], Error> = .success([])
        var jobResult: Result<CronJob, Error>?
        var mutationResult: Result<CronJob, Error>?
        var deleteError: Error?
        var platforms: [String]?
        private(set) var listCallCount = 0

        func listJobs() async throws -> [CronJob] {
            listCallCount += 1
            return try listResult.get()
        }

        func job(id: String) async throws -> CronJob {
            try (jobResult ?? mutationResult ?? .failure(CronJobServiceError.notFound)).get()
        }

        func createJob(_ body: CronJobCreateBody) async throws -> CronJob {
            try (mutationResult ?? .failure(CronJobServiceError.notFound)).get()
        }

        func updateJob(id: String, patch: CronJobPatchBody) async throws -> CronJob {
            try (mutationResult ?? .failure(CronJobServiceError.notFound)).get()
        }

        func deleteJob(id: String) async throws {
            if let deleteError { throw deleteError }
        }

        func pauseJob(id: String) async throws -> CronJob {
            try (mutationResult ?? .failure(CronJobServiceError.notFound)).get()
        }

        func resumeJob(id: String) async throws -> CronJob {
            try (mutationResult ?? .failure(CronJobServiceError.notFound)).get()
        }

        func runJob(id: String) async throws -> CronJob {
            try (mutationResult ?? .failure(CronJobServiceError.notFound)).get()
        }

        func deliverPlatforms() async -> [String]? {
            platforms
        }
    }

    private func job(id: String, name: String = "Job", state: String = "scheduled") throws -> CronJob {
        try JSONDecoder().decode(CronJob.self, from: Data("""
        {"id": "\(id)", "name": "\(name)", "state": "\(state)",
         "schedule": {"kind": "interval", "minutes": 30}}
        """.utf8))
    }

    private func makeStore(_ service: FixtureCronJobService) -> CronJobsStore {
        CronJobsStore(service: service)
    }

    // MARK: - Refresh

    @Test func refreshPopulatesAndMarksLoaded() async throws {
        let service = FixtureCronJobService()
        service.listResult = .success([try job(id: "aaa111aaa111")])
        let store = makeStore(service)

        #expect(!store.hasLoaded)
        await store.refresh()

        #expect(store.jobs.map(\.id) == ["aaa111aaa111"])
        #expect(store.hasLoaded)
        #expect(store.lastErrorMessage == nil)
        #expect(store.lastRefreshedAt != nil)
    }

    @Test func failedFirstLoadSurfacesErrorAndStaysUnloaded() async {
        let service = FixtureCronJobService()
        service.listResult = .failure(CronJobServiceError.unreachable("host down"))
        let store = makeStore(service)

        await store.refresh()

        #expect(store.jobs.isEmpty)
        #expect(!store.hasLoaded)
        #expect(store.lastErrorMessage == "host down")
    }

    /// The dispatch's hard rule: errors never replace content that already
    /// exists.
    @Test func failedRefreshKeepsExistingJobs() async throws {
        let service = FixtureCronJobService()
        service.listResult = .success([try job(id: "aaa111aaa111"), try job(id: "bbb222bbb222")])
        let store = makeStore(service)
        await store.refresh()
        #expect(store.jobs.count == 2)

        service.listResult = .failure(CronJobServiceError.timeout)
        await store.refresh()

        #expect(store.jobs.count == 2) // content survived
        #expect(store.lastErrorMessage != nil) // failure surfaced
        #expect(store.hasLoaded) // still a loaded surface
    }

    @Test func successfulRefreshClearsStaleError() async throws {
        let service = FixtureCronJobService()
        service.listResult = .failure(CronJobServiceError.timeout)
        let store = makeStore(service)
        await store.refresh()
        #expect(store.lastErrorMessage != nil)

        service.listResult = .success([try job(id: "aaa111aaa111")])
        await store.refresh()
        #expect(store.lastErrorMessage == nil)
    }

    // MARK: - Mutation propagation (upsert/delete)

    @Test func upsertReplacesInPlaceKeepingOrder() async throws {
        let service = FixtureCronJobService()
        service.listResult = .success([
            try job(id: "aaa111aaa111", name: "First"),
            try job(id: "bbb222bbb222", name: "Second"),
        ])
        let store = makeStore(service)
        await store.refresh()

        store.apply(.upsert(try job(id: "aaa111aaa111", name: "Renamed")))

        #expect(store.jobs.map(\.id) == ["aaa111aaa111", "bbb222bbb222"])
        #expect(store.jobs.first?.name == "Renamed")
    }

    @Test func upsertAppendsNewJob() async throws {
        let service = FixtureCronJobService()
        service.listResult = .success([try job(id: "aaa111aaa111")])
        let store = makeStore(service)
        await store.refresh()

        store.apply(.upsert(try job(id: "ccc333ccc333", name: "Created")))

        #expect(store.jobs.map(\.id) == ["aaa111aaa111", "ccc333ccc333"])
        #expect(store.job(id: "ccc333ccc333")?.name == "Created")
    }

    @Test func deleteRemovesRow() async throws {
        let service = FixtureCronJobService()
        service.listResult = .success([try job(id: "aaa111aaa111"), try job(id: "bbb222bbb222")])
        let store = makeStore(service)
        await store.refresh()

        store.apply(.delete("aaa111aaa111"))

        #expect(store.jobs.map(\.id) == ["bbb222bbb222"])
        #expect(store.job(id: "aaa111aaa111") == nil)
    }

    // MARK: - Actions propagate without refetch

    @Test func pauseUpsertsTheServerResponse() async throws {
        let service = FixtureCronJobService()
        service.listResult = .success([try job(id: "aaa111aaa111", state: "scheduled")])
        let store = makeStore(service)
        await store.refresh()
        let listCallsAfterLoad = service.listCallCount

        service.mutationResult = .success(try job(id: "aaa111aaa111", state: "paused"))
        let failure = await store.pause(id: "aaa111aaa111")

        #expect(failure == nil)
        #expect(store.job(id: "aaa111aaa111")?.state == "paused")
        #expect(store.job(id: "aaa111aaa111")?.derivedStatus == .paused)
        #expect(service.listCallCount == listCallsAfterLoad) // no refetch
    }

    @Test func actionFailureReturnsRenderableMessage() async throws {
        let service = FixtureCronJobService()
        service.listResult = .success([try job(id: "aaa111aaa111")])
        let store = makeStore(service)
        await store.refresh()

        service.mutationResult = .failure(CronJobServiceError.serverRejected("Cannot resume: one-shot time is in the past"))
        let failure = await store.resume(id: "aaa111aaa111")

        #expect(failure == "Cannot resume: one-shot time is in the past")
        // The row is untouched by a failed action.
        #expect(store.job(id: "aaa111aaa111") != nil)
    }

    /// A 404 means the job died host-side — the ghost row drops so the list
    /// reflects reality.
    @Test func notFoundOnActionDropsGhostRow() async throws {
        let service = FixtureCronJobService()
        service.listResult = .success([try job(id: "aaa111aaa111")])
        let store = makeStore(service)
        await store.refresh()

        service.mutationResult = .failure(CronJobServiceError.notFound)
        let failure = await store.runNow(id: "aaa111aaa111")

        #expect(failure != nil) // surfaced — the user should know
        #expect(store.jobs.isEmpty) // and the ghost is gone
    }

    @Test func deleteOfAlreadyGoneJobIsSuccess() async throws {
        let service = FixtureCronJobService()
        service.listResult = .success([try job(id: "aaa111aaa111")])
        let store = makeStore(service)
        await store.refresh()

        service.deleteError = CronJobServiceError.notFound
        let failure = await store.delete(id: "aaa111aaa111")

        #expect(failure == nil) // gone is what the user asked for
        #expect(store.jobs.isEmpty)
    }

    // MARK: - Sheet writes (create / update)

    @Test func createSuccessUpsertsAndReturnsJob() async throws {
        let service = FixtureCronJobService()
        let store = makeStore(service)
        service.mutationResult = .success(try job(id: "ddd444ddd444", name: "Fresh"))

        let result = await store.create(CronJobCreateBody(name: "Fresh", schedule: "every 30m", prompt: ""))

        guard case .success(let created) = result else {
            Issue.record("expected success")
            return
        }
        #expect(created.id == "ddd444ddd444")
        #expect(store.job(id: "ddd444ddd444") != nil)
    }

    /// The server's rejection text reaches the sheet VERBATIM — it is the
    /// only cron validator that exists.
    @Test func createFailureCarriesServerMessageVerbatim() async {
        let service = FixtureCronJobService()
        let store = makeStore(service)
        let serverText = "Cron expressions require 'croniter' package. Install with: pip install croniter"
        service.mutationResult = .failure(CronJobServiceError.serverRejected(serverText))

        let result = await store.create(CronJobCreateBody(name: "X", schedule: "0 9 * * *", prompt: ""))

        guard case .failure(let failure) = result else {
            Issue.record("expected failure")
            return
        }
        #expect(failure.message == serverText)
        #expect(store.jobs.isEmpty) // nothing phantom-inserted
    }

    @Test func updateSuccessPropagatesToList() async throws {
        let service = FixtureCronJobService()
        service.listResult = .success([try job(id: "aaa111aaa111", name: "Old")])
        let store = makeStore(service)
        await store.refresh()

        service.mutationResult = .success(try job(id: "aaa111aaa111", name: "New"))
        var patch = CronJobPatchBody()
        patch.name = "New"
        let result = await store.update(id: "aaa111aaa111", patch: patch)

        guard case .success = result else {
            Issue.record("expected success")
            return
        }
        #expect(store.job(id: "aaa111aaa111")?.name == "New")
        #expect(store.jobs.count == 1)
    }

    // MARK: - Deliver platforms

    @Test func deliverPlatformsPropagate() async {
        let service = FixtureCronJobService()
        service.platforms = ["telegram", "discord"]
        let store = makeStore(service)

        await store.refreshDeliverPlatforms()
        #expect(store.deliverPlatforms == ["telegram", "discord"])

        service.platforms = nil
        await store.refreshDeliverPlatforms()
        #expect(store.deliverPlatforms == nil) // degrade signal for the picker
    }

    // MARK: - #180: profile-scoped reset

    /// #180 — the store is host-fed and therefore profile-scoped: a profile
    /// switch must return it to never-loaded. `deliverPlatforms` is host
    /// data too — Host A's connected platforms are not Host B's.
    @Test func resetReturnsTheStoreToNeverLoaded() async throws {
        let service = FixtureCronJobService()
        service.listResult = .success([try job(id: "aaa111aaa111")])
        service.platforms = ["telegram"]
        let store = makeStore(service)
        await store.refresh()
        await store.refreshDeliverPlatforms()
        #expect(store.hasLoaded)
        #expect(store.deliverPlatforms == ["telegram"])

        store.reset()

        #expect(store.jobs.isEmpty)
        #expect(!store.hasLoaded)
        #expect(store.lastErrorMessage == nil)
        #expect(store.lastRefreshedAt == nil)
        #expect(store.deliverPlatforms == nil)
    }

    /// #180, the racy variant — a fetch already in flight against the OLD
    /// host when reset() lands must not deliver the old host's jobs into
    /// the reset store (same supersede family as #136's bootstrap cancel).
    @Test func resetDiscardsAnInFlightFetchFromTheOldHost() async throws {
        let service = GatedCronJobService()
        service.listResult = .success([try job(id: "aaa111aaa111")])
        let store = CronJobsStore(service: service)

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

        #expect(store.jobs.isEmpty)
        #expect(!store.hasLoaded)
        #expect(store.lastRefreshedAt == nil)
    }

    /// Parks each list fetch on a continuation until released, so a test can
    /// order reset() against an in-flight fetch deterministically.
    @MainActor
    final class GatedCronJobService: CronJobServiceProtocol {
        var listResult: Result<[CronJob], Error> = .success([])
        private var continuations: [CheckedContinuation<Void, Never>] = []
        var pendingCount: Int { continuations.count }

        func release() {
            let held = continuations
            continuations = []
            for continuation in held { continuation.resume() }
        }

        func listJobs() async throws -> [CronJob] {
            await withCheckedContinuation { continuations.append($0) }
            return try listResult.get()
        }

        func job(id: String) async throws -> CronJob { throw CronJobServiceError.notFound }
        func createJob(_ body: CronJobCreateBody) async throws -> CronJob { throw CronJobServiceError.notFound }
        func updateJob(id: String, patch: CronJobPatchBody) async throws -> CronJob { throw CronJobServiceError.notFound }
        func deleteJob(id: String) async throws {}
        func pauseJob(id: String) async throws -> CronJob { throw CronJobServiceError.notFound }
        func resumeJob(id: String) async throws -> CronJob { throw CronJobServiceError.notFound }
        func runJob(id: String) async throws -> CronJob { throw CronJobServiceError.notFound }
        func deliverPlatforms() async -> [String]? { nil }
    }
}
