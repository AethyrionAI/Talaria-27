import Foundation

@MainActor
@Observable
final class InboxStore {
    var items: [InboxItem] = []
    var isLoading = false
    var lastErrorMessage: String?

    private let inboxService: any InboxServiceProtocol
    private let persistence: any AppPersistenceStoreProtocol
    private let sessionStore: AppSessionStore
    private var localState: InboxLocalState {
        didSet { persistence.saveInboxState(localState) }
    }

    init(
        inboxService: any InboxServiceProtocol,
        persistence: any AppPersistenceStoreProtocol,
        sessionStore: AppSessionStore
    ) {
        self.inboxService = inboxService
        self.persistence = persistence
        self.sessionStore = sessionStore
        self.localState = persistence.loadInboxState()
    }

    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    func loadInbox(force: Bool = false) async {
        if isLoading || (!force && !items.isEmpty) { return }

        isLoading = true
        lastErrorMessage = nil
        defer { isLoading = false }

        do {
            let token = await sessionStore.currentAccessToken()
            let fetchedItems = try await inboxService.fetchInbox(accessToken: token)
            // #113: locally-raised alerts lead — they're operational state
            // about THIS device's pipeline, not relay directives.
            items = applyLocalState(to: localState.localItems + fetchedItems)
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

    // MARK: - Local operational alerts (#113)

    /// Marks an app-generated item so action handling never round-trips the
    /// relay for it. Value, not presence, is checked — a relay payload could
    /// carry the same key.
    private static let localAlertPayloadKey = "talaria.localAlert"
    static let connectorOutageAlertKind = "connector-outage"

    /// Enqueue the connector-down alert (#113). Deduped: while one is live
    /// in `localItems`, further raises are no-ops — the policy layer also
    /// guards this, but the store must stay safe to call unconditionally.
    func raiseConnectorOutageAlert() {
        guard !localState.localItems.contains(where: { isConnectorOutageAlert($0) }) else { return }
        let item = InboxItem(
            type: .alert,
            title: "Sensor uploads stalled",
            body: "Sensor uploads can't reach the host — the connector may be down. Data keeps queuing on this device and delivers when the connector returns.",
            priority: .high,
            payload: [Self.localAlertPayloadKey: Self.connectorOutageAlertKind],
            // Both actions resolve locally (submitAction short-circuits for
            // local items): Acknowledge marks it read, Dismiss removes it.
            primaryAction: InboxActionDescriptor(id: "acknowledge", title: "Acknowledge"),
            secondaryAction: InboxActionDescriptor(id: "dismiss", title: "Dismiss", isDestructive: true)
        )
        localState.localItems.append(item)
        items.insert(item, at: 0)
    }

    /// Remove the connector-down alert — a successful delivery proved the
    /// connector alive. Safe to call when no alert is live.
    func clearConnectorOutageAlert() {
        guard localState.localItems.contains(where: { isConnectorOutageAlert($0) }) else { return }
        localState.localItems.removeAll { isConnectorOutageAlert($0) }
        items.removeAll { isConnectorOutageAlert($0) }
    }

    private func isConnectorOutageAlert(_ item: InboxItem) -> Bool {
        item.payload?[Self.localAlertPayloadKey] == Self.connectorOutageAlertKind
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
            let token = await sessionStore.currentAccessToken()
            let targetID = item.serverID ?? item.id
            let result = try await inboxService.submitAction(
                itemID: targetID,
                actionID: actionID,
                accessToken: token
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

    func reset() {
        items = []
        lastErrorMessage = nil
        localState = InboxLocalState()
        persistence.clearInboxState()
    }
}
