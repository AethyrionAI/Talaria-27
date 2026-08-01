#if DEBUG
import Foundation
import Testing
@testable import Talaria

/// #217 — the intent vocabulary, and the one property that makes an intent
/// router safe to consider at all.
///
/// #216 priced the prize: scoping the calendar turn's belt cut it from 6.1s to
/// 3.5s and from 2,269 input tokens to 976, at no cost to creates or
/// composition. It is not promotable because `scopedBelt` keys on `promptTag`
/// and production has no `promptTag` — `routeNeedsDeviceTool` returns a Bool, so
/// production can decide WHETHER to arm but never WHAT to arm with.
///
/// **The danger this file exists to contain.** A Bool router that is wrong
/// degrades to the full belt, which is today's behaviour — the failure is free.
/// An INTENT router that is wrong arms the *wrong* belt, and a turn that needed
/// `createCalendarEvent` holding only health tools is **strictly worse than
/// arming everything.** So the vocabulary must have a total, lenient parse where
/// everything unrecognised lands on `.other`, and `.other` must mean the full
/// belt.
///
/// These tests pin that. They do not test classification accuracy — that is a
/// device probe, because it is a question about the model, not the code.
struct RouterIntentTests {

    // MARK: The vocabulary is closed, and closed over the guide

    /// The `@Guide(.anyOf(…))` vocabulary handed to the model and the cases the
    /// code can parse must be the same set. If a value is offered to the model
    /// that the parser does not know, the model can answer it and be scored
    /// wrong for a reason that has nothing to do with the model.
    @Test func theGuideVocabularyIsExactlyTheParseableCases() {
        let guided = Set(RouterIntent.guideVocabulary)
        let parseable = Set(RouterIntent.allCases.map(\.rawValue))
        #expect(guided == parseable)
    }

    /// `.other` must be offered too. Without it the model has no way to say "I
    /// don't know" and is pushed into guessing one of the scoped intents —
    /// converting safe misses into dangerous wrong answers, which is the exact
    /// failure mode this design is built around.
    @Test func theModelIsGivenAWayToSayItDoesNotKnow() {
        #expect(RouterIntent.guideVocabulary.contains(RouterIntent.other.rawValue))
    }

    // MARK: The parse is TOTAL — every unrecognised answer is safe

    /// #209's finding applied in advance: a required Swift `String` is satisfied
    /// by `""`, so a model with nothing to say emits an empty string rather than
    /// omitting the field. That must not be a crash, and it must not be a
    /// scoped intent.
    @Test func theEmptyStringParsesToOther() {
        #expect(RouterIntent(lenient: "") == .other)
    }

    /// Anything at all. The point is that no input reaches a scoped intent by
    /// accident — a hallucinated value, a prose sentence, a value from a future
    /// vocabulary this build does not know.
    @Test func everyUnrecognisedAnswerParsesToOther() {
        for junk in ["  ", "todo", "REMINDERS", "calendar event", "🌤️",
                     "I think this is about the calendar", "none", "nil",
                     "reminder;calendar", String(repeating: "a", count: 5_000)] {
            #expect(RouterIntent(lenient: junk) == .other,
                    "\(junk.prefix(20)) must not reach a scoped intent")
        }
    }

    /// The recognised values round-trip. Case and surrounding whitespace are
    /// forgiven, because a model emitting `"Calendar"` means calendar and
    /// scoring it `.other` would understate accuracy for a formatting reason.
    @Test func recognisedValuesRoundTripAndForgiveCaseAndSpace() {
        for intent in RouterIntent.allCases {
            #expect(RouterIntent(lenient: intent.rawValue) == intent)
            #expect(RouterIntent(lenient: intent.rawValue.uppercased()) == intent)
            #expect(RouterIntent(lenient: "  \(intent.rawValue)\n") == intent)
        }
    }

    // MARK: The safety property

    /// **The load-bearing assertion of the whole design.** `.other` is the
    /// fallback for every failure — an unparseable answer, a thrown generation,
    /// a vocabulary mismatch — so if `.other` ever meant anything narrower than
    /// "everything", every one of those failures would silently disarm a turn.
    ///
    /// Deliberately phrased as "is the full belt", not "is non-empty": a
    /// fallback that armed *some* tools would still be a regression against
    /// today, and would still pass a non-emptiness check.
    @Test func otherIsTheFullBeltSoEveryFailureDegradesToTodaysBehaviour() {
        #expect(RouterIntent.other.scopesTheBelt == false)
        // And it is the ONLY case that does not scope — otherwise some intent
        // would be silently inert and the probe would score it as a win.
        let nonScoping = RouterIntent.allCases.filter { !$0.scopesTheBelt }
        #expect(nonScoping == [.other])
    }
}
#endif
