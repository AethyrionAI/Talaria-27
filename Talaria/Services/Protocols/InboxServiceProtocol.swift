import Foundation

/// **#309 Lane C bar C6 (2026-08-25) dropped the `accessToken:` parameter from
/// both methods.** It carried the RELAY session token, and the shipped
/// implementation — `TalariaPlatformInboxService`, the plugin drain's local
/// cache since #251-2A — has never read it: the parameter existed only so
/// `InboxStore` could keep asking `AppSessionStore` for a credential that
/// nothing consumed. Dead plumbing that made the store look host-authenticated
/// when it is not.
@MainActor
protocol InboxServiceProtocol {
    func fetchInbox() async throws -> [InboxItem]
    func submitAction(itemID: UUID, actionID: String) async throws -> InboxActionResult
}
