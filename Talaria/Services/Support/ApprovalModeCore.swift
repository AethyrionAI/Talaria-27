import Foundation

// MARK: - Approval modes (#224 Phase 0)
//
// The scaffold for Hermes's three-mode approval model — `approvals.mode`
// with options ["manual", "smart", "off"] — mirrored for OUR OWN on-device
// confirm gate and NOTHING else. Not the host's mode (that key lives on the
// dashboard app, :9119; there is no `/api/config` on the :8642 chat plane the
// phone speaks, re-verified 2026-08-09), not MCP, not the read tools.
//
// Phase 0 ships the TYPE and nothing a user can reach. `.manual` is the only
// value this build resolves to: `selectable` is `[.manual]`, and
// `UserSettings` clamps everything it decodes through `resolved(_:)`. The
// other two cases exist so that every switch over an approval mode is
// exhaustive from day one — naming the door before anyone walks through it,
// so Phase 1 is a behaviour change and not a type change.
//
// Owen's ballot of 2026-08-10, rulings that this file encodes: (1) Phase 0
// only, no user-facing control; (2) the gate is GLOBAL (`UserSettings`), not
// per-profile — it governs THIS PHONE's writes, which happen identically
// whichever host a turn came from and happen at all with no host configured;
// (4) "Off" refuses a caution-tripping action rather than carding it, because
// carding would make Off silently identical to Smart; (5) Smart is
// deterministic rules or nothing.

/// How the confirm gate treats a staged side-effecting action. One-to-one
/// with Hermes's `approvals.mode` so the mapping stays legible in code and in
/// the tracker.
enum ApprovalMode: String, Codable, CaseIterable, Sendable {
    /// Ask every time — today's shipped behaviour, and the only value this
    /// build can reach.
    case manual
    /// Ask only when the deterministic caution layer flags the action.
    /// NOT REACHABLE in this build (Phase 2).
    case smart
    /// Never ask — but still refuse a caution-tripping action (the floor,
    /// ruling 4). NOT REACHABLE in this build (Phase 1).
    case off

    /// Ruling 1: Phase 0 ships no user-facing control, so exactly one mode is
    /// selectable. A later lane that adds the Privacy row widens this list —
    /// and the test named `approvalModeExposesOnlyManual` goes RED the moment
    /// it does. That is the point: exposing a mode has to be a deliberate
    /// edit to a line that says so, never a side effect of some other change.
    static let selectable: [ApprovalMode] = [.manual]

    /// What a fresh install gets, and what a settings blob with no key gets.
    static let defaultMode: ApprovalMode = .manual

    var isSelectable: Bool { Self.selectable.contains(self) }

    /// The clamp `UserSettings` decodes through. A hand-edited blob — or one
    /// written by a future build and restored onto this one — that names an
    /// unselectable mode resolves to the default rather than arming a path
    /// this build has not written. The fail-safe direction is toward the
    /// card, matching the gate's default-closed design.
    static func resolved(_ candidate: ApprovalMode?) -> ApprovalMode {
        guard let candidate, candidate.isSelectable else { return defaultMode }
        return candidate
    }

    /// Settings copy for the row Phase 1 would add. Present now so the
    /// vocabulary is fixed before anything renders it; nothing reads it yet.
    var displayLabel: String {
        switch self {
        case .manual: "Ask every time"
        case .smart: "Ask when unusual"
        case .off: "Never ask"
        }
    }

    /// The whole policy, as a pure function of the mode and whether the
    /// deterministic caution layer flagged the staged action.
    ///
    /// **Ruling 5 — the on-device model never goes on the safety path.** This
    /// function is SYNCHRONOUS and non-throwing, and that is not a style
    /// choice: a `LanguageModelSession` turn is necessarily `await`ed, so
    /// putting the model here would make this `async` and break every call
    /// site — including the deliberately non-`async` test body that pins it
    /// (`approvalPathDecisionsAreSynchronousAndModelFree`). The #200-series
    /// is a long record of this model mis-assessing which action a turn
    /// needs, and #297 measured a 7/20 miss; the safety path is the worst
    /// place to spend that reliability.
    func disposition(hasCaution: Bool) -> ApprovalDisposition {
        switch self {
        case .manual: .card
        case .smart: hasCaution ? .card : .autoApprove
        case .off: hasCaution ? .refuse : .autoApprove
        }
    }
}

/// What the gate should do with one staged action. Only `.card` has an
/// implementation in this build.
enum ApprovalDisposition: String, Equatable, Sendable {
    /// Stage the confirmation card and suspend the tool — the only path that
    /// ships today.
    case card
    /// Execute with no card (Phases 1–2; not built).
    case autoApprove
    /// Create nothing and hand the model an explanatory refusal — Off's
    /// floor, ruling 4 (Phase 1; not built).
    case refuse
}
