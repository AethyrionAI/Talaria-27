import SwiftUI

// MARK: - Sessions drawer (UI shell)
//
// Left slide-in panel listing chat sessions, per the "02 UPLINK · CHAT" design.
// This is a presentation shell with a clean wiring seam: all data lives in
// `SessionsDrawerModel` behind `// TODO: wire to Sessions API`, and user actions
// surface through callbacks. No backend integration here.

// MARK: View model (wiring seam)

@MainActor
@Observable
final class SessionsDrawerModel {

    enum Group: String, CaseIterable, Identifiable {
        case pinned = "PINNED"
        case today = "TODAY"
        case yesterday = "YESTERDAY"
        case earlier = "EARLIER"
        var id: String { rawValue }
    }

    struct SessionSummary: Identifiable, Hashable {
        let id: String
        var title: String
        var subtitle: String
        var timeLabel: String
        var group: Group
        var isActive: Bool = false
        var isPinned: Bool = false
        /// Optional mono badge, e.g. "AUTO · DAILY".
        var badge: String? = nil
    }

    // Wired to Hermes Sessions API — ChatScreen.refreshSessions() populates
    // this from chatStore.loadSessions() on drawer open and on initial load.
    var sessions: [SessionSummary] = []

    var searchText: String = ""

    /// Header telemetry, e.g. "14 THREADS · 2 ACTIVE".
    var headerStat: String {
        let active = sessions.filter(\.isActive).count
        return "\(sessions.count) THREADS · \(active) ACTIVE"
    }

    // Wiring seams — the host screen connects these to real behavior later.
    var onNewChat: (() -> Void)? = nil
    var onSelectSession: ((SessionSummary) -> Void)? = nil
    var onOpenHostSettings: (() -> Void)? = nil

