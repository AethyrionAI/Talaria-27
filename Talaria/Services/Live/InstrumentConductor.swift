#if DEBUG
import Foundation
import UIKit

/// #333: the ONE code path from "run instrument X" to "artifact on disk" —
/// buttons pass `unattended: false`, the launch-env trigger `unattended: true`.
/// Owns the #196/#200/#331 flag discipline the buttons used to hand-copy:
/// modes are mutually exclusive, set explicitly on every path (never
/// inherited), and cleared on every exit — `defer`, so an early return or a
/// cancelled Task cannot leave a flag armed (bar 333-D). Refusals (bar 333-E):
/// alarm-flagged instruments never run unattended (Owen's 2026-08-11 ruling;
/// `alarmWritesAttended` means "a human tapped" and this class never sets it
/// for an unattended run), and EventKit-flagged instruments never run on an
/// iPad (Shelley's-device rule, enforced by hardware class rather than by
/// trusting the caller). A refusal still writes an artifact naming the reason,
/// so the harness reads REFUSED rather than timing out.
///
/// **`completed` MEANS "a new `BatteryRunRecord` exists and is embedded"**
/// (review fix, post-Task-4): `spec.run` can return having done nothing —
/// `LocalChatBackend.beginBatteryRun()`'s mutex refuses a second concurrent
/// battery, or a legacy caller races one in — and a conductor that reported
/// `.completed` on the strength of "the closure returned" would hand the
/// harness a false positive for the one signal it exists to make trustworthy.
/// So completion is verified, not assumed: the run-store's newest id is
/// sampled before and after `spec.run`, and only a NEW record earns
/// `.completed`; no new record is `.failed` with a reason naming the mutex.
///
/// **#341: the cell request is resolved HERE, before anything runs.** The
/// launch env carries cell NAMES; instruments take cases. Resolving centrally
/// is what lets an unresolvable request seal an honest artifact — a per-entry
/// conversion would either drop a mistyped cell silently or leave the artifact
/// blaming the battery mutex for an operator's typo.
@MainActor
final class InstrumentConductor {
    private let confirmationCenter: ToolConfirmationCenter
    private let backend: LocalChatBackend?
    private let artifactWriter: InstrumentArtifactWriter
    private let idiom: UIUserInterfaceIdiom
    private let env: [String: String]
    /// #333 fix (review finding): the store-read seam. Defaulted to the real
    /// store so production callers say nothing; tests inject a closure that
    /// can simulate "the instrument ran but no record appeared" — the
    /// `beginBatteryRun()` mutex-refusal / recorder-bypass case a plain
    /// completion would otherwise lie about.
    private let loadRuns: @MainActor () -> [BatteryRunRecord]

    init(confirmationCenter: ToolConfirmationCenter,
         backend: LocalChatBackend?,
         artifactWriter: InstrumentArtifactWriter = InstrumentArtifactWriter(directory: InstrumentArtifactWriter.defaultDirectory),
         idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom,
         env: [String: String] = ProcessInfo.processInfo.environment,
         loadRuns: @escaping @MainActor () -> [BatteryRunRecord] = { LocalChatBackend.batteryRunStore.loadRuns() }) {
        self.confirmationCenter = confirmationCenter
        self.backend = backend
        self.artifactWriter = artifactWriter
        self.idiom = idiom
        self.env = env
        self.loadRuns = loadRuns
    }

