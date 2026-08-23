import SwiftUI

// MARK: - #257 lever 3a: the capability surface
//
// A registry-rendered "what Talaria can do" sheet — per-TOOL detail
// (semantic description, permissions, risk class), grouped by family.
// Reachable from the fresh-chat empty-state chip and the `/capabilities`
// slash command (bar 257-3a-B: ≤2 taps from a fresh chat).
//
// **No hand-written tool or family list exists here** (bar 257-3a-A). The
// rows are `CapabilityDescriptor`s built from the LIVE belt by
// `CapabilityRegistry(belt:)`, and the sections derive from
// `CapabilityGroup.allCases` — #257's root cause was a hand-written
// capability list that drifted, and the UI door is pinned shut against its
// re-entry by `CapabilitySurfaceTests`.

struct CapabilitiesSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Live descriptors, built by the presenting screen from the belt.
    /// The registry is the ONLY source; this view stores no copy of it.
    let descriptors: [CapabilityDescriptor]

    /// Declaration-ordered sections, derived — pure and static so bar
    /// 257-3a-A's unit test pins the derivation against the real belt.
    ///
    /// Groups with no live tool render nothing (real data only) — **except a
    /// family that DECLARES an `availabilityCaveat`** (bar 257-V-C). Those
    /// families are conditional by construction: `.vision`'s tools come off
    /// the belt on any turn with no attachment (#176), so dropping the
    /// section for an absent tool is what made image reading undiscoverable
    /// — the thing Owen's 2026-08-10 ruling flips. The caveat label rides
    /// the section and says when the tools are there, so the section is a
    /// caveated statement rather than an overpromise; that a caveated
    /// family's tools exist in the app AT ALL stays pinned by
    /// `everyGroupMapsToAtLeastOneToolAndEveryToolToExactlyOneGroup`.
    ///
    /// An EMPTY registry still derives to nothing, so the honest
    /// "registry unavailable" state below survives.
    nonisolated static func sections(
        from descriptors: [CapabilityDescriptor]
    ) -> [(group: CapabilityGroup, tools: [CapabilityDescriptor])] {
        guard !descriptors.isEmpty else { return [] }
        return CapabilityGroup.allCases.compactMap { group in
            let tools = descriptors
                .filter { $0.group == group }
                .sorted { $0.id < $1.id }
            if tools.isEmpty, group.availabilityCaveat == nil { return nil }
            return (group, tools)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { HUDScreenBackground().ignoresSafeArea() }
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
                Text("CAPABILITIES")
                    .font(Design.Typography.display(22, weight: .semibold, relativeTo: .title2))
                    .tracking(Design.Tracking.display)
                    .foregroundStyle(Design.Colors.foregroundBright)
                MonoLabel("EVERYTHING TALARIA CAN REACH ON THIS IPHONE",
                          size: 10, tracking: Design.Tracking.monoWide)
            }
            Spacer()
            Button { dismiss() } label: {
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
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close capabilities")
            .accessibilityIdentifier("capabilities.close")
        }
        .padding(.horizontal, Design.Spacing.lg)
        .padding(.top, Design.Spacing.xl)
        .padding(.bottom, Design.Spacing.md)
    }

    // MARK: Sections

    @ViewBuilder
    private var content: some View {
        let sections = Self.sections(from: descriptors)
        if sections.isEmpty {
            // Honest empty state (real data only): the belt has not been
            // installed, so there is nothing to enumerate — never a mock.
            MonoLabel("CAPABILITY REGISTRY UNAVAILABLE", size: 10,
                      tracking: Design.Tracking.monoWide,
                      color: Design.Colors.mutedForeground)
                .frame(maxWidth: .infinity)
                .padding(.top, Design.Spacing.xl)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Design.Spacing.md) {
                    ForEach(sections, id: \.group) { section in
                        sectionView(section.group, tools: section.tools)
                    }
                }
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.xs)
                .padding(.bottom, Design.Spacing.xl)
            }
        }
    }

    private func sectionView(_ group: CapabilityGroup,
                             tools: [CapabilityDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel(group.capabilityAnswerTitle, size: 10,
                      weight: .medium, tracking: Design.Tracking.monoXWide,
                      color: Design.Brand.accentText)
            // The family's one-line detail — the SAME registry copy the
            // capability answer block renders (one source, #202D). Plain
            // caption Text: MonoLabel force-uppercases, wrong for a sentence.
            Text(group.capabilityAnswerDetail)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
            if let caveat = group.availabilityCaveat {
                // #176: the image tools arm only when a photo rides the
                // conversation — say so rather than overpromise. The string
                // is the registry's, NOT a literal: the capability block
                // renders the same one, so the two surfaces cannot drift
                // (bar 257-V-B, #202D). `MonoLabel` uppercases it.
                MonoLabel(caveat, size: 8,
                          tracking: Design.Tracking.monoWide,
                          color: Design.Colors.dimForeground)
            }
            ForEach(tools, id: \.id) { descriptor in
                toolRow(descriptor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing.md)
        .hudPanel(cornerRadius: Design.CornerRadius.md, borderColor: Design.Colors.hairline)
    }

    private func toolRow(_ descriptor: CapabilityDescriptor) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xxs) {
            HStack(spacing: Design.Spacing.xs) {
                // The tool's REAL name, case preserved — MonoLabel would
                // uppercase "readHealth" into "READHEALTH", which stops
                // being the identifier the registry (and the belt) carry.
                Text(descriptor.id)
                    .font(Design.Typography.mono(10, weight: .medium))
                    .tracking(Design.Tracking.mono)
                    .foregroundStyle(Design.Colors.foregroundBright)
                Spacer()
                riskPill(descriptor.riskClass)
            }
            Text(descriptor.semanticDescription)
                .font(Design.Typography.caption)
                .foregroundStyle(Design.Colors.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
            if !descriptor.permissions.isEmpty {
                MonoLabel("NEEDS: \(descriptor.permissions.joined(separator: " · ").uppercased())",
                          size: 8, tracking: Design.Tracking.mono,
                          color: Design.Colors.dimForeground)
            }
        }
        .padding(.top, Design.Spacing.xxs)
    }

    /// Risk copy from the registry's own semantics: `.write` means
    /// confirmation-gated — every action tool shows the confirm card first.
    private func riskPill(_ riskClass: CapabilityRiskClass) -> some View {
        MonoLabel(riskClass == .write ? "ASKS FIRST" : "READ-ONLY",
                  size: 8, tracking: Design.Tracking.monoWide,
                  color: riskClass == .write ? Design.Brand.forgeText : Design.Colors.dimForeground)
    }
}
