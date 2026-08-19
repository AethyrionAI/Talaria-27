import Foundation
import Testing
@testable import Talaria

/// #283 armed this switch OFF; **#368 (3E) flipped it ON** and added the
/// one-time migration that makes the flip actually reach existing installs.
///
/// Bar 3E-A lives here. Its load-bearing half is the SECOND test: the key is
/// unconditionally encoded (`UserSettings.encode`), so every install that has
/// ever written settings carries an explicit `false`, and a default flip
/// alone would move nobody.
struct RunsTransportSwitchTests {

    /// A settings blob as a PRE-CUTOVER build wrote it: `useRunsTransport`
    /// present and false, `runsCutoverApplied` absent entirely.
    private func preCutoverBlob(useRunsTransport: Bool = false) throws -> Data {
        let current = try JSONEncoder().encode(UserSettings())
        var obj = try #require(JSONSerialization.jsonObject(with: current) as? [String: Any])
        obj["useRunsTransport"] = useRunsTransport
        obj.removeValue(forKey: "runsCutoverApplied")
        return try JSONSerialization.data(withJSONObject: obj)
    }

    @Test func aFreshInstallIsOnTheRunsPlane() throws {
        #expect(UserSettings().useRunsTransport == true)
        #expect(UserSettings().runsCutoverApplied == true)
    }

    @Test func aPreCutoverBlobsExplicitFalseIsTheOldDefaultAndIsMigrated() throws {
        // 3E-A, the half that matters. Mutation that turns this red: decode
        // `useRunsTransport` with `?? true` and no migration flag — the
        // stored `false` then wins and the cutover ships as a no-op for
        // every existing install.
        let decoded = try JSONDecoder().decode(UserSettings.self, from: preCutoverBlob())
        #expect(decoded.useRunsTransport == true)
        #expect(decoded.runsCutoverApplied == true, "the migration must stamp itself as done")
    }

    @Test func aPreCutoverBlobThatAlreadyOptedInStaysOptedIn() throws {
        let decoded = try JSONDecoder().decode(UserSettings.self, from: preCutoverBlob(useRunsTransport: true))
        #expect(decoded.useRunsTransport == true)
    }

    @Test func aBlobMissingTheKeyEntirelyLandsOnTheRunsPlane() throws {
        let current = try JSONEncoder().encode(UserSettings())
        var obj = try #require(JSONSerialization.jsonObject(with: current) as? [String: Any])
        obj.removeValue(forKey: "useRunsTransport")
        obj.removeValue(forKey: "runsCutoverApplied")
        let decoded = try JSONDecoder().decode(
            UserSettings.self,
            from: try JSONSerialization.data(withJSONObject: obj)
        )
        #expect(decoded.useRunsTransport == true)
    }

    /// The escape hatch Owen's 2026-08-19 ruling kept has to be a REAL
    /// switch, not a control the migration overrides on every launch — or
    /// the week of evidence it was kept for cannot be collected.
    ///
    /// Mutation that turns this red: force `true` unconditionally in
    /// `init(from:)` instead of gating on `runsCutoverApplied`.
    @Test func aPostCutoverOptOutSticksAcrossRelaunch() throws {
        var settings = try JSONDecoder().decode(UserSettings.self, from: preCutoverBlob())
        settings.useRunsTransport = false            // the user turns it back off
        let persisted = try JSONEncoder().encode(settings)

        let reloaded = try JSONDecoder().decode(UserSettings.self, from: persisted)
        #expect(reloaded.useRunsTransport == false, "the migration must not re-apply over a user's pick")

        // …and a second relaunch does not resurrect it either.
        let reloadedTwice = try JSONDecoder().decode(
            UserSettings.self,
            from: try JSONEncoder().encode(reloaded)
        )
        #expect(reloadedTwice.useRunsTransport == false)
    }

    @Test func roundTripsBothWays() throws {
        for value in [true, false] {
            var settings = UserSettings()
            settings.useRunsTransport = value
            let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
            #expect(decoded.useRunsTransport == value)
        }
    }
}
