import Foundation

struct InboxActionDescriptor: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let isDestructive: Bool

    init(
        id: String,
        title: String,
        isDestructive: Bool = false
    ) {
        self.id = id
        self.title = title
        self.isDestructive = isDestructive
    }
}
