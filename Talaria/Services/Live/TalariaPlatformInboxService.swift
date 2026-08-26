import Foundation

/// #251-2A: maps one drained outbox entry onto the Inbox's row type. Platform
/// items are plain notifications in slice A — the plugin has no action plane,
/// so nothing here is actionable and no action descriptors are attached (the
/// row's buttons render only for `isActionable && !isRead`).
///
/// The platform id is carried in `payload["platformID"]` because it is the
/// dedupe key: `InboxItem.id` is minted locally and `serverID` is a `UUID`,
/// which the plugin's 12-hex ids are not.
func talariaInboxItem(from platformItem: TalariaPlatformItem) -> InboxItem {
    InboxItem(
        type: .notification,
        title: "Hermes",
        body: platformItem.text,
        timestamp: talariaPlatformDate(from: platformItem.createdAt) ?? .now,
        isActionable: false,
        payload: ["platformID": platformItem.id]
    )
}

/// The plugin sends `isoformat(timespec="seconds")` — `2026-08-05T21:00:00+00:00`.
/// The fractional arm is insurance, not present practice: the two formatter
/// configurations are mutually exclusive (each returns nil for the other's
/// form), so a plugin that ever drops `timespec` would otherwise reset every
/// timestamp to "now" silently.
private func talariaPlatformDate(from iso: String) -> Date? {
    let plain = ISO8601DateFormatter()
    if let date = plain.date(from: iso) { return date }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: iso)
}

/// #251-2A: the Inbox's feed after the relay retirement (spec §2.3) — it reads
/// the local cache the drain loop fills, and makes no network call of its own.
/// The durability story lives upstream: the plugin holds an item until the
/// phone acks it, and this cache is what the phone shows afterwards.
@MainActor
final class TalariaPlatformInboxService: InboxServiceProtocol {
    private let persistence: any AppPersistenceStoreProtocol

    init(persistence: any AppPersistenceStoreProtocol) {
        self.persistence = persistence
    }

    /// Fold a drained batch into the persisted cache, deduped on the platform
    /// id — the lane's answer to the #133/#143 duplicate-delivery history. An
    /// item whose ack never landed is re-delivered by the plugin and must
    /// merge to nothing, so `known` grows as the batch is walked (a duplicate
    /// inside ONE batch is the same bug with a shorter fuse) and an existing
    /// row is left untouched rather than replaced — its locally minted `id` is
    /// what read/dismiss bookkeeping keys on.
    ///
    /// Takes `inout` state rather than writing through to persistence: the
    /// only correct caller is `InboxStore.receivePlatformItems`, which owns
    /// the persisted blob. A merge written straight to persistence would be
    /// erased by the store's next `localState` write.
    static func merge(_ new: [TalariaPlatformItem], into state: inout InboxLocalState) {
        var known = Set(state.platformItems.compactMap { $0.payload?["platformID"] })
        for platformItem in new where known.insert(platformItem.id).inserted {
            state.platformItems.append(talariaInboxItem(from: platformItem))
        }
    }

    func fetchInbox() async throws -> [InboxItem] {
        persistence.loadInboxState().platformItems.sorted(by: Self.newestFirst)
    }

    /// Newest first, tie-broken on the platform id. The plugin stamps
    /// `isoformat(timespec="seconds")`, so one agent turn's batch routinely
    /// carries IDENTICAL timestamps — and `sorted(by:)` is not guaranteed
    /// stable, so on timestamp alone those rows could reorder between two
    /// reads of the same unchanged cache. The id is random, not monotonic:
    /// this buys a DETERMINISTIC order, not a chronological one within the
    /// second.
    static func newestFirst(_ lhs: InboxItem, _ rhs: InboxItem) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
        return (lhs.payload?["platformID"] ?? "") > (rhs.payload?["platformID"] ?? "")
    }

    /// Unreachable in practice, and deliberately inert rather than pretending:
    /// platform items are `isActionable == false`, so `InboxItemRow` never
    /// renders a button that could route one here. Nothing is submitted
    /// anywhere, so the result reports the action as still `.pending` — the
    /// caller's own local bookkeeping (`InboxStore.updateLocalState`) is what
    /// records a dismiss. It does not throw, because a throw would paint the
    /// Inbox with an error the user cannot act on.
    func submitAction(itemID: UUID, actionID: String) async throws -> InboxActionResult {
        InboxActionResult(itemID: itemID, actionID: actionID, status: .pending, completedAt: .now)
    }
}
