import Foundation
import Testing
@testable import Talaria

/// #58 — the Control Center → app launch handoff surface. Since 2026-07-27
/// this is the FALLBACK lane: the control intents perform in the app process
/// (`allowedExecutionTargets = .main`) and route directly, and this store is
/// written only by their extension-compiled branch — i.e. only if the OS
/// performs in the widget process anyway. The contract tested here keeps
/// mattering exactly as long as that branch exists; when a device pass
/// proves `.main` holds and the store is deleted, this suite goes with it.
///
/// Two processes can share this store, so its contract is the whole lane: what
/// is written must read back, exactly once, and only while it is still about
/// the launch that is happening now. These tests drive a throwaway
/// `UserDefaults` suite rather than the app group — the production suite is
/// entitlement-gated and shared across the test host, so it would neither be
/// hermetic nor prove anything the injected suite doesn't.
struct ControlHandoffTests {

    /// Fixed reference instant — every staleness assertion is relative to it,
    /// so none of these tests depend on wall-clock timing.
    private static let t0 = Date(timeIntervalSince1970: 1_753_400_000)

    /// Runs `body` against a private, throwaway suite, removed afterwards so
    /// nothing leaks into the next test or the next run.
    private func withStore(
        stalenessWindow: TimeInterval = ControlHandoffStore.defaultStalenessWindow,
        _ body: (ControlHandoffStore, UserDefaults) throws -> Void
    ) throws {
        let suiteName = "ControlHandoffTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(
            ControlHandoffStore(defaults: defaults, stalenessWindow: stalenessWindow),
            defaults
        )
    }

    // MARK: - Round trip

    @Test func writtenDestinationReadsBack() throws {
        try withStore { store, _ in
            store.writeDestination(URL(string: "talaria://voice")!, now: Self.t0)
            #expect(store.consumeDestination(now: Self.t0.addingTimeInterval(1))
                == URL(string: "talaria://voice"))
        }
    }

    /// Consume-once is the load-bearing half. A destination left behind
    /// re-routes the NEXT launch: tap the Talk control, quit, reopen from the
    /// home screen, and the app yanks you into voice for no reason.
    @Test func destinationIsConsumedExactlyOnce() throws {
        try withStore { store, _ in
            store.writeDestination(URL(string: "talaria://chat")!, now: Self.t0)
            #expect(store.consumeDestination(now: Self.t0) != nil)
            #expect(store.consumeDestination(now: Self.t0) == nil)
        }
    }

    /// On the expected `.main` path nothing is ever written here, and every
    /// launch from the home screen reads this store too. Absence is the
    /// COMMON case and must route nowhere — never to a default destination.
    @Test func absentDestinationRoutesNowhere() throws {
        try withStore { store, _ in
            #expect(store.consumeDestination(now: Self.t0) == nil)
        }
    }

    // MARK: - Staleness

    /// A destination stranded by a launch that never arrived (app swiped away
    /// before the scene activated, extension write with no consumer) must not
    /// hijack an unrelated launch later.
    @Test func destinationOlderThanTheWindowIsIgnored() throws {
        try withStore(stalenessWindow: 30) { store, _ in
            store.writeDestination(URL(string: "talaria://chat")!, now: Self.t0)
            #expect(store.consumeDestination(now: Self.t0.addingTimeInterval(31)) == nil)
        }
    }

    /// The window is inclusive — a launch that lands exactly at the boundary
    /// is the launch this destination was written for.
    @Test func destinationAtTheWindowEdgeStillRoutes() throws {
        try withStore(stalenessWindow: 30) { store, _ in
            store.writeDestination(URL(string: "talaria://chat")!, now: Self.t0)
            #expect(store.consumeDestination(now: Self.t0.addingTimeInterval(30))
                == URL(string: "talaria://chat"))
        }
    }

    /// Expiring is not the same as clearing: a stale read must still empty the
    /// store, or the destination sits there until some later read happens to
    /// fall inside the window and routes then.
    @Test func staleDestinationIsClearedNotStranded() throws {
        try withStore(stalenessWindow: 30) { store, _ in
            store.writeDestination(URL(string: "talaria://voice")!, now: Self.t0)
            #expect(store.consumeDestination(now: Self.t0.addingTimeInterval(31)) == nil)
            // A subsequent read well inside the window finds nothing, because
            // the stale read consumed it.
            #expect(store.consumeDestination(now: Self.t0.addingTimeInterval(1)) == nil)
        }
    }

    // MARK: - Tolerance

    /// The timestamp is written FIRST, so a destination without one can only
    /// come from a torn or foreign write. Refuse it — routing on a value we
    /// can't date is exactly the stranded-destination failure above.
    @Test func destinationWithoutATimestampIsIgnored() throws {
        try withStore { store, defaults in
            defaults.set("talaria://voice", forKey: ControlHandoffStore.destinationKey)
            #expect(store.consumeDestination(now: Self.t0) == nil)
            // …and it is cleared, so it can't resurface.
            #expect(defaults.string(forKey: ControlHandoffStore.destinationKey) == nil)
        }
    }

    /// `handleDeeplink` is the router and owns scheme/host policy, but a value
    /// that isn't a URL at all can't reach it — the store drops it and clears.
    ///
    /// The empty string is the fixture because it is the one this SDK's
    /// `URL(string:)` actually rejects: iOS 27's RFC-3986 parser accepts far
    /// more than it looks like it should (`URL(string: "not a url")` is
    /// non-nil — that fixture was tried and failed here). Anything that parses
    /// but isn't ours still dies at `handleDeeplink`'s scheme guard.
    @Test func unparseableDestinationIsIgnored() throws {
        try withStore { store, defaults in
            defaults.set(Self.t0.timeIntervalSince1970, forKey: ControlHandoffStore.writtenAtKey)
            defaults.set("", forKey: ControlHandoffStore.destinationKey)
            #expect(store.consumeDestination(now: Self.t0) == nil)
            #expect(defaults.string(forKey: ControlHandoffStore.destinationKey) == nil)
        }
    }
}
