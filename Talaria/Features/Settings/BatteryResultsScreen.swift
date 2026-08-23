#if DEBUG
import SwiftUI
import UIKit

// MARK: - Battery results (#196 results-page lane, DEBUG builds only)
//
// Diagnostics → Local brain → Battery results. The Console-less results
// surface: every battery/probe run persisted by BatteryRunStore, a per-run
// heuristic tally table, drill-down to FULL raw replies, and — the actual
// point — export: "Copy raw run" puts the whole run on the clipboard in the
// established `battery:` line grammar so a paste into chat is immediately
// classifiable, and the share sheet carries the run JSON.
//
// Real-data rules: flag tallies are labeled heuristic (raw text is ground
// truth — this page never presents them as verdicts), and an empty store
// shows an empty state, never sample rows.

struct BatteryResultsScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var runs: [BatteryRunRecord] = []

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Battery results", subtitle: "#196 Instrument") { dismiss() }

                    if runs.isEmpty {
                        MonoLabel("No captured runs. Run a battery or router probe from Developer → Batteries — every run records here.",
                                  size: 10, tracking: Design.Tracking.mono,
                                  color: Design.Colors.secondaryForeground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Design.Spacing.md)
                            .hudPanel(
                                cornerRadius: Design.CornerRadius.lg,
                                borderColor: Design.Colors.accentTint(0.12),
                                fill: Design.Colors.background.opacity(0.5),
                                innerGlow: false
                            )
                    } else {
                        VStack(spacing: Design.Spacing.sm) {
                            ForEach(runs) { run in
                                NavigationLink {
                                    BatteryRunDetailScreen(run: run)
                                } label: {
                                    runRow(run)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        LocalChatBackend.batteryRunStore.delete(run)
                                        runs = LocalChatBackend.batteryRunStore.loadRuns()
                                    } label: {
                                        Label("Delete run", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    // #200 crash diagnostics: the append-only emit sink
                    // survives a crashed run (per-line writes), and off-LAN
                    // this button is the ONLY way to get it out. Every line
                    // of every run on this install, newest at the bottom.
                    if let captureLog = LocalChatBackend.batteryCaptureLogURL,
                       FileManager.default.fileExists(atPath: captureLog.path) {
                        ShareLink(item: captureLog) {
                            HStack(spacing: Design.Spacing.xs) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 12, weight: .medium))
                                MonoLabel("Share capture log (survives crashes)", size: 10,
                                          tracking: Design.Tracking.mono,
                                          color: Design.Colors.foregroundBright)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .hudPanel(
                                cornerRadius: Design.CornerRadius.md,
                                borderColor: Design.Colors.accentTint(0.2),
                                fill: Design.Colors.background.opacity(0.5),
                                innerGlow: false
                            )
                        }
                        .foregroundStyle(Design.Colors.foregroundBright)
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Battery results")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onAppear { runs = LocalChatBackend.batteryRunStore.loadRuns() }
    }

    private func runRow(_ run: BatteryRunRecord) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack {
                MonoLabel(run.startedAt.formatted(date: .abbreviated, time: .shortened),
                          size: 11, weight: .medium, tracking: Design.Tracking.mono,
                          color: Design.Colors.foregroundBright)
                Spacer()
                MonoLabel("v\(run.appVersion) (\(run.appBuild))",
                          size: 9, tracking: Design.Tracking.mono,
                          color: Design.Colors.mutedForeground)
            }
            MonoLabel(runSummary(run), size: 9, tracking: Design.Tracking.mono,
                      color: Design.Colors.secondaryForeground)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.md,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    private func runSummary(_ run: BatteryRunRecord) -> String {
        if run.trials.isEmpty && !run.probes.isEmpty {
            return "router probe · n=\(run.trialsPerCell) × \(run.probes.count) probes"
        }
        let failures = run.trials.filter { $0.error != nil || $0.timedOut }.count
        let failureNote = failures == 0 ? "" : " · \(failures) err/timeout"
        // #200 action runs name themselves; legacy shape runs stay "battery".
        let noun = run.kind == "action" ? "action battery" : "battery"
        // A false flag is a run that died mid-battery — the snapshot is
        // everything it measured before the crash (#200 diagnostics).
        let incompleteNote = run.endedCleanly == false ? " · INCOMPLETE (crashed)" : ""
        return "\(noun) n=\(run.trialsPerCell) · \(run.trials.count) trials\(failureNote)\(incompleteNote) · \(run.cells.joined(separator: ", "))"
    }
}

// MARK: - Run detail

struct BatteryRunDetailScreen: View {
    @Environment(\.dismiss) private var dismiss

    let run: BatteryRunRecord

    @State private var rawCopied = false

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(
                        title: "Run detail",
                        subtitle: run.startedAt.formatted(date: .abbreviated, time: .shortened)
                    ) { dismiss() }

                    headerPanel
                    exportPanel

                    if !run.trials.isEmpty {
                        tallySection
                    }
                    if routeRows.count > 0 {
                        routeSection
                    }
                    if !run.probes.isEmpty {
                        probeSection
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Run detail")
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            detailLine("Build", "v\(run.appVersion) (\(run.appBuild))")
            detailLine("OS", run.osVersion)
            detailLine("n per cell", "\(run.trialsPerCell)")
            if !run.cells.isEmpty {
                detailLine("Cells", run.cells.joined(separator: ", "))
            }
            // #200 action runs: name the kind, and show the teardown's
            // artifact-reap accounting — the run's claim that the phone
            // ended clean, in the same words the export carries.
            if run.kind == "action" {
                detailLine("Kind", "action battery (#200) — auto-accept, real writes")
            }
            if let reapSummary = run.reapSummary {
                detailLine("Reap", reapSummary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.sm) {
            MonoLabel(label, size: 9, weight: .medium, tracking: Design.Tracking.monoWide,
                      color: Design.Colors.mutedForeground)
                .frame(width: 72, alignment: .leading)
            MonoLabel(value, size: 9, tracking: Design.Tracking.mono,
                      color: Design.Colors.foreground)
        }
    }

    // MARK: Export — the actual point of the page

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            GhostButton(
                title: rawCopied ? "Copied — paste into chat" : "Copy raw run",
                systemImage: rawCopied ? "checkmark" : "doc.on.doc",
                height: 40
            ) {
                UIPasteboard.general.string = BatteryRunMath.renderRawLines(for: run)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation { rawCopied = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { rawCopied = false }
                }
            }

            ShareLink(item: LocalChatBackend.batteryRunStore.fileURL(for: run)) {
                HStack(spacing: Design.Spacing.xs) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                    MonoLabel("Share run JSON", size: 10, tracking: Design.Tracking.mono,
                              color: Design.Colors.foregroundBright)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .hudPanel(
                    cornerRadius: Design.CornerRadius.md,
                    borderColor: Design.Colors.accentTint(0.2),
                    fill: Design.Colors.background.opacity(0.5),
                    innerGlow: false
                )
            }
            .foregroundStyle(Design.Colors.foregroundBright)
        }
    }

    // MARK: Heuristic tallies

    private var tallySection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Heuristic flags — raw text is ground truth", size: 10,
                      tracking: Design.Tracking.monoXWide, color: Design.Colors.mutedForeground)
            MonoLabel("cant/denial are the emit line's hints, not verdicts. Tap a row for the full raw replies.",
                      size: 9, tracking: Design.Tracking.mono, color: Design.Colors.secondaryForeground)

            VStack(spacing: 0) {
                let tallies = BatteryRunMath.tallies(for: run.trials)
                ForEach(Array(tallies.enumerated()), id: \.element) { index, tally in
                    NavigationLink {
                        BatteryTrialListScreen(run: run, shape: tally.shape, prompt: tally.prompt)
                    } label: {
                        tallyRow(tally)
                    }
                    .buttonStyle(.plain)
                    if index < tallies.count - 1 {
                        Rectangle()
                            .fill(Design.Colors.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, Design.Spacing.md)
                    }
                }
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private func tallyRow(_ tally: BatteryCellPromptTally) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                MonoLabel("\(tally.shape) · \(tally.prompt)", size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Design.Colors.mutedForeground)
            }
            MonoLabel(tallyLine(tally), size: 9, tracking: Design.Tracking.mono,
                      color: Design.Colors.secondaryForeground)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .contentShape(Rectangle())
    }

    private func tallyLine(_ tally: BatteryCellPromptTally) -> String {
        var parts = ["n=\(tally.total)", "cant=\(tally.cantCount)", "denial=\(tally.denialCount)",
                     "tool-trials=\(tally.toolTrialCount)"]
        if tally.errorCount > 0 { parts.append("err=\(tally.errorCount)") }
        if tally.timeoutCount > 0 { parts.append("timeout=\(tally.timeoutCount)") }
        return parts.joined(separator: "  ")
    }

    // MARK: Router decision distribution

    private var routeRows: [(prompt: String, armed: Int, toolless: Int)] {
        BatteryRunMath.routeDistribution(for: run.trials)
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Router decisions (armed-routed trials)", size: 10,
                      tracking: Design.Tracking.monoXWide, color: Design.Colors.mutedForeground)

            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                ForEach(routeRows, id: \.prompt) { row in
                    MonoLabel("\(row.prompt): armed=\(row.armed)  toolless=\(row.toolless)",
                              size: 10, tracking: Design.Tracking.mono,
                              color: Design.Colors.foreground)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Spacing.md)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    // MARK: Router probe results

    private var probeSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Router probe", size: 10,
                      tracking: Design.Tracking.monoXWide, color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                ForEach(Array(run.probes.enumerated()), id: \.offset) { index, probe in
                    probeRow(probe)
                    if index < run.probes.count - 1 {
                        Rectangle()
                            .fill(Design.Colors.hairline)
                            .frame(height: 1)
                            .padding(.horizontal, Design.Spacing.md)
                    }
                }
            }
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private func probeRow(_ probe: RouterProbeRecord) -> some View {
        let clean = probe.correct == probe.trials
        return HStack(spacing: Design.Spacing.sm) {
            StatusPip(color: clean ? Design.Brand.accent : Design.Colors.danger,
                      diameter: 8, blinks: false)
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel(probe.probe, size: 10, tracking: Design.Tracking.mono,
                          color: Design.Colors.foreground)
                    .lineLimit(2)
                MonoLabel("expects \(probe.expected ? "device" : "words-only")",
                          size: 8, tracking: Design.Tracking.mono,
                          color: Design.Colors.mutedForeground)
            }
            Spacer()
            MonoLabel("\(probe.correct)/\(probe.trials)", size: 11, weight: .medium,
                      tracking: Design.Tracking.mono,
                      color: clean ? Design.Brand.accentText : Design.Colors.danger)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
    }
}

