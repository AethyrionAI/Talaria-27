import Foundation
import SwiftUI
import Testing
@testable import Talaria

/// IR v0 invariants (P8 rung 1): tolerant JSON ingestion produces the expected
/// tree, off-contract nodes are skipped without taking siblings down, the
/// sanitizer enforces the rules the schema can't express, and the renderer
/// never crashes on any decoded tree.
struct GenUISchemaTests {

    // MARK: - Well-formed decoding

    @Test func decodesWellFormedSurface() throws {
        let json = """
        {
          "blocks": [
            {
              "kind": "card",
              "framed": true,
              "children": [
                { "kind": "label", "text": "// agent status", "tone": "muted", "size": "small" },
                { "kind": "divider" },
                {
                  "kind": "row",
                  "children": [
                    { "kind": "pip", "tone": "warning", "blinks": true },
                    { "kind": "text", "text": "Gateway pin degraded", "tone": "warning" },
                    { "kind": "spacer" },
                    { "kind": "orb", "size": "small" }
                  ]
                },
                { "kind": "glowButton", "text": "Retry", "prompt": "Retry the gateway pin.", "size": "large" }
              ]
            },
            {
              "kind": "row",
              "children": [
                { "kind": "ghostButton", "text": "Details", "prompt": "Show relay details." }
              ]
            }
          ]
        }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        try #require(surface.blocks.count == 2)

        let card = surface.blocks[0]
        #expect(card.kind == .card)
        #expect(card.framed)
        try #require(card.children.count == 4)

        let label = card.children[0]
        #expect(label.kind == .label)
        #expect(label.text == "// agent status")
        #expect(label.tone == .muted)
        #expect(label.size == .small)

        #expect(card.children[1].kind == .divider)

        let row = card.children[2]
        #expect(row.kind == .row)
        try #require(row.children.count == 4)
        #expect(row.children[0].kind == .pip)
        #expect(row.children[0].tone == .warning)
        #expect(row.children[0].blinks)
        #expect(row.children[1].kind == .text)
        #expect(row.children[1].text == "Gateway pin degraded")
        #expect(row.children[2].kind == .spacer)
        #expect(row.children[3].kind == .orb)
        #expect(row.children[3].size == .small)

        let button = card.children[3]
        #expect(button.kind == .glowButton)
        #expect(button.text == "Retry")
        #expect(button.prompt == "Retry the gateway pin.")
        #expect(button.size == .large)

        let bottomRow = surface.blocks[1]
        #expect(bottomRow.kind == .row)
        #expect(bottomRow.children.count == 1)
        #expect(bottomRow.children[0].kind == .ghostButton)
    }

    @Test func acceptsBareArrayRoot() throws {
        let json = """
        [ { "kind": "stack", "children": [ { "kind": "text", "text": "hello" } ] } ]
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        try #require(surface.blocks.count == 1)
        #expect(surface.blocks[0].kind == .stack)
        #expect(surface.blocks[0].children[0].text == "hello")
    }

    @Test func missingFieldsGetDefaults() throws {
        let json = """
        { "blocks": [ { "kind": "stack", "children": [ { "kind": "label", "text": "x" } ] } ] }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        let block = surface.blocks[0]
        #expect(!block.framed)
        let leaf = block.children[0]
        #expect(leaf.tone == .standard)
        #expect(leaf.size == .medium)
        #expect(!leaf.blinks)
        #expect(leaf.prompt.isEmpty)
    }

    // MARK: - Skip-and-log: unknown and malformed nodes

    @Test func unknownBlockKindIsSkippedAndSiblingsSurvive() throws {
        let json = """
        { "blocks": [
          { "kind": "stack", "children": [ { "kind": "text", "text": "first" } ] },
          { "kind": "hologram", "children": [ { "kind": "text", "text": "never" } ] },
          { "kind": "stack", "children": [ { "kind": "text", "text": "last" } ] }
        ] }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        try #require(surface.blocks.count == 2)
        #expect(surface.blocks[0].children[0].text == "first")
        #expect(surface.blocks[1].children[0].text == "last")
    }

