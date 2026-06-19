import Foundation

struct HermesHostStatus: Codable, Hashable, Sendable {
    let id: UUID
    let displayName: String?
    let hostname: String?
    let platform: String?
    let connectorVersion: String?
    let hermesCommand: String?
    let hermesVersion: String?
    let hermesModel: String?
    let lastSeenAt: Date?
    let lastConnectedAt: Date?
    let isOnline: Bool

    var resolvedDisplayName: String {
        displayName ?? hostname ?? "Hermes Host"
    }
}
