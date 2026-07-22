import Foundation
import os

/// #156b — client over the Hermes gateway's `GET /v1/skills` (the ONLY skill
/// route; verified hermes-agent 0.19.0). Same `:8642` base + Bearer
/// `API_SERVER_KEY` seam as `CronJobService`; no relay, no connector, no new
/// services (#161). Read-only is the honest scope: the handler already
/// filters to enabled skills and exposes no toggle, detail, or install
/// surface — what this returns is what the agent can use.
///
/// NOT the composer's source: `/v1/commands` autocomplete keeps the relay
/// catalog (`SlashCommand`); the two planes can disagree and that is
/// expected — no reconciliation.
@MainActor
protocol SkillsServiceProtocol {
    func listSkills() async throws -> [Skill]
}

/// Typed, user-renderable failures — same shape as `CronJobServiceError`.
enum SkillsServiceError: LocalizedError, Equatable {
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
final class SkillsService: SkillsServiceProtocol {
    private static let logger = Logger(subsystem: TalariaLog.subsystem, category: "SkillsService")
    private static let skillsPath = "/v1/skills"

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

    func listSkills() async throws -> [Skill] {
        let request = try makeRequest(path: Self.skillsPath)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.transportError(error)
        }
        try Self.ensureSuccess(response: response, data: data)
        let listResponse: SkillListResponse
        do {
            listResponse = try decoder.decode(SkillListResponse.self, from: data)
        } catch {
            throw SkillsServiceError.invalidResponse(
                "The Hermes host answered in a shape this build can't read."
            )
        }
        if listResponse.skippedRowCount > 0 {
            Self.logger.error("listSkills: skipped \(listResponse.skippedRowCount, privacy: .public) unparseable skill row(s), kept \(listResponse.skills.count, privacy: .public)")
        }
        return listResponse.skills
    }

    // MARK: - HTTP plumbing

    private func makeRequest(path: String) throws -> URLRequest {
        guard let baseURL = baseURLProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURL.isEmpty else {
            throw SkillsServiceError.notConfigured("Hermes API base URL is not set.")
        }
        guard let apiKey = apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw SkillsServiceError.notConfigured("Hermes API key is not set.")
        }
        var normalized = baseURL
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard let url = URL(string: normalized + path) else {
            throw SkillsServiceError.notConfigured("Hermes API base URL is not a valid URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // A metadata read — fail fast instead of riding the chat path's 300s.
        request.timeoutInterval = 15
        return request
    }

    private nonisolated static func transportError(_ error: Error) -> SkillsServiceError {
        guard let urlError = error as? URLError else {
            return .unreachable(error.localizedDescription)
        }
        if urlError.code == .timedOut { return .timeout }
        return .unreachable(urlError.localizedDescription)
    }

    private nonisolated static func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SkillsServiceError.invalidResponse("The Hermes host returned an invalid response.")
        }
        let status = httpResponse.statusCode
        guard !(200 ..< 300).contains(status) else { return }
        switch status {
        case 401, 403:
            throw SkillsServiceError.unauthorized(
                "The Hermes host rejected this device's API key."
            )
        default:
            let snippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw SkillsServiceError.invalidResponse(
                "The Hermes host returned status \(status). \(snippet)"
            )
        }
    }
}
