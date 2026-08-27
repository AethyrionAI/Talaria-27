import Foundation

// MARK: - Approval modes (#224 Phases 0 → 1+2)
//
// Hermes's three-mode approval model — `approvals.mode` with options
// ["manual", "smart", "off"] — mirrored for OUR OWN on-device confirm gate and
// NOTHING else. Not the host's mode (that one is `ServerSettingsScreen`'s
// APPROVALS panel, #224-APP, a deliberately DIFFERENT actor reached through
// the plugin verb), not MCP, not the read tools.
//
// **⛔ SUPERSEDED 2026-08-26 — the paragraph that stood here said `.manual`
// was the only value this build resolves to and that `selectable` was
// `[.manual]`. Phases 1+2 landed on Owen's 2026-08-26 election ("Smart is a
// part of hermes, makes sense that we should have that too"), so all three
// modes are selectable, the Privacy screen renders the control, and
// `.autoApprove` / `.refuse` have real paths.** What did NOT change: `.manual`
// is still the DEFAULT, for a fresh install and for every settings blob that
// predates the key (bar 224-1A).
//
// Owen's ballot of 2026-08-10, rulings this file encodes: (1) held Phases 1–3
// until he asked — DISCHARGED 2026-08-26 by direct election; (2) the gate is
// GLOBAL (`UserSettings`), not per-profile — it governs THIS PHONE's writes,
// which happen identically whichever host a turn came from and happen at all
// with no host configured; (3) Off ships WITH the floor; (4) the floor
// REFUSES rather than carding, because carding would make Off silently
// identical to Smart; (5) Smart is deterministic rules or nothing; (7)
// transcript receipts for auto-approved actions stay DEFERRED — an
// auto-approval logs to `os_log` and renders no row.

/// How the confirm gate treats a staged side-effecting action. One-to-one
/// with Hermes's `approvals.mode` so the mapping stays legible in code and in
/// the tracker.
enum ApprovalMode: String, Codable, CaseIterable, Sendable {
    /// Ask every time — the shipped behaviour since #29, and still the
    /// default for every install.
    case manual
    /// Ask only when the deterministic caution layer flags the action.
    case smart
    /// Never ask — but still refuse a caution-tripping action (the floor,
    /// ruling 4).
    case off

    /// The modes a user can actually choose, in the order the Privacy control
    /// renders them.
    ///
    /// **Spelled out rather than derived from `allCases`, deliberately.**
    /// Phase 0 shipped this as `[.manual]` so that exposing a mode had to be a
    /// deliberate edit to a line that says so, never a side effect of some
    /// other change — and Phases 1+2 are that edit, made on Owen's 2026-08-26
    /// election. Writing `allCases` here would hand the property away: a
    /// future case would ship itself to users the day it was declared. The
    /// list stays literal so widening it stays a decision.
    static let selectable: [ApprovalMode] = [.manual, .smart, .off]

    /// What a fresh install gets, and what a settings blob with no key gets.
    static let defaultMode: ApprovalMode = .manual

    var isSelectable: Bool { Self.selectable.contains(self) }

    /// The clamp `UserSettings` decodes through. A hand-edited blob — or one
    /// written by a future build and restored onto this one — that names an
    /// unselectable mode resolves to the default rather than arming a path
    /// this build has not written. The fail-safe direction is toward the
    /// card, matching the gate's default-closed design.
    ///
    /// With all three modes selectable it is a NO-OP on every value this
    /// build can produce, and that is why it stays: it is the guard for the
    /// next narrowing, not for this widening. Removing it would mean the
    /// first future lane to drop a case inherits a settings file that arms it.
    static func resolved(_ candidate: ApprovalMode?) -> ApprovalMode {
        guard let candidate, candidate.isSelectable else { return defaultMode }
        return candidate
    }

    /// The Privacy row's title. Deliberately un-confusable with the HOST
    /// picker's `Manual / Smart / Off` segments (`ServerSettingsScreen`,
    /// #224-APP): that control names Hermes's own vocabulary because it sets
    /// Hermes's own key, and this one describes what THIS PHONE will do.
    var displayLabel: String {
        switch self {
        case .manual: "Ask every time"
        case .smart: "Ask when unusual"
        case .off: "Never ask"
        }
    }

    /// The one-line consequence under each row.
    ///
    /// **Honesty constraint (bar 224-1D(iv)): no claim the code cannot keep.**
    /// The blast radius is exactly the three agent-staged writes — a reminder,
    /// a calendar event, an alarm — and every word here stays inside it. In
    /// particular nothing promises silence: `.off` says an action that trips a
    /// caution is REFUSED, because the floor is what makes Off shippable at
    /// all (ruling 3).
    ///
    /// **The word "ordinary" was removed on 2026-08-26, and the reason is a
    /// measurement.** A first draft read *"Approves ordinary ones"*; then this
    /// lane's own tests found that an alarm set in the EVENING for the next
    /// morning trips #249's past-due rule (`ALREADY PASSED TODAY — RINGS
    /// TOMORROW`), which is about as ordinary as an alarm gets. Copy that
    /// called that case ordinary would have been a claim the code does not
    /// keep. These lines name the DISCRIMINATOR instead — "trips a caution" —
    /// which is exactly what the gate reads, so the copy cannot drift from the
    /// behaviour without the behaviour changing.
    var rowDetail: String {
        switch self {
        case .manual:
            "Every reminder, event, and alarm waits for your approval."
        case .smart:
            "Goes ahead unless the action trips a caution — an early-morning hour, or a time that has already passed. Those still ask."
        case .off:
            "Goes ahead without asking. An action that trips a caution is refused instead of created."
        }
    }

