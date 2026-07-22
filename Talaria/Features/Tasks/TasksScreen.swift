import SwiftUI

/// #156a D3 — the agent's scheduled jobs. Four content states, distinguished
/// explicitly; a failed refresh with rows on screen keeps the rows and
/// surfaces the error as a strip, never a replacement (#160).
struct TasksScreen: View {
    @Environment(AppContainer.self) private var container
    @Environment(TabRouter.self) private var router
    @State private var showCreateSheet = false

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            if let store = container.cronJobsStore {
                TasksContent(store: store, router: router, showCreateSheet: $showCreateSheet)
            } else {
                notConfiguredState
            }
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if container.cronJobsStore != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    GlassCircleButton(icon: "plus", accessibilityLabel: "New task") {
                        showCreateSheet = true
                    }
                }
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            if let store = container.cronJobsStore {
                TaskEditSheet(store: store, draft: CronJobDraft())
            }
        }
    }

    /// Bare containers (tests) construct no store; a real launch always has
    /// one. Honest state, no mock data.
    private var notConfiguredState: some View {
        ContentUnavailableView {
            Label {
                Text("Tasks Unavailable")
                    .font(Design.Typography.sectionTitle)
                    .foregroundStyle(Design.Colors.foregroundBright)
            } icon: {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(Design.Brand.forge)
            }
        } description: {
            MonoLabel(
                "NO HERMES HOST CONFIGURED",
                size: 10,
                weight: .regular,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
    }
}

private struct TasksContent: View {
    let store: CronJobsStore
    let router: TabRouter
    @Binding var showCreateSheet: Bool

    var body: some View {
        Group {
            if store.jobs.isEmpty {
                // Scrollable so pull-to-refresh works from every empty
                // state, not just the list.
                ScrollView {
                    Group {
                        if store.isLoading, !store.hasLoaded {
                            loadingState
                        } else if let message = store.lastErrorMessage, !store.hasLoaded {
                            errorState(message)
                        } else {
                            emptyState
                        }
                    }
                    .containerRelativeFrame([.horizontal, .vertical])
                }
            } else {
                jobList
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: - List

    private var jobList: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                if let message = store.lastErrorMessage {
                    refreshFailedStrip(message)
                        .padding(.top, Design.Spacing.sm)
                }

                LazyVStack(spacing: Design.Spacing.sm) {
                    ForEach(store.jobs) { job in
                        TaskRow(job: job) {
                            router.navigate(to: .taskDetail(job.id))
                        }
                    }
                }
                .padding(.top, Design.Spacing.md)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("SCHEDULED TASKS")
                .font(Design.Typography.screenTitle2)
                .tracking(Design.Tracking.display)
                .foregroundStyle(Design.Colors.foregroundBright)

            HStack(spacing: Design.Spacing.xs) {
                StatusPip(color: Design.Brand.accent, diameter: 7)
                MonoLabel(
                    statusLine,
                    size: 11,
                    weight: .medium,
                    tracking: Design.Tracking.monoWide,
                    color: Design.Colors.secondaryForeground
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Design.Spacing.md)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Design.Colors.hairline)
                .frame(height: 1)
        }
    }

    private var statusLine: String {
        let count = store.jobs.count
        let padded = String(format: "%02d", count)
        // Load-time snapshot, honestly labeled — never presented as live
        // (#160 weakness 3).
        if let refreshedAt = store.lastRefreshedAt {
            let time = refreshedAt.formatted(date: .omitted, time: .shortened)
            return "\(padded) JOB\(count == 1 ? "" : "S") · AS OF \(time)"
        }
        return "\(padded) JOB\(count == 1 ? "" : "S")"
    }

    /// The non-destructive failure surface: rows stay, the strip explains.
    private func refreshFailedStrip(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.xs) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Design.Brand.forge)
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel("REFRESH FAILED — SHOWING LAST FETCH", size: 9,
                          weight: .medium, tracking: Design.Tracking.mono,
                          color: Design.Brand.forge)
                Text(message)
                    .font(Design.Typography.body(12))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Brand.forge.opacity(0.4))
    }

    // MARK: - Empty-list states

    private var loadingState: some View {
        VStack(spacing: Design.Spacing.md) {
            ProgressView()
                .tint(Design.Brand.accent)
            MonoLabel(
                "FETCHING SCHEDULED TASKS",
                size: 10,
                weight: .regular,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Design.Spacing.md) {
            ContentUnavailableView {
                Label {
                    Text("Tasks Unreachable")
                        .font(Design.Typography.sectionTitle)
                        .foregroundStyle(Design.Colors.foregroundBright)
                } icon: {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(Design.Brand.forge)
                }
            } description: {
                Text(message)
                    .font(Design.Typography.body(13))
                    .foregroundStyle(Design.Colors.mutedForeground)
            }
            GhostButton(title: "Retry", systemImage: "arrow.clockwise", height: 44) {
                Task { await store.refresh() }
            }
            .frame(maxWidth: 200)
        }
    }

    /// Empty + loaded: creation offered inline, not just the toolbar `+`.
    private var emptyState: some View {
        VStack(spacing: Design.Spacing.lg) {
            ContentUnavailableView {
                Label {
                    Text("No Scheduled Tasks")
                        .font(Design.Typography.sectionTitle)
                        .foregroundStyle(Design.Colors.foregroundBright)
                } icon: {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .foregroundStyle(Design.Brand.accent)
                }
            } description: {
                MonoLabel(
                    "HERMES HAS NOTHING ON THE CLOCK",
                    size: 10,
                    weight: .regular,
                    tracking: Design.Tracking.monoWide,
                    color: Design.Colors.mutedForeground
                )
            }
            GlowButton(title: "New Task", systemImage: "plus", height: 46) {
                showCreateSheet = true
            }
            .frame(maxWidth: 240)
        }
    }
}

