# Device pass — running list

**A living list, not a dated pass.** Items are added as they are found and struck
when a verdict is recorded. Unlike `OPUS-T27-DEVICE-PASS-2026-07-25.md` this is
never "finished" — it is the queue that fills up between sittings.

**Started 2026-08-01.** Owen drives the phone; Claude reads logs and records
verdicts.

---

## How to use this

- **Record PASS / FAIL / PARTIAL / UNRUNNABLE.** PARTIAL and UNRUNNABLE are real
  outcomes. Do not round a partial up.
- **If a check cannot be performed as written, that is a defect in THIS
  DOCUMENT.** Say so and move on; never improvise a substitute check and record
  its result as a pass. (Carried from the 07-25 pass, where it earned its place.)
- **Log reads:** the app's own `Logger(subsystem:)` lines are NOT reachable from
  `idevicesyslog` — that is unified logging and the Mac CLI cannot see it (#133,
  proven on hardware). Use the Xcode bridge's `GetConsoleOutput`, and filter with
  `oslogSeverity: ["default"]` — its `pattern:` argument silently returns zero
  units for text that IS present. `scripts/device-pass-capture.sh` covers system
  processes only (`chronod`, `AppIntents`, `runningboardd`).
- **Verbose diagnostics** live behind the Developer screen's `verboseLogging`
  toggle. Several checks below need it ON.
- **Battery runs:** foreground and on power. Backgrounding the phone kills a run.

---

## ⚑ OWEN-SIDE — read this before scheduling a sitting

Two kinds of thing here: **decisions** (no phone needed, answer any time) and
**prerequisites** (things that must exist before a check can run). Added
2026-08-01 because both were scattered inside the sections below, where they only
surface once you are already holding the phone.

### Prerequisites — the sitting does not work without these

| for | you need | why it bites |
|---|---|---|
| **A1** (the top item) | **a second phone, or someone who will call you** | A1 is a real incoming call mid-session. There is no software substitute — the whole point is the OS interrupting us for real. **This is the single prerequisite most likely to end a sitting early.** |
| **A2** | to background the app **overnight** | the system decides when `BGAppRefreshTask` runs; it cannot be forced. Start it before bed on a sitting day, read the log the next morning. |
| **F3** | to **DELETE the app** | ⚠️ **destructive — local sessions and the Keychain stamp go with it.** Export anything you want from Battery Results FIRST. Run F3 **last** in any sitting for this reason. |
| **F5** | a **> 25 minute** induced connector outage | the window IS the check — the original close scored a false PASS on a short one. Do not squeeze this between other checks. |
| **B1 / F6** | the `probe/t27-130-halfduplex` branch **built to the phone** | say the word and I will stage it (OTA or corded). It is a separate build from `main`, so B1 cannot share a sitting with the `main` checks unless we reinstall between. |
| **C1–C4** | phone **foregrounded and on power** | backgrounding kills a battery run outright. |

### Decisions owed by you — no phone, no build, unblock other work

| # | the question | what it unblocks |
|---|---|---|
| **D2** | **Should LAN-hosted backends work at all?** `http://192.168.x` and MagicDNS names are ATS-blocked app-wide today; only the Tailscale CGNAT range is excepted. | If yes, it needs its own measured arm — and note `NSAllowsLocalNetworking` was only ever tested against a **CGNAT** host, never a `192.168.x` one, so do not assume the key does what its name says. If no, we close the ATS thread. |
| **#152** | **Pick the pairing-surface label** — "Pairing & Devices" / "Manage Pairing" / "Paired Devices". | It is a rename, then code. Nothing else is blocking it. |
| **#164** | **Close the old UI flake, or formally quarantine it?** | Its own bar is *three consecutive green runs*; we have **one** (2026-08-01, 8/8). I did not close it on your behalf — meeting a bar is not the same as being tired of it. Your call whether the bar still earns its cost. |
| **#170** | **Run #148's discriminator, or close as answered-for-the-world-that-exists?** | Neither shape is reachable on OJAMD — every real job carries a null `model_snapshot`. The discriminator is one read of the Mac's `cron/jobs.json`; I can do it if you want the answer. |
| **#47** | **Does the billing cap still matter?** | #47 is otherwise closed and in daily use. This residual is currently filed **nowhere** — it dies unless you say to keep it. |
| **tracker** | **Retire the old-style `## N.` headers?** | #198 and #199 each have two entries because the numbering convention changed mid-project. I documented rather than merged them — collapsing duplicates in a 14k-line file is a bigger call than a nit sweep should make alone. |

