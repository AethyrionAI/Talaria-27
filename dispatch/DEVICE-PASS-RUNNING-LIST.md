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

> ## ⛔ ORDERING RULE — **§C5 GOES FIRST, ahead of everything on this page.**
>
> **§C5 exports the ONLY copies of two irreplaceable battery runs**, and they are
> exposed to two different erasers that most of this list triggers:
>
> 1. **Every battery run prunes.** §C1–C4 and any promotion lane push those two
>    records one step closer to eviction. The bound was 10 until 2026-08-01 and
>    **pruning was silent** — so a lost record leaves no trace that it existed.
> 2. **Every reinstall touches the container that holds them.** B1's probe branch,
>    F3's delete, any OTA or corded install. An upgrade-install *should* preserve
>    app data (same bundle id — that is how `ota-stage.sh` is designed), but
>    "should" is a bad bet on a **unique asset when the export takes two minutes.**
>
> **This is not a warning about a risky check — it is an ordering rule about a
> cheap one.** §C5 costs two minutes and needs nothing. If it is skipped and a
> record is gone, the question it answers (are the #200-series' 0/10 grab results
> real or an artifact?) costs a **full battery sitting** to re-ask, and the answer
> would be a fresh measurement rather than the original evidence.
>
> The `F3` row below has said "export from Battery Results FIRST" since it was
> written. **That instinct was right and scoped too narrowly** — it named the one
> check that deletes the app, when the exposure is any reinstall and every run.

| for | you need | why it bites |
|---|---|---|
| **§C5** | **nothing — two minutes, do it first** | ⛔ see the ordering rule above. It is the only item here that gets **harder by waiting**, and the only one guarding evidence that cannot be regenerated. |
| **A1** (the top item) | **a second phone, or someone who will call you** | A1 is a real incoming call mid-session. There is no software substitute — the whole point is the OS interrupting us for real. **This is the single prerequisite most likely to end a sitting early.** |
| **A2** | to background the app **overnight** | the system decides when `BGAppRefreshTask` runs; it cannot be forced. Start it before bed on a sitting day, read the log the next morning. |
| **F3** | to **DELETE the app** | ⚠️ **destructive — local sessions and the Keychain stamp go with it.** Export anything you want from Battery Results FIRST. Run F3 **last** in any sitting for this reason. |
| **F5** | a **> 25 minute** induced connector outage | the window IS the check — the original close scored a false PASS on a short one. Do not squeeze this between other checks. |
| **B1 / F6** | the `probe/t27-130-halfduplex` branch **built to the phone** — **but B1 is PARKED, so do not stage it yet** | ⛔ **§C5 must be exported BEFORE this branch goes anywhere near the phone** (ordering rule above). And B1 is parked by Owen's own instruction — *"leave it parked as a reminder"* — so its blocker was never OTA-vs-corded. **Staging a build for a parked item, onto the phone holding §C5's only evidence, is the wrong move twice over.** It is a separate build from `main`, so it cannot share a sitting with the `main` checks either. |
| **C1–C4** | phone **foregrounded and on power** | backgrounding kills a battery run outright. |
| **F7d** | **host-side access to turn Hermes YOLO/auto-approve OFF**, and the discipline to restore it after | The other three F7 rows (**F7a–c**, the on-device confirm gate) need **nothing** — run them in any sitting. Only F7d touches the host. It is a **discovery probe, not a pass/fail**: Talaria handles no approval event at all, so the expected outcome is a stalled turn. Bounded by #145 Part A's timeouts now, which is itself worth confirming. |

### Decisions owed by you — no phone, no build, unblock other work

