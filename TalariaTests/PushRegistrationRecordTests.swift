import Foundation
import Testing
@testable import Talaria

/// #146 — the Diagnostics push row sat on TOKEN HELD · AWAITING RELAY while a
/// push from OJAMD demonstrably DELIVERED (confirmed on device 2026-07-20).
///
/// The cause was two records of one fact. `AppSessionState` carried a
/// `pushTokenRegistered` Bool (what both Settings screens rendered) AND, since
/// #133/PR #123, a `registeredPushToken` String consulted by the
/// skip-on-exact-match policy. Whenever those two disagreed the UI lied, and a
/// skip guaranteed no future POST would ever correct it.
///
/// The Bool is now DERIVED from the token, so they cannot disagree. These
/// tests pin that property rather than any one of the paths that used to
/// diverge.
struct PushRegistrationRecordTests {

    @Test func registrationIsExactlyWhetherATokenIsRecorded() {
        #expect(AppSessionState().pushTokenRegistered == false)
        #expect(AppSessionState(registeredPushToken: "tok-a").pushTokenRegistered)

        // The state is a value type and the flag has no setter, so there is
        // no longer any way to write one field without the other.
        var state = AppSessionState(registeredPushToken: "tok-a")
        state.registeredPushToken = nil
        #expect(state.pushTokenRegistered == false)
    }

    /// The pipeline row is a COMPARISON now — held token vs acked token.
    @MainActor private func pipelineState(held: String?, recorded: String?) -> AppContainer.PushTokenPipelineState {
        AppContainer.pushTokenPipelineState(heldToken: held, recordedToken: recorded)
    }

    @Test @MainActor func theRowFollowsTheRecordedToken() {
        // No APNs token from iOS at all.
        #expect(pipelineState(held: nil, recorded: nil) == .notIssued)

        // Held, nothing acked — the honest awaiting state.
        #expect(pipelineState(held: "tok-a", recorded: nil) == .awaitingRelay)

        // Held and acked — #146's observed case. The old Bool could sit false
        // here forever against a live server-side registration; the token
        // comparison cannot.
        #expect(pipelineState(held: "tok-a", recorded: "tok-a") == .registered)

        // A rotated token invalidates the old ack. The old Bool stayed TRUE
        // through this — the opposite lie, and the one that would have
        // suppressed a needed re-registration.
        #expect(pipelineState(held: "tok-b", recorded: "tok-a") == .awaitingRelay)

        // A record with no local token is not "registered" — there is nothing
        // it could be registered for.
        #expect(pipelineState(held: nil, recorded: "tok-a") == .notIssued)
    }

    /// The skip is the path that stranded the row: a launch that restores a
    /// matching token skips the POST by design. Under one record, the value
    /// the skip CONSULTS is the value the UI RENDERS, so a skip is
    /// self-confirming.
    @Test @MainActor func skippingTheRegistrationPostKeepsTheRowTruthful() {
        let state = AppSessionState(registeredPushToken: "tok-a")

        #expect(
            DormantPushRegistrationPolicy.shouldRegister(
                recordedToken: state.registeredPushToken,
                currentToken: "tok-a"
            ) == false
        )
        // Same field, so skipping cannot leave the row behind.
        #expect(pipelineState(held: "tok-a", recorded: state.registeredPushToken) == .registered)

        // And a cleared record re-registers rather than sitting silently.
        let cleared = AppSessionState()
        #expect(
            DormantPushRegistrationPolicy.shouldRegister(
                recordedToken: cleared.registeredPushToken,
                currentToken: "tok-a"
            )
        )
        #expect(pipelineState(held: "tok-a", recorded: cleared.registeredPushToken) == .awaitingRelay)
    }

    /// Pre-#146 blobs carry only the Bool. They must decode without throwing
    /// and read as "not registered" — the next foreground's
    /// `registerPushTokenIfNeeded` re-registers and records the token, so the
    /// state self-heals in one launch.
    @Test func legacyPersistedStateDecodesAsUnregistered() throws {
        let legacy = """
        {
          "installationID": "\(UUID().uuidString)",
          "deviceRegistered": true,
          "connectionStatus": "connected",
          "syncStatus": "synced",
          "isMockMode": false,
          "backendEndpoint": "http://relay:8000/v1",
          "pushTokenRegistered": true
        }
        """
        let decoded = try JSONDecoder().decode(AppSessionState.self, from: Data(legacy.utf8))
        #expect(decoded.registeredPushToken == nil)
        #expect(decoded.pushTokenRegistered == false)
        #expect(decoded.deviceRegistered)
    }

    /// Round-tripping must not resurrect a second field.
    @Test func encodedStateCarriesOnlyTheTokenRecord() throws {
        let encoded = try JSONEncoder().encode(AppSessionState(registeredPushToken: "tok-a"))
        let json = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(json["registeredPushToken"] as? String == "tok-a")
        #expect(json["pushTokenRegistered"] == nil)
    }
}
