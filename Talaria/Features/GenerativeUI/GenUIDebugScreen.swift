#if DEBUG
import SwiftUI

// MARK: - IR v0 debug harness (DEBUG builds only)
//
// Eyeball surface for the IR renderer: three hardcoded IR trees — one built in
// Swift, one decoded from well-formed JSON on device, and one decoded from
// deliberately mangled JSON so the skip-and-log tolerance is visible (the
// dropped nodes also log to Console.app under the org.aethyrion.talaria
// subsystem). Reached from Settings → System → Developer; the whole file is
// compiled out of Release, so nothing here ships to a user surface (v0 has no
// chat wiring by design).
//
// The interaction primitive is staged honestly: tapping a generated button
// writes its prompt string to the readout below — it is NOT sent anywhere.

struct GenUIDebugScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lastPrompt: String?

    var body: some View {
        ZStack {
            HUDScreenBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Spacing.lg) {
                    SettingsScreenHeader(title: "Gen UI", subtitle: "IR v0 Harness · Debug Only") { dismiss() }

                    promptReadout

                    sample("// 01 · Status card — Swift-built tree",
                           surface: GenUIDebugSamples.statusCard)
                    sample("// 02 · Actions — decoded from JSON on device",
                           surface: GenUIDebugSamples.decodedActions)
                    sample("// 03 · Mangled JSON — survivors only (drops log to Console)",
                           surface: GenUIDebugSamples.decodedSurvivors)
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.sm)
            }
        }
        .navigationTitle("Gen UI")
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    // MARK: Prompt readout (the staged interaction primitive)

    private var promptReadout: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.xs) {
            MonoLabel("Last button prompt", size: 10, tracking: Design.Tracking.monoWide,
                      color: Design.Colors.mutedForeground)
            Text(lastPrompt ?? "—")
                .font(Design.Typography.body(14))
                .foregroundStyle(lastPrompt == nil ? Design.Colors.mutedForeground : Design.Brand.accentBright)
                .fixedSize(horizontal: false, vertical: true)
            MonoLabel("Staged only — v0 sends nothing", size: 8, tracking: Design.Tracking.mono,
                      color: Design.Colors.dimForeground)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hudPanel(
            borderColor: Design.Colors.accentTint(0.12),
            fill: Design.Colors.background.opacity(0.5)
        )
    }

    // MARK: Sample section

    private func sample(_ title: String, surface: GenUISurface?) -> some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            MonoLabel(title, size: 10, tracking: Design.Tracking.mono,
                      color: Design.Colors.mutedForeground)
            if let surface {
                GenUISurfaceView(surface: surface) { prompt in
                    withAnimation(Design.Motion.quickResponse) { lastPrompt = prompt }
                }
            } else {
                // Real data only: if a sample fails to decode, say so.
                MonoLabel("Decode failed — see Console", size: 10,
                          tracking: Design.Tracking.mono, color: Design.Colors.danger)
            }
        }
    }
}

// MARK: - Hardcoded sample trees

enum GenUIDebugSamples {

    /// 01 — framed status card built directly in Swift (no decoder involved):
    /// exercises card/framed, label, divider, rows, pips, tones, orb, buttons.
    static var statusCard: GenUISurface {
        GenUISurface(blocks: [
            GenUIBlock(kind: .card, framed: true, children: [
                GenUIItem(kind: .label, children: [], text: "// agent status", tone: .muted,
                          size: .small, blinks: false, prompt: ""),
                GenUIItem(kind: .divider, children: [], text: "", tone: .standard,
                          size: .medium, blinks: false, prompt: ""),
                GenUIItem(kind: .row, children: [
                    GenUILeaf(kind: .orb, text: "", tone: .standard, size: .medium,
                              blinks: false, prompt: ""),
                    GenUILeaf(kind: .text, text: "Relay link nominal", tone: .bright,
                              size: .medium, blinks: false, prompt: ""),
                    GenUILeaf(kind: .spacer, text: "", tone: .standard, size: .medium,
                              blinks: false, prompt: ""),
                    GenUILeaf(kind: .pip, text: "", tone: .accent, size: .medium,
                              blinks: false, prompt: ""),
                ], text: "", tone: .standard, size: .medium, blinks: false, prompt: ""),
                GenUIItem(kind: .row, children: [
                    GenUILeaf(kind: .pip, text: "", tone: .warning, size: .small,
                              blinks: true, prompt: ""),
                    GenUILeaf(kind: .text, text: "Gateway session pin degraded", tone: .warning,
                              size: .small, blinks: false, prompt: ""),
                ], text: "", tone: .standard, size: .medium, blinks: false, prompt: ""),
                GenUIItem(kind: .glowButton, children: [], text: "Re-pin session", tone: .standard,
                          size: .medium, blinks: false, prompt: "Re-pin the gateway model session."),
            ]),
        ]).sanitized()
    }

    /// 02 — decoded from well-formed IR JSON at runtime, proving the tolerant
    /// ingestion path end-to-end on device.
    static var decodedActions: GenUISurface? {
        GenUIDecoder.surface(fromJSON: """
        {
          "blocks": [
            { "kind": "stack", "children": [
              { "kind": "label", "text": "// quick actions", "tone": "muted", "size": "small" },
              { "kind": "text", "text": "Generated from JSON on this device." }
            ] },
            { "kind": "row", "children": [
              { "kind": "ghostButton", "text": "Summarize", "prompt": "Summarize this conversation.", "size": "small" },
              { "kind": "ghostButton", "text": "Next steps", "prompt": "List the next steps.", "size": "small" }
            ] },
            { "kind": "card", "children": [
              { "kind": "row", "children": [
                { "kind": "pip", "tone": "accent" },
                { "kind": "label", "text": "ir v0 · decoder path", "size": "small" },
                { "kind": "spacer" },
                { "kind": "orb", "size": "small" }
              ] }
            ] }
          ]
        }
        """)
    }

    /// 03 — deliberately mangled IR: unknown kinds, a nested row, a promptless
    /// button, wrong-typed fields. What renders is exactly the survivors; every
    /// drop logs one line to Console.app.
    static var decodedSurvivors: GenUISurface? {
        GenUIDecoder.surface(fromJSON: """
        {
          "blocks": [
            { "kind": "hologram", "children": [ { "kind": "text", "text": "never shown" } ] },
            { "kind": "card", "framed": "not-a-bool", "children": [
              { "kind": "label", "text": "// survivors", "tone": "warning", "size": "small" },
              { "kind": "chart", "text": "unknown leaf, dropped" },
              { "kind": "row", "children": [
                { "kind": "row", "text": "nested row, dropped" },
                { "kind": "pip", "tone": "danger", "blinks": true },
                { "kind": "text", "text": "3 nodes were dropped around me", "tone": "danger", "size": "small" }
              ] },
              { "kind": "glowButton", "text": "Promptless — dropped" },
              { "kind": "ghostButton", "text": "I survived", "prompt": "Report which IR nodes were dropped." }
            ] }
          ]
        }
        """)
    }
}
#endif
