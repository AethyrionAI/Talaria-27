import SwiftUI

/// #156a D3 — full metadata + the actions (Run Now, Pause/Resume, Edit,
/// Delete). Reads the SAME store row the list renders, so a mutation's
/// upsert lands on both surfaces at once — they can never disagree.
struct TaskDetailScreen: View {
    let jobID: String

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var actionInFlight = false
    /// Action failures surface here, non-destructively — the record stays
    /// on screen.
    @State private var actionErrorMessage: String?

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            if let store = container.cronJobsStore {
                if let job = store.job(id: jobID) {
                    detail(job: job, store: store)
                } else {
                    goneState
                }
            } else {
                goneState
            }
        }
        .navigationTitle("Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showEditSheet) {
            if let store = container.cronJobsStore, let job = store.job(id: jobID) {
                TaskEditSheet(store: store, draft: CronJobDraft(job: job),
                              skillsStore: container.skillsStore)
            }
        }
    }

    /// The row vanished from the store (deleted here or host-side).
    private var goneState: some View {
        ContentUnavailableView {
            Label {
                Text("Task Gone")
                    .font(Design.Typography.sectionTitle)
                    .foregroundStyle(Design.Colors.foregroundBright)
            } icon: {
                Image(systemName: "clock.badge.xmark")
                    .foregroundStyle(Design.Colors.mutedForeground)
            }
        } description: {
            MonoLabel(
                "THIS JOB NO LONGER EXISTS",
                size: 10,
                weight: .regular,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
    }

    // MARK: - Detail

    private func detail(job: CronJob, store: CronJobsStore) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.md) {
                header(job: job)

                if let message = actionErrorMessage {
                    actionErrorStrip(message)
                }

                actionsPanel(job: job, store: store)
                schedulePanel(job: job)
                outcomePanel(job: job)
                configPanel(job: job)
                hostOnlyPanel(job: job)

                deleteButton
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable { await store.refresh() }
        .confirmationDialog(
            "Delete this task?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \"\(job.displayName)\"", role: .destructive) {
                Task {
                    actionInFlight = true
                    defer { actionInFlight = false }
                    let failure = await store.delete(id: jobID)
                    if let failure {
                        actionErrorMessage = failure
                    } else {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("The job is removed from the Hermes host. This cannot be undone.")
        }
    }

    private func header(job: CronJob) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text(job.displayName)
                .font(Design.Typography.screenTitle2)
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Design.Spacing.xs) {
                TaskStatusBadge(status: job.derivedStatus)
                MonoLabel(job.id, size: 9, tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Design.Spacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Design.Colors.hairline)
                .frame(height: 1)
        }
    }

    private func actionErrorStrip(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Design.Brand.forge)
            Text(message)
                .font(Design.Typography.body(12))
                .foregroundStyle(Design.Colors.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                actionErrorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Design.Colors.mutedForeground)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Brand.forge.opacity(0.4))
    }

    // MARK: - Actions

    private func actionsPanel(job: CronJob, store: CronJobsStore) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            GhostButton(title: "Run Now", systemImage: "play.fill", height: 44) {
                perform { await store.runNow(id: jobID) }
            }
            if job.derivedStatus == .paused {
                GhostButton(title: "Resume", systemImage: "arrow.clockwise", height: 44) {
                    perform { await store.resume(id: jobID) }
                }
            } else {
                GhostButton(title: "Pause", systemImage: "pause.fill", height: 44) {
                    perform { await store.pause(id: jobID) }
                }
            }
            GhostButton(title: "Edit", systemImage: "pencil", height: 44) {
                showEditSheet = true
            }
        }
        .disabled(actionInFlight)
        .opacity(actionInFlight ? 0.6 : 1)
    }

    private func perform(_ action: @escaping () async -> String?) {
        guard !actionInFlight else { return }
        actionInFlight = true
        actionErrorMessage = nil
        Task {
            defer { actionInFlight = false }
            actionErrorMessage = await action()
        }
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                Text("Delete Task")
                    .font(Design.Typography.body(14, weight: .medium))
            }
            .foregroundStyle(Design.Colors.dangerBright)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Design.Colors.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(Design.Colors.danger.opacity(0.4), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .disabled(actionInFlight)
        .padding(.top, Design.Spacing.sm)
    }

    // MARK: - Panels

    private func schedulePanel(job: CronJob) -> some View {
        panel("SCHEDULE") {
            metaRow("Schedule", job.scheduleText ?? "—")
            metaRow("Next run", TaskPresentation.nextRunLine(for: job))
            metaRow("Last run", TaskPresentation.lastRunLine(for: job))
            if let repeatPolicy = job.repeatPolicy {
                metaRow("Repeat", repeatText(repeatPolicy))
            }
            if job.derivedStatus == .paused {
                if let reason = job.pausedReason?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !reason.isEmpty {
                    metaRow("Paused", reason)
                }
            }
        }
    }

    private func repeatText(_ policy: CronRepeatPolicy) -> String {
        let completed = policy.completed ?? 0
        if let times = policy.times {
            return "\(completed)/\(times) runs"
        }
        return completed > 0 ? "forever · \(completed) done" : "forever"
    }

    @ViewBuilder
    private func outcomePanel(job: CronJob) -> some View {
        let execution = job.latestExecution
        let hasContent = job.lastStatus != nil || job.lastError != nil
            || job.lastDeliveryError != nil || execution != nil
        if hasContent {
            panel("LAST OUTCOME") {
                if let status = job.lastStatus {
                    metaRow("Status", status)
                }
                if let error = job.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !error.isEmpty {
                    metaTextBlock("Error", error, color: Design.Colors.dangerBright)
                }
                if let deliveryError = job.lastDeliveryError?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !deliveryError.isEmpty {
                    metaTextBlock("Delivery error", deliveryError, color: Design.Brand.forge)
                }
                if let execution {
                    metaRow("Execution", execution.status ?? "—")
                    if let error = execution.error?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !error.isEmpty {
                        metaTextBlock("Execution error", error, color: Design.Colors.dangerBright)
                    }
                }
            }
        }
    }

    private func configPanel(job: CronJob) -> some View {
        panel("CONFIGURATION") {
            if let prompt = job.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
               !prompt.isEmpty {
                metaTextBlock("Prompt", prompt, color: Design.Colors.foreground)
            }
            metaRow("Deliver", job.deliver ?? "—")
            if let skills = job.skills, !skills.isEmpty {
                metaRow("Skills", skills.joined(separator: ", "))
            }
            if let toolsets = job.enabledToolsets, !toolsets.isEmpty {
                metaRow("Toolsets", toolsets.joined(separator: ", "))
            }
            metaRow("Enabled", job.isEnabled ? "yes" : "no")
        }
    }

    /// Fields the HTTP surface can read but never write (`script`,
    /// `no_agent`, `workdir`, model/provider) — shown read-only when
    /// present, no inputs (#156a).
    @ViewBuilder
    private func hostOnlyPanel(job: CronJob) -> some View {
        let model = job.model ?? job.modelSnapshot
        let provider = job.provider ?? job.providerSnapshot
        let script = job.script?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasContent = model != nil || provider != nil
            || (script?.isEmpty == false) || job.noAgent == true || job.workdir != nil
        if hasContent {
            panel("HOST-SIDE (READ-ONLY)") {
                if let provider {
                    metaRow("Provider", provider)
                }
                if let model {
                    metaRow("Model", model)
                }
                if let script, !script.isEmpty {
                    metaTextBlock("Script", script, color: Design.Colors.foreground)
                }
                if job.noAgent == true {
                    metaRow("Agent", "bypassed (no_agent)")
                }
                if let workdir = job.workdir, !workdir.isEmpty {
                    metaRow("Workdir", workdir)
                }
            }
        }
    }

    // MARK: - Panel scaffolding

    private func panel(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel(title, size: 9, weight: .medium,
                      tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            content()
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.divider)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Design.Spacing.sm) {
            Text(label)
                .font(Design.Typography.body(12))
                .foregroundStyle(Design.Colors.mutedForeground)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(Design.Typography.body(13))
                .foregroundStyle(Design.Colors.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func metaTextBlock(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            Text(label)
                .font(Design.Typography.body(12))
                .foregroundStyle(Design.Colors.mutedForeground)
            Text(value)
                .font(Design.Typography.body(13))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
