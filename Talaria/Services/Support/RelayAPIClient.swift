import Foundation

enum RelayCoders {
    private static func internetDateTimeStyle() -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(timeZone: .gmt)
    }

    private static func internetDateTimeFractionalStyle() -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt)
    }

    private static func normalizedRelayDateStrings(for value: String) -> [String] {
        if value.hasSuffix("Z") || value.range(of: #"[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil {
            return [value]
        }

        return ["\(value)Z"]
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = parseRelayDate(value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported relay date: \(value)"
            )
        }
        return decoder
    }

    static func parseRelayDate(_ value: String) -> Date? {
        for candidate in normalizedRelayDateStrings(for: value) {
            if let date = try? internetDateTimeFractionalStyle().parse(candidate) {
                return date
            }

            if let date = try? internetDateTimeStyle().parse(candidate) {
                return date
            }
        }

        return nil
    }
}

@MainActor
final class RelayAPIClient {
    private struct Envelope<T: Decodable>: Decodable {
        let data: T
    }

    private struct ErrorEnvelope: Decodable {
        struct ErrorPayload: Decodable {
            let code: String
            let message: String
            let retryable: Bool
        }

        let error: ErrorPayload
    }

    private struct FastAPIErrorEnvelope: Decodable {
        let detail: String
    }