    /// Which of the design system's two roles the row wears (224-1D(ii)).
    ///
    /// **`danger` is deliberately not expressible here.** Off is a WARNING,
    /// not a danger: the floor means a caution-tripping action is refused
    /// rather than silently created, and the blast radius is three creates in
    /// Apple's own apps, each removable in one tap. Making the type carry only
    /// two roles is stronger than a comment saying "don't use danger" — a
    /// future lane cannot reach for it by accident.
    var accentRole: ApprovalModeAccentRole {
        self == .off ? .warning : .brand
    }

    /// VoiceOver's label, which states the CONSEQUENCE rather than the mode
    /// name alone (bar 224-1D(iii)). "Never ask" read on its own is a name
    /// with no content — a screen-reader user choosing between three names
    /// learns nothing about which one refuses their 4 AM alarm.
    var accessibilityLabel: String {
        switch self {
        case .manual:
            "Ask every time. Every reminder, event, and alarm waits for your approval."
        case .smart:
            "Ask when unusual. Actions go ahead without asking unless they trip a caution, and those still ask you first."
        case .off:
            "Never ask. Actions go ahead without asking, and any that trip a caution are refused instead of created."
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

/// The two colour roles an approval-mode row may wear. **Two, not three** —
/// see `ApprovalMode.accentRole`.
enum ApprovalModeAccentRole: String, CaseIterable, Equatable, Sendable {
    /// The theme's hero hue — `Design.Brand.accentText`.
    case brand
    /// The theme's warning amber — `Design.Brand.forgeText`.
    case warning
}

/// What the gate should do with one staged action.
enum ApprovalDisposition: String, Equatable, Sendable {
    /// Stage the confirmation card and suspend the tool.
    case card
    /// Execute with no card, on the values the tool staged.
    case autoApprove
    /// Create nothing and hand the model an explanatory refusal — Off's
    /// floor, ruling 4.
    case refuse
}

// MARK: - Off's floor (#224 Phase 1, ruling 3 + ruling 4)

/// The text the floor hands back when `.off` refuses a caution-tripping
/// action, composed in ONE place so its three call sites cannot drift apart.
///
/// **Why the floor exists at all.** Hermes's own Off is not the bottom: a
/// hardline blocklist trips before the approval layer, survives `--yolo` and
/// `approvals.mode: off`, never prompts, and returns an explanatory error so
/// nothing runs. Ours mirrors that exactly, and the caution rules are our
/// blocklist. Without it, Off would have shipped #233 — the wee-hour reminder
/// that was caught ON a card.
///
/// **Why it refuses rather than cards (ruling 4).** Carding would make Off
/// silently identical to Smart, and the name would stop being true. Off never
/// prompts; the known-defect shapes still do not happen.
///
/// **Why it carries a do-not-claim clause (#409, 2026-08-25).** This string is
/// a tool RESULT — the model reads it and speaks next. The 336-A forensics
/// measured the model answering a refusal with *"I've set the alarm for 6:30
/// AM"* **6/6** when the refusal named what to do without forbidding the claim.
/// `ToolCallGovernor` carries the same clause for the same reason; this is the
/// second family of refusal string in the app and it inherits the ruling.
///
/// **Why the flagged reason is DIGIT-FREE.** #233-E and #249-F both caught the
/// model mining a formatted timestamp out of a tool string into a fabricated
/// success claim. The two Phase-0 caution rows are digit-free already; the
/// REMINDER's rows are not (they predate the rule and are #233/#249's shipped,
/// device-validated card surface), so the reminder passes a digit-free TWIN of
/// its row rather than the row itself. Pinned by assertion, not by review.
enum ApprovalFloor {

    /// #409's clause, in this family's own words. One constant, so the three
    /// tools' refusals cannot drift; each is nonetheless pinned separately in
    /// test, on the string the gate actually returns.
    static let doNotClaimClause =
        "This action was refused and did not run — do not tell the user it happened."

    /// What the model is told to do next. Mirrors #233-E/#249-F's shape: hand
    /// back a course of action, not just a failure.
    static let followUpClause =
        "Tell the user what was flagged and ask them to confirm what they meant, then try again with what they confirm."

    /// The refusal for a named tool and a named flag.
    ///
    /// `nil` when nothing was flagged — a clean action has no refusal and
    /// never needs one, so a tool cannot accidentally hand the gate a floor
    /// message that does not apply.
    ///
    /// - Parameters:
    ///   - nothingHappened: the tool's own negative lead, e.g. "No reminder
    ///     was created." Leading with the negative is #233-E's rule.
    ///   - flagged: the DIGIT-FREE caution reason, e.g. "EARLY MORNING".
    static func refusal(nothingHappened: String, flagged: String?) -> String? {
        guard let flagged, !flagged.isEmpty else { return nil }
        return "\(nothingHappened) Action confirmations are set to Never ask, and this request was flagged: \(flagged). "
            + doNotClaimClause + " " + followUpClause
    }

    /// The fail-safe for a caution-tripping action whose tool supplied no
    /// floor text.
    ///
    /// **It refuses rather than falling back to the card**, and that direction
    /// is the ruling's, not a convenience: a card here would make Off secretly
    /// Manual for whichever tool forgot, which is the same class of dishonesty
    /// ruling 4 rejected. Refusing never writes anything, so the worst case is
    /// a vaguer message — and the message still carries the clause.
    ///
    /// Reachable today only from a direct `requestConfirmation` call (every
    /// production tool supplies its own), which is exactly how it is tested.
    static let unnamedRefusal =
        "Nothing was created. Action confirmations are set to Never ask, and this request was flagged as unusual. "
        + doNotClaimClause + " " + followUpClause
}
