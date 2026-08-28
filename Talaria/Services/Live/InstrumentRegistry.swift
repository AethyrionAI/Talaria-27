#if DEBUG
import Foundation

/// #333: one reachable instrument. `run` binds the EXACT call the
/// Developer-screen button makes — the button and the trigger share this
/// closure, which is the whole of bar 333-B. Capability flags feed the
/// conductor's refusal rules (alarms never unattended — Owen 2026-08-11;
/// EventKit never on an iPad — Shelley's-device rule made structural).
///
/// Backend is optional so conductor tests can exercise flag discipline with
/// no LocalChatBackend; every registry entry guard-lets it first thing.
struct InstrumentSpec {
    enum ConfirmationMode { case autoAccept, autoDecline, none }
    let name: String
    let confirmationMode: ConfirmationMode
    let writesEventKit: Bool
    let writesAlarms: Bool
    /// #341: the `ActionBatteryCell` list this instrument runs when the launch
    /// environment names none — i.e. its pinned default, referenced as the SAME
    /// symbol the backend wrapper defaults to, so the two cannot drift.
    ///
    /// **`nil` means "this instrument has no `ActionBatteryCell` dimension"**,
    /// and the conductor REFUSES a `TALARIA_CELLS` request for it rather than
    /// ignoring one. It is load-bearing, not documentation: the conductor
    /// substitutes it when nothing is requested, so a wrong value here is a
    /// wrong run rather than a stale comment.
    var defaultCells: [LocalChatBackend.ActionBatteryCell]? = nil
    let run: @MainActor (LocalChatBackend?, _ trials: Int,
                         _ cells: [LocalChatBackend.ActionBatteryCell]?) async -> Void
}

