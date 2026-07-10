# Lane D — P8 IR v0: constrained generative UI (schema + renderer, no model wiring)

**Repo:** `AethyrionAI/Talaria-27` · **Branch:** `claude/t27-lane-d-ir-v0` off `main` · **PR to:** `main` · **Do not merge.**

## Mission

First rung of P8: the model never emits raw UI code — it emits a constrained,
structured description of UI (an Intermediate Representation) as a strict
`@Generable` schema, and a hand-built renderer maps that IR onto real, shipped
SwiftUI components. IR v0's vocabulary is EXACTLY the existing HUD component set,
so the renderer is nearly free and the model literally cannot draw anything not
pre-approved.

## Scope (Fable builds all of this)

1. **Discovery first:** enumerate the public component set in
   `Talaria/Core/HUD/HUDComponents.swift` (+ `HUDEffects.swift` where a component
   is parameterized by an effect). The IR node vocabulary mirrors it 1:1 — no new
   visual capabilities in v0.
2. **IR schema** — `@Generable` structs/enums (follow the established idiom in
   `Talaria/Services/Live/DeviceTools/*.swift`; note the Wave 3 lesson: `@Generable`
   macro fails on `private` nested types — use `fileprivate`+). Tree-shaped:
   containers (card/row/stack) + leaves (the HUD components with their real
   parameters) + one interaction primitive (a button that sends a prompt string).
3. **Renderer** — a hardcoded IR-tree renderer view: recursive switch over node
   types → the existing HUD components. No dynamic view synthesis, no AnyView
   sprawl beyond what recursion requires.
4. **Tests** — decode sample IR JSON → structural assertions on the render tree;
   malformed/unknown-node handling (skip-and-log, never crash).
5. **Debug harness** — a DEBUG-only preview/screen with 2–3 hardcoded IR trees so
   Owen can eyeball rendering on device. Real-data-only rule applies to user
   surfaces: nothing here ships outside DEBUG.

## Explicitly OUT of scope

- Model integration, prompting, or FoundationModels session wiring.
- The on-device emission-quality test (needs the device runtime — Mac/Owen side, post-merge).
- Any `ChatScreen.swift` change. Any surfacing in the user-facing chat flow.

## Guardrails

- New files are expected — flag every new file in the handoff note (Mac session
  runs `xcodegen generate` + verifies `aps-environment` survives).
- File-scoped commits; no pbxproj/xcodegen output in feature commits.
- Cloud cannot build: verify API shapes against the DeviceTools precedents, note
  compile-risk areas honestly; the Mac review-then-build loop verifies against the
  iOS 27 SDK.
- Existing tests stay green; nothing outside the new files changes behavior.

## Definition of done

Open PR with schema + renderer + tests + DEBUG harness as discrete commits, plus a
handoff note listing new files, the IR node vocabulary table, and what remains for
the on-device emission-quality rung. Not merged.
