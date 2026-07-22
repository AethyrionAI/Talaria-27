import Foundation

/// #156b — shared state for the Skills browser (D3) and the cron editor's
/// skills picker (D5): the fetched list, load/error state, and the refresh
/// wrapper. No caching layer in this lane — fetch on appear +
/// pull-to-refresh, same posture as Tasks. Owns the same hard rule as
/// `CronJobsStore`: **errors never replace content that already exists** — a
/// failed refresh with skills on screen keeps the skills and only surfaces
/// the message.
@MainActor
@Observable
final class SkillsStore {
    private let service: any SkillsServiceProtocol

    private(set) var skills: [Skill] = []
    private(set) var isLoading = false
    /// True once ANY fetch has succeeded — distinguishes "empty because the
    /// host has no skills" from "empty because nothing loaded yet".
    private(set) var hasLoaded = false
    private(set) var lastErrorMessage: String?
    /// When the on-screen list was last actually fetched — rendered as
    /// "as of HH:mm" so a load-time snapshot is never presented as live.
    private(set) var lastRefreshedAt: Date?

    init(service: any SkillsServiceProtocol) {
        self.service = service
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            skills = try await service.listSkills()
            hasLoaded = true
            lastRefreshedAt = Date()
            lastErrorMessage = nil
        } catch {
            // Existing rows stay on screen; only the message updates.
            lastErrorMessage = Self.message(for: error)
        }
    }

    private nonisolated static func message(for error: Error) -> String {
        if let serviceError = error as? SkillsServiceError {
            return serviceError.errorDescription ?? "The Hermes host request failed."
        }
        let described = error.localizedDescription
        return described.isEmpty ? "The Hermes host request failed." : described
    }
}
