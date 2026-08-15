# #93 step 4 — `primingText` vs `probe.py`'s validated phrasing

**Run 2026-08-10 on OJAMD** (the probe lives here: `C:\Users\Owen\talaria-probe\probe.py`,
3,899 bytes, last write 2026-07-09 20:50). Routed by the handoff (§5) and by
`dispatch/FABLE-T27-93-101-continuity-memory.md` §1 row 13 / §7.3 — "run the 5-minute OJAMD
comparison, or close it as not-worth-doing. Silence is the one option that is not available."

**Verdict: RECONCILED — no change required. Production's `primingText` is a faithful superset
of the probe's validated phrasing.** Every load-bearing move in the probe's PRIMING survived
into production, and production's two additions each exist for a reason the probe arm did not
have. #93 step 4 can close as DONE.

## The two texts

**Probe (`probe.py:58-66`, arm B_condensed, validated 2026-07-09 — results in
`probe_results.json` beside it):**

> "Context from an earlier planning conversation -- treat this as established background, not a
> quote to echo back. I'm managing a rooftop-garden install for Voss Bakery, due before the
> bakery's grand reopening on August 14. The roof's structural limit is 18 pounds per square
> foot, so we chose lightweight fabric planters instead of ceramic pots. The approved budget was
> raised from an initial $4,200 to $4,700 to cover an irrigation timer. Planting priority is
> culinary herbs -- basil, thyme, and rosemary. Keep this as background and answer my questions
> about the project directly."

**Production (`Talaria/Services/Support/ContextTransplanter.swift:200-207`):**

> "[CONTEXT TRANSPLANT — this is turn zero of a continued conversation.]
> The notes below carry the context of this conversation so far, from the user's device journal.
> Treat them as established conversation memory: every fact is already stated at its most recent
> corrected value. Do not re-answer or re-open anything below. Acknowledge in one short sentence
> and wait for the user's next message." + `\(body)`

## The reconciliation, move by move

| Load-bearing move | Probe | Production | Status |
|---|---|---|---|
| Established-background framing | "treat this as established background" | "Treat them as established conversation memory" | ✅ carried |
| Anti-echo instruction | "not a quote to echo back" | "Do not re-answer or re-open anything below" | ✅ carried, strengthened (also blocks re-answering, the failure the probe's Q-arms actually measured) |
| Corrections-at-latest | demonstrated narratively ("raised from an initial $4,200 to $4,700") | stated as a convention ("every fact is already stated at its most recent corrected value") | ✅ carried, generalized — right call for an automated condenser whose brief emits facts at-latest rather than narrating each correction |
| Provenance | "from an earlier planning conversation" | "from the user's device journal" | ✅ carried, more honest |
| Forward posture | "answer my questions about the project directly" | "wait for the user's next message" | △ intentionally different — see below |

**Production's two additions, both justified:** (1) the `[CONTEXT TRANSPLANT — turn zero]`
header, machine-recognizable framing the probe never needed; (2) **"Acknowledge in one short
sentence"** — the probe's arm B sent its priming as an ordinary turn and let the model reply at
whatever length before Q1; production posts priming as a standalone SSE turn whose reply is
user-visible and token-billed, so pinning the acknowledgment short is a cost/UX fix the doc
comment states explicitly (`:195-199`). The △ row is the same story: the probe primed-then-asked
in one arm's flow; production primes and *stops*, so "answer directly" would dangle.

**Nothing in the probe's phrasing was lost silently.** The one dropped clause (△) is
structurally inapplicable to production's turn-zero shape.

## Consequence for #101 (per the brief: "lands in #101's evidence base")

The A-1 routing run (device row R13) can read this as: the injected-context phrasing production
uses is not a drifted cousin of what the 2026-07-09 probes validated — it is the same three
moves, generalized for automation. Any future failure of transplant fidelity should be
investigated in the *body* (the condensed brief) or the router, not the preamble phrasing.

Also present beside `probe.py`, for whoever next opens #101: `probe2.py`/`probe3.py` and their
results JSONs (further arms, 2026-07-09 21:xx), and `verify_connector.py`. Not compared here —
step 4 as routed names only `probe.py`.
