import Foundation

/// The HTTP-shaped client failure the app's hand-rolled request paths throw.
///
/// **#309 Lane C bar C1 (2026-08-25): extracted VERBATIM from
/// `RelayAPIClient.ClientError`.** It had to move before the relay client
/// could be deleted, because `LiveVoiceSessionService` borrows it at four
/// sites (`:986`, `:1045`, `:1055`, `:1447`) — WebRTC and OpenAI Realtime
/// failures that have nothing to do with the relay and outlive it. Leaving
/// the enum nested inside `RelayAPIClient` would have made the deletion break
/// voice compilation, which is exactly what the design doc §5b flagged.
///
/// Nothing about the cases or their `errorDescription` text changed in the
/// extraction — that is what "zero behaviour change" means here, and the
/// mutation that proves it is restoring the old nesting. `RelayAPIClient`
/// carries a `typealias ClientError = APIClientError` for as long as it
/// survives, so its own throw sites and the tests that catch them are
/// untouched by this move.
enum APIClientError: LocalizedError {
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
