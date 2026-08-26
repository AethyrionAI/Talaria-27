import Foundation

@MainActor
@Observable
final class InboxStore {
    var items: [InboxItem] = []
    var isLoading = false
    var lastErrorMessage: String?

    private let inboxService: any InboxServiceProtocol
    private let persistence: any AppPersistenceStoreProtocol
    /// **#309 Lane C bar C6 (#412's second sighting): the RELAY availability
    /// gate is now a GATEWAY-CREDENTIAL gate.**
    ///
    /// #310's reason for gating in the STORE rather than only at the
    /// profile-switch site is untouched — `InboxScreen` and
    /// `BriefingDetailScreen` each call `loadInbox(force: true)` from their
    /// own `.task`, so a gate at the switch alone is bypassed by opening the
    /// tab. What changed is the capability it asks about. The inbox has been
    /// plugin-backed since #251-2A (`TalariaPlatformInboxService` reads the
    /// drain's local cache), so `profile.hasRelay` gated a surface with no
    /// relay in it — and after #310's own migration cleared `relayBaseURL` on
    /// every profile, it answered NO everywhere and starved the working
    /// plugin inbox on every install. That is what Owen saw on the device.
    ///
    /// Defaults to "yes" so every existing construction is unchanged.
    private let hasGatewayCredentials: @MainActor () -> Bool
    private var localState: InboxLocalState {
        didSet { persistence.saveInboxState(localState) }
    }

    init(
        inboxService: any InboxServiceProtocol,
        persistence: any AppPersistenceStoreProtocol,
        hasGatewayCredentials: @escaping @MainActor () -> Bool = { true }
    ) {
        self.inboxService = inboxService
        self.persistence = persistence
        self.hasGatewayCredentials = hasGatewayCredentials
        self.localState = persistence.loadInboxState()

        // #352: drop any persisted #113 connector-outage alert — its producer
        // and its clearer died with the upload pipeline, so a raised alert
        // would otherwise sit in the inbox forever with no code left to
        // resolve it. Persisted explicitly (didSet is inert during init).
        if localState.localItems.contains(where: Self.isRetiredConnectorOutageAlert) {
            localState.localItems.removeAll(where: Self.isRetiredConnectorOutageAlert)
            persistence.saveInboxState(localState)
        }
    }

    /// The retired #113 alert's persisted shape (payload key + kind were
    /// inlined here when the producer died — retired names, never reused).
    private static func isRetiredConnectorOutageAlert(_ item: InboxItem) -> Bool {
        item.payload?["talaria.localAlert"] == "connector-outage"
    }

    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    // **#309 Lane C bar C6: `relayUnavailableMessage` is DELETED.**
    //
    // "This profile has no relay URL, so there's no inbox to load from it."
    // was #310's honest message about a plane that has since become the wrong
    // one, and `InboxScreen` renders ANY `lastErrorMessage` as the
    // "Inbox Unreachable — could not reach the relay" state. So the message
    // was the whole of what Owen saw on the device (#412): not a failed fetch
    // reported honestly, but a capability gate reporting the wrong capability
    // through a failure surface.
    //
    // A profile with no host has no inbox to be missing — the honest state is
    // EMPTY, not broken, and `emptyState` already renders it. The #310
    // argument for stating a reason ("nil with no message is indistinguishable
    // from 'asked, nothing there'") does not survive the move: on the plugin
    // plane those two ARE the same state, because the only source of inbox
    // rows is a link this profile does not have.

    func loadInbox(force: Bool = false) async {
        if isLoading || (!force && !items.isEmpty) { return }
        guard hasGatewayCredentials() else {
            // #113's locally-raised alerts are REAL data about this device
            // and must survive — only the host-fed half is unavailable.
            // Dropping them here would be the #45 inversion in reverse:
            // discarding real data because a remote source is absent.
            //
            // Assigned only when it actually CHANGES, for the same reason
            // `HermesHostStore.refresh()`'s hook now fires only on a
            // transition: `items` is `@Observable`, and `applyLocalState`
            // builds a fresh array every call, so an unconditional assignment
            // invalidates every observing view on each visit even when
            // nothing differs. Lower-stakes than the host hook (this is not
            // polled on a cadence), but the same mistake.
            let resolved = applyLocalState(to: localState.localItems)
            if items != resolved { items = resolved }
            lastErrorMessage = nil
            return
        }

        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }

