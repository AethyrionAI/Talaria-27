import SwiftUI

// MARK: - IR v0 renderer (P8 rung 1)
//
// Hand-built, hardcoded mapping from the IR tree onto the shipped HUD
// components — a recursive-in-shape (but depth-bounded, like the IR itself)
// switch over node kinds. No dynamic view synthesis, no AnyView. The renderer
// is a total function: it renders *something* (possibly nothing) for every
// tree and never crashes; off-contract nodes were already skipped and logged
// by `sanitized()` at ingestion, so the defensive `EmptyView` arms here are
// silent by design (no side effects in `body`).
//
// The one interaction primitive: buttons call `onPrompt` with the node's
// prompt string. Wiring that string into a chat send is a later rung —
// nothing here touches the chat flow.

/// Renders a sanitized `GenUISurface` with the shipped HUD components.
struct GenUISurfaceView: View {
    let surface: GenUISurface
    var onPrompt: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            ForEach(Array(surface.blocks.enumerated()), id: \.offset) { _, block in
                GenUIBlockView(block: block, onPrompt: onPrompt)
            }
        }
    }
}

// MARK: - Block (container)

private struct GenUIBlockView: View {
    let block: GenUIBlock
    let onPrompt: (String) -> Void

    var body: some View {
        switch block.kind {
        case .card:
            VStack(alignment: .leading, spacing: Design.Spacing.sm) { items }
                .padding(Design.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hudPanel()
                .overlay {
                    if block.framed { CornerBrackets() }
                }
        case .stack:
            VStack(alignment: .leading, spacing: Design.Spacing.sm) { items }
        case .row:
            HStack(spacing: Design.Spacing.sm) { items }
        }
    }

    private var items: some View {
        ForEach(Array(block.children.enumerated()), id: \.offset) { _, item in
            GenUIItemView(item: item, onPrompt: onPrompt)
        }
    }
}

// MARK: - Item (leaf, or one row of leaves)

private struct GenUIItemView: View {
    let item: GenUIItem
    let onPrompt: (String) -> Void

    var body: some View {
        switch item.kind {
        case .row:
            HStack(spacing: Design.Spacing.sm) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { _, leaf in
                    GenUILeafView(leaf: leaf, onPrompt: onPrompt)
                }
            }
        default:
            GenUILeafView(leaf: item.leafPayload, onPrompt: onPrompt)
        }
    }
}

// MARK: - Leaf (the HUD components)

private struct GenUILeafView: View {
    let leaf: GenUILeaf
    let onPrompt: (String) -> Void

    var body: some View {
        switch leaf.kind {
        case .label:
            MonoLabel(leaf.text, size: labelSize, color: toneColor(default: Design.Colors.mutedForeground))

        case .text:
            Text(leaf.text)
                .font(Design.Typography.body(textSize))
                .foregroundStyle(toneColor(default: Design.Colors.foreground))
                .fixedSize(horizontal: false, vertical: true)

        case .pip:
            StatusPip(
                color: toneColor(default: Design.Brand.accent),
                diameter: pipDiameter,
                blinks: leaf.blinks
            )

        case .glowButton:
            if leaf.isRenderableButton {
                GlowButton(title: leaf.text, height: buttonHeight) { onPrompt(leaf.prompt) }
            }

        case .ghostButton:
            if leaf.isRenderableButton {
                GhostButton(title: leaf.text, height: buttonHeight) { onPrompt(leaf.prompt) }
            }

        case .orb:
            ReactorOrb(size: orbSize, style: orbStyle)

        case .divider:
            Rectangle()
                .fill(Design.Colors.hairline)
                .frame(height: 1)

        case .spacer:
            Spacer(minLength: 0)

        case .row:
            // Off-contract in leaf position; sanitized() drops and logs these
            // upstream. Kept total so an unsanitized tree still can't crash.
            EmptyView()
        }
    }

    // MARK: Tone → theme tokens

    private func toneColor(default defaultColor: Color) -> Color {
        switch leaf.tone {
        case .standard: defaultColor
        case .bright: Design.Colors.foregroundBright
        case .muted: Design.Colors.mutedForeground
        case .dim: Design.Colors.dimForeground
        case .accent: Design.Brand.accent
        case .warning: Design.Brand.forge
        case .danger: Design.Colors.danger
        }
    }

    // MARK: Size step → real component presets

    private var labelSize: CGFloat {
        switch leaf.size {
        case .small: 9
        case .medium: 10   // MonoLabel's own default
        case .large: 12
        }
    }

    private var textSize: CGFloat {
        switch leaf.size {
        case .small: 13    // footnote
        case .medium: 16   // body
        case .large: 20
        }
    }

    private var pipDiameter: CGFloat {
        switch leaf.size {
        case .small: 5
        case .medium: 7    // StatusPip's own default
        case .large: 9
        }
    }

    private var buttonHeight: CGFloat {
        switch leaf.size {
        case .small: Design.Size.minTapTarget   // 44 — never below the tap floor
        case .medium: 48                        // GhostButton's own default
        case .large: 56                         // GlowButton's own default
        }
    }

    private var orbSize: CGFloat {
        switch leaf.size {
        case .small: Design.Size.orbAvatar        // 26
        case .medium: Design.Size.orbPanel        // 42
        case .large: Design.Size.orbOnboarding    // 74
        }
    }

    /// Each size step uses the orb style the app really ships at that size.
    private var orbStyle: ReactorOrb.Style {
        switch leaf.size {
        case .small: .minimal
        case .medium: .standard
        case .large: .onboarding
        }
    }
}
