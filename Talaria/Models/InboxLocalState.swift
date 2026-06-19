import Foundation

struct InboxLocalState: Codable, Hashable, Sendable {
    var readItemIDs: Set<String> = []
    var dismissedItemIDs: Set<String> = []
}
