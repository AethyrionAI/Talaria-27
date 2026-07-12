# Lane D handoff — P8 IR v0 (schema + renderer + tests + DEBUG harness)

**Branch:** `claude/t27-lane-d-ir-v0` off `main` (8771b34) · **PR to `main` — do not merge.**
Cloud-written, **NOT compiled or device-verified**. OPEN_ITEMS **#92** tracks the item.

## What was built

The first rung of P8 exactly per `dispatch/FABLE-LANE-D-p8-ir-v0.md`: the model's only UI
output is a constrained `@Generable` IR tree; a hand-built renderer maps it onto the shipped
HUD components. **No model wiring, no ChatScreen change, no user-facing surface** — the only
entry point is a DEBUG-gated Developer-screen row.

The tree is **depth-bounded by construction, not recursive**: surface → block
(card/stack/row) → item (leaf, or one row of leaves) → leaf. Deliberate: recursive
`@Generable` schemas are unverified against the shipped macro, and the hard nesting ceiling
constrains generation further — which is the point of v0.

Ingestion contract: every surface passes through `sanitized()` (skip-and-log; drops log one
always-on `TalariaLog.event` line each) before rendering — the renderer itself is a total,
side-effect-free mapping and never crashes on off-contract trees.

## New files (Mac session: `xcodegen generate` required)

| File | Role |
|---|---|
| `Talaria/Services/Live/GenerativeUI/GenUISchema.swift` | `@Generable` IR types + `sanitized()` funnel |
| `Talaria/Services/Live/GenerativeUI/GenUIDecoder.swift` | Tolerant JSON ingestion (JSONSerialization walk, skip-and-log) |
| `Talaria/Features/GenerativeUI/GenUISurfaceView.swift` | Renderer: IR tree → HUD components, `onPrompt` interaction primitive |
| `Talaria/Features/GenerativeUI/GenUIDebugScreen.swift` | DEBUG-only harness, 3 sample trees (whole file `#if DEBUG`) |
| `TalariaTests/GenUISchemaTests.swift` | Decode / tolerance / sanitizer / ImageRenderer smoke suite |

**Modified (1 file, additive, DEBUG-only):** `Talaria/Features/Settings/DeveloperSettingsScreen.swift`
— new `#if DEBUG` "// Generative UI → IR v0 Harness" nav section. Nothing else outside the
new files changed.

After regen, re-verify `aps-environment` + `com.apple.developer.weatherkit` survive
(the #44/#48 strip trap).

## IR node vocabulary (v0 — mirrors the shipped HUD set, nothing else)

| IR node | Renders as | Parameters exposed |
|---|---|---|
| block `card` | padded VStack + `.hudPanel()`; `framed` → `CornerBrackets` overlay | `framed`, `children` |
| block `stack` | `VStack(.leading, sm)` | `children` |
| block `row` | `HStack(sm)` | `children` |
| item `row` | `HStack(sm)` of leaves (rows cannot nest — sanitizer drops nested rows) | `children` |
| `label` | `MonoLabel` | `text`, `tone`, `size` → 9/10/12pt |
| `text` | `Text` + `Design.Typography.body` | `text`, `tone`, `size` → 13/16/20pt |
| `pip` | `StatusPip` | `tone`, `size` → ⌀5/7/9, `blinks` |
| `glowButton` | `GlowButton` → `onPrompt(prompt)` | `text`, `prompt`, `size` → h44/48/56 |
| `ghostButton` | `GhostButton` → `onPrompt(prompt)` | `text`, `prompt`, `size` → h44/48/56 |
| `orb` | `ReactorOrb` at the real app presets | `size` → 26·`.minimal` / 42·`.standard` / 74·`.onboarding` |
| `divider` | hairline `Rectangle` (`Design.Colors.hairline`, 1pt) | — |
| `spacer` | `Spacer(minLength: 0)` | — |

`tone` resolves through theme tokens (`standard`/`bright`/`muted`/`dim` → foreground ramp,
`accent` → `Brand.accent`, `warning` → `Brand.forge`, `danger` → `Colors.danger`), so
generated UI re-skins with the active theme like every other surface.

**Deliberately excluded from v0:** screen chrome (`HUDScreenBackground`, `GridOverlay`,
`ScanLine`, textures), `ReactorOrb.voice` (232pt hero), `SettingsScreenHeader`,
`GlassCircleButton`, button `systemImage` (arbitrary SF Symbol names are unapproved
surface), forge/danger tinted button pills (not shipped components — CLAUDE.md says build
them first). Effects (`hudGlow`/`hudPulse`/`continuousRotation`) ride *inside* the shipped
components (pip `blinks`, orb spin) — no standalone effect nodes.

**Sanitizer rules** (the part a schema can't express): nested rows dropped; buttons without
both title and prompt dropped; rows/blocks left empty dropped; every drop logs to Console
under `org.aethyrion.talaria`.

## Compile-risk areas (cloud could not build — verify against the iOS 27 SDK)

1. **`@Generable` on plain enums** (`GenUINodeKind`/`GenUIBlockKind`/`GenUITone`/`GenUISize`).
   Apple's Generable doc overview says "structure or enumeration", but the in-repo precedent
   (DeviceTools) only exercises structs. Fallback if the macro balks: make the kind/tone/size
   fields `String` — the decoder/renderer already route through `init?(irName:)` mappings.
2. **`@Guide(description:)` on enum-typed and Bool properties** — precedent covers
   String/Int only. Fallback: drop those `@Guide`s (the enums keep their own descriptions).
3. **Memberwise inits on `@Generable` structs** — tests, samples, and the sanitizer assume
   the macro preserves the implicit memberwise init. Fallback: add explicit inits.
4. **`ImageRenderer` smoke tests** in the unit bundle — expected fine on simulator; if not,
   downgrade those three tests to structural assertions.
5. Verified-in-docs (2026-07-10, live Generable doc JSON): arrays of `@Generable` types,
   nested `@Generable` structs, `@Generable(description:)`.

## What remains for the on-device emission-quality rung (post-merge, Mac/Owen side)

1. `xcodegen generate` → CLI build → full test run (`GenUISchemaTests` is new).
2. Device eyeball: Settings → System → Developer → **IR v0 Harness** — three samples render;
   sample 03 shows survivors only, with drop lines in Console.app; button taps stage their
   prompt in the readout (nothing sends). Flip through the four flagship themes — every
   color in the renderer is token-resolved.
3. The actual rung: `LanguageModelSession(…)` + `respond(generating: GenUISurface.self)`
   guided generation, prompt design, and an on-device eval of what the 3B model really emits
   (schema adherence, layout sanity, prompt-string quality). Strict output still goes through
   `sanitized()`. Only after that: any chat surfacing (explicitly out of v0's scope).
4. On merge: CLAUDE.md current-state note + OPEN_ITEMS #92 update with device verdicts.
