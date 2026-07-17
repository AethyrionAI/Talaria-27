import Foundation
import os

private let provisioningLog = Logger(subsystem: "org.aethyrion.talaria", category: "ProvisioningService")

/// The relay's post-pair provisioning bundle for a host (#116), served by
/// `GET /v1/device/provisioning`. Every field is optional — the relay returns
/// an explicit all-null shape when the connector has reported nothing, and
/// absence stays absence on this side (never fake-configured). The gateway
/// API key is deliberately NOT part of the bundle: adding a key in Uplink
/// stays a manual, human gate (#108).
struct RelayProvisioningDescriptor: Decodable, Equatable {
    var shimBaseURL: String?
    var shimToken: String?
    var gatewayBaseURL: String?

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var normalizedShimBaseURL: String? { Self.normalized(shimBaseURL) }
    var normalizedShimToken: String? { Self.normalized(shimToken) }
    var normalizedGatewayBaseURL: String? { Self.normalized(gatewayBaseURL) }

    var isEmpty: Bool {
        normalizedShimBaseURL == nil && normalizedShimToken == nil && normalizedGatewayBaseURL == nil
    }
}

/// Envelope for the endpoint's `data` payload.
struct DeviceProvisioningResponse: Decodable, Equatable {
    var provisioning: RelayProvisioningDescriptor
    var updatedAt: Date?
}

/// Applies a host's provisioning bundle to a backend profile (#116): shim
/// base URL + shim token (profile-scoped Keychain slot) and the gateway base
/// URL. Fill rules are the whole point, so they live in one place:
///
/// - URLs are only ever FILLED, never overwritten — a manually configured
///   endpoint (custom port, reverse proxy) survives every mode.
/// - The shim token fills when empty; `.refresh` (the explicit user action on
///   the profile card) additionally REPLACES a stored token — that's the
///   rotation path the affordance exists for.
/// - The gateway API key is never touched, in any mode.
@MainActor
final class ProvisioningService {
    enum FillMode: Equatable {
        /// Post-pair auto-fill: empty fields only, manual values are sacred.
        case fillEmptyOnly
        /// User-initiated "Refresh Provisioning": also rotates the shim token.
        case refresh
    }

    struct Outcome: Equatable {
        var filledShimBaseURL = false
        var filledShimToken = false
        var filledGatewayBaseURL = false
        /// The relay answered with the explicit empty shape — the host's
        /// connector has reported no provisioning (e.g. no shim runs there).
        var descriptorWasEmpty = false

        var didFillAnything: Bool { filledShimBaseURL || filledShimToken || filledGatewayBaseURL }

        /// Human summary for the Server screen's notice line.
        func summary(profileName: String) -> String {
            if descriptorWasEmpty {
                return "\(profileName): host reported no provisioning."
            }
            var parts: [String] = []
            if filledShimToken { parts.append("shim token") }
            if filledShimBaseURL { parts.append("shim URL") }
            if filledGatewayBaseURL { parts.append("gateway URL") }
            if parts.isEmpty {
                return "\(profileName): provisioning already up to date."
            }
            return "\(profileName): updated \(parts.joined(separator: ", "))."
        }
    }

    enum ServiceError: LocalizedError, Equatable {
        case profileNotFound
        case notPaired

        var errorDescription: String? {
            switch self {
            case .profileNotFound: "Profile no longer exists."
            case .notPaired: "Pair this profile first — provisioning uses the pairing's relay tokens."
            }
        }
    }

    private let profileResolver: @MainActor (UUID) -> BackendProfile?
    private let upsertProfile: @MainActor (BackendProfile) -> Void
    private let readShimToken: @MainActor (BackendProfile) async -> String?
    private let writeShimToken: @MainActor (String, BackendProfile) async -> Void
    private let fetchDescriptor: @MainActor (BackendProfile) async throws -> RelayProvisioningDescriptor

    init(
        profileResolver: @escaping @MainActor (UUID) -> BackendProfile?,
        upsertProfile: @escaping @MainActor (BackendProfile) -> Void,
        readShimToken: @escaping @MainActor (BackendProfile) async -> String?,
        writeShimToken: @escaping @MainActor (String, BackendProfile) async -> Void,
        fetchDescriptor: @escaping @MainActor (BackendProfile) async throws -> RelayProvisioningDescriptor
    ) {
        self.profileResolver = profileResolver
        self.upsertProfile = upsertProfile
        self.readShimToken = readShimToken
        self.writeShimToken = writeShimToken
        self.fetchDescriptor = fetchDescriptor
    }

    @discardableResult
    func applyProvisioning(profileID: UUID, mode: FillMode) async throws -> Outcome {
        guard let profile = profileResolver(profileID) else {
            throw ServiceError.profileNotFound
        }
        let descriptor = try await fetchDescriptor(profile)

        var outcome = Outcome()
        if descriptor.isEmpty {
            outcome.descriptorWasEmpty = true
            provisioningLog.notice("provisioning: '\(profile.name, privacy: .public)' — host reported no descriptor")
            return outcome
        }

        // Re-resolve after the await: the profile record may have been edited
        // while the fetch was in flight — apply onto the current truth.
        guard var updated = profileResolver(profileID) else {
            throw ServiceError.profileNotFound
        }

        if let shimURL = descriptor.normalizedShimBaseURL,
           (updated.shimBaseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.shimBaseURL = shimURL
            outcome.filledShimBaseURL = true
        }
        if let gatewayURL = descriptor.normalizedGatewayBaseURL,
           updated.gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.gatewayBaseURL = gatewayURL
            outcome.filledGatewayBaseURL = true
        }
        if outcome.filledShimBaseURL || outcome.filledGatewayBaseURL {
            upsertProfile(updated)
        }

        if let token = descriptor.normalizedShimToken {
            let stored = (await readShimToken(updated) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldWrite = stored.isEmpty || (mode == .refresh && stored != token)
            if shouldWrite {
                await writeShimToken(token, updated)
                outcome.filledShimToken = true
            }
        }

        provisioningLog.notice("provisioning: '\(profile.name, privacy: .public)' — \(outcome.summary(profileName: profile.name), privacy: .public)")
        return outcome
    }
}
