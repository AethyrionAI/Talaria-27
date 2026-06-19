import Foundation

struct InboxActionResult: Codable, Hashable, Sendable {
    let itemID: UUID
    let actionID: String
    let status: InboxItemStatus
    let completedAt: Date
}
