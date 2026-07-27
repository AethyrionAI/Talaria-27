# OPUS-T27-190B — PR #151 rework: the drawer opens what it lists

**Item:** OPEN_ITEMS #190 (device pass FAILED 2026-07-26) · **Repo:** AethyrionAI/Talaria-27
**Branch:** continue on `claude/t27-190-local-session-store` (PR #151 — stays open, do not open a new PR)
**Toolchain:** Xcode-beta4, pinned sim · `export GH_PAGER=cat` first
**Context:** PR #151 comment (issuecomment-5087007479) and the 2026-07-26 blocks on OPEN_ITEMS #190 + #192.

## What the device pass established

Storage held: sessions list, survive kill/relaunch, and the SIGTRAP workaround survived a cold boot.
**Open-by-tap is a silent dead tap.** Root cause is routing, source-traced — not SwiftData. Do not
touch the storage layer except for change (4).

Also relevant, decided since: **the brain pick is becoming a sticky mode** (Owen, 2026-07-27; see the
192 section of `dispatch/OPUS-T27-191-192-193-backend-truth.md`). That lane runs AFTER this one — do
not implement it here — but know it exists: the brain will stop rotating out from under
conversations, which simplifies your change (3).

## The five changes

1. **Symmetric membership routing.** `ChatBackendRouter.openSession` routes local ids by membership
   (correct; keep). Every non-local id currently falls to `backend(for: runningBrain ?? activeBrain)`
   — the active brain — so a Hermes row tapped while the local brain is active goes to
   `LocalChatBackend`, throws `sessionNotFound`, and dies silently. Fix: non-local ids route to
   **Hermes when configured**, independent of active brain; fall back to active brain only when
   Hermes is not configured (the stub path already prevents those taps). Deterministic test: active
   brain = local, open a Hermes session id → opened on the Hermes backend.

2. **Kill the silent catch.** `ChatStore.openSession`'s `catch` only logs — that is why a
   deterministic failure was invisible on device and green in a 1192-test suite. Surface failure to
   the user (minimal is fine) and make "open failed" a state the UI renders. Give the store's
   decode-nil path in `conversation(withID:)` the same treatment. Same false-green family as
   #189/#191.

3. **Close the `isLocalThread` contamination hole.** The walk-away persist guards on "any message
   stamped on-device," so #192's mixed paired-mode threads get upserted into the local store —
   violating the guard's own comment ("never a paired-mode Hermes thread"). Identify a local thread
   by **origin** (created by the local backend / id already known to the store), not by scanning
   message brain stamps. A mixed thread whose identity is a Hermes session must not enter the store.

4. **Maximal round-trip test.** Encode → SwiftData → decode a real-shaped `Conversation` —
   attachments, toolActivities, usage, reasoning, voiceSessionDuration, mixed brains — through the
   actual store. The existing 26 tests round-trip synthetic minimal conversations only.

5. **Drawer refresh after New.** Observed: the departing chat did not appear in the drawer
   immediately after New, then showed later. The walk-away persist is synchronous, so suspect the
   list snapshot not refetching on the New path (`refreshSessions(force:)` seam). Verify and fix.

## Definition of done

- The four routing/UI changes have deterministic tests; the suite is green with the new tests
  actually executing (remember the stale-object incident — fresh DerivedData or verify execution).
- Baseline confirmed before starting; delta explained by your new tests.
- PR #151 body updated: what changed since the device fail, and the exact device checklist for Owen —
  open-by-tap on a local session while Hermes is active, open a Hermes session while local is
  active, and the New-then-drawer immediacy check.
- Device verification is **owed by Owen**; the item does not close on suite green.

## House rules

Merge commits only, never squash. File-scoped commits. **OPEN_ITEMS.md edits in their own separate
commit.** No Swift files are expected to be added; if any are, `xcodegen generate`, pbxproj regen as
its own commit, and verify `aps-environment: development` survived.