    @discardableResult
    func run(spec: InstrumentSpec, trials: Int, cells: [String]?,
             unattended: Bool) async -> InstrumentRunStatus {
        var envelope = InstrumentResultEnvelope(
            instrument: spec.name, trialsRequested: trials, cells: cells,
            unattended: unattended, startedAt: Date(), endedAt: nil,
            deviceModel: UIDevice.current.model,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            buildSha: env["TALARIA_BUILD_SHA"],
            status: .running, refusalReason: nil, runRecord: nil)

        func finish(_ status: InstrumentRunStatus, reason: String? = nil) -> InstrumentRunStatus {
            envelope.status = status
            envelope.refusalReason = reason
            envelope.endedAt = Date()
            try? artifactWriter.write(envelope)
            LocalChatBackend.batteryEmit("instrument: \(status.rawValue.uppercased()) \(spec.name) (#333)")
            return status
        }

        if spec.writesAlarms && unattended {
            return finish(.refused, reason: "alarm-writing instruments never run unattended (Owen 2026-08-11; #331)")
        }
        if spec.writesEventKit && idiom == .pad {
            return finish(.refused, reason: "EventKit-writing instruments never run on an iPad (Shelley's-device rule)")
        }

        // #341: resolve the launch env's cell names BEFORE anything runs. A
        // request that cannot be honoured must not become a run that measures
        // the wrong thing, so the whole request is refused here rather than
        // partially applied downstream. `.failed` (not `.refused`) because
        // this is an operator error in the request, not one of the two
        // standing policy refusals above — and because the harness exits
        // non-zero on `failed`, which is what a mistyped cell name deserves.
        let resolvedCells: [LocalChatBackend.ActionBatteryCell]?
        switch ActionBatteryCellSelection.resolve(requested: cells, instrument: spec.name,
                                                  default: spec.defaultCells) {
        case .refused(let reason):
            return finish(.failed, reason: reason)
        case .resolved(let resolved):
            resolvedCells = resolved
        }

        try? artifactWriter.write(envelope) // status: running — bar 333-C

        // Explicit on EVERY path; mutually exclusive; never inherited.
        confirmationCenter.autoAcceptForBattery = (spec.confirmationMode == .autoAccept)
        confirmationCenter.autoDeclineForBattery = (spec.confirmationMode == .autoDecline)
        // #224 Phases 1+2: **an instrument run pins the approval mode to
        // `.manual` for its duration, whatever the user has chosen.**
        //
        // Found by this lane rather than by its bars. The two flags above
        // short-circuit ahead of the mode read, so an `.autoAccept` or
        // `.autoDecline` instrument is untouched by the setting — but a
        // `confirmationMode: .none` instrument (`read-tool`, `router-probe`)
        // arms neither, and those cells are precisely where the #200-series
        // measured the model GRABBING an action tool it was not offered a
        // reason to use. On a phone set to *Never ask*, such a grab would stop
        // staging an unanswerable card and start writing a real reminder to
        // the user's real list, unattended — which is exactly the containment
        // #331 was ruled to protect.
        //
        // It is also a measurement fact: without this, a rate would carry a
        // fourth hidden axis (#215's routing, #343's governor, #398-A's
        // runtime — and now the user's approval mode), and every archive rate
        // was measured before the setting existed.
        let userApprovalMode = confirmationCenter.modeProvider
        confirmationCenter.modeProvider = { .manual }
        BatteryTestContainer.alarmWritesAttended =
            (spec.confirmationMode == .autoAccept && spec.writesAlarms && !unattended)
        // A ~20-minute n=20 must survive auto-lock — work-desk runs have no
        // cable keeping the screen awake, and a locked screen suspends the run
        // mid-battery (rationale from the deleted #196 button; #333 final review).
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            confirmationCenter.autoAcceptForBattery = false
            confirmationCenter.autoDeclineForBattery = false
            confirmationCenter.modeProvider = userApprovalMode
            BatteryTestContainer.alarmWritesAttended = false
            UIApplication.shared.isIdleTimerDisabled = false
        }

        // #373 (#335's noted hazard): a SET DIFFERENCE, not `first`.
        //
        // The store sorts newest-first by `startedAt`, but the persisted form
        // is ISO8601 at SECOND granularity — so two runs inside one second
        // decode to equal keys and the sort gives no order between them. #335
        // declared this unreachable here (separate `run-instrument.sh`
        // launches are never a second apart) and asked for it to be made
        // impossible rather than merely unlikely. It is now impossible: the
        // ids present before the run are remembered, and the record claimed is
        // one that was NOT there — whatever the clock did.
        //
        // The failure it forecloses is not a crash. It is the conductor
        // embedding SOMEBODY ELSE'S run record in this run's artifact and
        // sealing it `.completed` — a wrong measurement wearing a positive
        // marker, which is the one shape this whole file exists to prevent.
        let priorIDs = Set(loadRuns().map(\.id))
        await spec.run(backend, trials, resolvedCells)
        if let fresh = loadRuns().first(where: { !priorIDs.contains($0.id) }) {
            envelope.runRecord = fresh
            return finish(.completed)
        }
        return finish(.failed, reason: "instrument produced no run record — battery mutex refusal or recorder bypass")
    }
}
#endif
