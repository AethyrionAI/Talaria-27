import Foundation

/// A single tool invocation event captured during streaming.
///
/// Tool activities are accumulated on the ``Message`` during streaming so the UI
/// can show a compact, expandable timeline of what Hermes did. Codable so a
/// finished turn's tool timeline survives the conversation cache across
/// relaunches instead of being discarded with the transient streaming state (#10).
struct ToolActivity: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    /// Tool name as the server reports it (e.g. "write_file").
    let label: String
    let startedAt: Date
    var isActive: Bool
    /// Compact key-input summary from the `tool.started` payload — the
    /// server's `preview` when present, else a condensed `args` line (#11).
    var detail: String?
    /// How many characters of assistant content had streamed when this call
    /// fired. Anchors the chip inline at the point in the transcript where the
    /// model actually invoked it, instead of trailing the whole message (#10).
    var anchorOffset: Int

    init(
        id: UUID = UUID(),
        label: String,
        startedAt: Date = .now,
        isActive: Bool = true,
        detail: String? = nil,
        anchorOffset: Int = 0
    ) {
        self.id = id
        self.label = label
        self.startedAt = startedAt
        self.isActive = isActive
        self.detail = detail
        self.anchorOffset = anchorOffset
    }
}
