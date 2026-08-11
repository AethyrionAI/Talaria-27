# Everything pending — consolidated for Owen, 2026-08-10 (post wave-2)

> # ⛔ SUPERSEDED 2026-08-10 EVENING — read `PENDING-OWEN-CONSOLIDATED-2026-08-10-EVENING.md` instead.
>
> This snapshot was assembled ~15:30 and was overtaken the same evening.
> **Every decision in its §1 was ruled**, its §5 asked for a go that had
> already been given on 08-09, and its §2 predates the §V1 device run that
> failed. The addenda appended below (§1-CLEARED, §5-RESOLVED, and the
> struck-through #301 bullet) are patches over a body that now contradicts
> itself in places — which is exactly the stale-header shape this project
> keeps paying for. **Kept unedited as the dated record of what was pending at
> 15:30; do not work from it.**

**A dated snapshot INDEX, not a second queue.** Every item points at its
canonical home; verdicts get recorded THERE (`OPEN_ITEMS.md`,
`dispatch/DEVICE-PASS-RUNNING-LIST.md`, the OJAMD handoff). Assembled from:
the device-pass running list (read in full, 2,857 lines), `OPEN_ITEMS.md`
decision blocks (latest-dated-block-wins), `handoffs/NEEDS-OWEN-2026-08-09-
BACKLOG-RUN.md` (mostly answered — only survivors carried),
`handoffs/HANDOFF-2026-08-09-OJAMD-SESSION.md`, the wave-1/wave-2 handoffs,
and the #224 brief.

**The build for everything phone-side: OTA 2484** (`main` @ `75e5e08`,
Release, staged today 15:37 — https://owens-mac-mini.tail5663a6.ts.net). It
postdates every build requirement named in the device list (2418, PR #290
`c8759b9`, PR #291 `1ecaa86` — all ancestors). One caveat: **R2 (island
icon) needs a DEBUG build** — it is the one row 2484 cannot run.

---

## 1 · Decisions owed — no phone, no box, just your word

| What | The ask | Home |
|---|---|---|
| **#282 §7** ⭐ new today | The ruled guard measured: fixes case (a), but 282-B/D/E RED — it trades assistant-row dupes for user-row dupes, unbounded on id-less rows. Options: (1) rank consumers (in-flight first, settled fallback) — keeps #248 closed, partial on (a); (2) deterministic fallback id in `mapStoredMessage` — kills the unbounded arm only. Or neither/both. | `OPEN_ITEMS.md` #282 🛑 RESULT block; PR #304 parked |
| **#224 ballot** | Eight cards, each with a recommendation + deciding fact. Answer "approved" or flip by number. | `planning/224-APPROVALS-SITTING-BRIEF-2026-08-10.md` |
| **Privacy policy** | Four OWEN-confirm comments inline (no analytics SDKs · no iCloud sync · local-only notifications · contact/entity/date), then publish — `docs/privacy.html` per your 08-09 ruling; publishing is yours. #166a's hard stop for submission. | `planning/privacy-policy-DRAFT-2026-08-10.html` |
| **#321** (can wait) | Stop-in-reconcile-window semantics: abandon `pendingRun` outright vs mark user-abandoned and reconcile quietly (+2 sub-questions). Gates the lane; nothing urgent — current state is strictly better than pre-#315. | `OPEN_ITEMS.md` #321 |
| **#299 archive routing** (minor) | Fixed+merged, bars met, fail-open edges recorded. Sweep to archive now or hold? | `OPEN_ITEMS.md` #299 |

**Product questions from the 08-09 backlog — short answers suffice** (the
other three of the original eight were ruled 08-09):
1. **#257 voice:** deterministic capability block is screen-only; voice
   replies still compress to ~4 families aloud. Acceptable, or does voice
   need its own answer later?
2. **#257 vision:** should the block/sheet name image reading with a "when
   you attach a photo" caveat? Currently excluded by design.
3. **#257 sheet home:** permanent home — Settings, chat sheet (current), or
   Skills neighborhood?
4. **#292 Ruling 1:** abandoned runs turn's tokens never recorded (CTX gauge
   shows prior run, stale). Accept, or want a single final status read on
   cancellation?
5. **#295 follow-up:** want the literal runs status-poll recovery your
   ruling named (needs a durable run_id surfaced)?

## 2 · Corded phone sittings (device queue — canonical: `dispatch/DEVICE-PASS-RUNNING-LIST.md`)

Grouped by setup so each batch is one trip. Rough total if run straight
through: ~3.5–4.5 h; Group 8 is the big block.

- **Group 1 remainder** (paired+OJAMD, default state): #21 OJAMD-side chip
  tap · C1 `searchPlaces` n=20 · C3 `readLocation` fields · #184/#185
  teardown paths + same-filename attachments.
- **Group 2** (~35–40 min): the #162 Tasks / #163 Skills / #165 Insights
  drawer checklists — never run once. (Insights >600-session strip: check
  OJAMD's session count first — flagged ambiguous in the list itself.)
- **Group 3** (~15 min, Settings churn): #75 header widths · Display Zoom
  letterbox re-test · #186 scoped-permission arms.
- **Group 4** (~25 min, unpaired block): #61 titles incl. spoken-only
  (**carries 280-F's clause**) · #190 read-aloud interruptions · #123 share
  ×3 · #124 Face ID backgrounding · #225 confirmation fixture · #165
  unpaired half.
- **Group 5** (~15 min, Mac profile): #21 Mac re-confirm · #33 Apple Note
  round-trip.
- **Group 7** (~25–30 min): #93/#312 continuity-fabric kill/relaunch cycles
  (a, b, c′, d, e, f) — the oldest owed verification on the board.
- **Group 8** (~60–75 min, run last; A1/A1b need a second person): #129
  voice audition + engine log · #82 other-engine residual · E1 capture
  format · A2b engine-pin arms · #58/#179 "Ask Hermes" Control Center half ·
  #77 URL scheme · #56 Siri Stop + tailnet-unreachable · A1/A1b call
  interruptions · A2 BGAppRefresh execution half.
- **§R rows:** **R12** #257 capability-lever batch (4 steps, in order) ·
  **R13** #101-A1 recall-routing A/B button (~3 min — decides whether Shape
  A lives) · **R15** #140-D ATS mechanism · **R16** 56-U-H Siri hostless.
- **New this wave:** **279-F** (local-brain generation-failure retry — the
  question appears exactly once; needs the forced-trip harness, not
  Airplane mode) · **302-A/B** (mic provably cold until unlock, both arms —
  the 302-C contract is ruled, this is its compliance measurement) ·
  ~~**#301** device repro attempt (n≥5, native voice; sim-only so far)~~
  **#301 — CORRECTED 2026-08-10, this bullet was stale when written: the
  repro is SETTLED (deterministic, 3 occurrences / 0 clean), the site is
  symbolicated, and the fix is merged (PR #300). No repro attempt is owed.
  What the device owes is 301-C's NEGATIVE CONTROL, and it requires a
  FRESH INSTALL** — the discriminator is authorized-vs-notDetermined, not
  sim-vs-device, and an OTA upgrade-in-place preserves TCC grants so it can
  never reach the crashing path.
- **All three of the above now have checkbox rows** —
  `dispatch/DEVICE-PASS-RUNNING-LIST.md` **§V** (added 2026-08-10; §V1 =
  #302-A/B, §V2 = #301, §V3 = #303-A/B). §8's gap 1 is closed.
- **Debug-build-only:** **R2 / 250T-C** — island icon via the throwaway
  Live Activity button (~2 min). Needs a Debug stage, or I drive it on the
  preserved CC-250 sim whenever you say.
- **Optional:** **F7e** — repeat F7d under `approvals.mode: smart`.

**Passive / opportunistic — do NOT schedule:** Z4 (#295 iOS-revocation
path — screenshot if ever seen) · Z6 (#293(b) clock-skew delta on any
failed reconcile) · R1 (reminder phrasing on a natural evening ask) · R3
(tinted-icon glow glance) · #222 device arm (fold into slack) · #21
announcement-scan noise watch.

## 3 · The OJAMD sitting (canonical: `handoffs/HANDOFF-2026-08-09-OJAMD-SESSION.md`)

Twelve sections, paste-ready, in its suggested order. Headlines: **#271
rollout** (+ the still-unpasted `platform_hint` block) · **route-table
parity probe** (discharges CLAUDE.md's last ASSUMED) · **shim StartType →
Disabled** (one elevated command; makes Lane 5 reboot-proof) · Z7's OJAMD
half (+ #133/#143 recount) · #93 step 4 · #21 valid retest · #155 SHA
capture · config chores · #223 stale-sensors re-read · opportunistic probes
(#60 SSE, #132 auxiliary.vision config, #170, #24e, **241-E** if phone in
hand) · device-adjacent: **R6 #254-D** + **#303-A/B** (realtime host is
here, gateway currently off by your choice) + #138 self-barge-in + L5-E.

## 4 · The host sitting — decisions agenda (NEEDS-OWEN Part 2 §4)

#269-A build go · #270's 🔐 go (two trees + backend restart; state
vocabulary settles first, shared with #269) · #271 (overlaps §3) ·
reconciliation Q2 (voice/conversation-feed tenants → #309) and Q6 (sensors
leaning) · #309/#310/#311 routing.

## 5 · The Mac session (you driving)

- **#74 CarPlay Simulator pass** — ruled GO 2026-08-09, not yet run.
  ⚠️ 74-F is a safety bar: re-comment the entitlement + regenerate after,
  or the next signed device build fails and stalls the device queue.
- **304-H/I approvals arms** — the one 🔐 live-install go being requested:
  `approvals.mode: manual` on the Mac, bounce, run both arms, restore,
  bounce (listener verified each time per #264). Say go/no-go when you're
  at the desk.

## 6 · Waiting on Apple / sequenced — nothing to do now

- **#72** — SBP submitted, pending with Apple; PCC request files when it
  clears.
- **#45** — CarPlay grant filing is sequenced BEHIND #74's sim pass (ruled
  08-09).

## 7 · Cleared since the 08-09 NEEDS-OWEN file (so absence reads as decided)

The ~35-ruling decision pass (recorded at owning entries) · 302-C
(defer-until-unlock) · #241 retro-pin (LEAVE old sessions) · #290 (closed:
no trimming, measured-and-unbounded) · #317/close-out rule (ratified,
carve-out (a)) · #161, #273, #101 (both halves), #45, #72 (routed) · #306
O8 (ratified) · wave-1's seven lanes · wave-2: #315 fixed, #299 fixed,
#282 measured (→ §1), #279 already-landed discovered + header corrected.

## §1 CLEARED — 2026-08-10, same-day interactive review (addendum to the snapshot)

All five decisions and all five product questions were ruled in the
interactive session; **verdicts live at the owning entries**, per this doc's
own rule. In one line each: #282 §7 → RANK consumers (option 1 alone, the
per-change go) · #224 → APPROVED, all eight (Phase 0 dispatch owed) · privacy
policy → confirmed and STAGED at `docs/privacy.html`, uncommitted, publish
moment Owen's · #321 → abandon outright / live-stream-Stop transcript /
restore the HOLD · #299 → SWEPT to archive · #257 voice → screen-only stands ·
#257 vision → ADD with attach-caveat (work owed in #257) · #257 home → chat
sheet permanent · #292 R1 → **superseded knowingly** (it turned out already
ruled ACCEPTED on 08-09 — this index carried it as an open survivor in error;
the conflict was surfaced and Owen chose the final read anyway, filed as
**#322**) · #295 poll → skip for now.

## §5 RESOLVED — same-day addendum (2026-08-10 evening)

Both §5 lines are settled, one of them was stale when this index was
assembled: **304-H/I were ALREADY MET 2026-08-09 evening** (archived #304
records both arms + the restore; no 🔐 go was outstanding — this index
carried a stale request). **#74's sim pass was attempted and is BLOCKED by
the iOS 27.0 beta-4 sim runtime** (CarPlay display never comes up; 26.5 A/B
proves the runtime is the variable; app-side config verified correct).
**74-F exit gate MET** — entitlement re-commented, signed device build
green, tree clean. 74-A…E re-run when a newer runtime lands. **#45 stays
sequenced behind the pass — Owen re-affirmed 2026-08-10 with the blocker in
view.** Full record at #74's entry.

## 8 · Two documented gaps (flagged, not fixed here)

1. ~~**#301/#302/#303's device rows exist only as prose** inside R6/R7's
   write-ups and their OPEN_ITEMS entries — not yet checkbox rows in the
   device list. Whoever opens the next sitting should fold them in (§2's
   "new this wave" bullets are the content).~~
   **✅ CLOSED 2026-08-10 — folded in as `dispatch/DEVICE-PASS-RUNNING-LIST.md`
   §V** (§V1 #302-A/B · §V2 #301 · §V3 #303-A/B), with pointers added at §R6,
   §R7 and §F3 so a runner arriving at the old prose finds the rows. **Two
   things the fold-in found that this index had wrong**, both corrected
   upstream and noted in §2: **#301's bullet was stale** (repro settled, fix
   merged — what's owed is the negative control, on a FRESH INSTALL), and
   the #302/#303 evidence **straddles two log subsystems**
   (`org.aethyrion.talaria` for the capture/router lines,
   `org.aethyrion.talaria27` for AppLock), so a single-subsystem log filter
   cannot score §V1 at all.
2. `/tmp/gate-282/` logs are deliberately preserved as PR #304's evidence —
   confirm before anyone deletes them.
