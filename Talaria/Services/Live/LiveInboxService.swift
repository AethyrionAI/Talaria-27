import Foundation

@MainActor
final class LiveInboxService: InboxServiceProtocol {
    private struct InboxResponse: Decodable {
        let items: [RelayInboxItem]
    }

    private struct RelayInboxItem: Decodable {
        let id: UUID
        let kind: InboxItemType
        let title: String
        let body: String
        let priority: InboxItemPriority
        let status: InboxItemStatus
        let payload: [String: String]?
        let createdAt: Date
        let primaryActionTitle: String?
        let secondaryActionTitle: String?
    }

    private struct ActionBody: Encodable {
        let actionID: String

        enum CodingKeys: String, CodingKey {
            case actionID = "actionId"
        }
    }

    private let apiClient: RelayAPIClient

    init(apiClient: RelayAPIClient) {
        self.apiClient = apiClient
    }

    func fetchInbox(accessToken: String?) async throws -> [InboxItem] {
        let response: InboxResponse = try await apiClient.get(
            path: "inbox",
            accessToken: accessToken
        )

        return response.items.map { item in
            let primaryActionID = item.primaryActionTitle?.lowercased() == "approve" ? "approve" : "open"
            return InboxItem(
                serverID: item.id,
                type: item.kind,
                title: item.title,
                body: item.body,
                timestamp: item.createdAt,
                isRead: item.status != .pending,
                isActionable: item.status == .pending,
                status: item.status,
                priority: item.priority,
                payload: item.payload,
                primaryAction: item.primaryActionTitle.map { InboxActionDescriptor(id: primaryActionID, title: $0) },
                secondaryAction: item.secondaryActionTitle.map { InboxActionDescriptor(id: "dismiss", title: $0, isDestructive: true) }
            )
        }
    }

    func submitAction(
        itemID: UUID,
        actionID: String,
        accessToken: String?
    ) async throws -> InboxActionResult {
        try await apiClient.post(
            path: "inbox/\(itemID.uuidString.lowercased())/action",
            body: ActionBody(actionID: actionID),
            accessToken: accessToken
        )
    }
}
