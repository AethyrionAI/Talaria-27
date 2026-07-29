# OPUS-T27-200H-CALENDAR-SPIRAL — kill the lookup spiral, both seams

**Executor:** local Claude Code. **Drafted 2026-07-29 from the FILED #200F/#200G
verdicts (PRs #170/#171 merged, main `f469311`), routed by Owen ("Lets
continue" down the Owen-approved queue).** Branch `claude/t27-200h-calendar-spiral`.

## Why

With the carve-out promoted (remind 15/20 pooled), the dominant remaining
action-path disease is the LOOKUP SPIRAL on calendar prompts: "Sam" hunting
via repeated searchConversations/lookupContact/searchPlaces/readCalendar
chains. Every excluded trial across #200F+#200G (5 of 240) traces to it —
one 8,192-token context overflow at five searchConversations calls, four
wedged TIMEOUTs — and its byproduct is the D4 ledger's worst family:
SEMANTIC MISBINDING, where searchPlaces("Sam") returns Sam's Club (or
Pluckers Wing Bar, Pasadena TX, 500 miles away) and the model binds it as
the lunch location, plus the fabricated "Sam's place". Calendar creates sit
at ~74%; the spiral eats most of the remainder and poisons artifacts it
doesn't kill.

Two candidate seams, both measured (nothing promotes without a verdict):

- **Instructions** (the findfix precedent — the seam that has now won
  twice): a carve-out licensing creation without identity resolution.
- **Structural** (the #200E demote machinery, repurposed): the model
  cannot spiral if the decode mask closes after the spiral starts.

## The cells (3 × 4 prompts × n=10 = 120 trials, ~40 min)

- `armed` — promoted production control (destall clause + find-first
  carve-out, the f469311 text).
- `armed-spiralfix` — full production belt; instructions gain the
  lookup-spiral carve-out behind `includeLookupSpiralCarveout` (default
  FALSE, flag-off byte-identical, pinned verbatim), two sentences:
  "A person's name in an event or reminder is just part of the title —
  never search contacts, conversations, or places to identify them first."
  and "Only include an event location the user themselves gave; a place
  search result is never the location."
- `armed-strikefix` — belt AND instructions production verbatim; the sole
  treatment is a `SpiralBudgetProfile` (DynamicProfile): tool-calling mode
  `.allowed` until ANY single tool reaches its THIRD call in the request,
  then `.disallowed` — the model must answer with what it already has.
  Third-strike is data-derived: across #200F/#200G, every healthy create
  used at most 2 calls of any one tool (readCalendar×2 max); every spiral
  casualty had a tool at 3+ (searchConversations×5 at the overflow).
  Per-name tally via `@SessionProperty` `[String: Int]` (Apple's own
  SessionPropertyEntry doc example is a dictionary) fed by the NAMED
  `onToolCall(perform: (Transcript.ToolCall) ...)` overload —
  `Transcript.ToolCall.toolName` verified in the vendored beta-4
  interface. Pure demote function pinned (`spiralBudgetMode(tally:)`).

Haiku rides as the grab/composition canary in every cell, unchanged.

## Success bar

In a treated cell: calendar creates ≥ control with ZERO spiral casualties
(no context-overflow ERROR, no wedged TIMEOUT), remind holds its promoted
band, alarm holds ceiling, grabs ≤ control, no new corruption. For
spiralfix additionally: zero location-misbinding specimens — the calendar
prompt names no place, so ANY location in a treated create is a misbind.

## Watch-fors (filed up front)

- `.allowed → .disallowed` mid-request via DynamicProfile is a NEW mode
  combination on 27b4. If it trips the decoder (the #200E
  `ifpInvalidExpertPickPosition` class), the cell is DEAD like
  `.required`: route around, NO Apple filing (standing rule per Owen).
- The strike budget could cut off legitimate long flows — #200G
  findfix/calendar/t5 created on its 6th call but never exceeded 2 of any
  one tool, so it survives third-strike; verify no treated no-create shows
  a strike firing before the create.
- The spiralfix sentences could suppress LEGITIMATE lookupContact use in
  ordinary chat — that is a promotion question for the follow-up lane,
  not this battery's.

## Rules

House rules. Instrument unchanged (per-trial reap + unmarked echo, proven
twice, arithmetic exact both runs). Suite green with count before PR
(last: 1292/1292 in 111 suites); TDD pins watched RED; file-scoped
commits; corded deploy preferred; Owen runs, routes the verdict and the
merge. Out of scope: the cap cell (D4), the grab-disease lane, tool
description edits, any `.required` rerun, promotion of either treatment.
