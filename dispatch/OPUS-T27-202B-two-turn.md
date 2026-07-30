# T27 #202B — does fixing the route actually produce the create?

**Owen routed this ("Build it") off the #202A verdict. Bars written BEFORE any
code. Classified from the run JSON.**

## Why this run exists

#202A proved the router is context-blind: production misrouted **6/6** bare
affirmatives after an offer, while scoring **17/17** on everything else. Both
context framings fixed it at **13/13**, and **ctx-a** was selected on parsimony —
it changes only the prompt envelope and leaves the pinned instructions alone.

**That was the mechanism. It is not the outcome.** A correct route only restores
the belt; the model still has to *use* it, given nothing but "Yes please" and an
offer in the transcript. Every create number this program owns comes from
single-turn prompts that state their own intent. **Nothing is known about whether
an accept turn creates.** That is this run.

## The one thing this instrument must not oversell

**The control's zero is guaranteed by CONSTRUCTION, not measured.** Its turn 2
routes toolless, a routed-toolless turn registers no belt, and a session with no
`createReminder` cannot create a reminder. So a 0-vs-k table here would be
theatre.

**The informative number is the treatment arm's create rate against an ABSOLUTE
bar.** The control arm runs anyway, exactly once, to confirm end-to-end that the
predicted denial actually appears in a real conversation — a structural claim
this program has only ever verified by reading code.

## Shape

Turn 1 is a statement that invites an offer; turn 2 is a bare affirmative. The
offer **carries a fully-specified time**, deliberately: an underspecified offer
would put #200K's date-interrogation disease in the middle of the measurement and
confound it with routing.

- **turn 1:** "Ugh, I always forget to call the dentist back."
- **offer:** "Would you like me to set a reminder to call the dentist tomorrow at 9am?"
- **turn 2:** "Yes please"

**The offer is SEEDED into the transcript**, through
`LocalChatBackend.transcriptEntries(instructions:verbatimTurns:)` — the same
static, unit-pinned constructor `rebuildSession` uses to replay a stored
conversation into a fresh session. This is not a shortcut around production; it
*is* production's replay path. Seeding makes **every trial evaluable**, which
matters because this program has now filed three lanes that landed one short of
their own gate.

**Arms, in run order:**

| arm | turn-2 router | slot |
|---|---|---|
| **twoturn-ctxa** | ctx-a (context envelope) | **cool** |
| **twoturn-control** | production | warm |
| **twoturn-natural** | ctx-a, but turn 1 is GENERATED | last, ungated |

**Slot order is deliberately the REVERSE of #201B's rule, and here is why.** That
rule puts the incumbent in the cool slot so a hot control cannot manufacture a
treatment win. There is no such risk here — the control's zero is structural, so
no comparison can be inflated. The live risk is the opposite: a throttled
treatment failing an ABSOLUTE bar for thermal reasons. So the arm being measured
against the bar gets the cool slot. Warm-up runs first as always.

**twoturn-natural** generates turn 1 for real and records what the model says, so
the seeded offer can be checked against the offers the model actually makes. It is
diagnostic, **not gated** — if it disagrees with the seed, that is the finding and
the seeded numbers get re-read in its light.

## Bars

**STRUCTURAL CHECK (control):** **0 creates.** Predicted by construction, so this
is a falsification test of #202's structural claim, not evidence for the fix. **Any
create here means "routed-toolless turns register no belt" is WRONG**, which is a
larger finding than this lane and would be filed as such.

**PRIMARY (ctx-a), pre-registered as an absolute bar:** **≥ 80% creates on
evaluable trials.** Derived, not guessed: production single-turn remind is 20/20,
and #201B's remind guard held 36/40 (90%) under load. An accept turn whose create
is fully specified should approach that. **Below 80% = the route was NECESSARY but
NOT SUFFICIENT** — a real, nameable outcome that sends #202 after a second seam
rather than declaring victory.

**ROUTE CHECK (gated):** ctx-a's turn 2 must route ARMED in **≥ 90%** of trials.
Below that, the arm is not testing what it claims and the primary is void.
Expected ~100% from #202A, and recorded per trial so it can be read rather than
assumed.

**FABRICATION COUNT (#199 cross-reference, reported and counted separately):**
trials whose reply CLAIMS the reminder was set while no artifact exists. The
standing classification law is that reply text lies in both directions; this is
the other way an accept turn can fail, and creation pressure is at an all-time
high across the promoted #200 clauses. Counted, not gated.

## n, and what #202A taught about it

**n=12 per arm** (24 seeded trials + 5 natural ≈ 13 min, under the ~15–20 min
throttle threshold).

**#202A's n was ineffective and this run must not repeat that mistake.** The
router decodes greedily, so repeating one prompt re-measured one sample and all 49
rows saturated. **Turn 2 here is ordinary chat generation — `.random(0.9)`,
temperature 0.7 — so trials genuinely vary and n means what it usually means.**
The determinism trap was specific to the router; it does not apply here, and the
run JSON will show real within-arm spread if this reasoning is right. **If the
seeded arms saturate at 12/12 and 0/12, say so and treat n as unproven again.**

**No Apple filing** — standing rule.
