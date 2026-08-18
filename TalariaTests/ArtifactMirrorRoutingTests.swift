import Foundation
import Testing
@testable import Talaria

/// #362 3D-C: artifact items fork away from the inbox at the drain.
struct ArtifactMirrorRoutingTests {

    private func item(
        id: String, kind: String, text: String = "t", meta: [String: String]? = nil
    ) -> TalariaPlatformItem {
        TalariaPlatformItem(
            id: id, kind: kind, text: text,
            createdAt: "2026-08-17T23:00:00+00:00", meta: meta
        )
    }

    @Test func artifactsForkAwayFromInboxItems() {
        let artifact = item(
            id: "a1", kind: "artifact", text: "content",
            meta: ["session_id": "s1", "path": "a.txt"]
        )
        let message = item(id: "m1", kind: "message", text: "hello")

        let split = ArtifactMirrorRouting.split([artifact, message])

        #expect(split.artifacts.map(\.platformItemID) == ["a1"])
        #expect(split.passthrough == [message])
    }

    @Test func malformedArtifactGoesNowhere() {
        // A mirror item without its correlation meta cannot attach anywhere,
        // and its text is file content — the inbox must never render it.
        let malformed = item(id: "a1", kind: "artifact", text: "secret file bytes")
        let split = ArtifactMirrorRouting.split([malformed])
        #expect(split.artifacts.isEmpty)
        #expect(split.passthrough.isEmpty)
    }

    @Test func unknownKindsPassThroughUntouched() {
        // Forward-compat: only "artifact" forks; future kinds keep flowing
        // to the inbox exactly like "message" does today.
        let odd = item(id: "x1", kind: "banner", text: "hi")
        let message = item(id: "m1", kind: "message", meta: ["chat_id": "d1"])
        let split = ArtifactMirrorRouting.split([odd, message])
        #expect(split.artifacts.isEmpty)
        #expect(split.passthrough == [odd, message])
    }

    @Test func orderIsPreservedWithinEachFork() {
        let a1 = item(id: "a1", kind: "artifact", meta: ["session_id": "s", "path": "1.txt"])
        let m1 = item(id: "m1", kind: "message")
        let a2 = item(id: "a2", kind: "artifact", meta: ["session_id": "s", "path": "2.txt"])
        let m2 = item(id: "m2", kind: "message")
        let split = ArtifactMirrorRouting.split([a1, m1, a2, m2])
        #expect(split.artifacts.map(\.platformItemID) == ["a1", "a2"])
        #expect(split.passthrough.map(\.id) == ["m1", "m2"])
    }
}
