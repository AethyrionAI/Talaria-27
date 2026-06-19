import Foundation

@MainActor
final class ResilientInboxService: InboxServiceProtocol {
    private let primary: any InboxServiceProtocol
    private let fallback: any InboxServiceProtocol
    private let allowsFallback: @MainActor () -> Bool

    init(
        primary: any InboxServiceProtocol,
        fallback: any InboxServiceProtocol,
        allowsFallback: @escaping @MainActor () -> Bool = { true }
    ) {
        self.primary = primary
        self.fallback = fallback
        self.allowsFallback = allowsFallback
    }

    func fetchInbox(accessToken: String?) async throws -> [InboxItem] {
        do {
            return try await primary.fetchInbox(accessToken: accessToken)
        } catch {
            guard allowsFallback() else { throw error }
            return try await fallback.fetchInbox(accessToken: accessToken)
        }
    }

    func submitAction(
        itemID: UUID,
        actionID: String,
        accessToken: String?
    ) async throws -> InboxActionResult {
        do {
            return try await primary.submitAction(itemID: itemID, actionID: actionID, accessToken: accessToken)
        } catch {
            guard allowsFallback() else { throw error }
            return try await fallback.submitAction(itemID: itemID, actionID: actionID, accessToken: accessToken)
        }
    }
}
