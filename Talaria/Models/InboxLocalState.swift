import Foundation

struct InboxLocalState: Codable, Hashable, Sendable {
    var readItemIDs: Set<String> = []
    var dismissedItemIDs: Set<String> = []
    /// #113: app-generated operational alerts (connector-down, etc.) that
    /// never came from the relay. Persisted so an active alert survives a
    /// relaunch mid-outage; merged ahead of fetched rows by InboxStore.
    var localItems: [InboxItem] = []
    /// #251-2A: agent-initiated platform messages received via the talaria
    /// drain. Persisted app-side because the server marks them delivered on
    /// ack — this cache IS the user-facing history. Written only through
    /// `InboxStore.receivePlatformItems`, which keeps the store the single
    /// writer of this whole blob.
    var platformItems: [InboxItem] = []

    enum CodingKeys: String, CodingKey {
        case readItemIDs
        case dismissedItemIDs
        case localItems
        case platformItems
    }
}

// Pre-#113 caches lack `localItems`, pre-#251-2A ones lack `platformItems` —
// decode additively so an existing persisted inbox state never resets
// read/dismissed bookkeeping (the #42 lesson). Encoding stays synthesized.
// The init lives in an extension so the struct keeps its memberwise and
// default initializers.
extension InboxLocalState {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readItemIDs = try container.decodeIfPresent(Set<String>.self, forKey: .readItemIDs) ?? []
        dismissedItemIDs = try container.decodeIfPresent(Set<String>.self, forKey: .dismissedItemIDs) ?? []
        localItems = try container.decodeIfPresent([InboxItem].self, forKey: .localItems) ?? []
        platformItems = try container.decodeIfPresent([InboxItem].self, forKey: .platformItems) ?? []
    }
}
