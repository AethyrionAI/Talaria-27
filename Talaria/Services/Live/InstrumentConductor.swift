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
@MainActor
final class InstrumentConductor {
    private let confirmationCenter: ToolConfirmationCenter
    private let backend: LocalChatBackend?
    private let artifactWriter: InstrumentArtifactWriter
    private let idiom: UIUserInterfaceIdiom
    private let env: [String: String]

    init(confirmationCenter: ToolConfirmationCenter,
         backend: LocalChatBackend?,
         artifactWriter: InstrumentArtifactWriter = InstrumentArtifactWriter(directory: InstrumentArtifactWriter.defaultDirectory),
         idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom,
         env: [String: String] = ProcessInfo.processInfo.environment) {
        self.confirmationCenter = confirmationCenter
        self.backend = backend
        self.artifactWriter = artifactWriter
        self.idiom = idiom
        self.env = env
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

        try? artifactWriter.write(envelope) // status: running — bar 333-C

        // Explicit on EVERY path; mutually exclusive; never inherited.
        confirmationCenter.autoAcceptForBattery = (spec.confirmationMode == .autoAccept)
        confirmationCenter.autoDeclineForBattery = (spec.confirmationMode == .autoDecline)
        BatteryTestContainer.alarmWritesAttended =
            (spec.confirmationMode == .autoAccept && spec.writesAlarms && !unattended)
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            confirmationCenter.autoAcceptForBattery = false
            confirmationCenter.autoDeclineForBattery = false
            BatteryTestContainer.alarmWritesAttended = false
            UIApplication.shared.isIdleTimerDisabled = false
        }

        let priorNewestID = LocalChatBackend.batteryRunStore.loadRuns().first?.id
        await spec.run(backend, trials, cells)
        if let newest = LocalChatBackend.batteryRunStore.loadRuns().first, newest.id != priorNewestID {
            envelope.runRecord = newest
        }
        return finish(.completed)
    }
}
#endif
