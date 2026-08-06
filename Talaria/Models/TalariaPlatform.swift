import Foundation

// #251-2A: envelope DTOs for the talaria platform transport. The gateway
// speaks snake_case on this plane, and every param/meta value is a STRING by
// contract (spec §Addendum) — so these decode straight into `[String: String]`
// rather than an `Any`-typed bag.

/// Response to a `pair` envelope: the durable device identity the phone then
/// presents on every drain/ack/query_result.
struct TalariaPairResponse: Decodable, Sendable {
    let deviceID: String
    let deviceToken: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case deviceToken = "device_token"
    }
}

/// One durable outbox entry — something the agent wants to say to the phone.
struct TalariaPlatformItem: Decodable, Sendable, Equatable {
    let id: String
    let kind: String
    let text: String
    let createdAt: String
    let meta: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, kind, text, meta
        case createdAt = "created_at"
    }
}

/// One question the agent is asking OF the phone; answered with a
/// `query_result` envelope carrying the same `id`.
struct TalariaPlatformQuery: Decodable, Sendable, Equatable {
    let id: String
    let kind: String
    let params: [String: String]?
}

/// Response to a `drain` envelope. Both arrays are always present on the
/// wire; an idle drain is two empty arrays, not a 204.
struct TalariaDrainResponse: Decodable, Sendable {
    let items: [TalariaPlatformItem]
    let queries: [TalariaPlatformQuery]
}

/// The gateway's error envelope — `code` is the machine-readable half,
/// decoded purely for logging. Re-pair is driven by the HTTP 401 status
/// alone (`TalariaPlatformLink.drain`); this code is never inspected to
/// decide it — `invalid_talaria_auth` is simply the value that's been
/// observed to accompany the 401, not a trigger in its own right.
struct TalariaEnvelopeError: Decodable, Sendable {
    let error: String
    let code: String
}
