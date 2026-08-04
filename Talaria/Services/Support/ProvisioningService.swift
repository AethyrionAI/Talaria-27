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
    /// #223 Lane 5: the shim retired — these two decode tolerantly (old relays
    /// still send them) and are IGNORED on apply.
    var shimBaseURL: String?
    var shimToken: String?
    var gatewayBaseURL: String?

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    var normalizedGatewayBaseURL: String? { Self.normalized(gatewayBaseURL) }

    /// Nothing the app still consumes (#223 Lane 5: shim fields don't count).
    var isEmpty: Bool { normalizedGatewayBaseURL == nil }
}

/// Envelope for the endpoint's `data` payload.
struct DeviceProvisioningResponse: Decodable, Equatable {
    var provisioning: RelayProvisioningDescriptor
    var updatedAt: Date?
}

/// Applies a host's provisioning bundle to a backend profile (#116, reduced
/// by #223 Lane 5 to the gateway base URL — the shim fields are tolerated and
/// ignored). Fill rules live in one place:
///
/// - URLs are only ever FILLED, never overwritten — a manually configured
///   endpoint (custom port, reverse proxy) survives every mode.
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
        var filledGatewayBaseURL = false
        /// The relay reported nothing the app still consumes.
        var descriptorWasEmpty = false

        var didFillAnything: Bool { filledGatewayBaseURL }

        /// Human summary for the Server screen's notice line.
        func summary(profileName: String) -> String {
            if descriptorWasEmpty {
                return "\(profileName): host reported no gateway provisioning."
            }
            if filledGatewayBaseURL {
                return "\(profileName): updated gateway URL."
            }
            return "\(profileName): provisioning already up to date."
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
    private let fetchDescriptor: @MainActor (BackendProfile) async throws -> RelayProvisioningDescriptor

    init(
        profileResolver: @escaping @MainActor (UUID) -> BackendProfile?,
        upsertProfile: @escaping @MainActor (BackendProfile) -> Void,
        fetchDescriptor: @escaping @MainActor (BackendProfile) async throws -> RelayProvisioningDescriptor
    ) {
        self.profileResolver = profileResolver
        self.upsertProfile = upsertProfile
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

        if let gatewayURL = descriptor.normalizedGatewayBaseURL,
           updated.gatewayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.gatewayBaseURL = gatewayURL
            outcome.filledGatewayBaseURL = true
            upsertProfile(updated)
        }

        provisioningLog.notice("provisioning: '\(profile.name, privacy: .public)' — \(outcome.summary(profileName: profile.name), privacy: .public)")
        return outcome
    }
}
