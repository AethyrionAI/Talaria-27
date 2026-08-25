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
    /// #296: why this call did NOT complete. `nil` = it completed, or is still
    /// running (`isActive`). Non-nil = the user's Stop, the system revoking a
    /// turn nothing is coming back for, or a host-reported failure.
    ///
    /// On that last one, corrected 2026-08-10 (296-C1): the runs host reports
    /// failure as a bare `"error": true` with **no words**, so this usually
    /// holds `SessionsHermesClient.unspecifiedHostError` rather than "the
    /// host's own error text" as this line used to promise. A real message is
    /// carried verbatim if one ever arrives.
    ///
    /// Distinct from ``detail`` on purpose: `detail` is the call's INPUT
    /// summary (what it touched), and overwriting it with a reason would trade
    /// the more useful of the two away.
    ///
    /// **OPTIONAL ON PURPOSE — this is load-bearing, not a style choice.**
    /// `ToolActivity` has no hand-written `init(from:)`, and Swift does not
    /// apply property defaults in a synthesized one. A non-optional field here
    /// would make every conversation cached before this change throw
    /// `keyNotFound`; `UserDefaultsAppPersistenceStore.load` catches that and
    /// returns nil, so the whole transcript would vanish — the #42 silent-wipe
    /// shape. Bar 296-E pins it (`legacyToolActivityJSONStillDecodes`), and
    /// that test was watched RED with this declared non-optional before it was
    /// trusted.
    var failure: String?

    /// #371: how this record came to exist. `nil` = witnessed live — the
    /// historical value, and what every pre-change cache decodes to.
    /// `.reconstructed` = rebuilt from the server transcript, which carries
    /// no per-call outcome, so the app never saw these calls finish and the
    /// chip must not claim it did. OPTIONAL ON PURPOSE — the same #42
    /// silent-wipe reasoning `failure` documents above.
    var provenance: Provenance?

    enum Provenance: String, Codable, Sendable {
        case reconstructed
    }

    /// #296: the marker written when the user taps Stop on a turn with a tool
    /// still in flight. A constant rather than a literal at the call site so
    /// the store that writes it and the tests that assert it cannot drift.
    static let stoppedByUser = "Stopped"
    /// #296: the marker for a turn the SYSTEM cut short with no recovery armed
    /// — a revoked background budget on a plane that cannot be resumed. Not
    /// `stoppedByUser`: the user did not ask for this one.
    static let interruptedBySystem = "Interrupted"

    init(
        id: UUID = UUID(),
        label: String,
        startedAt: Date = .now,
        isActive: Bool = true,
        detail: String? = nil,
        anchorOffset: Int = 0,
        failure: String? = nil,
        provenance: Provenance? = nil
    ) {
        self.id = id
        self.label = label
        self.startedAt = startedAt
        self.isActive = isActive
        self.detail = detail
        self.anchorOffset = anchorOffset
        self.failure = failure
        self.provenance = provenance
    }
}
