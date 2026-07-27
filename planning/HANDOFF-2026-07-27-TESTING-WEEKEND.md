# HANDOFF — 2026-07-27 — the testing weekend: three passes, seven lanes, two root causes

**For the next Claude session.** Read this, then `git log --oneline -20` on main, then check PR
state. Trust live state over any document, including this one (DIAGNOSTIC DISCIPLINE rule).

---

## Where things stand

**main** is at `991e517` (dispatch: 190B), clean, all work pushed. Repo checkout on the Mac may be on
**any branch** — Owen checks out PR branches to build to his phone. **`git status --branch` BEFORE
every commit.** This bit us twice this weekend (commits landed on a feature branch both times;
recovered losslessly both times via ff-merge once, cherry-pick once).

**Merged this weekend:** PR #148 (#176 vision-tool gating), PR #150 (#184 one teardown primitive
`abandonPendingRun(stopSpeech:)` at ChatStore:748 + #185 attachment identity merge). Both verified
in fresh worktrees before merge (own DerivedData — immune to the stale-object trap Fable hit, where
three "green" runs never executed the new tests).

**In flight at Fable (cloud), sent 2026-07-27, awaiting return:**
1. `dispatch/OPUS-T27-190B-151-rework.md` — continues PR #151 on `claude/t27-190-local-session-store`
   (no new PR). Five changes: symmetric membership routing, kill the silent catch, isLocalThread
   contamination, maximal round-trip test, drawer refresh after New.
2. `dispatch/OPUS-T27-189-147-notifications-end-to-end.md` — notification authorization + honest
   panel + tap crash (the nonisolated didReceive fix; #47 headless reply must survive).
3. `dispatch/OPUS-T27-117-cross-cycle-backoff.md` — backoff decays because the ladder is per-cycle;
   any re-check must state its duration (passes at 15min, fails at 25).

**Queued, send after 190B merges:** `dispatch/OPUS-T27-191-192-193-backend-truth.md` — it builds on
190B's routing fix. Then/anytime: `OPUS-T27-176B-186-belt-truth.md` (unblocked since #148; grazes
LocalChatBackend, trivial-rebase risk vs 190B), `OPUS-T27-58-controls-execution-target.md`
(disjoint). All lanes are cloud-runnable; nothing queued needs local.

**When PRs return:** verify in a fresh worktree (`git worktree add -f /tmp/t27-NNN origin/<branch>`,
full `xcodebuild test` with nohup+disown, poll the log from a NEW shell — never sleep inside a DC
call, 4-min ceiling). Confirm suite count delta = new tests. Check adds/removals → pbxproj regen →
`aps-environment: development` survived. Merge with `gh pr merge NNN --merge` (never squash).
GitHub blocks request-changes on same-account PRs — holds are by comment + convention.

---

## The two root causes found this weekend (both fully source-traced; specs carry them)

**#190 device FAIL — routing, not SwiftData.** Storage layer is SOUND (lists, survives relaunch,
SIGTRAP workaround held on cold boot — the workaround: private `ModelContext(container)` under
@MainActor, never `mainContext`, because beta-4 runs MainActor Tasks on non-main OS threads).
The dead tap: `ChatBackendRouter.openSession` sends non-local ids to the ACTIVE BRAIN, so Hermes
rows tapped while local is active hit LocalChatBackend → `sessionNotFound` → swallowed by
ChatStore.openSession's log-only catch → silent nothing. SwiftData exonerated: predicates already
avoided (fetch-all + in-memory match), Message Codable symmetric, list/fetch share one path.

