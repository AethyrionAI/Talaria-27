import Foundation
import Testing
@testable import Talaria

/// #362 3D: the typed parse of a plugin-channel artifact item. The mirror
/// hook appends `kind="artifact"` rows whose meta carries the correlation
/// fields; everything else on the drain (today's `kind="message"` inbox
/// items included) must parse to nil here so routing stays honest.
struct ArtifactMirrorItemTests {

    private func platformItem(
        id: String = "item-1",
        kind: String = "artifact",
        text: String = "file contents",
        meta: [String: String]? = [
            "session_id": "s1",
            "turn_id": "s1:s1:deadbeef",
            "tool_call_id": "call-1",
            "path": "notes/a.txt",
            "ts": "2026-08-17T23:00:00+00:00",
            "type": "written_file",
        ]
    ) -> TalariaPlatformItem {
        TalariaPlatformItem(
            id: id, kind: kind, text: text,
            createdAt: "2026-08-17T23:00:00+00:00", meta: meta
        )
    }

    @Test func parsesTheFullMirrorShape() {
        let parsed = ArtifactMirrorItem.parse(platformItem())

        #expect(parsed?.platformItemID == "item-1")
        #expect(parsed?.sessionID == "s1")
        #expect(parsed?.path == "notes/a.txt")
        #expect(parsed?.content == "file contents")
        #expect(parsed?.turnID == "s1:s1:deadbeef")
        #expect(parsed?.toolCallID == "call-1")
        #expect(parsed?.hostTimestamp == "2026-08-17T23:00:00+00:00")
    }

    @Test func messageKindParsesToNil() {
        // The inbox's items must never be mistaken for artifacts, whatever
        // their meta happens to carry.
        #expect(ArtifactMirrorItem.parse(platformItem(kind: "message")) == nil)
    }

    @Test func missingSessionIDParsesToNil() {
        var meta = [
            "turn_id": "t", "tool_call_id": "c", "path": "a.txt",
        ]
        #expect(ArtifactMirrorItem.parse(platformItem(meta: meta)) == nil)
        meta["session_id"] = ""
        #expect(ArtifactMirrorItem.parse(platformItem(meta: meta)) == nil)
    }

    @Test func missingPathParsesToNil() {
        #expect(ArtifactMirrorItem.parse(platformItem(meta: ["session_id": "s1"])) == nil)
        #expect(
            ArtifactMirrorItem.parse(platformItem(meta: ["session_id": "s1", "path": ""])) == nil
        )
    }

    @Test func absentMetaParsesToNil() {
        #expect(ArtifactMirrorItem.parse(platformItem(meta: nil)) == nil)
    }

    @Test func emptyContentIsARealFile() {
        // Writing an empty file is a real write; empty text is not "missing".
        let parsed = ArtifactMirrorItem.parse(platformItem(text: ""))
        #expect(parsed != nil)
        #expect(parsed?.content == "")
    }

    @Test func optionalMetaFieldsMayBeAbsent() {
        // Only session_id + path are load-bearing; the bookkeeping fields
        // (turn_id, tool_call_id, ts) ride along when present.
        let parsed = ArtifactMirrorItem.parse(
            platformItem(meta: ["session_id": "s1", "path": "a.txt"])
        )
        #expect(parsed != nil)
        #expect(parsed?.turnID == nil)
        #expect(parsed?.toolCallID == nil)
        #expect(parsed?.hostTimestamp == nil)
    }
}
