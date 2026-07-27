# OPUS-T27-176C — the session shape that refuses to write: convict it, then release it

**Items:** OPEN_ITEMS #194 (residual of #176B) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-176c-creative-suppressor` · **Toolchain:** Xcode-beta4 = **Xcode 27.0 (27A5228h)**, pinned sim
**Evidence scope:** your return MUST state the Xcode build your suite ran on (`xcodebuild -version`). If your
environment cannot build against 27A5228h, say so explicitly — a green on any other SDK is NOT a green here.
**Baseline:** confirm the current green count before you start (expected ~1231 tests / 109 suites) · `export GH_PAGER=cat` first

This is a **confirm-then-fix** lane, like #192 was: Part 1 builds the instrument, Owen's device
A/B convicts the mechanism, Part 2 ships the fix only if the conviction lands where the evidence
points. Do not skip to the fix.

## The evidence chain (all 2026-07-27, all device, airplane mode where it matters)

1. On-device creative requests refuse with a stable signature: *"I can't write a poem for you,
   but I can help you [tool-flavored deflection]"*. Reproduced across poem, sonnet, haiku, and a
   bare "write me a poem" after a greeting.
2. **The merged 176B Part A clause did not release it.** Post-merge (`a86c750`, fresh-chat IN
   1.6K→1.7K proving the new instructions were in-session), the refusal persists — while the SAME
   clause fixed factual fixation: "what's 2+2" → "The answer is 4.", "capital of Greece" →
   "Athens", offline, no tool. The factual half is a device-verified PASS and is this lane's
   **negative guard**, not its target.
3. **Length is not the variable** — a 3-line haiku refused identically to a poem.
4. **Instruction strength is not the variable** — "You're allowed to write. Write a poem about
   spring" produced a WORD-FOR-WORD identical refusal.
5. **The base model is exonerated** — Shortcuts' "Use Model" action, On-Device, same phone, same
   minute, happily wrote the haiku. Whatever suppresses creation lives in OUR session shape.

## Suspects, in order

1. **The registered tool belt itself** — a `LanguageModelSession` armed with tools may bias the
   model against non-tool turns wholesale, before instructions say a word.
2. **The prose tool enumeration inside `instructionsText`'s armed branch** — the sentence starting
   "You also have device tools — health, location, …" is REDUNDANT with the tools' native
   `Tool.description` metadata already registered on the session, and is plausibly the
   "job description" signal the model over-learns.
3. Long shots (do not chase without cause): #83's explicit `GenerationOptions`, #26 transcript
   condensation.

## Part 1 — the instrument (build this)

A DEBUG-only session-shape selector in `LocalChatBackend`, following the `UITEST_DUPID_PROBE`
seam precedent (armed by launch environment, inert in every normal run, `#if DEBUG`):

`TALARIA_SESSION_SHAPE` = one of:
- **`armed`** (or unset): production behavior, the control cell.
- **`armed-noprose`**: tools registered exactly as today; instructions armed branch WITHOUT the
  belt-enumeration sentence (keep the licensing clause, the action-confirmation sentence, the
  honesty sentence, the recovery sentence — remove only the roster).
- **`prose-notools`**: NO tools registered on the session; instructions are the armed branch
  VERBATIM, enumeration included. (Yes, this violates the "never claim a tool the session wasn't
  given" doc rule at LocalChatBackend:~1235 — it is a debug measurement cell, not a shippable
  state; say so in a comment.)
- **`toolless`**: the existing tool-less branch, tools unregistered — the far control.

Constraints on the instrument:
- The selector touches session CONSTRUCTION only — no changes to streaming, append, availability
  gating, the DUPID probe, or the #148 `offeredTools` seam's production behavior.
- Log the active shape once per session build (`chatLog.notice`) so device runs are self-labeling
  in Console.
- Tests: deterministic substring tests on the two new instruction variants (noprose lacks the
  roster but keeps all four kept sentences; prose-notools equals armed verbatim). Do not assert
  what the model chooses — the 176B precedent.

## Owen's device A/B (owed after merge; write this checklist into the PR body)

Airplane mode, fresh chat per cell, same prompt ("Write a poem about spring"), one factual probe
("what's 2+2") and one tool probe ("what does my calendar look like today" — expect an honest
tool/permission path in cells with tools) per cell. Record poem/refusal per cell. The readout:
- B writes, A refuses → **enumeration convicted** → Part 2 ships.
- C refuses with no tools registered → the prose alone suppresses (strengthens Part 2).
- B refuses but D writes → **the belt itself convicted** → Part 2 does NOT apply; report back —
  the fix becomes per-turn tool gating or a PCC escalation offer (#30 pattern), a separate lane.
- All four refuse → the suppressor is elsewhere (long shots); report back, do not guess.

## Part 2 — the provisional fix (ship ONLY the change; it stays inert until conviction)

Remove the belt-enumeration sentence from the PRODUCTION armed branch — i.e., make `armed`
equal today's `armed-noprose`. Prepare it as its own final commit clearly labeled
**"Part 2 — do not merge-cherry-pick until the device A/B convicts the enumeration"**, so Owen
can drop it trivially if the A/B says otherwise. Adjust the #148 substring anchors it breaks
(they may key on the roster text) — every other #148 anchor and its vision-gating tests stay
green, unmodified.

## HARD CONSTRAINTS

- The #176 factual fix must not regress: the licensing clause, the recovery clause, and the
  honesty sentence survive every variant. "2+2"/"Greece" answered offline is the negative guard.
- #148's vision gating and its tests: green, untouched.
- Real-data tool routing must survive: a health/calendar question still reaches its tool in every
  tools-registered cell. Turning the belt off is the failure mode, not the fix.
- Tool-less branch text: unchanged.
- No model-choice assertions in tests, no reliance on the sim having a model (it does not).

## Definition of done

- Suite green on 27A5228h, count delta stated and explained.
- All four shapes reachable by launch env, self-labeling in Console, provably inert in release
  builds (the selector reads nothing outside `#if DEBUG`).
- Instruction-variant substring tests pin the two new texts.
- Part 2 present as the labeled final commit, inert until Owen's verdict.
- PR body carries the device A/B checklist above and states what was and wasn't compiled.

## House rules

- Merge commits only, never squash. File-scoped commits.
- **OPEN_ITEMS.md edits in their own separate commit.**
- `xcodegen generate` only if Swift files are added or removed (none should be); pbxproj regen as
  its own commit; verify `aps-environment: development` survived.
