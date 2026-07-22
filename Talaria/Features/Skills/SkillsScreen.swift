import SwiftUI

/// #156b D3 — read-only browser over the agent's installed skills. ~100
/// skills on the live host, so search + category grouping are load-bearing.
/// Five content states, distinguished explicitly; a failed refresh with rows
/// on screen keeps the rows and surfaces the error as a strip, never a
/// replacement (same rule as 156a D3). No detail screen — no detail endpoint
/// exists; a row expands in place to show the full description.
struct SkillsScreen: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            if let store = container.skillsStore {
                SkillsContent(store: store)
            } else {
                notConfiguredState
            }
        }
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Bare containers (tests) construct no store; a real launch always has
    /// one. Honest state, no mock data.
    private var notConfiguredState: some View {
        ContentUnavailableView {
            Label {
                Text("Skills Unavailable")
                    .font(Design.Typography.sectionTitle)
                    .foregroundStyle(Design.Colors.foregroundBright)
            } icon: {
                Image(systemName: "sparkles")
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

private struct SkillsContent: View {
    let store: SkillsStore

    @State private var searchText = ""
    @State private var expandedSkillIDs: Set<String> = []

    private var groups: [SkillGroup] {
        SkillsPresentation.groups(from: store.skills, matching: searchText)
    }

    var body: some View {
        Group {
            if store.skills.isEmpty {
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
                skillList
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: - List

    private var skillList: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                searchField
                    .padding(.top, Design.Spacing.sm)

                if let message = store.lastErrorMessage {
                    refreshFailedStrip(message)
                        .padding(.top, Design.Spacing.sm)
                }

                if groups.isEmpty {
                    // The one state Tasks doesn't have, because Tasks has no
                    // search (#160): matches exist ↔ groups exist.
                    noMatchesState
                        .padding(.top, Design.Spacing.xxl)
                } else {
                    LazyVStack(spacing: Design.Spacing.sm, pinnedViews: []) {
                        ForEach(groups, id: \.title) { group in
                            groupSection(group)
                        }
                    }
                    .padding(.top, Design.Spacing.md)
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDismissesKeyboard(.immediately)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Text("SKILLS")
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
        let count = store.skills.count
        let padded = String(format: "%02d", count)
        // Load-time snapshot, honestly labeled — never presented as live.
        if let refreshedAt = store.lastRefreshedAt {
            let time = refreshedAt.formatted(date: .omitted, time: .shortened)
            return "\(padded) SKILL\(count == 1 ? "" : "S") · AS OF \(time)"
        }
        return "\(padded) SKILL\(count == 1 ? "" : "S")"
    }

    private var searchField: some View {
        HStack(spacing: Design.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Design.Colors.mutedForeground)
            TextField("", text: $searchText,
                      prompt: Text("Search skills…").foregroundStyle(Design.Colors.dimForeground))
                .font(Design.Typography.body(13))
                .foregroundStyle(Design.Colors.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Design.Colors.dimForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Design.Spacing.sm)
        .frame(height: 40)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
    }

    private func groupSection(_ group: SkillGroup) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel(group.title.uppercased(), size: 9, weight: .medium,
                      tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
                .padding(.top, Design.Spacing.xs)
            ForEach(group.skills) { skill in
                SkillRow(
                    skill: skill,
                    isExpanded: expandedSkillIDs.contains(skill.id)
                ) {
                    withAnimation(Design.Motion.standard) {
                        if expandedSkillIDs.contains(skill.id) {
                            expandedSkillIDs.remove(skill.id)
                        } else {
                            expandedSkillIDs.insert(skill.id)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Empty / no-match states

    private var loadingState: some View {
        VStack(spacing: Design.Spacing.md) {
            ProgressView()
                .tint(Design.Brand.accent)
            MonoLabel(
                "FETCHING SKILLS",
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
                    Text("Skills Unreachable")
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

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("No Skills Installed")
                    .font(Design.Typography.sectionTitle)
                    .foregroundStyle(Design.Colors.foregroundBright)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(Design.Brand.accent)
            }
        } description: {
            MonoLabel(
                "NO SKILLS INSTALLED ON THIS HOST",
                size: 10,
                weight: .regular,
                tracking: Design.Tracking.monoWide,
                color: Design.Colors.mutedForeground
            )
        }
    }

    /// Search-with-no-matches — echoes the query so the state explains
    /// itself (the #160-noted hermex touch this lane keeps).
    private var noMatchesState: some View {
        VStack(spacing: Design.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Design.Colors.dimForeground)
            Text("No skills match \u{201C}\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}")
                .font(Design.Typography.body(13))
                .foregroundStyle(Design.Colors.mutedForeground)
                .multilineTextAlignment(.center)
            GhostButton(title: "Clear Search", systemImage: "xmark", height: 40) {
                searchText = ""
            }
            .frame(maxWidth: 180)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Design.Spacing.xl)
    }
}

// MARK: - Row

/// Collapsed: name + 2-line collapsed description. Expanded: the full
/// description untouched (embedded newlines and all) — this IS the detail
/// surface; three fields do not earn a screen.
private struct SkillRow: View {
    let skill: Skill
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                HStack(alignment: .center, spacing: Design.Spacing.xs) {
                    Text(skill.name)
                        .font(Design.Typography.body(14, weight: .medium))
                        .foregroundStyle(Design.Colors.foregroundBright)
                        .lineLimit(1)
                    Spacer(minLength: Design.Spacing.xs)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Design.Colors.dimForeground)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                if isExpanded {
                    if let description = skill.description?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                        !description.isEmpty {
                        Text(description)
                            .font(Design.Typography.body(12))
                            .foregroundStyle(Design.Colors.secondaryForeground)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    } else {
                        // Real data only — say the description is absent.
                        MonoLabel("NO DESCRIPTION", size: 9,
                                  tracking: Design.Tracking.mono,
                                  color: Design.Colors.dimForeground)
                    }
                } else if let preview = skill.rowDescription {
                    Text(preview)
                        .font(Design.Typography.body(12))
                        .foregroundStyle(Design.Colors.mutedForeground)
                        .lineLimit(2)
                }
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.divider)
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel(skill.name)
        .accessibilityHint(isExpanded ? "Collapses the description" : "Expands the description")
    }
}
