import Foundation
import os

@MainActor
final class LiveInboxService: InboxServiceProtocol {
    private static let logger = Logger(subsystem: TalariaLog.subsystem, category: "LiveInboxService")

    /// #58: decoded row-by-row. One malformed row (unknown `kind`, bad UUID /
    /// date, missing field) used to fail the whole `[RelayInboxItem]` decode,
    /// which surfaced app-side as "relay offline" with a healthy relay. Bad
    /// rows are now skipped (counted, so fetchInbox can log the quarantine);
    /// every parseable row survives. Internal (not private) for tests.
    struct InboxResponse: Decodable {
        let items: [RelayInboxItem]
        let skippedRowCount: Int

        private enum CodingKeys: String, CodingKey {
            case items
        }

        /// Decodes and discards one JSON value of any shape. A failed
        /// `decode(RelayInboxItem.self)` leaves the unkeyed container's index
        /// on the bad row — decoding into this no-op type is what steps past
        /// it.
        private struct SkippedRow: Decodable {
            init(from decoder: any Decoder) throws {}
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var rows = try container.nestedUnkeyedContainer(forKey: .items)
            var decoded: [RelayInboxItem] = []
            var skipped = 0
            while !rows.isAtEnd {
                let indexBeforeRow = rows.currentIndex
                do {
                    decoded.append(try rows.decode(RelayInboxItem.self))
                } catch {
                    // Step past the bad row: `decodeNil` advances over a JSON
                    // null (and refuses without advancing otherwise); the
                    // no-op decode advances over anything else.
                    if (try? rows.decodeNil()) != true {
                        _ = try? rows.decode(SkippedRow.self)
                    }
                    skipped += 1
                    // If nothing could advance, abandon the remainder rather
                    // than spin forever on the same row.
                    if rows.currentIndex == indexBeforeRow { break }
                }
            }
            items = decoded
            skippedRowCount = skipped
        }
    }

    struct RelayInboxItem: Decodable {
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
    private let accessTokenRefresher: @MainActor () async -> String?

    init(
        apiClient: RelayAPIClient,
        accessTokenRefresher: @escaping @MainActor () async -> String? = { nil }
    ) {
        self.apiClient = apiClient
        self.accessTokenRefresher = accessTokenRefresher
    }

    func fetchInbox(accessToken: String?) async throws -> [InboxItem] {
        let response: InboxResponse = try await performAuthorizedRequest(initialAccessToken: accessToken) { token in
            try await self.apiClient.get(
                path: "inbox",
                accessToken: token
            )
        }

        if response.skippedRowCount > 0 {
            // Always-on: a producer is emitting rows this build can't parse
            // (#58) — quarantined here, not a fetch failure.
            Self.logger.error("fetchInbox: skipped \(response.skippedRowCount, privacy: .public) unparseable row(s), kept \(response.items.count, privacy: .public)")
        }

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
        try await performAuthorizedRequest(initialAccessToken: accessToken) { token in
            try await self.apiClient.post(
                path: "inbox/\(itemID.uuidString.lowercased())/action",
                body: ActionBody(actionID: actionID),
                accessToken: token
            )
        }
    }

    // #45 follow-up: the same 401-recovery ladder as LiveHermesHostService.
    // The Inbox was the one relay consumer that treated a stale access token
    // as terminal — it reported "unreachable" while every other surface
    // (host, sensors, talk) silently refreshed and looked online.
    private func performAuthorizedRequest<T>(
        initialAccessToken: String?,
        _ operation: @escaping @MainActor (_ accessToken: String?) async throws -> T
    ) async throws -> T {
        do {
            return try await operation(initialAccessToken)
        } catch RelayAPIClient.ClientError.unauthorized {
            guard let refreshedToken = await accessTokenRefresher(), !refreshedToken.isEmpty else {
                throw RelayAPIClient.ClientError.unauthorized("Hermes session expired and couldn't be renewed automatically — re-pair this device with your Hermes relay.")
            }
            return try await operation(refreshedToken)
        }
    }
}
