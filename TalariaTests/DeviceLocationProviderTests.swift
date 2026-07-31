import CoreLocation
import Foundation
import Testing
import UIKit
@testable import Talaria

/// #203 (2A) — the three waiting policies of `DeviceLocationProvider`,
/// finally BEHAVIOUR-tested through the seam instead of pinned by a
/// constant-in-range check:
///
/// 1. `currentLocation()` is bounded: a fix that never arrives resumes the
///    waiter at the deadline, once, with nil — and a STALE deadline (one
///    armed for an already-resolved request) can never fail a later one.
///    That second half is what the generation counter exists for.
/// 2. `ensureAuthorization()` stays unbounded by any clock (a human is
///    reading a system dialog), but a dismissed dialog resolves
///    `.notDetermined` on the foreground transition instead of parking the
///    turn forever.
/// 3. A real decision resolves through the delegate, exactly once, and
///    tears the foreground observer down.
///
/// Everything here drives the provider through the SAME entry points
/// CoreLocation uses — the delegate methods and the notification — with the
/// seam scripted by `FakeCoreLocation`. The only line of the class no test
/// reaches is the production `init()` that wires the concrete
/// CLLocationManager, which no unit test could reach anyway.
///
/// Double-resume honesty: `CheckedContinuation` traps on a second resume,
/// so every test that resolves a waiter and then fires the other resolution
/// path is asserting "exactly once" by surviving.
@MainActor
struct DeviceLocationProviderTests {

    // MARK: Harness

    /// Scriptable CoreLocation stand-in: the seam's four closures read and
    /// record here. Tests never poke continuations directly — resolution
    /// always flows through the provider's real delegate/foreground paths.
    @MainActor
    final class FakeCoreLocation {
        var status: CLAuthorizationStatus = .notDetermined
        var cached: CLLocation?
        private(set) var authorizationRequests = 0
        private(set) var fixRequests = 0

        var seam: DeviceLocationProvider.Seam {
            DeviceLocationProvider.Seam(
                authorizationStatus: { self.status },
                cachedLocation: { self.cached },
                requestWhenInUseAuthorization: { self.authorizationRequests += 1 },
                requestLocation: { self.fixRequests += 1 }
            )
        }
    }

    private func makeProvider(
        _ fake: FakeCoreLocation,
        center: NotificationCenter = NotificationCenter(),
        deadline: Duration = .seconds(60)
    ) -> DeviceLocationProvider {
        // 60s default: far past any test's lifetime, so the deadline task a
        // request arms can never interfere with a test that drives
        // resolution explicitly. The deadline-fires test shortens it.
        DeviceLocationProvider(seam: fake.seam, notificationCenter: center, fixDeadline: deadline)
    }

