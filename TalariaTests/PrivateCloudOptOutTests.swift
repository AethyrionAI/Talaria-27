import Foundation
import Testing
@testable import Talaria

/// **#395 — the Private Cloud hard opt-out, and #391's honest quota row.**
///
/// **The toggle is NOT the brain picker, and that distinction is the whole
/// point of the feature.** The picker chooses who answers the next turn; PCC
/// has always appeared there when the tier is live. This decides whether the
/// tier is offered to the app at all — Owen's reasons (2026-08-21): privacy,
/// and being able to shut the tier off when quota is exhausted and its
/// behaviour turns strange.
@MainActor
struct PrivateCloudOptOutTests {

    /// Reused from `ChatBackendRouterTests` rather than re-stubbed here.
    /// `HermesClientProtocol` is wide, and a second hand-rolled conformance is
    /// how two test stubs drift apart until they disagree about the protocol
    /// they both claim to implement (#256's shape).
    private typealias StubBackend = ChatBackendRouterTests.StubBackend

    private func makeDefaults() -> UserDefaults {
        let suite = "PrivateCloudOptOutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// `selectable` and `usable` are set INDEPENDENTLY rather than from one
    /// expression, so a test can construct the half-gated arrangement and show
    /// what it does. Deriving both from a single flag would make every test
    /// pass whether the container gated one predicate or both — the test would
    /// be asserting its own stub.
    private func makeRouter(
        selectable: Bool,
        usable: Bool,
        disabledByUser: Bool
    ) -> ChatBackendRouter {
        let router = ChatBackendRouter(
            hermes: StubBackend(replyContent: "hermes"),
            local: StubBackend(replyContent: "local"),
            isHermesConfigured: { false },
            hasHermesHost: { false },
            defaults: makeDefaults()
        )
        router.isPrivateCloudSelectable = { selectable }
        router.isPrivateCloudUsable = { usable }
        router.isPrivateCloudDisabledByUser = { disabledByUser }
        return router
    }

    /// The wiring under test, mirroring `AppContainer`: the setting gates BOTH
    /// predicates.
    private func makeGatedRouter(pccAvailable: Bool, optedOut: Bool) -> ChatBackendRouter {
        makeRouter(selectable: pccAvailable && !optedOut,
                   usable: pccAvailable && !optedOut,
                   disabledByUser: optedOut)
    }

    // MARK: The gate

    /// The tier is live and the user has not opted out — unchanged behaviour.
    @Test func privateCloudIsSelectableWhenTheTierIsLiveAndNotOptedOut() {
        let router = makeGatedRouter(pccAvailable: true, optedOut: false)
        #expect(router.selectableBrains.contains(.privateCloud))
    }

    /// The opt-out removes it from the picker entirely.
    @Test func theOptOutRemovesPrivateCloudFromThePicker() {
        let router = makeGatedRouter(pccAvailable: true, optedOut: true)
        #expect(!router.selectableBrains.contains(.privateCloud))
    }

    /// **The load-bearing one.** Gating only `isPrivateCloudSelectable` would
    /// hide the picker entry while leaving every automatic route to the tier
    /// intact — a toggle that means "hide the button" rather than "do not use
    /// this". A user who pinned PCC before opting out must be moved off it.
    @Test func aPinnedPrivateCloudConversationStopsRoutingThereOnceOptedOut() {
        let router = makeGatedRouter(pccAvailable: true, optedOut: true)
        let conversation = UUID()
        router.setPreferredBrain(.privateCloud, forConversation: conversation)
        #expect(router.resolvedBrainForNextTurn() == .onDevice)
    }

    /// **The hazard, demonstrated rather than asserted away.** This builds the
    /// HALF-gated arrangement — picker entry hidden, routing predicate still
    /// true — and shows that a pinned conversation keeps routing straight to
    /// the tier the user just switched off.
    ///
    /// It is the reason `AppContainer` gates `isPrivateCloudUsable` as well as
    /// `isPrivateCloudSelectable`. Without this test the suite would pass
    /// whether the container gated one predicate or both, because every other
    /// test here sets the two together.
    @Test func gatingOnlyThePickerWouldLeaveAutomaticRoutingIntact() {
        let halfGated = makeRouter(selectable: false, usable: true, disabledByUser: true)
        halfGated.setPreferredBrain(.privateCloud, forConversation: UUID())
        #expect(halfGated.resolvedBrainForNextTurn() == .privateCloud,
                """
                This test documents the BROKEN arrangement on purpose. If it now reports \
                on-device, the router gained its own internal gate and this test — plus the \
                container's double gate — should be revisited rather than deleted.
                """)
        #expect(!halfGated.selectableBrains.contains(.privateCloud))
    }

    // MARK: The notice must name the cause the user can act on

