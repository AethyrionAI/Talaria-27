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
