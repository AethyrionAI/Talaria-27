import XCTest

/// **Unit-level coverage for the snapshot parser (#219, fix round 1).**
///
/// `HittableTap`'s centre-point walk is a DIAGNOSTIC, and a diagnostic that is
/// wrong fails silently: it names the wrong element and nothing reds. Its four
/// pure statics (`rows(fromDebugDescription:)`, `frame(inLine:)`,
/// `elementType(inLine:)`, `identifier(inLine:)`) therefore get a test that
/// launches no app and runs in milliseconds.
///
/// **Every number below was MEASURED, not recalled.** The fixture is one real
/// `XCUIApplication.debugDescription`, captured verbatim from a fixture run on
/// 2026-09-04 (Xcode-beta6 27A5252f, simulator `CC-lane-3`, iOS 27.0 runtime
/// 24A5423a) at the moment `testOverlayFixtureMakesStartChattingUnhittable`
/// reaches step 3 with the blocking overlay armed. Its expected parse was then
/// computed by an independent re-implementation of the same rules
/// (`scratchpad/fix1-parse-check.py`) rather than by reading this parser back
/// to itself.
final class HittableTapParserTests: XCTestCase {

    /// One `XCUIApplication.debugDescription`, verbatim — including the
    /// `Attributes:` root line, the `Element subtree:` header, and the
    /// trailing `Path to element:` / `Query chain:` sections the parser must
    /// stop at.
    private static let recordedDump = """
Attributes: Application, 0x11124a6c0, pid: 69888, label: 'Talaria27'
Element subtree:
 →Application, 0x11124a6c0, pid: 69888, label: 'Talaria27'
    Window (Main), 0x111249b80, {{0.0, 0.0}, {420.0, 912.0}}
      Other, 0x111249cc0, {{0.0, 0.0}, {420.0, 912.0}}
        Other, 0x111249e00, {{0.0, 0.0}, {420.0, 912.0}}
          Other, 0x111249f40, {{0.0, 0.0}, {420.0, 912.0}}
            Other, 0x11124a080, {{0.0, 0.0}, {420.0, 912.0}}
              Other, 0x11124a1c0, {{0.0, 0.0}, {420.0, 912.0}}
                Other, 0x11124a300, {{0.0, 0.0}, {420.0, 912.0}}
                  Other, 0x11124a580, {{0.0, 0.0}, {420.0, 912.0}}
                    Other, 0x1112483c0, {{0.0, 0.0}, {420.0, 912.0}}
                      Other, 0x111248280, {{0.0, 0.0}, {420.0, 912.0}}
                        Button, 0x11124a800, {{24.0, 89.7}, {12.3, 17.0}}, identifier: 'chevron.left', label: 'Back'
                        Button, 0x1112488c0, {{335.7, 88.3}, {60.3, 19.3}}, identifier: 'connectHostWizard.notNow', label: 'Not now'
                        ScrollView, 0x111248500, {{0.0, 127.0}, {420.0, 785.0}}
                          Other, 0x11124b700, {{0.0, 127.0}, {420.0, 462.0}}
                            StaticText, 0x11124b480, {{24.0, 151.0}, {106.3, 39.0}}, label: 'YOU'RE'
                            StaticText, 0x111248000, {{24.0, 190.0}, {176.7, 39.0}}, label: 'CONNECTED'
                            StaticText, 0x11124b200, {{24.0, 253.0}, {358.3, 38.3}}, label: '127.0.0.1 is answering. Your desktop models are in the picker, and sessions now live on the host.'
                            StaticText, 0x111248c80, {{24.0, 324.7}, {221.3, 19.3}}, label: 'Pick a desktop model any time'
                            StaticText, 0x11124b840, {{351.3, 327.7}, {44.7, 13.3}}, label: 'MODELS'
                            StaticText, 0x11124b980, {{24.0, 353.7}, {282.7, 38.3}}, label: 'Sensor sharing stays off until you turn it on'
                            StaticText, 0x11124be80, {{344.0, 366.2}, {52.0, 13.3}}, label: 'PRIVACY'
                            StaticText, 0x111248b40, {{24.0, 401.7}, {192.0, 19.3}}, label: 'Add another machine later'
                            StaticText, 0x11124bc00, {{359.0, 404.7}, {37.0, 13.3}}, label: 'HOSTS'
                            StaticText, 0x11124af80, {{24.0, 454.3}, {360.7, 30.7}}, label: 'All of this lives in Settings → Connect Host — edit the address, swap the key, or disconnect there.'
                            Button, 0x11124a940, {{24.0, 509.0}, {372.0, 56.0}}, identifier: 'connectHostWizard.startChatting', label: 'START CHATTING'
                          Other, 0x11124aa80, {{387.0, 127.0}, {30.0, 723.0}}, label: 'Vertical scroll bar, 1 page', value: 0%
                            Other, 0x111249680, {{414.0, 363.7}, {3.0, 483.3}}
                          Other, 0x111248640, {{387.0, 127.0}, {30.0, 723.0}}, label: 'Vertical scroll bar, 1 page', value: 0%
                            Other, 0x1112492c0, {{414.0, 363.7}, {3.0, 483.3}}
                        Other, 0x111249400, {{24.0, 124.0}, {372.0, 3.0}}
                        Other, 0x111248f00, {{0.0, 68.0}, {420.0, 810.0}}, identifier: 'uitest.overlayBlocksWizard', label: 'uitest overlay', value: 0
                Toolbar, 0x1112497c0, {{0.0, 0.0}, {420.0, 912.0}}, identifier: 'Toolbar', label: 'Toolbar'
                  Other, 0x111249900, {{0.0, 0.0}, {420.0, 912.0}}
    Window, 0x111249a40, {{0.0, 0.0}, {420.0, 912.0}}
      Other, 0x11124abc0, {{0.0, 0.0}, {420.0, 912.0}}
        Other, 0x11124ad00, {{0.0, 0.0}, {420.0, 912.0}}
Path to element:
 →Application, 0x11124a6c0, pid: 69888, label: 'Talaria27'
Query chain:
 →Find: Target Application 'org.aethyrion.talaria27'
  Output: {
    Application, 0x105a23480, pid: 69888, label: 'Talaria27'
  }
"""

