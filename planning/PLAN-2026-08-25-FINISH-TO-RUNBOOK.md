# PLAN 2026-08-25 — finish the elected queue, land everything in Owen's runbook corner

**Ruled by Owen 2026-08-25 (in-chat):** finish the open items; every
remaining piece of work ends as a Talaria Device Runbook card (his corner);
any NEW open items come only from testing. Post-compaction execution is
ORCHESTRATED: Opus for code, Sonnet for chores/verification, no Haiku
(standing memory: never haiku for exploration; nothing here is
haiku-reliable), Fable steps in for escalations and the design doc.
Workflows are explicitly permitted ("you have my permission to try").

## The elected build queue (all rulings filed in OPEN_ITEMS 2026-08-25)

Order small→large; each lane: bars pre-registered in its entry BEFORE code
(write them at lane-open where missing), worktree, RED-first, mutations
isolating, `lane-gate.sh` (TALARIA_SIM_NAME=CC-lane-2 or -3), PR, merge on
green, tracker close-out in the same PR. Stage an OTA after merges land
(stacking ruling — never hold), republish the runbook with each new card.

1. **#409 refusal-string reword** (Opus, S). The governor's same-tool-repeat
   refusal string gains an explicit do-not-claim clause. Bars: string
   pinned; existing governor tests green; verification = the next device
   `refusal-words` run (runbook note on the #339 subset card).
2. **#408 auto-degrade once** (Opus, S-M). Catch `.guardrailViolation` on an
   image-carrying on-device turn → retry ONCE with images demoted to the
   OCR placeholder + honest reply note; text-only declines unchanged.
   Bars at lane-open: one-retry-only; the demote reuses `composeTurnInput`
   with `imageInputEnabled: false` (no second compose path); the reply
   surface says what happened; #390 pins untouched. Device card: re-send
   the declined laundromat photo — expect an OCR answer + the note.
3. **#330 measurement lane** (Opus, S-M). Unit repro FIRST
   (`ChatStore.openSession` + server-shaped double — confirms/kills
   candidate ① on sim, per the entry's investigation block); then the
   verbose-gated `/usage` command + three seam breadcrumbs (⚠️ NOT
   `#if DEBUG` — ota-stage builds Release; and do NOT copy `/history`'s
   sender filter). Device card: the six-step script in the entry.
4. **#334 labels + doc-debt lane** (Opus, S). Correct the four mislabelled
   `expected:` rows; add E1 (2×2 offer×length) + E2 (non-anaphoric
   words-only) rows to `routerLongContextGrid`; pin the no-op suffix (E4);
   rewrite the RETRACTED rationale at `+IntentRouting.swift:169-177` on
   the latency basis + the test's stale comment
   (`DeviceToolBeltTests.swift:2538-2540`). ⚠️ Land BEFORE the first
   beta-7 #339 subset run (band count moves). Device card: E1/E2 rows ride
   the next `long-context-probe` run.
5. **#393 mutedForeground ramp fix** (Opus, S). Nudge the 9/88 cells with
   ramp ORDER pinned by test (call 2's exact precedent). **PR HELD for
   Owen's device eyeball — do not merge on the gate alone.** Device card:
   the eyeball.
6. **LiveHermesClient deletion** (Opus, S). Port/tombstone its tests
   (AppStoresTests ×3 sites), structural check nothing references it,
   gate. Independent of the pairing design.
7. **#309 pairing-handshake DESIGN DOC** (Fable — escalation-tier, no
   code). `planning/` doc: plugin-native pairing for NEW devices (the
   handshake over the gateway/talaria plugin), migration for existing
   pairings (Keychain identities survive), what the relay client family's
   deletion then looks like (the three live services), and the #406/#405
   pairing-screen implications (the relay URL field's future). OWEN RULES
   ON THE DOC before any code.

## The runbook endgame (after the queue)

- Stage the final OTA; republish the runbook: front-page build bump + new
  cards (#408 degrade check · #330 six-step script · #393 eyeball · #334
  E1/E2 note on the subset card · #409 note on the refusal-words card).
- **Consolidation pass:** walk the live board (grep every entry's latest
  block); every item whose remaining step is device/desk gets a card or an
  annotation on an existing card; everything else must read as an explicit
  Owen-decision, watch, or external-block state. Anything that doesn't fit
  those buckets is a finding — file it. A Sonnet sweep with a
  coverage-check (a Workflow fan-out is a good fit here) verifies:
  "for each open item: card, decision, watch, or external — name which."
- Handoff the final board state; the runbook becomes the single active
  surface. New items thereafter come only from Owen's testing results.

## Standing traps for the executor (all bitten THIS session — read first)

- **A `;` or a pipe swallows a checker's exit code** — bit TWICE today
  (#318 close-out merged past a RED invariant; an earlier docs commit).
  Gate every tracker commit on the checker's explicit exit, `if [ $? -eq 0 ]`.
- **Never chain a long job with `&` inside a Bash call** — bit TWICE today
  (a gate, an OTA stage — both forked untracked with output discarded).
  Use the harness's background mode; kill strays by PID.
- **"Runner hung before establishing connection"** = the #219 family /
  self-inflicted sim state — re-run on the other CC-lane sim before
  believing a red; record the attribution.
- Stage by name, never wildcard · count-moved check after test edits ·
  structural-pin greps count COMMENTS too (reword comments, keep pins
  dumb) · CC-lane pool only, TALARIA_SIM_NAME always · beta6 is the
  toolchain (`DEVELOPER_DIR=/Applications/Xcode-beta6.app/...`).
- **⛔ TIME-BOX open-ended hunts (the 10-hour xflake lane, 08-27):** a
  reproduction/diagnosis lane gets an explicit attempt budget and a
  report-back checkpoint IN THE BRIEF ("after N attempts or T hours,
  stop and file what you have") — an honest non-answer at hour 2 beats
  a marathon; the orchestrator failed to cap this one and a process
  crash, not a decision, ended it.
- **⛔ NEVER `pkill -f lane-gate.sh` or `pkill -f "xcodebuild -project"`
  (bit the night batch, 08-26):** pattern-kills murder EVERY lane's gate on
  the box — one lane's pre-rerun cleanup silently killed another's gate
  mid-Release, leaving a log that just stops (the no-failure-marker trap).
  Kill only PIDs you started and recorded; find a stale build of your OWN
  by its worktree path, never the shared project name. Corollary of the
  same incident: `setsid` does not exist on macOS.
- **A count taken by name-grep is a count of names (trio lane, 08-26):**
  #264's "four sites" missed a fifth site that didn't carry the
  identifier and counted three that were already dead — inventory by
  reading call sites, not grepping a name.
- **Three more, from the 08-25 evening lanes:** a commit subject starting
  with `#` gets EATEN by `git rebase --continue`'s comment cleanup
  (repair with `--amend --cleanup=verbatim`; house "#NNN:" subjects are
  exposed) · the session scratchpad is SHARED across parallel agents —
  lane-prefix every scratch filename (`pr-body.md` got clobbered) ·
  `gh pr merge --delete-branch` from a worktree always fails the LOCAL
  delete (merge still lands; delete the remote branch explicitly, prune
  the local one after) · deletion bars pin "zero NON-COMMENT references,"
  never "zero grep hits," when tombstones are also required (309-DEL-A's
  bar-formation error, adjudicated in the entry).

## NIGHT-BATCH ADDENDUM (2026-08-25 ~23:00 — the ten-item ballot, ALL elected, "Tonight, stacked")

Owen elected the entire unelected backlog in one ballot and confirmed
overnight orchestration. Same discipline as the day: bars at lane-open
(the lane writes them into its entry where missing, invariant-gated,
BEFORE code), RED-first, gates, merge-on-green (his standing grant),
close-outs in the same PR, device halves become runbook cards.

**⛔ HARD CONSTRAINT (Owen, 2026-08-25 ~23:05): MAX 3 BOOTED SIMULATORS
at any moment — the box CRASHED at 7; 3 is measured stable with overage
headroom. Every lane checks `xcrun simctl list devices | grep -c Booted`
before booting; a #219 flake re-run on CC-lane-1 first SHUTS DOWN the sim
it came from. Also in CLAUDE.md's pool section now.**

**Lane groupings + order (max 2 concurrent gates; #309 Lane C is
running and Lane B queues first):**
1. **#150 discovery** — Opus, read-only, dispatched immediately (no sim).
2. **#309 Lane B** (already queued) — after C merges.
3. **#330 FIX lane** — Opus, solo; parallel with B on the second sim.
4. **Hygiene trio** — #264 half-2 + #377 + #336-C, one Opus lane, one
   gate (the night-trio precedent).
5. **Bundle** — #373's four chores + #378 memories read, one Opus lane.
6. **Instruments lane** — #211A battery build + #372 (decline path +
   `.required` remedy): cells/scorers built and sim-gated tonight;
   device runs → runbook cards.
7. **#398-A..C** — own lane; Mac/sim-side halves run tonight, device
   halves → runbook cards.

Morning deliverables: merged lanes, a fresh staged OTA, the runbook
republished with the new cards, handoff updated.

## STATE AT THE 08-27 **NIGHT** COMPACTION (~00:00 — supersedes every block below)

**Board: 68 live · 0 open PRs · main `a2b2cbaa` · device AND staged on Debug
build 3134 · 1 worktree · 2 booted sims · no stray processes.**
**NOTHING IS RUNNING.** No lanes, no gates, no waiters, no monitors.

**The night in one line:** the instrument harness could not resolve the phone and
the installed build was Release (so `#if DEBUG` compiled the trigger out) — both
fixed (#416), then all five owed instrument runs ran and scored.

- **#340-H5′ PASSED** — both bars, both guards; promotion condition satisfied.
- **#339** baselined on beta 7; **#372** HD1–HD4 met; **#392** reproduced but
  underpowered (needs `--trials 50`).
- **#211A's D1 retired by Owen's ruling** and its question restated to *honest
  refusal vs fabrication*; that produced **#417**, and #417's own tool-failure
  instrument was built and run the same night — **a present-but-failing tool
  fabricates 0/40** where an empty belt fabricates 20/40. The failure strings are
  protective.
- **#398-A closed for free:** device is `24A5424a`, sim is `24A5423a` — parity
  was assumed and is now measured FALSE; CLAUDE.md corrected in three places.

**⚠️ The phone is on a DEBUG build (3134).** Re-stage Release before any UX card
— DEBUG seams are live.

**Owen's corner:** #392 at `--trials 50` · #417's one open question (can a
production path reach the model with neither data nor a failure string?) ·
#124 sweep-ready · the UX cards on a Release build · OJAMD's gateway still down.

## STATE AT THE 08-27 AFTERNOON COMPACTION (14:4x — superseded by the block above)

**Board: 66 live · 0 open PRs · main `08120139` · build 3120 staged ·
suite 2752 + 15 · 1 worktree (main only) · 2 pool sims · no stray
processes.** Everything the 00:30 block listed as in-flight MERGED
(#415 fix `8ccc602b`, naming sweep `60a874dd`, shortcuts `da4017b0`,
controls `39e5bb25`); sweeps 9–11 ran; the day's full record is handoff
**§23**.

**NOTHING IS RUNNING.** No lanes, no gates, no waiters, no monitors.
The next action is Owen's — device cards, or a new election.

**If he pastes runbook results:** file each verdict into its entry
(dated, build-quoted), mark the runbook cards, offer the sweep pool.
**If he elects work:** bars at lane-open, worktree, RED-first, gate,
merge-on-green — and TIME-BOX any diagnosis lane (the trap below).

**Live watches/parked:** #219 (XFLAKE tripwire armed — the next natural
red self-documents; do NOT start another reproduction hunt), #413,
#414, #373's bullet, #224 Phase 3 (deferred by ruling), CarPlay rename
(deferred-with-trigger on #74). **OJAMD's gateway was down** at last
report.

---

## STATE AT THE 08-27 00:30 COMPACTION (historical — superseded above)

**Board: 68 live entries** (95 at plan-write). Sweeps 7–10 executed on
Owen's approvals. Both hosts run plugin **0.8.0**; both approval pickers
live; the app-side modes (#224 P1+2) shipped in **3101**; `talaria://`
primary + `hermes://` easter egg in **3108** (device-confirmed); CC
controls renamed to Talaria (PR #392, in no staged build yet).

**IN FLIGHT, two lanes (both self-file their close-outs + merge on
green — their completion notifications are self-contained):**
1. **#415 FIX lane** (CC-lane-3, worktree agent branch
   `worktree-agent-a745a46ee24e0c69a`): mid-flight App-Lock gate
   re-evaluation (a voice session that becomes COVERED parks — closes
   #302's blind ordering, the forensics-named mechanism) + the realtime
   capture instrument. RED witness `AppLockMidFlightCoverTests` seen
   running.
2. **#415 SHORTCUTS mini-lane** (CC-lane-2): "Ask Talaria" in the
   Shortcuts surface; was in its gate at compaction prep.

**POST-COMPACTION STEPS when each lane reports:** review honestly →
pull → prune worktree/branch (squash blinds `--merged`; delete by name)
→ after BOTH land: stage ONE build (`ota-stage.sh main`, background,
tracked) carrying renames+shortcuts+fix → runbook: add the fix lane's
device card (warm-app CC tap → lock arms → mic goes cold; from its
result block), mark cards, front-page bump, republish (source:
scratchpad `talaria-device-runbook.html`, URL in this doc's foot,
artifact edits via the same file path) → digest to Owen.

**Sweep-11 pool accumulating:** #190, #123, #77 (+ whatever the lanes
close). **CarPlay rename: DECLINED-FOR-NOW with a trigger** (#74's sim —
recorded in #415; do not resurrect). **#414** (/v1/models 401s) filed,
unelected. **#413** (phantom first utterance) filed — AirPods probe on
the runbook. **OJAMD's gateway was down** at last check (Owen's word);
`gateway_state.json` names causes. **#373 held** from sweep 8 (one
bullet). **Instrument device runs + subset**: cards ready, never run.

**Day-2 traps added to the record:** subagent waiters outlive their
agents (sweep `until grep` after every lane; in briefs: kill your
waiters); sweep-marker dates must not be inherited from the template
(fixed for 9/10; write fresh markers); verify BEFORE the move runs, in
a separate command; name-grep counts are name counts; the survivor
check self-matches (CLAUDE.md carries the filter).

## Owen's standing state (do not re-ask)

Stacking ruling (never hold builds/lanes for testing; edit the runbook) ·
**merge-on-green-gate autonomy CONFIRMED by Owen 2026-08-25 in so many
words ("Merge on green approved") for the elected lanes — except #393's
PR, which HOLDS for his device eyeball** · the runbook confirmed as his
single work surface ("the runbook stays the place where my work goes") ·
outward-facing publishes still need his explicit go · runbook artifact:
`https://claude.ai/code/artifact/050aa59f-551a-4e6d-a664-f3e6d535d356`
(WebFetch to read; republish with `url`; source currently at this
session's scratchpad `talaria-device-runbook.html`).