### Decisions owed by you — not blocking this list, but open

- **#99** — WKContentRuleList: accept the current behaviour, or fix it? Pre-launch.
- **#116** — no route to an empty token slot; needs a spec/decision before its DoD
  is even runnable.
- **#132** — host-side image attachments: your model-vision/config question, plus
  two placeholder strings.
- **#166c** — a Tailscale-only host is **structurally unreviewable** by App Review.
  A reviewer-reachable server decision is a launch gate, not a nicety.

### What needs nothing from you

I can run these solo whenever: **§G**'s source-confirms (#151/#153), **#128**'s
archaeology, **#216A**'s re-read, **E1**'s isolated build, and staging B1's branch.
Say go and they happen without a sitting.

---

## A · #198 — the last open question, and the only user-facing risk here

### A1 · Real interruption, both engines · **[OWEN + PHONE, CLAUDE READS LOG]**

**This is the highest-value item on the list.** The 2026-08-01 pass proved there
are no false POSITIVES — three app deactivations were correctly filtered, zero
spurious "Audio interrupted." It proves nothing about false NEGATIVES, and the
two are not symmetric:

- an unwarranted `.interrupted` **self-recovers** via the route-change handler
- a **missed** interruption leaves a **dead capture chain that still looks
  alive** — the UI says listening, the mic is gone

**DO:** start a live voice session, then have someone call the phone. Repeat for
**both** engines (`LiveVoiceSessionService` and `NativeVoicePipelineService` —
the Talk screen's engine selector).

- **PASS:** the session reports interrupted, and after declining/ending the call
  it resumes or ends cleanly — no state where the UI claims to be listening and
  nothing is captured.
- **FAIL:** UI still says listening after the call; speech produces nothing.

**Claude captures:** `didBecomeInactive` with `source == .system` (verbose ON),
and whether `AudioInterruptionRule.isInterruption` returned true. Also
`resumptionRecommendationNotification` and its `.shouldResume` value on call end.

**Closes:** #198's last open question, plus open questions A and B.

### A2 · `BGTaskScheduler` app-refresh actually fires · **[OWEN + PHONE]**

The migrated `submitTaskRequest` completion path has **never run** — the
2026-08-01 pass never backgrounded the app.

**DO:** background the app and leave it. Overnight is fine; the system decides
when `BGAppRefreshTask` runs.

- **PASS:** an `app-refresh scheduled (earliest +15m)` line, and later evidence
  the refresh executed.
- **FAIL:** a `submit failed:` line, or no scheduling line at all.

**Note the asymmetry that motivated the migration:** the old throwing `submit`
UNDER-reported ("to capture all error conditions" is Apple's own deprecation
reason), so a submit that didn't throw was never proof it landed. This check is
the first time we see the real answer.

---

## B · #130 — the half-duplex A/B, owed since 2026-07-20

### B1 · Half-duplex gate vs talk-over barge-in · **PARKED 2026-08-01 — kept as a REMINDER**

> **Owen 2026-08-01: the original trigger for #130 is no longer a concern, but
> keep this parked — "we need to get to the bottom of it."** The *it* is the
> engine-identification gap below, and B1 is the sharpest illustration of why it
> matters.
>
> **B1's design assumes we know which engine is running, and until today we did
> not.** #130's gate lives in `NativeVoicePipelineService`. If a comparison run
> silently used the **realtime** engine — which is what happened to A1 — then
> B1 would compare probe-branch-realtime against main-realtime and conclude the
> gate does nothing, **because the gate was never in the path.** A null result
> that looks like evidence.
>
> That is not hypothetical any more: A1 spent two real phone calls and a second
> person's time before anyone could say which engine had been tested.
>
> **Do not run B1 until the engine is named in the log** (fixed 2026-08-01 —
> `voice session starting on engine …`) **and the run quotes that line.** The
> same caution applies retroactively: **any past voice verdict that did not name
> its engine may have measured the other one.**

Branch `probe/t27-130-halfduplex` (on origin **and** local; DO NOT DELETE — #130
is open). It is `.default` session mode, no `setVoiceProcessingEnabled`, and a
software gate discarding recognition while TTS `isSpeaking` + 300ms hangover.

**DO:** build the probe branch to the phone, hold a voice conversation, compare
against `main`.

- **The trade being judged:** crisper TTS (no ducking) vs losing the ability to
  barge in while the assistant speaks. **This is Owen's call — it is a
  preference, not a measurement**, which is exactly why it has sat this long.

**Weight:** #105/#141 note that the realtime engine may need the identical gate
at its transcription ingest, so this verdict now decides two engines, not one.

---

## C · Measurement items — cheap to fold into any sitting

### C1 · `searchPlaces` n=20
Never run at n=20. Foreground, on power.

### C2 · #206's row set
Outstanding from the #206 lane.

### C3 · #212 `readLocation` dropped-country delta
The MapKit migration (`CLGeocoder` → `MKReverseGeocodingRequest`) changed which
fields come back; the `country` delta is disclosed in the tracker but not
measured on device.

### C4 · Matched-thermal replication of OPEN_ITEMS #215 / #216
**These are the measurement items, NOT the PR numbers** — the sequences differ.
Both verdicts carried a stated thermal confound running AGAINST the winner, so a
matched-thermal re-run would strengthen conclusions that are currently honest but
qualified. Long; only worth a dedicated sitting.

---

## D · Spotted, never chased

### D1 · Cold-route timeouts at launch
`:8765/models` and `:8000/v1/commands` timed out at launch while push/register to
the **same relay** succeeded four seconds later. Reads like a cold Tailscale
route rather than a service being down. **Not diagnosed.** Worth one deliberate
cold launch with verbose on.

### D2 · LAN-hosted backends are ATS-blocked · **[DECISION FIRST, THEN TEST]**
`http://192.168.x` and MagicDNS names have **no** ATS exception — only the
Tailscale CGNAT range `100.64.0.0/10` does. This explains the
`listSessions: 'Mac Mini' unreachable` line seen on 2026-08-01.

**Owen decides whether LAN backends should work at all.** If yes, it needs its
own measured arm in #166b's harness (probes inside the app test host, so
`URLSession` obeys the real plist — `curl` does not exercise ATS). Note
`NSAllowsLocalNetworking` was tested only against a **CGNAT** host and has never
been tried against a `192.168.x` one. **That is the untried arm** — do not assume
the key does what its name suggests, because for CGNAT it did not.