    /// #180's family: a surface must not describe a state it did not observe.
    /// Reporting the user's own setting as *"unavailable or over its daily
    /// limit"* sends them hunting for a network fault they do not have.
    @Test func theFallbackNoticeSaysTurnedOffWhenTheUserTurnedItOff() {
        let router = makeGatedRouter(pccAvailable: true, optedOut: true)
        router.setPreferredBrain(.privateCloud, forConversation: UUID())
        _ = router.resolvedBrainForNextTurn()
        let notice = router.privateCloudFallbackNotice ?? ""
        #expect(notice.contains("turned off"), "expected the opt-out wording, got: \(notice)")
        #expect(!notice.contains("daily limit"),
                "the opt-out must NOT be reported as a quota problem, got: \(notice)")
    }

    /// The other cause keeps its own wording — the fix must not collapse two
    /// distinct states into one message in the opposite direction.
    @Test func theFallbackNoticeStillSaysRateLimitedWhenThatIsTheCause() {
        let router = makeGatedRouter(pccAvailable: false, optedOut: false)
        router.setPreferredBrain(.privateCloud, forConversation: UUID())
        _ = router.resolvedBrainForNextTurn()
        let notice = router.privateCloudFallbackNotice ?? ""
        #expect(notice.contains("daily limit"), "expected the quota wording, got: \(notice)")
        #expect(!notice.contains("turned off"), "got the opt-out wording for a non-opt-out cause: \(notice)")
    }

    // MARK: Migration — an existing install must not silently lose the tier

    /// PCC shipped enabled (#72/#386). Settings written before this key
    /// existed must decode to ON; defaulting to OFF would withdraw a
    /// capability users already have, silently, on upgrade.
    @Test func settingsThatPredateTheToggleKeepPrivateCloudEnabled() throws {
        let json = Data(#"{"verboseLogging":false}"#.utf8)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: json)
        #expect(decoded.privateCloudEnabled == true)
    }

    @Test func theToggleSurvivesAnEncodeDecodeRoundTrip() throws {
        var settings = UserSettings()
        settings.privateCloudEnabled = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        #expect(decoded.privateCloudEnabled == false)
    }

    // MARK: #391 — the quota row prints what it has, and nil reads as nil

    private static let reference = Date(timeIntervalSince1970: 1_756_000_000)

    /// Owen's ruling: *"Print what it shows. If it's nil, it's nil."* The
    /// RESETS field is always present so its ABSENCE is visible — a row that
    /// silently omitted the field could not tell the user the app was never
    /// given a reset date.
    @Test func anAbsentResetDateRendersAsADashRatherThanVanishing() {
        let label = LocalChatBackend.PrivateCloudStatus.quotaRowLabel(
            quota: .belowLimit(approaching: false), resetDate: nil, now: Self.reference)
        #expect(label.contains("RESETS —"))
        #expect(label.contains("BELOW DAILY LIMIT"))
    }

    /// **#391's actual defect.** The reset date used to be read only inside
    /// the `limitReached` arm, so on the common below-limit path a date the OS
    /// HAD supplied was discarded before anything could show it.
    @Test func aResetDateIsShownOnTheBelowLimitPathNotOnlyWhenTheLimitIsReached() {
        let resets = Self.reference.addingTimeInterval(3 * 3600)
        let label = LocalChatBackend.PrivateCloudStatus.quotaRowLabel(
            quota: .belowLimit(approaching: false), resetDate: resets, now: Self.reference)
        #expect(!label.contains("RESETS —"), "the below-limit arm dropped a reset date it was given: \(label)")
    }

    /// A bare time is useless if the turnover is not today — which is exactly
    /// the case Owen named as worth surfacing ("no PCC left, resets tomorrow").
    @Test func aResetDateOnAnotherDayCarriesTheDateNotJustTheTime() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Self.reference)!
        let sameDay = Self.reference.addingTimeInterval(60)

        let laterToday = LocalChatBackend.PrivateCloudStatus.resetFieldText(
            sameDay, now: Self.reference, calendar: calendar)
        let nextDay = LocalChatBackend.PrivateCloudStatus.resetFieldText(
            tomorrow, now: Self.reference, calendar: calendar)

        #expect(laterToday != nextDay)
        #expect(nextDay.count > laterToday.count,
                "a next-day reset must carry more than a bare time — got '\(nextDay)' vs '\(laterToday)'")
    }

    /// An unrecognised status is not good news. It used to be folded into
    /// `belowLimit(approaching: false)` and rendered as "BELOW DAILY LIMIT".
    @Test func anUnknownStatusRendersAsUnknownRatherThanAsReassurance() {
        let label = LocalChatBackend.PrivateCloudStatus.quotaRowLabel(
            quota: .unknown, resetDate: nil, now: Self.reference)
        #expect(label.contains("STATUS —"))
        #expect(!label.contains("BELOW DAILY LIMIT"))
    }

    // MARK: The MAPPING, not just the formatting

    /// **#391's defect was in the plumbing, so the plumbing is what this
    /// pins.** The reset date used to be read only inside the limit-reached
    /// branch. A test that drove the label formatter with an explicit date
    /// would have stayed green through that bug — it was never the formatter
    /// that dropped the value.
    @Test func theResetDateSurvivesTheMappingOnTheBelowLimitArm() {
        let resets = Self.reference.addingTimeInterval(7200)
        let status = LocalChatBackend.PrivateCloudStatus.make(
            isLimitReached: false,
            isApproachingLimit: false,
            resetDate: resets,
            hasLimitIncreaseSuggestion: false
        )
        #expect(status.quota == .belowLimit(approaching: false))
        #expect(status.resetDate == resets, "the below-limit arm discarded the OS's reset date")
    }

    @Test func theResetDateSurvivesTheMappingOnTheLimitReachedArm() {
        let resets = Self.reference.addingTimeInterval(7200)
        let status = LocalChatBackend.PrivateCloudStatus.make(
            isLimitReached: true,
            isApproachingLimit: nil,
            resetDate: resets,
            hasLimitIncreaseSuggestion: true
        )
        #expect(status.quota == .limitReached)
        #expect(status.resetDate == resets)
    }

    /// An unnameable status maps to `.unknown`, never to good news — and
    /// `isLimitReached` still wins over it, because that flag is a direct
    /// reading rather than an inference.
    @Test func anUnnameableStatusMapsToUnknownUnlessTheLimitFlagIsSet() {
        let unknown = LocalChatBackend.PrivateCloudStatus.make(
            isLimitReached: false, isApproachingLimit: nil,
            resetDate: nil, hasLimitIncreaseSuggestion: false)
        #expect(unknown.quota == .unknown)

        let reached = LocalChatBackend.PrivateCloudStatus.make(
            isLimitReached: true, isApproachingLimit: nil,
            resetDate: nil, hasLimitIncreaseSuggestion: false)
        #expect(reached.quota == .limitReached)
    }

    @Test func theApproachingFlagIsCarriedThroughTheMapping() {
        let approaching = LocalChatBackend.PrivateCloudStatus.make(
            isLimitReached: false, isApproachingLimit: true,
            resetDate: nil, hasLimitIncreaseSuggestion: false)
        #expect(approaching.quota == .belowLimit(approaching: true))
    }

    // MARK: - #395-D: the toggle moved, the quota row stayed

    /// **395-D-B/-D structural half** (source-reading pattern per
    /// `VoiceMemoAttachmentTests.deactivationIsSpelledOnlyInsideTheInjectableSeam`,
    /// #399): SwiftUI view bodies are unreachable from a unit test, so the
    /// move is pinned in the sources. The binding WRITE is the discriminator —
    /// `privateCloudEnabled = $0` — because whoever holds it holds the
    /// control, and one source of truth means exactly one surface writes it.
    ///
    /// Fails loudly if a source cannot be read: a check that cannot run must
    /// say so rather than print a pass it did not earn.
    @Test func allPCCStateLivesOnlyOnTheDedicatedScreen() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
        func source(_ relative: String) throws -> String {
            let url = root.appendingPathComponent(relative)
            return try #require(
                try? String(contentsOf: url, encoding: .utf8),
                "cannot read \(relative) — this check did not run"
            )
        }

        let models = try source("Talaria/Features/Settings/ModelsSettingsScreen.swift")
        let pcc = try source("Talaria/Features/Settings/PrivateCloudSettingsScreen.swift")

        #expect(!models.contains("privateCloudEnabled = $0"),
                "the toggle's binding write must not remain on the Models screen (#395-D)")
        #expect(pcc.contains("privateCloudEnabled = $0"),
                "the dedicated screen must write the SAME UserSettings key — one source of truth, no second flag")
        // Owen's 2026-08-23 night ruling (from a device screenshot of the
        // crowded picker): PCC state lives on the PCC square ALONE. This
        // assertion previously enforced the opposite — the #30
        // quota-where-you-pick row — and flips with the ruling as authority.
        #expect(!models.contains("PrivateCloudQuotaRow"),
                "PCC usage moved into the PCC tile — the Models screen must not grow its readout back")
        #expect(pcc.contains("PrivateCloudQuotaRow"),
                "control and state stay one surface on the dedicated screen (#395's own principle)")
    }

    /// **The AppContainer wiring pin #395's own bars declared missing, added
    /// by the 2026-08-23 Opus-week audit.** Every predicate test above
    /// mirrors the gating in its own stub, so reverting `AppContainer` to
    /// gate one predicate failed nothing — the entry states this limit in so
    /// many words. Structural floor (the #399 pattern): the container's
    /// wiring must read `settings.privateCloudEnabled` exactly three times —
    /// selectable's guard, usable's guard, and disabledByUser's negation.
    @Test func theContainerGatesAllThreePredicatesOnTheUsersSetting() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // TalariaTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Talaria/Stores/AppContainer.swift")
        let source = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "cannot read AppContainer.swift — this check did not run"
        )
        let reads = source.components(separatedBy: "settings.privateCloudEnabled").count - 1
        #expect(reads == 3, """
            expected exactly 3 reads of settings.privateCloudEnabled in \
            AppContainer (selectable guard, usable guard, disabledByUser \
            negation); found \(reads) — a predicate lost its gate (or a new \
            reader was added without extending this pin)
            """)
    }
}