**#192 — the app switches ITSELF away from on-device; the "refused switch" was the residue.**
`resolvedBrainForNextTurn()`: Hermes wins by default on a paired device; the on-device pick is a
per-conversation preference keyed to the conversation UUID. Any id rotation (New, clear,
openSession) orphans the pick → next send or ~10s `connect()` probe reverts. Refusal half:
`refreshActiveBrain()` no-ops while `runningBrain != nil`, and sendStreaming only clears
runningBrain on completion → a dropped run wedges routing until force quit (in-memory).
**DECIDED (Owen 2026-07-27): sticky mode.** The explicit pick is the resolution default; id
rotations must not revert it; per-conversation override on top; migrate stored picks; automatic
changes must announce (the #30 PCC pattern). It's all in the 191-192-193 dispatch.

**Compounding context:** #192 contaminated the 07-26 device pass (threads believed local ran on
Hermes — screenshots show ON-DEVICE badge + DEEPSEEK-V4-FLASH pill + ONLINE·OJAMD simultaneously,
which is also #191's header lie), and feeds the isLocalThread store-contamination hole 190B fixes.

---

## Owen's device run (when home) — the gate for merging #151

Ground truth rule: **airplane mode** for any step needing certainty the local backend answered
(on-device answers offline; Hermes cannot). The UI's claims are not evidence until 191/192 land.

1. Two local chats survive: New → turns → New → turns → drawer shows BOTH → both open with content.
   (Open-by-tap is THE failed check being re-verified.)
2. Cross-routing both ways: open a local session while Hermes active; open a Hermes session while
   local active. Both must open on the right backend.
3. Kill/relaunch: both local sessions still listed and openable.
4. New-then-drawer immediacy: departing chat appears without delay.
5. Read-aloud stops on session switch (stopSpeech flip, already merged in #150's wake via 190B base).
6. Connected-mode parity: Hermes list/restore unchanged.
7. If 189/147 merged by then: fresh-install priming prompt appears on plain-text usage; panel reads
   NotDetermined/Denied/Authorized honestly; cold-tap on a completion notification does NOT crash;
   #47 headless typed reply still works.
8. Anything odd → capture Console.app filtered on "openSession" / "brain" — 190B adds logging that
   makes failures name themselves.

Owen offered: **a Hermes pairing key is available on request** — the next session can pair a
simulator/instance against the Mac Mini (relay :8000, gateway :8642 answers ~15-20s after start) for
end-to-end checks without waiting for the phone. Simulators may get most of the way; the pinned sim
is 47F68496-24F9-45D9-93D3-1C778DB6B557 (survived the beta-4 rebind).

---

## Local-only work queue (needs Owen/DC, not cloud; none of it gates the lanes)

- #188 watchdog split + relay.log rotation/timestamps (OJAMD; the forensics half FIRST — 493MB, no
  timestamps, event 7036 never logged)
- #133/#143 partial unique index migration on the relay DB (the 53ms same-device-same-token race
  makes it load-bearing, not polish)
- `ojamd-deploy` rebase (192 behind t27/main; BOM fix d6bd83d un-upstreamed)
- Device housekeeping: phone auto-lock still Never; 25.07MiB test PDF in iCloud Drive; Mac Mini
  re-pairing after A11's Forget was never confirmed (check FIRST if pairing misbehaves)
- ~10 stale local branches incl. one [gone]; Owen intends to tidy — check item text before deleting
  anything (the recovered-branch incident)

## Checks/items deliberately NOT dispatched (need redesign, not code)

#116 (no route to an empty token slot — resolve the gap before rewriting the check), #137 (check
must name an input that COULD have changed the posture), #128 (repro path structurally impossible
since April — establish which before device time).

---

## Process rules earned this weekend (enforce them)

1. **A verification claim states the scope of its evidence** — verified how, on what build, observed
   where. Every serious miss was a scope error: #147 closed on a merge; "no callers" from a 29-file
   slice; restart counts from a rotated log; #117 green on a too-short window; three checks scored
   conditions they never created.
2. **Items close on device evidence, not merges.** #147's "fix" was inert from the moment it merged
   (nonisolated overloads opt out of class-level @MainActor).
3. **Check existing items before writing new ones** — 4 of 10 planned items already existed; #176
   had a dispatch AND an open PR. The staleness sweep is the highest-value step.
4. **git status --branch before every commit** (twice bitten).
5. **Verify returned PRs in fresh worktrees**; suite counts from Swift Testing lines ("Test run with
   N tests"), not XCTest "Executed" lines.
6. Intermittent bugs: instrument-first, never speculative-fix (masking makes the next occurrence
   harder to catch). #192 ultimately fell to source-tracing, not reproduction.

Tracker is internally consistent: 193 items, numbered 1-193, no dupes, no gaps, both grep idioms
agree (#157's em-dash normalized).