// MARK: - Trial drill-down: the raw replies

struct BatteryTrialListScreen: View {
    @Environment(\.dismiss) private var dismiss

    let run: BatteryRunRecord
    let shape: String
    let prompt: String

    private var trials: [BatteryTrialRecord] {
        run.trials.filter { $0.shape == shape && $0.prompt == prompt }
    }

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: prompt, subtitle: shape) { dismiss() }

                    VStack(spacing: Design.Spacing.sm) {
                        ForEach(trials, id: \.trial) { trial in
                            trialPanel(trial)
                        }
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("\(shape) · \(prompt)")
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    private func trialPanel(_ trial: BatteryTrialRecord) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            HStack(spacing: Design.Spacing.sm) {
                MonoLabel(String(format: "t%02d", trial.trial), size: 10, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Colors.foregroundBright)
                if let route = trial.route {
                    MonoLabel("route=\(route)", size: 9, tracking: Design.Tracking.mono,
                              color: route == "toolless" ? Design.Brand.accentText : Design.Brand.forgeText)
                }
                Spacer()
                MonoLabel(String(format: "%.1fs", trial.latencySeconds), size: 9,
                          tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
            }

            ForEach(Array(trial.toolCalls.enumerated()), id: \.offset) { _, call in
                MonoLabel("⚙ \(call.name)\(call.detail.isEmpty ? "" : " — \(call.detail)")\(confirmSuffix(for: call))",
                          size: 9, tracking: Design.Tracking.mono, color: Design.Brand.forgeText)
                    .lineLimit(4)
            }

            if let error = trial.error {
                Text("ERROR: \(error)")
                    .font(Design.Typography.mono(11, weight: .regular))
                    .foregroundStyle(Design.Colors.danger)
                    .textSelection(.enabled)
            } else if trial.timedOut {
                MonoLabel("TIMEOUT — wedged trial guillotined", size: 10,
                          tracking: Design.Tracking.mono, color: Design.Colors.danger)
            } else if let text = trial.text {
                Text(text)
                    .font(Design.Typography.mono(11, weight: .regular))
                    .foregroundStyle(Design.Colors.foreground)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.md,
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    /// #200: the confirmation-gate outcome for one tool invocation, in the
    /// export's own words. A CAPTURED outcome shows on any run kind;
    /// confirm=none shows only on action runs and only for action-named
    /// tools — it means the tool ran and bailed before staging a
    /// confirmation (read tools have no gate, so they get no suffix).
    private func confirmSuffix(for call: BatteryToolCallRecord) -> String {
        if let confirmation = call.confirmation {
            return " · confirm=\(confirmation)"
        }
        if run.kind == "action", DeviceToolBelt.actionToolNames.contains(call.name) {
            return " · confirm=none"
        }
        return ""
    }
}
#endif
