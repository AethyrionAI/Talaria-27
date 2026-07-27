# OPUS-T27-191 + 192 + 193 — the header tells the truth, the switch takes, the dialog has a way out

**Items:** OPEN_ITEMS #191 + #192 + #193 (touches #139, #68, #190) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-191-192-193-backend-truth` · **Toolchain:** Xcode-beta4, pinned sim
**Baseline:** confirm the current green count before you start · `export GH_PAGER=cat` first

Three defects on the backend-switching surface. #192 is a **confirm-then-fix** half — one observation
is missing and you may need to establish it from source.

---

## Part 1 — #192: switching to on-device is silently refused until force quit

**Observed 2026-07-25, whoGoesThere.** Selecting the on-device backend does not take — the UI stays
on Hermes. Force-quitting clears it; the switch then succeeds.

Force quit being the remedy establishes the stuck state is **in-memory only** — nothing persisted, it
dies with the process. Expected shape: a transition guard set and not cleared on some path, so every
later switch attempt is refused up front.

### RE-DIAGNOSED 2026-07-26 — the defect is SELF-INITIATED switching; read this before the sections below

Device evidence (screenshots on file): with ON-DEVICE active, a request for a 500-word summary
**switched the backend to Hermes with no user action**. The header kept the ON-DEVICE badge while the
model pill read `DEEPSEEK-V4-FLASH` and the status line read `ONLINE · OJAMD`; replies carried
server-shaped tool confirmations. The originally-reported "manual switch refused until force quit" is
the **residue** that reversion leaves behind, not the defect.

**UPDATE 2026-07-26 late: the initiator is FOUND, in source. Both halves. This is now a fix lane,
not a search lane.**

