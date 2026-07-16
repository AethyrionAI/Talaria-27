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
    /// Hermes Sessions API base URL, e.g. "http://ojamd:8642".
    var gatewayBaseURL: String
    /// Relay base URL including `/v1`, e.g. "http://ojamd:8000/v1".
    var relayBaseURL: String
    /// Talaria models-shim base URL, e.g. "http://ojamd:8765". Optional — a
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

    init(
        id: UUID = UUID(),
        name: String,
        gatewayBaseURL: String,
        relayBaseURL: String,
        shimBaseURL: String? = nil,
        note: String? = nil,
        usesLegacyCredentialKeys: Bool = false,
        lastTokenRefreshAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.gatewayBaseURL = gatewayBaseURL
        self.relayBaseURL = relayBaseURL
        self.shimBaseURL = shimBaseURL
        self.note = note
        self.usesLegacyCredentialKeys = usesLegacyCredentialKeys
        self.lastTokenRefreshAt = lastTokenRefreshAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case gatewayBaseURL
        case relayBaseURL
        case shimBaseURL
        case note
        case usesLegacyCredentialKeys
        case lastTokenRefreshAt
    }

    /// Hand-written so future additive fields decode tolerantly — a decode
    /// failure here would read as "no profiles" and re-run the migration.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Backend"
        gatewayBaseURL = try container.decodeIfPresent(String.self, forKey: .gatewayBaseURL) ?? ""
        relayBaseURL = try container.decodeIfPresent(String.self, forKey: .relayBaseURL) ?? ""
        shimBaseURL = try container.decodeIfPresent(String.self, forKey: .shimBaseURL)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        usesLegacyCredentialKeys = try container.decodeIfPresent(Bool.self, forKey: .usesLegacyCredentialKeys) ?? false
        lastTokenRefreshAt = try container.decodeIfPresent(Date.self, forKey: .lastTokenRefreshAt)
    }

    /// The scope under which this profile's credentials are keyed: nil means
    /// the legacy (pre-profile) keys — see `BackendProfileScopedKeys`.
    var credentialScopeID: UUID? {
        usesLegacyCredentialKeys ? nil : id
    }
}

/// The persisted profile set. Stored as ONE blob (UserDefaults primary +
/// Keychain mirror, the #41 pattern) so the profile UUIDs — which key every
/// per-profile credential — survive clean reinstalls together with the
/// credentials they scope.
///
/// `activeProfileID` / `sensorDestinationProfileID` live HERE rather than on
/// `UserSettings`: splitting them from the profile list would let a reinstall
/// recover the profiles but lose which one is active / owns the sensors.
struct BackendProfilesState: Codable, Hashable, Sendable {
    var profiles: [BackendProfile] = []
    /// Default target for NEW sessions and the relay-plane interactive
    /// surfaces (device files, inbox polling, talk).
    var activeProfileID: UUID?
    /// Where the sensor outbox drains — pinned independently of the active
    /// profile so production context never goes dark on a switch (M-8).
    var sensorDestinationProfileID: UUID?

    private enum CodingKeys: String, CodingKey {
        case profiles
        case activeProfileID
        case sensorDestinationProfileID
    }

    init(
        profiles: [BackendProfile] = [],
        activeProfileID: UUID? = nil,
        sensorDestinationProfileID: UUID? = nil
    ) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.sensorDestinationProfileID = sensorDestinationProfileID
    }

    /// Tolerant decode — same rationale as `BackendProfile`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decodeIfPresent([BackendProfile].self, forKey: .profiles) ?? []
        activeProfileID = try container.decodeIfPresent(UUID.self, forKey: .activeProfileID)
        sensorDestinationProfileID = try container.decodeIfPresent(UUID.self, forKey: .sensorDestinationProfileID)
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
    /// Relay session tokens (Keychain, `AppSessionStore`).
    static func accessToken(_ scope: UUID?) -> String { scoped("session.accessToken", scope) }
    static func refreshToken(_ scope: UUID?) -> String { scoped("session.refreshToken", scope) }
    /// Hermes Sessions API bearer key (Keychain, chat + shim fallback auth).
    static func gatewayAPIKey(_ scope: UUID?) -> String { scoped("hermes.apiServerKey", scope) }
    /// Dedicated models-shim token (Keychain, legacy/manual override).
    static func shimToken(_ scope: UUID?) -> String { scoped("talaria.modelsShimToken", scope) }
    /// Paired relay configuration (UserDefaults + Keychain mirror, #41).
    static func pairedRelayConfiguration(_ scope: UUID?) -> String { scoped("hermes.pairedRelayConfiguration", scope) }
    /// Relay session state (UserDefaults, `AppSessionStore.state`).
    static func sessionState(_ scope: UUID?) -> String { scoped("hermes.sessionState", scope) }

    private static func scoped(_ base: String, _ scope: UUID?) -> String {
        guard let scope else { return base }
        return "\(base).\(scope.uuidString)"
    }
}
