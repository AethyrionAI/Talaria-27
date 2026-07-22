import Foundation
import os

/// #156d — client over the gateway's `GET /api/sessions` list (handler
/// verified at `api_server.py:2246`: `limit` max 200, `offset`, ordered by
/// last-active). Same `:8642` base + Bearer `API_SERVER_KEY` seam as
/// `CronJobService`/`SkillsService`; no relay, no connector, no new services
/// (#161). `include_children` stays unset (server default false) — fork
/// children would double-count their parent's spend.
///
/// The fetch assembles a bounded recency window: up to `maxPages` pages of
/// `pageSize`, stopping early when the server says `has_more` is false. When
/// the cap cuts the list short the result says so (`isTruncated`) — the
/// screen's numbers are always labeled with the window they cover.
@MainActor
protocol InsightsServiceProtocol {
    func fetchRecentSessions() async throws -> SessionStatsFetch
}

/// Typed, user-renderable failures — same shape as `SkillsServiceError`.
enum InsightsServiceError: LocalizedError, Equatable {
    case notConfigured(String)
    case unreachable(String)
    case timeout
    case unauthorized(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message),
             .unreachable(let message),
             .unauthorized(let message),
             .invalidResponse(let message):
            return message
        case .timeout:
            return "The Hermes host took too long to respond."
        }
    }
}

@MainActor
final class InsightsService: InsightsServiceProtocol {
    private static let logger = Logger(subsystem: TalariaLog.subsystem, category: "InsightsService")
    private static let sessionsPath = "/api/sessions"
    /// The server's hard `limit` maximum (verified).
    static let pageSize = 200
    /// 3 × 200 = a 600-session window — enough for honest aggregate shape
    /// without an unbounded crawl of a long-lived host's history.
    static let maxPages = 3

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let baseURLProvider: @MainActor () -> String?
    private let apiKeyProvider: @MainActor () -> String?

    init(
        baseURLProvider: @escaping @MainActor () -> String?,
        apiKeyProvider: @escaping @MainActor () -> String?,
        session: URLSession = .shared
    ) {
        self.baseURLProvider = baseURLProvider
        self.apiKeyProvider = apiKeyProvider
        self.session = session
    }

    func fetchRecentSessions() async throws -> SessionStatsFetch {
        try await Self.collectWindow { offset in
            try await self.fetchPage(offset: offset)
        }
    }

    /// The pagination loop, factored off the transport so tests drive it
    /// with fixture pages. Stops on `has_more` false, an empty page (a
    /// server claiming more while sending nothing must not spin), or the
    /// page cap — only stopping with `has_more` still true marks the window
    /// truncated. MainActor like its callers — the closure hops are free and
    /// the iOS 27 strict checker has nothing to prove.
    static func collectWindow(
        pageSize: Int = InsightsService.pageSize,
        maxPages: Int = InsightsService.maxPages,
        fetchPage: (Int) async throws -> SessionStatsPage
    ) async rethrows -> SessionStatsFetch {
        var rows: [SessionStatsRow] = []
        var isTruncated = false
        for pageIndex in 0 ..< max(maxPages, 1) {
            let page = try await fetchPage(pageIndex * pageSize)
            rows.append(contentsOf: page.rows)
            guard page.hasMore else { break }
            if page.rows.isEmpty || pageIndex == maxPages - 1 {
                // Either the cap, or a server claiming more while sending
                // nothing — both end the crawl with rows left unseen.
                isTruncated = true
                break
            }
        }
        return SessionStatsFetch(rows: rows, isTruncated: isTruncated)
    }

    private func fetchPage(offset: Int) async throws -> SessionStatsPage {
        let path = "\(Self.sessionsPath)?limit=\(Self.pageSize)&offset=\(offset)"
        let request = try makeRequest(path: path)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.transportError(error)
        }
        try Self.ensureSuccess(response: response, data: data)
        let page: SessionStatsPage
        do {
            page = try decoder.decode(SessionStatsPage.self, from: data)
        } catch {
            throw InsightsServiceError.invalidResponse(
                "The Hermes host answered in a shape this build can't read."
            )
        }
        if page.skippedRowCount > 0 {
            Self.logger.error("fetchPage(offset \(offset, privacy: .public)): skipped \(page.skippedRowCount, privacy: .public) unparseable session row(s), kept \(page.rows.count, privacy: .public)")
        }
        return page
    }

    // MARK: - HTTP plumbing

    private func makeRequest(path: String) throws -> URLRequest {
        guard let baseURL = baseURLProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURL.isEmpty else {
            throw InsightsServiceError.notConfigured("Hermes API base URL is not set.")
        }
        guard let apiKey = apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw InsightsServiceError.notConfigured("Hermes API key is not set.")
        }
        var normalized = baseURL
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard let url = URL(string: normalized + path) else {
            throw InsightsServiceError.notConfigured("Hermes API base URL is not a valid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // A metadata read — fail fast instead of riding the chat path's 300s.
        request.timeoutInterval = 15
        return request
    }

    private nonisolated static func transportError(_ error: Error) -> InsightsServiceError {
        guard let urlError = error as? URLError else {
            return .unreachable(error.localizedDescription)
        }
        if urlError.code == .timedOut { return .timeout }
        return .unreachable(urlError.localizedDescription)
    }

    private nonisolated static func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw InsightsServiceError.invalidResponse("The Hermes host returned an invalid response.")
        }
        let status = httpResponse.statusCode
        guard !(200 ..< 300).contains(status) else { return }
        switch status {
        case 401, 403:
            throw InsightsServiceError.unauthorized(
                "The Hermes host rejected this device's API key."
            )
        default:
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw InsightsServiceError.invalidResponse(
                "The Hermes host returned status \(status). \(snippet)"
            )
        }
    }
}
