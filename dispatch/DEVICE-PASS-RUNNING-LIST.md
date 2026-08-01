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

### B1 · Half-duplex gate vs talk-over barge-in · **[OWEN — SUBJECTIVE VERDICT]**

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

*(Nothing yet — this list was created 2026-08-01. Append here with date, run ID
where applicable, and PASS/FAIL/PARTIAL/UNRUNNABLE.)*
