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
/// extraction itself — that is what "zero behaviour change" meant for bar C1.
///
/// **Bar C5 then trimmed what the deletion left dead, in its own commit:**
/// `payloadRejected` had exactly one producer (`RelayAPIClient.send`'s 400/422
/// arm, for the #24a sensor uploaders — a pipeline #352 deleted) and zero
/// consumers, so it went with the client; and the two case texts that named
/// the relay were re-cut, because with the relay client gone the only thrower
/// left is voice, and "Invalid relay URL: https://api.openai.com/…" is a
/// sentence about a component neither end of that request has ever involved.
enum APIClientError: LocalizedError {
    case unauthorized(String)
    case invalidURL(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let message):
            message
        case .invalidURL(let url):
            "Invalid URL: \(url)"
        case .requestFailed(let message):
            message
        }
    }
}
