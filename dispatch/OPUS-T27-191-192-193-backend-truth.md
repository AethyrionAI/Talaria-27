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

**The missing observation:** whether the toggle **moves then reverts** (switch accepted, apply
failed) or **refuses to move** (guard rejects the input up front). Different fixes. Establish it from
source if you can — trace every early-return in the backend-switch path in `ChatBackendRouter` (#68)
and whatever owns the guard — and **state which case you found**. If source cannot settle it, say so
and stop rather than guessing; Owen can get the observation in five seconds on device.

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

- Switch to on-device and back to Hermes repeatedly without a force quit. The switch takes every time.
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