---

## E · Probes that are deliberately NOT tests

### E1 · `installTap` double-install · **[ISOLATED BUILD, NOT THE SUITE]**
Does the migrated `AudioNodeTap.install` THROW on a double-install where the old
API raised an uncatchable ObjC exception?

**Deliberately not written as a test:** if the successor still raises, it takes
down the test host rather than failing, which would cost a green suite and teach
nothing. Wants a throwaway build with one deliberate double-install.

**Until it runs, the migration's rationale is well-founded INFERENCE and is
labelled as such in #198.** The preflights (#82's format check, #128's `removeTap`
adjacency) prevent the failure; this probe only prices the residue.

---

## F · Absorbed backlog — device debts that were filed nowhere runnable

**Added 2026-08-01 from the second Hermes OPEN_ITEMS audit (Part 1C).** These
existed only as "device verification owed" sentences inside items whose headers
read closed. That is the same failure as `#133 landed eight days late`: **a
finding recorded where nobody looks is not recorded.** They live here now; the
tracker entries point at this list rather than restating the checks.

**Grouped by SETUP STATE, not item number** — toggling pairing is the expensive
part of a sitting, the checks are cheap. Work top to bottom and you change state
four times total.

### F1 · PAIRED + CONNECTED (start here — this is the default state)

| # | check | pass |
|---|---|---|
| **#121** | Resume a session that has prior reasoning | thinking panes restore from stored messages |
| **#122** | Open a session with known usage | spend row shows real numbers; `$0.00` only where genuinely unknown |
| **#191** | Airplane mode ON with **on-device** active | header title + model pill name the ACTIVE brain, not the stale Hermes session |
| **#192** | On-device active → ask for a 500-word summary | app does **not** silently switch itself away from on-device |
| **#193** | Trigger any destructive-action confirmation | the **Cancel** button renders (iOS 27 regression) |
| **#147** | Inbox-alert notification: **cold** tap, then warm tap | no crash on either. **Cold is the mis-verified case** — a merge commit plus one warm observation is what closed this wrongly last time |
| **#146** | Diagnostics push row after a healthy launch | row is NOT stuck on `TOKEN HELD · AWAITING RELAY`. Note: seeing the push arrive ×4 does **not** falsify this — that count is #143, relay-side |
| **#112** | Settings → toggle system appearance while foregrounded | Comic Book re-skins villain↔funnies **without relaunch** |
| **#184/#185** | Exercise all three ChatStore teardown paths; send two attachments with the **same filename** | teardown clears consistently; each attachment resolves to its OWN local file. Sim-only today |

