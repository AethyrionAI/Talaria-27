# Everything pending — consolidated for Owen, 2026-08-10 **EVENING**

**SUPERSEDES `PENDING-OWEN-CONSOLIDATED-2026-08-10.md`** (assembled post-wave-2,
~15:30). That file is not wrong so much as overtaken: its §1 lists five
decisions that were all ruled the same evening, and its §5 asks for a go that
had already been given the day before. Read this one.

**Same contract as its predecessor: a dated snapshot INDEX, not a second
queue.** Every item points at its canonical home and verdicts get recorded
THERE — `OPEN_ITEMS.md`, `dispatch/DEVICE-PASS-RUNNING-LIST.md`, the OJAMD
handoff. If this file and an entry disagree, **the entry wins**; this one has
already been overtaken once in six hours.

**Build state, verified rather than remembered.** The phone (`whoGoesThere`)
is on **OTA 2484 = `main` @ `75e5e08`, Release** — confirmed by reading the
installed bundle version off the device, not by asking. **Every one of the 9
commits since is docs-only** (`git diff 75e5e08..HEAD` over `*.swift`,
`*.yml`, `*.plist`, `*.entitlements` is empty), so 2484 *is* current and no
reinstall is owed. **The one exception that matters: R12, R13 and R2 are
`#if DEBUG` and do not exist in this Release build** — verified by walking the
preprocessor nesting, not by grep. They need a Debug install.

---

## 1 · Decisions owed — just your word

Two, both from tonight's device run. **Everything the previous index listed
here is ruled** (see §7).

| What | The ask | Home |
|---|---|---|
| **#302 fix** ⭐ new | The mic is provably live behind App Lock. The fix defers voice-session start behind the unlock — which changes the Control Center flow you called your felt flow this morning. Open the lane, or sit with it? **My constraint if you open it: the bar must close the RACE, not the arm** — a green 302-A that still depends on Face ID winning a footrace is not a fix. | `OPEN_ITEMS.md` #302 🚨 RESULT block |
| **#323 shape** ⭐ new | Does App Lock become a **real gate** that every subsystem consults (one mechanism, one bar), or does each subsystem defer on its own (N mechanisms, N ways to miss one)? Plus three sub-questions in the entry: in-flight work when the cover drops · queue-vs-drop for sensor samples · keep/discard/hold a transcript written while locked (today: kept, silently). | `OPEN_ITEMS.md` #323 |

## 2 · Ruled but NOT BUILT — these need dispatching, not deciding

**This is the real backlog now, and it is the shift worth noticing: the queue
stopped being decisions and became work.** All five were ruled today; none has
code.

- **#224 Phase 0** — ballot approved all eight. OPUS-tier dispatch: Manual-card
  improvement + the mode scaffold behind it. Phases 1–3 stay closed until you
  ask for fewer prompts in so many words.
- **#282 ranking lane** — RANK the consumers (option 1 alone) is the
  per-change go. Bars re-pre-register in the entry before code. PR #304 stays
  parked as the measurement record.
- **#321** — semantics ruled (abandon outright · live-stream-Stop transcript ·
  restore the mid-window HOLD). Lane ungated, bars owed.
- **#322** — one bounded `GET /v1/runs/{id}` on cancel. Filed today,
  knowingly superseding the 08-09 acceptance.
- **#257 vision line** — add image reading to the deterministic block + 3a
  sheet, with the "when you attach a photo" caveat. Small; bars in the entry.

> **➡️ UPDATE, 2026-08-10 ~23:00 — PHASE B IS PARTLY RUN. Two of its three
> rows are done, and two of §3's stated blockers were already stale when
> this file was written.** The phone was **LAN-reachable** (`devicectl`
> `Transport Type: localNetwork`), so no cord was needed — a Debug build
> went on over OTA 2484 via the Xcode bridge. And **OJAMD's gateway is UP**
> (`:8642` → `{"status":"ok","version":"0.20.0"}`), so Groups 1 and 2 are no
> longer blocked.
> - **R13 → 101-A1 MISSED** (`armed=0/20`, `scored=20/20`, `errors=0`).
>   **Shape A is dead**; A-2/A-3 do not open. ❓ **one question waiting for
>   you in #101:** does the item continue as Shape B, or close?
> - **R2 → 250T-C MISSED, then the cause was found and FIXED the same
>   sitting.** #250 itself shipped the regression on 2026-08-05. Fix is
>   device-proven on `t27-250-island-compact-icon`; bars + gate + a re-run
>   are owed before merge. **The re-scope this looked like it needed is
>   cancelled — nothing owed from you.**
> - **R12 is the only Phase B row left**, and the Debug build stays on the
>   phone, so it is one tap away with no reinstall.
>
> Verdicts live at their canonical homes as this file's contract requires:
> `OPEN_ITEMS.md` #101 and #250, and §R's R13/R2 rows.

## 3 · Device queue — Phase B is staged and unrun

**Tonight's sitting stopped on purpose.** §V1 ran and FAILED (see §7); the row's
own instruction is stop-and-file, so nothing after it was attempted.

**Phase B — needs a cord AND a Debug install** (I drive the install via the
Xcode bridge; upgrade-in-place, pairing and data survive; it also gives live
console instead of post-hoc `sudo log collect`):
- **R13** #101-A1 recall-routing A/B (~3 min) — decides whether Shape A lives.
  The `router: CROSSCHAT` lines are the artifact; the results screen has **no
  error indicator** and cannot be read for this bar.
