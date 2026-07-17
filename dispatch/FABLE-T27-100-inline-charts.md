# FABLE T27-100 — Inline charts / data viz

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-100-*`
**Dispatch date:** 2026-07-16 · **Tracks:** OPEN_ITEMS #100 (no GitHub issue)
**Size:** two PRs, stacked. PR 1 is pure model+parser (cloud-safe, fully
unit-testable). PR 2 is the SwiftUI/Swift Charts render surface.

**Merged-PR check done 2026-07-16 (the staleness rule):** `gh pr list --state
all` across all 106 PRs shows no chart/data-viz PR; `grep -rln "import Charts"`
returns nothing on main. The work does not exist. #92 (markdown pipeline) is
merged AND device-verified 2026-07-11, which is what unblocked this item.

## Why this is worth building

Both competitors render charts inline. Talaria has health/sensor telemetry and
cost/usage data already flowing through it — the payload is here, the surface
isn't. This is the first feature that makes Hermes's numbers *legible* rather
than recited.

## The seam (verified in source at HEAD, 2026-07-16)

The markdown pipeline is a clean two-piece hinge, and it already does 90% of
the structural work:

- `Talaria/Core/MarkdownParser.swift` — `enum MarkdownSegment: Identifiable`
  with cases `.prose / .codeBlock(language:code:) / .image / .heading /
  .blockQuote / .list / .table(header:alignments:rows:)`. Note `.table` is
  ALREADY parsed into structured `[String]` header + `[[String]]` rows.
- `Talaria/Features/Chat/MarkdownContentView.swift` — one `switch segment`
  renders each case. Entry is
  `parseMarkdownSegments(content, isStreaming: isStreaming)`.

Add one case to the enum, one arm to the switch. Do not fork the pipeline, do
not add a second parser, do not touch `MessageBubble`'s ownership of content.

## CRITICAL: the parser re-runs on every streaming delta

`MarkdownContentView.body` calls `parseMarkdownSegments(content, isStreaming:)`
on every evaluation — i.e. per SSE delta. A chart fence therefore arrives
CHARACTER BY CHARACTER and will be malformed JSON for most of its life on
screen. This is the single hardest constraint in the lane:

- While `isStreaming` and the fence is unterminated → render the partial as a
  `.codeBlock` (or nothing), NEVER a chart. No flicker, no half-drawn axes, no
  re-layout thrash per token.
- A chart may only materialize on a CLOSED fence with a spec that decodes.
- Charts must not animate-in per delta. Draw once, when whole.

## Detection: two paths, deliberately

**Path A — the fence contract (primary).** A fenced block whose language is
`chart` carrying a JSON spec:

    ```chart
    {"type":"line","title":"Resting HR, 7d",
     "x":{"label":"Day","values":["Mon","Tue","Wed"]},
     "series":[{"name":"bpm","values":[58,61,57]}]}
    ```

Parser: extend the EXISTING fenced-code-block scan — when language == `chart`,
attempt `ChartSpec` decode; on success emit `.chart(spec:)`, on failure emit
`.codeBlock` unchanged (see degradation below).

**Path B — numeric table promotion (fallback, no model cooperation needed).**
`.table` is already structured. When a table's non-header columns are ≥2 rows
and fully numeric-parseable, attach an affordance to CHART it (PR 2: a small
chart toggle on the table surface). This path works today with zero prompt
changes, on output the model already produces.

Path A is the better artifact; Path B is the one that works without asking
anything of the backend. Build A in PR 1; wire B's detection predicate
(`MarkdownTable.isChartable`) in PR 1 as a pure function + tests, and land its
UI in PR 2 only if it stays cheap.

## ChartSpec: tolerant by law

New file `Talaria/Models/ChartSpec.swift`. Decodable, and TOLERANT in the
house sense (the #58 inbox lesson: one bad field must never poison the render):

- `type: String` decoded permissively → map to a `ChartKind` enum
  (`line/bar/area/point`), unknown → decode FAILS cleanly (falls back to code
  block). Do NOT crash, do NOT force-unwrap, do NOT default a wrong chart type.
- Series values: `[Double]`. Mismatched x/y lengths → decode fails (fall back).
  Empty series → decode fails.
- `title`, `x.label`, `y.label` optional.
- Cap the input: refuse specs over a sane series/point budget (say 8 series ×
  500 points) rather than trying to render a 50k-point line on a phone.

**Degradation is the acceptance criterion, not a nicety:** every failure path
renders the ORIGINAL fenced block as a normal code block. The user always sees
the data. Losing content to a chart bug is the one unacceptable outcome.

## PR 1 — model + parser (no UI)

Files: `Talaria/Models/ChartSpec.swift` (new), `Talaria/Core/MarkdownParser.swift`,
`TalariaTests/ChartSpecTests.swift` (new), `TalariaTests/MarkdownParserTests.swift`
(extend if it exists).

1. `ChartSpec` + `ChartKind` as above.
2. `MarkdownSegment.chart(id: UUID = UUID(), spec: ChartSpec)` + its `id` arm.
3. Parser: language == `chart` → decode → `.chart` or `.codeBlock`.
4. Streaming: unterminated `chart` fence while `isStreaming` → `.codeBlock`.
5. `isChartable` predicate for numeric tables (pure, tested, unused in PR 1).

Test gate (all pure, cloud-runnable — this is why PR 1 exists):
- valid spec of each kind → `.chart`
- malformed JSON / unknown type / empty series / ragged lengths / over-budget
  → `.codeBlock`, content preserved byte-for-byte
- unterminated fence + isStreaming → `.codeBlock`, never `.chart`
- a `chart` fence inside a larger message → neighbouring segments unchanged
- `isChartable`: numeric table true; mixed/1-row/empty false

## PR 2 — render surface

Files: `Talaria/Features/Chat/ChartSegmentView.swift` (new),
`MarkdownContentView.swift`, tests as feasible.

- `import Charts` (first use in the app — confirm the iOS 27 deployment target
  is satisfied under Xcode-beta3, `/Applications/Xcode-beta3.app`).
- Theme it: colours come from `Design.Colors.accent / .accentBright /
  .accentDeep` (which resolve live from `ThemeRuntime.shared.palette`). A chart
  must look native under Midnight Marquee and every other theme — NEVER
  hardcode a hex. Multi-series: derive from the palette, don't invent a
  rainbow.
- Respect the bubble's width; charts get a fixed sane height (~180pt), no
  intrinsic-size fights with `LazyVStack`.
- Tap → fullscreen. There is an EXISTING precedent to mirror, not reinvent:
  `MarkdownContentView`'s `@State private var fullscreenImage: MarkdownSegment?`
  does exactly this for `.image`. Follow that shape.
- Accessibility: `.accessibilityLabel` summarizing title + series names; the
  chart must not be an unlabeled blob to VoiceOver.

## Constraints (house)

- File-scoped commits. No `OPEN_ITEMS.md` edits in feature commits.
- **`xcodegen generate` IS required** — this lane adds Swift files (ChartSpec,
  ChartSegmentView, test files). The regen commit is separate from feature
  commits, and the loop verifies `aps-environment: development` survives in
  `Talaria/Talaria.entitlements` afterward. New test files unregistered = the
  build gate silently lies (this cost us 24 missing tests on #99 — don't).
- Toolchain is **Xcode-beta3** (`DEVELOPER_DIR=/Applications/Xcode-beta3.app/
  Contents/Developer`), per CLAUDE.md as of 2026-07-16.
- PR 2 stacks on PR 1: `gh pr edit <PR2> --base main` before PR 2 merges.
- Do not touch `MessageBubble`'s streaming/ownership logic. Do not add a
  charting dependency — Swift Charts is first-party and sufficient.
- Baseline to beat: **691 tests / 58 suites** green (main @ 2026-07-16).

## Acceptance

- PR 1: parser emits `.chart` only for closed, valid fences; every failure and
  every mid-stream state degrades to a code block with content intact; test
  gate above green.
- PR 2: chart renders themed, sized, tappable-to-fullscreen, VoiceOver-labeled;
  suite green; PR notes the device check for Owen (ask Hermes for a `chart`
  fence of recent resting HR — the sensor data is already flowing to the host).

## Open decision for Owen (do NOT guess — ask in the PR)

Path A needs the model to KNOW the fence contract. Nothing tells it today.
Options: (a) a system-prompt/instruction addition on the Hermes side, (b) rely
on Path B table-promotion until then, (c) both. This lane deliberately builds
the app-side surface so that EITHER path lights it up, and leaves the prompt
question to Owen. Don't add prompt plumbing in this lane without his call.
