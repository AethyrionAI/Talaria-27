# T27 #200T — the same schema surgery, on the calendar tool

**Owen routed this ("lets continue"). Home and corded: Xcode `RunProject` WITH
DEBUGGER ATTACHED (jetsam protocol), classified live from the console bridge.**

**Bars are written here BEFORE any data exists.** #200S ran 120 trials against
remembered bars and that is filed as a protocol gap, not glossed. This doc
closes it for the lane it recommended.

## Why this lane, and why now

Calendar is the weakest production number: **15/20 (75%)** pooled on #200S,
against remind's 20/20 and alarm's 20/20. It is also the only production intent
whose tool still carries the exact defect #200S removed from the reminder tool.

`CalendarEventTool.Arguments` declares:

```swift
var title: String
var startsAt: String
var durationMinutes: Int        // REQUIRED in the schema
var location: String            // REQUIRED in the schema — and @Guide says "Optional location, or empty"
```

The `@Guide` text on `location` literally reads **"Optional location, or
empty"** on a field `@Generable` marks REQUIRED. That is the #200S
contradiction verbatim, one tool over — and the promoted #200D clause says the
same thing again in prose: *"never ask which list, which calendar, or for other
optional details first; leave optional fields empty and the defaults apply."*

And the battery's calendar prompt is built to collide with it:

> "Put lunch with Sam on my calendar Friday at noon"

**No location. No duration.** Two required fields with nothing in the request to
fill them. #200S proved on the reminder tool that this is a create-blocking
shape — restore the required `list` field and the model asks which list; make it
optional and it creates, 20/20 vs 7/10 in the same run.

## The treatment — two type changes, nothing else

`CalendarEventToolOptionalFields` is `CalendarEventTool` with:

```swift
var durationMinutes: Int?       // optional in the SCHEMA
var location: String?
```

Everything else is byte-identical and pinned that way: the tool `name`, the
production `description`, the `@Guide` texts verbatim, and the create flow —
both structs call one extracted `CalendarEventTool.performCreate` engine
(structural-identity discipline: two structs, one engine, as #200Q/#200S did for
reminders). `title` and `startsAt` stay REQUIRED: the schema should demand what
the tool genuinely cannot default, and an event with no start time cannot be
created.

**Omission semantics, stated in advance:**

- `location` omitted ≡ the empty string it already accepts — the existing
  no-location path, unchanged.
- `durationMinutes` omitted → **60 minutes**. A supplied value still clamps to
  5…1440 exactly as today. Omission was previously *impossible*, so this
  default is new behaviour and not a silent change: it is the humane default for
  an unspecified event, the confirmation card shows Minutes, and the user can
  edit it before anything is saved.

**This is not a confound for the measured rate.** Classification counts creates
(`confirm=accepted` + the event artifact); the duration *value* does not change
whether an event is created. It changes only what the card shows on the
treatment arm.

Bonus, as on #200S: this removes two more of the required fields whose absence
produces the `ToolCallError` argument-decode class from the tool-throw audit.

## Cells

`calfixBatteryCells = [.armed, .armedCalfix]` × 4 prompts × n=10 = **80
trials**. Diagnostics → "Calendar schema n=10 (80)".

Two arms, one run. Cross-run comparison is not admissible here (#200O landed
three cells on exactly 6/10 on three different texts); every number below is a
within-run delta.

## Bars — within-run, ceiling-aware, set before the data

**PRIMARY (calendar):** treatment **≥ control + 2**, OR treatment **10/10 with
control ≤ 9/10**.

- **If control = 10/10, the lane is INCONCLUSIVE for want of headroom** — no
  delta is measurable above a perfect control. Pre-registered so it cannot be
  re-framed as a pass after the fact. Calendar has hit 10/10 once this week, so
  this is a live possibility, not a formality.

**MECHANISM (the qualitative bar, adjudicated BEFORE the delta is claimed):**
classify every control-arm calendar miss from raw text.

- Misses that are **field interrogations** ("how long?", "where?", or the
  card-narration ask) ⇒ the schema mechanism is operating, and the treatment is
  expected to fix them. Treatment arm must show **zero field-interrogation
  misses** for a clean pass.
- Misses that are **"Sam" lookup dead-ends** (the residual disease #200O's
  carve-out only partly tames) ⇒ a different mechanism. **A null result then is
  NOT evidence against the schema hypothesis** — it is evidence that calendar's
  remaining losses live somewhere else, which redirects the next lane to the
  lookup dead-end instead of to more schema work.
- Both outcomes are informative. I will not re-label the mechanism after seeing
  the delta.

**GUARDS (must hold):**

- remind **≥ 9/10 AND ≥ control − 1** — production remind is 20/20 pooled and
  is the program's biggest win; a belt change must not cost it.
- alarm **≥ 9/10** — it has never regressed below 10/10 in any cell of any run;
  one miss gets adjudicated instrument-vs-disease before it is scored.
- haiku grabs: **reported, not a gate.** The router probe went 200/200 and sends
  the canary toolless 20/20, so armed-construction grab rates are not
  user-facing (#200O closed that lane by measurement).

**REPRODUCTION:** a clear pass earns a **confirmation run, not a promotion**.
#200P's perfect stall cell and #200Q's grab collapse both evaporated on re-run.

## Protocol

Branch from `origin/main` → this doc → pins written and watched RED → full suite
green WITH COUNT → file-scoped commits, OPEN_ITEMS note separate → PR, Owen
merges → corded deploy **with the debugger attached** (debugged processes are
jetsam-exempt; four consecutive undebugged runs died mid-battery) → classify from
RAW TEXT (a create = `confirm=accepted` + its artifact; reply text lies in both
directions) → exclusions listed AND adjudicated instrument-vs-disease → reap
arithmetic exact → verdict as a dated OPEN_ITEMS note, rates not verdicts.

**No Apple filing** — standing rule, and nothing here is an Apple defect: the
schema is doing exactly what `@Generable` documents. This is our declaration to
fix.
