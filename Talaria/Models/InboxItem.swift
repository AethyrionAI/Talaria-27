import Foundation

struct InboxItem: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let serverID: UUID?
    let type: InboxItemType
    let title: String
    let body: String
    let timestamp: Date
    var isRead: Bool
    var isActionable: Bool
    var status: InboxItemStatus
    var priority: InboxItemPriority
    var payload: [String: String]?
    var primaryAction: InboxActionDescriptor?
    var secondaryAction: InboxActionDescriptor?

    init(
        id: UUID = UUID(),
        serverID: UUID? = nil,
        type: InboxItemType,
        title: String,
        body: String,
        timestamp: Date = .now,
        isRead: Bool = false,
        isActionable: Bool = true,
        status: InboxItemStatus = .pending,
        priority: InboxItemPriority = .normal,
        payload: [String: String]? = nil,
        primaryAction: InboxActionDescriptor? = nil,
        secondaryAction: InboxActionDescriptor? = nil
    ) {
        self.id = id
        self.serverID = serverID
        self.type = type
        self.title = title
        self.body = body
        self.timestamp = timestamp
        self.isRead = isRead
        self.isActionable = isActionable
        self.status = status
        self.priority = priority
        self.payload = payload
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }

    var stableIdentifier: String {
        serverID?.uuidString ?? id.uuidString
    }
}
