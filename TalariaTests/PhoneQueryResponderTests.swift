import Foundation
import Testing
@testable import Talaria

/// #251-2A Task 9 — the structured phone-query catalog.
///
/// Two things are pinned here and nothing else: WHICH privacy gate each query
/// kind sits behind, and WHICH read the responder dispatches to once the gate
/// opens. The reads themselves are the belt's (HealthKit, EventKit,
/// WeatherKit, CoreLocation) and stay device-verified, so the reader seam is
/// faked — but the fake is not a tautology: every method returns a DISTINCT
/// string and records its own name, so a case that returned the right text
/// through the wrong read, or read anything at all through a closed gate,
/// fails.
@MainActor
struct PhoneQueryResponderTests {

    /// Non-final so the throwing case can override exactly one read.
    @MainActor
    class FakeReader: PhoneQueryReader {
        var calls: [String] = []

        func location(relay: ToolEventRelay) async throws -> String {
            calls.append("location")
            return "Current location: Home"
        }

        func health(metric: String?, relay: ToolEventRelay) async throws -> String {
            calls.append("health:\(metric ?? "")")
            return "Steps today: 1200"
        }

        func motion(relay: ToolEventRelay) async throws -> String {
            calls.append("motion")
            return "Current activity: walking"
        }

        func weather(relay: ToolEventRelay) async throws -> String {
            calls.append("weather")
            return "Weather at current location: Clear, 22C"
        }

        func calendar(daysAhead: Int, relay: ToolEventRelay) async throws -> String {
            calls.append("calendar:\(daysAhead)")
            return "Wed Aug 5 09:00–10:00 — Standup"
        }

        func reminders(relay: ToolEventRelay) async throws -> String {
            calls.append("reminders")
            return "• Buy milk [Reminders]"
        }

        func deviceStatus() async -> String {
            calls.append("deviceStatus")
            return "Battery: 80% (not charging)"
        }
    }

    private func makeResponder(_ settings: UserSettings, reader: FakeReader) -> PhoneQueryResponder {
        PhoneQueryResponder(settings: { settings }, reader: reader)
    }

    /// Every collection toggle on — the shape a user who has opted into
    /// sensor streaming has. `UserSettings()` defaults them all to false.
    private var allOn: UserSettings {
        var settings = UserSettings()
        settings.sensorStreamingEnabled = true
        settings.healthCollectionEnabled = true
        settings.locationCollectionEnabled = true
        settings.motionCollectionEnabled = true
        return settings
    }

    // MARK: - Dispatch