/// Every instrument the Developer screen can launch, and the ONLY place a
/// launch is described. Each entry carries the measurement rationale that
/// used to sit above the button's `@ViewBuilder` factory — those comments are
/// the lane history for the run they describe, so the #333 sweep MOVED them
/// here rather than deleting them with the factories.
///
/// **The capability flags describe what the INSTRUMENT writes, not what the
/// button armed.** Every accept-mode button set `alarmWritesAttended = true`
/// identically, so copying the button would have told us nothing; these were
/// derived by reading each backend method through to its prompt set. The
/// #200-family batteries delegate to `runActionBattery` with the DEFAULT
/// prompts, and that set contains `("alarm", "Set an alarm for 6:30")`
/// beside the reminder and calendar creates — so they write EventKit AND
/// AlarmKit, and per Owen's 2026-08-11 ruling none of them may run
/// unattended. The three read-only exceptions in that family
/// (`read-tool`, `motion-scope`, `motion-redirect`) pass their own prompt
/// set and write nothing.
///
/// **#341: `defaultCells` is the second load-bearing column.** An entry that
/// declares one accepts `TALARIA_CELLS` and runs exactly those cells; an entry
/// that leaves it nil REFUSES a cell request rather than ignoring it (`shape`,
/// `two-turn`, the honesty pair and the probes take other cell types or none).
/// The declared list and the wrapper's own default are the SAME symbol, so
/// they cannot drift apart.
enum InstrumentRegistry {
    static let all: [InstrumentSpec] = [
        // #196 second battery: one launcher, two powers — n=10 resolves the
        // reminder-grab question (8/10 -> ~0 is unmissable); n=20 is required
        // for a significant composition verdict (4/10 vs 8/10 at n=10 is
        // p~0.17 — the exact underpowering behind the afternoon's overturned
        // n=4 conviction).
        //
        // Surface: nothing. Auto-decline is checked FIRST in
        // `ToolConfirmationCenter.requestConfirmation`, so no action tool ever
        // executes and the reap is a no-op.
        // The #196 shape battery's own prompt set, run under decline. Headless
        // sessions can never answer a confirmation card, so grabs auto-decline —
        // which also measures post-denial recovery (restored: #333 final review).
        // Button: `instrumentButton("shape", …)`.
        InstrumentSpec(name: "shape", confirmationMode: .autoDecline,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runShapeBattery(trials: trials)
                       }),
        // #200 action battery: the action-SUCCESS path. Auto-ACCEPT armed —
        // every staged confirmation approves, so appropriate creates EXECUTE:
        // real EventKit/AlarmKit writes, every artifact marker-tagged by the
        // gate, all reaped before the DONE line. Run with Reminders/Calendar
        // permissions GRANTED (the observed #200 failure post-dates the grant).
        // Shares the batteryRunning guard with the other instruments.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // ~~`runActionBattery`'s real `cells:` parameter is `[ActionBatteryCell]`,
        // not `[String]` — the button never supplies one, so this entry does not
        // either; inventing a conversion here would be an argument the button
        // does not pass.~~ SUPERSEDED 2026-08-12 (#341): the conversion is no
        // longer "invented" — it is `ActionBatteryCellSelection`, which fails
        // loudly on an unknown name, and the conductor substitutes
        // `defaultCells` when the launch env names none. The button still
        // supplies nothing and still gets exactly this list.
        // Button: `instrumentButton("action", …)`.
        InstrumentSpec(name: "action", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.actionBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runActionBattery(trials: trials, cells: cells)
                       }),
        // #209 read-tool battery: production vs the pinned read-tool rollback on
        // prompts where OMITTING the field is correct. READ tools only — nothing
        // is written, so no auto-accept is needed and the reap is a no-op.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Its own `readToolBatteryPrompts` (weather / health) replace the create
        // prompts, so no confirmation can fire and the reap is a no-op.
        // Button: `instrumentButton("read-tool", …)`.
        InstrumentSpec(name: "read-tool", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       defaultCells: LocalChatBackend.readToolBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runReadToolBattery(trials: trials, cells: cells)
                       }),
        // #196 battery 4: router-accuracy probe — no tools execute (pure
        // classification), so no confirmation auto-decline is needed; the
        // shared batteryRunning guard keeps the two instruments from
        // overlapping on the model.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Button: `instrumentButton("router-probe", …)`.
        InstrumentSpec(name: "router-probe", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runRouterProbe(trials: trials)
                       }),
        // #200B destall battery: the reminder list-stall treatment as measured
        // cells (control / guidefix / toolfix / bothfix) × four prompts — the
        // haiku grab canary included, since the de-stall texts push toward
        // immediate creation. Auto-ACCEPT, real writes, reaped. Promotion only
        // on the classified verdict.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("destall", …)`.
        InstrumentSpec(name: "destall", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.destallBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runDestallBattery(trials: trials, cells: cells)
                       }),
        // #200C instrfix battery: control vs the INSTRUCTIONS-level de-stall
        // clause (#200B falsified the tool-text seam — the stall fires before
        // tool engagement). Auto-ACCEPT, grab canary watching whether "create
        // it right away" pushes haiku grabs above the 8/10 control baseline.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("instrfix", …)`.
        InstrumentSpec(name: "instrfix", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.instrfixBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runInstrfixBattery(trials: trials, cells: cells)
                       }),
        // #200E toolmode battery: promoted-production control vs the structural
        // `.required` treatment (DynamicProfile with the mandatory demote-after-
        // first-call exit — a static .required loops). Auto-ACCEPT; the canary
        // measures which tool a FORCED call grabs on the haiku misroute.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("toolmode", …)`.
        InstrumentSpec(name: "toolmode", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.toolmodeBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runToolmodeBattery(trials: trials, cells: cells)
                       }),
        // #200F community battery: promoted-production control vs the three
        // survey-derived treatments (per-intent scoped belt, create-only belt,
        // find-first carve-out instructions). Auto-ACCEPT; per-trial reap.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("community", …)`.
        InstrumentSpec(name: "community", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.communityBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runCommunityBattery(trials: trials, cells: cells)
                       }),
        // #200G findfix re-verify: promoted control vs explicit-true findfix
        // (identity — both halves measure production and pool).
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("findfix", …)`.
        InstrumentSpec(name: "findfix", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.findfixBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runFindfixBattery(trials: trials, cells: cells)
                       }),
        // #200H spiral battery: promoted control vs the lookup-spiral
        // carve-out (instructions) and the third-strike demote (structural).
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("spiral", …)`.
        InstrumentSpec(name: "spiral", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.spiralBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runSpiralBattery(trials: trials, cells: cells)
                       }),
        // #214 THE structural lane: production vs per-intent belt + composition
        // licensing. Creates real artifacts — auto-ACCEPT, reaped before DONE.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("scoped-v2", …)`.
        InstrumentSpec(name: "scoped-v2", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.scopedV2BatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runScopedV2Battery(trials: trials, cells: cells)
                       }),
        // #215 THE missing denominator: unrouted control vs production's routed
        // configuration. Creates real artifacts — auto-ACCEPT, reaped before DONE.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("routed", …)`.
        InstrumentSpec(name: "routed", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.routedActionBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runRoutedActionBattery(trials: trials, cells: cells)
                       }),
        // #216 the narrow belt re-tried where it cannot lose: both arms routed,
        // only the armed belt differs. Creates real artifacts — auto-ACCEPT, reaped.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("routed-scoped", …)`.
        InstrumentSpec(name: "routed-scoped", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.routedScopedBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runRoutedScopedBattery(trials: trials, cells: cells)
                       }),
        // #200I spiralfix re-measure: promoted control vs the event-scoped
        // reword of the lookup-spiral carve-out. Strikefix is parked (its
        // tally instrument is unproven), so this is 2 cells, not 3.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("spiralfix", …)`.
        InstrumentSpec(name: "spiralfix", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.spiralfixBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runSpiralfixBattery(trials: trials, cells: cells)
                       }),
        // #200J: promoted control vs the card-narration clause — the
        // treatment for #200I's largest failure bucket (zero-tool trials that
        // type the confirmation card out in prose and call nothing).
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("cardfix", …)`.
        InstrumentSpec(name: "cardfix", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.cardfixBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runCardfixBattery(trials: trials, cells: cells)
                       }),
        // #200K: the promoted control + the (now identity) cardfix cell —
        // pooled as the production re-verify — plus the datefix treatment.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("datefix", …)`.
        InstrumentSpec(name: "datefix", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.datefixBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runDatefixBattery(trials: trials, cells: cells)
                       }),
        // #200L: promoted production vs the pinned card-clause rollback vs
        // the #200I spiral carve-out — the calendar lane.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("calendar", …)`.
        InstrumentSpec(name: "calendar", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.calendarBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runCalendarBattery(trials: trials, cells: cells)
                       }),
        // #200M: production vs the v3 dead-end carve-out vs v2, same run.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("deadend", …)`.
        InstrumentSpec(name: "deadend", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.deadendBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runDeadendBattery(trials: trials, cells: cells)
                       }),
        // #200N: the v3 confirmation A/B — production vs the dead-end
        // carve-out only, second independent run before any promotion.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("deadend-verify", …)`.
        InstrumentSpec(name: "deadend-verify", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.deadendVerifyBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runDeadendVerifyBattery(trials: trials, cells: cells)
                       }),
        // #200O: the promoted control + the (now identity) deadendfix cell
        // pooled as the production re-verify, plus the grabfix treatment.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("grabfix", …)`.
        InstrumentSpec(name: "grabfix", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.grabfixBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runGrabfixBattery(trials: trials, cells: cells)
                       }),
        // #200P: production vs the card-correction clause — the conserved
        // zero-tool stall, treated as a class rather than field by field.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("stallfix", …)`.
        InstrumentSpec(name: "stallfix", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.stallfixBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runStallfixBattery(trials: trials, cells: cells)
                       }),
        // #200Q: production vs the reminder tool whose optional fields are
        // optional in the SCHEMA — the stall's structural seam.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("schemafix", …)`.
        InstrumentSpec(name: "schemafix", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.schemafixBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runSchemafixBattery(trials: trials, cells: cells)
                       }),
        // #200S: pooled production re-verify (control + the now-identity
        // schemafix cell) vs the pinned pre-promotion rollback.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("schema-reverify", …)`.
        InstrumentSpec(name: "schema-reverify", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.schemaReverifyBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runSchemaReverifyBattery(trials: trials, cells: cells)
                       }),
        // #200T: production control vs the calendar tool with its two
        // undefaultable fields optional in the schema.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("calfix", …)`.
        InstrumentSpec(name: "calfix", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.calfixBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runCalfixBattery(trials: trials, cells: cells)
                       }),
        // #200U: control vs the contact not-found RESULT carrying continuation,
        // plus the ceiling probe with the tool absent.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("deadend2", …)`.
        InstrumentSpec(name: "deadend2", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.deadend2BatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runDeadend2Battery(trials: trials, cells: cells)
                       }),
        // #200V: #200U's three arms REVERSED (production last) after a discarded
        // warm-up pass — the confirmation run that tests the cell-order confound.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("deadend-confirm", …)`.
        InstrumentSpec(name: "deadend-confirm", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.deadendConfirmBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runDeadendConfirmBattery(trials: trials, cells: cells)
                       }),
        // #200W: #200T's calendar arms re-run WARM with production last. The
        // primaries are the location-spiral and invented-location counts, not the
        // rate — warm production calendar is already ~9/10.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("calfix-warm", …)`.
        InstrumentSpec(name: "calfix-warm", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.calfixWarmBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runCalfixWarmBattery(trials: trials, cells: cells)
                       }),
        // #200W's OWN CONTROL, registered by #373 (2026-08-26). Same calendar
        // arms as `calfix-warm`, same prompt set, `warmup: false` — so the pair
        // isolates the discarded warm-up pass and nothing else. The method has
        // existed in `LocalChatBackend+Battery.swift` since #200W and had no
        // entry here, which meant the cold-first measurement was re-runnable
        // only by editing code: an asserted artifact rather than a reproducible
        // one, and the exact gap #333's registry exists to close.
        //
        // FLAGS ARE DERIVED, NOT COPIED from the sibling above: this delegates
        // to `runActionBattery` with the DEFAULT prompt set — remind / alarm /
        // calendar creates, executed for real under auto-accept — so it writes
        // EventKit AND AlarmKit, and Owen's 2026-08-11 ruling keeps it off an
        // unattended device.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set, auto-accept.
        // Button: `instrumentButton("cold-calfix", …)`.
        InstrumentSpec(name: "cold-calfix", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.calfixWarmBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runColdCalfixBattery(trials: trials, cells: cells)
                       }),
        // #200X: the promoted calendar tool against its OWN pinned rollback,
        // warm, production last — the confidence run the promotion is owed.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("cal-rollback-verify", …)`.
        InstrumentSpec(name: "cal-rollback-verify", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.calRollbackVerifyBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runCalRollbackVerifyBattery(trials: trials, cells: cells)
                       }),
        // #201: #200U's contact fix re-measured at n=20, production last — the
        // primary is a dead-end COUNT, which n=10 could not carry.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // TWO buttons share this entry — n=20 (#201) and the n=40 POWER run
        // (#201B). Trials are the caller's, which is exactly why they can.
        // Button: `instrumentButton("deadend-reconsider", …)`.
        InstrumentSpec(name: "deadend-reconsider", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.deadendReconsiderBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runDeadendReconsiderBattery(trials: trials, cells: cells)
                       }),
        // #201B: the same two arms REVERSED — production first, in the cool slot,
        // so the run doubles as the thermal control.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("deadend-reversed", …)`.
        InstrumentSpec(name: "deadend-reversed", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.deadendReversedBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runDeadendReversedBattery(trials: trials, cells: cells)
                       }),
        // #202B two-turn battery: an offer, then a bare affirmative. Auto-ACCEPT
        // so an appropriate create EXECUTES and is countable as an artifact —
        // real writes, marker-tagged, reaped per trial.
        //
        // Surface: NOT `runActionBattery` — `runTwoTurnBattery` is its own
        // instrument — but the same write surface, and derived rather than
        // assumed from the family: it accumulates `perTrialAlarms` and calls
        // `AlarmService.reapBatteryAlarms()` per trial, so alarms are in
        // scope. The flags follow the writes, not the neighbours.
        // Button: `instrumentButton("two-turn", …)`.
        InstrumentSpec(name: "two-turn", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runTwoTurnBattery(trials: trials)
                       }),
        // #204: full action battery — auto-ACCEPT, real writes, reaped per
        // trial. Run with Reminders/Calendar GRANTED.
        //
        // Surface: `runActionBattery` on the DEFAULT prompt set — remind /
        // alarm / calendar creates, executed for real under auto-accept.
        // Button: `instrumentButton("clause-reverify", …)`.
        InstrumentSpec(name: "clause-reverify", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       defaultCells: LocalChatBackend.clauseReverifyBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runClauseReverifyBattery(trials: trials, cells: cells)
                       }),
        // #340: the due-date A/B — production vs #200K's UNPROMOTED
        // day-default clause, on the one prompt shape that reproduces the
        // measured omission (fifteen production calls on 2026-08-15, exactly
        // one correct due date, and it was the only day-bearing prompt).
        //
        // Surface: NOTHING is written. auto-decline is checked first in
        // `ToolConfirmationCenter.requestConfirmation`, and the prompt set
        // drops the alarm and calendar creates entirely — so no AlarmKit (which
        // would bar it from running unattended) and no calendar events (whose
        // reap the #343 campaign caught under-deleting). The measurement still
        // lands: #249's instrument logs the model's `due` argument at
        // `DeviceActionTools.swift:260`, BEFORE the gate at :309.
        //
        // Read the result from the DEVICE LOG with
        // `scripts/mac/score-due-omission.py`, four buckets. Scoring creates is
        // precisely what shelved this clause in July.
        // Button: `instrumentButton("due-date", …)`.
        InstrumentSpec(name: "due-date", confirmationMode: .autoDecline,
                       writesEventKit: false, writesAlarms: false,
                       defaultCells: LocalChatBackend.dueDateBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runDueDateBattery(trials: trials, cells: cells)
                       }),
        // #199: the DECLINE lane. auto-DECLINE is mutually exclusive with
        // auto-accept — declining is the whole measurement, so no artifact can
        // be created and there is nothing to reap.
        //
        // Surface: nothing. Auto-decline is checked FIRST in
        // `ToolConfirmationCenter.requestConfirmation`, so no action tool ever
        // executes and the reap is a no-op.
        // Button: `instrumentButton("decline", …)`.
        InstrumentSpec(name: "decline", confirmationMode: .autoDecline,
                       writesEventKit: false, writesAlarms: false,
                       defaultCells: LocalChatBackend.declineBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runDeclineBattery(trials: trials, cells: cells)
                       }),
        // #211 motion-scope: control vs the scoped readMotion description.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Its own `motionScopeBatteryPrompts` (two step questions) replace the
        // create prompts — READ tools only.
        // Button: `instrumentButton("motion-scope", …)`.
        InstrumentSpec(name: "motion-scope", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       defaultCells: LocalChatBackend.motionScopeBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runMotionScopeBattery(trials: trials, cells: cells)
                       }),
        // #211 follow-on: promoted vs promoted-plus-boundary. READ tools only.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Same read-only `motionScopeBatteryPrompts`.
        // Button: `instrumentButton("motion-redirect", …)`.
        InstrumentSpec(name: "motion-redirect", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       defaultCells: LocalChatBackend.motionRedirectBatteryCells,
                       run: { backend, trials, cells in
                           guard let backend, let cells else { return }
                           await backend.runMotionRedirectBattery(trials: trials, cells: cells)
                       }),
        // #217 intent-router probe: READ-ONLY, no tools registered, nothing
        // created or reaped. Just classifications.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Button: `instrumentButton("intent-router-probe", …)`.
        InstrumentSpec(name: "intent-router-probe", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runIntentRouterProbe(trials: trials)
                       }),
        // #284 vector router probe: READ-ONLY, no tools registered, nothing
        // created or reaped. Three bands — baseline gate, grid (armed/groups/
        // danger), meta rows (measured, no bar).
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Button: `instrumentButton("vector-router-probe", …)`.
        InstrumentSpec(name: "vector-router-probe", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runVectorRouterProbe(trials: trials)
                       }),
        // #297 toolless-index A/B: READ-ONLY, no tools registered — the toolless
        // branch by definition, so no confirmation gate can fire. 2 arms
        // (control/treatment) x 3 prompts, both built through the one
        // productionToollessInstructions builder (#202D). Bars 297-A/B/C are
        // pre-registered in OPEN_ITEMS #297.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Button: `instrumentButton("toolless-index", …)`.
        InstrumentSpec(name: "toolless-index", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runToollessIndexBattery(trials: trials)
                       }),
        // #257 capability-detection probe: READ-ONLY, classifications only — no
        // tools registered, nothing created or reaped. Arm (2-field production
        // route) vs control (pinned 1-field) in the SAME run; bands GATE x2
        // (10 rows x n each), RECALL (10 x n/2), DANGER (20 x n/2), HONESTY
        // (the deterministic appended payload through the shipped 297-C halves,
        // counted separately). Bars 257-1-GATE/A/B/D pre-registered in
        // OPEN_ITEMS #257; run the device tokenCount pre-flight first.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Button: `instrumentButton("capability-detection-probe", …)`.
        InstrumentSpec(name: "capability-detection-probe", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runCapabilityDetectionProbe(trials: trials)
                       }),
        // #335 A — #257's MANDATORY PRE-FLIGHT (the `21F0C10D` gate), which
        // has been owed since the capability lane was routed. READ-ONLY in
        // the strongest sense available: tokenizer round trips ONLY, no
        // generation at all, no tools registered, nothing created or reaped.
        // What it prices is the payload `capability-detection-probe` submits
        // — production's router instructions, the prompt envelope for the
        // longest pinned baseline row, and BOTH generation schemas — plus the
        // worst-case response JSON against the cap each schema really
        // generates under, read from `twoFieldRouterOptions` /
        // `toolIntentRouterOptions` rather than retyped. The hazard: the
        // router's catch arm fails safe to ARMED, so a response that outgrows
        // its cap routes every capability question armed and reads as
        // "detection doesn't work" while the instrument is dead — that is
        // `21F0C10D` exactly, 165/165 instrument errors scored as behaviour.
        // `trials` is a REPEAT count; token counts should be deterministic
        // and the repeats are what turn "should" into a measured `distinct`.
        //
        // Surface: read-only — tokenizer round trips; nothing is generated
        // and nothing is written.
        // Button: `instrumentButton("tokencount-preflight", …)`.
        InstrumentSpec(name: "tokencount-preflight", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runTokenCountPreflight(trials: trials)
                       }),
        // #335 B — #324-W3's three device-only FM questions, one labeled band
        // each. READ-ONLY: two bands are tokenizer round trips and the third
        // is a SINGLE plain generation with no tools registered and no
        // confirmation reachable, so nothing can be created or reaped. The
        // beta5 SDK audit could not settle any of these off-device in its own
        // words — on a sim `tokenCount` throws 1026 and `contextSize` reads 0.
        // Bands: the 4096-vs-8192 counting boundary (both counts and both
        // ratios, because clamping shows up as tokenRatio < charRatio); the
        // new `SystemLanguageModel.variant.displayName`; and whether a binding
        // `maximumResponseTokens` THROWS or TRUNCATES on plain generation
        // (guided generation is known to throw — plain is unmeasured).
        //
        // ⚠️ The variant band references a NEW-IN-BETA5 symbol, and #324
        // proved a beta5-built binary referencing one dies at DYLD LAUNCH on a
        // beta4 27.0 runtime — the whole app, not the instrument. Every target
        // device must be on beta5 before this entry is run.
        //
        // Surface: read-only — tokenizer round trips plus one beltless
        // generation; nothing is written.
        // Button: `instrumentButton("fm-asymmetries", …)`.
        InstrumentSpec(name: "fm-asymmetries", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runFMAsymmetriesProbe(trials: trials)
                       }),
        // #335 C — #210's own "Still owed", made runnable: *"whether one
        // forced condensation actually gets a real long-conversation turn
        // under 8,192 is a separate question and needs a measured run, not an
        // assumption."* READ-ONLY: no generation at all, no tools, nothing
        // created; the transcript is SYNTHETIC and the user's real ChatStore
        // is never read (that would measure whatever was in the app that day
        // and could not be re-run). It calls PRODUCTION's condenser —
        // `sessionBlueprint(…forceCondense: true)`, the same function
        // `rebuildSession` calls on the #26/#229 retry — rather than modelling
        // one, because a measurement of a lookalike measures nothing. A trial
        // scores only if it is ARMED: pre-condensation count above the 8,192
        // ceiling, MEASURED, per #215's rule that an unarmed cell measures a
        // configuration the app never enters.
        //
        // Surface: read-only — tokenizer round trips and one condenser call;
        // nothing generated, nothing written.
        // Button: `instrumentButton("condensation-fit", …)`.
        InstrumentSpec(name: "condensation-fit", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runCondensationFitProbe(trials: trials)
                       }),
        // #101 bar 101-A1 — Shape A's falsifier. READ-ONLY, classifications
        // only: ten pinned cross-chat-recall rows x n through PRODUCTION's own
        // `routeTurn`, armed-vs-toolless tallied per row. No belt, no tools
        // registered, nothing created or reaped. If these route toolless the
        // already-armed ConversationSearchTool never fires and Shape A is dead
        // before any corpus work — which is why this runs first.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Button: `instrumentButton("cross-chat-recall-probe", …)`.
        InstrumentSpec(name: "cross-chat-recall-probe", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runCrossChatRecallProbe(trials: trials)
                       }),
        // #202A: same shape as the #196 router probe — pure classification, so
        // no confirmation auto-decline and nothing to sweep afterwards. The
        // idle-timer lock matters here too: ~585 generations is ~10 minutes.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Button: `instrumentButton("router-context-probe", …)`.
        InstrumentSpec(name: "router-context-probe", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runRouterContextProbe(trials: trials)
                       }),
        // #207: same shape as the other probes — classification only.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Button: `instrumentButton("image-routing-probe", …)`.
        InstrumentSpec(name: "image-routing-probe", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runImageRoutingProbe(trials: trials)
                       }),
        // #202C companion: ctx-a on realistic LONG contexts, timed. The only
        // button in the sweep whose factory carried NO rationale comment —
        // this line is the call site's, moved here so the entry is not the
        // one blank in the table.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Button: `instrumentButton("long-context-probe", …)`.
        InstrumentSpec(name: "long-context-probe", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runLongContextProbe(trials: trials)
                       }),
        // #202C: the honesty lane. Every trial runs with an EMPTY belt, so no
        // confirmation can fire and nothing can be written — no grants needed
        // and nothing to reap, same as the probes.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // Empty belt in every trial, so nothing can be confirmed or created.
        // `ticTrials` stays at its default 4 — the button never passed one.
        // Button: `instrumentButton("honesty", …)`.
        InstrumentSpec(name: "honesty", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runHonestyBattery(trials: trials)
                       }),
        // #202D: same empty-belt shape as #202C — nothing to grant, nothing to reap.
        //
        // Surface: read-only — classifications or READ tools; nothing is written.
        // The SAME backend method as `honesty` with the v2 cell list BOUND —
        // the one converted button that passed more than `trials`.
        // Button: `instrumentButton("honesty-v2", …)`.
        InstrumentSpec(name: "honesty-v2", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runHonestyBattery(
                                trials: trials, cells: LocalChatBackend.honestyV2BatteryCells)
                       }),
        // #337 bar 337-D — the refusal-words instrument. #232 filed the grind
        // and #337 measured its rate (69/90, 74/90) without either ever
        // recording what a refusal SAYS. Captures each refusal verbatim with
        // the governor counters that produced it, whether the cut fired, and
        // — bar 337-B / #225 B2's named instrument gap — the POST-CUT toolless
        // retry's text, so a cut trial stops reading as an empty row.
        //
        // Two cells, differing in ONE line: `turn-reset` calls
        // `relay.beginTurn()` before every trial, which is what production's
        // two send loops do; `leaked` calls it once per cell, which is what
        // `runActionBattery`'s trial loop does today (it never calls it at
        // all). Read #337's cut rates against that contrast.
        //
        // Surface: auto-DECLINE, so nothing is written — a declined call is
        // still an EXECUTED call as far as the governor is concerned, which is
        // the whole mechanism this measures, so the grind is fully reachable
        // without arming a single write. That is what makes it
        // unattended-eligible; the cost is that trials where the model DOES
        // call a tool then reason about a decline, and the row records
        // `toolCallsAdmitted` so those can be partitioned out.
        // Button: `instrumentButton("refusal-words", …)`.
        InstrumentSpec(name: "refusal-words", confirmationMode: .autoDecline,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runRefusalWordsInstrument(trials: trials)
                       }),
        // #337 bar 337-F — the confirmation-card A/B. #337-A's production turn
        // printed "**Confirmation card:** … has been created" with no card and
        // no call; the candidate mechanism, filed with a text pointer and NOT
        // elected, is that the action tools' own descriptions teach the
        // phrase. Three arms: production verbatim, the clause removed from the
        // three tool DESCRIPTIONS, and that plus the armed blurb's own
        // confirmation-card sentence — the third exists because a null in the
        // tools-only arm would be uninterpretable while the blurb kept
        // teaching it.
        //
        // **Production's descriptions do not change.** The stripped strings
        // are `#if DEBUG` constants derived by removal from production's own
        // statics, and the manipulation-check row records how many
        // descriptions were actually swapped — a treatment that silently
        // failed to apply must not read as a null.
        //
        // Surface: auto-DECLINE, so nothing is written. The phenomenon lives
        // on ZERO-TOOL turns, where the confirmation mode is unreachable, so
        // the mode does not touch the arm that matters.
        // Button: `instrumentButton("card-clause", …)`.
        //
        // #372, 2026-08-26 — TWO successors landed on this same instrument and
        // the entry above does not describe either. (a) every trial now
        // records whether the gate actually DECLINED, and scores the reply with
        // #392's `DeclineAttributionScorer` only when it did — the decline half
        // of the shipping blurb had never been exercised by a measurement
        // because nothing could see a decline. (b) a seventh arm,
        // `toolmode-required`, is 337-H's remedy: belt and instructions
        // production verbatim, `.required` with the mandatory demote exit as
        // the sole delta. **Production sets no tool-calling mode and this
        // changes none** — the remedy ships as an arm and the device A/B
        // decides.
        InstrumentSpec(name: "card-clause", confirmationMode: .autoDecline,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runCardClauseAB(trials: trials)
                       }),
        // #372(b) / 337-H — the REMEDY A/B on its own, and it exists because
        // the full instrument now costs 210 trials.
        //
        // Two arms, `control` first and the remedy SECOND: this is the run
        // whose primary is that single contrast, and the five prose arms of
        // the full sweep buy it nothing while inserting ~90 trials of thermal
        // drift between the two arms being compared. The remedy sits LAST in
        // the seven-arm run (the worst slot, conservative for a positive) and
        // SECOND here (adjacent to its control, which is what a two-arm A/B
        // wants) — the same reasoning #211A's arm order records, and the two
        // placements answer different questions rather than contradicting.
        //
        // Same flags as `card-clause`, DERIVED not copied: auto-DECLINE,
        // nothing written, the phenomenon lives on zero-tool turns where the
        // confirmation mode is unreachable anyway.
        //
        // Surface: auto-DECLINE, so nothing is written.
        // Button: `instrumentButton("card-clause-remedy", …)`.
        InstrumentSpec(name: "card-clause-remedy", confirmationMode: .autoDecline,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runCardClauseAB(
                                trials: trials, arms: [.control, .toolmodeRequired])
                       }),
        // #211A offer-instead-of-act on READ paths: three arms × four read
        // prompts × n. Production (routed) vs #211's pinned `readMotion`
        // rollback vs a read-tool-free CEILING.
        //
        // The ceiling arm is a POSITIVE CONTROL, not a candidate: a detector
        // that never fires cannot be told from a clean run, so one arm must
        // make it fire. If `no-read-belt` does not offer, the run is
        // uninterpretable and no other arm may be read.
        //
        // FLAGS DERIVED, NOT COPIED: the prompt set is four READ questions
        // (#211's two step/motion rows, #209's two bare-field rows), answered
        // by `readHealth` / `readMotion` / `currentWeather`. Nothing is
        // written. The production belt still carries the action tools —
        // removing them would be a second manipulation — so the mode is
        // auto-DECLINE and a grab still creates nothing, which is what keeps
        // this unattended-eligible under Owen's 2026-08-11 ruling.
        //
        // Surface: read-only — READ tools; nothing is written and the reap is
        // a no-op.
        // Button: `instrumentButton("offer-read", …)`.
        InstrumentSpec(name: "offer-read", confirmationMode: .autoDecline,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runOfferReadBattery(trials: trials)
                       }),
        // #211A-E1..E3 (2026-08-27) — the TOOLLESS probe, registered as its own
        // instrument rather than as a cell of `offer-read`.
        //
        // Two reasons, both learned the same evening. (1) `offer-read`'s run
        // closure DISCARDS its cells argument, so `--cells toolless` would have
        // been silently ignored and the operator would have got a default
        // three-arm run reported under the probe's name — the #341 shape
        // exactly, a selection that falls back while appearing to select.
        // (2) A separate name keeps the default run's meaning frozen: every
        // prior `offer-read` artifact stays comparable.
        //
        // It answers whether D1's >=50% is reachable by ANY arm. Its rate is a
        // measurement, not a bar — see the entry.
        InstrumentSpec(name: "offer-read-toolless", confirmationMode: .autoDecline,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runOfferReadBattery(trials: trials, arms: [.toolless])
                       }),
        // #417 (2026-08-27, Owen's ruling) — the TOOL-FAILURE instrument.
        //
        // #211A-E measured fabrication with an EMPTY belt. A user never hits an
        // empty belt; they hit tools that are PRESENT and FAIL — HealthKit
        // empty, Location denied, network down. The failure arms replay
        // production's own honest "no data" / "permission not granted" strings
        // verbatim rather than inventing a failure shape, because an invented
        // one measures something production never emits.
        //
        // Reuses offer-read's four prompts and trial mechanics so the result is
        // directly comparable to the toolless run's 20 fabricate / 20 honest.
        InstrumentSpec(name: "tool-failure", confirmationMode: .autoDecline,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runToolFailureBattery(trials: trials)
                       }),
        // #388 beta5 surface sweep: bars 388-A (capabilities, BOTH tiers),
        // 388-B (quota, plus the log needle it must be correlated against)
        // and 388-D's device-answerable half (does each of three
        // never-examined frameworks LOAD here). READ-ONLY in the strongest
        // sense in this file: no generation at all, no tokenizer round trip,
        // no tools registered, nothing created and nothing to reap — it reads
        // properties and calls `dlopen`.
        //
        // `trials` is a REPEAT count and only the quota band uses it:
        // capabilities and framework loads are static reads, so repeating
        // them would pad the artifact without adding a fact.
        //
        // ⚠️ **On the simulator this instrument DELIBERATELY MEASURES
        // NOTHING for PCC** — `pccGrantConfirmed` is false there, so both PCC
        // rows record `errors` and omit their per-capability metrics rather
        // than reporting zeros (bar 388-C). A green sim run is evidence the
        // instrument seals its run, never evidence about the tier.
        //
        // Surface: read-only — property reads and `dlopen`; nothing is
        // generated and nothing is written.
        // Button: `instrumentButton("pcc-surface", …)`.
        InstrumentSpec(name: "pcc-surface", confirmationMode: .none,
                       writesEventKit: false, writesAlarms: false,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runPCCSurfaceProbe(trials: trials)
                       }),
    ]

    static func spec(named name: String) -> InstrumentSpec? {
        all.first { $0.name == name }
    }
}
#endif
