import Foundation

enum InboxItemStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case pending
    case opened
    case completed
    case dismissed
}