        do {
            let fetchedItems = try await inboxService.fetchInbox()
            // #136: a cancelled launch probe was superseded by a reset —
            // its result must not land over the canceller's state.
            guard !Task.isCancelled else { return }
            // #113: locally-raised alerts lead — they're operational state
            // about THIS device's pipeline, not relay directives.
            items = applyLocalState(to: localState.localItems + fetchedItems)
        } catch is CancellationError {
            // #136: cancellation is the caller superseding this load, not an
            // unreachable relay — leave items + error state untouched.
        } catch {
            // #45: real data only — a failed fetch shows the unreachable
            // state, never demo items. (The DemoData fallback shipped fake
            // directives whenever the relay was down.) Local alerts are real
            // data — a connector-down alert must survive the relay fetch
            // failing, since both symptoms share a likely cause.
            lastErrorMessage = error.localizedDescription
            items = applyLocalState(to: localState.localItems)
        }
    }

    // MARK: - Platform drain (#251-2A)

    /// The drain loop's landing point. Merging happens against this store's
    /// OWN `localState` because the store is the single writer of the
    /// persisted inbox blob: a merge written straight to persistence would be
    /// erased by the next `localState` mutation here (a markRead, a dismiss,
    /// a #113 alert), silently losing items the plugin has already marked
    /// delivered and will never send again.
    ///
    /// Refreshing the visible list is the caller's job (`loadInbox(force:)`)
    /// — this only lands the cache. A batch that is entirely re-delivery
    /// changes nothing and writes nothing.
    func receivePlatformItems(_ platformItems: [TalariaPlatformItem]) {
        var updated = localState
        TalariaPlatformInboxService.merge(platformItems, into: &updated)
        guard updated != localState else { return }
        localState = updated
    }

    private func isLocalItem(_ item: InboxItem) -> Bool {
        localState.localItems.contains { $0.id == item.id }
    }

    func performPrimaryAction(for item: InboxItem) async {
        let actionID = item.primaryAction?.id ?? "approve"
        await submitAction(for: item, actionID: actionID)
    }

    func dismiss(_ item: InboxItem) async {
        await submitAction(for: item, actionID: item.secondaryAction?.id ?? "dismiss")
    }

    /// #126: opening a briefing detail marks it read — device-local
    /// bookkeeping only (same rules as `applyLocalState`), never a relay
    /// action round-trip.
    func markRead(_ item: InboxItem) {
        guard !localState.readItemIDs.contains(item.stableIdentifier) else { return }
        localState.readItemIDs.insert(item.stableIdentifier)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isRead = true
            if items[index].status == .pending { items[index].status = .opened }
            items[index].isActionable = items[index].status == .pending
        }
    }

    // MARK: - #354 user-side delete / clear-all

    /// Whether `delete(_:)` will act on this row. The store owns platform and
    /// local rows — device-local copies (the platform server row was acked
    /// and dropped the moment it drained; #144's deactivate-never-delete
    /// governs SERVER rows, not this copy). Relay-fetched rows are not ours
    /// to delete — dismiss is their lifecycle.
    func canDelete(_ item: InboxItem) -> Bool {
        localState.platformItems.contains { $0.id == item.id }
            || localState.localItems.contains { $0.id == item.id }
    }

    /// Removes an owned row outright, with its marks — one persisted write.
    /// Deleting the row deletes its dedupe memory too, which is fine: the
    /// plugin never redelivers an acked item, so nothing can re-mint it.
    func delete(_ item: InboxItem) {
        guard canDelete(item) else { return }
        var updated = localState
        updated.platformItems.removeAll { $0.id == item.id }
        updated.localItems.removeAll { $0.id == item.id }
        updated.readItemIDs.remove(item.stableIdentifier)
        updated.dismissedItemIDs.remove(item.stableIdentifier)
        localState = updated
        items.removeAll { $0.id == item.id }
    }

    /// The bulk form — every owned row and its marks, one persisted write.
    /// Marks belonging to rows this store does not own (relay annotations)
    /// survive untouched.
    func clearAllInboxItems() {
        var updated = localState
        let removedIDs = Set((updated.platformItems + updated.localItems).map(\.stableIdentifier))
        guard !removedIDs.isEmpty else { return }
        updated.platformItems = []
        updated.localItems = []
        updated.readItemIDs.subtract(removedIDs)
        updated.dismissedItemIDs.subtract(removedIDs)
        localState = updated
        items.removeAll { removedIDs.contains($0.stableIdentifier) }
    }

    private func submitAction(for item: InboxItem, actionID: String) async {
        // #113: app-generated items have no server row — acting on one must
        // never hit the relay (the id would 404 and surface as an error).
        if isLocalItem(item) {
            if actionID == "dismiss" {
                localState.localItems.removeAll { $0.id == item.id }
            } else if let index = localState.localItems.firstIndex(where: { $0.id == item.id }) {
                localState.localItems[index].isRead = true
            }
            applyLocalAction(actionID, to: item)
            return
        }

        do {
            let targetID = item.serverID ?? item.id
            let result = try await inboxService.submitAction(
                itemID: targetID,
                actionID: actionID
            )

            apply(result: result, to: item)
        } catch {
            lastErrorMessage = error.localizedDescription
            applyLocalAction(actionID, to: item)
        }
    }

    private func apply(result: InboxActionResult, to item: InboxItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isRead = true
            items[index].status = result.status
            items[index].isActionable = result.status == .pending
        }

        updateLocalState(for: item, actionID: result.actionID)
    }

    private func applyLocalAction(_ actionID: String, to item: InboxItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isRead = true
            items[index].status = actionID == "dismiss" ? .dismissed : .completed
            items[index].isActionable = false
        }

        updateLocalState(for: item, actionID: actionID)
    }

    private func updateLocalState(for item: InboxItem, actionID: String) {
        localState.readItemIDs.insert(item.stableIdentifier)
        if actionID == "dismiss" {
            localState.dismissedItemIDs.insert(item.stableIdentifier)
            items.removeAll { $0.id == item.id }
        }
    }

    private func applyLocalState(to items: [InboxItem]) -> [InboxItem] {
        items.compactMap { item in
            guard !localState.dismissedItemIDs.contains(item.stableIdentifier) else { return nil }

            var adjustedItem = item
            if localState.readItemIDs.contains(item.stableIdentifier) {
                adjustedItem.isRead = true
                adjustedItem.status = adjustedItem.status == .pending ? .opened : adjustedItem.status
                adjustedItem.isActionable = adjustedItem.status == .pending
            }
            return adjustedItem
        }
    }

    /// Clears the device-local bookkeeping — relay/local read marks, #113
    /// operational alerts — and the visible list.
    ///
    /// #251-2A: `platformItems` deliberately SURVIVE. Every other slice of
    /// this blob is a local annotation on data the server can re-serve; the
    /// platform items are the only copy that exists anywhere, because the
    /// plugin drops an item from its outbox the moment the phone acks it.
    /// Clearing them on a pairing change or a profile switch would delete the
    /// user's agent messages outright, with no re-fetch to recover them.
    ///
    /// #354: marks BELONGING to the surviving platform rows survive with
    /// them. Marks are annotations ON rows and share the rows' lifetime —
    /// clearing them while preserving the rows is what re-badged old agent
    /// messages as NEW on every reset (pairing change, profile switch, and
    /// the launch-path pairing clear). Marks for rows this reset actually
    /// clears still die with their rows.
    func reset() {
        items = []
        lastErrorMessage = nil
        var preserved = InboxLocalState()
        preserved.platformItems = localState.platformItems
        let survivingIDs = Set(preserved.platformItems.map(\.stableIdentifier))
        preserved.readItemIDs = localState.readItemIDs.intersection(survivingIDs)
        preserved.dismissedItemIDs = localState.dismissedItemIDs.intersection(survivingIDs)
        // Clear FIRST, then assign: `localState`'s didSet is what writes the
        // preserved copy back, so a clear afterwards would erase it.
        persistence.clearInboxState()
        localState = preserved
    }
}