    @Test func unknownLeafKindIsSkippedAndSiblingsSurvive() throws {
        let json = """
        { "blocks": [ { "kind": "card", "children": [
          { "kind": "text", "text": "keep" },
          { "kind": "chart", "text": "drop" },
          { "kind": "text", "text": "also keep" }
        ] } ] }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        let children = surface.blocks[0].children
        try #require(children.count == 2)
        #expect(children[0].text == "keep")
        #expect(children[1].text == "also keep")
    }

    @Test func nonObjectNodesAreSkipped() throws {
        let json = """
        { "blocks": [
          "not a block",
          { "kind": "stack", "children": [ 42, { "kind": "text", "text": "kept" } ] }
        ] }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        try #require(surface.blocks.count == 1)
        #expect(surface.blocks[0].children.count == 1)
        #expect(surface.blocks[0].children[0].text == "kept")
    }

    @Test func wrongFieldTypesFallBackToDefaults() throws {
        let json = """
        { "blocks": [ { "kind": "card", "framed": "yes", "children": [
          { "kind": "pip", "blinks": 1, "text": 42, "tone": [], "size": {} }
        ] } ] }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        let block = surface.blocks[0]
        #expect(!block.framed)
        let pip = block.children[0]
        #expect(pip.kind == .pip)
        #expect(!pip.blinks)
        #expect(pip.text.isEmpty)
        #expect(pip.tone == .standard)
        #expect(pip.size == .medium)
    }

    @Test func unknownToneAndSizeFallBackToDefaults() throws {
        let json = """
        { "blocks": [ { "kind": "stack", "children": [
          { "kind": "text", "text": "x", "tone": "chartreuse", "size": "cosmic" }
        ] } ] }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        let leaf = surface.blocks[0].children[0]
        #expect(leaf.tone == .standard)
        #expect(leaf.size == .medium)
    }

    @Test func unparseableJSONReturnsNil() {
        #expect(GenUIDecoder.surface(fromJSON: "{ not json") == nil)
        #expect(GenUIDecoder.surface(fromJSON: "42") == nil)
        #expect(GenUIDecoder.surface(fromJSON: #"{ "notBlocks": [] }"#) == nil)
    }

    // MARK: - Sanitizer rules

    @Test func nestedRowIsDropped() throws {
        let json = """
        { "blocks": [ { "kind": "stack", "children": [
          { "kind": "row", "children": [
            { "kind": "row", "text": "rows cannot nest" },
            { "kind": "pip" }
          ] }
        ] } ] }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        let row = surface.blocks[0].children[0]
        #expect(row.kind == .row)
        try #require(row.children.count == 1)
        #expect(row.children[0].kind == .pip)
    }

    @Test func buttonsWithoutTitleOrPromptAreDropped() throws {
        let json = """
        { "blocks": [ { "kind": "stack", "children": [
          { "kind": "glowButton", "text": "No prompt" },
          { "kind": "ghostButton", "prompt": "No title." },
          { "kind": "glowButton", "text": "  ", "prompt": "   " },
          { "kind": "glowButton", "text": "Valid", "prompt": "Do the thing." }
        ] } ] }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        let children = surface.blocks[0].children
        try #require(children.count == 1)
        #expect(children[0].text == "Valid")
    }

    @Test func blockEmptiedBySanitizerIsDropped() throws {
        let json = """
        { "blocks": [
          { "kind": "card", "children": [ { "kind": "glowButton", "text": "No prompt" } ] },
          { "kind": "card", "children": [] },
          { "kind": "stack", "children": [ { "kind": "text", "text": "survivor" } ] }
        ] }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        try #require(surface.blocks.count == 1)
        #expect(surface.blocks[0].children[0].text == "survivor")
    }

    @Test func rowEmptiedBySanitizerIsDropped() throws {
        let json = """
        { "blocks": [ { "kind": "card", "children": [
          { "kind": "row", "children": [ { "kind": "ghostButton", "text": "promptless" } ] },
          { "kind": "text", "text": "kept" }
        ] } ] }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        let children = surface.blocks[0].children
        try #require(children.count == 1)
        #expect(children[0].kind == .text)
    }

