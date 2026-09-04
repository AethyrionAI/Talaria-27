# 340 — The User's Words Resolve the Due Date Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the on-device brain calls `createReminder` with an EMPTY due date — which it does in roughly 55% of trials on the shipping guide text — the app resolves the date from what the user actually typed, deterministically, before the confirmation card is staged. The dateless reminder that opened #340 stops being the common case, and the model's "I'll remind you at 4" becomes a true sentence because the card really says 4.

**Architecture:** One new deterministic parser (`DeviceActionParsing.detectDue(in:now:)`, `NSDataDetector` + the existing bare-clock parser run over the USER'S message), one new per-turn field on the tool relay (`ToolEventRelay.beginTurn(userText:)` — the seam `LocalChatBackend.beginToolTurn()` already calls at the top of every turn), and one new branch in `ReminderCreateTool.performCreate` that fires ONLY when the model's argument is empty. Nothing about the model, the guide text, the guards, or the honesty guard changes. The existing `due-date` instrument and `score-due-omission.py` measure it, with one added column so the fix's contribution is a number rather than an inference.

**Tech Stack:** Swift 6.4 / FoundationModels tool calling (`ReminderCreateTool`, `@Generable Arguments`) / Foundation `NSDataDetector` / EventKit / Swift Testing / `scripts/mac/run-instrument.sh` + `scripts/mac/score-due-omission.py` / `scripts/mac/lane-gate.sh`.

**Why this is the shape (read before touching anything):** Owen ruled route (a) — APP-SIDE — on 2026-08-18: *"`performCreate` resolves a bare clock time itself."* That shipped (2026-08-21) and is correct (0 wrong-value across every measured call) but **it only ever sees the model's argument**, and the model sends an empty string most of the time — so the correct parser almost never runs. This plan extends route (a) one step upstream: when the argument is empty, resolve from the user's own words. It is the same deterministic-before-the-model shape `ExplicitMemoryIntent` uses for memory notes (#422), and it stays inside every ruling on the entry: 340-E (the honesty guard stays prose-only) is untouched, route (b) (schema `required`, twice shown to convert omissions into WRONG values) is not revisited, and the guide text promoted on 2026-09-01 is byte-untouched.

**Provenance of the numbers here:** 340-H5′-A/B, device `whoGoesThere`, build 3125, `24A5424a`, n=40/arm, 2026-08-27: `armed-bareclock` populated-future **18/40 (45%)**, union omitted+wrong-value 19/40, wrong-value 0/40, no-call 3/40. That text was promoted to production 2026-09-01 (PR #404); **no post-promotion production run exists** — 340-P-D records the replication as OWED. This plan's device run replaces that owed replication with an A/B that also measures the fix.

## Global Constraints

- **Route (a) is the ruling; this is route (a) upstream.** The fallback fires ONLY when the model's `due` argument is empty. A populated argument keeps today's path byte-for-byte (explicit ISO → bare clock → guards). Never overrule a value the model supplied — the existing measurement (0 wrong-value) is the reason.
- **Deterministic, no model.** `NSDataDetector(types: .date)` and the existing `parseBareClock` only. No second model call, no guided-generation retry, no prose. A structural pin (grep) keeps `LanguageModelSession`/`respond(` out of `DeviceActionParsing`.
- **Never a past date, never a guess.** The resolved value passes the SAME three guards (`isPastDue`, `isEarlyMorning`, `isNextMorning`) the model's value passes. A user message with no detectable date leaves the reminder dateless — the honest state today.
- **The card is the review point.** No new UI. The confirmation card already shows the due; a user who sees the wrong day edits it there (the `resolveEditedDate` path is unchanged).
- **The instrument must see the source.** `createReminder due raw="…" bareClock=… parsed=…` gains `source=model|userText|none`; `score-due-omission.py` reports `populated-future` split by source. A rate that cannot say where the date came from cannot say the fix did anything (the "instrument the error path" rule).
- **Measurement discipline (#215/#343/#398-A):** the instrument calls `beginTurn()` per trial (it already does); every rate carries build, `osVersion`, thermal; Debug install on the phone; the sim cannot generate on this model, so bars 340-U-C/D are device-only.
- **Gate + merge protocol:** worktree isolation; RED-first with the mutation named per bar; `TALARIA_SIM_NAME=CC-lane-N scripts/mac/lane-gate.sh`, ≤ 3 booted; positive `GATE: PASS`; merge on green; RESULT block in entry 340.
- **Plan-authored code is unreviewed code.** The sketches below are INTERFACES. Task 0 measures the two premises this plan rests on before any bar is pinned; if either fails, stop and file.

## Decisions for Owen (defaults this plan builds unless he overrules at session start — one AskUserQuestion round)

1. **Narrow trigger (recommended):** the fallback fires only on an EMPTY model argument. Alternative: also fire when the model's value fails to parse (`unreadable`). Measured `unreadable` is rare and pooled into wrong-value; the narrow trigger keeps the A/B clean.
2. **Two dates in one message** ("remind me tomorrow to call about Friday's meeting"): take the EARLIEST future date (recommended — the reminder is what happens first) and log the candidate count. Alternative: refuse to guess when there are two, stay dateless.
3. **Time-only phrases** ("remind me at 4"): after `NSDataDetector`, run `parseBareClock` over the message's tokens and resolve with `resolveBareClock` (next occurrence) — recommended, it is the exact parser Owen already ruled in. Alternative: `NSDataDetector` only.
4. **Scope:** reminders only (recommended). Calendar creates always carry a start (an event without one is not a request the model makes); alarms carry a time by construction. Extending to calendar is a follow-up lane if the instrument ever shows an omission there.
5. **A dateless reminder when the words carry no date:** stays dateless (recommended; the honest state). Alternative: default to "today at 09:00" — rejected by the entry's own history (every default arm produced stale or wrong values).

## Session contract

1. Read `OPEN_ITEMS.md` entry 340 in full (the 08-15 falsifications, the 08-18 route ruling, 340-H5′, 340-PROMOTE, 340-P-D). Pre-register bars 340-U-A..E in the entry, in the shape below, BEFORE Task 0.
2. Task 0 first, alone. Its output decides whether the bars stand as written.
3. One worktree lane (Opus), RED-first, mutations named per bar, gate, merge on green, RESULT block. Fable only for a falsified bar.
4. The device run is a runbook card (§05 instrument runs, Debug build, unattended). Owen's evening.

## File structure

**Modify:**
- `Talaria/Services/Live/DeviceTools/DeviceActionTools.swift` — `DeviceActionParsing.detectDue(in:now:)` (new, in the existing `enum DeviceActionParsing`, `:119-297`); `ReminderCreateTool.call` (`:381`) passes the relay's turn text; `performCreate` (`:396`) gains the fallback branch + the `source=` field on the #249 instrument line (`:423-425`).
- `Talaria/Services/Live/DeviceTools/DeviceToolBelt.swift` — `ToolEventRelay.beginTurn(userText:)` (`:207`) stores `private(set) var currentTurnUserText: String?`; cleared on `beginTurn` so a stale message can never resolve a later turn's date.
- `Talaria/Services/Live/LocalChatBackend.swift` — `beginToolTurn()` (`:660`) becomes `beginToolTurn(userText:)`; `send` and `streamTurn` pass the user's message (the bare `message`, not the composed prompt — attachments and memory prefixes must not donate dates).
- `Talaria/Services/Live/InstrumentRegistry.swift` (`:549`) + `LocalChatBackend+Battery.swift` — the `armed-nofallback` DEBUG cell (the mutation arm), wired and PINNED as wired (the deleted `bareClockBatteryCells` had zero call sites for two weeks; a cell nobody dispatches measures nothing).
- `scripts/mac/score-due-omission.py` — parse `source=`; report `populated-future` by source; the fixture test `scripts/mac/score-due-omission-test.py` (or the existing test shape) gains a line with the new field and one WITHOUT it (old archives must still score).

**Test:**
- `TalariaTests/DeviceActionParsingDetectDueTests.swift` (new) — 340-U-A.
- `TalariaTests/ToolTurnUserTextTests.swift` (new) — 340-U-B, including the source-witness pins for `send`/`streamTurn`.
- `TalariaTests/DueDateBatteryCellsTests.swift` — the `armed-nofallback` cell is registered and dispatchable.

## Bars (paste into entry 340 before Task 0)

- **340-U-A — the parser (unit, deterministic).** `detectDue(in:now:)` resolves each phrasing in Task 0's measured list to a FUTURE date with the asked clock time; returns `nil` for text with no date; never returns a date ≤ `now`; the bare-clock second pass resolves "at 4pm" / "at 16:30". Mutation: return `nil` unconditionally → every resolving row reds; drop the future guard → the past-date row reds.
- **340-U-B — the seam.** `ToolEventRelay.beginTurn(userText:)` carries the text and `beginTurn()` clears it; `ReminderCreateTool` reaches it; source-witness pins prove `send` and `streamTurn` pass `message` (not `promptText`). Mutation: stop passing it in `send` → the witness pin reds.
- **340-U-C — the number (device, the `due-date` instrument, `armed` cell, n=40).** `populated-future ≥ 34/40` (from 18/40 on the promoted text), `wrong-value = 0/40` (unchanged), `already-past = 0`, and the new `source=userText` column ≥ 12/40 (the fix has to be visibly doing the work, not the model getting lucky). Prediction written first: the residual omissions are exactly the prompts whose text carries no date phrase (Task 0 lists them).
- **340-U-D — the mutation arm (same run).** `armed-nofallback` on the same 40 prompts: `populated-future` back in the 08-27 band (≤ 24/40) — the A/B that proves the delta is the fallback and not a model drift between runs. Bar: `armed − armed-nofallback ≥ 10` populated-future, Fisher p < 0.05.
- **340-U-E — the honesty half is closed by construction.** On the `armed` cell, every reply that names a time for a reminder whose card carries a date is counted `claimTrue`; the count of `claimedTimeCardDateless` (the entry's founding artifact) must be 0 on prompts that carry a date phrase. Scored from the transcript + the instrument line, not from the model's prose alone.
- **340-GATE.**

## Task 0: Measure the two premises (no production code)

**Files:** `TalariaTests/DeviceActionParsingDetectDueProbeTests.swift` (temporary; deleted at the end of the lane), `scripts/mac/run-instrument.sh` (read only).

- [ ] **Step 1: Read the instrument's prompt set.** `LocalChatBackend.dueDateBatteryCells` and the prompts `runDueDateBattery` sends. List, per prompt, the date phrase it carries ("tomorrow at 4", "at 9am", none). Write the list into the RESULT block skeleton. Bar 340-U-C's prediction is derived from it: prompts with no phrase cannot resolve and must be excluded from the `≥ 34/40` numerator's expectation — if more than 6 of 40 carry no phrase, the bar is re-pinned BEFORE the run, not after.
- [ ] **Step 2: Probe `NSDataDetector` on the sim, printing, not asserting.** For each phrase in the list plus the plan's own set ("tomorrow at 4pm", "at 4:30", "in 20 minutes", "next Tuesday 9am", "tonight", "this evening at 7", "on Friday", "at 4"), print `date`, `duration`, and whether the result is in the past relative to `Date()`. Record two things the plan cannot know from documentation: (a) whether a bare "at 4" resolves at all, (b) whether a bare clock resolves to TODAY even when already past (the existing `resolveBareClock` next-occurrence rule then applies). `NSDataDetector` has no reference-date parameter — tests assert RELATIONS to `Date()` captured in the same second, never absolute dates.
- [ ] **Step 3: File the probe output** in entry 340 as a dated block. If `NSDataDetector` resolves fewer than half of the instrument's date-bearing prompts, STOP: the plan's premise is falsified and the consequence (a hand-rolled relative-date grammar, or no lane) goes to Owen.

## Task 1: `DeviceActionParsing.detectDue(in:now:)` (bar 340-U-A)

**Files:** modify `DeviceActionTools.swift` (`enum DeviceActionParsing`); create `TalariaTests/DeviceActionParsingDetectDueTests.swift`.

**Interface:**
```swift
extension DeviceActionParsing {
    /// The date the USER'S OWN WORDS name, or nil. NSDataDetector first; then the
    /// bare-clock parser over the message's tokens, resolved to the next occurrence.
    /// Never returns a value ≤ `now`. Deterministic; no model.
    nonisolated static func detectDue(in userText: String, now: Date = Date()) -> Date?
}
```

- [ ] **Step 1: RED tests** — one row per Task-0 phrase that resolved (assert `hour`/`minute` and `> now`), a no-date row (`nil`), a past-clock row ("at 4pm" typed at 17:00 → tomorrow 16:00 — construct via `now`), a two-dates row per decision 2, and the structural pin (no model token in the file).
- [ ] **Step 2: Run — RED** (symbol missing). **Step 3: Implement** minimal. **Step 4: GREEN + the named mutations.** **Step 5: Commit** `340-U-A: detectDue — the user's words, deterministically`.

## Task 2: The per-turn seam (bar 340-U-B)

**Files:** modify `DeviceToolBelt.swift` (`ToolEventRelay`), `LocalChatBackend.swift` (`beginToolTurn`, `send`, `streamTurn`); create `TalariaTests/ToolTurnUserTextTests.swift`.

- [ ] **Step 1: RED tests** — `relay.beginTurn(userText: "remind me at 4")` then `relay.currentTurnUserText == "remind me at 4"`; a second `beginTurn()` clears it; source-witness pins (the `backendFunctionBody(from:)` shape `MemoryInjectionTests` uses) that `send(` and `streamTurn(` call `beginToolTurn(userText: message)`.
- [ ] **Step 2: RED. Step 3: implement.** `beginTurn(userText: String? = nil)` so every existing caller (the instruments' per-trial `beginTurn()`) compiles unchanged and clears the field. **Step 4: GREEN + mutation** (stop passing in `send` → witness reds). **Step 5: Commit.**

## Task 3: The fallback in `performCreate` + the instrument line (bar 340-U-C's mechanism)

**Files:** modify `DeviceActionTools.swift` (`ReminderCreateTool.call`, `performCreate`), `scripts/mac/score-due-omission.py` + its fixture test.

- [ ] **Step 1: RED tests** — `performCreate(rawTitle:"call mom", rawDue:"", userText:"remind me tomorrow at 4pm to call mom", …)` stages a card whose due is tomorrow 16:00 (use the `ToolConfirmationCenter` test seam the existing `performCreate` tests use); with `rawDue:"16:30"` and a DIFFERENT user text, the model's value wins (decision 1 pinned); the instrument line carries `source=userText` / `source=model` / `source=none`.
- [ ] **Step 2: RED. Step 3: implement** — `let parsedDue = explicitDue ?? resolvedBareClock ?? (rawDue.isEmpty ? DeviceActionParsing.detectDue(in: userText, now: now) : nil)`; the three guards run on the result unchanged. **Step 4: scorer** — parse `source=` (absent on old archives → `legacy`), report `populated-future` by source; fixture test with both line shapes. **Step 5: GREEN + mutations** (fallback disabled → the tomorrow-4pm row reds; scorer without the field → fixture reds). **Step 6: Commit.**

## Task 4: The `armed-nofallback` cell (bar 340-U-D's arm)

**Files:** modify `InstrumentRegistry.swift`, `LocalChatBackend+Battery.swift`; test `DueDateBatteryCellsTests.swift`.

- [ ] **Step 1: RED test** — the cell name is in `dueDateBatteryCells`, the registry dispatches it, and it runs with the fallback disabled via a DEBUG-only relay flag (`ToolEventRelay.disableUserTextDueFallback`), never by a second copy of `performCreate` (the "two structs, one engine" discipline — and the deleted `Bareclock` copy's lesson: pin the call site, not the declaration).
- [ ] **Step 2–5:** RED → implement → GREEN → commit. The flag is `#if DEBUG`; a Release grep pin proves production cannot reach it.

## Task 5: Gate, PR, RESULT block, runbook card

- [ ] `xcodegen generate` (new test files); `TALARIA_SIM_NAME=CC-lane-N scripts/mac/lane-gate.sh`; merge on green; RESULT block for 340-U-A/B + the mechanism of C/D/E; `ota-stage.sh main Debug` (the instrument needs a DEBUG install — the §05 rule); a §05 runbook card: `run-instrument.sh --device whoGoesThere --instrument due-date --cells armed,armed-nofallback --trials 40`, same-day `log collect`, `score-due-omission.py --start/--end` (the #416-G window — cell names are not unique across instruments).

## DEVICE EVENING (Owen's hands)

One unattended run, ~15 min, Debug build, phone unlocked, Verbose ON, thermal read before/after. Claude scores 340-U-C/D/E from the artifact + archive. **Stop rule:** if `populated-future` on `armed` is < 34/40 the bar is MISSED and the residual prompts are listed verbatim — a missed bar is a falsification, not a redefinition; the consequence (widen the parser, or accept the residual) is Owen's.

## Self-review (at plan-writing time, 2026-09-04)

- The seam exists and is called at the top of both turn paths (`beginToolTurn`, `LocalChatBackend.swift:660`; `ToolEventRelay.beginTurn`, `DeviceToolBelt.swift:207`) — verified by reading, not recalled.
- The tool reaches the relay (`ReminderCreateTool.call` uses `relay.started/completed`) — verified.
- No `NSDataDetector` exists in the tree — verified (zero hits). Its behaviour on the phrasings is the plan's one unmeasured premise and is Task 0, not an assumption.
- The instrument and scorer exist and already carry the #249 line the fallback extends — verified (`score-due-omission.py:47-48`, four buckets at `:228-247`).
- What this plan does NOT claim: that the model will stop claiming a time on a reminder whose words carry none (340-E is ruled out; 340-U-E scores only the prompts that carry a phrase).
