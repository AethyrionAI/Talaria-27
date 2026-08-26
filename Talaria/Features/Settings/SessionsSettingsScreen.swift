import SwiftUI

// MARK: - Sessions settings screen (Settings → SESSIONS)
//
// Recent sessions, an overview, metadata export, and a clear action.
// Mirrors design/Settings.dc.html screen 07, adapted to Talaria's reality:
//   • Sessions come from the ACTIVE brain (#27 — ChatBackendRouter routes
//     listSessions): the Hermes HOST's Sessions API (:8642) when Hermes
//     carries chat, or the single locally cached conversation when the
//     on-device brain does (#26). The third overview tile shows ACTIVE (a
//     real count) instead of the mockup's unbacked on-device byte figure.
//   • There is no host bulk-delete endpoint; the only real op is
//     clearConversation() (the current thread — it clears BOTH brains), so
//     the destructive action is "Clear Conversation", not "Clear All
//     Sessions". A true delete-all would need a new host route.
struct SessionsSettingsScreen: View {
    // #252: deck pages supply the background and top bar; the screen keeps
    // owning its content, tasks, and sheets in both presentations.
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(TabRouter.self) private var router

    @State private var sessions: [HermesSessionInfo] = []
    @State private var isLoading = false
    @State private var isClearing = false
    @State private var isExporting = false
    @State private var showClearConfirm = false
    @State private var showExportSheet = false
    @State private var exportURL: URL?

    private var totalMessages: Int { sessions.reduce(0) { $0 + $1.messageCount } }
    private var activeCount: Int { sessions.filter(\.isActive).count }

    /// Most-recent first; sessions with no timestamp sort last.
    private var sortedSessions: [HermesSessionInfo] {
        sessions.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
    }

