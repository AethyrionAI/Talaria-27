import Foundation

/// #362 3D: one agent-written file mirrored over the plugin channel.
///
/// The plugin's `pre_tool_call` hook sees `write_file`'s full args on both
/// transport planes and appends them to the outbox as `kind="artifact"`;
/// this is the typed read of that item off a drain. Only `session_id` and
/// `path` are load-bearing — they are the correlation key (the runs stream
/// records the same path as the `write_file` activity's preview). `turn_id`
/// is host-generated and never appears on the runs stream, so it rides
/// along for bookkeeping only; correlation never keys on it.
struct ArtifactMirrorItem: Equatable, Sendable {
    let platformItemID: String
    let sessionID: String
    let path: String
    let content: String
    let turnID: String?
    let toolCallID: String?
    let hostTimestamp: String?

    /// nil unless the item is `kind == "artifact"` with a non-empty
    /// `session_id` and `path` in meta. Content is the item's `text` —
    /// empty string is a real (empty) file, not a missing one.
    static func parse(_ item: TalariaPlatformItem) -> ArtifactMirrorItem? {
        guard item.kind == "artifact", let meta = item.meta else { return nil }
        guard let sessionID = meta["session_id"], !sessionID.isEmpty,
              let path = meta["path"], !path.isEmpty else { return nil }
        return ArtifactMirrorItem(
            platformItemID: item.id,
            sessionID: sessionID,
            path: path,
            content: item.text,
            turnID: meta["turn_id"].flatMap { $0.isEmpty ? nil : $0 },
            toolCallID: meta["tool_call_id"].flatMap { $0.isEmpty ? nil : $0 },
            hostTimestamp: meta["ts"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }
}
