import SwiftUI

/// #156a D5 — ONE sheet for create and edit, driven by `CronJobDraft`
/// (#160 idea 1). Fields are exactly the writable surface: create set +
/// PATCH whitelist, nothing else. On server rejection the sheet STAYS OPEN
/// with the input intact and renders the server's message verbatim — the
/// server is the only cron validator that exists (D4 non-negotiable).
struct TaskEditSheet: View {
    let store: CronJobsStore
    @State var draft: CronJobDraft
    /// #156b D5: feeds the skills picker. nil (bare test containers, or a
    /// failed fetch leaving the store empty-unloaded) degrades the field to
    /// the 156a free text — degrade, don't block.
    var skillsStore: SkillsStore?

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    /// The server's `{"error": ...}` string, untranslated.
    @State private var serverMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                HUDScreenBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Design.Spacing.md) {
                        nameField
                        promptField
                        ScheduleInputView(draft: $draft.schedule)
                        deliverField
                        skillsField
                        repeatField
                        if draft.isEditing {
                            enabledField
                        }

                        if let serverMessage {
                            rejectionStrip(serverMessage)
                        }

                        GlowButton(
                            title: draft.isEditing ? "Save Changes" : "Create Task",
                            systemImage: draft.isEditing ? "checkmark" : "plus",
                            height: 50
                        ) {
                            save()
                        }
                        .disabled(!draft.isSubmittable || isSaving)
                        .opacity(draft.isSubmittable && !isSaving ? 1 : 0.5)
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.md)
                }
            }
            .navigationTitle(draft.isEditing ? "Edit Task" : "New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(Design.Typography.body(15))
                        .foregroundStyle(Design.Colors.secondaryForeground)
                }
                if isSaving {
                    ToolbarItem(placement: .topBarTrailing) {
                        ProgressView()
                            .tint(Design.Brand.accent)
                    }
                }
            }
            .task {
                // Best-effort platform list for the deliver picker; failure
                // just means free text (D5).
                await store.refreshDeliverPlatforms()
            }
            .task {
                // #156b D5: best-effort skill list for the skills picker —
                // same degradation contract.
                await skillsStore?.refresh()
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    // MARK: - Save

    private func save() {
        guard !isSaving else { return }
        serverMessage = nil
        if draft.isEditing {
            guard let patch = draft.patchBody() else { return }
            guard !patch.isEmpty else {
                // Nothing changed — closing is the honest no-op.
                dismiss()
                return
            }
            guard let jobID = draft.editingJobID else { return }
            isSaving = true
            Task {
                defer { isSaving = false }
                switch await store.update(id: jobID, patch: patch) {
                case .success:
                    dismiss()
                case .failure(let failure):
                    serverMessage = failure.message
                }
            }
        } else {
            guard let body = draft.createBody() else { return }
            isSaving = true
            Task {
                defer { isSaving = false }
                switch await store.create(body) {
                case .success:
                    dismiss()
                case .failure(let failure):
                    serverMessage = failure.message
                }
            }
        }
    }

    /// The verbatim server rejection — inline, input intact.
    private func rejectionStrip(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.xs) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Design.Brand.forge)
            VStack(alignment: .leading, spacing: 2) {
                MonoLabel("HOST REJECTED THIS TASK", size: 9, weight: .medium,
                          tracking: Design.Tracking.mono, color: Design.Brand.forge)
                Text(message)
                    .font(Design.Typography.body(12))
                    .foregroundStyle(Design.Colors.secondaryForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(Design.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Brand.forge.opacity(0.4))
    }

    // MARK: - Fields

    private var nameField: some View {
        fieldGroup("NAME") {
            TextField("", text: $draft.name,
                      prompt: Text("What is this task called?")
                          .foregroundStyle(Design.Colors.dimForeground))
                .font(Design.Typography.body(14))
                .foregroundStyle(Design.Colors.foreground)
                .padding(.horizontal, Design.Spacing.sm)
                .frame(height: 44)
                .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        }
    }

    private var promptField: some View {
        fieldGroup("PROMPT") {
            TextEditor(text: $draft.prompt)
                .font(Design.Typography.body(14))
                .foregroundStyle(Design.Colors.foreground)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 88, maxHeight: 180)
                .padding(Design.Spacing.xs)
                .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        }
    }

    private var deliverField: some View {
        fieldGroup("DELIVER TO") {
            TaskDeliverPicker(deliver: $draft.deliver, platforms: store.deliverPlatforms)
        }
    }

    /// #156b D5 — the picker 156a's free-text field promised. Fed from the
    /// gateway skill list; a failed fetch leaves the field free text exactly
    /// as it was.
    private var skillsField: some View {
        fieldGroup("SKILLS") {
            TaskSkillsPicker(
                skillsText: $draft.skillsText,
                skills: (skillsStore?.hasLoaded == true) ? skillsStore?.skills : nil
            )
        }
    }

    private var repeatField: some View {
        fieldGroup("REPEAT LIMIT") {
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                Toggle(isOn: Binding(
                    get: { draft.repeatTimes != nil },
                    set: { limited in draft.repeatTimes = limited ? max(draft.repeatTimes ?? 1, 1) : nil }
                )) {
                    Text("Limit total runs")
                        .font(Design.Typography.body(14))
                        .foregroundStyle(Design.Colors.foreground)
                }
                .tint(Design.Brand.accent)

                if let times = draft.repeatTimes {
                    Stepper(value: Binding(
                        get: { times },
                        set: { draft.repeatTimes = max($0, 1) }
                    ), in: 1 ... 999) {
                        Text("Run \(times) time\(times == 1 ? "" : "s"), then stop")
                            .font(Design.Typography.body(13))
                            .foregroundStyle(Design.Colors.secondaryForeground)
                    }
                }
            }
            .padding(Design.Spacing.sm)
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        }
    }

    private var enabledField: some View {
        fieldGroup("STATE") {
            Toggle(isOn: $draft.enabled) {
                Text("Enabled")
                    .font(Design.Typography.body(14))
                    .foregroundStyle(Design.Colors.foreground)
            }
            .tint(Design.Brand.accent)
            .padding(Design.Spacing.sm)
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        }
    }

    private func fieldGroup(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel(title, size: 9, weight: .medium,
                      tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)
            content()
        }
    }
}