// MARK: - Row

/// Lean by design: name, status, next run, one-line prompt preview. The
/// nine-row metadata stack lives in detail, not here (#160 weakness 2).
private struct TaskRow: View {
    let job: CronJob
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                HStack(alignment: .center, spacing: Design.Spacing.xs) {
                    Text(job.displayName)
                        .font(Design.Typography.body(14, weight: .medium))
                        .foregroundStyle(Design.Colors.foregroundBright)
                        .lineLimit(1)
                    Spacer(minLength: Design.Spacing.xs)
                    TaskStatusBadge(status: job.derivedStatus)
                }
                MonoLabel(TaskPresentation.nextRunLine(for: job), size: 9,
                          tracking: Design.Tracking.mono,
                          color: Design.Colors.secondaryForeground)
                    .hudSingleLine()
                if let preview = promptPreview {
                    Text(preview)
                        .font(Design.Typography.body(12))
                        .foregroundStyle(Design.Colors.mutedForeground)
                        .lineLimit(1)
                }
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.divider)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(job.displayName), \(job.derivedStatus.badgeText)")
    }

    private var promptPreview: String? {
        guard let prompt = job.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else { return nil }
        return prompt.replacingOccurrences(of: "\n", with: " ")
    }
}

// MARK: - Status badge

struct TaskStatusBadge: View {
    let status: CronJobStatus

    var body: some View {
        HStack(spacing: 4) {
            StatusPip(color: status.badgeColor, diameter: 6, blinks: status == .running)
            MonoLabel(status.badgeText, size: 8, weight: .medium,
                      tracking: Design.Tracking.mono, color: status.badgeColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(status.badgeColor.opacity(0.1), in: RoundedRectangle(cornerRadius: Design.CornerRadius.xs))
    }
}

extension CronJobStatus {
    var badgeText: String {
        switch self {
        case .running: "RUNNING"
        case .active: "ACTIVE"
        case .paused: "PAUSED"
        case .off: "OFF"
        case .error: "ERROR"
        case .needsAttention: "ATTENTION"
        }
    }

    @MainActor var badgeColor: Color {
        switch self {
        case .running, .active: Design.Brand.accent
        case .paused: Design.Colors.mutedForeground
        case .off: Design.Colors.dimForeground
        case .error: Design.Colors.danger
        case .needsAttention: Design.Brand.forge
        }
    }
}

// MARK: - Shared presentation

enum TaskPresentation {
    /// The next-run line for a job. Offset-carrying timestamps convert to
    /// this device's clock; a NAIVE server timestamp is host wall-clock the
    /// device can't convert — shown raw and labeled, never silently
    /// reinterpreted. "—" where nothing is knowable (real data only).
    static func nextRunLine(for job: CronJob) -> String {
        if job.latestExecution?.isInFlight == true {
            return "RUNNING NOW"
        }
        if let date = job.nextRunAt {
            return "NEXT \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        if let raw = job.nextRunAtRaw {
            return "NEXT \(compactHostTimestamp(raw)) HOST TIME"
        }
        if job.state == "completed" {
            return "COMPLETED"
        }
        return "NO RUN SCHEDULED"
    }

    static func lastRunLine(for job: CronJob) -> String {
        if let date = job.lastRunAt {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        if let raw = job.lastRunAtRaw {
            return "\(compactHostTimestamp(raw)) HOST TIME"
        }
        return "—"
    }

    /// "2026-07-22T09:00:00.123456" → "2026-07-22 09:00" — display trim
    /// only, no timezone math.
    static func compactHostTimestamp(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "T", with: " ")
        if let dotIndex = text.firstIndex(of: ".") {
            text = String(text[..<dotIndex])
        }
        // Drop trailing :ss when the shape matches HH:mm:ss.
        if text.count >= 19, text[text.index(text.endIndex, offsetBy: -3)] == ":" {
            text = String(text.dropLast(3))
        }
        return text
    }
}
