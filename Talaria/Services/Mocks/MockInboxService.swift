import Foundation

@MainActor
final class MockInboxService: InboxServiceProtocol {
    private var items = DemoData.sampleInboxItems

    func fetchInbox(accessToken: String?) async throws -> [InboxItem] {
        try? await Task.sleep(for: .seconds(0.2))
        return items
    }

    func submitAction(
        itemID: UUID,
        actionID: String,
        accessToken: String?
    ) async throws -> InboxActionResult {
        try? await Task.sleep(for: .seconds(0.1))

        if let index = items.firstIndex(where: { $0.serverID == itemID || $0.id == itemID }) {
            items[index].isRead = true
            items[index].status = actionID == "dismiss" ? .dismissed : .completed
        }

        return InboxActionResult(
            itemID: itemID,
            actionID: actionID,
            status: actionID == "dismiss" ? .dismissed : .completed,
            completedAt: .now
        )
    }
}
