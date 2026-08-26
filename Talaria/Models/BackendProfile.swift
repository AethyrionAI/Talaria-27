import Foundation

/// One named backend host (Lane M / OPEN_ITEMS #114): a Hermes installation
/// the phone can talk to — gateway (Sessions API, `:8642`), relay (`:8000/v1`,
/// sensors + pairing + push), and models shim (`:8765`) — e.g. "OJAMD"
/// (Windows production) or "Mac Mini" (Apple ecosystem / Xcode / iMessage).
///
/// The profile record carries the ENDPOINTS only. Credentials (relay tokens,
/// gateway API key, shim token) and the per-profile pairing record live in
/// the Keychain / persistence under profile-scoped keys derived by
/// `BackendProfileScopedKeys`, so pairing or re-keying one profile can never
/// touch another's slot (the #94/#3 clean-slate stays scoped to one host).
struct BackendProfile: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    /// Hermes Sessions API base URL, e.g. "http://your-host:8642".
    var gatewayBaseURL: String
    // **`relayBaseURL` is DELETED (#309 Lane B, Owen's ruling 3).** #310 made
    // it optional so a gateway-only profile could exist; every profile is one
    // now, and the last reader of the relay plane went with `PairingStore`.
    // A persisted blob that still carries the key decodes fine and the value
    // is simply ignored — `init(from:)` never asks for it — so there is no
    // migration and no state to rewrite.
    /// Talaria models-shim base URL, e.g. "http://your-host:8765". Optional — a
    /// profile without a shim simply exposes no model picker.
    var shimBaseURL: String?
    /// Free text, e.g. "Apple ecosystem / Xcode / iMessage".
    var note: String?
    /// True only for the profile the one-shot migration minted from the
    /// pre-profile configuration: its credentials stay under the ORIGINAL
    /// (unscoped) Keychain/persistence keys instead of being renamed to
    /// profile-scoped ones. Mapping instead of copying is what makes the
    /// migration unable to strand an existing pairing (#41): even if the
    /// profile list itself were lost, re-migration re-adopts the same keys.
    var usesLegacyCredentialKeys: Bool
    /// When this profile's relay tokens were last known refreshed (M-9):
    /// dormant profiles get an opportunistic refresh so the 30-day refresh
    /// TTL never strands one. Stamped on pair and on dormant refresh; the
    /// ACTIVE profile's tokens rotate organically, so its stamp may lag —
    /// worst case is one redundant cheap refresh after a switch.
    var lastTokenRefreshAt: Date?
    /// #223 Lane 5: the profile's model pick — sent on every chat turn as a
    /// per-turn lock (provider + model + require_model_lock). Both nil =
    /// follow the host default (no model fields on the wire). Optional-only
    /// so old persisted blobs decode and old builds tolerate new blobs.
    var selectedModelProvider: String?
    var selectedModelID: String?

    init(
        id: UUID = UUID(),
        name: String,
        gatewayBaseURL: String,
        shimBaseURL: String? = nil,
        note: String? = nil,
        usesLegacyCredentialKeys: Bool = false,
        lastTokenRefreshAt: Date? = nil,
        selectedModelProvider: String? = nil,
        selectedModelID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.gatewayBaseURL = gatewayBaseURL
        self.shimBaseURL = shimBaseURL
        self.note = note
        self.usesLegacyCredentialKeys = usesLegacyCredentialKeys
        self.lastTokenRefreshAt = lastTokenRefreshAt
        self.selectedModelProvider = selectedModelProvider
        self.selectedModelID = selectedModelID
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case gatewayBaseURL
        case shimBaseURL
        case note
        case usesLegacyCredentialKeys
        case lastTokenRefreshAt
        case selectedModelProvider
        case selectedModelID
    }

    /// Hand-written so future additive fields decode tolerantly — a decode
    /// failure here would read as "no profiles" and re-run the migration.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Backend"
        gatewayBaseURL = try container.decodeIfPresent(String.self, forKey: .gatewayBaseURL) ?? ""
        // #309 Lane B: the `relayBaseURL` key is not read. An old blob still
        // carries it; `Codable` ignores unknown keys, and re-encoding drops it.
        shimBaseURL = try container.decodeIfPresent(String.self, forKey: .shimBaseURL)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        usesLegacyCredentialKeys = try container.decodeIfPresent(Bool.self, forKey: .usesLegacyCredentialKeys) ?? false
        lastTokenRefreshAt = try container.decodeIfPresent(Date.self, forKey: .lastTokenRefreshAt)
        selectedModelProvider = try container.decodeIfPresent(String.self, forKey: .selectedModelProvider)
        selectedModelID = try container.decodeIfPresent(String.self, forKey: .selectedModelID)
    }

    /// The scope under which this profile's credentials are keyed: nil means
    /// the legacy (pre-profile) keys — see `BackendProfileScopedKeys`.
    var credentialScopeID: UUID? {
        usesLegacyCredentialKeys ? nil : id
    }

    /// **#384-C: does this profile have a gateway at all?**
    ///
    /// The ONE spelling of the gateway-plane gate, added for the same reason
    /// #310 added `hasRelay` above — *"a gate with two spellings is a gate with
    /// a hole."* Three call sites were already testing
    /// `gatewayBaseURL.isEmpty == false` by hand, which is two spellings of a
    /// predicate that is about to become load-bearing: with #384 shipping no
    /// default host, **the empty case stops being an edge and becomes every
    /// fresh install's first state.**
    ///
    /// A profile with no gateway is not broken. Talaria is local-brain-first
    /// and Hermes is the optional upgrade tier, so this is the normal state
    /// until the user adds a host.
    var hasGateway: Bool {
        gatewayBaseURL.isEmpty == false
    }

    /// The gateway base URL, normalized to nil when empty — what a
    /// gateway-plane caller actually wants. Mirrors `resolvedRelayBaseURL`.
    var resolvedGatewayBaseURL: String? {
        hasGateway ? gatewayBaseURL : nil
    }
}

