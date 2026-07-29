# OPUS-T27-200E-TOOLMODE — structural de-stall: `.required` with a demote exit

**Executor:** local Claude Code. **Drafted 2026-07-29 from the VERIFIED #200D promotion
(PR #168 merged `2866f87`) and the FM SDK seam survey
(`planning/FM-SDK-SEAM-SURVEY-2026-07-28.md`), routed by Owen ("Lets do it. I'm ok
with your plan").** Branch `claude/t27-200e-toolmode`.

## Why

The promoted clause took calendar and alarm to ceiling but remind sits at ~10% creates
(2/19 on the promoted build) — the list-stall survives every prose treatment at
~50–90%. `GenerationOptions.ToolCallingMode` (verified in the beta-4 SDK) is the
structural seam UPSTREAM of response planning: `.required` forces tool engagement at
the decoding level. The stall becomes impossible-by-construction — the open question
is what the forced call is (createReminder, or a readReminders that satisfies the
requirement and re-enters the substitution path).

## Loop hazard (design-critical, three sources agree)

`.required` makes the session LOOP "until a Tool throws an error or this value is
changed dynamically" (fmf.md doc-comment transcription of this exact SDK; WWDC26/242
confirms and gives the exit pattern; Foundation Lab ships working code). The cell
therefore implements the DEMOTE pattern — `.required` until the first tool call, then
`.allowed` — via `DynamicProfile` + an `.onToolCall` flag (or the closest
battery-compatible equivalent verified against the local SDK at build time). Raw
`.required` in a plain GenerationOptions respond() is FORBIDDEN in this lane: it would
spin trials into the guillotine and burn the battery.

## The cells

- `armed` — promoted production control (clause ON since #200D; re-baselines in-run).
- `armed-toolmode` — production belt + promoted production instructions, UNTOUCHED;
  the ONLY treatment is the per-request tool-calling mode with the demote exit.

Success = remind creates move decisively off ~10% at tolerable cost. The canary is
CRITICAL and expected to be ugly: `.required` on the haiku prompt FORCES a tool call
by construction — the cell measures WHICH tool the model grabs when forced (an
escape-valve read? createReminder?). A promotion would therefore be ROUTER-GATED
(required-mode only on turns the router classifies as action intent); the haiku cell
here measures the misroute blast radius, not a promotable rate.

## Protocol

2 cells × 4 prompts × n=10 = 80 trials, auto-accept, reap, mutex — the standard
instrument. Button: "Toolmode battery n=10 (80)". Deploy CORDED via the Xcode bridge
(Owen is home): `RunProject` on whoGoesThere, console attached — first lane with live
device logs, so also watch for the wedged-respond hang class in GetConsoleOutput.
Watch the D4 signals filed in #200D: `missing 'title'` ToolCallError rate and
comma-prefix titles — forced calling may raise or reshape argument corruption.

## Rules

House rules as ever: TDD (pins watched RED first), file-scoped commits, suite green
with stated count, classification from RAW TEXT with rates, ERROR/TIMEOUT trials
excluded and listed, reap arithmetic cross-check (NOTE from #200D: counts are
this-run + leftovers; confirm no aborted-run artifacts precede the run — Owen runs
the alarm sweep first). NOTHING promotes without the verdict. Out of scope: the
DynamicProfile adoption bundle (pivot B), tool-scoping cell (C), cap cell (D),
Hermes-as-provider (E) — all queued behind this lane per the survey plan.
