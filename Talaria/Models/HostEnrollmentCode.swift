import Foundation

struct HostEnrollmentCode: Codable, Hashable, Sendable {
    let setupCode: String
    let expiresAt: Date?
    let relayHost: String
}
