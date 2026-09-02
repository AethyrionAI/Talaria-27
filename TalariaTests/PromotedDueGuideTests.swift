import Foundation
import FoundationModels
import Testing
@testable import Talaria

/// **#340-P-A — the promoted `due` guide, pinned on the PRODUCTION type.**
///
/// The 340-H5′-A/B device A/B (2026-08-27, n=40/arm, Debug build 3125, iOS
/// `24A5424a`) put `armed-bareclock` against production `armed` and both bars
/// were met: the union `omitted + wrong-value` FELL 87.5% → 47.5%
/// (p = 2.54e-04) and `populated-future` ROSE 0% → 45% (p = 6.38e-07), with
/// `wrong-value` 0/40 in both arms and `no-call` falling rather than rising.
/// This entry's own promotion condition — *"Then, and only then, the guide
/// text promotes"* — was satisfied that night and then sat unexecuted for five
/// days, because nothing in the tree could tell that production still carried
/// the losing text. This file is that thing.
///
/// **Why a schema pin rather than a source grep.** Every prior note in this
/// entry says `@Guide` "has no runtime accessor, so the text is pinned by
/// comment and measured by the battery." That is true of the macro's *argument*
/// and false of its *effect*: `@Generable` lowers each `@Guide(description:)`
/// into `Arguments.generationSchema`, which is `Codable`, so the string the
/// model will actually be shown is readable at runtime. Pinning the schema
/// rather than the source line means this test fails if the text is reverted
/// AND if some future refactor stops the text reaching the model at all —
/// a source grep can only see the first.
struct PromotedDueGuideTests {

    /// The text the 08-27 A/B measured, verbatim from the winning arm
    /// (`ReminderCreateToolBareclock`, retired in the same commit that promoted
    /// this). Retyping it would defeat the point, so it is transcribed once,
    /// here, and compared against the schema rather than against another copy.
    static let winningBareclockGuide =
        "Due time. Give just the clock time the user said, like \"16:30\" or \"9am\" — the app works out which day it means. Use a full \"2026-07-08T09:00\" only when the user named a specific date. Leave empty ONLY when the user asked for no due date at all."

    /// The losing text production shipped from #200S until 2026-09-01. Kept so
    /// a revert is caught positively rather than only by absence — and so the
    /// RED this test was born in is reproducible.
    static let supersededDueGuide =
        "Due date and time like \"2026-07-08T09:00\" (local time), or empty for no due date."

    /// The `@Guide` descriptions as the model will be shown them, keyed by
    /// property name.
    ///
    /// **Decoded, never string-searched.** The first draft of this test did
    /// `encodedJSON.contains(text)` and it was a bad instrument in both
    /// directions: the schema JSON escapes the embedded quotes in
    /// `\"16:30\"`, so a raw Swift literal can never match it — the positive
    /// assertion went RED for the escaping rather than for the text, and the
    /// negative one ("the old guide is gone") passed VACUOUSLY while the old
    /// guide was still sitting right there in the payload. Decoding the field
    /// and comparing with `==` has neither failure mode.
    private static func guideDescriptions() throws -> [String: String] {
        let data = try JSONEncoder().encode(ReminderCreateTool.Arguments.generationSchema)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let properties = try #require(root?["properties"] as? [String: Any],
                                      "generationSchema has no `properties` object: \(String(decoding: data, as: UTF8.self))")
        return properties.reduce(into: [:]) { out, entry in
            if let body = entry.value as? [String: Any], let text = body["description"] as? String {
                out[entry.key] = text
            }
        }
    }

    /// 340-P-A. Watched RED against the old guide before the swap.
    @Test func productionDueGuideIsTheWinningBareclockText() throws {
        let guides = try Self.guideDescriptions()
        let due = try #require(guides["due"], "no `due` property in the schema: \(guides)")
        #expect(due == Self.winningBareclockGuide,
                "production `due` guide is not the 340-H5′ winner; it is: \(due)")
        #expect(due != Self.supersededDueGuide,
                "production still carries the pre-promotion `due` guide")
    }

    /// The mechanism check, so a RED above is attributable. If the schema
    /// carried no descriptions at all — or stopped carrying them after some
    /// future refactor — the pin above would fail for a reason that has
    /// nothing to do with #340. This one says which it is. `title` and `list`
    /// are untouched by the promotion, so they double as the control.
    @Test func theSchemaCarriesEveryGuideText() throws {
        let guides = try Self.guideDescriptions()
        #expect(Set(guides.keys) == ["title", "due", "list"],
                "the reminder schema's shape moved: \(guides.keys.sorted())")
        #expect(guides["title"] == "What to be reminded about, e.g. \"Call Shelley\".")
        #expect(guides["list"] == "Reminders list name, or empty for the default list.")
    }
}