    enum ClientError: LocalizedError {
        case unauthorized(String)
        case invalidURL(String)
        case requestFailed(String)
        /// The relay parsed the request and rejected the PAYLOAD itself
        /// (400/422 — e.g. Pydantic validation): retrying identical bytes can
        /// never succeed. Distinct from `requestFailed` so uploaders can
        /// isolate poison data instead of wedging on infinite retries of the
        /// same rejected body (OPEN_ITEMS #24a follow-up). Other 4xx (403/404
        /// etc.) intentionally stay `requestFailed` — they're about auth or
        /// routing, not the payload, and other services key off that mapping.
        case payloadRejected(statusCode: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .unauthorized(let message):
                message
            case .invalidURL(let url):
                "Invalid relay URL: \(url)"
            case .requestFailed(let message):
                message
            case .payloadRejected(let statusCode, let message):
                "Relay rejected the payload (\(statusCode)): \(message)"
            }
        }
    }

    /// #21 Tier 2: how `downloadFile` failed. Its own enum (not `ClientError`)
    /// because the agent-file route's status semantics are load-bearing for
    /// the UI: 401 = the device bearer was refused (re-auth territory), 404 =
    /// the relay's honest "no such file" — which by design NEVER distinguishes
    /// missing from outside-the-whitelist, so neither do we.
    enum FileDownloadError: LocalizedError, Equatable {
        case unauthorized
        case notFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                "The relay refused this device's authorization."
            case .notFound:
                "The file isn't available from the relay."
            case .failed(let message):
                message
            }
        }
    }

    /// #136: timeouts for launch/bootstrap-class probes. A black-holed host
    /// — Windows Firewall silently DROPS packets to listener-less ports, so
    /// there is no TCP refusal and every request hangs the full timeout
    /// (error -1001) — must fail in seconds, even in background init.
    static let bootstrapProbeRequestTimeout: TimeInterval = 5
    static let bootstrapProbeResourceTimeout: TimeInterval = 10

    /// #136: dedicated session for launch/bootstrap probes (session
    /// bootstrap, host status, inbox fetch, command catalog, push
    /// register). Scoped to probe-class calls only — NEVER the chat path
    /// (`:8642`), SSE streams, agent-file downloads, or sensor uploads,
    /// whose long-transfer semantics a 10s resource timeout would break.
    static func makeBootstrapProbeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = bootstrapProbeRequestTimeout
        configuration.timeoutIntervalForResource = bootstrapProbeResourceTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private let baseURLProvider: @MainActor () -> String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        baseURLProvider: @escaping @MainActor () -> String,
        session: URLSession = .shared
    ) {
        self.baseURLProvider = baseURLProvider
        self.session = session
        self.encoder = RelayCoders.makeEncoder()
        self.decoder = RelayCoders.makeDecoder()
    }

    func get<T: Decodable>(
        path: String,
        accessToken: String? = nil
    ) async throws -> T {
        let request = try makeRequest(path: path, method: "GET", accessToken: accessToken, body: nil)
        return try await send(request)
    }

    func post<T: Decodable>(
        path: String,
        accessToken: String? = nil
    ) async throws -> T {
        let request = try makeRequest(path: path, method: "POST", accessToken: accessToken, body: nil)
        return try await send(request)
    }

    func post<Body: Encodable, T: Decodable>(
        path: String,
        body: Body,
        accessToken: String? = nil
    ) async throws -> T {
        let requestBody = try encoder.encode(body)
        let request = try makeRequest(
            path: path,
            method: "POST",
            accessToken: accessToken,
            body: requestBody
        )
        return try await send(request)
    }

    /// #21 Tier 2: downloads an agent-written file from the relay's
    /// whitelisted agent-files route (`GET /v1/device/files?path=…`) to a
    /// local temp file and returns its URL. `path` is the
    /// AGENT_FILES_DIR-relative path (route-form — the relay also accepts
    /// contained absolute paths, but the app only ever sends the whitelisted
    /// relative form); the caller stages the returned file and owns its
    /// lifetime. The device bearer rides the Authorization HEADER only —
    /// never the URL, query, or logs.
    func downloadFile(path: String, accessToken: String) async throws -> URL {
        guard !accessToken.isEmpty else { throw FileDownloadError.unauthorized }
        let baseURLString = baseURLProvider().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Strict RFC 3986 unreserved-set encoding, ASCII-only on purpose:
        // `/` and `+` in a filename must not survive raw (Starlette decodes
        // `+` in a query as a space), and non-ASCII must be percent-encoded
        // rather than left for URL(string:) to reject.
        let allowed = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        guard !baseURLString.isEmpty,
              let encodedPath = path.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "\(baseURLString)/device/files?path=\(encodedPath)") else {
            throw FileDownloadError.failed("Invalid relay URL for the file download.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300

        let (temporaryURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw FileDownloadError.failed("Relay returned an invalid response.")
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            switch httpResponse.statusCode {
            case 401: throw FileDownloadError.unauthorized
            case 404: throw FileDownloadError.notFound
            default: throw FileDownloadError.failed("Relay file download failed with status \(httpResponse.statusCode).")
            }
        }
        // URLSession only guarantees its temp file until this scope returns —
        // claim it immediately under a name we own.
        let claimed = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-file-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: temporaryURL, to: claimed)
        return claimed
    }

    private func makeRequest(
        path: String,
        method: String,
        accessToken: String?,
        body: Data?
    ) throws -> URLRequest {
        let path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let baseURLString = baseURLProvider().trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard let url = URL(string: "\(baseURLString)/\(path)") else {
            throw ClientError.invalidURL(baseURLString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    /// Opens an SSE stream to the given path and yields parsed events.
    ///
    /// The stream handles `event:` / `data:` lines per the SSE spec,
    /// ignores keepalive comments (lines starting with `:`), and
    /// terminates when the server closes the connection.
    nonisolated func streamEvents(
        path: String,
        accessToken: String?
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    var request = try makeRequest(
                        path: path,
                        method: "GET",
                        accessToken: accessToken,
                        body: nil
                    )
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 300

                    let (bytes, response) = try await session.bytes(for: request)
                    let httpResponse = response as? HTTPURLResponse

                    guard let httpResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        if code == 401 {
                            continuation.finish(throwing: ClientError.unauthorized("Unauthorized"))
                        } else {
                            continuation.finish(throwing: ClientError.requestFailed(
                                "SSE stream failed with status \(code)."
                            ))
                        }
                        return
                    }

                    var currentEvent = "message"
                    var currentData = ""

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        // Keepalive comment
                        if line.hasPrefix(":") {
                            continue
                        }

                        // Empty line = dispatch event
                        if line.isEmpty {
                            if !currentData.isEmpty {
                                continuation.yield(SSEEvent(
                                    event: currentEvent,
                                    data: currentData
                                ))
                                currentEvent = "message"
                                currentData = ""
                            }
                            continue
                        }

                        if line.hasPrefix("event:") {
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

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        guard let httpResponse else {
            throw ClientError.requestFailed("Relay returned an invalid response.")
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let makeError: (String) -> ClientError = { message in
                switch httpResponse.statusCode {
                case 401:
                    return .unauthorized(message)
                case 400, 422:
                    return .payloadRejected(statusCode: httpResponse.statusCode, message: message)
                default:
                    return .requestFailed(message)
                }
            }

            if let errorEnvelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw makeError(errorEnvelope.error.message)
            }

            if let errorEnvelope = try? decoder.decode(FastAPIErrorEnvelope.self, from: data) {
                throw makeError(errorEnvelope.detail)
            }

            throw makeError("Relay request failed with status \(httpResponse.statusCode).")
        }

        return try decoder.decode(Envelope<T>.self, from: data).data
    }
}