/// The persisted profile set. Stored as ONE blob (UserDefaults primary +
/// Keychain mirror, the #41 pattern) so the profile UUIDs — which key every
/// per-profile credential — survive clean reinstalls together with the
/// credentials they scope.
///
/// `activeProfileID` lives HERE rather than on `UserSettings`: splitting it
/// from the profile list would let a reinstall recover the profiles but lose
/// which one is active. (#352 removed `sensorDestinationProfileID` — the M-8
/// sensor-destination pin — with the upload pipeline; old blobs carrying the
/// key decode fine, the value is simply ignored.)
struct BackendProfilesState: Codable, Hashable, Sendable {
    var profiles: [BackendProfile] = []
    /// Default target for NEW sessions and the relay-plane interactive
    /// surfaces (device files, inbox polling, talk).
    var activeProfileID: UUID?

    private enum CodingKeys: String, CodingKey {
        case profiles
        case activeProfileID
    }

    init(
        profiles: [BackendProfile] = [],
        activeProfileID: UUID? = nil
    ) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
    }

    /// Tolerant decode — same rationale as `BackendProfile`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decodeIfPresent([BackendProfile].self, forKey: .profiles) ?? []
        activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
    }

    func profile(id: UUID?) -> BackendProfile? {
        guard let id else { return nil }
        return profiles.first { $0.id == id }
    }

    var activeProfile: BackendProfile? {
        profile(id: activeProfileID) ?? profiles.first
    }
}

/// Derives the per-profile storage keys for everything credential-shaped.
/// A nil scope resolves to the ORIGINAL pre-profile key strings — the
/// migrated first profile keeps them (see
/// `BackendProfile.usesLegacyCredentialKeys`), which is what makes the
/// profile migration byte-identical for existing installs: no Keychain entry
/// moves, no persisted state is rewritten.
enum BackendProfileScopedKeys {
    // **The four slots below are PURGE-ONLY since #309 Lane B (bar 309-B9).**
    // Nothing writes or reads them; they are named here so
    // `RelayCredentialHygiene` can enumerate the residue by its real key
    // strings instead of reconstructing them, and so a reader can see at a
    // glance which of this namespace is dead. Deleting the names would make
    // the purge a set of string literals — the shape that goes stale silently.
    /// Relay session tokens (Keychain) — written by the deleted `AppSessionStore`.
    static func accessToken(_ scope: UUID?) -> String { scoped("session.accessToken", scope) }
    static func refreshToken(_ scope: UUID?) -> String { scoped("session.refreshToken", scope) }
    /// Hermes Sessions API bearer key (Keychain, chat + shim fallback auth).
    static func gatewayAPIKey(_ scope: UUID?) -> String { scoped("hermes.apiServerKey", scope) }
    /// Dedicated models-shim token (Keychain, legacy/manual override).
    static func shimToken(_ scope: UUID?) -> String { scoped("talaria.modelsShimToken", scope) }
    /// #251-2A: the talaria-platform device token minted by auto-pair.
    static func talariaDeviceToken(_ scope: UUID?) -> String { scoped("talaria.platformDeviceToken", scope) }
    /// The device id issued alongside the token above — same slot family
    /// (this key plus the ".deviceID" suffix), named here rather than
    /// derived inline at the call site so a future purge (#251-2A Task 11)
    /// can enumerate both halves of the credential from this namespace
    /// instead of reconstructing the suffix by hand.
    static func talariaDeviceID(_ scope: UUID?) -> String { talariaDeviceToken(scope) + ".deviceID" }
    /// Paired relay configuration (UserDefaults + Keychain mirror, #41) —
    /// purge-only, see above.
    static func pairedRelayConfiguration(_ scope: UUID?) -> String { scoped("hermes.pairedRelayConfiguration", scope) }
    /// Relay session state (UserDefaults) — purge-only, see above.
    static func sessionState(_ scope: UUID?) -> String { scoped("hermes.sessionState", scope) }

    private static func scoped(_ base: String, _ scope: UUID?) -> String {
        guard let scope else { return base }
        return "\(base).\(scope.uuidString)"
    }
}