| # | the question | what it unblocks |
|---|---|---|
| **D2** | **Should LAN-hosted backends work at all?** `http://192.168.x` and MagicDNS names are ATS-blocked app-wide today; only the Tailscale CGNAT range is excepted. | If yes, it needs its own measured arm — and note `NSAllowsLocalNetworking` was only ever tested against a **CGNAT** host, never a `192.168.x` one, so do not assume the key does what its name says. If no, we close the ATS thread. |
| ~~**#152**~~ | ~~Pick the pairing-surface label~~ — **WITHDRAWN 2026-08-01. This was not owed; it SHIPPED 2026-07-24.** The row reads **"Pairing & Devices"** in the tree today (`UplinkSettingsScreen.swift:357`, `ConnectHermesHostScreen.swift:38`), merged in **PR #146**. I put it on your plate as an open decision, and repeated it to you verbally — both wrong. If you want a different label it is now a change, not a decision. | Nothing. The device check it left behind is in **§F1**. |
| **#164** | **Close the old UI flake, or formally quarantine it?** | Its own bar is *three consecutive green runs*; we have **one** (2026-08-01, 8/8). I did not close it on your behalf — meeting a bar is not the same as being tired of it. Your call whether the bar still earns its cost. |
| **#170** | **Run #148's discriminator, or close as answered-for-the-world-that-exists?** | Neither shape is reachable on OJAMD — every real job carries a null `model_snapshot`. The discriminator is one read of the Mac's `cron/jobs.json`; I can do it if you want the answer. |
| **#47** | **Does the billing cap still matter?** | #47 is otherwise closed and in daily use. This residual is currently filed **nowhere** — it dies unless you say to keep it. |
| ~~**tracker**~~ | ~~**Retire the old-style `## N.` headers?**~~ — **RESOLVED 2026-08-02, Owen delegated ("whatever works best for tracking and your reading it"). Decided the OTHER WAY: `## N.` is now the ONE canonical form and `## #N` was retired**, because a header reading `#223` looks like a GitHub reference and that collision has misfired twice. 33 headers converted, invariant-checked (no non-heading byte moved). | Nothing — `grep -oE '^## [0-9]+[A-Z]?\.' \| sort -u \| wc -l` is now the whole count. **#198/#199's two entries stay** (both ✅, each pointing at the other): merging entries is a content call, not a header call. |

### Decisions owed by you — not blocking this list, but open

- **#99** — WKContentRuleList: accept the current behaviour, or fix it? Pre-launch.
- **#116** — no route to an empty token slot; needs a spec/decision before its DoD
  is even runnable.
- **#132** — host-side image attachments: your model-vision/config question, plus
  two placeholder strings.
- **#166c** — a Tailscale-only host is **structurally unreviewable** by App Review.
  A reviewer-reachable server decision is a launch gate, not a nicety.

### What needs nothing from you

**NOTHING — the solo queue is EMPTY as of 2026-08-01.** All four lanes ran, and
the one remaining candidate is ruled out (see below). **The next real work needs
Owen and the phone, starting with §C5.**

> ⏳ **ONE THING IS TIME-SENSITIVE — §C5.** #216A's re-read landed on a question
> only two saved battery runs can answer, and the store prunes. Two minutes on the
> phone, no battery run needed, and it is the only item here that gets *harder* by
> waiting. **See the ordering rule above — it goes first, ahead of everything.**

**All four solo lanes are ✅ done (2026-08-01), and every one of them SHRANK the
board:**
- **#128's archaeology** — confirmed #220's engine hypothesis from source and
  removed #128 from the queue entirely.
- **§G's #151/#153 source-confirms** — the confirms had **already been done
  2026-07-24 and merged as PR #146**. #153 closed; #151 and #152 moved *into*
  §F1/§F5 as ordinary device checks; one decision withdrawn off Owen's plate.
- **#216A's re-read** — could not be settled by analysis, which IS the finding.
  It created §C5 and the ordering rule above.
- **§E1's double-install probe** — **CONFIRMED, it throws.** #198's migration
  rationale is no longer inference, and #82's half was settled for free. Left one
  zero-setup residual in §F6.

