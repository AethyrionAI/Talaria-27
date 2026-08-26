import Foundation

/// **#309 Lane C shrank this protocol from three methods to one (2026-08-25).**
///
/// `createEnrollmentCode` (row 8) and `revokeCurrentHost` (row 9) were both
/// relay verbs about the relay's ENROLLMENT record — a host registering itself
/// with the relay so the phone could ask a third party about it. Their
/// disposition was DELETE, and they dissolve with the pairing they served: the
/// gateway IS the host under #251/#269, so there is nothing to enrol and
/// nothing to unregister. Forgetting a host is local ("forget the key"), which
/// is what `PairingStore.disconnect()` already does.
///
/// The surviving method also lost its `accessToken:` parameter: it carried the
/// relay's session token, and the gateway implementation resolves the profile's
/// own credentials itself (the `SkillsService`/`CronJobService` seam).
@MainActor
protocol HermesHostServiceProtocol {
    func fetchCurrentHost() async throws -> HermesHostStatus?
}
