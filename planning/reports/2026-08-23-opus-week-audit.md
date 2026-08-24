# Audit of Opus 5's week — 2026-08-16 → 2026-08-23

**Run 2026-08-23 evening at HEAD `f718f9bb`** by three parallel read-only
auditors (clusters 08-19/20, 08-20/21, 08-22/23) plus global checks.
Scope: every commit trailered `Co-Authored-By: Claude Opus 5` in the window
— **102 commits, 31 lanes, 28 PRs (#322–#354)**. Method: claim-vs-code at
HEAD, revert-sensitivity reading of every lane's tests, device claims
checked against preserved artifacts (never against their own summaries),
sweep corrections re-executed against historical tracker snapshots,
PR/merge facts via `gh`, gate-count chain reconciled.

## Verdict

**The week's mechanisms are sound.** Every lane's load-bearing code claim
verified at HEAD; all 28 PRs merged as recorded (one, #342, legitimately
closed-superseded by #343 with no stale citation); the gate-count chain is
strictly monotonic with every step's arithmetic stated and consistent
(2351 → 2498); bars were pre-registered before code in every lane that
claimed it; mutation claims that were checked reproduced. The failures are
at the edges: **one overstated heading, one numbers-vs-artifact
discrepancy, a family of stale "PR OPEN" markers that outsmart the
invariants checker by spelling, and doc drift in repo-facing files after
#383.** Zero fabricated results. Zero mechanism claims falsified.

Counts: **FALSIFIED 1** (minor, self-inconsistent heading) ·
**DRIFT 10** · **WEAK-TEST 4** (2 already disclosed in their own entries) ·
**UNVERIFIED 2** (both accounted as inferences in the tracker itself) ·
**CLEAN 31 lanes** · plus 1 pre-existing latent bug found in passing.

## Findings that warrant correction (applied 2026-08-23, same session)

1. **#340-H5 numbers vs the preserved artifact** *(the audit's most
   substantive find)*. The result block says control no-call **5/20**
   (p = 0.047 — the table's only significant row) and "0 of **37** calls";
   the run's own preserved record
   (`planning/reports/2026-08-21-340-h5-due-date.json`) shows exactly
   **4** armed no-call trials → 36 calls, and Fisher on 4/20 vs 0/20 is
   **p = 0.106** — the significant row vanishes. The block is also
   internally inconsistent (5 no-calls ⇒ 35 total, not 37). Scoring came
   from a `log show` archive not preserved in the repo; per the
   evidence-decay rule a missing log row ≠ no call, so the relay artifact
   is the stronger record. **The bar verdict (H5 MISSED, guide not
   promoted) survives either reading; the specific counts do not.**
   → corrected with a dated block under #340.

2. **"PR #329 OPEN" survived on two corrected headers** (#302 at
   OPEN_ITEMS:7764, #323 at :8856) though PR #329 merged 2026-08-21
   (`2767ca70`) — stale 2+ days when the 08-23 sweep appended corrections
   *to those very headers* without clearing the marker. **And the checker
   built for this class is blind to the spelling**: `STALE_MERGE`
   (oi-invariants.py:63) matches only adjacent "PR open", never
   "PR #NNN OPEN". Same family: #173's "PR open; merge is Owen's review"
   for merged PR #327 evades the check a different way (its branch name
   doesn't match the BRANCH regex). → regex widened FIRST and proven to
   catch the live instances, then the three markers fixed.

3. **#302's RESULT heading overstates its own scorecard** — "302-D…G ALL
   MET, EACH PROVEN RED BY MUTATION" vs the scorecard's own 302-G line:
   "green under every mutation — which is the bar." Three of four
   mechanism bars were RED-proven; the negative control by design was
   not. → heading corrected.

4. **#397's sweep correction took the UTC day** — "BUILT + MERGED
   2026-08-23" vs git author/commit 2026-08-22 20:50 -0500 and the
   entry's own "✅ 2026-08-22" block. House rule: dates come from
   `git log`. → corrected.

5. **Repo-facing docs falsified by #383 and #375, not re-swept**:
   README/SECURITY still say the relay's remaining job is the
   realtime-voice WebRTC bootstrap (#383 moved it to the talaria plugin);
   README:163 still advertises `AGENT_FILES_DIR` "(enables in-chat
   downloads)" (#375 deleted the capability). CLAUDE.md's architecture
   section still presents `POST /api/sessions/{id}/chat` + `/chat/stream`
   as THE chat path — the runs plane has been the default since #368
   (2026-08-19), and #382 deletes the sessions turn transport Tuesday.
   → all corrected (CLAUDE.md gets a supersession note; #382's lane will
   rewrite the section properly).

> **SECOND WAVE APPLIED the same evening (Owen: "Fix the things found in
> the audit") — PR #359, squash `f1b393ac`, filed as #400.** The latent
> `midTurnSendAction` bug is fixed structurally (hand-written `encode(to:)`
> deleted; synthesized encode cannot omit a key; 400-A RED-first), the
> three unpinned wirings below (#138-B, #394, #395) got structural
> source-pins each RED-proven by unwiring its site, the #383 naming residue
> is renamed/corrected, and the scorer-test dead stanza is gone. The items
> below stand as the audit recorded them; their "filed, not fixed" status
> is superseded by that lane.

## Findings filed, not fixed (notes added to their entries)

- **#138-B pinning is pure-function-only** — `SpeakerRouteOverrideTests`
  pin the decision; unwiring either call site leaves the suite green (the
  #340 wiring shape). Low severity: the tracker's own claims are scoped
  honestly. Noted under #138.
- **#383 naming residue** — "the relay bootstrap request" comments at
  LiveVoiceSessionService:286/:969 and `VoiceState.relayBootstrapReceivedAt`
  keep the relay name post-re-home (the struct-name reuse elsewhere is
  documented as deliberate). Cosmetic; rides the next voice code lane.
- **Two disclosed weak-tests** (no action — the entries already state
  them): #394's `.task(id: scenePhase)` fix has no automated pin (retired
  394-D with reasoning + device-verified with quoted bounds); #395's
  AppContainer double-gate wiring is unpinned (entry states the limit).
- **Two accounted inferences** (no action): "OJAMD at plugin `fb2e364`"
  is a pull-then-restart ordering inference — the wire probe proves verb
  registration, not the commit — and the tracker itself files it under a
  measured-vs-inferred split; the OTA high-water seed lives server-side.
- **Side find (pre-existing, not Opus's week)**:
  `UserSettings.midTurnSendAction` is decoded but never written in the
  hand-written `encode(to:)` — a user's non-default choice silently
  reverts on relaunch. Introduced `d60e6642` (#357 3C era). Spawned as a
  background-task chip by the cluster-A auditor.

## What was verified CLEAN (per lane, at HEAD)

- **#368** runs-plane default + one-shot migration + status-read recovery
  + 12 recovery tests incl. both negative controls; close-out debt paid
  incl. archive pointers. **#369** hold-not-unpair with all three tests.
  **#375/#21** zero download residue; CLAUDE.md supersession accurate;
  the gate-TCC fix reads the bundle id from project.yml. **#302/#323**
  AppLockGate: one state, one writer, exactly three consumers, 15 tests,
  the intent bypass declared. **#310** optional relayBaseURL, nine tests,
  count arithmetic exact twice. **#173/#380** never-claim floor with the
  inverted pin. **#236** settled-text UI assertion, mutation output
  preserved. **#72/#385** PCC live; identity strings byte-pinned; device
  verification quotes the verbatim reply. **#386** policy with the dated
  Apple quotations shipped as ruled. **#388** loader seam complete (8/8
  fake-loader call sites); every device number reproduces from the
  preserved JSON. **#389/#373** the replacement test forces ordering
  (parked activation), no sleeps; five knives real. **#391** reset-date
  carried on every arm, mapping-level pin. **#395** half-gated
  demonstration real. **#372(c)** every number recomputed from the JSON
  artifact; governor discipline verified in code. **#325** forgeText,
  69 call sites, both floors enforced. **#340 route (a)** both wirings +
  the wiring-sensitive tests. **#383** bootstrap relay-free end-to-end,
  "host predates voice" arm wired, plugin verbs at fb2e364, wire probes
  QUOTED with controls. **#396-B** byte-identical default proven by test.
  **#397** both fixes present and ordered. **#399** structural
  one-spelling test on both files. **#393 calls 1/3/4** "215 call sites"
  and "36 variants" EXACT at HEAD. **#384** no default host; OTA
  high-water logic correct. **#392** instrument-only confirmed by diff;
  scorer test executed live: PASS. **The sweep** — its 14 headers
  reproduced by executing the checker against the pre-sweep tree; 12 of
  13 non-#340 corrections accurate (the 13th is the #397 date). **The
  new invariant** (296e4e85) has real teeth, proven by execution against
  three historical snapshots.

## The meta-lesson

The week's failures cluster in one class the project already names:
**asserted state rots** (#342's rule). Every mechanism was real; what
went stale was *prose about state* — PR markers, a heading, a date, docs
describing a deleted plane — and the two live instances survived because
the checker matched a spelling the tracker doesn't use. The fix applied
tonight widens the checker to the house spelling and was proven to catch
the live instances before the markers were corrected.
