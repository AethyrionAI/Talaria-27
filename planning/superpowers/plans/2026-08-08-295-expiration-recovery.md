# #295 Expiration-Path Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When iOS revokes a backgrounded turn's budget (`cancelStreaming(hardStopHost:
false)`), the user row settles `.working` and the real recovery route arms — instead of
today's silent hole. User-initiated Stop is byte-unchanged.

**Architecture:** Owen's approved shape (ruling filed 2026-08-08 in the #295 entry):
mirror the `.interrupted` arm — remove the placeholder preserving partial reasoning,
settle the user row `.working`, mint `PendingRun`, `startReconcileLoopIfNeeded()`.
Plane-appropriateness comes free: `reconcileFromServer()` is routed by
`ChatBackendRouter` (four implementations — router/resilient/sessions/local), so the
one arming site recovers correctly on whichever plane owns the turn. All work in
`ChatStore.swift` + tests.

**Tech Stack:** Swift 6, swift-testing. Test homes: the existing ChatStore/reconcile
test files (grep `seedPendingRunForTesting` and `cancelStreaming` in `TalariaTests/` —
those files' construction idioms are the authority).

## Global Constraints

- `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`; sim id
  `47F68496-24F9-45D9-93D3-1C778DB6B557`; suite-level `-only-testing:` one suite per
  run, foreground, read executed counts. Branch `t27-295-expiration-recovery`
  (worktree). Trailer at commit time.
- **Bars (registered in the entry):** **295-A** an expiration-path turn ends in a state
  that is neither a false failure nor a silent hole (`.working` + recovery armed);
  **295-B** user-initiated Stop unaffected (`.delivered`, silent, NO pendingRun, no
  reconcile armed); **295-C** no comment anywhere claims a recovery route the code does
  not walk (the big comment block at `ChatStore.swift:1141-1153` must be rewritten to
  describe the NEW behavior).
- **The `abandonActiveRun()` hazard — resolve before writing code, with the
  enumerate-its-callers discipline** (the #283-era near-miss was wiring behavior onto
  this exact method): `cancelStreaming` calls `hermesClient.abandonActiveRun()`
  unconditionally (`ChatStore.swift:1167`). It releases the router's routing lock
  (#192) AND `SessionsHermesClient.clearActiveRunContext` clears the run context the
  runs-plane recovery may need. The implementer MUST read `abandonActiveRun`'s
  implementations (router + sessions client + local) and the `.interrupted` arm (which
  does NOT call it, `ChatStore.swift:884-909`) and decide: keep it on the expiration
  path (if the reconcile loop doesn't need the context) or gate/re-order it — stating
  the reasoning and the callers enumerated in the report. A wrong call here silently
  destroys answers.
- **#294's empty-placeholder removal stays** on both paths (a recovery that finds
  content re-creates the row via the adoption path; an empty box must never persist).
- The `.interrupted` arm (`ChatStore.swift:884-909`) is the reference implementation —
  REUSE its mechanics (extract a shared helper if that avoids duplication; both arms
  must stay behaviorally identical where they overlap).
- `PendingRun` needs `sessionId` (+ optional `runId`): `cancelStreaming` does not
  receive them today. Preferred seam: capture at stream start into a store property
  (the stream events carry them — the `.interrupted(let sessionId, let runId)` case
  proves it; find where the send path first learns them and store
  `activeStreamRun: (sessionId: String, runId: String?)?`, cleared on every terminal
  path). Fallback if capture is impractical: a client accessor. State the choice +
  why in the report.
- Lane gate before the PR.

---

### Task 1: `.working` settle + identifier capture

**Files:**
- Modify: `Talaria/Stores/ChatStore.swift` (`settleStoppedUserMessage` :1228; the send
  path where session/run ids first appear; `cancelStreaming` :1158)
- Test: the ChatStore test file that already exercises `cancelStreaming` (locate by
  grep; extend it)

**Interfaces:**
- Produces: `settleStoppedUserMessage(as: MessageStatus)` (explicit at both call
  paths: `.delivered` for user stop, `.working` for expiration);
  `activeStreamRun: (sessionId: String, runId: String?)?` captured at stream start,
  cleared on every terminal path (normal finish, error arms, `cancelStreaming`).

- [ ] **Step 1: Failing tests** — (i) `cancelStreaming(hardStopHost: false)` settles
  the user row `.working`; (ii) `cancelStreaming()` (user stop) still settles
  `.delivered` (the 295-B pin); (iii) `activeStreamRun` is non-nil during a stream and
  nil after every terminal path the file's harness can drive. Model construction on
  the existing tests in that file.
- [ ] **Step 2: verify RED.**
- [ ] **Step 3: implement** — the settle parameterization is mechanical; the capture
  goes where the send path first holds the ids (state the exact line in the report).
- [ ] **Step 4: verify GREEN both suites the file belongs to.**
- [ ] **Step 5: commit** (`feat(#295): expiration path settles .working; stream identifiers captured for recovery`).

---

### Task 2: Arm the recovery (the core of the lane)

**Files:**
- Modify: `Talaria/Stores/ChatStore.swift` (`cancelStreaming`)
- Test: same file as Task 1 + the reconcile-loop test file (grep
  `startReconcileLoopIfNeeded` / `seedPendingRunForTesting` in tests)

**Interfaces:**
- Consumes: Task 1's capture + parameterized settle; the `.interrupted` arm's
  mechanics (:884-909).
- Produces: on `hardStopHost: false` ONLY — placeholder removed preserving
  `partialReasoning`, `PendingRun` minted from the captured ids, reconcile loop
  started. On `hardStopHost: true` — byte-identical behavior to today.

- [ ] **Step 1: Failing tests** — (i) expiration path: `pendingRun` non-nil
  (`pendingRunSessionId` matches the captured session), placeholder gone, reasoning
  preserved on the PendingRun, user row `.working`; (ii) 295-B: user stop mints NO
  pendingRun, arms no loop; (iii) the `abandonActiveRun` resolution (whatever Task
  2's investigation decided) is pinned by a test that fails if the ordering/gating
  regresses.
- [ ] **Step 2: verify RED.**
- [ ] **Step 3: implement**, including the `abandonActiveRun` resolution with its
  reasoning in a code comment citing the enumerated callers.
- [ ] **Step 4: verify GREEN** (both test files + `RunsPlaneTransportTests` if the
  resolution touched anything the runs plane reads).
- [ ] **Step 5: commit** (`feat(#295): expiration path arms the real recovery — PendingRun + reconcile loop, the .interrupted shape (bars 295-A/B)`).

---

### Task 3: The 295-C comment sweep + close-out

**Files:**
- Modify: `Talaria/Stores/ChatStore.swift` (:1141-1153 comment block — rewrite to
  describe the NEW behavior), plus any other comment the grep finds
- Modify: `OPEN_ITEMS.md` #295 (bars-met note, accreted header per the never-erase
  convention), this plan (outcome line)
- Test: none new (docs + comments), but re-run the touched suites once

- [ ] **Step 1: grep sweep** — `restartPendingPollingIfNeeded`, "recovery poll",
  "degrades to" across `Talaria/` and `TalariaTests/`; every comment describing the
  expiration path must match the shipped behavior (bar 295-C). The
  `HermesClientProtocol.swift:~138` and `RunsPlaneTransportTests.swift:~1333` sites
  named in the entry were being corrected in the #291 lane — VERIFY their current
  text and fix any residue.
- [ ] **Step 2: close-out docs** — bars-met note (each bar → its pinning test),
  header accretes (e.g. "… Owen's call. → ✅ FIX LANDED 2026-08-08 …"), plan outcome
  line, close-out rule sweep for falsified text.
- [ ] **Step 3: lane gate** (backgrounded + polled), **Step 4: commit(s), Step 5: PR**
  via `gh pr create` (🤖 line), hand Owen the merge.

---

## Self-review record

- **Spec coverage:** bar 295-A → Task 2; 295-B → Tasks 1+2 pins; 295-C → Task 3.
  Owen's plane-appropriateness requirement → satisfied structurally by the router's
  `reconcileFromServer` (stated in Architecture; Task 2's runs-plane suite run is the
  regression check). The #292 interaction (producer keeps running) is out of scope per
  the ruling ("noted, not blocking").
- **Placeholder scan:** Task test-steps reference existing files located by grep
  rather than named paths — deliberate: the ChatStore test suite's file layout is
  discovered at execution (the plan's author verified `seedPendingRunForTesting`
  exists as a harness seam, `ChatStore.swift:2123`).
- **Type consistency:** `activeStreamRun` tuple, `settleStoppedUserMessage(as:)`,
  `PendingRun(sessionId:runId:userMessageID:sentAt:partialReasoning:)` (the real
  initializer, from :898-904) used consistently.
