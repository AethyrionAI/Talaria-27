# T27 #200P — the conserved stall, treated as a class

**Owen routed the merge of #180 and this lane ("merge and prepare the next /
iterate if needed"). Grabfix is NOT iterated: #200O was a clean negative and
re-labelled the disease as routing, which the existing router probe already
measures for free. Off-LAN: OTA Debug staging, run-JSON export.**

## The disease

Zero-tool interrogation is the last thing standing on the remind path. In
#200O it took **12 of 30 remind trials** — every one of them the model asking
instead of calling:

> Before I set this reminder, could you let me know which list I should add it to?
> I can set a reminder for that. Do you want it to be today, or a different date?
> Would you like to specify a due date or reminder list?

And it is **conserved**. #200K's datefix cell closed the date question and the
model started asking about the list instead — same count, different field. So a
field-by-field clause relocates the stall rather than removing it, and this
lane treats the class.

## Why it cannot just restate #200D

The promoted destall clause ALREADY says "never ask which list, which calendar,
or for other optional details first; leave optional fields empty and the
defaults apply". It is demonstrably ignored ~40% of the time in a bad run.
Repeating a prohibition that is already being ignored is not a treatment.

What DID work, twice, is naming the confirmation card: #200J killed card
narration outright (3 → 0) by naming the card as the thing the model was
standing in for. So this clause gives the question somewhere to go instead of
being asked:

> A missing detail is never a reason to ask first — create it with the default
> and let the confirmation card be where the user changes it.

`includeCardCorrectionClause`, default FALSE, seated after the promoted
dead-end carve-out.

## Cells

`stallfixBatteryCells = [.armed, .armedStallfix]` × 4 prompts × n=10 = **80
trials**. Diagnostics → "Stallfix battery n=10 (80)".

## Bars — WITHIN-RUN deltas only, and that is now a rule

#200O settled this: its three cells landed on **exactly 6/10 remind on three
different instruction texts**, and pooling across runs would have indicted the
freshly-promoted carve-out at p≈0.017 on what was purely a run-level swing.
**Only same-run arms are trustworthy.** Every bar below is a delta against the
control cell in this same run:

- remind **≥ control + 3**
- zero-tool stall trials in the treated cell **≤ half** the control's
- alarm **10/10**
- calendar **not worse than control by more than 3**
- grabs **not worse than control by more than 3**

## Also run: the router probe (free, no new code)

`runRouterProbe` already exists and its probe list already contains **"Write a
haiku about sledding" with expected = toolless**. Tapping "Router probe n=20
(200)" therefore measures the router's haiku miss rate directly — which is the
number that decides how much the ~79% armed-construction grab rate actually
matters, since production is armed-routed and a grab requires a router miss
first. #200O re-labelled grabs as a routing failure; this is the measurement
that follows, and it costs one button press.

## Protocol

Unchanged: auto-accept gate, `[T27-battery]` marker, per-trial reap, 35s
guillotine, foreground + on power, hands off. Rates from RAW TEXT; a create =
`confirm=accepted` + its artifact; exclusions listed AND adjudicated
instrument-vs-disease.

**Watch item:** #200O produced the first reap gap in ten runs (42 accepted
`createReminder` calls counted vs 43 swept, safe direction, ERROR-trial record
truncation suspected). If the gap recurs here, the trial-record write on the
tool-throw path is the suspect and gets its own fix.

Deploy: `scripts/mac/ota-stage.sh claude/t27-200p-stallfix Debug`, install from
Safari at `https://owens-mac-mini.tail5663a6.ts.net`.