**Half 1 — the self-switch is `resolvedBrainForNextTurn()`'s default plus id-keyed preferences.**
`ChatBackendRouter.resolvedBrainForNextTurn()` ends with: `guard isHermesConfigured() else { return
.onDevice }` / `if let preferred { return preferred }` / `return hermes.connectionStatus == .error ?
.onDevice : .hermes` — **on a paired device, Hermes wins by default**. The user's on-device pick is
not a mode; it is a per-conversation preference keyed to the conversation UUID
(`resolvePreferenceForCurrentConversation`). So the moment the conversation id rotates — **New chat,
`clearConversation`, or #190's `openSession`** — the new id has no stored preference, resolution
falls through to the default, and the next turn runs on Hermes. No error, no big-request routing:
the "500-word summary switched it" was simply the first send after an id rotation. And
`connect()` runs "on appear and every ~10s" per its own comment ("a restarted gateway flips the next
turn back to Hermes without user action"), calling `refreshActiveBrain()` each time — so even
without a send, the header snaps Hermes-ward on the next probe after rotation.

**Half 2 — the refusal-until-force-quit is a stuck `runningBrain`.** `refreshActiveBrain()` is
`guard runningBrain == nil else { return }`. `send()` clears `runningBrain` in a `defer`;
`sendStreaming` clears it inside the stream's completion handling — so a stream that never finishes
(the #145/#184 dropped-run family) leaves `runningBrain` set for the life of the process, freezing
re-derivation and wedging the toggle until force quit. In-memory only, exactly as observed.

**DECIDED (Owen, 2026-07-27): (a) — the brain pick is a STICKY MODE.** A global default that new
chats inherit; per-conversation override remains on top of it. Owen's framing, which is the spec's
intent test: "if a user sets it to On-Device, you'd want that chat to actually get sent to
On-Device." Concretely: the user's explicit pick becomes the resolution default — `New chat`,
`clearConversation`, and `openSession` id rotations must NOT revert the brain; only an explicit user
pick (or an announced, consented fallback per the #30 pattern) changes it. Migrate the existing
per-conversation preference store forward; do not strand stored picks.

**Regardless of that decision, all of the following are required:**
- `runningBrain` must be cleared on run abandonment — wire it into #184's `abandonPendingRun`
  (ChatStore's primitive) or the router's own teardown, so an abandoned stream can never wedge
  routing. Deterministic test: start stream, abandon, assert `refreshActiveBrain()` re-derives.
- Every `activeBrain` change logs old → new, the initiator (user pick / default resolution / probe
  refresh / error fallback), and the conversation key consulted. This is the instrumentation half,
  now with named call sites: `:187`, `:270`, `:292`, `:319`, and both send paths.
- Any automatic brain change the user did not just ask for must be **visible in the transcript or
  header at the moment it happens** — the #30 PCC degradation already models this correctly
  (one-line fallback notice, never silent); reuse that pattern.

Known blast damage, for motivation: this contaminated the #190 device pass (threads believed local
ran on Hermes) and it feeds the #190 `isLocalThread` store-contamination hole. Combined with #191,
the user cannot know which brain holds their conversation.

### The refusal half — instrument, do not hunt

**Reproduction was attempted 2026-07-26 and the switch behaved correctly.** The defect does not occur
from a clean app state. Whatever sets the stuck condition is rare and situational.

**This changes the shape of the lane. Read carefully:**

- The observation that would have split the two cases — toggle **moves then reverts** (switch
  accepted, apply failed) versus **refuses to move** (guard rejects input up front) — is currently
  **unobtainable**. Do not block on it and do not ask for it.
- **Do not guess between them and ship a speculative fix.** A wrong guess here plausibly *masks* the
  symptom by clearing state indiscriminately, which would make the next occurrence harder to catch,
  not easier.
- **Do not "fix" it by clearing every guard you find on every path.** That is the same
  indiscriminate-teardown reflex #184 exists to correct.

**What IS fully available without a reproduction — do this:**

1. **Exhaustive trace.** Enumerate *every* early-return and guard on the backend-switch path —
   `ChatBackendRouter` (#68), whatever owns the transition state, and the settings surface that
   drives it. Produce the list. A path that can refuse a switch without leaving a trace is a finding
   in itself, whether or not it is *this* bug.
2. **Instrumentation, and this is the primary deliverable.** Every refusal path must log *which*
   guard refused and *why*, at a level that survives into a device log Owen can retrieve after the
   fact. Right now the failure is silent, which is the reason a whole session produced no evidence.
3. **Narrow by construction.** Of the guards found, identify which could plausibly persist across a
   failed switch and which are cleared on every exit. Rank them. State your reasoning.
4. **A synthetic test.** If you can drive the suspected state directly in a test — set the guard,
   attempt a switch, assert refusal, assert recovery — that is worth more than any amount of device
   time on a bug that will not appear on command.

**Read `Settings-ModelTransition` (project knowledge) against live source** — the transition path has
design behind it and the doc may name the intended state machine, which would make an unreachable
state obvious by comparison.

**Read `Settings-ModelTransition` (project knowledge) against live source before speccing a fix** —
the transition path has design behind it and the doc may name the intended state machine.

**This bug invalidates other tests, which is why it is filed above its apparent severity.** A tester
can believe they are on-device while Hermes answers every turn. Any on-device check must establish
the active backend independently of the UI's claim — airplane mode is the cheap ground truth, since
on-device answers offline and Hermes cannot.

## Part 2 — #191: the header is not backend-aware

**Observed 2026-07-25, ON-DEVICE active, phone in airplane mode.** The header read `HERMES` with a
model pill of `KIMI-K3` — a model that runs on OJAMD and was unreachable at the time. Only the
ON-DEVICE badge told the truth.

Message count and CTX% **do** update correctly (10→12 messages, 12%→15%). Do not "fix" those.

**Likely mechanism:** the local backend runs inside a Hermes session shell because it has no session
identity of its own to mint (**#190**). Switching backends does not switch the conversation — the
Hermes thread stays on screen with the on-device model behind it.

**Not a content leak — verified.** The on-device model does *not* receive the Hermes transcript; asked
about prior content it reports no history. This is a display defect. Do not go hunting for
contamination.

**Fix:** the title and model pill must derive from the **active backend**, not from the session that
happened to be loaded. When on-device is active the pill should name the on-device model, and the
title should not assert a host that is not answering.

**Coordination with #190:** that lane gives local conversations their own identity, which may make
part of this fall out naturally. Do not block on it — a header that names the wrong model is wrong
regardless of which session object it reads from. If your fix would be obsoleted by #190, say so in
the PR body rather than building something disposable.

Same family as **#139** (engine-truth label lie) and **#189** (false-green notification panel).

## Part 3 — #193: `confirmationDialog` Cancel does not render

**Observed 2026-07-25.** Destructive-action confirmations built with `.confirmationDialog` present
with **no visible Cancel affordance** — an iOS 26/27 presentation change. The cancel role is declared
in code, so this is dead code rather than an omission.

**Fix:** move destructive confirmations to `.alert`, which still renders an explicit cancel. Sweep for
other `.confirmationDialog` uses and decide each one — a non-destructive dialog that dismisses on
tap-outside may be fine as is. **List what you found and what you did with each.**

## Definition of done

- **#192 does not close on a green suite or a clean device run** — it did not reproduce on demand, so
  absence of the symptom proves nothing. It closes on: the refusal-path inventory, instrumentation
  that would capture the next occurrence, and either a synthetic test of the stuck state or an
  explicit statement that none could be constructed and why.
- Switch to on-device and back to Hermes repeatedly without a force quit. The switch takes every time
  — necessary, **not sufficient**, for #192.
- With on-device active: the header does not claim a Hermes model. In airplane mode it still does not.
- Switching backends does not leave the previous backend's conversation on screen — or, if that is
  deferred to #190, the PR body says so explicitly and the header is still correct.
- Every destructive confirmation has a visible way out.
- Device verification is **owed by Owen**; state in the PR body what to check, and include the
  airplane-mode ground-truth step for the on-device case.

## House rules

Merge commits only, never squash. File-scoped commits. **OPEN_ITEMS.md edits in their own separate
commit.** `xcodegen generate` only when Swift files are added or removed; pbxproj regen as its own
commit; verify `aps-environment: development` survived.