// MARK: - Deliver picker (D5)

/// Server-driven when `/health/detailed` answered (connected platforms +
/// the two built-in destinations), free text when it didn't. A current
/// value outside the server's list is preserved as a marked "(custom)"
/// entry — editing never clobbers a legacy value.
struct TaskDeliverPicker: View {
    @Binding var deliver: String
    let platforms: [String]?

    /// "Custom…" flips to free text without losing the typed value.
    @State private var useFreeText = false

    private static let builtIns = ["origin", "local"]

    var options: [String] {
        guard let platforms else { return [] }
        var merged = Self.builtIns
        for platform in platforms where !merged.contains(platform) {
            merged.append(platform)
        }
        return merged
    }

    var body: some View {
        if platforms == nil || useFreeText {
            freeTextField
        } else {
            menuPicker
        }
    }

    private var freeTextField: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            TextField("", text: $deliver,
                      prompt: Text("origin, local, or a platform name (optional)")
                          .foregroundStyle(Design.Colors.dimForeground))
                .font(Design.Typography.mono(12))
                .foregroundStyle(Design.Colors.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, Design.Spacing.sm)
                .frame(height: 44)
                .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
            if platforms == nil {
                MonoLabel("HOST PLATFORM LIST UNAVAILABLE — FREE ENTRY", size: 8,
                          tracking: Design.Tracking.mono, color: Design.Colors.dimForeground)
            }
        }
    }

    private var menuPicker: some View {
        Menu {
            Button("Server default") { deliver = "" }
            ForEach(options, id: \.self) { option in
                Button {
                    deliver = option
                } label: {
                    if deliver == option {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
            if isCustomValue {
                Button {
                    // Keep it — selecting the marked row is a no-op keep.
                } label: {
                    Label("\(deliver) (custom)", systemImage: "checkmark")
                }
            }
            Button("Custom…") { useFreeText = true }
        } label: {
            HStack {
                Text(currentLabel)
                    .font(Design.Typography.body(14))
                    .foregroundStyle(deliver.isEmpty ? Design.Colors.mutedForeground : Design.Colors.foreground)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Design.Colors.mutedForeground)
            }
            .padding(.horizontal, Design.Spacing.sm)
            .frame(height: 44)
            .contentShape(Rectangle())
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
        }
    }

    private var isCustomValue: Bool {
        !deliver.isEmpty && !options.contains(deliver)
    }

    private var currentLabel: String {
        if deliver.isEmpty { return "Server default" }
        return isCustomValue ? "\(deliver) (custom)" : deliver
    }
}

// MARK: - Schedule input (D4 ⭐)

/// The structured schedule picker — emits one of the four verified grammar
/// strings; hermex's bare free-text survives as the Advanced escape hatch.
struct ScheduleInputView: View {
    @Binding var draft: ScheduleDraft

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel("SCHEDULE", size: 9, weight: .medium,
                      tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            Picker("Schedule kind", selection: $draft.mode) {
                ForEach(ScheduleDraft.Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch draft.mode {
                case .interval:
                    intervalControls
                case .daily:
                    timeControls(showWeekday: false)
                case .weekly:
                    timeControls(showWeekday: true)
                case .once:
                    onceControls
                case .advanced:
                    advancedControls
                }
            }
            .padding(Design.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)

            previewLine
            if draft.usesHostClock {
                hostClockCaveat
            }
        }
    }

    // MARK: Controls

    private var intervalControls: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Stepper(value: $draft.intervalValue, in: 1 ... 999) {
                Text("Every \(draft.intervalValue) \(draft.intervalUnit.label(for: draft.intervalValue))")
                    .font(Design.Typography.body(14))
                    .foregroundStyle(Design.Colors.foreground)
            }
            unitPicker
        }
    }

    private var unitPicker: some View {
        Picker("Unit", selection: $draft.intervalUnit) {
            ForEach(ScheduleDraft.IntervalUnit.allCases) { unit in
                Text(unit.label(for: 2).capitalized).tag(unit)
            }
        }
        .pickerStyle(.segmented)
    }

    private func timeControls(showWeekday: Bool) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            if showWeekday {
                Picker("Weekday", selection: $draft.weekday) {
                    ForEach(ScheduleDraft.Weekday.allCases) { day in
                        Text(day.name).tag(day)
                    }
                }
                .pickerStyle(.menu)
                .tint(Design.Brand.accent)
            }
            DatePicker("At", selection: timeOfDayBinding, displayedComponents: .hourAndMinute)
                .font(Design.Typography.body(14))
                .foregroundStyle(Design.Colors.foreground)
                .tint(Design.Brand.accent)
        }
    }

    private var onceControls: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Picker("When", selection: $draft.onceIsRelative) {
                Text("From now").tag(true)
                Text("At a time").tag(false)
            }
            .pickerStyle(.segmented)

            if draft.onceIsRelative {
                Stepper(value: $draft.intervalValue, in: 1 ... 999) {
                    Text("In \(draft.intervalValue) \(draft.intervalUnit.label(for: draft.intervalValue))")
                        .font(Design.Typography.body(14))
                        .foregroundStyle(Design.Colors.foreground)
                }
                unitPicker
            } else {
                DatePicker(
                    "Run at",
                    selection: $draft.onceDate,
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(Design.Typography.body(14))
                .foregroundStyle(Design.Colors.foreground)
                .tint(Design.Brand.accent)
            }
        }
    }

    private var advancedControls: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            TextField("", text: $draft.advancedText,
                      prompt: Text("0 9 * * *  ·  every 30m  ·  2026-02-03T14:00")
                          .foregroundStyle(Design.Colors.dimForeground))
                .font(Design.Typography.mono(12))
                .foregroundStyle(Design.Colors.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(height: 36)
            MonoLabel("SENT AS-IS — THE HERMES HOST VALIDATES ON SAVE", size: 8,
                      tracking: Design.Tracking.mono, color: Design.Colors.dimForeground)
        }
    }

    // MARK: Preview + caveats

    /// Presets: humanized from our own inputs. Advanced: honest silence —
    /// no client cron parser; the server's `schedule_display` is the
    /// authority after save (D4 preview rule).
    @ViewBuilder
    private var previewLine: some View {
        if let preview = draft.localizedPreview {
            HStack(spacing: Design.Spacing.xs) {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(Design.Brand.accent)
                Text(preview)
                    .font(Design.Typography.body(13))
                    .foregroundStyle(Design.Colors.coolForeground)
            }
        }
    }

    /// No endpoint exposes the host's timezone (verified against 0.19.0) —
    /// so say whose clock it is instead of pretending they match (#156a
    /// timezone footgun).
    private var hostClockCaveat: some View {
        HStack(alignment: .top, spacing: Design.Spacing.xs) {
            Image(systemName: "globe.badge.chevron.backward")
                .font(.system(size: 11))
                .foregroundStyle(Design.Brand.forge)
            Text("Times run on the Hermes host's clock, in its configured timezone — not this device's. If the host is in another timezone, the hour differs.")
                .font(Design.Typography.body(12))
                .foregroundStyle(Design.Colors.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var timeOfDayBinding: Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                return calendar.date(
                    bySettingHour: draft.hour, minute: draft.minute, second: 0, of: Date()
                ) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                draft.hour = components.hour ?? 9
                draft.minute = components.minute ?? 0
            }
        )
    }
}