### F2 · STANDALONE / UNPAIRED

| # | check | pass |
|---|---|---|
| **#61** | Create local sessions, read the drawer | on-device titles + previews are distinct, not near-identical. **Must be standalone** — the connected drawer is server-fed and never touches `conversation.title`, which is why the paired check is meaningless here |
| **#190** | (a) switch sessions during read-aloud; (b) force a session-open failure | (a) read-aloud stops; (b) failure banner appears. **The only two unexercised checks left on #190** — everything else cleared 2026-07-27 |
| **#123** | Share into the app from Safari (URL) and Photos (image) | composer receives it, focused, works unpaired on the on-device brain |
| **#124** | Background → foreground with Face ID lock on | overlay covers the scene root; passcode fallback offered (never biometry-only) |

### F3 · FRESH INSTALL (app DELETED, then reinstalled — do these together, the setup is expensive)

| # | check | pass |
|---|---|---|
| **#189** | First dispatched send on a fresh install | the OS authorization prompt appears (status was `NotDetermined`, never `Denied`), and the Diagnostics panel reports the REAL `UNAuthorizationStatus` — no false green. **This is the last blocker-shaped verification** |
| **#137** | ⚠️ **NOT RUNNABLE AS FILED — needs a rewritten check first.** The 2026-07-25 pass scored UNRUNNABLE, and the spec's "revoke/disconnect FIRST" setup is actively wrong: disconnect no longer produces a re-migratable device and neither does deleting the app. **Do not attempt until someone writes a sequence that can actually reach the un-stamped state.** Queued as a WRITING task, not a device task | — |

### F4 · LOCKED DEVICE

| # | check | pass |
|---|---|---|
| **#81** | Let a run finish while the phone is locked | push carries **Reply**; long-press → Reply → headless post lands; the NEXT push also carries Reply |

### F5 · INDUCED OUTAGE (longest — run last, or on its own)

| # | check | pass |
|---|---|---|
| **#117** | Induce a connector outage and hold it **> 25 minutes** | drains back off and STAY backed off; outage rate < 50% of healthy. **The window is the check** — the original close scored a false PASS on a short window, and the 27-minute run showed decay |

### F6 · Voice — same physical sitting as B1

| # | check | pass |
|---|---|---|
| **#129** | Audition a voice mid-session | no crash, session survives, mic live afterwards. Owed since 2026-07-24. Known-and-accepted: native-engine sessions share the assistant TTS instance |
| **#58 / #179** | First Control Center tap from cold | action does not report success before the widget extension exists. **One check closes both** — #179 is chained to #58's pass by its own decision point |

---

## G · NOT device work — routed out of this list

Filed here only so the audit's Part 1C list is fully accounted for. **Do not
carry these into a device sitting.**

- **#151 / #153 — source-confirm, not device.** Both need a Mac shell read before
  any device check is meaningful (`grep testConnection`; determine whether hosts
  are stored as one record or already an array). Their spec makes PHASE 0 CONFIRM
  mandatory precisely because Bundle B shipped with 2 of 4 premises wrong.
  #151's three device shapes (live / stopped / black-holed host) only become
  runnable after that.
- **#152 — a naming decision, not a check.** Needs Owen to pick a label
  ("Pairing & Devices" / "Manage Pairing" / "Paired Devices"), then it is code.
