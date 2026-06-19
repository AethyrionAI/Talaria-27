import Foundation

struct PairedRelayConfiguration: Codable, Hashable, Sendable {
    let baseURLString: String
    let hostDisplayName: String
    let pairedAt: Date
}
