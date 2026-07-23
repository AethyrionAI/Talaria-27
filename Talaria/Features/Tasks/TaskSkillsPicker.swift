import SwiftUI

// MARK: - Selection model (testable, no view state)

/// #156b D5 — the ordered skill selection behind the cron editor's picker.
/// Parses and re-emits the SAME comma-separated string the PATCH surface
/// expects (splitting matches `CronJobDraft.parsedSkills`) — the wire format
/// does not change. Order is preserved from the seeded text; newly toggled-on
/// names append; values not present in the fetched list are "custom" and
/// survive untouched unless the user explicitly deselects them (the
/// preserve-unknown-values pattern, #160 idea 1).
struct SkillsPickerSelection: Equatable {
    private(set) var selected: [String]

    init(commaSeparated: String) {
        var seen = Set<String>()
        selected = commaSeparated
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func isSelected(_ name: String) -> Bool {
        selected.contains(name)
    }

    mutating func toggle(_ name: String) {
        if let index = selected.firstIndex(of: name) {
            selected.remove(at: index)
        } else {
            selected.append(name)
        }
    }

    /// Selected values the fetched list doesn't know — legacy or hand-typed;
    /// rendered as "(custom)" rows that stay selected.
    func customValues(knownNames: Set<String>) -> [String] {
        selected.filter { !knownNames.contains($0) }
    }

    var commaSeparatedValue: String {
        selected.joined(separator: ", ")
    }
}

// MARK: - Field mode (testable, no view state)

/// #168a — which of the field's two modes is showing, lifted out of `@State`
/// so the transitions are assertable. Before this the free-text flag had
/// exactly ONE write site (`true`) and no way back: tapping EDIT AS TEXT
/// swapped the picker for a raw `TextField` permanently, for the life of the
/// sheet, while the caption promised a return path that did not exist.
///
/// The mode owns no text. Both transitions leave `skillsText` untouched, so a
/// round trip through free text is selection-preserving by construction —
/// which is what makes the "(custom)"-value preservation property (#156b D5)
/// reachable from the UI at all.
struct SkillsFieldMode: Equatable {
    private(set) var isFreeText: Bool

    init(isFreeText: Bool = false) {
        self.isFreeText = isFreeText
    }

    /// A picker can only show when the host list actually has rows.
    func showsPicker(hasPickerSkills: Bool) -> Bool {
        hasPickerSkills && !isFreeText
    }

    /// The escape into hand-typing — only from the picker, and only when
    /// there is a picker to escape.
    func offersEditAsText(hasPickerSkills: Bool) -> Bool {
        hasPickerSkills && !isFreeText
    }

    /// #168a's second dead-end guard: with no host list there is no picker to
    /// return to, so free text is the only mode and offering a way "back"
    /// would open a second door onto nothing.
    func offersReturnToPicker(hasPickerSkills: Bool) -> Bool {
        hasPickerSkills && isFreeText
    }

    mutating func editAsText() {
        isFreeText = true
    }

    mutating func usePicker() {
        isFreeText = false
    }
}

// MARK: - Field control

/// The SKILLS field for the cron create/edit sheet. Server-driven when the
/// skills fetch succeeded and returned rows; free text (exactly the 156a
/// field) when it didn't — degrade, don't block. "Edit as text" keeps
/// hand-typing reachable even with the picker up, same escape the deliver
/// picker offers.
struct TaskSkillsPicker: View {
    @Binding var skillsText: String
    /// nil = fetch unavailable/failed; empty = host reports no skills. Both
    /// degrade to free text (nothing to pick).
    let skills: [Skill]?

    @State private var mode = SkillsFieldMode()
    @State private var showPicker = false

    private var pickerSkills: [Skill]? {
        guard let skills, !skills.isEmpty else { return nil }
        return skills
    }

    private var hasPickerSkills: Bool {
        pickerSkills != nil
    }

    var body: some View {
        if mode.showsPicker(hasPickerSkills: hasPickerSkills), let pickerSkills {
            pickerControl(pickerSkills)
        } else {
            freeTextField
        }
    }

