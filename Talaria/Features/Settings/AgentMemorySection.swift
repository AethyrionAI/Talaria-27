import SwiftUI

/// #378 (156c) — the read-only agent-memory panel.
///
/// It renders whatever `HermesMemoryReader` could see and nothing else. Every
/// sentence it shows comes from `HermesMemoryReader.Result`'s own
/// `headline`/`detail`, so the four outcomes are unit-pinned rather than
/// composed here — see that type for why "cannot reach" and "nothing found"
/// must never collapse into one message.
///
/// **Why this lives on the Developer channel and not in the main settings
/// deck.** Under the ruled scope (local `~/.hermes/memories/*.md`, read-only,
/// no new dependency) there is nothing for a device user to look at: those
/// files are on the Hermes host's filesystem and a phone has no path to it. A
/// user-facing panel would be a permanently empty screen with an explanation
/// attached. Lifting that needs a routing decision — plugin delivery or Honcho
/// — that has not been made.
struct AgentMemorySection: View {

    /// Injected so the whole panel is previewable and testable against a temp
    /// directory; production passes the ruled path.
    var directory: URL? = HermesMemoryReader.localMemoriesDirectory

    @State private var result: HermesMemoryReader.Result?
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel("// Agent memory", size: 10, tracking: Design.Tracking.monoXWide,
                      color: Design.Colors.mutedForeground)

            VStack(alignment: .leading, spacing: Design.Spacing.sm) {
                if let result {
                    header(result)
                    if result.showsSourceCaveat {
                        MonoLabel(HermesMemoryReader.sourceCaveat, size: 9,
                                  tracking: Design.Tracking.mono,
                                  color: Design.Brand.forgeText)
                    }
                    if case .loaded(_, let files) = result {
                        ForEach(files) { file in fileRow(file) }
                    }
                } else {
                    MonoLabel("READING…", size: 10, tracking: Design.Tracking.mono,
                              color: Design.Colors.mutedForeground)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Spacing.md)
            .background(Design.Colors.background,
                        in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(Design.Colors.accentTint(0.14), lineWidth: 1)
            }
        }
        .task { result = HermesMemoryReader.read(directory: directory) }
    }

    @ViewBuilder
    private func header(_ result: HermesMemoryReader.Result) -> some View {
        MonoLabel(result.headline, size: 11, weight: .medium,
                  tracking: Design.Tracking.mono, color: Design.Colors.coolForeground)
        Text(result.detail)
            .font(Design.Typography.caption)
            .foregroundStyle(Design.Colors.mutedForeground)
            .textSelection(.enabled)
    }

    @ViewBuilder
    private func fileRow(_ file: HermesMemoryReader.File) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            Button {
                if expanded.contains(file.name) { expanded.remove(file.name) }
                else { expanded.insert(file.name) }
            } label: {
                HStack {
                    MonoLabel(file.name, size: 10, tracking: Design.Tracking.mono,
                              color: Design.Colors.foregroundBright)
                    Spacer()
                    MonoLabel("\(file.entries.count) · \(file.characterCount) CH", size: 9,
                              tracking: Design.Tracking.mono,
                              color: Design.Colors.mutedForeground)
                }
            }
            if expanded.contains(file.name) {
                ForEach(Array(file.entries.enumerated()), id: \.offset) { _, entry in
                    Text(entry)
                        .font(Design.Typography.caption)
                        .foregroundStyle(Design.Colors.mutedForeground)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, Design.Spacing.xs)
    }
}
