import Foundation
import FoundationModels

// MARK: - Generative UI IR v0 (P8 rung 1)
//
// The model never emits UI code — it emits THIS: a constrained, tree-shaped
// Intermediate Representation whose node vocabulary is exactly the shipped HUD
// component set (Core/HUD). A hand-built renderer (`GenUISurfaceView`) maps IR
// nodes onto those real components, so generated UI cannot draw anything that
// isn't already pre-approved, theme-resolved, and reduce-motion-aware.
//
// The tree is depth-bounded by construction — surface → block (card/stack/row)
// → item (leaf, or one row of leaves) → leaf — rather than recursive. That is
// deliberate: recursive `@Generable` schemas are unverified against the shipped
// macro, and a hard nesting ceiling constrains generation further, which is the
// whole point of v0.
//
// Idiom (mirrors Services/Live/DeviceTools):
//  • Empty string means "not set" — the established sentinel; no Optionals.
//  • No default property values — plain `var`s are the macro's verified surface.
//  • Types are top-level, not `private` nested (the Wave 3 macro-visibility lesson).
//
// Ingestion contract: every surface — tolerant-decoded (`GenUIDecoder`) or, in a
// later rung, strict-decoded from guided generation — passes through
// `sanitized()` before rendering, so off-contract nodes are skipped and logged
// exactly once, at the ingestion funnel, never inside a view body.

// MARK: - Node vocabulary

/// The pre-approved node vocabulary. Every case maps 1:1 onto a shipped HUD
/// component (or a SwiftUI layout primitive, for `row`/`spacer`). There is no
/// other visual output.
@Generable(description: "The kind of UI node. row lays child leaves out horizontally and is the only kind with children; every other kind is a leaf component.")
enum GenUINodeKind {
    /// Horizontal group of leaves. Valid at item level only; rows cannot nest.
    case row
    /// `MonoLabel` — uppercase tracked mono telemetry label.
    case label
    /// Body text (Space Grotesk, `Design.Typography.body`).
    case text
    /// `StatusPip` — small glowing status dot.
    case pip
    /// `GlowButton` — primary CTA; sends `prompt` when tapped.
    case glowButton
    /// `GhostButton` — low-emphasis button; sends `prompt` when tapped.
    case ghostButton
    /// `ReactorOrb` — decorative reactor orb (small/minimal, medium/standard,
    /// large/onboarding presets).
    case orb
    /// Hairline rule (`Design.Colors.hairline`, 1pt).
    case divider
    /// Flexible spacer (`Spacer`) — pushes row content apart.
    case spacer
}

/// Container style for a top-level block.
@Generable(description: "Container style for one block of the surface.")
enum GenUIBlockKind {
    /// Bordered translucent HUD panel (`.hudPanel`) with padded content.
    case card
    /// Plain vertical stack, no panel chrome.
    case stack
    /// Horizontal row.
    case row
}

/// Theme-resolved color tone. Maps onto `Design.Brand.*` / `Design.Colors.*`
/// tokens at render time, so generated UI re-skins with the active theme like
/// every other surface.
@Generable(description: "Color tone from the app theme. standard is the node's default color; accent, warning, and danger are status colors.")
enum GenUITone {
    case standard
    case bright
    case muted
    case dim
    case accent
    case warning
    case danger
}

/// Size step. Each node kind maps the step onto its real preset sizes at
/// render time (e.g. orb small/medium/large = the 26/42/74pt app presets).
@Generable(description: "Size step for the node. medium is the default look for every kind.")
enum GenUISize {
    case small
    case medium
    case large
}

// MARK: - Tree

/// Root of a generated surface: a vertical sequence of blocks.
@Generable(description: "A generated HUD surface: a top-to-bottom sequence of blocks rendered with the app's shipped HUD components.")
struct GenUISurface {
    @Guide(description: "The blocks of the surface, top to bottom.")
    var blocks: [GenUIBlock]
}

/// One top-level container.
@Generable(description: "One container block of the surface.")
struct GenUIBlock {
    @Guide(description: "Container style. card is a bordered HUD panel; stack is a plain vertical group; row is a horizontal group.")
    var kind: GenUIBlockKind
    @Guide(description: "True to frame a card with corner brackets (targeting-frame motif). Ignored for stack and row.")
    var framed: Bool
    @Guide(description: "The block's content nodes, in order.")
    var children: [GenUIItem]
}

