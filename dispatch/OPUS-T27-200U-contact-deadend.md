# T27 #200U — the "Sam" dead-end: fix the tool RESULT, not the prose

**Owen routed this ("lets go after the sam dead-end next then"). Corded, WITH
DEBUGGER ATTACHED (jetsam protocol), classified live from the console bridge.**

**Bars are written here BEFORE any data exists.** Branched off the #200T tip so
the two lanes cannot conflict on the cell enum or OPEN_ITEMS; merging PR #185
first makes this PR's diff show only its own commits.

## The disease, measured

#200T pinned it: **4 of the 5 calendar misses across both arms were the "Sam"
lookup dead-end**, verbatim —

- control t7: *"I couldn't find a contact named \"Sam.\" Could you provide more
  details…"*
- treatment t3: *"I couldn't find a contact named \"Sam\" in your contacts.
  Could you confirm the name or provide additional details?"*
- treatment t8: *"…Would you like to provide an alternative name or let me know
  if this is for someone else?"*

It survives the **promoted #200O carve-out**, which already says in prose: *"If
you can't identify a person named in an event, that's fine — create the event
with the name exactly as the user gave it."* So more wording is not the answer.
Five lanes of prose failed against the reminder stall for the same reason
(#200S): **prose cannot outrank the structural layer.**

## Where the structure actually is

`ContactsTool`'s not-found path returns exactly this, and nothing else:

```swift
return "No contact matching \"\(query)\" was found."
```

A bare negative with no continuation. That string is not instructions the model
weighs against other instructions — it is **tool output the model consumes as
fact**, which is precisely the layer that beat prose in #200S.

And the second half of the observation: **`CalendarEventTool` has no attendee or
invitee field** — `title`, `startsAt`, `durationMinutes`, `location`. A contact
lookup cannot contribute *anything* to a calendar create. The tool that owns 4
of 5 calendar misses produces output the create tool cannot consume.

## Two arms, two different questions

**Arm A — `armed-deadend2` (the PROMOTABLE fix).** One seam on `ContactsTool`:
`var continuesAfterNoMatch: Bool = false`, and the not-found text becomes

> "No contact matching \"Sam\" was found. This does not block anything — if the
> name came from a request to create something, continue with the name exactly
> as the user gave it."

Production default is `false`, so the shipping belt stays byte-identical until a
verdict promotes it; promotion is flipping one default, and the rollback is
flipping it back. Same seam shape as `includesSchemaInInstructions` (#196).

**Arm B — `armed-nocontact` (the CEILING probe).** `lookupContact` removed from
the belt entirely. If the model cannot call it, it cannot dead-end into it. This
is **not** proposed for production — dropping a useful tool globally is a product
regression — it exists to bound the win: it answers *"how much of the calendar
loss is caused by this tool being reachable at all?"*

`deadend2BatteryCells = [.armed, .armedDeadend2, .armedNocontact]` × 4 prompts ×
n=10 = **120 trials**. Diagnostics → "Contact dead-end n=10 (120)".

## Bars — within-run, ceiling-aware, set before the data

**CO-PRIMARY 1 — the disease count, which is the sharper instrument.** At n=10 a
rate carries roughly ±1.5 trials of noise; the dead-end **count** does not.
Pre-registered: **Arm A must show ZERO dead-end misses**, or at most **half** the
control's count. This is the measure the lane lives or dies on.

**CO-PRIMARY 2 — the calendar rate.** Arm A **≥ control + 2**, OR **10/10 with
control ≤ 9/10**. **If the control lands 10/10 the rate comparison is
INCONCLUSIVE for want of headroom** — declared in advance, as in #200T.

**CEILING READING (Arm B), pre-registered so it cannot be rationalised later:**

- If Arm B beats the control by ≥ 2 and Arm A does not, the dead-end is caused
  by the tool being *reachable*, and the next lane is production intent-scoping
  — not more result-text work.
- **If Arm B does NOT beat the control by ≥ 2 either, the entire hypothesis class
  is falsified**: the calendar loss is not about `lookupContact` at all, and this
  seam gets abandoned rather than iterated. That would be a valuable negative and
  it gets filed as one.

**GUARDS (must hold):**

- remind **≥ 9/10 AND ≥ control − 1** — 20/20 pooled production is the program's
  biggest win.
- alarm **≥ 9/10** — never below 10/10 in any cell of any run.
- Arm B removes a read tool from **every** prompt, not just calendar, so remind
  is the number to watch there specifically.
- haiku grabs: **reported, not a gate** (#200O's router probe went 200/200).

**REPRODUCTION:** a clear pass earns a **confirmation run, not a promotion**.
#200P and #200Q both produced large effects that evaporated on re-run.

## What this lane does NOT touch

The #200T location-spiral finding (optional `location` collapsed
`currentLocation` 9/10 → 2 and `searchPlaces` 6/10 → 0, and stopped the model
stamping the home address onto a lunch event) is a **separate, post-hoc**
finding awaiting its own pre-registered run. One variable at a time: mixing it
in here would confound both.

## Protocol

Unchanged: pins RED before implementation → full suite green WITH COUNT →
file-scoped commits, OPEN_ITEMS note separate → PR, Owen merges → corded deploy
**with the debugger attached** → classify from RAW TEXT (a create =
`confirm=accepted` + its artifact; replies lie in both directions) → exclusions
listed AND adjudicated instrument-vs-disease → reap arithmetic exact → verdict as
a dated OPEN_ITEMS note, rates not verdicts.

**No Apple filing** — standing rule, and nothing here is an Apple defect: the
bare not-found string is ours.
