import Foundation

/// #422 ruling 2 — how a reply came to draw on memory, so the transcript can
/// say so. Every stored row carries a resolvable source: the local case names
/// the indexed entries and explicit notes that were injected (and the note
/// this turn SAVED, when it saved one); the host case names the memory-plugin
/// tools that were actually observed running.
///
/// OPTIONAL on `Message` (`var memoryProvenance: MemoryProvenance?`) and read
/// with `decodeIfPresent` — the #42 silent-wipe rule, the same reasoning
/// `ToolActivity.provenance` documents. `nil` = this reply drew on no memory,
/// which is also what every pre-#422 cached row decodes to, and no chip
/// renders.
///
/// Ruling 3: a `.host` value is minted ONLY from an observed `tool.started`
/// whose name is in the memory-plugin tool set — never inferred, and never
/// written into the local store. Local and host provenance are never merged.
enum MemoryProvenance: Codable, Hashable, Sendable {
    /// Retrieval over the user's own stored turns and explicit notes on this
    /// device. `savedNoteID` is set only when the turn ALSO saved a note.
    case local(entryIDs: [UUID], noteIDs: [UUID], savedNoteID: UUID?)
    /// The host's own memory tools ran for this turn. Fuller shape — minted
    /// only from an observed `tool.started`, never from this plan's writer.
    case host(observedTools: [String])

    /// The chip's text. Verbatim per #422's naming ruling (CLAUDE.md,
    /// Owen 2026-08-27): the outward identity is TALARIA, so on-device memory
    /// never says "Hermes"; `HERMES MEMORY` is host-meaning only.
    var chipLabel: String {
        switch self {
        case .local(_, _, let saved): saved != nil ? "SAVED TO MEMORY" : "ON-DEVICE MEMORY"
        case .host(let tools): "HERMES MEMORY" + (tools.first.map { " · \($0)" } ?? "")
        }
    }
}