/// One node inside a block: a leaf component, or a single horizontal row of
/// leaves. `children` is only meaningful for `kind == .row`; the remaining
/// fields are the leaf payload and are only meaningful for leaf kinds.
@Generable(description: "One node inside a block: a leaf component, or one horizontal row of leaves. Rows cannot nest.")
struct GenUIItem {
    @Guide(description: "The node kind. row lays children out horizontally; every other kind is a leaf and ignores children.")
    var kind: GenUINodeKind
    @Guide(description: "Child leaves for kind row, in order. Empty for every other kind.")
    var children: [GenUILeaf]
    @Guide(description: "Text content: the label or text string, or the button title. Empty for kinds without text.")
    var text: String
    @Guide(description: "Color tone. standard uses the node's default theme color.")
    var tone: GenUITone
    @Guide(description: "Size step. medium is the default.")
    var size: GenUISize
    @Guide(description: "For pip only: true makes the status pip blink.")
    var blinks: Bool
    @Guide(description: "For buttons only: the prompt message sent to the assistant when the button is tapped. A button with an empty prompt or empty text is dropped.")
    var prompt: String
}

/// A leaf component node (no children by construction — this is what bounds
/// the tree depth).
@Generable(description: "A leaf HUD component node.")
struct GenUILeaf {
    @Guide(description: "The leaf kind. row is not valid here — rows cannot nest.")
    var kind: GenUINodeKind
    @Guide(description: "Text content: the label or text string, or the button title. Empty for kinds without text.")
    var text: String
    @Guide(description: "Color tone. standard uses the node's default theme color.")
    var tone: GenUITone
    @Guide(description: "Size step. medium is the default.")
    var size: GenUISize
    @Guide(description: "For pip only: true makes the status pip blink.")
    var blinks: Bool
    @Guide(description: "For buttons only: the prompt message sent to the assistant when the button is tapped. A button with an empty prompt or empty text is dropped.")
    var prompt: String
}

// MARK: - Renderer support

extension GenUIItem {
    /// The item's leaf payload, for leaf kinds. (`kind == .row` items render
    /// their `children` instead and never consult this.)
    var leafPayload: GenUILeaf {
        GenUILeaf(kind: kind, text: text, tone: tone, size: size, blinks: blinks, prompt: prompt)
    }
}

extension GenUILeaf {
    /// A button is renderable only when it has both a visible title and a
    /// non-empty prompt to send — a button that does nothing is dishonest UI.
    var isRenderableButton: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Sanitation (skip-and-log, never crash)
//
// Rendering policy for off-contract nodes, applied at the ingestion funnel so
// the renderer itself stays a total, side-effect-free mapping:
//  • a `row` in leaf position is dropped (rows cannot nest),
//  • a `row` item with no surviving leaves is dropped,
//  • a button missing its title or prompt is dropped,
//  • a block left with no children is dropped.
// Every drop emits one always-on `TalariaLog.event` line — off-contract model
// output is something we want visible in Console.app, not swallowed.

extension GenUISurface {
    /// Returns the surface with every off-contract node skipped (and logged).
    func sanitized() -> GenUISurface {
        var result = self
        result.blocks = blocks.compactMap { block in
            var block = block
            block.children = block.children.compactMap { $0.sanitizedItem() }
            guard !block.children.isEmpty else {
                TalariaLog.event("GenUI: dropped \(block.kind) block with no renderable children")
                return nil
            }
            return block
        }
        return result
    }
}

private extension GenUIItem {
    func sanitizedItem() -> GenUIItem? {
        if kind == .row {
            var row = self
            row.children = children.compactMap { $0.sanitizedLeaf() }
            guard !row.children.isEmpty else {
                TalariaLog.event("GenUI: dropped row with no renderable leaves")
                return nil
            }
            return row
        }
        guard let leaf = leafPayload.sanitizedLeaf() else { return nil }
        // Fold any sanitizer normalization back into the item's leaf fields.
        return GenUIItem(kind: leaf.kind, children: [], text: leaf.text, tone: leaf.tone,
                         size: leaf.size, blinks: leaf.blinks, prompt: leaf.prompt)
    }
}

private extension GenUILeaf {
    func sanitizedLeaf() -> GenUILeaf? {
        guard kind != .row else {
            TalariaLog.event("GenUI: dropped nested row — rows cannot nest")
            return nil
        }
        if (kind == .glowButton || kind == .ghostButton) && !isRenderableButton {
            TalariaLog.event("GenUI: dropped \(kind) without a title and prompt")
            return nil
        }
        return self
    }
}
