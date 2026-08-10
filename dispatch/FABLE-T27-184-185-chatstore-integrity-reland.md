# FABLE T27-184/185 — the STRANDED ChatStore-integrity fix: rebase or re-derive, then land

**Items:** OPEN_ITEMS **#184** (three teardown paths, each clears a different
subset) + **#185** (`mergeAttachments` duplicate-filename aliasing), folding
**#293(d)**'s judgment call. **Difficulty: FABLE** — not because the original
fixes were hard, but because they must be re-derived against a ChatStore that
has absorbed #278, #279-era review fixes, #296, #306/#307 since the branch was
cut. Written 2026-08-10.

## 1. The headline fact (verified in git, 2026-08-10)

**Both fixes were BUILT and suite-green on 2026-07-26** — branch
`claude/t27-184-185-chatstore-integrity` (local + origin), commits `dab0172`
(fix #185) / `b0f53b5` (tests #185) / `ae766dc` (tracker note), 1152/105 on
the pinned sim against a 1147/105 baseline, RED-verified tests, implemented
exactly as specced. **The branch NEVER MERGED** (`git branch --contains` —
`main` absent) and has sat 15 days across the heaviest ChatStore churn in the
project's history. The entries' own UPDATE blocks record all of this; the
board summary that called these "not started" was wrong by a branch.

## 2. What changed underneath (why re-derive is the likely verdict)

The 07-26 fix predates: the #278 corruption-class sweep, #279's review-era
adjustments, #282's filing, #296's activity plumbing, and **#306/#307's lane —
which added state the teardown matrix has never been evaluated against**
(held/queued turns, the compose outbox, `isDrainingComposeOutbox`, the
reconcile-window door work). #184's whole point is "each teardown clears a
different subset" — **the subset UNIVERSE has since grown.** A mechanical
rebase would unify the OLD matrix and silently exclude the new members,
recreating the defect's shape on day one.

## 3. Task breakdown

1. **Diff the branch against HEAD** (`git diff main...claude/t27-184-185-…`)
   and attempt the rebase. Pre-registered expectation: heavy conflicts in
   `ChatStore.swift`. If it rebases clean, suspect the diff didn't land where
   it thinks it did — verify the three paths by read, not by conflict-absence.
2. **Re-derive the #184 matrix at HEAD, and EXTEND it.** Re-tabulate
   `clearConversation` / `openSession` / `reset()` (call sites:
   `AppContainer.handlePairingActivated` / `handlePairingRemoved` — the
   cross-HOST leakage half, the worse one) against the CURRENT state set:
   `streamingTask`, `pendingRun`/`reconcileTask`, Live Activity, speech,
   **held turn (#306), compose outbox, drain flag**. The fix stays the
   entry's shape — one private `abandonPendingRun()` (name may widen), all
   paths call it — with the new members decided row by row. **A held turn's
   teardown semantics are ALREADY RULED (O8, ratified 2026-08-09): holds
   PARK with the thread on non-destructive departures** — the matrix must
   implement that ruling, not re-decide it.
3. **Re-land #185** (id-first, dequeue-from-unclaimed, same-index insurance)
   — the branch's version is likely close to portable; its two RED tests
   (same-named picker files across rounds) carry over.
4. **#293(d) judgment, in this lane (its entry says so):** the same-index
   insurance clause reads `localAttachments`, not `unclaimed`
   (`:2438-2444` as-filed) — an already-claimed entry can be handed again,
   positionally. Auditor: ~85% shape / ~15% reachable. **Decide distinct-vs-
   fold on the code as re-landed**: if the re-land's insurance clause reads
   from the unclaimed pool, (d) dissolves — record that in #293 and strike it;
   if kept as-is deliberately, (d) stays filed with the reason.
5. Bars, gate, close-out (three entries + the branch's disposition —
   delete-after-land, per the branch hygiene convention).

## 4. Bars — copy into the entries before the run

- **184-A (RED→GREEN at HEAD):** pending on S1 → `openSession(S2)` → no
  reconcile against S2 (the branch's test, re-armed at HEAD).
- **184-B (RED→GREEN at HEAD):** streaming on S1 → `handlePairingActivated()`
  → task cancelled, `pendingRun` nil, **held turn parked per O8** (NEW half).
- **184-C:** `reset()`'s two pairing call-sites drive the unified teardown —
  cross-host leakage closed; sits beside the #136 reset-race tests.
- **184-D (the grown matrix):** every teardown row × every state member has an
  asserted disposition — the test enumerates the matrix so a future member
  addition FAILS it (the #180 lesson: the convention is the deliverable).
- **185-A/B:** the branch's two tests green at HEAD (distinct bytes in send
  order; identity outranks name fallback under reorder).
- **185-C:** single-attachment round-trip unchanged.
- **GATE: PASS**, counts MOVED at every step.

## 5. Traps

- **Do not trust the 07-26 suite-green** — 1152 tests then, ~2005 now; the
  world it was green in no longer exists. Everything re-verifies at HEAD.
- `reconcileFromServer()` taking no session argument was #184's enabling
  defect — check whether ANY intervening lane already changed that signature
  before re-deriving (if #235/#292's work touched it, the fix shrinks).
- The #184 entry's own caveat stands: the S2-adoption trigger is one path
  (drop on S1 → switch → send on S2), NOT common — don't spec it as common.
- Device checks for both items live in the running list **§F1** (one queue) —
  this lane's close-out updates those rows, it does not restate them.

## 6. Owen's to decide

- Nothing blocking start. The rebase-vs-rederive verdict is the lane's to
  make and REPORT (step 1's evidence decides it); the matrix's new-member
  dispositions follow O8 and existing rulings — anything genuinely novel
  (e.g. "should `reset()` kill a held turn on UNPAIR?" if O8 doesn't cover
  the destructive-departure reading there) comes back as a question, not a
  guess.
