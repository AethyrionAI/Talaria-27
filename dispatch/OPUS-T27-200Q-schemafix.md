# T27 #200Q — the stall's structural seam: stop requiring what we tell it to omit

**Owen routed this ("merge and keep going"). Off-LAN: OTA Debug staging,
run-JSON export.**

## Why wording was never going to work

The conserved stall is 0-for-2 on instruction treatments and 0-for-3 counting
tool-text: #200B's guidefix (rewrote the `@Guide` texts) was falsified, #200K's
datefix relocated it (date question became list question, same count), and
#200P's stallfix hit a perfect 10/10 once and then did not reproduce on a
rested device. Five lanes have thrown words at it.

Here is the reason words cannot reach it. `ReminderCreateTool.Arguments`
declares:

```swift
var title: String
var due: String       // NON-optional
var list: String      // NON-optional
```

`@Generable` derives the tool's schema from those declarations, so `due` and
`list` are **REQUIRED fields**. Production has therefore been telling the model
two contradictory things at once:

- the promoted #200D clause: *"never ask which list … leave optional fields
  empty and the defaults apply"*
- the schema it is decoding against: *both of these fields are required*

**When instructions and schema disagree, the schema is the harder constraint** —
and asking the user is a perfectly rational way to obtain a value the contract
demands. That predicts exactly what we see: the model asks about `list` and
`due`, the two required-but-undefaultable fields, and never about anything else;
and the single-field alarm tool has sat at 10/10 in **every cell of every run
all program**.

## The treatment — one type change, nothing else

`ReminderCreateToolSchemafix` is `ReminderCreateTool` with:

```swift
var due: String?      // optional in the SCHEMA
var list: String?
```

Everything else is byte-identical and pinned that way: the tool `name`, the
production `description` (this is NOT #200B's toolfix under a new name), the
`@Guide` texts verbatim (they read "or empty for…" correctly either way), and
the create flow — the body reuses `ReminderCreateTool.performCreate` with
`?? ""`, so an omitted field lands on exactly the path an empty string took.
`title` stays REQUIRED: the schema should demand what the tool genuinely cannot
default.

**So the only thing that reaches the model is whether the schema requires the
two fields it is being told to leave empty.**

Bonus, if it works: this also removes two of the fields whose absence produces
the `ToolCallError` argument-decode class filed in the tool-throw audit.

## Cells

`schemafixBatteryCells = [.armed, .armedSchemafix]` × 4 prompts × n=10 =
**80 trials**. Diagnostics → "Schemafix battery n=10 (80)".

## Bars — within-run deltas, ceiling-aware (both hard-won)

- remind **≥ control + 3, OR treatment = 10/10 with zero-tool stalls at zero**
  (the #200P lesson: a +K bar is unmeetable when the control sits at 8/10)
- zero-tool stall trials **≤ half** the control's
- alarm **10/10** (a schema change touching the belt must not disturb the one
  metric that has never regressed)
- calendar and grabs **not worse than control by more than 3**
- **and it must reproduce**: #200P proved a single perfect cell is not a
  result. A clear pass here earns a confirmation run, not a promotion.

## Protocol

Unchanged, plus the two additions this day earned: **cool the device between
batteries** (#200P's 7-error cascade came after ~800 trials), and adjudicate
every exclusion instrument-vs-disease.

Deploy: `scripts/mac/ota-stage.sh claude/t27-200q-schemafix Debug`, install from
Safari at `https://owens-mac-mini.tail5663a6.ts.net`.
