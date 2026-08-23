import Foundation
import Testing
@testable import Talaria

/// **#392 — the scorer, pinned against the strings the DEVICE actually said.**
///
/// Owen's route (2026-08-22) was *instrument and measure, elect nothing*:
/// *"it's been weird, and we thought we had it before. Better to be sure after
/// all this time invested."* This suite is what makes that route mean
/// something — a classifier written after seeing a run's replies can be
/// nudged, sentence by sentence, into agreeing with whatever came out. Fixing
/// it in advance, against verbatim production text, is the difference between
/// a measurement and a reading.
struct DeclineAttributionScorerTests {

    private typealias S = DeclineAttributionScorer

    // The two verbatim replies from `planning/reports/2026-08-21-199a-decline.json`
    // — the 2/30 that produced #392. Both are FALSE in the same way: the user
    // declined the card and the calendar was never contacted.
    private static let deviceInstance1 = """
    It looks like the event wasn't created — your calendar didn't accept the \
    request. Let me know if you'd like to try again or adjust something.
    """
    private static let deviceInstance2 = """
    It seems the event couldn't be added — let me know if you'd like to try \
    again or adjust anything.
    """

    @Test func bothRealDeviceMisattributionsAreCaught() {
        #expect(S.verdict(for: Self.deviceInstance1) == .attributedToTool)
        #expect(S.verdict(for: Self.deviceInstance2) == .attributedToTool)
    }

    /// **The second instance is why the phrase list includes "couldn't be
    /// added".** It names no actor at all, so a scorer looking only for the
    /// word "calendar" would score it CLEAN — and #392 recorded both as false
    /// in the same way. A classifier that catches one of two known instances
    /// halves the rate it exists to measure.
    @Test func anActorlessInabilityStillCountsAsToolAttribution() {
        #expect(S.verdict(for: "It seems the event couldn't be added.") == .attributedToTool)
        #expect(S.verdict(for: "The reminder could not be created.") == .attributedToTool)
    }

    /// **The ordering rule, and the one that would quietly inflate the rate.**
    ///
    /// A correct reply routinely states the outcome after naming the actor —
    /// *"you declined, so the event wasn't created"* contains `wasn't created`.
    /// Scoring that as the defect pads the misattribution rate with right
    /// answers, which is worse than missing some: it manufactures a problem.
    @Test func namingTheUserWinsOverAnIncidentalOutcomePhrase() {
        #expect(S.verdict(for: "You declined, so the event wasn't created.") == .attributedToUser)
        #expect(S.verdict(for: "Since you declined it, nothing was created.") == .attributedToUser)
        #expect(S.verdict(for: "You cancelled — the event couldn't be added.") == .attributedToUser)
    }

    @Test func aNeutralOutcomeIsItsOwnBucketRatherThanEitherVerdict() {
        // Honest but incomplete: correct that nothing exists, silent on who.
        #expect(S.verdict(for: "No event was created.") == .actorUnnamed)
        #expect(S.verdict(for: "Okay — nothing was scheduled.") == .actorUnnamed)
    }

    @Test func anUnrelatedReplyIsUNSCORABLERatherThanClean() {
        // The distinction matters: "clean" would let a wedged or off-topic run
        // read as an improvement.
        #expect(S.verdict(for: "Sure, what else can I help with?") == .unscorable)
        #expect(S.verdict(for: "") == .unscorable)
    }

    @Test func curlyApostrophesAreNormalised() {
        // The device emits U+2019, not ASCII. A scorer that misses it would
        // have scored BOTH real instances unscorable.
        #expect(S.verdict(for: "your calendar didn\u{2019}t accept the request") == .attributedToTool)
        #expect(S.verdict(for: "you didn\u{2019}t confirm it") == .attributedToUser)
    }

    /// **392-C's readability, at the scorer level.** The finding is that the
    /// defect is CALENDAR-ONLY — 2/10 there against 0/20 on remind and alarm —
    /// so a tally that does not split by surface literally cannot see the
    /// entry's central claim, and a treatment aimed at "declines" in general
    /// would be aimed at the wrong surface.
    @Test func theTallySplitsBySurfaceSoTheCalendarOnlyFindingStaysVisible() {
        let trials: [(surface: String, reply: String)] = [
            ("calendar", Self.deviceInstance1),
            ("calendar", "You declined, so nothing was created."),
            ("remind",   "You declined — no reminder was created."),
            ("alarm",    "You declined — no alarm was set."),
        ]
        let tally = S.tally(trials)

        #expect(tally["calendar"]?.misattributionRate == 0.5)
        #expect(tally["remind"]?.misattributionRate == 0)
        #expect(tally["alarm"]?.misattributionRate == 0)
        // A pooled rate would read 1/4 and hide that it is calendar-only.
        #expect(tally.count == 3)
    }

    /// **The denominator rule — #215's sibling lesson.**
    ///
    /// An instrument with no error bucket reports its own failures as
    /// behaviour. If unscorable replies counted in the denominator, a run
    /// where the model mostly went off-topic would show a *lower*
    /// misattribution rate and read as an improvement.
    @Test func unscorableRepliesAreExcludedFromTheDenominatorNotCountedAsClean() {
        var tally = S.Tally()
        tally.record(.attributedToTool)
        tally.record(.attributedToUser)
        tally.record(.unscorable)
        tally.record(.unscorable)

        #expect(tally.total == 4)
        #expect(tally.misattributionRate == 0.5, "unscorable trials must not dilute the rate")
    }

    @Test func aTallyOfNothingScorableReportsNilRatherThanZero() {
        var tally = S.Tally()
        tally.record(.unscorable)
        // Zero would read as "no misattributions", which is a claim this run
        // cannot support. nil is the honest answer (#180's tri-state rule).
        #expect(tally.misattributionRate == nil)
    }
}