**The remaining candidate is NOT available:** staging B1's branch is ruled out
twice — B1 is parked by Owen's instruction, and staging is a reinstall that must
not precede §C5's export. See the `B1 / F6` prerequisite row.

> **This paragraph was itself stale for an hour and that is worth recording.**
> It advertised "E1's isolated build" as available **after** E1 had run and its
> verdict was filed three sections below, in the same commit. **A summary line
> above a section it summarises is the highest-risk text in any document** — it is
> read first, trusted most, and updated last. It is the exact failure this session
> catalogued four times in other people's entries before producing a fifth of my
> own. **When a section changes, grep the document for anything that describes
> it.**

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

## A2b · #221 — brain-governs-voice A/B · **[HIGH — verifies a spend + privacy fix]**

**Fixed 2026-08-01, unverified on device.** The bug: `VoiceEngineRouter` keyed on
relay pairing alone, so the **on-device** brain still ran voice over **OpenAI
Realtime** — billing audio tokens and sending microphone audio off-device while
the UI said on-device. Found by Owen hearing a different voice in airplane mode.

**This is a two-arm A/B with an audible check AND a logged check**, which is the
point: the ear is what caught it originally, and the log is what makes it a
record. Run both arms in one sitting, network ON, phone paired — the failing
configuration is *paired and healthy*, so do **not** use airplane mode here.
Airplane mode would pass trivially and prove nothing.

### Arm 1 — brain = **On-Device**  (the arm that used to fail)

**DO:** Settings → brain → **On-Device**. Start a voice session. Say a couple of
things.

- **PASS:** log reads `voice session starting on engine native (relayPaired=true)`
  — note **`relayPaired=true`**, that is the whole point — and the voice is
  **Apple TTS**, audibly different from the OpenAI voice.
- **FAIL:** `engine realtime`, or the OpenAI voice. That is the original bug alive.

### Arm 2 — brain = **Hermes**  (must still work)

**DO:** switch to **Hermes**, start a voice session.

- **PASS:** `voice session starting on engine realtime`, OpenAI voice.
- **FAIL:** stuck on native — the fix over-corrected and broke the paid path.

### Arm 3 — does it STICK?  ← Owen's explicit ask

The fix re-checks the brain at three points, but nothing has proven the *setting*
survives real usage. Check all four:

1. **Mid-session switch.** On-Device → start voice → end → switch to Hermes →
   start voice. Second session must be `realtime`. Then reverse it.
2. **Cold relaunch.** Set On-Device, force-quit, relaunch, start voice.
   Must be `native` — a brain that resets to Hermes on launch would silently
   restore the billing.
3. **After a re-pair.** Pairing is what used to decide; confirm re-pairing does
   not re-admit realtime under On-Device.
4. **After network flap.** Airplane on → off → start voice under On-Device.
   Must stay `native`; the readiness probe recovering must not override the brain.

### Also capture while you are here

`#221`'s open product question: **should a realtime voice session show a visible
indicator?** Arm 2 is the moment to judge it — you will be on realtime with audio
leaving the device. Note whether the absence of any indicator feels wrong.

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

### C5 · Rescue two battery run records before they are pruned · **[DO THIS FIRST — IT IS A RACE, AND THE ONLY ONE ON THIS LIST]**

**Two minutes, no battery run, and it can only get harder.** Everything else here
waits patiently; **this one degrades every time a battery runs.**

Open **Diagnostics → Battery Results** and check whether these are still in the
store, then **export both**:

