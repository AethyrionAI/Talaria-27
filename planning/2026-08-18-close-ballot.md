# The Close Ballot — 2026-08-18 night

Product of a six-agent audit of every live entry in `OPEN_ITEMS.md` (all ~110 items,
classified from latest dated blocks, never headers; load-bearing claims verified
against git, the tree, and live process state). **How to answer:** "go with
recommendations" is a complete answer; name exceptions by number. §3's starred
questions need your actual words.

Already ruled tonight (banked, not re-asked): 3E cutover GO (Wed/Thu build) ·
#302/#323 App-Lock fix GO (Thu PM) · #354 token-guard FILE+FIX · 271-F was already
met (it was the privacy round-trip bar, not the venv retirement).

**Headline: 67 of ~110 live items close tonight** (13 new, smaller filings come out
of them). The board after: ~55 entries, of which only ~10 are active build work.

---

## §1 CLOSE — done, verified, zero residue (or residue re-homed as noted)

**Recent batch (8):** #351 (both plugin PRs merged 08-16, 12 bars met, deployed;
F13 → §3-9) · #354 (with tonight's token-guard filing) · #355 · #357 (steer
affordance gap → new item N14) · #361 · #362 · #364 (archive-pointer chore rides
the sweep) · #366 (dedupe duplicated block at move).

**Merged/verified but never swept (26):** #261 (261-E = §3-5 glance) · #271 (all
bars met 08-15/16) · #282 (merged `78f1a45` 08-11; index line badly stale) · #283
(after N1 files 3E) · #287 · #288 (both hosts re-run clean; Mac verified read-only
tonight: zero orphans) · #289 · #290 (phantom sweep) · #297 · #301 · #313 (7/7 on
device; gate-grep repoint in same commit) · #316 · #317 · #320 (320-E is in fact
published — docs/privacy.html:73 live; dated correction at close) · #321 · #322 ·
#326 (relocate the misfiled #321/#322 block) · #327 (restored-✓ residual → N4) ·
#331 · #333 (minors → N6) · #335 · #337 (write the 08-15 adoption block into the
entry; successors → N5) · #338 (router-gate Q = §3-7) · #341 (dev-button gap → N6)
· #343 (calendar-reap → N3, then header+RT-G corrected to MET) · #346 (Mac half →
N8) · #347 (rules promoted to CLAUDE.md first).

**Old guard, done long ago (10):** #3 · #6 · #8 (phantom sweep) · #21 (OJAMD chip
confirmed 08-15; UUID-prefix cosmetic noted under #311) · #82 · #99 (the "owed"
WKContentRuleList decision shipped under archived #259) · #155 (0.20.1 pinned by
reflog; the "constant" never existed — the entry's table IS the pin) · #159 ·
#160 · #177 (app-side mitigation shipped 08-09).

**#225 family, all bars met (10):** #225 (four device bars 08-16) · #227 · #228
(L0-D scored per §3-3) · #229 (residual per §3-2) · #230 · #235 (235-E met 08-04;
NOT blocked on 3E — 235-F per §3-4) · #237 · #250 · #252 (phantom sweep) · #255
(08-06 ruling written upstream first).

**Old measurement items (4):** #205E (closes into #334) · #208 (successor per
§3-8) · #210 · #210A.

**Count: 58.**

## §2 MOOT-CLOSE — overtaken by deletion/retirement (8)

- **#7** — `ModelsShimClient` is gone from the tree (verified by grep).
- **#116** — shim out of the model path (#223 L5), services Stopped+Disabled,
  plugin 0.5.0 replaces both. Dead `ProvisioningService.swift` → N8.
- **#117** — #352 deleted `SensorUploadService` (1,149 lines) + the backoff code
  it measured; #346 retired the connector it hammered.
- **#137** — #352: nothing starts a sensor at launch; the trap is structurally
  impossible. Query-time consent question → N12.
- **#188** — the watchdog task is deleted, its relay/connector retired. Recorded
  honestly at close: the MAC still runs its own connector shape (verified live
  tonight) — that surface is N8's, not a watchdog item's.
- **#189** — #238 deleted the whole notification subsystem (grep-verified).
- **#267** — superseded → #306 (closed+archived 08-11); composer half shipped in
  #357 §2.6.
- **#345** — did not reproduce 08-15 (real health data returned). Fully moot if
  §3-6★ answers "no active-energy/sleep data"; else the narrow residual rides N8's
  lane as a one-liner.