- **R12** #257 capability-lever batch (4 steps, in order).
- **R2 / 250T-C** island icon via the throwaway Live Activity button (~2 min).

**Still standing, unchanged, no Debug needed** (canonical:
`dispatch/DEVICE-PASS-RUNNING-LIST.md`): Group 1 remainder · Group 2 drawers ·
Group 3 Settings churn · Group 4 unpaired block · Group 5 Mac profile ·
Group 7 continuity fabric · Group 8 voice/Control Center (A1/A1b need a second
person) · R15 #140-D ATS · R16 56-U-H Siri hostless · 279-F (needs the
forced-trip harness, not Airplane mode) · **§V3** #303-A/B (OJAMD only) ·
**§V2** #301's negative control (**fresh install — runs LAST, ever**;
an upgrade-in-place preserves TCC grants and can never reach the path).

**Group 1 and Group 2 are blocked while the OJAMD gateway is off** — they're
paired-to-OJAMD rows. Worth pairing with §4 when you next bring it up.

**Passive / opportunistic — do NOT schedule:** Z4 · Z6 · R1 · R3 · #222 device
arm · #21 announcement-scan noise watch.

## 4 · The OJAMD sitting — unchanged from the previous index

Canonical: `handoffs/HANDOFF-2026-08-09-OJAMD-SESSION.md`. Twelve sections,
paste-ready. Headlines: **#271 rollout** (+ the unpasted `platform_hint`
block) · **route-table parity probe** (discharges CLAUDE.md's last ASSUMED,
and OJAMD is the host the phone actually talks to) · **shim StartType →
Disabled** (one elevated command; makes Lane 5 survive a reboot) · Z7's OJAMD
half · #93 step 4 · #21 valid retest · #155 SHA capture · #223 stale-sensors
re-read · opportunistic probes · device-adjacent **R6 #254-D**, **§V3**, #138,
L5-E.

## 5 · The host sitting — decisions agenda, unchanged

#269-A build go · #270's 🔐 go (two trees + backend restart; state vocabulary
settles first, shared with #269) · #271 (overlaps §4) · reconciliation Q2
(voice/conversation-feed tenants → #309) and Q6 (sensors leaning) ·
#309/#310/#311 routing.

## 6 · Blocked or waiting — nothing to do

- **#74 CarPlay** — the sim pass was attempted today and is **blocked by the
  iOS 27.0 beta-4 simulator runtime**, which never brings up the CarPlay
  display (a same-host iOS 26.5 A/B brings it up instantly). App-side config
  verified correct; **74-F exit gate MET**. Re-stage takes ~10 min when a newer
  runtime lands; check the runtime first.
- **#45** — CarPlay grant filing **stays sequenced behind** that pass. You
  re-affirmed this today with the blocker in view: it has to be right first.
- **#72** — SBP submitted, pending with Apple.

## 7 · Cleared today (so absence reads as decided, not forgotten)

**Ruled:** #282 §7 (rank consumers) · #224 ballot (all eight) · #321 (three
semantics) · #299 (swept to archive) · #257 ×3 (voice screen-only · vision
ADD with caveat · chat sheet is the permanent home) · #292 R1 (superseded
knowingly → #322) · #295 status-poll (skip) · #45 (stays sequenced).

**Done:** the **privacy policy is PUBLISHED** and live at
`https://aethyrionai.github.io/Talaria-27/privacy.html` (effective 2026-08-10,
developer of record James Jones, footer-linked) — **166a's public-URL hard
stop is satisfied**. Two accuracy fixes happened before it went out, not
after: a claim that the app indicates realtime sessions (that indicator is
**#320, NOT STARTED**) was removed, and internal tracker comments were
stripped from the published source.

**Corrected:** #166a's "no privacy manifests" paragraph (they landed
2026-07-22 and ship in the bundle) · #301's header and index line · #302's
header and index line · the §V lane's own #301 bullet · #74/#45.

**Measured:** **§V1 → 302-B FAILED.** The microphone is live behind App Lock —
HOT for 34.92 s while `cover=locked`, going hot 3.87 s *before* the biometric
was cancelled, with a second unplanned reproduction going hot 820 ms *before*
App Lock even evaluated. **302-A's green is a 470 ms Face ID footrace, not a
gate** — the voice path never consults lock state at all. Root cause: App Lock
is an opaque `UIWindow` over the screen and nothing more. Filed **#323** for
what else ran behind that cover: a complete inference turn that committed to
the transcript, and the sensor pipeline collecting GPS + health and
**attempting to upload them** — the uploads failed only because your OJAMD
gateway happened to be off. **Severity bounded the same evening:** the device
passcode gates the lock-screen path, so there's no device-lock bypass; the
exposure is an unlocked phone in someone else's hands, which is exactly App
Lock's own threat model.

## 8 · Gaps

1. ~~#301/#302/#303 device rows exist only as prose~~ **CLOSED** — they are
   `dispatch/DEVICE-PASS-RUNNING-LIST.md` **§V** (§V1 · §V2 · §V3), added
   2026-08-10.
2. **`/tmp/gate-282/` logs are deliberately preserved as PR #304's evidence** —
   still true, still needs to survive until the #282 ranking lane runs.
   Confirm before anyone deletes them.
3. **New:** tonight's App Lock evidence is preserved at
   `handoffs/302-applock-2026-08-10/v1-evidence.txt` (397 filtered lines) and
   the raw `v1.logarchive` is in this session's scratchpad — **the scratchpad
   is session-scoped and will not survive**; if the archive matters beyond the
   filtered extract, move it somewhere durable.
