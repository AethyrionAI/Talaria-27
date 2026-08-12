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
    let run: @MainActor (LocalChatBackend?, _ trials: Int, _ cells: [String]?) async -> Void
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
        // The #196 shape battery's own prompt set, run under decline.
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
        // `runActionBattery`'s real `cells:` parameter is `[ActionBatteryCell]`,
        // not `[String]` — the button never supplies one, so this entry does not
        // either; inventing a conversion here would be an argument the button
        // does not pass.
        // Button: `instrumentButton("action", …)`.
        InstrumentSpec(name: "action", confirmationMode: .autoAccept,
                       writesEventKit: true, writesAlarms: true,
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runActionBattery(trials: trials)
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
                       run: { backend, trials, _ in
                           guard let backend else { return }
                           await backend.runReadToolBattery(trials: trials)
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
    ]

    static func spec(named name: String) -> InstrumentSpec? {
        all.first { $0.name == name }
    }
}
#endif