**Running total: 66 (+#257 = 67 if §3-1★ scores tonight).**

## §3 Micro-rulings (★ = needs your words; others have a recommendation)

1. ★ **#257 3a-C** — open a fresh chat, tap "WHAT CAN TALARIA DO?": does the sheet
   answer better than the model does? Your pass/fail is the last bar. (1 minute,
   closes #257.)
2. **#229** refusal-string token residual → declare moot (nothing overflows
   post-#230/#232; #337-D's instrument exists if it resurfaces). REC: moot.
3. **#228** restated L0-D → score MET on the corded coda evidence (two live turns,
   instrument on, deferred flush fixed). REC: MET.
4. **#235** 235-F → accept #246's closure inheritance (same mechanism). REC:
   accept. (Alternative: one dead-stream line on Saturday.)
5. **#261-E** — your one-glance "the split works" grant. REC: grant.
6. ★ **#345** — does your Health app actually hold active-energy and sleep data?
   (No → fully moot.)
7. **#338** router-gate question (gate the guard on router action-intent) → REC:
   decline; the guard is shipped and proven, don't complicate it.
8. **#208** D4-decode successor question → REC: accept-as-documented; argument
   integrity is now #336/#340's territory.
9. **#351 F13** (CLI-paired rows never auto-rotate) → REC: accept as recorded
   design note; revisit only if a CLI pairing is ever used in anger.
10. ★ **#101** cross-chat memory — Shape A died on device (0/20 armed). Continue
    as Shape B (L3 preferences, ≤120 tok, held since 08-10), or close the item?
    REC: close; refile if wanted later.
11. ★ **#173** attachment-blindness → REC: ship the never-claim floor only
    ("not known to support images"), demote capability-surfacing to WATCH.
12. **#109** iPad multi-window → the shipped single-window refusal IS the v1.0
    answer (#166 ruling). REC: close; refile post-launch if wanted.
13. ★ **#254-D / #303** — both need a REALTIME-configured host. Does OJAMD have
    an OpenAI/realtime key? (Mac has none.) No key anywhere → #254 closes as
    unrunnable-as-written, #303 → WATCH.
14. **#266** board re-org → REC: drop and close — tonight's sweep IS the
    actionability separation.
15. **#359** compose fusion (one occurrence, mechanism unknown) → REC: convert to
    WATCH; trigger = recurrence (artifact durable, #358-style witness named as the
    next step if it fires).
16. **#339** instruments-as-regression-gate → REC: WATCH, trigger = #342 ruling.
17. **#342** kanban → REC: invariants-only (no per-entry status tokens);
    `oi-invariants.py` already caught a real collision. The two unbuilt checks
    ride N6.
18. ★ **#340** fix route — the model omits the due date; both prose fixes
    falsified 08-15. (a) resolve a bare clock time APP-SIDE in `performCreate`
    (which already owns `isPastDue`/`isNextMorning`), or (b) the #200S
    required-field schema rollback (twice shown to convert omissions into WRONG
    values). REC: (a), Friday's lane.
19. ★ **#325** forge-on-light-themes route — (a) retune per light palette,
    (b) demote to non-text, (c) add a `forgeText` token, (d) accept+document.
    REC: (c) — least invasive, no curated-hue retune.
20. ★ **#251 P1 doorbell** — parked since 08-06: nothing vs self-hosted ntfy.
    REC: nothing for v1.
21. ★ **N8 go** — execute #346's disposition on the MAC (disable
    `mcp_servers.hermes_mobile` in config.yaml, bounce gateway + relaunch
    desktop app; retire `hermes-mobile-service.py`; delete dead
    `ProvisioningService.swift` / `downloadAgentFile` in a gated app PR). Live
    config edit → your per-experiment go. REC: go this week.
22. ★ **About-page drain** (your 08-16 observation "The drain must not be updated
    on the about page") — name the exact screen/value you saw stale so N9 can be
    filed actionably.

## §4 New filings (per #268 — the day they're named)

- **N1** 3E cutover lane (RULED GO tonight; absorbs #283's evidence clock; #328
  route 1 rides it).
- **N2** initialize() token-guard: keychain miss must not destroy the pairing
  (from #354; RULED file+fix).
- **N3** calendar-reap under-delete — up to 17 test events possibly on the real
  calendar (from #343). **Glance at your calendar for mid-Aug test events.**
- **N4** restored ✓ chips assert completions the app never witnessed on runs
  nobody stopped (from #327; entangled with #328 route 1 / N1).
- **N5** #337 successors: decline-path measurement + 337-H (.required) + the
  rollback arm for measuring the promotion.
- **N6** instrument/test hygiene bundle: #333's four minors, #341's dev-button
  single-cell gap, #224's poll-then-decline hang idiom, #342's two unbuilt
  invariant checks.
- **N7** the #47 billing-cap decision (un-filed residual from #268).
- **N8** retire the MAC's legacy hermes-mobile surface (config, service, dead
  code) — #346's second half.
- **N9** about-page drain display (pending §3-22★).
- **N10** Private Relay detection row in diagnostics (re-homed from #24e; chat
  still speaks HTTP to a tailnet IP).
- **N11** #156 successors: 156c Memory (scope decision: local files vs Honcho)
  and 156e Projects — then #156's umbrella closes too (+1 to the count).
- **N12** query-time sensor consent question (from #137's close).
- **N13** — (reserved; #21's UUID-prefix cosmetic noted under #311 instead).
- **N14** steer/interrupt unreachable while composer is `busyNoCommit` with the
  hold slot taken (from #357-E's verdict).

## §5 The board after (what genuinely stays open)

**This week's build lanes:** N1/3E (Wed PM–Thu) · #302/#323 App Lock (Thu PM) ·
#340 route per §3-18 (Fri) · N2 token guard (fits Fri) · free-bucket quickies:
#293(d) two-line fix, #198B off-main AVAudioSession, #264 half-2's
one-banner-one-truth (or defer), N8's app-side deletions.

**Real open items:** #24 (one diagnostics row → N10 then closes) · #138 (source
read: who renders realtime remote audio) · #148 (NVIDIA prune on OJAMD gateway —
box-side chore) · #150 (discovery pass, gated) · #156 (→N11 then closes) · #166
(submission gate, pre-launch) · #180 (scoping Q + two numbers) · #223 (umbrella;
gates #309/#310/#311 + N8) · #236 (HEATING — consolidate occ 3/4/5 into the
entry; lane if it fires again) · #253 · #263(a)+PID-log chore · #269 (269-B
publication, gates #308) · #305 · #309 (count corrected 18→16) · #310 · #311 ·
#318 · #329 · #330 · #334 · #336 · #348 (10-min Mac check — will just do it) ·
#359 (→WATCH per §3-15) · #365.

**Watches:** #45 · #60 · #72 · #74 · #109 (unless closed per §3-12) · #170 (re-check
against 0.20.1) · #182 · #219 (gate-grep hazard noted) · #224 · #241 (241-E rides
next OJAMD sitting) · #308 · #314 · #324-W1/W2 · #344 · #358 · #363 (~08-25).

## §6 Saturday device day (rebuilt from the audit; cheap-first)

Phone-minutes tonight/any evening (don't need Saturday): #350-D 30-s fixture ·
#349+#367 shared 60-s reopen check (needs a fresh OTA carrying #320/#321 — I'll
stage it with the 3E build).

Saturday proper:
1. #58 + #179 — cold-boot double-tap discriminator (30 s; closes #179, advances #58).
2. #360 dictation pass (1-s finish grace).
3. #302/#323 closing bars (if Thursday ships).
4. #312(b) gateway-restart-mid-turn (Mac-side bounce while streaming).
5. #329/#330 measurement bars.
6. #249F-D one evening reminder (tonight-or-tomorrow question).
7. #162/#163/#165 short re-confirms (one bar + two + two) · #190's two checks ·
   #61 standalone title check · #121/#122 resume/spend rows · #123 share-sheet
   walk · #124's seven App-Lock checks (folds into #302/#323 verification) ·
   #112 Comic Book live-switch · #77 URL-scheme two taps · #33 Notes write ·
   #222 image arm (opportunistic) · #220/#198A engine-pinned voice re-checks ·
   #332-c iPad fixture measurement.
8. If OJAMD sitting happens: 241-E (2 min) · #148 NVIDIA prune · N8's OJAMD
   glance (desktop-app relaunch clears the last legacy child).

## §7 Mechanical chores riding the sweep (no ruling needed)

Archive moves verbatim + `oi-split-verify.py` per batch · INDEX regeneration ·
~35 stale headers corrected (incl. #349/#350/#367 merge-blindness, #362's moot
residue line, #349's falsified retest note written back) · #312's Group-7 result
block written into its entry · #308 upstream pointer for today's ruling · #326's
misfiled block relocated · #366 dedupe · 364-E's archive pointers to #21/#277 ·
gate-grep repoints for #313/#219 · CLAUDE.md: #347's scoring rules + #264's
gateway_state.json diagnosis paragraph + the "zero hermes-mobile processes"
line scoped to OJAMD-only (Mac verified otherwise tonight) · 279-F row added to
the device list; 340-B row removed (met 08-15).