    @Test func eachKindDispatchesToItsOwnRead() async {
        let reader = FakeReader()
        let responder = makeResponder(allOn, reader: reader)
        #expect(await responder.answer(kind: "location", params: [:]) == .success(text: "Current location: Home"))
        #expect(await responder.answer(kind: "health", params: [:]) == .success(text: "Steps today: 1200"))
        #expect(await responder.answer(kind: "motion", params: [:]) == .success(text: "Current activity: walking"))
        #expect(await responder.answer(kind: "weather", params: [:]) == .success(text: "Weather at current location: Clear, 22C"))
        #expect(await responder.answer(kind: "calendar", params: [:]) == .success(text: "Wed Aug 5 09:00–10:00 — Standup"))
        #expect(await responder.answer(kind: "reminders", params: [:]) == .success(text: "• Buy milk [Reminders]"))
        #expect(await responder.answer(kind: "deviceStatus", params: [:]) == .success(text: "Battery: 80% (not charging)"))
        #expect(reader.calls == [
            "location", "health:", "motion", "weather",
            "calendar:\(PhoneQueryResponder.defaultCalendarDaysAhead)", "reminders", "deviceStatus",
        ])
    }

    @Test func paramsReachTheRead() async {
        let reader = FakeReader()
        let responder = makeResponder(allOn, reader: reader)
        _ = await responder.answer(kind: "health", params: ["metric": "sleep"])
        _ = await responder.answer(kind: "calendar", params: ["window_days": "3"])
        #expect(reader.calls == ["health:sleep", "calendar:3"])
    }

    @Test func unparsableWindowFallsBackToTheDefault() async {
        let reader = FakeReader()
        let responder = makeResponder(allOn, reader: reader)
        _ = await responder.answer(kind: "calendar", params: ["window_days": "next week"])
        #expect(reader.calls == ["calendar:\(PhoneQueryResponder.defaultCalendarDaysAhead)"])
    }

    // MARK: - Gates

    @Test func healthAnswersWhenToggledOn() async {
        let reader = FakeReader()
        let answer = await makeResponder(allOn, reader: reader).answer(kind: "health", params: ["metric": "steps"])
        #expect(answer == .success(text: "Steps today: 1200"))
        #expect(reader.calls == ["health:steps"])
    }

    @Test func masterOffDeniesSensorKindsButNotCalendarOrStatus() async {
        var settings = allOn
        settings.sensorStreamingEnabled = false
        let reader = FakeReader()
        let responder = makeResponder(settings, reader: reader)
        #expect(await responder.answer(kind: "health", params: [:]) == .denied)
        #expect(await responder.answer(kind: "location", params: [:]) == .denied)
        #expect(await responder.answer(kind: "motion", params: [:]) == .denied)
        #expect(await responder.answer(kind: "weather", params: [:]) == .denied)
        // A denied kind must not have READ anything on its way to the denial.
        #expect(reader.calls.isEmpty)
        #expect(await responder.answer(kind: "calendar", params: [:]) == .success(text: "Wed Aug 5 09:00–10:00 — Standup"))
        #expect(await responder.answer(kind: "reminders", params: [:]) == .success(text: "• Buy milk [Reminders]"))
        #expect(await responder.answer(kind: "deviceStatus", params: [:]) == .success(text: "Battery: 80% (not charging)"))
    }

    @Test func perStreamToggleDeniesItsKindOnly() async {
        var settings = allOn
        settings.healthCollectionEnabled = false
        let reader = FakeReader()
        let responder = makeResponder(settings, reader: reader)
        #expect(await responder.answer(kind: "health", params: [:]) == .denied)
        #expect(await responder.answer(kind: "location", params: [:]) == .success(text: "Current location: Home"))
        #expect(await responder.answer(kind: "motion", params: [:]) == .success(text: "Current activity: walking"))
        #expect(reader.calls == ["location", "motion"])
    }

    @Test func motionToggleDeniesMotionOnly() async {
        var settings = allOn
        settings.motionCollectionEnabled = false
        let reader = FakeReader()
        let responder = makeResponder(settings, reader: reader)
        #expect(await responder.answer(kind: "motion", params: [:]) == .denied)
        #expect(await responder.answer(kind: "health", params: [:]) == .success(text: "Steps today: 1200"))
    }

    /// Weather here is weather AT THE USER'S LOCATION — the responder never
    /// passes a place through — so it is a location read wearing a different
    /// name and rides the location toggle.
    @Test func weatherRidesLocationToggle() async {
        var settings = allOn
        settings.locationCollectionEnabled = false
        let reader = FakeReader()
        let responder = makeResponder(settings, reader: reader)
        #expect(await responder.answer(kind: "weather", params: [:]) == .denied)
        #expect(await responder.answer(kind: "location", params: [:]) == .denied)
        #expect(await responder.answer(kind: "health", params: [:]) == .success(text: "Steps today: 1200"))
        #expect(reader.calls == ["health:"])
    }

    /// Calendar / reminders / deviceStatus carry no settings gate at all —
    /// iOS's own permission prompts are their gate, exactly as on the belt.
    @Test func permissionOnlyKindsAnswerWithEverySettingOff() async {
        let reader = FakeReader()
        let responder = makeResponder(UserSettings(), reader: reader)
        #expect(await responder.answer(kind: "calendar", params: [:]) == .success(text: "Wed Aug 5 09:00–10:00 — Standup"))
        #expect(await responder.answer(kind: "reminders", params: [:]) == .success(text: "• Buy milk [Reminders]"))
        #expect(await responder.answer(kind: "deviceStatus", params: [:]) == .success(text: "Battery: 80% (not charging)"))
    }

    /// The gate is read PER ANSWER, not captured once at construction — a
    /// toggle the user flips mid-session has to take effect on the next query.
    @Test func gateIsReReadOnEveryAnswer() async {
        final class SettingsBox: @unchecked Sendable {
            var settings: UserSettings
            init(_ settings: UserSettings) { self.settings = settings }
        }
        let box = SettingsBox(allOn)
        let reader = FakeReader()
        let responder = PhoneQueryResponder(settings: { box.settings }, reader: reader)
        #expect(await responder.answer(kind: "location", params: [:]) == .success(text: "Current location: Home"))
        box.settings.locationCollectionEnabled = false
        #expect(await responder.answer(kind: "location", params: [:]) == .denied)
    }

    // MARK: - Failure shapes

    @Test func unknownKindIsUnavailableNotDenied() async {
        let reader = FakeReader()
        let answer = await makeResponder(allOn, reader: reader).answer(kind: "contacts", params: [:])
        #expect(answer == .unavailable(reason: "unknown_kind"))
        #expect(reader.calls.isEmpty)
    }

    /// Pins the dispatch switch's `default:` arm — which returns
    /// `.unavailable`, NOT the device-status report.
    ///
    /// Honest about its own reach: the gate switch rejects "photos" first, so
    /// this case cannot execute the dispatch default arm today. What it pins
    /// is the CONTRACT between the two hand-synced switches — a kind the
    /// catalog does not serve answers `unknown_kind` and reads nothing, by
    /// whichever of the two arms it reaches. Before the hardening the default
    /// arm answered `deviceStatus()`, so a kind added to the gate's
    /// permission-only list and forgotten in dispatch would have returned the
    /// battery/storage report as a `.success` — confidently wrong data on a
    /// privacy-adjacent path.
    @Test func kindOutsideTheCatalogNeverFallsThroughToDeviceStatus() async {
        let reader = FakeReader()
        let answer = await makeResponder(allOn, reader: reader).answer(kind: "photos", params: [:])
        #expect(answer == .unavailable(reason: "unknown_kind"))
        #expect(answer != .success(text: "Battery: 80% (not charging)"))
        #expect(reader.calls.isEmpty)
    }

    @Test func readerThrowBecomesUnavailable() async {
        final class ThrowingReader: FakeReader {
            struct Boom: Error {}
            override func location(relay: ToolEventRelay) async throws -> String {
                calls.append("location")
                throw Boom()
            }
        }
        let reader = ThrowingReader()
        let answer = await makeResponder(allOn, reader: reader).answer(kind: "location", params: [:])
        #expect(answer == .unavailable(reason: "read_failed"))
        #expect(reader.calls == ["location"])
    }

    /// The responder is the link's `PhoneQueryResponding` conformer — the
    /// seam Task 7 declared, not a parallel type.
    @Test func conformsToTheLinkSeam() async {
        let responder: any PhoneQueryResponding = makeResponder(allOn, reader: FakeReader())
        #expect(await responder.answer(kind: "deviceStatus", params: [:]) == .success(text: "Battery: 80% (not charging)"))
    }

    // MARK: - #260(B): a denial can name its gate

    /// The gate table itself is unchanged (#260-C) — `.denied` still comes
    /// back exactly as the pins above assert. What #260(B) adds is a parallel
    /// CLASSIFIER the link asks when it serializes a denial, so the wire can
    /// say WHICH gate refused instead of a bare `permission_denied` the model
    /// has to guess a toggle from.
    @Test func deniedGateNamesTheMasterWhenTheMasterIsOff() async {
        var settings = allOn
        settings.sensorStreamingEnabled = false
        let responder = makeResponder(settings, reader: FakeReader())
        #expect(responder.deniedGate(kind: "health") == .master)
        #expect(responder.deniedGate(kind: "location") == .master)
        #expect(responder.deniedGate(kind: "motion") == .master)
        #expect(responder.deniedGate(kind: "weather") == .master)
    }

    /// Master on, one stream off: the classifier names THAT stream's toggle —
    /// including weather naming LOCATION, because that is the toggle a user
    /// must actually flip to unblock a weather query.
    @Test func deniedGateNamesTheSensorStreamWhenOnlyItsToggleIsOff() async {
        var settings = allOn
        settings.healthCollectionEnabled = false
        settings.locationCollectionEnabled = false
        let responder = makeResponder(settings, reader: FakeReader())
        #expect(responder.deniedGate(kind: "health") == .stream(sensor: "health"))
        #expect(responder.deniedGate(kind: "location") == .stream(sensor: "location"))
        #expect(responder.deniedGate(kind: "weather") == .stream(sensor: "location"))
        #expect(responder.deniedGate(kind: "motion") == nil)
    }

    /// Master-off outranks a stream-off: with both closed, the master is the
    /// switch that unblocks nothing until it flips, so it is the one named.
    @Test func masterOffOutranksAStreamOff() async {
        var settings = allOn
        settings.sensorStreamingEnabled = false
        settings.healthCollectionEnabled = false
        let responder = makeResponder(settings, reader: FakeReader())
        #expect(responder.deniedGate(kind: "health") == .master)
    }

    /// Open gates, permission-only kinds, and unknown kinds all classify as
    /// nil — there is no denial for the wire to explain.
    @Test func deniedGateIsNilWhereNothingWouldDeny() async {
        let open = makeResponder(allOn, reader: FakeReader())
        #expect(open.deniedGate(kind: "health") == nil)
        #expect(open.deniedGate(kind: "weather") == nil)
        var masterOff = allOn
        masterOff.sensorStreamingEnabled = false
        let gated = makeResponder(masterOff, reader: FakeReader())
        #expect(gated.deniedGate(kind: "calendar") == nil)
        #expect(gated.deniedGate(kind: "reminders") == nil)
        #expect(gated.deniedGate(kind: "deviceStatus") == nil)
        #expect(gated.deniedGate(kind: "photos") == nil)
    }

    /// #260-B's third payload: iOS-ungranted is NOT a settings denial — the
    /// read runs and the belt's honest "not granted" prose comes back as a
    /// `.success`, so the wire carries `result.text`, never `permission_denied`.
    /// This pins that no one "improves" the responder into inspecting read
    /// prose and converting it to a denial the wire would then mis-blame on a
    /// toggle.
    @Test func iosUngrantedProseTravelsAsSuccessNotDenial() async {
        final class UngrantedReader: FakeReader {
            override func health(metric: String?, relay: ToolEventRelay) async throws -> String {
                calls.append("health:\(metric ?? "")")
                return "Health data permission hasn't been granted to Talaria in the Health app."
            }
        }
        let reader = UngrantedReader()
        let responder = makeResponder(allOn, reader: reader)
        let answer = await responder.answer(kind: "health", params: [:])
        #expect(answer == .success(text: "Health data permission hasn't been granted to Talaria in the Health app."))
        #expect(responder.deniedGate(kind: "health") == nil)
    }
}
