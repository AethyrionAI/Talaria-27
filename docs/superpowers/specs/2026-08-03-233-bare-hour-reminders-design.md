# #233 — the wee-hour bounce and the loud card (design)

**Date:** 2026-08-03 · **OPEN_ITEMS #233** (not GitHub #233 — the sequences collide)
**Decided with Owen, same morning, on the phone.** Preference order he set: ask
AM/PM (ideal) → afternoon default (fallback if asking proves too much). Card
treatment: loud wee hours, chosen from three options.

## The defect, decomposed

Trial 3 of the 2026-08-02 instrumented run: "Remind me to call Shelley tomorrow
at 4," sent 23:05, produced a REAL reminder due Aug 3 **4:00 AM** (verified in
the store by trial 7). Three halves, three homes:

1. **Model half:** the on-device model rendered "at 4" as `due:
   "2026-08-03T04:00"`. The `@Guide` shows only a format example — no
   disambiguation rule.
2. **Tool half:** `createReminder` receives a fully-qualified time — **the tool
   never sees "bare hours,"** only suspicious results. This kills the entry's
   literal "refuse bare hours back to the model" candidate; the buildable form
   is *refuse suspicious results once*.
3. **Card half:** the #29 confirm card renders "Aug 3, 2026 at 4:00 AM" in small
   monospaced text; the AM was present, undifferentiated, and approved past at
   11 PM.

## Decision: tool-side wee-hour bounce + conversation latch + forge-amber card

### The bounce

In `ReminderCreateTool.performCreate`, after `DeviceActionParsing.parseDateTime`
and **before any card is staged**: if the parsed due falls in **00:00–06:59
local** and the conversation's early-morning ask has not been issued, set the
latch and return — as ordinary tool output, never a throw (#197's rule) —

> "The due time reads as 4:00 AM — early morning. Ask the user whether they
> meant AM or PM, then create the reminder with the time they confirm."

The model relays the question; the user's answer arrives next turn; the model
re-calls with the confirmed time.

- The check lives in the shared `performCreate` engine, so the DEBUG twins
  (`ReminderCreateToolRequiredFields`, `ReminderCreateToolGuidefix`) inherit it
  identically — structural-identity discipline; battery cells stay comparable
  to each other, not to pre-#233 runs.
- The bounce is an **executed** call (post-`relay.started`): bounded by #225's
  per-turn and same-tool caps, invisible to #232's `refusalsThisTurn` — no
  interaction with the cut. (Bar 233-B pins this.)

### The latch

One flag, **conversation scope**: NOT reset by `beginTurn()` (the ask/answer
round-trip spans two turns), cleared when a fresh chat starts. It rides the
session-scoped tool state (governor or relay — the exact seam is a plan
decision; either way it is pinned by its own test, including the
fresh-conversation clear).

**Why the design is safe on a 3B model — the degradation ladder.** Model asks →
Owen's preferred behavior. Model silently re-calls with 16:00 → the stated
fallback (afternoon default). Model stubbornly re-sends 04:00 → the latch
admits it and the amber card catches it. Every failure mode lands on an outcome
Owen approved. Cost accepted: an explicit "remind me at 5 AM" bounces once per
conversation.

### The card

`performCreate` passes a caution to `requestConfirmation` when the **staged**
due is early-morning; `ToolConfirmationCard` renders it as a forge-amber row
(`Design.Brand.forge`, HUD conventions — themes resolve per palette):

> ⚠ EARLY MORNING — 4:00 AM

Normal times render byte-identically to today. Honest boundary: the caution is
computed at staging time; hand-editing the card's due field into the wee hours
does not add it live (deliberate — the user typed it).

## Bars — mirrored into the OPEN_ITEMS #233 entry before the lane runs

- **233-A (mechanical, sim):** wee-hour due (hour 0–6), latch clear → bounce
  string, no card staged, latch set; hour ≥ 7 → stages normally; latch set →
  same wee-hour due proceeds to a card; fresh conversation clears the latch.
  Tests written first.
- **233-B (mechanical, sim):** the bounce increments no governor refusal count
  and no `refusalsThisTurn` — asserted against the #228 instrument counters.
- **233-C (mechanical, sim):** early-morning staged due carries the caution; a
  16:00 due carries none and renders unchanged from today.
- **233-D (device):** trial 3's prompt verbatim, sent in the evening → the
  assistant asks AM or PM; answering "PM" yields a card showing 4:00 PM and a
  store row at 16:00 (baseline: the real Aug 3 4:00 AM row). A silent 4 PM card
  without the ask also passes — the accepted fallback shape.
- **233-E (device):** explicit "remind me at 5 AM tomorrow" completes with at
  most one bounce; its card shows the caution.

## Non-goals, alternatives recorded

- **`createCalendarEvent`** has the same exposure ("meeting tomorrow at 4") —
  follow-on note in the entry, NOT built here (#230's "not a licence" shape).
- **No `@Guide` text changes.** Approach B (teach ask-AM/PM in guide text) was
  rejected: it re-opens the #200-measured clarifying-question stall and is
  unverifiable off-device. Approach C (afternoon-default guide line, "bare 4 →
  16:00") is the **recorded fallback** if device trials show the bounce
  grinding — it would *replace* the ask, so it is not stacked on top now.
- **Window stays 00:00–06:59.** Bare 7–11 ambiguity ("remind me at 9") is
  observed-only until evidence says otherwise.
- Branch `claude/t27-233-bare-hour`; TDD with RED watched; gate before PR.
