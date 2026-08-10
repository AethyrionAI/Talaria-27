# FABLE T27-299 — the adoption merge duplicates in-app assistant rows

> **✅ RAN 2026-08-10, ALL BARS MET** — lane `claude/t27-299-adoption-identity`,
> `ChatStore.serverIdentityAdoptions` (turn-anchored adoption; §2's shape
> confirmed, with a `Message.id`-is-`let` refinement recorded in the entry).
> Results, verbatim REDs, and the 282-D/E read live in OPEN_ITEMS #299/#282.
> §1's "RED test already in the tree" is resolved: the baseline now pins the
> clean array. #282 is unblocked.

**Item:** OPEN_ITEMS **#299**. **Sequencing (Owen's ruling, 2026-08-09 decision
pass): this lane runs FIRST — #282's ruled guard lands only after this does,
and bars 282-D/282-E get RE-READ against the fixed merge.** Written 2026-08-10.

## 1. Verified state (from #299's entry — measured, not inferred)

- **The measurement exists and is a RED test already in the tree:**
  `ChatStorePersistenceTests.theHermesReconcileMergeBaselineBeforeScopingTheClaim`,
  run against unmodified production at `12ed25b`:
  `["Q1", "A1", "Q2", "A2", "A1", "A2"]` — every in-app-born assistant row
  duplicates on reconcile. User rows survive only because the content-claim
  tier absorbs them (the tier #282's ruling narrows).
- **Mechanism (one line of scope):** `ChatStore.unconfirmedLocalMessages`'s
  tier 3 is `.user`-only. A `.hermes` row born in-app has NO tier: tier 1
  misses (client `UUID()` vs host `stableMessageID`, #237), tier 2 misses (no
  `clientMessageID` in the gateway transcript, #248), tier 3 is `.user`-only.
  The row appends at the tail (`ChatStore.swift:2741` at filing) and
  `dedupingAdoptedEchoes` can't collapse it (timestamp is in its key;
  phone clock ≠ host clock).
- **Bounded, measured:** `theHermesReconcileMergeDoesNotCompoundAcrossASecondFetch`
  — second reconcile changes nothing (`stableMessageID` is deterministic).
- **Reachability:** everyday stall-recovery on any in-app thread with history.
  Drawer-reopened threads are immune (tier 1 holds) — why it went unreported.

## 2. Fix direction (the entry's own, and Owen's ruling leans on it)

**Give locally-born assistant rows a server-derived identity at adoption** —
when the merge confirms a turn, the local `.hermes` row adopts the host's
`stableMessageID` (the same id the row would carry if reopened from the
drawer). That closes #299 AND removes #282 case (b)'s root, which is why the
sequencing ruling put it first. **The lane verifies this shape at HEAD before
building** — an alternative (extending a tier to `.hermes` rows by content
claim) re-imports the demand-side problems #282 exists to narrow; do not take
it without a written reason.

## 3. Bars — copy into #299's entry BEFORE the run (the convention)

- **299-A (RED→GREEN):** the baseline test flips — merged
  `map(\.content)` == `["Q1","A1","Q2","A2"]`, no duplicates. The RED half is
  already proven (it's the filing measurement).
- **299-B:** `theHermesReconcileMergeDoesNotCompoundAcrossASecondFetch` stays
  green — boundedness survives the fix.
- **299-C:** a drawer-reopened thread (rows already carrying stable ids)
  merges identically before/after — tier 1's path untouched.
- **299-D:** adopted identity survives persistence — save → cold load →
  re-reconcile: still no duplicates (the #277/#278 corruption family's
  standard round-trip check).
- **299-E:** `GATE: PASS` (units + XCUITest + Release), counts MOVED.

## 4. Task breakdown

1. Re-verify the mechanism at HEAD (`unconfirmedLocalMessages` tiers, the
   append site, `dedupingAdoptedEchoes` key) — line numbers above are as-filed;
   ChatStore churns weekly.
2. Implement adoption-time identity; smallest diff that makes 299-A pass.
3. Run 299-A..E. 4. Close-out per the ratified rule: #282's entry gets a dated
   note that its lane is unblocked; bars 282-D/E re-read (their PREDICTED-RED
   was written against the duplicating merge and may no longer hold).

## 5. Traps

- **Do not touch the content-claim tier here** — that is #282's ruled,
  separately-dispatched change (`dispatch/OPUS-T27-282-claim-demand-scope.md`).
  One lane per mechanism; the sequencing ruling exists so these don't blend.
- The baseline test is the lane's OWN red — do not rewrite its fixture to make
  it pass; the fixture (in-app-born two-turn thread, host view with stable ids,
  no `clientMessageID`, host-clock timestamps) IS the defect's shape.
- `timestamp` stays in `dedupingAdoptedEchoes`' key — loosening it is a
  different, riskier fix with #278-family blast radius. Not this lane's call.

## 6. Owen's to decide

Nothing pre-registered — the scope ruling and sequencing are already his
(2026-08-09). If implementation forces a choice the entry doesn't cover,
report and stop rather than widening.