    @Test func sanitizerWorksOnDirectlyBuiltTrees() {
        // The sanitizer is the shared funnel for BOTH ingestion paths (tolerant
        // JSON today, strict guided generation later), so it must hold on trees
        // built without the decoder.
        let surface = GenUISurface(blocks: [
            GenUIBlock(kind: .card, framed: false, children: [
                GenUIItem(kind: .glowButton, children: [], text: "Broken", tone: .standard,
                          size: .medium, blinks: false, prompt: ""),
            ]),
            GenUIBlock(kind: .stack, framed: false, children: [
                GenUIItem(kind: .row, children: [
                    GenUILeaf(kind: .row, text: "", tone: .standard, size: .medium,
                              blinks: false, prompt: ""),
                    GenUILeaf(kind: .label, text: "OK", tone: .muted, size: .medium,
                              blinks: false, prompt: ""),
                ], text: "", tone: .standard, size: .medium, blinks: false, prompt: ""),
            ]),
        ]).sanitized()

        #expect(surface.blocks.count == 1)
        #expect(surface.blocks[0].kind == .stack)
        #expect(surface.blocks[0].children[0].children.count == 1)
        #expect(surface.blocks[0].children[0].children[0].text == "OK")
    }

    // MARK: - Renderer smoke (never crash, on every kind)

    @Test @MainActor func rendererSurvivesKitchenSinkTree() throws {
        let json = """
        { "blocks": [
          { "kind": "card", "framed": true, "children": [
            { "kind": "label", "text": "// telemetry", "tone": "muted" },
            { "kind": "divider" },
            { "kind": "row", "children": [
              { "kind": "orb", "size": "small" },
              { "kind": "text", "text": "All systems nominal", "tone": "bright", "size": "large" },
              { "kind": "spacer" },
              { "kind": "pip", "tone": "accent", "blinks": true }
            ] },
            { "kind": "glowButton", "text": "Run diagnostics", "prompt": "Run a full diagnostic pass." },
            { "kind": "ghostButton", "text": "Dismiss", "prompt": "Dismiss this card.", "size": "small" }
          ] },
          { "kind": "stack", "children": [ { "kind": "text", "text": "Footnote", "tone": "dim", "size": "small" } ] },
          { "kind": "row", "children": [ { "kind": "pip", "tone": "danger" }, { "kind": "label", "text": "alert" } ] }
        ] }
        """
        let surface = try #require(GenUIDecoder.surface(fromJSON: json))
        var tappedPrompt: String?
        let view = GenUISurfaceView(surface: surface) { tappedPrompt = $0 }
        let renderer = ImageRenderer(content: view.frame(width: 390))
        #expect(renderer.uiImage != nil)
        #expect(tappedPrompt == nil) // rendering alone must not fire the interaction primitive
    }

    @Test @MainActor func rendererSurvivesUnsanitizedOffContractTree() {
        // Belt and braces: even a tree that skipped sanitized() (row in leaf
        // position, promptless button) must render without crashing.
        let surface = GenUISurface(blocks: [
            GenUIBlock(kind: .stack, framed: false, children: [
                GenUIItem(kind: .row, children: [
                    GenUILeaf(kind: .row, text: "", tone: .standard, size: .medium,
                              blinks: false, prompt: ""),
                ], text: "", tone: .standard, size: .medium, blinks: false, prompt: ""),
                GenUIItem(kind: .glowButton, children: [], text: "", tone: .standard,
                          size: .medium, blinks: false, prompt: ""),
            ]),
        ])
        // Frame BOTH dimensions (like the empty-surface sibling test): the
        // off-contract content is defensively dropped by design, so the view
        // collapses to zero height and ImageRenderer of a zero-size view is
        // nil — that's a fixture artifact, not a survival failure.
        let renderer = ImageRenderer(content: GenUISurfaceView(surface: surface).frame(width: 390, height: 10))
        #expect(renderer.uiImage != nil)
    }

    @Test @MainActor func emptySurfaceRendersNothingButDoesNotCrash() {
        let renderer = ImageRenderer(
            content: GenUISurfaceView(surface: GenUISurface(blocks: [])).frame(width: 390, height: 10)
        )
        #expect(renderer.uiImage != nil)
    }
}
