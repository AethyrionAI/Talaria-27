import Foundation
import Testing
@testable import Talaria

/// #260(A) — the Revoke/Reset row's honesty matrix.
///
/// The defect this pins against: the row used to read ONLY the app's
/// collection flag and claim ACTIVE while iOS had never granted (or never
/// been asked for) the underlying permission — a flag displayed as a state.
/// `RevokeRowState.compute` is the single pure source the row renders from:
/// ACTIVE requires the flag AND an iOS authorization; every other cell names
/// its real state and offers the action that actually unblocks it.
///
/// Health nuance, recorded here on purpose: HealthKit hides read-grant
/// status by design, so `LiveHealthService` can only report "a request
/// completed this launch" (`.authorized`) or "not confirmed this launch"
/// (`.notDetermined`). The matrix is honest against what iOS lets us KNOW —
/// `.notDetermined` renders as needs-permission, whose action re-requests
/// and resolves silently when the grant already exists.
@MainActor
struct RevokeRowStateTests {

    private static let authorizedFamily: [PermissionStatus] = [
        .authorized, .authorizedWhenInUse, .authorizedAlways, .limited,
    ]
    private static let ungrantedFamily: [PermissionStatus] = [
        .notDetermined, .denied, .restricted,
    ]

    // MARK: - The matrix

    @Test func activeRequiresFlagAndIOSAuthorization() {
        for status in Self.authorizedFamily {
            #expect(RevokeRowState.compute(flagOn: true, iosStatus: status) == .active)
        }
    }

    /// 260-A's core sentence: with iOS not granted, the row NEVER reads
    /// ACTIVE — no matter what the app flag says.
    @Test func ungrantedIOSNeverReadsActive() {
        for status in Self.ungrantedFamily {
            let state = RevokeRowState.compute(flagOn: true, iosStatus: status)
            #expect(state != .active)
            #expect(state.statusLabel != "ACTIVE")
        }
    }

    @Test func flagOffIsOffRegardlessOfIOS() {
        for status in Self.authorizedFamily + Self.ungrantedFamily {
            #expect(RevokeRowState.compute(flagOn: false, iosStatus: status) == .off)
        }
    }

    @Test func flagOnWithoutTheIOSAskIsNeedsPermission() {
        #expect(RevokeRowState.compute(flagOn: true, iosStatus: .notDetermined) == .needsPermission)
    }

    @Test func flagOnAgainstAnIOSDenialIsBlocked() {
        #expect(RevokeRowState.compute(flagOn: true, iosStatus: .denied) == .blockedByIOS)
        #expect(RevokeRowState.compute(flagOn: true, iosStatus: .restricted) == .blockedByIOS)
    }

    @Test func unsupportedHardwareIsUnavailableEitherWay() {
        #expect(RevokeRowState.compute(flagOn: true, iosStatus: .unsupported) == .unavailable)
        #expect(RevokeRowState.compute(flagOn: false, iosStatus: .unsupported) == .unavailable)
    }

    // MARK: - Words and actions match the state (260-A: "names the real
    // state and offers the action that matches")

    @Test func labelsNameTheRealState() {
        #expect(RevokeRowState.off.statusLabel == "OFF")
        #expect(RevokeRowState.active.statusLabel == "ACTIVE")
        #expect(RevokeRowState.needsPermission.statusLabel == "NEEDS PERMISSION")
        #expect(RevokeRowState.blockedByIOS.statusLabel == "OFF IN iOS")
        #expect(RevokeRowState.unavailable.statusLabel == "—")
    }

    @Test func eachStateOffersTheActionThatActuallyUnblocksIt() {
        #expect(RevokeRowState.off.action == .enableCollection)
        #expect(RevokeRowState.active.action == .revoke)
        #expect(RevokeRowState.needsPermission.action == .requestPermission)
        #expect(RevokeRowState.blockedByIOS.action == .openSystemSettings)
        #expect(RevokeRowState.unavailable.action == nil)
    }

    @Test func onlyActiveOffersRevoke() {
        let states: [RevokeRowState] = [.off, .needsPermission, .blockedByIOS, .unavailable]
        for state in states {
            #expect(state.action != .revoke)
        }
    }

    // MARK: - Both sensors ride the same matrix

    @Test func revocablePermissionsMapToTheirIOSPermissionTypes() {
        #expect(RevocablePermission.health.permissionType == .health)
        #expect(RevocablePermission.location.permissionType == .location)
        #expect(RevocablePermission.allCases.count == 2)
    }
}
