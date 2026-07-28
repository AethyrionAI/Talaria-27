# OPUS-T27-196-PROMOTE-ROUTED — armed-routed becomes the production default

**Executor:** local Claude Code. **Promotion called by Owen 2026-07-28 (~09:05 CDT)** after
the battery-4 device verdict. Branch `claude/t27-196-promote-routed`, stacked on #162.

## Verdict basis (all device, whoGoesThere, 27b4, 2026-07-28 — filed in OPEN_ITEMS #196)

- Battery n=20 (`run-20260728-133701`): **armed-routed 60/60 CONTENT and 60/60 CLEAN**
  across canary/haiku/norway; toolless-lic2 likewise 60/60; armed control diseased in the
  same run (haiku clean 0/20, norway content 3/20). Zero ERROR/TIMEOUT trials.
- Router probe n=20 (`run-20260728-135219`): **200/200, both directions.**
- Live-path spot check (Owen, screenshot): novel arithmetic and novel creative prompts
  clean over the real chat path — the cure is not overfit to the battery prompts.
- Measured router cost ~0.6s/turn — accepted by the verdict desk.

## What promotion means

1. **Release builds route every turn.** `preparedSession` classifies the incoming prompt
   with the few-shot guided-generation router (greedy, 64-token cap). Words-only turns
   build a session with NO belt and the `toolless-lic2` instruction text; device turns
   build the production armed session, byte-identical to today's. Router errors fail safe
   to armed. The #176 recreate seam already swaps sessions when the route flips.
2. **The router machinery leaves `#if DEBUG`:** `ToolIntentRoute`, the few-shot
   instructions, the greedy options, `routeNeedsDeviceTool`, and the `turnRoutedToolless`
   turn state become production code. The measured winning prompt/options are pinned by
   tests and MUST NOT drift silently.
3. **The DEBUG A/B instrument survives intact.** The Diagnostics picker still overrides
   per launch; a non-routed cell disables routing for that launch so every legacy cell
   stays pure. The DEBUG default flips `armed` → `armed-routed` so an untouched Debug
   install behaves like production. Batteries are unaffected (they parameterize shapes
   explicitly).
4. **Nothing else ships.** Held battery-2 candidates stay held. The armed instruction
   text, belt assembly, options, and confirmation gates are unchanged for device turns.

## Constraints

House rules: file-scoped commits, merge commits only, OPEN_ITEMS separate, suite green
with stated count, evidence scope + build ID in the PR. Verification MUST include a
**Release-configuration build** (the promoted code now lives outside `#if DEBUG` — a
Debug-only suite cannot prove Release compiles). After PR: OTA-stage the branch Debug and
report, so Owen can verify the promoted default on device.
