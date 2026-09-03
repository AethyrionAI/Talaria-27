import Foundation
import Testing
@testable import Talaria

/// #422 bar 422-A — the decode pin for `Message.memoryProvenance`.
///
/// The field is OPTIONAL and read with `decodeIfPresent` inside `Message`'s
/// EXISTING hand-written `init(from:)` (the #42 silent-wipe rule: a new
/// decoder would drop every field it forgot). These tests are the pin that
/// makes the optionality load-bearing rather than incidental — 296-E's RED
/// procedure ran them against a NON-optional declaration with a plain
/// `decode` first, and `aPre422CachedMessageDecodesWithNoProvenance` failed
/// with `keyNotFound(CodingKeys(stringValue: "memoryProvenance"…))` before
/// the optional landed.
struct MemoryProvenanceCodingTests {

    // MARK: - 422-A: legacy caches decode

    /// A pre-#422 cached row — the same shape `HostFailureConventionTests`
    /// pins for #180 — carries no `memoryProvenance` key at all. It must
    /// decode, and it must decode as "this reply drew on no memory".
    @Test func aPre422CachedMessageDecodesWithNoProvenance() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","sender":"hermes","content":"hi",
         "timestamp":0,"status":"delivered"}
        """.data(using: .utf8)!
        let old = try JSONDecoder().decode(Message.self, from: legacy)
        #expect(old.memoryProvenance == nil,
                "a pre-#422 cached reply must not read as having drawn on memory")
    }

    /// A row written by this build decodes to the case it names. The empty
    /// arrays are deliberate: the wire shape must not depend on the payload
    /// being non-empty.
    @Test func aStoredLocalProvenanceDecodesToTheLocalCase() throws {
        let json = """
        {"id":"\(UUID().uuidString)","sender":"hermes","content":"hi",
         "timestamp":0,"status":"delivered",
         "memoryProvenance":{"local":{"entryIDs":[],"noteIDs":[],"savedNoteID":null}}}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Message.self, from: json)
        #expect(decoded.memoryProvenance == .local(entryIDs: [], noteIDs: [], savedNoteID: nil))
    }

    // MARK: - Round trip

    @Test func aLocalProvenanceSurvivesTheConversationCacheRoundTrip() throws {
        let entryA = UUID(), entryB = UUID(), note = UUID(), saved = UUID()
        let original = Message(
            sender: .hermes, content: "I remember.", status: .delivered,
            memoryProvenance: .local(entryIDs: [entryA, entryB],
                                     noteIDs: [note],
                                     savedNoteID: saved)
        )
        let decoded = try JSONDecoder().decode(
            Message.self, from: try JSONEncoder().encode(original))
        #expect(decoded.memoryProvenance == .local(entryIDs: [entryA, entryB],
                                                   noteIDs: [note],
                                                   savedNoteID: saved))
    }

    @Test func aHostProvenanceSurvivesTheConversationCacheRoundTrip() throws {
        let original = Message(
            sender: .hermes, content: "The host looked it up.", status: .delivered,
            memoryProvenance: .host(observedTools: ["honcho_search"])
        )
        let decoded = try JSONDecoder().decode(
            Message.self, from: try JSONEncoder().encode(original))
        #expect(decoded.memoryProvenance == .host(observedTools: ["honcho_search"]))
    }

    // MARK: - The conditional-encode pin

    /// Nil provenance writes NO key — the overwhelmingly common row stays the
    /// size it was, and a cache written by this build is still readable by a
    /// build that predates the field.
    @Test func aMessageWithNoProvenanceEncodesWithoutTheKey() throws {
        let message = Message(sender: .hermes, content: "hi", status: .delivered)
        #expect(message.memoryProvenance == nil)
        let object = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(message)) as? [String: Any]
        let keys = try #require(object).keys
        #expect(!keys.contains("memoryProvenance"),
                "an absent provenance must not be written as an explicit null")
    }

    // MARK: - Chip labels (the naming ruling, verbatim)

    @Test func chipLabelsMatchTheRuledStringsExactly() {
        #expect(MemoryProvenance.local(entryIDs: [UUID()], noteIDs: [], savedNoteID: nil)
            .chipLabel == "ON-DEVICE MEMORY")
        #expect(MemoryProvenance.local(entryIDs: [], noteIDs: [], savedNoteID: UUID())
            .chipLabel == "SAVED TO MEMORY")
        #expect(MemoryProvenance.host(observedTools: []).chipLabel == "HERMES MEMORY")
        #expect(MemoryProvenance.host(observedTools: ["honcho_search"])
            .chipLabel == "HERMES MEMORY · honcho_search")
    }
}
