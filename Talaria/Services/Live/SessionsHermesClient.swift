import Foundation
import os

/// Talks directly to the Hermes API server's Sessions API (default :8642).
///
/// Replaces the relay → connector → Hermes-CLI pipe for chat. Responses are
/// structured JSON / SSE, so they carry no ANSI codes and keep reasoning in a
/// separate channel. Relay/connector are still used for sensors and pairing.
@MainActor
final class SessionsHermesClient: HermesClientProtocol {
    private static let logger = Logger(subsystem: "org.aethyrion.talaria", category: "SessionsHermesClient")
    private static let modelsPath = "/v1/models"
    private static let modelOptionsPath = "/api/model/options"
    private static let sessionsPath = "/api/sessions"

    var connectionStatus: ConnectionStatus = .disconnected
    var currentConversation: Conversation?

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let baseURLProvider: @MainActor () -> String?
    private let apiKeyProvider: @MainActor () -> String?

    /// The current Hermes Sessions API session id (e.g. "api_…"). Distinct from
    /// `currentConversation.id`, which is the client-side UUID used by the chat UI.
    private var apiSessionId: String?

    init(
        baseURLProvider: @escaping @MainActor () -> String?,
        apiKeyProvider: @escaping @MainActor () -> String?,
        session: URLSession = .shared
    ) {
        self.baseURLProvider = baseURLProvider
        self.apiKeyProvider = apiKeyProvider
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - HermesClientProtocol

    func connect() async {
        connectionStatus = .connecting
        do {
            let _: ModelsResponse = try await getJSON(path: Self.modelsPath)
            connectionStatus = .connected
        } catch {
            Self.logger.warning("Sessions API /v1/models failed: \(error.localizedDescription)")
            connectionStatus = .error
        }
    }

    func disconnect() async {
        apiSessionId = nil
        connectionStatus = .disconnected
    }

    func send(
        message: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) async -> Message {
        do {
            let sessionId = try await ensureSession()
            let path = "\(Self.sessionsPath)/\(sessionId)/chat"
            let response: SyncChatResponse = try await postJSON(
                path: path,
                body: ChatTurnBody(input: message)
            )
            connectionStatus = .connected
            let content = response.message?.content ?? response.content ?? ""
            return Message(
                sender: .hermes,
                content: content,
                status: .delivered
            )
        } catch {
            connectionStatus = .error
            return Message(
                sender: .system,
                content: failureMessage(for: error),
                status: .failed
            )
        }
    }

    func sendStreaming(
        message content: String,
        attachments: [PendingAttachment] = [],
        clientMessageID: UUID
    ) -> AsyncStream<StreamingUpdate> {
        AsyncStream { continuation in
            Task { @MainActor [weak self] in
                guard let self else {
                    continuation.yield(.failed("Client deallocated"))
                    continuation.finish()
                    return
                }

                do {
                    let sessionId = try await self.ensureSession()
                    let path = "\(Self.sessionsPath)/\(sessionId)/chat/stream"
                    let body = try self.encoder.encode(ChatTurnBody(input: content))
                    let request = try self.makeRequest(path: path, method: "POST", body: body, accept: "text/event-stream")

                    let (bytes, response) = try await self.session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200 ..< 300).contains(httpResponse.statusCode) else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        self.connectionStatus = .error
                        continuation.yield(.failed("Hermes API returned status \(code)."))
                        continuation.finish()
                        return
                    }

                    self.connectionStatus = .connected

                    var currentEvent = "message"
                    var currentData = ""
                    var assembledContent = ""
                    var finalMessageDelivered = false

                    func dispatchEvent() {
                        defer {
                            currentEvent = "message"
                            currentData = ""
                        }
                        guard !currentData.isEmpty else { return }
                        switch currentEvent {
                        case "assistant.delta":
                            if let delta = self.decodeJSONString(currentData, key: "delta"),
                               !delta.isEmpty {
                                assembledContent += delta
                                continuation.yield(.textDelta(delta))
                            }
                        case "tool.started", "tool.completed":
                            if let toolName = self.decodeJSONString(currentData, key: "tool_name"),
                               !toolName.isEmpty,
                               toolName != "_thinking" {
                                continuation.yield(.toolActivity(toolName))
                            }
                        case "tool.progress":
                            // Reasoning chunks ride on `_thinking`; drop them in
                            // Phase 1 (the disclosure UI is Phase 2 work).
                            break
                        case "assistant.completed":
                            // Streaming returns an empty final_response (text already
                            // streamed via assistant.delta), so the server sends content:"".
                            // Empty string is non-nil, so `?? assembledContent` won't fire;
                            // fall back to the assembled deltas when content is blank.
                            let declared = self.decodeJSONString(currentData, key: "content")
                            let finalContent = (declared?.isEmpty == false) ? declared! : assembledContent
                            let finalMessage = Message(
                                sender: .hermes,
                                content: finalContent,
                                status: .delivered
                            )
                            continuation.yield(.finished(finalMessage, nil, nil))
                            finalMessageDelivered = true
                        case "done":
                            break
                        default:
                            break
                        }
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.hasPrefix(":") { continue }
                        if line.isEmpty {
                            dispatchEvent()
                            continue
                        }
                        if line.hasPrefix("event:") {
                            // URLSession's bytes.lines swallows the blank lines that
                            // separate SSE events, so the `line.isEmpty` dispatch above
                            // never fires. Flush the previous event when a new one begins.
                            if !currentData.isEmpty { dispatchEvent() }
                            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if currentData.isEmpty {
                                currentData = value
                            } else {
                                currentData += "\n" + value
                            }
                        }
                    }

                    // Flush any pending event the server didn't terminate with a blank line.
                    if !currentData.isEmpty { dispatchEvent() }

                    if !finalMessageDelivered {
                        let fallbackMessage = Message(
                            sender: .hermes,
                            content: assembledContent,
                            status: .delivered
                        )
                        continuation.yield(.finished(fallbackMessage, nil, nil))
                    }
                    continuation.finish()
                } catch {
                    self.connectionStatus = .error
                    Self.logger.warning("Sessions API stream failed: \(error.localizedDescription)")
                    continuation.yield(.failed(self.failureMessage(for: error)))
                    continuation.finish()
                }
            }
        }
    }

    func loadConversation() async -> Conversation {
        if let currentConversation { return currentConversation }
        let fresh = Conversation(title: "Hermes")
        currentConversation = fresh
        return fresh
    }

    func clearConversation() async throws -> Conversation {
        apiSessionId = nil
        let fresh = Conversation(title: "Hermes")
        currentConversation = fresh
        return fresh
    }

    func injectVoiceTranscript(voiceSessionId: UUID) async throws -> Conversation {
        // Voice transcript injection is a relay-side concept. The Sessions API
        // doesn't expose an equivalent endpoint, so leave the local conversation
        // untouched and let callers decide how to surface this.
        if let currentConversation { return currentConversation }
        let fresh = Conversation(title: "Hermes")
        currentConversation = fresh
        return fresh
    }

    // MARK: - Model controls

    /// Lists switchable model identifiers from the host's /api/model/options.
    func availableModels() async throws -> [String] {
        // The OpenAI-compatible /v1/models endpoint reports only the Hermes
        // agent itself as a single pseudo-model ("hermes-agent"). The real list
        // of switchable models lives at /api/model/options (provider-grouped —
        // the same source `hermes model` uses). Flatten the authenticated
        // providers' models into a de-duplicated, ordered id list.
        let response: ModelOptionsResponse = try await getJSON(path: Self.modelOptionsPath)
        var ids: [String] = []
        var seen = Set<String>()
        for provider in response.providers where provider.authenticated == true {
            for model in provider.models ?? [] where !model.isEmpty {
                if seen.insert(model).inserted { ids.append(model) }
            }
        }
        return ids
    }

    // MARK: - Session lifecycle

    /// Switches the active model for the NEXT session. The Hermes agent
    /// dispatches `/model …` as a command turn; the chosen model applies once a
    /// fresh session is created. Phase 3 wiring will call this from the picker.
    func switchModel(_ identifier: String) async throws {
        let sessionId = try await ensureSession()
        let path = "\(Self.sessionsPath)/\(sessionId)/chat"
        let _: SyncChatResponse = try await postJSON(
            path: path,
            body: ChatTurnBody(input: "/model \(identifier)")
        )
    }

    // MARK: - Sessions list / open

    func listSessions() async throws -> [HermesSessionInfo] {
        let response: SessionsListResponse = try await getJSON(
            path: "\(Self.sessionsPath)?limit=50&order=recent&min_messages=1"
        )
        return response.sessions.map { row in
            HermesSessionInfo(
                id: row.id,
                title: row.title,
                preview: row.preview,
                model: row.model,
                source: row.source,
                messageCount: row.messageCount ?? 0,
                lastActive: row.lastActive.map { Date(timeIntervalSince1970: $0) },
                isActive: row.isActive ?? false
            )
        }
    }

    /// Adopts `id` as the active session and returns its full history. New
    /// messages then continue that thread (see ensureSession()).
    func openSession(_ id: String) async throws -> Conversation {
        let response: SessionMessagesResponse = try await getJSON(
            path: "\(Self.sessionsPath)/\(id)/messages"
        )
        apiSessionId = response.sessionId ?? id
        let messages = response.messages.compactMap(Self.mapStoredMessage)
        let convo = Conversation(
            title: "Hermes",
            messages: messages,
            lastActivity: messages.last?.timestamp ?? .now
        )
        currentConversation = convo
        connectionStatus = .connected
        return convo
    }

    nonisolated private static func mapStoredMessage(_ m: SessionMessagesResponse.StoredMessage) -> Message? {
        let sender: MessageSender
        switch (m.role ?? "").lowercased() {
        case "user": sender = .user
        case "assistant": sender = .hermes
        default: return nil   // skip system / tool / other roles
        }
        let text = (m.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let ts = m.timestamp.map { Date(timeIntervalSince1970: $0) } ?? .now
        return Message(sender: sender, content: text, timestamp: ts, status: .delivered)
    }

    private func ensureSession() async throws -> String {
        if let apiSessionId { return apiSessionId }
        let response: CreateSessionResponse = try await postJSON(
            path: Self.sessionsPath,
            body: EmptyBody()
        )
        apiSessionId = response.session.id
        if currentConversation == nil {
            currentConversation = Conversation(title: "Hermes")
        }
        return response.session.id
    }

    // MARK: - HTTP plumbing

    private func getJSON<T: Decodable>(path: String) async throws -> T {
        let request = try makeRequest(path: path, method: "GET", body: nil, accept: "application/json")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func postJSON<Body: Encodable, T: Decodable>(path: String, body: Body) async throws -> T {
        let encodedBody = try encoder.encode(body)
        let request = try makeRequest(path: path, method: "POST", body: encodedBody, accept: "application/json")
        let (data, response) = try await session.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func makeRequest(path: String, method: String, body: Data?, accept: String) throws -> URLRequest {
        guard let baseURL = baseURLProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURL.isEmpty,
              let url = URL(string: normalizedBaseURL(baseURL) + path) else {
            throw SessionsClientError.notConfigured("Hermes API base URL is not set.")
        }
        guard let apiKey = apiKeyProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !apiKey.isEmpty else {
            throw SessionsClientError.notConfigured("Hermes API key is not set.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.httpBody = body
        request.timeoutInterval = 300
        return request
    }

    private func normalizedBaseURL(_ raw: String) -> String {
        var trimmed = raw
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    private func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SessionsClientError.requestFailed("Hermes API returned an invalid response.")
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let bodySnippet = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            throw SessionsClientError.requestFailed(
                "Hermes API returned status \(httpResponse.statusCode). \(bodySnippet)"
            )
        }
    }

    nonisolated private func decodeJSONString(_ raw: String, key: String) -> String? {
        guard let data = raw.data(using: .utf8) else { return nil }
        if let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            return dict[key] as? String
        }
        return nil
    }

    private func failureMessage(for error: Error) -> String {
        if let sessionsError = error as? SessionsClientError {
            return sessionsError.errorDescription ?? "Hermes API request failed."
        }
        let described = error.localizedDescription
        return described.isEmpty ? "Hermes API request failed." : described
    }

    // MARK: - Wire types

    private struct EmptyBody: Encodable {}

    private struct ChatTurnBody: Encodable {
        let input: String
    }

    private struct CreateSessionResponse: Decodable {
        let session: SessionEnvelope
        struct SessionEnvelope: Decodable {
            let id: String
        }
    }

    private struct SyncChatResponse: Decodable {
        let message: AssistantMessage?
        let content: String?
        struct AssistantMessage: Decodable {
            let content: String
        }
    }

    private struct ModelsResponse: Decodable {
        let data: [ModelInfo]?
        struct ModelInfo: Decodable {
            let id: String?
        }
    }

    /// Subset of /api/model/options needed to flatten the picker list. Extra
    /// keys (provider labels, auth hints, pricing, current selection) are
    /// ignored; `models` is a flat list of model-id strings per provider.
    private struct ModelOptionsResponse: Decodable {
        let providers: [ProviderRow]
        struct ProviderRow: Decodable {
            let models: [String]?
            let authenticated: Bool?
        }
    }

    private struct SessionsListResponse: Decodable {
        let sessions: [Row]
        struct Row: Decodable {
            let id: String
            let title: String?
            let preview: String?
            let model: String?
            let source: String?
            let messageCount: Int?
            let lastActive: Double?
            let isActive: Bool?
            enum CodingKeys: String, CodingKey {
                case id, title, preview, model, source
                case messageCount = "message_count"
                case lastActive = "last_active"
                case isActive = "is_active"
            }
        }
    }

    private struct SessionMessagesResponse: Decodable {
        let sessionId: String?
        let messages: [StoredMessage]
        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case messages
        }
        struct StoredMessage: Decodable {
            let role: String?
            let content: String?
            let timestamp: Double?
            enum CodingKeys: String, CodingKey {
                case role, content, timestamp
                case createdAt = "created_at"
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                role = try c.decodeIfPresent(String.self, forKey: .role)
                let ts = try? c.decodeIfPresent(Double.self, forKey: .timestamp)
                let created = try? c.decodeIfPresent(Double.self, forKey: .createdAt)
                timestamp = (ts ?? nil) ?? (created ?? nil)
                // content may be a plain string or an array of {type, text} parts.
                if let s = try? c.decode(String.self, forKey: .content) {
                    content = s
                } else if let parts = try? c.decode([ContentPart].self, forKey: .content) {
                    content = parts.compactMap(\.text).joined(separator: "\n")
                } else {
                    content = nil
                }
            }
            struct ContentPart: Decodable {
                let type: String?
                let text: String?
            }
        }
    }

    enum SessionsClientError: LocalizedError {
        case notConfigured(String)
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured(let message), .requestFailed(let message):
                return message
            }
        }
    }
}
