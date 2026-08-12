# Device backlog triage — 2026-08-11

**Question Owen asked:** if the phone is plugged in and set never to sleep, how much of
the device backlog can run unattended?

**Method.** Two independent readers, identical criteria, disjoint sources — one over
`dispatch/DEVICE-PASS-RUNNING-LIST.md` (3,251 lines), one over `OPEN_ITEMS.md`'s
device-owed bars. Neither read the other's file. Both were told an UNCLEAR row is worth
more than a confidently-wrong "automatable", because anything classed A gets built into a
suite whose failures are then trusted.

**Classification.** **A** = scoreable unattended with no new infrastructure ·
**H** = mechanically checkable but needs a harness built first · **O** = needs Owen
(judgment, biometrics, two people, a real physical condition, or host ops) ·
**⚠️DATA** = writes to his real calendar / reminders / alarms / contacts / health.

---

## 1. The numbers

| source | live rows | A | H | O | unclear |
|---|---|---|---|---|---|
| running list | 64 | 29 | 21 | 14 | 6 |
| tracker bars | 74 | 15 | 32 | 23 | 4 |

**These overlap and must not be added.** #162/#163/#165, #184/#185, #21, #123, #190, #225
and #312(b) appear in both. Unique live device debt is roughly **90–100 rows**, of which
**~35 are automatable today** and **~30 more become automatable behind five harnesses**.