    /// Sessions filtered by `searchText`, grouped and ordered for display.
    func grouped() -> [(group: Group, items: [SessionSummary])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty
            ? sessions
            : sessions.filter {
                $0.title.lowercased().contains(query) || $0.subtitle.lowercased().contains(query)
            }
        return Group.allCases.compactMap { group in
            let items = filtered.filter { $0.group == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    func selectSession(_ summary: SessionSummary) {
        onSelectSession?(summary)
    }

    func newChat() {
        onNewChat?()
    }

    static let placeholders: [SessionSummary] = [
        SessionSummary(id: "pin-briefing", title: "Morning Briefing",
                       subtitle: "Daily digest · weather, calendar, inbox",
                       timeLabel: "7:00", group: .pinned, isPinned: true, badge: "AUTO · DAILY"),
        SessionSummary(id: "today-resched", title: "Reschedule afternoon",
                       subtitle: "4 events moved · note to Sarah queued",
                       timeLabel: "09:41", group: .today, isActive: true),
        SessionSummary(id: "today-invoice", title: "Invoice triage",
                       subtitle: "3 approved · 1 flagged for review",
                       timeLabel: "08:12", group: .today),
        SessionSummary(id: "yday-tokyo", title: "Tokyo trip planning",
                       subtitle: "Flights + hotel shortlisted",
                       timeLabel: "Tue", group: .yesterday),
        SessionSummary(id: "yday-review", title: "Codebase review",
                       subtitle: "12 files · 3 diffs proposed",
                       timeLabel: "Tue", group: .yesterday),
    ]
}

// MARK: Drawer view

struct SessionsDrawer: View {
    @Binding var isPresented: Bool
    var model: SessionsDrawerModel
    /// Footer host status line (driven by the host screen).
    var hostName: String = "HERMES HOST"
    var hostDetail: String = "LINKED"
    var hostOnline: Bool = true

    private let panelWidth: CGFloat = 320

    var body: some View {
        ZStack(alignment: .leading) {
            backdrop
            panel
                .frame(width: panelWidth)
                .offset(x: isPresented ? 0 : -(panelWidth + 48))
        }
        .animation(Design.Motion.standard, value: isPresented)
        .ignoresSafeArea()
    }

    // MARK: Backdrop

    @ViewBuilder
    private var backdrop: some View {
        if isPresented {
            Design.Colors.scrim
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }
                .transition(.opacity)
                .accessibilityLabel("Close sessions")
                .accessibilityAddTraits(.isButton)
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, Design.Spacing.lg)
            newChatButton
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.sm)
            sessionList
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(drawerBackground)
        .overlay(alignment: .leading) {
            // Bright cyan edge highlight.
            LinearGradient(
                colors: [.clear, Design.Brand.accent.opacity(0.5), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 2)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Design.Colors.cyanBorder)
                .frame(width: 1)
        }
    }

    private var drawerBackground: some View {
        Design.Colors.drawerGradient
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text("SESSIONS")
                    .font(Design.Typography.display(22, weight: .semibold, relativeTo: .title2))
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                MonoLabel(model.headerStat, size: 10, tracking: Design.Tracking.monoWide)
            }
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .frame(width: 34, height: 34)
                    .background(Design.Colors.chipSurface, in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                            .strokeBorder(Design.Colors.chipBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close sessions")
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.top, Design.Spacing.xxl)
        .padding(.bottom, Design.Spacing.md)
    }

    private var searchField: some View {
        HStack(spacing: Design.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.mutedForeground)
            TextField("", text: Binding(get: { model.searchText }, set: { model.searchText = $0 }),
                      prompt: Text("Search conversations…").foregroundStyle(Design.Colors.dimForeground))
                .font(Design.Typography.body(13))
                .foregroundStyle(Design.Colors.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            MonoLabel("⌘K", size: 9, color: Design.Brand.accent)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Design.Colors.accentTint(0.08), in: RoundedRectangle(cornerRadius: Design.CornerRadius.xs))
        }
        .padding(.horizontal, Design.Spacing.sm)
        .frame(height: 42)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.cyanHairline)
    }

    private var newChatButton: some View {
        GlowButton(title: "New Chat", systemImage: "plus", height: 46) {
            model.newChat()
            isPresented = false
        }
    }

    private var sessionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                ForEach(model.grouped(), id: \.group.id) { entry in
                    MonoLabel(entry.group.rawValue, size: 9, tracking: Design.Tracking.monoXWide,
                              color: Design.Colors.dimForeground)
                        .padding(.top, Design.Spacing.xs)
                        .padding(.horizontal, Design.Spacing.xxs)
                    ForEach(entry.items) { item in
                        SessionRow(summary: item) { model.selectSession(item); isPresented = false }
                    }
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.top, Design.Spacing.sm)
        }
    }

    private var footer: some View {
        HStack(spacing: Design.Spacing.xs) {
            StatusPip(color: hostOnline ? Design.Brand.accent : Design.Brand.forge, diameter: 8)
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel(hostName, size: 11, weight: .medium, tracking: Design.Tracking.mono,
                          color: Design.Colors.coolForeground)
                MonoLabel(hostDetail, size: 9, tracking: Design.Tracking.mono)
            }
            Spacer()
            Button { model.onOpenHostSettings?(); isPresented = false } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Design.Brand.accent)
                    .frame(width: Design.Size.minTapTarget, height: Design.Size.minTapTarget)
            }
            .accessibilityLabel("Host settings")
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.sm)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.cyanHairline)
        .padding(.horizontal, Design.Spacing.md)
        .padding(.top, Design.Spacing.sm)
        .padding(.bottom, Design.Spacing.xl)
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let summary: SessionsDrawerModel.SessionSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Design.Spacing.sm) {
                leadingGlyph
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(summary.title)
                            .font(Design.Typography.body(14, weight: summary.isActive ? .medium : .regular))
                            .foregroundStyle(summary.isActive ? Design.Colors.foregroundBright : Design.Colors.foreground)
                            .lineLimit(1)
                        Spacer()
                        MonoLabel(summary.timeLabel, size: 9,
                                  color: summary.isActive ? Design.Brand.accent : Design.Colors.dimForeground)
                    }
                    Text(summary.subtitle)
                        .font(Design.Typography.body(12))
                        .foregroundStyle(summary.isActive ? Design.Colors.coolForeground : Design.Colors.secondaryForeground)
                        .lineLimit(1)
                    if summary.isActive {
                        badge("● CURRENT", color: Design.Brand.accent, tint: 0.14)
                    } else if let badge = summary.badge {
                        self.badge(badge, color: Design.Colors.secondaryForeground, tint: 0.06, neutral: true)
                    }
                }
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudPanel(
                cornerRadius: Design.CornerRadius.md,
                borderColor: summary.isActive ? Design.Colors.accentTint(0.4) : Design.Colors.divider,
                fill: summary.isActive ? Design.Colors.accentTint(0.1) : Design.Colors.surface
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(summary.title), \(summary.subtitle)\(summary.isActive ? ", current session" : "")")
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        if summary.isActive {
            StatusPip(color: Design.Brand.accent, diameter: 7).padding(.top, 5)
        } else if summary.isPinned {
            Image(systemName: "diamond.fill")
                .font(.system(size: 9))
                .foregroundStyle(Design.Brand.accent)
                .padding(.top, 3)
        } else {
            Image(systemName: "hexagon")
                .font(.system(size: 10))
                .foregroundStyle(Design.Colors.mutedForeground)
                .padding(.top, 3)
        }
    }

    private func badge(_ text: String, color: Color, tint: Double, neutral: Bool = false) -> some View {
        MonoLabel(text, size: 8, tracking: Design.Tracking.mono, color: color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                (neutral ? Design.Colors.chipSurface : Design.Colors.accentTint(tint)),
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.xs)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.xs)
                    .strokeBorder(neutral ? Design.Colors.chipBorder : Design.Colors.accentTint(0.4), lineWidth: 1)
            }
            .padding(.top, 4)
    }
}
