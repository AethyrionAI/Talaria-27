import Foundation
import Testing
@testable import Talaria

/// #338 — the honesty guard's PRODUCTION half: the settle-point application,
/// the counter (#338-E), the log line, and the composition the user sees.
///
/// `ActionClaimDetectorTests` pins the pure detector against the real
/// artifacts. This file pins what `LocalChatBackend` does with its verdict —
/// the half a table of strings cannot reach: that the model's text survives
/// verbatim, that a normal turn is untouched, that a firing is counted, and
/// that the guard is an identity function whenever a tool call ran.
///
/// `@MainActor` because the backend is.
@MainActor
struct HonestyGuardWiringTests {

    private func makeBackend() -> LocalChatBackend {
        LocalChatBackend(
            persistence: UserDefaultsAppPersistenceStore(
                defaults: UserDefaults(suiteName: "honesty-guard-wiring-tests")!
            ),
            intelligence: LocalIntelligenceService()
        )
    }

    /// The #337-A production reply, verbatim.
    private static let productionDefect =
        "**Confirmation card:** A reminder to \"take out the trash\" at 8 AM has been created."

    // MARK: - The response shape (#338's ruling clause)

    @Test("338: the model's text survives VERBATIM as the prefix — nothing is rewritten or deleted")
    func modelTextIsNeverRewritten() {
        let backend = makeBackend()
        let out = backend.honestyGuardedReply(
            modelText: Self.productionDefect,
            settledText: Self.productionDefect,
            executedToolNames: [])
        #expect(out.hasPrefix(Self.productionDefect),
                "silent rewriting is its own trust problem — the entry says APPEND")
        #expect(out.contains(LocalChatBackend.honestyCorrectionNotice))
        #expect(out == Self.productionDefect + "\n\n" + LocalChatBackend.honestyCorrectionNotice)
    }

    @Test("338: the correction is one named constant and it is visibly distinct")
    func theCorrectionIsOneNamedConstant() {
        let notice = LocalChatBackend.honestyCorrectionNotice
        #expect(!notice.isEmpty)
        #expect(notice.contains("\u{26A0}\u{FE0F}"), "a visibly distinct marker, not prose that blends in")
        // It must not itself read as a completed-action claim — otherwise a
        // corrected reply replayed as history could arm the guard again.
        #expect(ActionClaimDetector.claims(in: notice).isEmpty,
                "the correction must be claim-free: \(ActionClaimDetector.claims(in: notice))")
        // It must not promise a retry will work — #337 measured 0/90 creations.
        let lowered = notice.lowercased()
        #expect(!lowered.contains("try again"))
        #expect(!lowered.contains("ask me again"))
    }

    @Test("338: an empty model reply still gets an honest correction, not an empty bubble")
    func emptySettledTextStillCarriesTheCorrection() {
        #expect(LocalChatBackend.appendingHonestyCorrection(to: "")
                == LocalChatBackend.honestyCorrectionNotice)
    }

    @Test("338: the correction attaches to the SETTLED text, so an appended block survives")
    func theCorrectionFollowsTheSettledText() {
        let backend = makeBackend()
        let settled = Self.productionDefect + "\n\nI can read your calendar and reminders."
        let out = backend.honestyGuardedReply(
            modelText: Self.productionDefect, settledText: settled, executedToolNames: [])
        #expect(out.hasPrefix(settled))
        #expect(out.hasSuffix(LocalChatBackend.honestyCorrectionNotice))
    }

    // MARK: - 338-D: production safety

    @Test("338-D: a normal successful turn is untouched — the guard is an identity function")
    func normalTurnIsUntouched() {
        let backend = makeBackend()
        let honest = "Here\u{2019}s a haiku about sledding:\n\nSnow flies fast,  \nLaughter echoes down the hill\u{2014}  \nWinter\u{2019}s wild ride."
        #expect(backend.honestyGuardedReply(
            modelText: honest, settledText: honest, executedToolNames: []) == honest)
        #expect(backend.honestyGuardFireCount == 0)
        #expect(backend.lastHonestyGuardClaim == nil)
    }

    @Test("338-D: an honest OFFER is untouched")
    func honestOfferIsUntouched() {
        let backend = makeBackend()
        let offer = "Here\u{2019}s the confirmation:\n\n- **Title**: Test Talaria  \n- **Time**: 4:30 PM today  \n\nWould you like me to create this reminder?"
        #expect(backend.honestyGuardedReply(
            modelText: offer, settledText: offer, executedToolNames: []) == offer)
        #expect(backend.honestyGuardFireCount == 0)
    }

    @Test("338-D: a turn that DID execute its action tool is untouched",
          arguments: ["createReminder", "createCalendarEvent", "scheduleAlarm"])
    func executedActionTurnIsUntouched(_ tool: String) {
        let backend = makeBackend()
        // The real F6C46C82 row that DID call the tool and DID say so.
        let honestClaim = "I\u{2019}ve set a reminder for you to test Talaria at 4:30 PM. Anything else?"
        #expect(backend.honestyGuardedReply(
            modelText: honestClaim, settledText: honestClaim, executedToolNames: [tool]) == honestClaim)
        #expect(backend.honestyGuardFireCount == 0)
        // …and it is untouched even alongside read calls in the same turn.
        #expect(backend.honestyGuardedReply(
            modelText: honestClaim, settledText: honestClaim,
            executedToolNames: ["currentWeather", tool, "readCalendar"]) == honestClaim)
        #expect(backend.honestyGuardFireCount == 0)
    }

    @Test("338-D: the guard returns text on every path and never throws")
    func theGuardNeverThrows() {
        // #197's rule, stated as a type fact: `honestyGuardedReply` is not
        // `throws`, so no caller on the tool path can gain a throw from it.
        // The test that would BITE is a compile failure, so this asserts the
        // behavioural half — every input yields a string.
        let backend = makeBackend()
        for text in ["", " ", Self.productionDefect, "I've set a reminder.", "haiku"] {
            let out = backend.honestyGuardedReply(
                modelText: text, settledText: text, executedToolNames: [])
            #expect(out.hasPrefix(text) || out == LocalChatBackend.honestyCorrectionNotice)
        }
    }

    // MARK: - 338-E: counted

    @Test("338-E: every firing increments the counter and records the claim")
    func firingsAreCounted() {
        let backend = makeBackend()
        #expect(backend.honestyGuardFireCount == 0)

        _ = backend.honestyGuardedReply(
            modelText: Self.productionDefect, settledText: Self.productionDefect,
            executedToolNames: [])
        #expect(backend.honestyGuardFireCount == 1)
        #expect(backend.lastHonestyGuardClaim?.kind == .impersonatedCard)

        // #336's fabricated alarm row.
        _ = backend.honestyGuardedReply(
            modelText: "I\u{2019}ve set the alarm for 6:30. Let me know if you need anything else!",
            settledText: "I\u{2019}ve set the alarm for 6:30. Let me know if you need anything else!",
            executedToolNames: [])
        #expect(backend.honestyGuardFireCount == 2)
        #expect(backend.lastHonestyGuardClaim?.kind == .firstPersonCreation)

        // A quiet turn must not move the counter.
        _ = backend.honestyGuardedReply(
            modelText: "Would you like me to set an alarm for 6:30?",
            settledText: "Would you like me to set an alarm for 6:30?",
            executedToolNames: [])
        #expect(backend.honestyGuardFireCount == 2)
    }

    @Test("338-E: the log line is stable and carries the grep key")
    func logLineShape() {
        let line = LocalChatBackend.honestyGuardLogLine(
            kind: .impersonatedCard, executedCalls: 0, fireCount: 1)
        #expect(line == "honesty-guard FIRED impersonatedCard — 0 tool call(s) executed this turn, 1 firing(s) this session (#338)")
        // Every claim kind renders.
        for kind in ActionClaimDetector.ClaimKind.allCases {
            let rendered = LocalChatBackend.honestyGuardLogLine(kind: kind, executedCalls: 2, fireCount: 7)
            #expect(rendered.contains("honesty-guard FIRED"))
            #expect(rendered.contains(kind.rawValue))
            #expect(rendered.contains("(#338)"))
        }
    }

    // MARK: - The defect, end to end through the production composition

    @Test("338: the #337-A reply composed through the settle point comes out honest")
    func theProductionDefectIsCorrected() {
        let backend = makeBackend()
        // Exactly what `send`/`streamTurn` do: settle first, then guard.
        let settled = LocalChatBackend.settledReplyContent(
            Self.productionDefect, appendingCapabilityAnswer: false)
        let userSees = backend.honestyGuardedReply(
            modelText: Self.productionDefect, settledText: settled, executedToolNames: [])
        #expect(userSees != Self.productionDefect, "the user must not see the bare lie")
        #expect(userSees.contains("has been created"), "the model's own words are still there to diagnose")
        #expect(userSees.contains("nothing was actually created"))
        #expect(backend.honestyGuardFireCount == 1)
    }
}