| run | lane | date |
|---|---|---|
| `1835BBF9` | **#214** — narrow belt, haiku grabs 0/10 | 2026-07-31 |
| *(#200F's run id — read it off the screen)* | **#200F** — `scoped` + `createonly`, haiku grabs 0/10 | 2026-07-29 |

**Why it matters:** #216A found that the haiku canary rides the **REMIND scope**,
so every "grabs 0/10" cell in the series still had **`readCalendar`** on its belt
— the exact tool #216 measured the over-serving impulse displacing off of. If a
grab was scored from response text, a silent `readCalendar` call would have gone
uncounted. **`call_economy_report` reads the answer straight out of these two
records** (`toolCalls` recording predates both runs, `801e872` 2026-07-28).

**Why it is a race:** `maxRuns` was **10** until 2026-08-01, and pruning was
**silent** until the same commit that raised it to 50. #200F may already be gone
and nothing would have said so. **If a run is missing, record that as the
result** — "evicted, unrecoverable" is a finding, not a failed check, and it is
the concrete cost of the bound that #219 argued about in the abstract.

**If both are gone:** the 0/10 haiku grabs across #200F/#214 stay permanently
UNRESOLVED unless someone re-runs those cells — which is a real battery sitting,
not a two-minute read. That asymmetry is the whole reason this is first.

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

### E1 · `installTap` double-install · ✅ **RAN 2026-08-01 — CONFIRMED. It throws.**

Does the migrated `AudioNodeTap.install` THROW on a double-install where the old
API raised an uncatchable ObjC exception?

> ## ✅ VERDICT: **IT THROWS.** #198's migration rationale is CONFIRMED, not inferred.
>
> **Two identical runs, iOS 27.0 simulator (`24A5390f`), standalone binary under
> `simctl spawn`. Process exit 0 both times — it was never raised out of.**
>
> ```
> E1: mainMixer first install OK
> E1: mainMixer attempting SECOND install (no removeTap) ...
> E1: mainMixer THREW — Error Domain=com.apple.coreaudio.avfaudio Code=-10863
>                       UserInfo={false condition=nullptr == Tap()}
> ```
>
> **`nullptr == Tap()` is the EXACT condition string from #128's device crash**
> (`AVAEGraphNode CreateRecordingTap: nullptr == Tap()`, whoGoesThere,
> 2026-07-17). Same failure, same assertion — **now delivered as a catchable
> Swift error instead of an uncatchable NSException.**
>
> ### It also answered a question it was not aimed at — #82's, for free
>
> The simulator's `inputNode` reports a **degenerate format (rate=0.0, ch=2)** —
> which is precisely **#82's wedge shape** — and the install threw there too:
>
> ```
> E1: inputNode INCONCLUSIVE — first install threw: Code=-10868
>     UserInfo={false condition=IsFormatSampleRateAndChannelCountValid(format)}
> ```
>
> **So BOTH hand-rolled mitigations now guard failures the API REPORTS rather
> than raises** — #82's format preflight and #128's adjacency invariant. Neither
> was written knowing that; both were written because the old API raised.
>
> **Both preflights STAY**, exactly as #198 said. They prevent the failure; this
> only prices the residue. A recoverable throw is a better floor than a crash,
> not a reason to remove the thing that stops you reaching the floor.
>
> ### Limits, stated because the result is favourable
>
> - **Simulator, not device.** The error domain and codes are CoreAudio's and the
>   runtime is the same iOS 27.0 family, but hardware is not proven here.
> - **The double-install was on `mainMixerNode`, not `inputNode`** — the sim's
>   `inputNode` cannot complete a *first* install (degenerate format), so it
>   cannot host a second. The identical condition string is strong evidence it is
>   the same `AVAEGraphNode` path, but it is not the same node #128 crashed on.
> - **Therefore `inputNode` double-install on real hardware is UNMEASURED.** It is
>   the one residual, and it is cheap to fold into any voice sitting — see §F6.
>
> **Probe source is committed — `scripts/e1-doubleinstall-probe.swift`** — so this
> is re-runnable after any SDK bump, which is exactly when it should be re-run
> (`__installTap`'s `__` spelling is awaiting an AVFAudio overlay and WILL change).
> It is outside `project.yml`'s source paths, so it needs no `xcodegen generate`.
>
> ```bash
> DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios27.0-simulator scripts/e1-doubleinstall-probe.swift -o /tmp/e1probe && DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcrun simctl spawn 47F68496-24F9-45D9-93D3-1C778DB6B557 /tmp/e1probe
> ```
>
> Deliberately a standalone binary, not an XCTest: had it raised, the process
> dying **is** the answer and costs nothing, where a test host dying costs a green
> suite and teaches nothing.

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
| **#151** | Settings → Hermes Host → **Test Connection** against the LIVE host | verdict appears **within ~5s** with a latency figure. Shape 1 of 3 — the other two are in **§F5**. Pre-#146 this button was silent and, on a black-holed host, would have hung **five minutes** (the shared client stamps `timeoutInterval = 300`) |
| **#152** | Settings → Hermes Host → **"Pairing & Devices"** → reach Revoke | the renamed row lands on the revoke/disconnect surface, and **Pair New Device (QR)** is present so the screen is not destructive-only. Sim-verified 8/8 already; this is the device leg |
| **#222** | **On-device brain**, attach an image, then ask something OCR **cannot** answer from a list of strings — *"who posted this?"*, *"is this the Safe Harbor group?"*, or anything about layout/colour/what is depicted | **Either answer is informative.** A correct answer ⇒ the model genuinely sees the image and #222's premise falls. A wrong/hedged answer, or a `readImageText` chip firing and it reasoning only over extracted text, ⇒ the transcript really is text-only and the SDK's `ImageAttachment` is an unused capability. **Works in any state — Owen already ran the OCR half on-device in airplane mode.** Do NOT re-run "what's this say" — that already passed and answers the wrong question |

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
| **#151** | Test Connection against a **STOPPED** host (gateway down, port closed) | **REFUSED**, fast — not OFFLINE, not a spinner. Shape 2 of 3 |
| **#151** | Test Connection against a **BLACK-HOLED** host (packets dropped, e.g. an offline tailnet IP) | **NO ANSWER** at **~5s**. Shape 3 of 3, and the one that matters most — this is the case that used to hang for five minutes. **Cheapest setup on the board: point the base URL at an offline tailnet IP; no service needs stopping** |
| **#145** ⭐ | **RIDES #151's BLACK-HOLE FIXTURE — same setup, do them together.** With the base URL pointed at an offline tailnet IP: background the app, then **foreground it**. Then point the URL back at the live host and foreground again. | **(1)** the app stays **responsive** while blocked — you can scroll, open Settings, switch brains. **(2)** the visible state (widget/Live Activity) reflects last-known-good **immediately**, not after minutes. **(3)** when the URL is restored it **recovers on its own — NO phone restart.** ← the whole item |

> **⭐ #145 — the fixture, and the now-authorised alternative.**
>
> **Owen, 2026-08-02: *"you can stage whatever outage you want. Production is just
> my windows box, and I'm not actively using the app right now."*** That lifts the
> fix spec's *"staging an outage on OJAMD is out of scope"* constraint — **recorded
> here so the permission is not lost, and so nobody re-derives the old limit from
> the spec.**
>
> **The offline-tailnet-IP fixture is still the better default**, and not for
> caution: it needs no coordination, restores by editing a text field, and is the
> same setup #151 needs one row up, so the two share a sitting.
>
> **But know which network SHAPE you are producing — they are not equivalent.**
> #145 needs packets **DROPPED** (every request eats its full timeout, #136's
> shape). A stopped process normally gives connection **REFUSED**, which fails fast
> and would NOT reproduce this bug. **On OJAMD they coincide:** #136 established
> that Windows Firewall silently drops packets to listener-less ports, so stopping
> the gateway there does produce DROP. **That coincidence is host-specific — do not
> carry it to the Mac**, where a stopped gateway refuses and would quietly test the
> wrong thing.
>
> **All four parts are BUILT (PRs #233–#235): expect CLEAN, not merely better.**
> B repaints visible state before any network call, C budgets the reconcile loop
> on wall time, A gives every client a real timeout (20s interactive / 300s
> streaming idle), D stops activations stacking. Record what you actually see —
> a non-clean result is now a finding, not a known gap. *(This block previously
> said "Parts A and D are NOT built yet" — that was true when written, mid-lane;
> corrected 2026-08-02.)*
>
> **RIDER — #180 instance 4, the disconnection-indicator rejudgement (Owen,
> 2026-08-02: "yes, lets rejudge").** While the outage fixture is up, on a build
> that includes **PR #237**: walk the surfaces you actually use — chat, the
> sessions shelf, Skills, Tasks, Insights, the cron editor — and JUDGE whether
> the reactive convention (failure strips, "as of HH:mm" stamps, the honest
> empty-branch, profile-scoped resets) is enough, or whether you still want one
> proactive app-wide "disconnected" signal and where it should live. The
> original complaint (2026-07-23) predates every one of those mechanisms — this
> is a taste call on today's build, not a repro. Outcome feeds #180's remaining
> scope; "the strips are enough" closes instance 4 outright.
>
> **The original 2026-07-20 report said "hard-lock, phone restart."** The
> investigation's honest limit still stands: serial `await`s suspend, they do not
> block the main thread, so the mechanism explains *wedged and stale* but not a
> literal frozen touch UI. **If input genuinely freezes, that is a separate and
> bigger finding** — grab the iOS hang report (Settings → Privacy → Analytics) and
> say so, because it would mean something blocks the main thread that we have not
> found.

### F6 · Voice — same physical sitting as B1

| # | check | pass |
|---|---|---|
| **#129** | Audition a voice mid-session | no crash, session survives, mic live afterwards. Owed since 2026-07-24. Known-and-accepted: native-engine sessions share the assistant TTS instance |
| **#58 / #179** | First Control Center tap from cold | action does not report success before the widget extension exists. **One check closes both** — #179 is chained to #58's pass by its own decision point |
| **E1 residual** | Start a native voice session; confirm the log shows a REAL capture format (not rate=0.0) and no `nullptr == Tap()` **crash** | **Zero extra setup — it rides any native voice session you are already running.** §E1 proved the double-install THROWS on the simulator, but on `mainMixerNode`; the sim's `inputNode` has a degenerate format and cannot host the test. This is the only unmeasured leg: `inputNode` on real hardware. **A crash here would falsify §E1's verdict on the node that actually matters** |

### F7 · APPROVALS with auto-mode OFF · **[NEW 2026-08-02, Owen: "one thing I haven't done"]**

**There are TWO separate approval systems and only one of them has ever been
exercised.** Source-checked 2026-08-02 before writing this section — read the
finding before running it, because half of this is a discovery probe, not a
pass/fail check.

**System 1 — the on-device confirm gate (#29, `ToolConfirmationCenter`).** The
local brain's side-effecting tools (create reminder, create calendar event)
suspend on it; the card renders inline at the chat tail with EDITABLE fields.
There is no user-facing auto-approve — `autoAcceptForBattery` exists but is
harness-only, set by the Diagnostics battery buttons and cleared in their
`defer`. So this gate is always live in ordinary use, and the whole #200-series
ran through it.

**System 2 — HOST-side approvals: a THREE-mode config key, not a binary.**
*(Corrected 2026-08-02 from Owen's screenshot + a source check — this section
first said "YOLO on/off", which is the session mechanism, not the model.)*
`hermes_cli/web_server.py:933` declares **`approvals.mode`**, "Dangerous command
approval mode", options **`["manual", "smart", "off"]`** — Owen's host currently
reads **Off**. It is a schema'd config key: readable via `GET /api/config`,
writable via `PUT /api/config`, on `:8642` under the key the app already holds.
**So F7d means switching it to `manual` (or `smart`), not flipping a session
flag** — and it can be set from the dashboard, or by hand, or eventually from
Talaria (see **OPEN_ITEMS #224**, filed off this).

> **UPDATE 2026-08-02 — an ANSWER channel exists, and the `/api/config` claim above is
> wrong.** `approvals.mode` is real but lives on the dashboard app (`:9119`), **not** the
> `:8642` the phone speaks — so setting it from Talaria as described is not possible
> (see #224's correction). Set it from the dashboard or by hand for this check. **What IS
> on `:8642`: `POST /v1/runs/{run_id}/approval`** (plus `/v1/runs`, `/{id}`, `/{id}/events`,
> `/{id}/stop`). So F7d is no longer only "watch it stall" — it is also **"find out whether
> our runs are reachable as `/v1/runs` ids,"** which decides whether the phone could answer
> approvals at all. Note the run id from `run.started` when you run F7d.

**Expect trouble, because Talaria handles NO approval event.** Its SSE taxonomy
is `run.started` / `assistant.delta` / `tool.started` / `tool.completed` /
`tool.progress` / `assistant.completed` / `run.completed` / `done` — there is no
approval or input-required case anywhere in `SessionsHermesClient`.
`InboxItemType.approval` exists with an "Approve" action, but the only producers
in this repo are `DemoData` — whether the relay ever emits a real one is
**unverified**.

| # | check | what to record |
|---|---|---|
| **F7a** | **On-device brain**, ask for a reminder/calendar create. **Tap Cancel, not Approve.** | The decline path. Does the model relay the decline honestly, or fabricate a completed action (#199's shape)? Does the chat stay usable, or enter #176's absorbing state? |
| **F7b** | Same, but **edit a field in the card before approving** | The written record matches the EDITED values, not the staged ones. This is the card's headline feature and has never been checked on device |
| **F7c** | Same, and **background the phone while the card is waiting** | The gate survives suspension — card still there on return, still answerable, tool not silently resolved |
| **F7d** | Set the host's **`approvals.mode` to `manual`** (dashboard, or `PUT /api/config`) — it is on **`off`** today — then ask the connected tier for something that needs approval (a shell/file write). **Restore `off` after.** | ⚠️ **DISCOVERY, and the likely outcome is a STALL.** Record what the app shows: a hung run, a silent stop, an inbox item, or nothing at all. **#145 Part A now bounds it** — the turn should FAIL on a real timeout (20s interactive / 300s streaming idle) rather than hang forever. If it hangs past those, that is a #145 finding too. Whatever happens, note whether the host is left waiting on an approval nobody can answer |
| **F7e** | *(optional, same sitting)* Repeat F7d with **`smart`** instead of `manual` | Whether "automatically assess" prompts at all for ordinary agent work. If Smart rarely asks, it may be the honest default for a phone client that cannot answer prompts — an input to **#224** |

**Why F7d matters beyond the check:** if the connected tier can be put into a
state Talaria cannot answer, that is a shipping-relevant gap in the same family
as #180 (the app hides its own degradation) — the user would see a dead turn
with no way to learn an approval is pending. **Do not leave YOLO off**
afterwards unless you mean to; restore whatever state you started in.

---

## G · NOT device work — routed out of this list

Filed here only so the audit's Part 1C list is fully accounted for. **Do not
carry these into a device sitting.**

- **~~#151 / #152 / #153~~ — ✅ ALL THREE RESOLVED OUT OF §G, 2026-08-01. This
  section's premise for them was stale by a week.** The source-confirms it calls
  "owed" were **done 2026-07-24**, the work was **built**, and it **merged as
  PR #146** (`git merge-base --is-ancestor claude/t27-settings-host-surface main`
  → ancestor). Verified in the tree, not taken from the tracker:
  - **#151** — `probeTimeout = 5`, a dedicated probe deliberately off the shared
    300s client path, `testState` bound to the UI, and the three new honest
    verdicts **REFUSED / NO ANSWER / NO HOST** at `UplinkSettingsScreen.swift:38-40`.
  - **#152** — row and destination both read **"Pairing & Devices"**
    (`UplinkSettingsScreen.swift:357`, `ConnectHermesHostScreen.swift:38`).
  - **#153** — the scope gate came back the good way: hosts were **already an
    array** (`BackendProfile.swift:100`), so never a data-model lane;
    `deleteProfile(id:)` ships with `profileIsActive` / `profileIsSensorDestination`.
  **#151 and #152 are now ordinary device checks and have moved to §F1 / §F5** —
  the opposite direction from where the audit routed them, because the confirm
  they were waiting on had already happened. **#153 needs nothing and is ✅.**
  **The lesson is the one this week keeps re-teaching:** §G was written from the
  tracker's *"Source-confirm owed (next Mac shell)"* lines, which were true when
  logged 2026-07-20 and dead four days later — and each entry carried its own
  answer in a **later** paragraph of the same entry. Read the whole item, not its
  oldest line.
- **#128 — source archaeology. ✅ DONE 2026-08-01, no device time.** Neither horn of
  the dichotomy: the fix is **live** (layer 3 of 4 guards) and the repro is
  **decoupled, not unreachable** — PR #127 re-enabled the mid-session preview button
  and removed the session-category flip that was the actual trigger, in the same
  commit. **#220's engine hypothesis confirmed and strengthened:** realtime is
  WebRTC with *zero* tap sites, so a paired healthy-realtime phone runs no
  tap-install code at all. **Nothing is owed on the device queue for #128** — the
  physical re-verify is #129's test (§F6) and closes #129. Full write-up in the
  tracker; the deliberate-race probe, if anyone wants real evidence for the
  invariant, is §E1. **§E1 has since RUN (2026-08-01) — and be precise about what
  it did and did not settle.** It proved the double-install now **throws** rather
  than raising, so #128's failure mode is recoverable if the race ever occurs.
  **It did NOT test the adjacency invariant itself** — it priced the residue, which
  is exactly what that item said it would do. #128's close is *strengthened*, not
  independently verified.
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

### ⚑ AIRPLANE MODE IS A FREE ENGINE PIN (found 2026-08-01)

**Turning on airplane mode forces the NATIVE engine**, no build and no unpair
required: the realtime readiness probe fails, `shouldRouteNative` fires, and the
router logs it. Verified 2026-08-01:

```
18:57:09  readiness routed voice to the native engine (configured=nil, state=failed)
18:57:09  active voice engine → native
18:57:10  voice session starting on engine native (relayPaired=true)
```

**Note `relayPaired=true` alongside `engine native`.** Pairing does NOT determine
the engine — the probe result does. That is precisely the case that was invisible
before the log line existed, and it is why the engine varied run to run.

**Also established, and previously unrecorded: native voice + the on-device brain
works FULLY OFFLINE** — four complete turns with `sendStreaming routed to
on-device`, no network at all.

**Interruptions still reachable in airplane mode:** a **timer or alarm** firing is
a genuine `.system` audio interruption; phone calls are not (no cellular).

### A1c · Timer interruption on the NATIVE engine · **[WEAKER SUBSTITUTE — not a replacement for A1]**

**Owen 2026-08-01: "a timer isn't the same as a phone call."** Correct, and the
difference is not cosmetic:

- a **call** hands audio to another process, backgrounds the app, and holds the
  route for minutes — it is what real users hit
- a **timer** is a short local interruption that never takes the foreground the
  same way

So a timer exercises `AudioInterruptionRule` on the native engine — worth having,
since that engine has **no** interruption verification — but **passing it does NOT
close A1.** A1 needs a real call on the native engine, which needs the engine
pinned some other way than airplane mode (unpair, or a debug override), because
airplane mode is precisely what prevents the call.

**Queued, not scheduled.** Circle back.

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