- **#128 — source archaeology.** Is the `removeTap` fix dead defensive code, or
  was the repro route never recorded? Answerable from the tree; costs no device
  time. (Its physical re-verify is the same test as #129 above.)
- **#170 — probably unanswerable as filed.** Neither shape is reachable on OJAMD:
  every real job carries a null `model_snapshot`, and #148 suspects 0.19 stopped
  writing `*_snapshot` at all. **Either run #148's cheap discriminator (read the
  Mac's `cron/jobs.json`) or close it as answered-for-the-world-that-exists** — do
  not put it in a device sitting expecting it to resolve.

---

## Recorded verdicts

### A1 — **PARTIAL**, 2026-08-01, corded whoGoesThere, PID 14087, two real calls

> **⚠️ CORRECTED within the hour, after Owen asked whether this was truly the
> local engine or the OpenAI realtime path.** The first write-up of this verdict
> said **"both engines"**. That is WRONG and the correction matters more than the
> verdict: **both services register their observers in `init()`**
> (`LiveVoiceSessionService.swift:154`, `NativeVoicePipelineService.swift:132`),
> so **both observers fire on every notification regardless of which engine is
> capturing.** Two log lines proved two OBSERVERS classified correctly — never
> that two ENGINES ran.
>
> **And the log cannot say which engine it was.** Nothing logs the active voice
> engine at session start; `VoiceEngineRouter` is silent. The low-level evidence
> does not disambiguate either — `aurioc AURemoteIO … enable 3` (full-duplex
> capture) failing across the interruption window proves a real capture chain
> existed and was torn away, but **both** paths capture locally; realtime merely
> streams the result onward.
>
> **So A1 is verified for ONE engine and we do not know which.** The shared
> decision core (`AudioInterruptionRule`) is identical for both, so the residual
> risk is low — but low risk is not verification, which is the lesson this whole
> day has been about. **A1 stays open until re-run with the engine pinned and
> logged.** See §A1b.

**What IS established: both orderings, correct classification, no false negative.**

| run | what Owen did | interruption detected |
|---|---|---|
| **1** | let it ring, **declined** | ✅ `17:53:30.815` — 567ms **before** #118's teardown |
| **2** | **answered**, spoke, hung up | ✅ `17:55:47.418` — 167ms **after** #118's teardown |

```
[NativeVoicePipeline]     audio interrupted — system deactivation, reason: …rawValue: 0 (#198)
[LiveVoiceSessionService] audio interrupted — system deactivation, reason: …rawValue: 0 (#198)
[AppContainer] #118: app backgrounded with a live voice session — ending it
[both] audio deactivated by app — not an interruption (#198)
[both] audio resumption recommendation: resume (#198)
```

**What this proves, and it is more than "it passed":**

1. **The false-NEGATIVE half is closed.** The 2026-08-01 pass proved no false
   positives and explicitly could not speak to missed interruptions. A real call
   was **seen**, classified `source == .system`, on both engines.
2. **True positive and true negatives in the SAME trace.** The real interruption
   classified as one; the app's own teardown deactivations classified as
   `not an interruption`. The filter discriminates — it is not merely permissive.
3. **Order-independence, measured rather than designed.** #118's background
   teardown and the interruption notification **race, and the winner varies** —
   run 1 the interruption arrived first, run 2 the teardown did. Classification
   was correct either way. Nobody designed that; it held, and now it is recorded.
4. **Corroboration from the negative side:** Owen began speaking again *as the
   call arrived* and that speech was **not captured**. A missed interruption
   would have left the mic live. The absence is evidence.
5. **No call audio reached the transcript.** The chat turn that completes a few
   seconds after each interruption is the PRE-call utterance being submitted as
   the session tears down — confirmed with Owen, expected behavior.

### A1b · RE-RUN with the engine PINNED · **[BLOCKED ON AN INSTRUMENT FIX FIRST]**

**Do not re-run A1 until the app logs which voice engine is active.** Repeating it
blind would produce another verdict that cannot say what it tested — the entire
problem with the first attempt.

**Instrument fix (mine, no device needed):** log the selected engine at voice
session start, at `.notice` so Console shows it without verbose. `VoiceEngineRouter`
already decides; it just never says so.

**Then:** one call per engine, engine named in the log each time. Cheap once the
line exists — the expensive part is Shelley's time, and this is two more calls.

### The `AVAudioSession` hang-risk FAULT — found in the same log, unrelated to A1

```
17:55:51.682 [AVAudioSession Hang Risk] AVAudioSession_iOS.mm:978
  This method can lead to UI unresponsiveness if called on the main thread.
  Consider using the asynchronous activate/deactivate API instead.
```

**Severity `fault`** — the highest iOS emits, and it fired in the **resumption**
path. We are making a synchronous `AVAudioSession` activate/deactivate call on the
main thread. `AudioSessionOffMain` exists precisely to avoid this, so some site is
bypassing it. Filed as OPEN_ITEMS **#198B**; source work, no device time.

### A2 — **PARTIAL**, 2026-08-01. Scheduling half CONFIRMED; execution half still owed.

`[BackgroundTasks] app-refresh scheduled (earliest +15m)` fired **three times**
(17:39:34, 17:53:31, 17:55:46) with **no `submit failed:` line**. This is the
first time the migrated `submitTaskRequest` **completion path** has actually run
on device — it had never executed before today, and the deprecation reason for
the old API was that the throwing form *under-reported*.

**Still owed:** evidence the refresh actually EXECUTES. Needs the overnight
backgrounding; the system decides when, and it cannot be forced.