    func testParsesTheRecordedDumpAndSkipsTheAttributesRootLine() {
        let rows = HittableTap.rows(fromDebugDescription: Self.recordedDump)

        XCTAssertEqual(
            rows.count, 36,
            "the recorded dump carries 36 framed elements before 'Path to element'"
        )

        // **The root-line decision, pinned.** On THIS toolchain the
        // `Attributes:` line carries no frame (`pid:` and `label:` only), so
        // the frame guard alone already drops it — which means the hazard is
        // latent and a test that only used the recorded bytes would prove
        // nothing about it. The second arm below is the one that bites: a root
        // line that DOES print the application's frame must still not become a
        // row, or the walk reports a full-screen phantom typed "Attributes:"
        // at index 1, over every centre point there is.
        XCTAssertFalse(
            rows.contains { $0.type == "Attributes:" },
            "the dump's root line is not an element and must never parse as one"
        )
        let rootLineWithAFrame = """
            Attributes: Application, 0x11124a6c0, {{0.0, 0.0}, {420.0, 912.0}}, label: 'Talaria27'
            """
        let dumpWithFramedRoot = rootLineWithAFrame + "\n" + Self.recordedDump
        let rowsWithFramedRoot = HittableTap.rows(fromDebugDescription: dumpWithFramedRoot)
        XCTAssertEqual(
            rowsWithFramedRoot.count, 36,
            """
            a root line that carries a frame must be SKIPPED, not parsed — got \
            \(rowsWithFramedRoot.count) rows, first=\(rowsWithFramedRoot.first.map(String.init(describing:)) ?? "none")
            """
        )

        // Field extraction, on the two rows the DET-A bar actually reads.
        guard let button = rows.first(where: { $0.identifier == "connectHostWizard.startChatting" }) else {
            XCTFail("the recorded dump contains the START CHATTING button")
            return
        }
        XCTAssertEqual(button.type, "Button")
        XCTAssertEqual(button.frame, CGRect(x: 24, y: 509, width: 372, height: 56))

        guard let overlay = rows.first(where: { $0.identifier == "uitest.overlayBlocksWizard" }) else {
            XCTFail("the recorded dump contains the fixture overlay")
            return
        }
        XCTAssertEqual(overlay.type, "Other")
        XCTAssertEqual(overlay.frame, CGRect(x: 0, y: 68, width: 420, height: 810))

        // The walk, over the same bytes the fixture run walked.
        let centre = CGPoint(x: button.frame.midX, y: button.frame.midY)
        XCTAssertEqual(centre, CGPoint(x: 210, y: 537))
        let covering = rows.filter { $0.frame.contains(centre) }
        XCTAssertEqual(covering.count, 19, "19 of the 36 rows contain the button's centre point")

        // **Why the cap keeps BOTH ends.** With the fixture's
        // `.accessibilitySortPriority(-1000)` the blocker lands at covering
        // position 14 of 19 — inside a tail-6 window, outside a head-6 one.
        // Without a sort priority SwiftUI reports a ZStack front-to-back and
        // the blocker would land near position 1. Head 6 + tail 6 names it
        // either way; the old `suffix(12)` would not have.
        XCTAssertEqual(
            covering.firstIndex(where: { $0.identifier == "uitest.overlayBlocksWizard" }), 13,
            "the blocker sits at covering position 14 (0-based 13) in the recorded dump"
        )
        let half = HittableTap.maximumElementsUnderPoint / 2
        let shown = Array(covering.enumerated().prefix(half)) + Array(covering.enumerated().suffix(half))
        XCTAssertEqual(shown.count, HittableTap.maximumElementsUnderPoint)
        XCTAssertTrue(
            shown.contains { $0.element.identifier == "uitest.overlayBlocksWizard" },
            "head \(half) + tail \(half) must still NAME the blocker — that is bar DET-A"
        )

        // The parser stops at `Path to element`: an appended framed row after
        // that marker must not appear.
        let withTrailingRow = Self.recordedDump + "\n  Other, 0xdead, {{1.0, 2.0}, {3.0, 4.0}}, identifier: 'must.not.parse'"
        XCTAssertFalse(
            HittableTap.rows(fromDebugDescription: withTrailingRow).contains { $0.identifier == "must.not.parse" },
            "rows after 'Path to element' repeat the tree and must not double-count"
        )

        // The three field statics, on their tolerances rather than their
        // happy path.
        XCTAssertEqual(HittableTap.elementType(inLine: " \u{2192}Application, 0x1, pid: 1"), "Application",
                       "the root marker and indentation are noise")
        XCTAssertEqual(HittableTap.elementType(inLine: "    Window (Main), 0x1, {{0.0, 0.0}, {1.0, 1.0}}"), "Window",
                       "a parenthetical qualifier is not part of the type")
        XCTAssertNil(HittableTap.frame(inLine: "Element subtree:"),
                     "a line with no frame yields nil rather than a zero rect")
        XCTAssertNil(HittableTap.frame(inLine: "Attributes: Application, 0x1, pid: 1, label: 'Talaria27'"),
                     "the recorded root line carries no frame on this toolchain")
        XCTAssertEqual(HittableTap.identifier(inLine: "    Window (Main), 0x1, {{0.0, 0.0}, {1.0, 1.0}}"), "",
                       "an element with no identifier reports an empty one, which is itself a finding")
    }
}