Unattended runtime for the A column: **~4 hours**, ~60% of it Group 2's drawer surfaces —
three shipped lanes (#162 Tasks, #163 Skills, #165 Insights) whose device checklists have
**never been executed at all** since 2026-07-22.

## 2. The finding that changes the shape of this

**The measurement instruments already exist. They are unreachable, not unbuilt.**

`runActionBattery` and ~20 sibling batteries live in `LocalChatBackend+Battery.swift`, the
#134 forced-trip harness exists, the #297 A/B exists, and results already persist as JSON
per run in `BatteryRunStore`. What is missing is only the two ends:

- they are Developer-screen **`Button`s with no accessibility identifiers**, so nothing can
  press them; and
- **nothing reads the run store back out**, so nothing can assert on a result.

Add a launch-environment trigger (`TALARIA_RUN_INSTRUMENT=<name>`, `TRIALS=<n>`) and a
machine-readable export, and **~13 bars unlock from one build**: #199A, #205E, #208,
#210 residual, #210A, #211A, #225 B1–B4, #257's never-built tokenCount pre-flight, and
#279-F. The buttons already set `isIdleTimerDisabled = true`, so half of "plugged in and
never sleeps" is solved.

This is the single highest-leverage build on the board and it is plumbing, not science.

## 3. Build order

**1 — Instrument trigger + result sink** (cluster 1 above). ~13 bars. Must ship with an
abort-time reap (see §5) and must never call `tokenCount` during a live streaming turn —
recorded hazard: it kills the turn.

**2 — Forced-unreachable host fixture.** 6+ bars: #56(3), #56-U-H, #117, #163/#165's
refresh arms, #190's banner, #312(b). A launch-env profile pointing at a dead port
(refused) or a black-hole tailnet IP (timeout), flippable back to live.
**Strictly better than airplane mode for an unattended phone** — no hands, and the phone
never leaves the tailnet. **Boundary:** it is *not* a substitute for real airplane mode
where send-classification is under test. Group 7(e) turned on exactly that distinction
(`.notConnectedToInternet` queues, `.timedOut` fails honestly), and airplane mode is also
the free native-engine pin.

**3 — Remote-turn UI harness.** ~8 rows, and it de-risks half of Group 2. Send a real turn
to a live host from a UI test, await the reply, assert on transcript structure.

**4 — Test-visible state.** Four one-line exposures that each convert a human observation
into a mechanical one: *speech active* (#190), the conversation-card verdict /
`degenerateCardReason` (#61, #280), tool-activity marker state (#327's family), and the
battery run store (cluster 1).

**5 — Voice/transcript injection.** A hook driving `appendVoiceTranscript` with a pinned
engine takes the mic and the ear out of the loop for #280-F, part of #61, and lets #129
and #220's engine-ambiguous verdicts be scored by log assertion — the engine line is
already logged at `init` and every `startSession()`.

**6 — Small audited host-step runner.** Create/PATCH/delete a cron job, read a session's
stored model, stand up a throwaway gateway on a spare port: #162's badge repro, #170's
second half, #241-E, and a second route for #312(b). **Fixed command allowlist only** —
the `hermes-ojamd` MCP fabricates on its failure path and cannot be an assertion oracle
without a live-clock canary.

**7 — Cross-app share rig** (3 rows, #123) and **8 — a no-ATS-exception build variant**
(1 row, but it is #140-D's *deciding* arm; a test bundle inherits the host app's
Info.plist, so this needs a real second target).

## 4. Rows that should come OFF the device list entirely

The #301-C precedent — a `simctl privacy reset` reached the state a full phone reset was
queued for, which discharged §V2, the row that had to run *last, ever*. The same logic
applies to:

- **#137's fresh-install pass — the biggest single saving.** Its stated preconditions are
  "the Keychain items must be gone" and "no existing Health/Location/Motion
  authorization". **A fresh simulator gives both for free.** One caveat that must be
  handled or the sim arm scores a fiction: `CODE_SIGNING_ALLOWED=NO` strips sim HealthKit
  entitlements *and* silently kills keychain writes — the sim run has to be signed.
- **#124's App Lock checklist.** The sim can enrol and match/fail biometry; six of seven
  checks are behavioural (grace windows, snapshot obscuring, cover-above-sheet,
  push-while-locked), not hardware.
- **#186's three permission checks.** The whole point is *narrow* TCC states, and
  `simctl privacy` sets TCC directly. One command confirms whether `contacts-limited` and
  calendar write-only are settable.
- **#75's acceptance pass** — width and Dynamic Type sweeps are a simulator's strongest
  suit, and the entry already says "iOS 27 sim + whoGoesThere".
- **#112's Comic Book live-switch** — flipping *system* appearance is scriptable on a sim
  and unscriptable on a device.
- **#74 is not phone debt at all.** It is a sim pass blocked by the sim runtime across two
  betas; it appears in device sweeps only by association with #45.

**Counter-examples — do not try to move these.** Anything needing FoundationModels
**generation** is genuinely device-only: the sim still cannot generate on beta5
(`LanguageModelError -1` wrapping `ModelManagerError 1026`, `contextSize = 0`). That pins
#61's card, every battery, #225's four bars, #257's tokenCount and #222's image experiment
to the phone. And #140-D is device-owed for exactly the right reason — its *sim* arm is
what is in doubt.

## 5. The hazard that gates unattended running

**The battery cluster arms `autoAcceptForBattery = true` and performs real Calendar,
Reminders and Alarm writes**, reaped before the DONE line. **An interrupted unattended run
leaves residue in Owen's real data.** Eight further rows carry ⚠️DATA independently (#33,
#137, #162-CRUD, #170, #186, #199A, #225-B4, #249F-D).

**✅ RULED BY OWEN 2026-08-11, and it is narrower than this section assumed — the
per-device rules differ and must not be collapsed into one.**

**On `whoGoesThere` (his phone):**
- **Reminders — ALLOWED.** *"Reminders are fine and I'm not worried about stragglers."*
- **Calendar — ALLOWED.** He has pointed it at a calendar he does not care about, and
  **it is not shared**. That is the containment, and it already exists.
- **Alarms — the ONLY real constraint.** *"Please don't have surprise alarms for me while
  I'm at work."* Not a ban: a ban on surprises.
- **Apple Notes (#33) is NOT covered by this ruling** — he named reminders, calendar and
  alarms. Do not infer Notes from it; ask before running #33.

**On Shelley's iPad: NONE OF IT.** Unchanged and unqualified — see §9.

**What this changes.** This section previously called data containment "the hazard that
gates unattended running". **That framing is now wrong for his phone.** The
calendar/reminder rows can run unattended today, with no new infrastructure, because the
containment is a setting he has already made. What remains is:

1. **Alarms, which need a real answer** — AlarmKit alarms **ring through Silent mode** and
   have no container to nuke. Standing rule: **alarm-writing rows never run unattended.**
   They run only when Owen has said go and is around. A start-of-run sweep of
   Talaria-created alarms helps with residue but cannot cover the window between "created"
   and "crashed", which is the honest reason to keep them attended rather than clever.
2. **#331 survives as hygiene and as the alarm answer**, not as a gate. Downgraded
   accordingly; it no longer blocks the instrument-trigger build.

## 6. Cross-resolution — what running two readers bought

The tracker reader marked **#184/#185's "§F1 device row"** UNCLEAR, because both entries
deliberately refuse to restate the check ("one queue — a check that lives in two places
drifts"). The running-list reader has it: **A, ~10 min, run the existing suites on
device.** Neither reader could have closed that alone.

It also surfaced **two places the running list is now stale where the tracker is not**,
both of which would mislead a runner: **R2** still says "re-run this row as written"
though #250 closed 2026-08-11 with 250F-E met, and **all six Group 7 checkboxes still read
`[ ]`** while the tracker records the results.

## 7. Open questions for Owen

1. **#221's three-arm voice A/B** — archived 2026-08-01 with no device arm required, yet
   the running list still queues all three arms. Same shape as B1/#130, which needed his
   ruling to retire. Discharged, or live?
2. **The ⚠️DATA question in §5** — which containment strategy.
3. **#323's four design questions**, which gate whether #302/#323's verification can even
   be classified (their eventual checks are cheap log assertions; the contract is not
   chosen).
4. **#56(1)** hides a product decision inside a verification row: a Siri ask appends to the
   *current cached conversation*, and the entry records "Owen leans: Siri asks should open
   a NEW chat." One line either closes it or opens a micro-lane.
5. **C2** — the doc calls it ambiguous and #206 is archived. Write a real check, or retire?
6. **R3** — #250 closed, but the tinted-icon glow judgement was never recorded anywhere.
7. **Is OJAMD up?** It gates five rows and was deliberately off as of 2026-08-09.

## 8. One measurement to take before trusting any backgrounding assertion

§D4/§F8 recorded that "a process with a live Xcode launch session NEVER SUSPENDS" (measured
at 2 m 42 s) — but that was a **debugger-attached** session, not an XCUITest runner. Nobody
has established whether a test-launched app suspends normally. This decides whether #A2 and
every future backgrounding row can be automated at all, and a wrong assumption produces a
confident false PASS of exactly the §F8 shape. One throwaway measurement settles it.

## 9. The second device — Shelley's iPad Air (M3), and a HARD constraint on it

**Standing rule, Owen 2026-08-11: NO calendar, reminder or alarm tests on the iPad. Ever.**
It is Shelley's device and her iCloud; test writes do not go there, container or no
container. This is not a preference to be re-litigated by a later lane looking for a free
runner — if a row writes to EventKit or AlarmKit, it belongs on `whoGoesThere` behind
#331's container.

**Also corrected here, because it was asserted wrongly in conversation:** there is **no M5
iPad**. A `devicectl` JSON parse that did not filter on the Reality field surfaced a
*simulator* (`iPad Pro 13-inch (M5)`, UUID-style identifier) and it was reported as
hardware. The real inventory is Owen's 1st-gen iPad Pro (**cannot run iOS 27 at all**) and
Shelley's **iPad Air 11-inch (M3)** on iPadOS 27, updating to beta 5, on the tailnet, with
Developer Mode on and prior installs. Filter on Reality, or read the table rather than the
JSON.

**What the split therefore is:**

| host | role |
|---|---|
| **iPad (M3)** | **write-free FM measurement only.** Anything needing real on-device generation that touches no personal data. |
| **`whoGoesThere`** | everything that writes (behind #331), plus every iPhone-only surface — Dynamic Island, CarPlay, Action button, Control Center layout, cellular/airplane. |

**What the iPad can host under that rule:** #324-W3's FM asymmetries (`tokenCount`
4096-vs-8192, `variant.displayName`, `maximumResponseTokens`), #257's never-built
tokenCount pre-flight, #61's card generation, #205E's ctx-a probe, #210 / #210A's
condensation budget, #211A's read-path battery (read-only prompts by construction), #208's
exploratory re-suspect, #229's log-grep rider, and #222's image experiment **provided the
image is a bundled test asset rather than her photo library**.

**What it must NOT host, under the rule:** #199A (calendar misattribution — writes),
#225's B1–B4 (B4 writes a reminder), C4's thermal replication (auto-accept writes), A1c
(schedules a real alarm), #33 (writes a Note), #170 / #162-CRUD (host jobs — allowed only
because those write to Owen's *host*, not to her device).

**Before planning on it, four checks, none skippable:** generate once (not "available" —
*generate*; availability has lied twice, `Code=5000` on sim and an un-bridged
`LanguageModelError -1` on beta5); install and launch a beta5 build watching for the
dyld-death signature (#324 — no `.ips`, empty stdout, so a silent death looks like
nothing); confirm tailnet reach for host-touching rows; and confirm Apple Intelligence is
actually enabled after the update.
