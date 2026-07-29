# T27 #200R — replicate #200Q, and find out which half did the work

**Owen is home and corded again, so this deploys via the Xcode bridge rather
than OTA. Owen routed the lane ("lets continue").**

## Two questions, one run

**#200Q passed every bar** — remind 10/10 with zero-tool stalls at zero against
a control at 8/10 with two, alarm 10/10, calendar within tolerance — exactly as
the schema-contradiction hypothesis predicted. **And it collapsed grabs 10/10 →
1/10**, with seven of ten treated haiku trials calling no tool at all. That
second result was not predicted by anything.

Two things must happen before it can be promoted:

1. **Replication.** #200P produced a perfect cell with its specimen at zero and
   evaporated on re-run. An unpredicted nine-trial swing earns *more*
   scepticism, not less.
2. **The confound.** `includesSchemaInInstructions` is true, so the tool renders
   its schema INTO the instructions. Changing two field types therefore also
   changed the instructions text. #200Q cannot tell which one moved the model.

## The separating arm

The flag governs only whether the schema is **described in the instructions** —
the schema still constrains decoding either way. So `armed-schemaquiet` is
#200Q's tool with the description suppressed, one flag on top of that cell and
nothing else:

- **grabs stay collapsed** → the effect is the **decode constraint**, and the
  instructions text is irrelevant to it
- **grabs rebound toward control** → the effect was the **instructions text**,
  and "optionality" was never the mechanism

Either answer is worth having before a promotion, because it decides whether the
follow-on work is schema-shaped (extend optionality to the calendar tool's
`location`/`durationMinutes`) or prose-shaped (the rendered schema is just
another instructions surface, and we have been writing instructions all week).

## Cells

`schemaMechanismBatteryCells = [.armed, .armedSchemafix, .armedSchemaquiet]` ×
4 prompts × n=10 = **120 trials**. Diagnostics → "Schema mechanism n=10 (120)".

`armed-schemafix` is #200Q's cell **verbatim**, so its arm IS the replication.

## Bars

**Replication half** (`armed-schemafix` vs `armed` in this run):

- remind **≥ control + 3, OR 10/10 with zero-tool stalls at zero** (ceiling-aware)
- grabs **≤ half** control's — #200Q's 1/10 vs 10/10 is a large effect; half is
  the least that counts as reproducing it
- alarm **10/10**, calendar **not worse than control by more than 3**

**Mechanism half** (`armed-schemaquiet`, reported not gated): its grab rate
against the other two arms is the answer. No promotion rides on it — it tells us
where to work next.

**If the replication half clears, the promotion is the optional-field schema**
on the #200D/#200G/#200K/#200O pattern: production types change, the pinned
rollback becomes the old required-field struct, and the promoted cell becomes
the next run's pooled re-verify.

## Protocol

Corded: `git -C <main-checkout> fetch && checkout --detach origin/<branch>` →
`RunProject(tabIdentifier: "windowtab1", attachDebugger: false)` → Owen taps the
button, foreground, on power, hands off. Classification from the run-JSON export
as usual (the console bridge is available again but the export has been
sufficient all week).

Cool the device first — #200P's 7-error cascade came after ~800 trials in a day,
and today has already run four batteries.
