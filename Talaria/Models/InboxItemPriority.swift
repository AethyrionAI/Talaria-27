import Foundation

enum InboxItemPriority: String, Codable, Hashable, Sendable, CaseIterable {
    case low
    case normal
    case high
    case urgent
}