    private var freeTextField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            TextField("", text: $skillsText,
                      prompt: Text("skill-one, skill-two (optional)")
                          .foregroundStyle(Design.Colors.dimForeground))
                .font(Design.Typography.mono(12))
                .foregroundStyle(Design.Colors.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, Design.Spacing.sm)
                .frame(height: 44)
                .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
            // The list-ness of the field stays on screen in both cases; only
            // the picker promise is gone — the button below says it now.
            MonoLabel(
                hasPickerSkills
                    ? "COMMA-SEPARATED SKILL NAMES"
                    : "COMMA-SEPARATED SKILL NAMES ON THE HOST",
                size: 8,
                tracking: Design.Tracking.mono, color: Design.Colors.dimForeground
            )
            if mode.offersReturnToPicker(hasPickerSkills: hasPickerSkills) {
                usePickerButton
            }
        }
    }

    /// #168a — the return path the caption used to only promise.
    private var usePickerButton: some View {
        Button {
            mode.usePicker()
        } label: {
            MonoLabel("USE PICKER", size: 8, weight: .medium,
                      tracking: Design.Tracking.mono, color: Design.Brand.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use the skills picker instead of text")
    }

    private func pickerControl(_ available: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            Button {
                showPicker = true
            } label: {
                HStack {
                    Text(currentLabel)
                        .font(Design.Typography.mono(12))
                        .foregroundStyle(selectionIsEmpty ? Design.Colors.mutedForeground : Design.Colors.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Design.Colors.mutedForeground)
                }
                .padding(.horizontal, Design.Spacing.sm)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skills, \(selectionIsEmpty ? "none selected" : currentLabel)")

            if mode.offersEditAsText(hasPickerSkills: hasPickerSkills) {
                Button {
                    mode.editAsText()
                } label: {
                    MonoLabel("EDIT AS TEXT", size: 8, weight: .medium,
                              tracking: Design.Tracking.mono, color: Design.Brand.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showPicker) {
            SkillsPickerSheet(skillsText: $skillsText, available: available)
        }
    }

    private var selectionIsEmpty: Bool {
        SkillsPickerSelection(commaSeparated: skillsText).selected.isEmpty
    }

    private var currentLabel: String {
        let selection = SkillsPickerSelection(commaSeparated: skillsText)
        guard !selection.selected.isEmpty else { return "None (optional)" }
        return selection.selected.joined(separator: ", ")
    }
}

// MARK: - Multi-select sheet

/// Multi-select over the fetched skills. Every toggle re-emits the field's
/// comma-separated string immediately — there is no separate apply step to
/// lose state in. Custom values (selected but not on the host list) pin to
/// the top as "(custom)" rows and stay selected until deliberately removed.
private struct SkillsPickerSheet: View {
    @Binding var skillsText: String
    let available: [Skill]

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var selection: SkillsPickerSelection {
        SkillsPickerSelection(commaSeparated: skillsText)
    }

    private var knownNames: Set<String> {
        Set(available.map(\.name))
    }

    private var visibleSkills: [Skill] {
        available
            .filter { $0.matches(searchText) }
            .sorted { lhs, rhs in
                let ordering = lhs.name.caseInsensitiveCompare(rhs.name)
                if ordering != .orderedSame { return ordering == .orderedAscending }
                return lhs.name < rhs.name
            }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                HUDScreenBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                        searchField

                        let customValues = selection.customValues(knownNames: knownNames)
                        if !customValues.isEmpty {
                            MonoLabel("SELECTED — NOT ON THE HOST LIST", size: 8, weight: .medium,
                                      tracking: Design.Tracking.monoXWide,
                                      color: Design.Colors.mutedForeground)
                            ForEach(customValues, id: \.self) { value in
                                row(title: "\(value) (custom)", subtitle: nil, isSelected: true) {
                                    toggle(value)
                                }
                            }
                        }

                        MonoLabel("ON THE HOST", size: 8, weight: .medium,
                                  tracking: Design.Tracking.monoXWide,
                                  color: Design.Colors.mutedForeground)
                            .padding(.top, customValues.isEmpty ? 0 : Design.Spacing.xs)
                        if visibleSkills.isEmpty {
                            Text("No skills match \u{201C}\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}")
                                .font(Design.Typography.body(12))
                                .foregroundStyle(Design.Colors.mutedForeground)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, Design.Spacing.lg)
                        } else {
                            LazyVStack(spacing: Design.Spacing.xs) {
                                ForEach(visibleSkills) { skill in
                                    row(
                                        title: skill.name,
                                        subtitle: skill.rowDescription,
                                        isSelected: selection.isSelected(skill.name)
                                    ) {
                                        toggle(skill.name)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.sm)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Design.Typography.body(15, weight: .medium))
                        .foregroundStyle(Design.Brand.accent)
                }
            }
        }
    }

    private func toggle(_ name: String) {
        var updated = selection
        updated.toggle(name)
        skillsText = updated.commaSeparatedValue
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
        }
        .padding(.horizontal, Design.Spacing.sm)
        .frame(height: 40)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
    }

    private func row(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        toggle: @escaping () -> Void
    ) -> some View {
        Button(action: toggle) {
            HStack(alignment: .center, spacing: Design.Spacing.xs) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Design.Brand.accent : Design.Colors.dimForeground)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Design.Typography.mono(12))
                        .foregroundStyle(Design.Colors.foreground)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(Design.Typography.body(11))
                            .foregroundStyle(Design.Colors.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
