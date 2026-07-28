# OPUS-T27-196-DECOMPOSITION — third battery: structural decomposition of the armed disease

**Executor:** local Claude Code, checkout `/Users/owenjones/Documents/Claude/Talaria-27`.
**Verdict desk:** Owen (+ chat-lane Opus). **Written:** 2026-07-27 late evening.

## Why this lane exists — read before touching anything

#196 in one paragraph: the on-device brain opens replies with disclaimers it then
contradicts, refuses composition as "external knowledge," and parses creative verbs as
todos. First battery (n=10, 2026-07-27 morning build) identified two mechanisms:
task-verb confusion (spurious `createReminder` grabs on "write a haiku") and
knowledge-denial on composition. Second battery (n=20, build `686d2e2`, same evening)
measured three prose treatments: a scoped reminder description (weak partial), a
composition-licensing sentence (real gains, insufficient), and a licensed tool-less
branch (a genuine cure — but on the branch production barely exercises).

**Owen's verdict: nothing on the armed path is fixed. Prose amendments inside the
existing architecture are not the road.** Every cell tested so far edits sentences;
none has decomposed the structure. This lane does the decomposition.

**THE BAR (do not reinterpret it):** nothing ships until a cell posts toolless-class
numbers WITH a belt available. `toolless` wrote 20/20 flawless haiku and, licensed,
18/20 clean Norway summaries — the base model is healthy. Every disease is something
our armed session construction adds. The job is finding which ingredient, structurally.

## Baseline — second battery, n=20/cell, Debug `686d2e2`, whoGoesThere (iOS 27 beta 4), 2026-07-27 22:04 CDT

| Cell | Canary content (clean) | Haiku content (clean) | Action grabs | Norway content (clean) |
|---|---|---|---|---|
| armed | 14/20 (6) | 17/20 (7) | 19/20 | 3/20 (0) |
| armed-remfix | 12/20 (3) | 13/19 (5) | 12/20 | 4/20 (0) |
| armed-complic | 19/20 (16) | 17/19 (6) | 20/20 | 7/17 (0) |
| armed-fix | 19/20 (18) | 17/20 (3) | 17/20 | 9/17 (0) |
| toolless | 0/20 (0) | 20/20 (20) | 0 | 0/20 (0) |
| toolless-lic | 8/20 (4) | 20/20 (20) | 0 | 18/20 (18) |

Notes that must survive into your analysis:
- 8 trials died to `ToolCallError`/JSON ERROR lines and are excluded from denominators
  (they are #197's machinery-failure family surfacing in battery form — note, don't fix here).
- NEW discovery: the bare branch denies ARITHMETIC (toolless canary 0/20). The licensing
  sentence only partially recovers it (8/20) because it licenses writing, not calculation.
- `toolless-lic` produced a degenerate `response_format: {"content": "4"}` JSON wrapper on
  4/20 canary trials — watch-item, cell-unique artifact.
- armed haiku t11 CLAIMED "I've also created a reminder for you" after the gate declined —
  a real-data-only fabrication. Noted in-thread; candidate for its own item later.
- Grabs are now measured directly (`tool=` log lines): 19/20 armed haiku trials would pop
  a spurious confirmation card at a real user. This is the defect that reaches the screen.
- HELD ship candidates (measured wins, held by Owen's verdict): the composition sentence
  and the licensed bare branch. Their cells and seams stay in the code untouched. Do NOT
  ship, delete, or reword them in this lane.

## Part 0 — SDK reconnaissance (do this first, ~30 min)

Grep the beta-4 FoundationModels `.swiftinterface` (under
`/Applications/Xcode-beta4.app/.../iPhoneOS.sdk` and the Simulator SDK) for any per-call
or per-session tool-selection control: `toolChoice`, `allowedTools`, tool-related members
on `GenerationOptions`, `Tool` protocol properties that gate schema injection into the
prompt (e.g. anything like `includesSchemaInInstructions`), session-level tool toggles.
Report EXACT findings (declarations, availability) in your return.
**If a genuine per-turn tool-choice control exists, STOP after Part 0 and report before
building cells — it changes the cell design and possibly the entire ship path.**

## Part 1 — the five-cell decomposition battery

Battery-2's treatment cells stay in the `SessionShape` enum (held candidates; the
Diagnostics picker keeps them reachable for manual spot checks). The BATTERY cell list
swaps to these five. New raw values must round-trip the enum; retired spellings keep
parsing to production, pinned by the existing test pattern.

1. **`armed`** — control, byte-identical production. Unchanged.
2. **`armed-noinstr`** — production belt, NO instructions. Use the no-instructions
   `LanguageModelSession` init if the API offers one; otherwise the closest the API
   permits (e.g. empty `Instructions`). DOCUMENT exactly what was passed — this cell's
   value depends on it.
3. **`toolless-noinstr`** — no belt, no instructions. The in-app replica of the
   Shortcuts "Use Model" probe that wrote haiku happily on this same phone.
4. **`armed-readonly`** — production instructions; belt = production MINUS the three
   action tools (`ReminderCreateTool`, `CalendarEventTool`, `AlarmTool`). Implement as a
   shape-keyed filter in `shapedBelt` (the remfix precedent — same instances otherwise,
   same order, same relay).
5. **`armed-example`** — production instructions PLUS one worked-example sentence placed
   beside the licensing clause: "For example, if asked to write a haiku, a poem, or a
   summary, you simply write it yourself — no tool is involved." (Owen veto at PR
   review; keep it to exactly one sentence, single-variable discipline.)