    /// A fix with a controllable age, for the freshness gate.
    private static func fix(latitude: Double, ageSeconds: TimeInterval = 0) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: -122),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            timestamp: Date(timeIntervalSinceNow: -ageSeconds)
        )
    }

    /// A wait whose outcome a test can OBSERVE without awaiting it. Awaiting
    /// `Task.value` on a stranded waiter can never return — a non-throwing
    /// `value` is not cancellation-responsive, so even a racing task group
    /// hangs with it (this hung the first mutation run for real). The box is
    /// settled by the child task; the pump watches the flag from outside.
    @MainActor
    final class Pending<T> {
        private(set) var outcome: T?
        private(set) var isSettled = false
        init(_ operation: @escaping @MainActor () async -> T) {
            Task { @MainActor in
                self.outcome = await operation()
                self.isSettled = true
            }
        }
    }

    /// Pumps until `pending` settles or ~`boundSeconds` of pumping passes, so
    /// a STRANDED waiter — the exact regression this file exists to catch —
    /// fails its test instead of hanging the whole suite. Outer nil = never
    /// settled. The bound is pump-iterations, not wall-clock precision; it
    /// only needs to comfortably exceed the 100ms test deadline, and does.
    private func settledValue<T: Sendable>(
        of pending: Pending<T>, boundSeconds: Double = 5
    ) async -> T? {
        for _ in 0 ..< Int(boundSeconds * 1000) {
            if pending.isSettled { return pending.outcome }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        return pending.isSettled ? pending.outcome : nil
    }

    /// Pumps the main actor until `condition` holds (or a generous bound is
    /// hit). Used to know a waiter has genuinely PARKED — its request has
    /// reached the fake — before a test fires a resolution path at it.
    private func pumpUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0 ..< 500 {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }

    /// A throwaway manager to satisfy the delegate methods' signatures; the
    /// provider under test never touches it (its CoreLocation surface is the
    /// scripted seam).
    private var dummyManager: CLLocationManager { CLLocationManager() }

    // MARK: Policy 1 — the bounded fix (#203 ship blocker)

    @Test func fixThatNeverArrivesResumesNilAtTheDeadlineOnce() async throws {
        let fake = FakeCoreLocation()
        let provider = makeProvider(fake, deadline: .milliseconds(100))
        let request = Pending { await provider.currentLocation() }
        #expect(await pumpUntil { fake.fixRequests == 1 })
        // No fix, no error — CoreLocation goes silent. The deadline must be
        // the thing that resumes the waiter, honestly, with nil.
        let outcome = await settledValue(of: request)
        let fixAtDeadline = try #require(outcome, "waiter was stranded past the deadline")
        #expect(fixAtDeadline == nil)
        // The fix limping in AFTER the deadline already resolved this waiter
        // must be a no-op for it — a second resume would trap right here.
        provider.locationManager(dummyManager, didUpdateLocations: [Self.fix(latitude: 1)])
        _ = await pumpUntil { false }
    }

    @Test func staleDeadlineFromAResolvedRequestCannotFailALaterOne() async throws {
        let fake = FakeCoreLocation()
        let provider = makeProvider(fake)
        // Request 1 parks under generation 0, then a real fix resolves it
        // (and bumps the generation), leaving request 1's deadline armed but
        // stale.
        let first = Pending { await provider.currentLocation() }
        #expect(await pumpUntil { fake.fixRequests == 1 })
        provider.locationManager(dummyManager, didUpdateLocations: [Self.fix(latitude: 10)])
        let firstFix = try #require(await settledValue(of: first), "first waiter stranded")
        #expect(firstFix?.coordinate.latitude == 10)
        // Request 2 parks under the bumped generation.
        let second = Pending { await provider.currentLocation() }
        #expect(await pumpUntil { fake.fixRequests == 2 })
        // Request 1's deadline finally fires, carrying the generation it was
        // armed for. The guard must make it a no-op — this is the bug a
        // naive timeout would have introduced.
        provider.failLocationWaitersIfStillPending(generation: 0)
        // Proof: request 2 is still alive to receive ITS answer. If the
        // stale deadline had killed it, this would resolve nil, not 20.
        provider.locationManager(dummyManager, didUpdateLocations: [Self.fix(latitude: 20)])
        let secondFix = try #require(await settledValue(of: second), "second waiter stranded")
        #expect(secondFix?.coordinate.latitude == 20)
    }

    @Test func definitiveFailureResumesNilThroughTheDelegate() async throws {
        let fake = FakeCoreLocation()
        let provider = makeProvider(fake)
        let request = Pending { await provider.currentLocation() }
        #expect(await pumpUntil { fake.fixRequests == 1 })
        provider.locationManager(dummyManager, didFailWithError: CLError(.locationUnknown))
        let fix = try #require(await settledValue(of: request), "waiter stranded after didFailWithError")
        #expect(fix == nil)
    }

    @Test func freshCachedFixSkipsTheRadio() async {
        let fake = FakeCoreLocation()
        fake.cached = Self.fix(latitude: 40, ageSeconds: 30)
        let provider = makeProvider(fake)
        let fix = await provider.currentLocation()
        #expect(fix?.coordinate.latitude == 40)
        #expect(fake.fixRequests == 0)
    }

    @Test func staleCachedFixSpinsTheRadio() async throws {
        let fake = FakeCoreLocation()
        fake.cached = Self.fix(latitude: 40, ageSeconds: 300)
        let provider = makeProvider(fake)
        let request = Pending { await provider.currentLocation() }
        #expect(await pumpUntil { fake.fixRequests == 1 })
        provider.locationManager(dummyManager, didUpdateLocations: [Self.fix(latitude: 50)])
        let fix = try #require(await settledValue(of: request), "waiter stranded past a stale cache")
        #expect(fix?.coordinate.latitude == 50)
    }

    // MARK: Policy 2 — the dismissed dialog (#203 2A)

    @Test func dismissedDialogResolvesNotDeterminedOnForeground() async throws {
        let fake = FakeCoreLocation() // status stays .notDetermined throughout
        let center = NotificationCenter()
        let provider = makeProvider(fake, center: center)
        let wait = Pending { await provider.ensureAuthorization() }
        #expect(await pumpUntil { fake.authorizationRequests == 1 })
        #expect(provider.foregroundObserver != nil)
        // The user swipes the dialog away; the app comes back to the front
        // with the status still undetermined. That IS the answer.
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        let status = try #require(await settledValue(of: wait), "dismissed dialog stranded the waiter")
        #expect(status == .notDetermined)
        #expect(provider.foregroundObserver == nil)
        // A later foreground with nobody waiting must be inert.
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        _ = await pumpUntil { false }
    }

    @Test func foregroundWithADecidedStatusStandsDownForTheDelegate() async throws {
        let fake = FakeCoreLocation()
        let center = NotificationCenter()
        let provider = makeProvider(fake, center: center)
        let wait = Pending { await provider.ensureAuthorization() }
        #expect(await pumpUntil { fake.authorizationRequests == 1 })
        // The user answers ON the dialog: the app foregrounds with the
        // status already decided but the delegate not yet fired. The
        // foreground path must not resolve — `.notDetermined` here would be
        // a fabricated answer the delegate is about to contradict.
        fake.status = .denied
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        _ = await pumpUntil { false }
        provider.locationManagerDidChangeAuthorization(dummyManager)
        let status = try #require(await settledValue(of: wait), "waiter stranded between foreground and delegate")
        #expect(status == .denied)
    }

    // MARK: Policy 3 — the real decision

    @Test func realDecisionResolvesThroughTheDelegateAndTearsDownTheObserver() async throws {
        let fake = FakeCoreLocation()
        let provider = makeProvider(fake)
        let wait = Pending { await provider.ensureAuthorization() }
        #expect(await pumpUntil { fake.authorizationRequests == 1 })
        #expect(provider.foregroundObserver != nil)
        // CoreLocation's order on a real answer: status flips, then the
        // delegate fires.
        fake.status = .authorizedWhenInUse
        provider.locationManagerDidChangeAuthorization(dummyManager)
        let status = try #require(await settledValue(of: wait), "waiter stranded after a real decision")
        #expect(status == .authorizedWhenInUse)
        #expect(provider.foregroundObserver == nil)
    }

    @Test func alreadyDeterminedStatusNeverPromptsOrParks() async {
        let fake = FakeCoreLocation()
        fake.status = .denied
        let provider = makeProvider(fake)
        let status = await provider.ensureAuthorization()
        #expect(status == .denied)
        #expect(fake.authorizationRequests == 0)
        #expect(provider.foregroundObserver == nil)
    }

    // MARK: Concurrent waiters

    @Test func everyConcurrentWaiterResumesAndNoneTwice() async throws {
        let fake = FakeCoreLocation()
        let provider = makeProvider(fake)
        let authA = Pending { await provider.ensureAuthorization() }
        let authB = Pending { await provider.ensureAuthorization() }
        #expect(await pumpUntil { fake.authorizationRequests == 2 })
        let fixA = Pending { await provider.currentLocation() }
        let fixB = Pending { await provider.currentLocation() }
        #expect(await pumpUntil { fake.fixRequests == 2 })
        fake.status = .authorizedWhenInUse
        provider.locationManagerDidChangeAuthorization(dummyManager)
        provider.locationManager(dummyManager, didUpdateLocations: [Self.fix(latitude: 30)])
        let statusA = try #require(await settledValue(of: authA), "authorization waiter A stranded")
        let statusB = try #require(await settledValue(of: authB), "authorization waiter B stranded")
        #expect(statusA == .authorizedWhenInUse)
        #expect(statusB == .authorizedWhenInUse)
        let a = try #require(await settledValue(of: fixA), "location waiter A stranded")
        let b = try #require(await settledValue(of: fixB), "location waiter B stranded")
        #expect(a?.coordinate.latitude == 30)
        #expect(b?.coordinate.latitude == 30)
    }

    // MARK: The production constant

    /// The shipped deadline itself, still pinned: bounded, non-zero, sane.
    /// This used to be the ONLY test this class had, with an apology
    /// attached; the behaviour above is what it was standing in for.
    @Test func productionFixDeadlineIsBoundedAndSane() {
        #expect(DeviceLocationProvider.fixDeadline > .zero)
        #expect(DeviceLocationProvider.fixDeadline <= .seconds(30))
    }
}
