import Foundation
import os

/// #156a — how a mutation's result lands back in the list: the service
/// returns the server's updated record and BOTH surfaces (list + detail)
/// read the same store, so they can never disagree or flicker. Never a
/// refetch (#160 idea 2).
enum CronJobMutation {
    case upsert(CronJob)
    case delete(String)
}

/// Shared state for the Tasks surface (#156a D3): the job list, load/error
/// state, and the action wrappers the screens call. Owns the one rule the
/// dispatch is strict about — **errors never replace content that already
/// exists**: a failed refresh with jobs on screen keeps the jobs and only
/// surfaces the message.
@MainActor
@Observable
final class CronJobsStore {
    private static let logger = Logger(subsystem: TalariaLog.subsystem, category: "CronJobsStore")

    private let service: any CronJobServiceProtocol

    private(set) var jobs: [CronJob] = []
    private(set) var isLoading = false
    /// True once ANY fetch has succeeded — distinguishes "empty because the
    /// host has no jobs" from "empty because nothing loaded yet" (D3's four
    /// content states).
    private(set) var hasLoaded = false
    private(set) var lastErrorMessage: String?
    /// When the on-screen list was last actually fetched — rendered as
    /// "as of HH:mm" so a load-time snapshot is never presented as live
    /// (#160 weakness 3).
    private(set) var lastRefreshedAt: Date?
    /// Connected platform names for the deliver picker; nil = the fetch
    /// failed and the picker degrades to free text (D5).
    private(set) var deliverPlatforms: [String]?

    init(service: any CronJobServiceProtocol) {
        self.service = service
    }

    // MARK: - Loading

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            jobs = try await service.listJobs()
            hasLoaded = true
            lastRefreshedAt = Date()
            lastErrorMessage = nil
        } catch {
            // Existing rows stay on screen; only the message updates.
            lastErrorMessage = Self.message(for: error)
        }
    }

    /// Best-effort, refreshed alongside the sheet opening; failure only
    /// means free-text deliver entry.
    func refreshDeliverPlatforms() async {
        deliverPlatforms = await service.deliverPlatforms()
    }

    // MARK: - Mutation propagation

    func apply(_ mutation: CronJobMutation) {
        switch mutation {
        case .upsert(let job):
            if let index = jobs.firstIndex(where: { $0.id == job.id }) {
                jobs[index] = job
            } else {
                jobs.append(job)
            }
        case .delete(let id):
            jobs.removeAll { $0.id == id }
        }
    }

    func job(id: String) -> CronJob? {
        jobs.first { $0.id == id }
    }

    // MARK: - Actions

    /// Every action returns the user-renderable failure message (nil =
    /// success) so the calling screen can surface it non-destructively.
    @discardableResult
    func runNow(id: String) async -> String? {
        await mutate(id: id) { .upsert(try await $0.runJob(id: id)) }
    }

    @discardableResult
    func pause(id: String) async -> String? {
        await mutate(id: id) { .upsert(try await $0.pauseJob(id: id)) }
    }

    @discardableResult
    func resume(id: String) async -> String? {
        await mutate(id: id) { .upsert(try await $0.resumeJob(id: id)) }
    }

    @discardableResult
    func delete(id: String) async -> String? {
        await mutate(id: id, notFoundIsSuccess: true) { service in
            try await service.deleteJob(id: id)
            return .delete(id)
        }
    }

    /// Create/update for the sheet (D5). On success the server's record is
    /// upserted and returned; on failure the message comes back verbatim so
    /// the sheet stays open with the input intact (D4's one non-negotiable).
    func create(_ body: CronJobCreateBody) async -> Result<CronJob, CronSheetError> {
        await write { try await $0.createJob(body) }
    }

    func update(id: String, patch: CronJobPatchBody) async -> Result<CronJob, CronSheetError> {
        await write { try await $0.updateJob(id: id, patch: patch) }
    }

    struct CronSheetError: Error {
        let message: String
    }

    private func write(
        _ operation: @MainActor (any CronJobServiceProtocol) async throws -> CronJob
    ) async -> Result<CronJob, CronSheetError> {
        do {
            let job = try await operation(service)
            apply(.upsert(job))
            return .success(job)
        } catch {
            return .failure(CronSheetError(message: Self.message(for: error)))
        }
    }

    private func mutate(
        id: String,
        notFoundIsSuccess: Bool = false,
        _ operation: @MainActor (any CronJobServiceProtocol) async throws -> CronJobMutation
    ) async -> String? {
        do {
            apply(try await operation(service))
            return nil
        } catch CronJobServiceError.notFound {
            // The job died out from under us (deleted host-side) — drop the
            // ghost row so the list reflects reality. Deleting an
            // already-gone job is the outcome the user asked for.
            apply(.delete(id))
            return notFoundIsSuccess ? nil : CronJobServiceError.notFound.errorDescription
        } catch {
            return Self.message(for: error)
        }
    }

    private nonisolated static func message(for error: Error) -> String {
        if let serviceError = error as? CronJobServiceError {
            return serviceError.errorDescription ?? "The Hermes host request failed."
        }
        let described = error.localizedDescription
        return described.isEmpty ? "The Hermes host request failed." : described
    }
}