What each comparison isolates:
- `armed` vs `armed-noinstr`: is OUR instruction text a net cause of the armed disease,
  or is it the belt registration itself? The single most load-bearing comparison — every
  future fix routes on it.
- `armed-noinstr` vs `toolless-noinstr`: pure tool-registration effect, zero prose.
- `toolless-noinstr` vs `toolless`: what the bare-branch PROSE costs (it denies
  arithmetic 20/20 — is that the text or the model?).
- `armed` vs `armed-readonly`: grabs must die structurally (no tool to grab); the
  question is whether haiku CLEAN recovers toward toolless levels. If yes, the ship path
  is extending #176 availability gating to action tools — built, battle-tested mechanism.
- `armed` vs `armed-example`: do worked examples beat rules for this model size?

## Part 2 — battery mechanics

Unchanged from PR #159 except the cell list: n as passed (Owen runs n=20), same three
prompts (canary / haiku / norway), same per-trial log format, `tool=` lines via
`ToolEventRelay.batteryTrialTag`, confirmation auto-decline, 35s guillotine. Update the
Diagnostics button labels (5 cells ≈ 300 trials at n=20) and add the new cells to the
picker (menu style).

## Rules — non-negotiable (CLAUDE.md + this thread's scars)

- `export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in EVERY
  shell. Wrong-toolchain smell: `cannot find in scope` on iOS-27 API — fix the env,
  never the app code. State build ID `27A5228h` and evidence scope in the return.
- File-scoped commits; merge commits only (`gh pr merge --merge`); OPEN_ITEMS edits in
  their own commits; specs/docs direct to main, code via PR.
- `xcodegen generate` ONLY if Swift files are added/removed; afterwards verify
  `aps-environment: development` survived in entitlements. (No new files are expected
  in this lane.)
- Sim `47F68496-24F9-45D9-93D3-1C778DB6B557`, `CODE_SIGNING_ALLOWED=NO` for sim builds.
  Suite baseline entering this lane: **1236 tests / 109 suites + 15 XCUITest**. Repin
  for the new cells and state the new count.
- Rates or nothing. No verdict from single shots — n=4 and n=1 convictions have both
  been overturned in this investigation. Classify from RAW TEXT; `cant=`/`denial=` are
  hints only. Exclude ERROR trials from denominators and list them.
- NEVER fabricate, simulate, or extrapolate battery results. The device run is the only
  data source. If the device is unreachable, stop and say so.

## Deploy + capture

Preferred: the Xcode MCP bridge if configured in your session (destination
`whoGoesThere`, `RunProject`, then `GetConsoleOutput` with `pattern: "battery:"` and a
small `tailLimit` — the bridge crashes on heavy first calls). Fallback: `xcodebuild`
Debug device build + `xcrun devicectl device install app` / `launch` (phone is
LAN-reachable at home; NOT reachable via Xcode over the tailnet — do not relitigate,
see CLAUDE.md). Then STOP: Owen taps Diagnostics → Local brain → Battery n=20. Resume
only when he says the run finished.

## Return format

1. PR: cells + repinned tests, green suite, evidence-scope statement, build ID.
2. Part 0 findings verbatim (declarations found or a clean "nothing exists").
3. After the device run: the full table in the baseline's exact format + per-cell grab
   counts + ERROR list.
4. Verdict routed against THE BAR, with the decomposition logic above made explicit:
   which ingredient owns the disease, and which structural lane follows (instruction
   rework wholesale / action-tool availability gating / per-turn routing).
5. Results filed into OPEN_ITEMS #196 as a separate commit.
