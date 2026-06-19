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
    private let allowDemoFallback: Bool
    private var localState: InboxLocalState {
        didSet { persistence.saveInboxState(localState) }
    }

    init(
        inboxService: any InboxServiceProtocol,
        persistence: any AppPersistenceStoreProtocol,
        sessionStore: AppSessionStore,
        allowDemoFallback: Bool = true
    ) {
        self.inboxService = inboxService
        self.persistence = persistence
        self.sessionStore = sessionStore
        self.allowDemoFallback = allowDemoFallback
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
            items = applyLocalState(to: fetchedItems)
        } catch {
            lastErrorMessage = error.localizedDescription
            items = allowDemoFallback ? applyLocalState(to: DemoData.sampleInboxItems) : []
        }
    }

    func performPrimaryAction(for item: InboxItem) async {
        let actionID = item.primaryAction?.id ?? "approve"
        await submitAction(for: item, actionID: actionID)
    }

    func dismiss(_ item: InboxItem) async {
        await submitAction(for: item, actionID: item.secondaryAction?.id ?? "dismiss")
    }

    private func submitAction(for item: InboxItem, actionID: String) async {
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
