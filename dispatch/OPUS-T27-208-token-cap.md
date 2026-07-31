# T27 #208 (Lane 4) — is the 1024-token cap even binding?

**Owen routed this. Bars written BEFORE any code. This run MEASURES A DISTRIBUTION
and tests no treatment — the reason is arithmetic, below.**

## The hypothesis, and why it cannot be tested head-on

Apple's own docs say a strict `maximumResponseTokens` **"can lead to the model
producing malformed results"**, and Talaria caps every on-device chat turn at
**1024** (`responseHeadroomTokens`, #102's thermal guard, deliberate). That makes
the cap the standing suspect for the **D4 corruption class** — malformed tool-call
arguments — whose specimens are on file:

- #200K: `Encountered content that cannot be completed into valid JSON. Text:
  {"term":"Sam"Sam"}<ctrl43>` on a `searchPlaces` call.
- The `readHealth` argument-decode throws that have cost trials in five lanes
  (3 in #200W, 2 in #200Z, 1 in #200O).

**If the cap is the cause, these are the same bug.**

**But the corruption rate is ~1–2% of trials.** The week plan's proposed cell —
1024 / 2048 / nil × 4 prompts × n=10 — gives **40 trials per arm and an expected
0.4–1.0 events**. **No bar can sit on that.** Running it would repeat #201's
mistake exactly: a gate demanding the disease exceed its own expected rate. To see
~10 control events you would need n≈500 per arm — roughly two hours of device time
for one comparison.

## What is cheap and decisive instead

**`response.usage.output.totalTokenCount` is available per response** (verified in
the beta-4 swiftinterface). So the prior question can be answered exactly, per
trial, at n=10:

> **Is the 1024 cap ever within reach of an actual turn?**

If typical output is 50–150 tokens and the maximum across 120 trials is nowhere near
1024, **the cap cannot be causing corruption on these prompts** — the hypothesis is
falsified for this shape at a fraction of the cost, and #102's cap is safe to leave
alone.

If some turns *do* approach the cap, a treatment cell becomes justified **and can be
sized from the measured near-cap rate** rather than guessed.

**This is the #199 sequencing, which paid off today:** measure the base rate first,
and let it decide whether the treatment lane exists at all. #199's armed-branch
honesty clause was the obvious next build until the run said 0/30.

## The open question the tokens will illuminate

The corruption specimens are in **tool-call ARGUMENT generation**, not the prose
reply. Whether `maximumResponseTokens` bounds the whole multi-step turn (tool calls
included) or only the final response text is **not documented**. If it bounds the
turn, a trial with three tool calls accumulates toward the cap far faster than its
short reply suggests — and the reply length everyone has been eyeballing is a
misleading proxy. **The recorded counts distinguish these directly:** compare output
tokens against reply length per trial, and a turn whose token count far exceeds its
prose is a turn spending budget on tool calls.

## Design

**One cell — production (`armed`), 4 prompts × n=10 = 40 trials ≈ 4 min.** Auto-ACCEPT
so tool turns behave normally and their token cost is included; artifacts reaped as
usual.

`inputTokens` / `outputTokens` are added to `BatteryTrialRecord` and captured on
**every** battery from now on, so this data accrues for free on future runs rather
than needing its own lane again.

## Bars

**PRIMARY (descriptive, no pass/fail):** the output-token distribution per prompt —
median, max, and the count of trials within 10% of the cap (≥922 tokens).

**PRE-REGISTERED READING:**

- **Max < 512 across all 40 trials** ⇒ the cap is **not binding** on any measured
  shape. **The D4-cap hypothesis is falsified for these prompts**, #102's cap stays
  untouched, and the `readHealth` decode errors need a different explanation.
  **Say so plainly and do not run the 3-arm cell.**
- **Any trial ≥ 922 (90% of cap)** ⇒ the cap **is** reachable. The 3-arm cell
  (1024 / 2048 / nil) is justified, sized from the observed near-cap rate.
- **Between** ⇒ report the headroom honestly and treat the cell as unjustified for
  now; a cap that is never approached cannot corrupt what it never truncates.

**EVALUABILITY:** ≥36 of 40 trials must record a token count. `usage` is read from
the response, so ERROR and TIMEOUT trials have none by construction — and those are
exactly the corruption trials. **That asymmetry is stated in advance:** this
instrument measures the tokens of turns that SUCCEEDED, and cannot see the token
count of the ones that broke. It bounds the hypothesis; it cannot confirm it.

**GUARD:** create rates must stay at #204's levels (remind/alarm/calendar ≥9/10). A
drop means the instrumentation changed behaviour, and that is read before anything
else.

**No Apple filing** — standing rule.