    var body: some View {
        ZStack {
            if !embedded {
                HUDScreenBackground()
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    if !embedded {
                        SettingsScreenHeader(title: "Sessions", subtitle: "Storage & Data") { dismiss() }
                    }
                    if embedded {
                        SubsystemHero(
                            motif: .stackedRows,
                            title: SettingsSubsystem.sessions.title,
                            status: SettingsCardValues.sessions(
                                count: isLoading ? nil : sessions.count,
                                hasHost: container.hasGatewayCredentials),
                            statusColor: isLoading ? Design.Colors.mutedForeground : Design.Brand.accentText,
                            chip: SettingsSubsystem.sessions.chip,
                            accented: !isLoading
                        )
                    }
                    statsRow
                    shelfSection
                    midTurnSendSection
                    recentSection
                    manageSection
                    footerNote
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Sessions")
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await load() }
        // #193: was a `.confirmationDialog`, whose cancel role does not
        // render on iOS 26/27 — destructive confirmations use `.alert`,
        // which still shows an explicit way out.
        .alert(
            "Clear the current conversation?",
            isPresented: $showClearConfirm
        ) {
            Button("Clear Conversation", role: .destructive) {
                Task { await clearConversation() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Starts a fresh thread on the host. Your other sessions are not affected.")
        }
        .sheet(isPresented: $showExportSheet) {
            if let exportURL {
                ShareSheet(activityItems: [exportURL])
            }
        }
    }

    // MARK: Overview tiles

    private var statsRow: some View {
        HStack(spacing: Design.Spacing.sm) {
            statTile(value: "\(sessions.count)", label: "Sessions")
            statTile(value: compactCount(totalMessages), label: "Messages")
            statTile(value: "\(activeCount)", label: "Active")
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: Design.Spacing.xs) {
            Text(value)
                .font(Design.Typography.display(24, weight: .bold, relativeTo: .title))
                .foregroundStyle(Design.Brand.accentBrightText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            MonoLabel(label, size: 8, weight: .medium,
                      tracking: Design.Tracking.monoWide, color: Design.Colors.mutedForeground)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Spacing.md)
        .hudPanel(
            cornerRadius: Design.CornerRadius.lg,
            borderColor: Design.Colors.accentTint(0.14),
            fill: Design.Colors.background.opacity(0.5),
            innerGlow: false
        )
    }

    // MARK: Shelf

    /// OPEN_ITEMS #187: `fetchSessionList` asks the gateway for
    /// `?min_messages=1` and the gateway silently ignores it, so zero-message
    /// sessions reach the app and pile up in the drawer. The shelf filters
    /// them client-side; this is the escape hatch. The current session and any
    /// pinned session stay visible either way.
    private var shelfSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Shelf", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                HStack(spacing: Design.Spacing.sm) {
                    Text("Show Empty Sessions")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.foreground)
                    Spacer()
                    Toggle("", isOn: showEmptySessionsBinding)
                        .labelsHidden()
                        .tint(Design.Brand.accentText)
                }
                Text("Sessions the host reports with no messages are hidden from the sessions drawer. The current session and any pinned session always show.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
            .padding(Design.Spacing.md)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    /// #357 (3C): Owen's send-behavior toggle. QUEUE is the shipped #306
    /// default; STEER is safe to prefer in any phase because a steer that
    /// misses its window degrades honestly into the queued next message —
    /// the composer names whichever door a send actually took.
    private var midTurnSendSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Mid-turn send", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                HStack(spacing: Design.Spacing.sm) {
                    Text("Send While Streaming")
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.foreground)
                    Spacer()
                    Picker("", selection: midTurnSendBinding) {
                        Text("Queues").tag(MidTurnSendAction.queue)
                        Text("Steers").tag(MidTurnSendAction.steer)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                }
                Text("Queues: the message waits and posts when the current turn finishes. Steers: the message redirects the running turn if it can still take direction — otherwise it queues, and the composer says which happened.")
                    .font(Design.Typography.caption)
                    .foregroundStyle(Design.Colors.secondaryForeground)
            }
            .padding(Design.Spacing.md)
            .hudPanel(
                cornerRadius: Design.CornerRadius.lg,
                borderColor: Design.Colors.accentTint(0.12),
                fill: Design.Colors.background.opacity(0.5),
                innerGlow: false
            )
        }
    }

    private var midTurnSendBinding: Binding<MidTurnSendAction> {
        Binding(
            get: { settingsStore.settings.midTurnSendAction },
            set: { settingsStore.settings.midTurnSendAction = $0 }
        )
    }

    private var showEmptySessionsBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.settings.showEmptySessions },
            set: { settingsStore.settings.showEmptySessions = $0 }
        )
    }

    // MARK: Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Recent", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(spacing: 0) {
                if isLoading && sessions.isEmpty {
                    infoRow("Loading sessions…", showSpinner: true)
                } else if sortedSessions.isEmpty {
                    infoRow("No sessions yet", showSpinner: false)
                } else {
                    let rows = Array(sortedSessions.prefix(8))
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, session in
                        sessionRow(session)
                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(Design.Colors.hairline)
                                .frame(height: 1)
                                .padding(.horizontal, Design.Spacing.md)
                        }
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

    private func sessionRow(_ session: HermesSessionInfo) -> some View {
        Button {
            Task { await open(session) }
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Circle()
                    .fill(session.isActive ? Design.Brand.accent : Design.Colors.mutedForeground)
                    .frame(width: 6, height: 6)
                    .shadow(color: session.isActive ? Design.Brand.accent : .clear, radius: 3)

                VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                    Text(sessionTitle(session))
                        .font(Design.Typography.callout)
                        .foregroundStyle(Design.Colors.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    MonoLabel(rowMeta(session), size: 9, weight: .medium,
                              tracking: Design.Tracking.mono, color: Design.Colors.mutedForeground)
                    // #122: a compact spend/usage line, only when the wire
                    // carried real figures — absent data hides it (never $0.00).
                    if let readout = SessionCostReadout.display(for: session.usage) {
                        MonoLabel(readout.line, size: 9, weight: .medium,
                                  tracking: Design.Tracking.mono, color: Design.Colors.dimForeground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .truncationMode(.tail)
                            .accessibilityLabel(costAccessibilityLabel(readout))
                    }
                }

                Spacer(minLength: Design.Spacing.xs)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Design.Colors.accentTint(0.7))
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ text: String, showSpinner: Bool) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            if showSpinner { ProgressView().controlSize(.small) }
            MonoLabel(text, size: 10, tracking: Design.Tracking.mono,
                      color: Design.Colors.mutedForeground)
            Spacer()
        }
        .padding(Design.Spacing.md)
    }

    // MARK: Manage

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Manage", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            exportRow
            clearRow
        }
    }

    private var exportRow: some View {
        Button {
            Task { await prepareExport() }
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Text("Export Conversations")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Brand.accentBrightText)
                Spacer()
                if isExporting {
                    ProgressView().controlSize(.mini)
                } else {
                    MonoLabel(".JSON", size: 9, weight: .medium,
                              tracking: Design.Tracking.mono, color: Design.Brand.accentText)
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .hudPanel(
                cornerRadius: Design.CornerRadius.md,
                borderColor: Design.Colors.accentTint(0.32),
                fill: Design.Colors.accentTint(0.08),
                innerGlow: false
            )
        }
        .buttonStyle(.plain)
        .disabled(isExporting || sessions.isEmpty)
    }

    private var clearRow: some View {
        Button {
            showClearConfirm = true
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Text("Clear Conversation")
                    .font(Design.Typography.callout)
                    .foregroundStyle(Design.Colors.dangerBrightText)
                Spacer()
                if isClearing {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Design.Colors.dangerBrightText)
                        .frame(width: 18, height: 18)
                        .overlay {
                            RoundedRectangle(cornerRadius: Design.CornerRadius.xs)
                                .strokeBorder(Design.Colors.danger.opacity(0.5), lineWidth: 1)
                        }
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                Design.Colors.danger.opacity(0.07),
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.md)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.danger.opacity(0.34), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isClearing)
    }

    private var footerNote: some View {
        MonoLabel("Sessions stored on the Hermes host",
                  size: 9, tracking: Design.Tracking.monoWide,
                  color: Design.Colors.mutedForeground)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Design.Spacing.xs)
    }

    // MARK: Derived strings

    private func sessionTitle(_ s: HermesSessionInfo) -> String {
        if let t = s.title, !t.isEmpty { return t }
        return "Untitled session"
    }

    private func rowMeta(_ s: HermesSessionInfo) -> String {
        let msgs = "\(s.messageCount) MSG\(s.messageCount == 1 ? "" : "S")"
        guard let date = s.lastActive else { return msgs }
        return "\(relativeLabel(date).uppercased()) · \(msgs)"
    }

    private func relativeLabel(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    /// Spells the compact cost line out for VoiceOver (#122) — the mono glyphs
    /// don't read cleanly. Mirrors the fields' honest-absence: only real
    /// segments are voiced.
    private func costAccessibilityLabel(_ readout: SessionCostReadout.Display) -> String {
        var parts: [String] = []
        if let cost = readout.costText {
            parts.append("\(readout.costIsEstimated ? "estimated cost " : "cost ")\(cost)")
        }
        if let input = readout.inputText { parts.append("\(input) input tokens") }
        if let output = readout.outputText { parts.append("\(output) output tokens") }
        if let calls = readout.apiCallsText { parts.append("\(calls) API calls") }
        return parts.joined(separator: ", ")
    }

    private func compactCount(_ n: Int) -> String {
        guard n >= 1000 else { return "\(n)" }
        let k = Double(n) / 1000.0
        return String(format: k >= 10 ? "%.0fK" : "%.1fK", k)
    }

    // MARK: Actions

    private func load() async {
        isLoading = true
        sessions = await container.chatStore.loadSessions()
        isLoading = false
    }

    private func open(_ session: HermesSessionInfo) async {
        await container.chatStore.openSession(session.id)
        router.dismissSheet()
    }

    private func clearConversation() async {
        isClearing = true
        try? await container.chatStore.clearConversation()
        isClearing = false
        await load()
    }

    private func prepareExport() async {
        isExporting = true
        defer { isExporting = false }
        let records = sortedSessions.map(SessionExportRecord.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("talaria-sessions-\(Int(Date().timeIntervalSince1970)).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        exportURL = url
        showExportSheet = true
    }
}

// MARK: - Export record (metadata only)

private struct SessionExportRecord: Codable {
    let id: String
    let title: String?
    let model: String?
    let source: String?
    let messageCount: Int
    let lastActive: Date?
    let isActive: Bool

    init(_ s: HermesSessionInfo) {
        id = s.id
        title = s.title
        model = s.model
        source = s.source
        messageCount = s.messageCount
        lastActive = s.lastActive
        isActive = s.isActive
    }
}
