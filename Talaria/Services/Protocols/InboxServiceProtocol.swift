import Foundation

@MainActor
protocol InboxServiceProtocol {
    func fetchInbox(accessToken: String?) async throws -> [InboxItem]
    func submitAction(
        itemID: UUID,
        actionID: String,
        accessToken: String?
    ) async throws -> InboxActionResult
}
