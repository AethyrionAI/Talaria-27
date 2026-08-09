# Device pass — running list

**A living list, not a dated pass.** Items are added as they are found and struck
when a verdict is recorded. Unlike `OPUS-T27-DEVICE-PASS-2026-07-25.md` this is
never "finished" — it is the queue that fills up between sittings.

**Started 2026-08-01.** Owen drives the phone; Claude reads logs and records
verdicts.

---

## Batch 2026-08-08 — four lanes merged/opened the same day (#284, #286, #295, #297) + Owen's rulings

**Context:** a single session ran #284 (capability broker) spec→plan→SDD→device
probe→close-out, then #286 (honest settlement), then #295 (expiration recovery),
then #297 (toolless capability index). Three merged (GitHub PRs #282/#283/#284);
#297 is PR #285 awaiting merge. **(PR #285 merged same day as `5521260` —
see Z1's discharge note below.)** **Everything below is device debt this
session CREATED or moved.** Nothing here is a re-statement of §A–§G — those
stand unchanged.

**⚑ PREREQUISITE FOR THE WHOLE BATCH: install OTA 2250** (staged 2026-08-08 from
merged `main` `29fa34a`, Debug config so `#if DEBUG` surfaces exist). The phone's
prior build (2225) predates #286 and #295 entirely. If PR #285 (#297) merges
first, re-stage — Z1 needs code that is not in 2250. **It did merge, and Z1's
harness lane landed more code after that — see Z1's discharge note: a fresh
re-stage past OTA 2250 is needed before Z1 runs.**

### Z1 · #297 — toolless capability index A/B · ~~**BARS PRE-REGISTERED, NOT MET**~~ **✅ RUN 2026-08-09 (`A04154D7`) — VERDICT FILED, NO RE-RUN OWED**

**Correcting the entry's own wording:** #297's bars blockquote says the flag "may
be BUILT and landed behind the flag before this run." **It now IS built** —
PR #285, gate PASS (1852 tests + XCUITest + Release), flag
`includeToollessCapabilityIndex` defaults **false**, production text byte-identical
to today's and pinned by test. Building was not shipping; this run is what decides
shipping.

~~**⛔ MUST BE BUILT BEFORE THIS CAN RUN:** there is **no DEBUG A/B cell yet.** The
treatment builder is `productionToollessInstructions(includeToollessCapabilityIndex: true)`
— a Developer-screen cell must wire to THAT (never a copied string; #202D's
one-builder rule). Building that cell is part of this run's lane, not #297's
build lane.~~

> **✅ BLOCKER DISCHARGED, 2026-08-08 (Task 3 of the A/B-harness lane, branch
> `t27-297-ab-harness`).** The cell exists: `runToollessIndexBattery(trials:)`
> (`LocalChatBackend+Battery.swift`, commits `2d9b94b`/`257c000`/`6947370`)
> wired to the Developer-screen button `toollessIndexBatteryButton` (commit
> `d513505`), sitting beside the other probe buttons. **Its exact label, for
> whoever runs the phone: "Toolless index A/B n=20 (120)".** Gate PASS on
> this branch. **The remaining prerequisite is only the OTA stage** — this
> code postdates OTA 2250 (staged before PR #285's build-phase merge), so
> the phone needs a fresh re-stage before this row can run; nothing else
> blocks it.

> **✅ THE CELL IS SPEC'D 2026-08-08 —
> `planning/superpowers/specs/2026-08-08-297-toolless-index-ab-design.md`
> (Owen approved the design; scoring approach, detection approach, n=20 all
> confirmed).** `runToollessIndexBattery(trials:)`, 2 arms × 3 prompts × n=20.
> Three things from it that change how this row runs:
> - **Sequencing: the harness lane cannot start until PR #285 merges** (or must
>   branch from `t27-297-toolless-index`) — `includeToollessCapabilityIndex`
>   does not exist on `main` yet, and starting from `main` fails as a
>   missing-argument error that looks like a typo. **(Historical, 2026-08-08:
>   PR #285 merged as `5521260` and the harness lane — `t27-297-ab-harness` —
>   started from `main` after that merge, per plan.)**
> - **297-C is a UNION measure — claim OR tool syntax — inherited from #202C**,
>   whose gate FAILED by measuring only prose lies while the control's failures
>   moved into raw tool syntax (lies 10/12→4/10, syntax 2/12→6/10). Either
>   pattern set alone reproduces that mistake.
> - **Two halves of this run are transcript READS, not automated:** 297-C's
>   backstop and 297-B's correct-arithmetic / is-it-a-haiku judgments, which
>   no flag can score. The emit line carries the text, so it is reading — not
>   re-running. **Corrected 2026-08-08 (findings pass):** 297-C is scored on
>   ALL THREE prompt rows, not just `whatcanyoudo` — read every trial the ARM
>   SUMMARY flags on any row, not only the treatment's 20 `whatcanyoudo`
>   replies.
> - **A flagged 297-C hit is not automatically real (findings pass,
>   2026-08-08):** some patterns (`"action:"`, `"done!"`, `"done —"`) are
>   deliberately broad and will catch ordinary prose that is neither a claim
>   nor tool syntax. Since the patterns are correctly frozen, the transcript
>   read is the ONLY way to catch a false flag — confirm a flagged trial is a
>   genuine claim/syntax leak before it fails the bar, the same way you'd
>   confirm a pattern gap didn't let a real one through.

- **What to do:** device A/B. Control = the shipped toolless payload
  (`toolless-lic2` + clause v2). Treatment = same + the index sentence.
- **Rows:** "What can you do?" at n=20 per arm; plus the two toolless canaries at
  n=20 per arm — **"What's 2+2?"** and **"Write a haiku about sledding"** (exact
  text, from `LocalChatBackend+Battery.swift:158-159`).
- **Bars (registered in the #297 entry BEFORE any code):**
  - **297-A** ≥90% of trials (≥18/20) name ≥8 of the 10 non-vision capability
    families.
  - **297-B** canaries no worse than control beyond the stated margin.
  - **297-C** **ZERO** trials claim a performed device action or emit tool syntax
    — a single occurrence FAILS the bar. This is the specific risk: the sentence
    names capabilities on a branch with NO tools armed (#196's disclaimer tic,
    #202B's asserted-create).
- **Pre-registered responses:** 297-A missed → the sentence does not ship, #257's
  conversational bar stays open. **297-B or 297-C missed → does not ship
  REGARDLESS of 297-A** (a capability index that costs honesty on the branch built
  to protect honesty is not a trade worth making).
- **Why it exists:** device-verified 2026-08-08 on build 2225 — production's
  one-Bool router routes "What can you do?" **toolless**, and the reply named
  **zero** capability families (`IN=500`, a beltless turn). #284's armed-side fix
  cannot reach that question.

> **✅ RAN, 2026-08-09 — run `A04154D7`, OTA build 2271 (merged `main`
> `11aaeb2`), iOS 27.0 (24A5390f), `scored=20/20` on all six rows (no
> swallowed trials). 297-A MISSED at 7/20 vs the ≥18/20 bar; 297-B and 297-C
> both MET clean. The sentence does not ship; #257's conversational bar
> stays open. This row is done — no re-run is owed. Full numbers, the
> per-trial distribution, and the compression finding: OPEN_ITEMS #297.**

### Z2 · #290(a) — history-vs-body-budget, read the logged sizes · **RULED: measure before deciding**

- **What to do:** Developer screen → **Runs Transport switch ON** (it ships OFF).
  Then a LONG thread plus an image-attached turn — the shape that can exceed the
  budget.
- **Signal:** the one-shot warning log that fires when `history + attachments`
  exceeds the 900 KB budget (shipped in #283). Read the real sizes.
- **The decision it unblocks:** trim oldest-first vs raise the budget vs leave it
  measured-and-unbounded. Owen 2026-08-08: *"Measure deliberately, then decide"* —
  do NOT decide from first principles.
- **#290(b) is CLOSED, not owed** — Owen ruled 2026-08-08 there is NO whole-`send()`
  deadline: host model think-time varies wildly (his example: Kimi K3 vs DeepSeek
  flash), so a fixed whole-turn clock would misclassify slow models as failures.

### Z3 · #286 — honest-settlement smoke check · **cheap, fold into any sitting**

Merged tonight (PR #283). A failed ACK / `query_result` now classifies the drain
`.failed` instead of lying `.delivered`. The unit bars are met; what a device adds
is the **live plugin** — the risk is a regression in the HAPPY path or a hot loop,
not the failure path.

- **What to do:** nothing special — ordinary use with the platform link active
  (sensor traffic / `hermes_mobile` tools) for a while.
- **Signal (mostly host-side, Claude can read it):** the plugin outbox shows no
  growing undelivered backlog — `~/.hermes/plugins/talaria/outbox.json` absent, or
  present with everything carrying `delivered_at`. **Baseline recorded 2026-08-08:
  no `outbox.json` at all on the Mac = the healthy state.** App-side: no repeated
  drain-failure lines, no backoff ladder stuck.

### Z4 · #295 — expiration recovery · **OPPORTUNISTIC ONLY — do NOT schedule**

Merged tonight (PR #284). **Deliberately not triggerable:** the path is reachable
only from an **attachment** turn (`beginContinuedSend` is wired only when
attachments are non-empty), **backgrounded**, when **iOS decides** to revoke the
continued-processing budget. You cannot request that revocation, and a
"nothing happened" sitting would prove nothing — which is why **no device bar was
registered** and bars 295-A/B/C are unit-pinned instead.

- **If it ever happens in real use:** the user row should show **`.working`** and a
  reply should arrive via the reconcile loop — instead of the old silent hole
  (delivered-looking prompt, no reply, no spinner, no retry). **Screenshot it and
  say so** — that is the only way this behavior is ever seen live.
- **Gate ruling worth knowing:** a **local-brain** turn deliberately does NOT arm
  recovery (it keeps finalize-and-`.delivered`) — arming one would have adopted a
  later Hermes reply onto a dead local turn and destroyed its partial.
- **➡️ If you want to exercise the recovery machinery on purpose, run §Z8
  instead** *(added 2026-08-09)*. A gateway restart mid-turn is deliberately
  triggerable and drives the same `PendingRun` → reconcile → adopt path from a
  different entry point. **It does not score 295-A** — different trigger — but it
  is the only way to see the recovery arm work without waiting for iOS to revoke
  a budget.

### Z5 · #284 — the `fullBelt=` budget contrast · ~~opportunistic, no bar~~ **✅ CAPTURED 2026-08-09 — `fullBelt=1648tok`. Nothing further owed.**

> **✅ 2026-08-09, build 2330 — captured for FREE while running R7, no setup, no
> dedicated turn.** Two toolless on-device turns, ~11 minutes apart, both
> reporting the same figure:
> ```
> 13:21:04  session budget: 0 tool(s) ~0 tok + transcript ~527 tok of window 8192 — ~7665 free fullBelt=1648tok (#228)
> 13:32:39  session budget: 0 tool(s) ~0 tok + transcript ~565 tok of window 8192 — ~7627 free fullBelt=1648tok (#228)
> ```
> **The un-narrowed belt costs 1,648 tokens — the real number #229/#101 have
> never had.** Note the shape these two rows happen to capture: both turns were
> routed **toolless**, so `0 tool(s) ~0 tok` is the *armed* cost and `fullBelt`
> is what arming WOULD have cost. Against an 8,192 window that is **20.1%**.
> An armed-turn reading is still worth taking opportunistically for the
> contrast, but this row's stated signal is met.

*(original row text follows, kept for the record)*

Not owed (arming didn't ship, so nothing narrows — the #284 verdict records
"reclaim: n/a"). But the line now measures the **un-narrowed** belt cost per turn,
which is a real number #229/#101 have never had.

- **What to do:** Developer screen → verbose logging ON, then any ARMED turn.
- **Signal:** the session-budget line, grep `session budget:` — the new field is
  `fullBelt=<n>tok` (or `fullBelt=—` when unknown; never a fabricated 0).

### Z6 · #293(b) — reconcile clock-skew delta · **no repro needed, watch for it**

Instrumented 2026-08-07, deliberately NOT fixed — the strict `>` comparison and
zero slack are untouched pending measurement.

- **What to do:** nothing special; the line fires on a **failed reconcile pass**.
- **Signal:** the logged client `pending.sentAt` vs the newest host row timestamp,
  and their delta. That delta is what decides whether the sibling guard's 60s
  clock-skew slack (`historyAdoptsQueuedTurn`) belongs here too.

### Z7 · 288-C — orphan device rows re-run · **PRECONDITION NOW MET**

The #285 profile-atomicity fix **merged 2026-08-08** (PR #281), which was 288-C's
stated precondition (*"the re-run that actually proves the leak stopped"*).

- **What to do:** after some **real profile-switch traffic**, re-read each paired
  host's `devices.json` and cross-check `active:true` rows against pairings the
  phone recognizes.
- **⚠️ Read the result carefully:** a found orphan is **NOT automatically a fix
  failure.** `pair()`'s checkpoint sits between the pair RESPONSE and the Keychain
  store, so a `stop()` landing while that POST is in flight can still mint an
  orphan. **Record WHICH window produced it.** 288-C is not a total seal and must
  not be reported as one.

---

### Z8 · #295 / #235 recovery — **GATEWAY RESTART MID-TURN. Cheap, deliberately triggerable, and it tests machinery Z4 cannot reach** *(added 2026-08-09)*

> **🔴 STOP — THIS ROW'S PREMISE IS FALSE ON THE MAC, verified 2026-08-09.
> Attempt 1 that day was VOID. Read this block before running it again.**
>
> **1. The two upstream commits this row rests on are NOT installed.** The text
> below says `51fa7db46` + `d9ddfb23d` are *"both already on the Mac install"*
> and therefore persist a closing assistant row. Checked at the file level, with
> a positive control so an empty grep could not read as a negative:
>
> | revision | drain test file | shutdown-interrupt code |
> |---|---|---|
> | `01a1037d1` — what the listener served | absent | 0 hits |
> | `ceebb21dd` — checkout HEAD | absent | 0 hits |
> | `d9ddfb23d` — the commit itself (**control**) | — | **2 hits** |
>
> `git branch -a --contains` returns **nothing** for either commit — they are
> fetched objects on no ref, **not on `origin/main`**. So this is an **unmerged
> upstream PR**, and `hermes update` will NOT bring it. **Pass criterion (b) is
> therefore expected to fail for a HOST reason.** Run (a) and (c) as real bars
> and treat (b) as a measurement of today's production behaviour — do not score
> it as a failure.
>
> **2. iOS autocapitalize silently defeats the fixture.** Attempt 1's prompt
> became `Sleep 25; echo RESTARTTEST` — capital `S` is not a command, so it
> no-op'd, the turn was never long-running, and the shutdown landed after it had
> already completed. **The agent itself flagged the capital**, which is the only
> reason it was caught. Write the prompt so the command is not sentence-initial,
> and confirm the lowercase `s` on screen before sending.
>
> **3. ⚠️ THE RESTART CAN LEAVE THE GATEWAY HEADLESS — budget for it.** launchd
> respawned 6 s after the old API server released; the socket was not free;
> `[Errno 48] address already in use`; the gateway then ran for **two minutes
> with a healthy PID and no `:8642` listener**. A second `kill` fixed it in 2 s.
> **After the kill, verify the LISTENER, not the process** (#264), and be ready
> to restart again:
> ```bash
> lsof -nP -iTCP:8642 -sTCP:LISTEN -t
> ```
>
> **4. ~~Timing that actually works: … kill once the terminal activity is
> visibly RUNNING.~~ SUPERSEDED same day — the phone CANNOT provide this
> trigger.** Trial 2 proved it: the runner watched for "terminal activity,"
> but the screen does not reliably distinguish model-thinking from
> tool-running, and the kill landed **9 s after the turn had already
> completed** (the model thought for 4 s, not 60; the 90 s the runner read as
> thinking WAS the tool). **The working trigger is host-side:** watch
> `agent.log` for `tools.terminal_tool: local environment ready`, then kill
> ~15 s later — automated, no human timing anywhere. Trial 3 landed 15 s into
> a 300 s sleep this way, first try.

> ## ✅ Z8 RAN 2026-08-09 (trial 3; trials 1–2 void) — (a) MET · (b) UNEXERCISABLE via SIGTERM · (c) no duplication, wording inapplicable. **DO NOT RE-RUN AS WRITTEN — the row's core premise is false on this host in the GOOD direction.**
>
> **What the host actually does on SIGTERM mid-turn: it DRAINS.** Full arc,
> build 2330, gateway at checkout head:
> ```
> 14:26:12  SIGTERM (kill landed 15 s into a 300 s sleep, host-log-triggered)
> 14:28:29  drain done +137.06s — timed_out=False, api_at_start=1, api_now=0
> 14:28:34  adapters disconnected; final-cleanup tool kill
> 14:28:37  exit code 1
> 14:28:42  new listener bound (cleanly this time — headless respawn is a
>           2-of-3 RACE, not deterministic)
> ```
> The drain saw the active API turn (`api_at_start=1`), kept the listener AND
> the phone's SSE stream alive for 137 s, and let the turn COMPLETE through
> the teardown. **The stream never broke, so the reconcile loop was never
> invoked — there is nothing for `PendingRun` → reconcile → adopt to do.**
> This row's premise paragraph ("the turn was amputated with nothing
> persisted") is wrong for this host: SIGTERM defers the restart rather than
> amputating. **Only SIGKILL would exercise the recovery machinery**, and
> that variant skips every teardown the drain exists to do — it is NOT
> queued; it is a decision for Owen.
>
> **Verdicts against the pre-registered bars:**
> - **(a) ✅ MET.** Owen, verbatim: *"no vibration, no error indication."*
>   The user row never flipped `.failed`; the UI showed an honest
>   "STILL WORKING" throughout the 137 s drain. #291's guarantee held under a
>   real host restart.
> - **(b) ⛔ UNEXERCISABLE via SIGTERM** — see above; not a fail. What was
>   measured instead, and it is worth having: **a user whose turn is live when
>   the gateway restarts feels nothing at all** — the reply arrives on the
>   ordinary stream and the restart is invisible.
> - **(c) ✅ in spirit, literal wording inapplicable.** The bar says "ONE
>   assistant row, not two" — but this turn LEGITIMATELY produced two
>   assistant messages (an interim "Running —" and the final "Done"), which
>   the bar's fixture never anticipated. What (c) guards is DUPLICATE
>   ADOPTION, and there was none: the transcript renders exactly the rows the
>   host history holds, once each. (Screenshot-verified; a force-quit
>   re-render check is the remaining confirmation and was pending at
>   write-up.)
>
> **Two host findings, filed from the same run:**
> - **A shutdown-killed process is reported as a CLEAN EXIT.** The wait tool
>   returned `completion_reason:"exited", termination_source:"", exit_code:0`
>   for a process the gateway's own final-cleanup killed. Partial answer to
>   §R5/#296-C2 from an unplanned angle: the host does not merely omit error
>   fields — it can mislabel a termination as voluntary success.
> - **⚠️ FIXTURE DEFECT, inherited by every plan built on this row's own
>   suggested prompt:** `sleep N; echo X` uses `;`, so killing the sleep
>   RUNS the echo — output `RESTARTTEST`, exit 0, and **a killed command
>   reads as a successful one.** The trial's "Done ✅ / exit 0" was real
>   output honestly captured, not model fabrication — the kill itself
>   triggered it. Any future amputation fixture must use `&&`.
>
> **Errors made running this, kept for the next runner:** two pollers
> declared recovery on seeing the DYING process's socket (compare PIDs,
> always); and a `cut -c1-170` truncated the drain log line, briefly
> producing a false "the drain counter is blind to API turns" claim —
> `api_at_start=1` was in the cut-off tail. Both corrected same hour.

**Why this exists.** Z4 above is opportunistic *because you cannot ask iOS to
revoke a background budget*. **This one you can trigger on purpose**, and it
exercises the same downstream recovery machinery (`PendingRun` → reconcile →
adopt) from a different entry point. It also verifies genuinely NEW upstream
behaviour: `51fa7db46` + `d9ddfb23d` (both already on the Mac install) now
**cooperatively interrupt in-flight turns on gateway shutdown, covering both
session-chat routes**, and `_persist_session` is not gated behind a
not-interrupted check — **so a restart now writes a closing assistant row where
it previously wrote none.** Before those commits the turn was amputated with
nothing persisted.

**No live-install gate needed.** Restarting the Mac gateway is routine —
launchd-supervised, `kill` = clean respawn. This loads no experimental code, so
it does not ride the per-experiment authorization.

**Setup:** phone on the **Mac Mini** profile, Hermes brain, chat screen open.

1. Send a turn that will run for a while (e.g. `sleep 25; echo RESTARTTEST`, or
   any prompt that takes >15s).
2. **While it is still streaming**, on the Mac: `kill` the `:8642` listener.
   launchd respawns it; the gateway answers again ~15–20s later.
3. Watch the phone **without touching it** for ~90s, then foreground/background
   once.

**Pass:**
- **(a)** the user's row does **not** flip to `.failed`, and **no error haptic**
  fires (this is #291's guarantee under a new stressor).
- **(b)** a reply **arrives** — via the reconcile loop, not a re-send. It may
  legitimately be the literal **`"Operation interrupted."`**, which is the host's
  honest placeholder and counts as a PASS, not a failure.
- **(c)** the transcript shows **one** assistant row for that turn, not two
  (#237's double-adopt guard holding under a real restart).

**What this does NOT prove, stated so a green run is not over-read:**
- It does **not** exercise #295's own trigger. #295 fires on
  `cancelStreaming(hardStopHost: false)` when **iOS** revokes a background
  budget; a gateway restart kills the *stream*, which arms the pre-existing
  `.interrupted` path. **Shared downstream machinery, different entry point** —
  a pass here raises confidence in the recovery arm, it does not score 295-A.
- **The known residual applies:** the host appends its closing placeholder only
  when the tail is a `tool` message. **Kill the gateway during the FIRST model
  call — before any tool runs — and nothing is persisted, so nothing is
  recoverable.** If step 1 uses a prompt with no tool call, expect (b) to fail
  and that is CORRECT behaviour, not a defect. Use a tool-calling prompt.

**Bonus reading, free while you are here:** `GET /api/sessions/{id}/messages`
after the restart shows whether the closing row landed server-side —
distinguishing "the host never wrote it" from "the app never fetched it".

**Related, and worth contrasting in the same sitting:** the runs plane behaves
*worse* here. `_run_statuses` is in-memory with a 3600s TTL, so a gateway restart
drops it and `GET /v1/runs/{id}` returns 404 — the sessions plane is on disk and
survives. If the runs switch is ON, the same test should NOT recover, and that
asymmetry is itself the finding.


## Consolidated run 2026-08-07

**Context (written 2026-08-06 evening):** Owen approved one consolidated
phone-in-hand session covering all outstanding device debt, to run tomorrow
at work on the build he installs at 7am. This section is the live queue for
that session. The 2026-08-02 SITTING PLAN just below is not deleted — its
Sitting 1 and most of Sitting 2 are DONE (their rows carry ✅ verdicts
throughout §F1/§F5); Sitting 3 (voice+calls, Shelley, scheduled 2026-08-04)
has **no verdict recorded anywhere in this file**, so it is treated as
NOT run and folds into Group 8 below (renumbered from Group 6 by the
batch-3 addendum just below); Sitting 4 (§F8) is **retired outright** —
see "Dropped from tomorrow" below.

**New this pass, reconciled against OPEN_ITEMS #21/#56/#58/#61/#74/#75/#77/
#78/#80/#81/#82, archived #83, and #262 (bar 262-E, PR #277 merged — it WILL
be in tomorrow's build):** #262-E, #75, #77, #78, #80 (revised), #21
(dual-host), #56, and the Display Zoom re-test are added below in their
state groups. #61's and #81's existing rows needed no new check — #61 was
already correctly filed in §F2; #81 turns out to be dead, see below.

**#58 prerequisite check (git-verified 2026-08-06):** OPEN_ITEMS #58's header
still reads "`.main` execution BUILT 2026-07-27 (cloud, NOT compiled)" — that
wording is stale. `git log` shows the cloud branch
(`claude/opus-t27-58-controls-eopguj`) merged same day via **PR #154**
(`ebc0347`), with a Mac-side `xcodegen generate` regen committed eight
minutes earlier (`0bfb80d`, "cloud lane could not produce this") — both are
ancestors of current `HEAD` (`6b2f6d6`), and `TALARIA_MAIN_APP` is live in
`project.yml:93` today. **Confidence: HIGH that it compiles** — the flag has
ridden hundreds of green-suite/gate commits on `main` since 2026-07-27 — but
no commit or tracker note ever recorded an explicit build-success check for
THIS lane, so treat tomorrow's device pass as also closing that gap.
**No new build needed — #58/#179 is runnable on tomorrow's OTA as filed in
§F6.**

**MAJOR FINDING — #238 (closed 2026-08-03, "notification removal") deleted
the entire `UNUserNotificationCenter` surface. Confirmed by source grep
2026-08-06: zero hits anywhere in the tree for `UNTextInputNotificationAction`,
`HERMES_REPLY`, `handleNotificationReply`, `UNUserNotificationCenter`,
`aps-environment`, or `remote-notification`.** #238's own closure text says
explicitly: *"Confirmed collateral, Owen accepted explicitly:
reply-from-the-lock-screen (#47) and its failure banner"* is gone, and its
"everything goes" list names "the push-token pipeline (#189)" outright by
number. **Three rows already in this document are therefore DEAD, not
merely stale** — annotated MOOT in place below (§F1's `#147`, §F3's `#189`,
§F4/§F8's `#81`, §F8's `#226`) rather than deleted or rewritten. This
retires the entire former Sitting 4 (§F8 had exactly two rows, both dead).
#80's silent-push sub-checks are dead for the same reason — Inbox is
poll-fed only now (explicitly on #238's "STAYS" list) — its still-live
checks are rewritten below to the poll path.

**#225 update — the §F1 row below still reads like a first-time check; it
is not.** It already ran the night it was filed (2026-08-02, "Lane 1":
L1-A/C/D/E PASS, L1-B failed only on one refusal-grind trial), and the two
findings that run produced — **#230** (WeatherKit daily forecast) and
**#232** (the refusal grind) — are both built AND device-confirmed fixed
(#232: "ZERO refusals on the control prompt (was 57), turn 5.9s (was
minutes)," 2026-08-03). Tomorrow's run against the *original* 4-bar fixture
(B1–B4) is a **confirmation run of a very likely-already-fixed defect**, not
a first look — kept in the plan only because that exact fixture has not been
re-run since the compound fix landed.

**#82 residual, newly folded into §F6 (not previously a runnable row):** its
2026-08-01 #220 flag records that the 2026-07-16 device confirm ran on ONE
voice engine and nothing logged which — "the other engine's half is
unverified." The engine-naming log line now exists
(`VoiceEngineRouter.swift:196`, shipped with #221's fix). See Group 8 (moved
from Group 6 by tonight's batch-3 addition below).

**Batch-3 addendum (same evening, 2026-08-06, later): three shipped lanes'
device checklists were never centralized and were at risk of being
forgotten — #162 (Tasks), #163 (Skills), #165 (Insights), all `SHIPPED, on
main` with a "device checklist still owed" header, and #93 (continuity
fabric, Lane A), merged 2026-07-10 and STILL never device-verified at all.
Folded in below as new **Group 2** (drawer surfaces) and new **Group 7**
(kill/relaunch cycles), pushing the former Groups 2–6 down to 3–6 and 8.
This is a real, not cosmetic, growth in scope — the total estimate at the
bottom moved from ~3–3.5h to ~4–4.5h and that is not shaded down.**

> ## ⏸ WHERE THIS RUN STOPPED — reconciled 2026-08-07 (tracker tidy pass)
>
> **The run started, paused twice for fixes, and is PART WAY THROUGH GROUP 1.
> Do not re-run what is already marked below.** Three OTA builds carried it:
> 2120 (first attempt), 2145, then 2154.
>
> **MET on device today — all closed, nothing owed on these:**
> 262-E · 265-E (OTA 2120) · **78-F** (2145) · **139-F** (2145) · **278-D**
> (2145) · **277-C + 277-D** (2154) · **281-E** (2154) · **78-G** (2154, the
> same run as 281-E — one pass satisfied both). Items #139, #274, #275,
> #276, #277, #278 and #281 are closed and swept to
> `OPEN_ITEMS-ARCHIVE.md`.
>
> ## ✅ RUN 2026-08-07 EVENING (OTA 2171, Mac Mini profile) — 78-F2 AND ALL FOUR 3A BARS MET. DO NOT RE-RUN THESE.
>
> **78-F2 ✅ MET ~17:51** on the ON-DEVICE brain (the requirement that kept
> it owed). Regenerated reply read "2 + 2 is 4." — no acknowledgement of a
> prior answer, which is the clause the Hermes path could never satisfy.
> Removed turns stayed gone through 10s, background/foreground, and
> force-quit. **#78 is CLOSED**; it leaves this queue.
>
> **3A-G ✅ · 3A-H ✅ · 3A-F ✅ · 3A-C ✅** — all four with host-log
> evidence (`~/.hermes/logs/agent.log` watched live). Full detail in
> OPEN_ITEMS #283's device-pass note. Three things a future runner needs:
> 1. **3A-F took THREE attempts to trigger.** Backgrounding ~40s and a
>    ~20-40s network drop did NOT kill the stream — TCP bridged both, no
>    poll ever ran. Only an outage held **past the 60s stall guard** (75s+)
>    engaged recovery. If you re-run it, hold the interruption past 60
>    seconds or you will measure the happy path and think you measured
>    recovery.
> 2. **The recovery is invisible by design** — the UI keeps showing "still
>    working" while it polls, so the screen cannot tell you which path ran.
>    Only the host log can. Owen's read ("never stopped") was correct AND
>    the mechanism had switched underneath.
> 3. **3A-C is two halves and both are load-bearing:** Stop → host log shows
>    `exit_code 130` / `interrupted_by_user`; walking away → NO `/stop` sent
>    and the turn completes normally. If a future change makes walking away
>    also stop the host, that is a regression.
>
> **Still open from Group 1 and below:** the `#80` row onward (#80, #21
> dual-host, C1/C3, #184/#185), then Groups 2–8. Also still unrun and not a
> bar: **Edit & Resend on a turn that HAD an attachment**.
>
> ---
>
> **THE FRONT OF THE QUEUE — two things, in this order:** *(superseded by
> the ✅ block above — 78-F2 is done; the Group 1 remainder stands)*
>
> **1. 78-F2 — the ONLY device bar left over from the fix lanes, and it is
> OWED.** ⚠️ **It requires the ON-DEVICE brain selected in Settings.** Every
> passing run of 78-F used **Deepseek flash — a Hermes-hosted model** — so
> the local-brain clauses have never been exercised, and *a runner who
> repeats this on Hermes has not run this bar.* On a CLEAN thread (no user
> turn carrying more than one reply), send at least three turns, regenerate
> the reply to the MIDDLE user turn, and assert: that reply and every row
> below it vanish at the tap; the producing user row is a FRESH row carrying
> the regenerate-time timestamp; the new reply appears at that position;
> after 10s and a background/foreground the removed turns have NOT
> reappeared; force-quit + relaunch — still absent. **Two clauses only the
> local brain can reach:** the re-roll must genuinely re-ask WITHOUT the
> original answer in context (falsified by a reply that acknowledges having
> already answered — on the Hermes path the model DOES know and said so:
> *"Still 4"*), and the truncated mirror must be what a relaunch restores.
> Full text in OPEN_ITEMS #78.
>
> **2. The Group 1 remainder, from the `#80` row onward** — #80, #21
> (OJAMD side), #21 (announcement-scan noise), C1, C3, #184/#185 — then
> Groups 2–8 unchanged. Also still unrun from the #78 row and NOT a bar:
> **Edit & Resend on a turn that HAD an attachment** (does the attachment
> return to the composer).
>
> Nothing above Group 1's `#80` row needs the phone again except 78-F2.
>
> **📲 THE BUILD FOR ALL OF THIS: OTA build 2171** (`claude/t27-283-3a-runs-transport`
> @ `8652633`, Release), staged 2026-08-07 15:30 at
> `https://owens-mac-mini.tail5663a6.ts.net` — install from phone Safari.
> **It carries BOTH halves of the queue:** every fix lane merged today (so
> 78-F2 and the Group 1 remainder run on it unchanged) **and** slice 3A
> behind its OFF-by-default switch. Verified in the shipped binary, not
> just claimed: the Release ipa contains the "Runs Transport (Phase 3)"
> toggle string and the `/v1/runs` paths, and the toggle is outside every
> `#if DEBUG` block, so it is reachable in this Release build. One install
> covers the whole sitting.
>
> **3. NEW 2026-08-07 — Phase 3 slice 3A device bars (#283), added when the
> lane's build-side work went green.** A SEPARATE sitting from the fix-lane
> debt above, and it needs **the Developer switch "Runs Transport (Phase 3)"
> turned ON** — it ships **OFF**, and with it off none of these paths
> execute at all (pinned in the suite), so an accidental off-run measures
> the old transport and proves nothing. Run against a REMOTE host; the local
> brain is untouched by this lane.
>
> - **3A-F (the headline):** one real remote conversation end-to-end on the
>   runs path — including a **tool-using turn** and a turn whose stream you
>   kill by **backgrounding the app mid-answer**. The answer must still
>   arrive exactly once (it is fetched by status poll, not replayed).
>   **Write down how LONG that recovery took** — the poll knobs (2s interval
>   / 120s budget; 20s on the sync path) are engineering guesses, and a
>   zombie stream composes to ~60s stall + up to ~120s poll ≈ 3 minutes of
>   silent-looking screen. If it feels broken, the knobs are the fix, not
>   the design.
> - **3A-G (history continuity — the one that fails QUIETLY):** turn N+1
>   must demonstrably see turn N's content. **Assert the actual content, not
>   merely that an answer arrived** — runs do not read server history, the
>   app supplies it, and a missing history does NOT error: the agent answers
>   plausibly from long-term memory instead. Use a marker ("reply with
>   exactly KUMQUAT-N4A", then next turn "what marker did I ask for?"). A
>   confident wrong answer is a FAILED bar. Then leave the thread, re-open
>   it, and confirm the transcript matches what the sessions plane shows.
> - **3A-H (attachments):** send an image on the runs path and ask about it;
>   the agent must answer correctly about the image (attachment turns are
>   wrapped differently on this plane — the old shape the app used is
>   rejected by the server outright).
> - **3A-C (stop is REAL now — and the walk-away contrast is half the bar):**
>   on a long tool-using turn, tap **Stop** → host-side work actually stops.
>   **Evidence must be the HOST's own log, not the app's UI** (the
>   sessions-plane Stop only stops the app listening; the host keeps
>   generating and spending). Then the contrast: start another long turn and
>   **switch threads or start a new chat instead of tapping Stop** — the
>   host must KEEP working and the answer must still be there when you come
>   back. The two halves are deliberately different behaviors; if walking
>   away also kills the run, that is a regression.
> - **Artifacts on this path are EXPECTED to be content-less** (a chip
>   naming the file, no inline content) — the runs stream carries no tool
>   arguments. Honest absence, not a bug; the mirror that restores it is
>   slice 3D. **Fabricated content would be the bar failure.**
> - **Not built yet, so do not look for them:** in-chat approvals (3B) and
>   steering (3C).

### (a) Runnable now, ordered to minimize churn

**Group 1 — Default state: PAIRED + CONNECTED to OJAMD, no settings changes
(start here, it's already where the phone rests).** Est. ~30 min.
- [x] #262-E + #265-E — **✅ PASS 2026-08-07 on OTA 2120 (Deepseek flash,
  narrate-through-a-write prompt). BOTH ITEMS CLOSED.** Owen: *"chip stayed
  put. Locked to a word instead of splitting one."* then *"tap worked, chip
  still in place after relaunch."* All four parts met: no movement during
  streaming · word-boundary split (the 2026-08-06 "lan⟨chip⟩ded" shape is
  gone) · mid-stream tap opens the preview without racing the model ·
  placement survives kill + relaunch + history reload (the anchor persists
  with the message). #262 and #265 swept to the archive.
  *(original check text, kept for the record: send a prompt on the fastest
  available model that makes the agent write a file mid-turn and watch the
  reply stream — chip appears under the write_file card at its generation
  point, does NOT move while later text streams beneath, is tappable
  mid-turn, and stays anchored after relaunch/history reload.)*
- [~] #78 — **RUN 2026-08-07 on OTA 2120. PARTIAL: two PASS, two FAIL. The
  two FAILs paused the whole device run** (Owen: "lets pause the phone work
  while you fix it") — resume the consolidated run on the build that carries
  the fixes, starting at the #80 row below.
  - ✅ **Copy / Share / Select Text** — work on every bubble type.
  - ✅ **Streaming guard, in session** — no menu appears on a bubble while
    its run streams; Regenerate/Edit correctly withheld.
  - ❌ **Regenerate a mid-history reply** — Owen: *"I regnerated the
    10:50pm, and it never showed that I did anything today until I responded
    to that regeneration. And it put it below the previous answer I
    regenerated."* Truncation fires and is then undone by the backend-mirror
    merge; the regenerated reply lands at the tail. Edit & Resend carries the
    same defect delayed one turn (*"was weird. worked technically"*).
    Diagnosed in full — see OPEN_ITEMS #78's 2026-08-07 note; bars 78-A..F
    pre-registered; fix lane building. Spun out: #274, #275.
  - ❌ **Streaming guard does NOT survive re-entry** — Owen: *"If you leave
    and come bck immediately, it presents the option."* Screenshot: Edit &
    Resend offered on a row still in flight (clock icon, no reply yet).
    `isTranscriptBusy` ← `chatStore.isStreaming` ← `streamingMessageID`;
    under diagnosis. Consequence to establish: an edit-resend under a live
    run truncates and re-sends while that run is streaming.
  *(original check text, kept for the record: long-press each bubble type;
  Copy/Share/Select on each; regenerate a MID-history reply and confirm the
  transcript truncates from that turn; Edit & Resend with and without an
  attachment; confirm no context menu on a streaming bubble. STILL UNRUN
  from this check when the pause was called: **Edit & Resend on a turn that
  HAD an attachment** — does the attachment return to the composer.)*
  - **RESOLUTION 2026-08-07 — both ❌ rows above are FIXED and re-verified
    on device. Neither needs re-running.**
    - **Regenerate a mid-history reply → ✅ 78-F MET on OTA 2145.** Owen,
      fresh chat, three turns, middle reply regenerated: *"did 3, regnerated
      the middle, the 3rd disappeared."* Durability held: *"Backgrounded and
      returned - no change. Force quit and returned - no change."* A first
      attempt failed diagnostically — it ran against a thread the PRE-FIX
      bug had already corrupted (one user turn carrying two stacked
      replies), and the real defect behind it was **#281**, fixed and
      **281-E MET on OTA 2154** (*"regenerated text has new timestamp and
      removed the old"*). The same 2154 run satisfied **78-G** (repeated
      identical prompts — two visibly distinct bubbles, 10:37 and 10:39).
    - **Streaming guard does not survive re-entry → ✅ 278-D MET on OTA
      2145.** Owen: *"278D pass. No regenerate presented mid stream."* Filed
      and closed as **#278**.
    - ⚠️ **STILL OWED from this row: 78-F2** — the same regenerate bar on
      the **ON-DEVICE brain**, which no passing run has used. See the
      "WHERE THIS RUN STOPPED" block above; it is the front of the queue.
- [x] **NEW 2026-08-07, found mid-run — agent-file chips vanish from a
  thread you navigate away from and return to.** Owen, after 262-E passed
  in a fresh thread (chip survived force-quit + relaunch INTO THE SAME
  THREAD): all three older threads he reopened — two markdown, one HTML —
  show no chip, while *"write file card is present. Just not the chip WITH
  the file to view in the chat."* Tool activities ride the refetched
  transcript; the Tier-1 attachment is client-side only. Under diagnosis;
  bar to be written to cover SWITCH AWAY → other thread → RETURN, the path
  #258's and #262's bars both missed.
  - **✅ PASS 2026-08-07 on OTA 2154. FILED AND CLOSED AS #277.** Owen:
    *"made a new one, force quit, returned — still there. Force quit again,
    changed threads, came back, still there, pass."* (277-C). Cause was
    `ChatStore.openSession` assigning the fetched transcript over the local
    one against a single-slot conversation cache; fixed with an on-device
    sidecar keyed on the server session id. **277-D, the diagnostic marker,
    also confirmed:** *"already lost threads don't regenerate from before
    this build"* — the loss is not self-healing and the fix is
    forward-looking. **Owen's three already-damaged threads stay damaged;
    do not queue a re-check for them.** A sibling regression found in the
    same diagnosis (`mergeAttachments` silently dropping `anchorOffset`) was
    filed as **#276** and fixed in #78's lane. Nothing left on the phone for
    this row.
> **⚰️ MOOT 2026-08-09 — annotating, not deleting.** OPEN_ITEMS #80 CLOSED
> 2026-08-09 (superseded by #251 Slice 2A). **This row is not merely stale, it is
> UNRUNNABLE:** its first leg ("ask Hermes to create an inbox item") needs an
> agent-callable PRODUCER tool, and the talaria plugin registers exactly ONE tool —
> `talaria_phone_query`, a PULL (`~/.hermes/plugins/talaria/tools.py:29, 146-157`).
> `hermes talaria send` is a CLI subcommand (`admin.py:21`, `register_cli_command`
> at `:93-95`) — Owen at a host shell, not something an agent can call mid-turn. Its
> last leg (verdict readback, ex-`get_inbox_verdict`) has **no successor at all**.
> Inbox itself still works via `TalariaPlatformInboxService`; its device coverage
> lives under #251's own 2A bars (2A-A/C/D/E/F/G MET). **Do not carry this into a
> sitting.** *(Verified on the MAC install; #149's close-out records that the Windows
> plugin path does not exist on OJAMD, so that host is a separate question.)*
- [ ] ~~#80 (revised — push-delivery sub-checks are dead, see MAJOR FINDING
  above)~~ — Ask Hermes, in a Talaria chat, to create an inbox item; then
  pull-to-refresh the Inbox screen (or leave/reopen it); approve it in-app
  and ask Hermes to read back the verdict. (PASS: the item appears after a
  manual refresh/reopen — NOT automatically, that path is gone — and the
  verdict readback matches the approval. Do not expect any push banner.)
- [ ] #21 (OJAMD side) — Ask the OJAMD-backed agent to write a fresh file,
  then tap the resulting chip. (PASS: preview sheet presents and ShareLink
  works, matching the Mac-side PASS already recorded 2026-07-20.)
- [ ] #21 (announcement-scan noise, passive, no setup) — over the course of
  this session, note whether any ordinary turn that merely *mentions* a
  MobileDL path grows an unwanted attachment bubble. (Record either outcome
  — this is an eyeball finding, not strictly pass/fail.)
- [ ] C1 — Run `searchPlaces` with n=20 (never run at this n before).
  (PASS: no exception/crash.)
- [ ] C3 — Ask a `readLocation`-shaped question and read the returned
  fields. (PASS: no crash; note whether `country` is present, per the
  disclosed MapKit-migration delta.)
- [ ] #184/#185 — Exercise all three ChatStore teardown paths (row still
  reads "sim-only today"); send two attachments with the SAME filename in
  one turn. (PASS: teardown clears consistently across all three paths;
  each attachment resolves to its own local file, neither overwritten.)

**Group 2 — Drawer surfaces: Tasks / Skills / Insights (added 2026-08-06,
batch-3). All three are `SHIPPED, on main`, still PAIRED + CONNECTED to
OJAMD — the same default state as Group 1, just deeper in the app, so no
extra churn to reach them. Their device checklists lived only inside their
OPEN_ITEMS entries until tonight; quoted verbatim below, cited to their
item numbers.** Est. ~35–40 min.

*#162 (Tasks):*
- [ ] Drawer → SCHEDULED TASKS → list renders real OJAMD jobs (or the
  honest empty state)
- [ ] Create via each preset (interval / daily / weekly / once-relative /
  once-absolute) and confirm the server's `schedule_display` matches the
  preset's intent
- [ ] Advanced mode: submit a bad string → sheet stays open with the
  server's message verbatim; submit a valid cron → server display shown
  after save
- [ ] Run Now / Pause / Resume / Delete round-trips; list+detail stay in
  lockstep with no refetch flicker
- [ ] Edit an existing job: untouched fields absent from the PATCH (proxy:
  legacy deliver value survives an unrelated edit)
- [ ] needsAttention badge on a genuinely dead recurring job (PREREQUISITE:
  the item's own repro is "disable one host-side with `enabled: false` via
  PATCH" — a direct host-side API call, not a phone action; do this from
  wherever you'd run F7d's host call)
- [ ] Timezone caveat renders next to daily/weekly time input;
  once-absolute fires at the device-local instant picked

*#163 (Skills):*
- [ ] Drawer → SKILLS renders the real host list (~98 on the Mac host)
  grouped by category, Uncategorized last
- [ ] Search filters live across name/description/category; a garbage
  query shows the "No skills match" state echoing the query
- [ ] Expand a row with a long multi-line description — full text,
  newlines intact; collapse restores the 2-line preview
- [ ] Pull-to-refresh; then airplane-mode refresh keeps rows on screen
  with the REFRESH FAILED strip (never a replacement)
- [ ] Cron editor: SKILLS field shows the picker fed from the host list; a
  hand-typed value renders "(custom)" and survives an unrelated edit
  round-trip; with the gateway unreachable the field stays free text
- [ ] EDIT AS TEXT escape works and round-trips back through the picker

*#165 (Insights):*
- [ ] Drawer → INSIGHTS renders real host numbers; banner names the window
  and host, "AS OF" stamp updates on pull-to-refresh
- [ ] Totals strip agrees with a spot-check against `GET /api/sessions` on
  OJAMD (tokens in/out, tool calls, api calls); cost row absent while the
  host serves 0.0/null costs (expected today) — no "$0.00" anywhere
- [ ] By-source shows api_server/discord/tui split; by-model shows the
  real model mix; shares sum to ~100%
- [ ] Session rows: title-or-id-prefix, source badge, relative recency;
  expand shows duration/cache/reasoning/messages; a usage-less session
  shows NO zeros (row renders, numbers absent)
- [ ] >600-session host, if reachable: truncation strip appears and the
  banner count matches the fetched window, not all-time (AMBIGUOUS: no
  record of whether OJAMD currently holds >600 sessions — check the count
  first; if it doesn't, record this as untested-precondition-not-met,
  don't skip it silently)
- [ ] Airplane-mode refresh keeps numbers on screen with the REFRESH
  FAILED strip (never a replacement); CTX gauge in chat unchanged and
  never contradicted by this screen's copy
- [ ] Unpaired/bare profile: honest NO HERMES HOST CONFIGURED state — **run
  this one during Group 4 (Standalone/Unpaired) instead**, not here; it
  needs the opposite pairing state from the rest of this group, so doing
  it here would cost an extra churn cycle this document exists to avoid.

**Group 3 — Settings-dependent (batch these — one trip through Settings).**
Est. ~15 min.
- [ ] #75 — Check the chat header at: default width, both brains (HERMES /
  ON-DEVICE), a long model name (e.g. `DEEPSEEK-V4-...`), and a Dynamic
  Type sweep (Settings → Accessibility → Display & Text Size → Larger Text,
  several notches). (PASS: wordmark/status/model chip stay single-line with
  scale-then-truncate behavior at every size; the brain pill never resizes
  itself out of shape.)
- [ ] Display Zoom letterbox re-test (from archived #83): set Display Zoom
  to Larger Text, launch, check for letterboxing; if it repros, file a NEW
  item (do not reopen #83, closed as terminal against a toolchain that no
  longer exists). Restore Display Zoom to Default afterward — it affects the
  whole phone, not just Talaria.
- [ ] #186 — Needs a Settings-level permission reset first (Settings →
  Privacy → revoke Calendar/Contacts for Talaria). Then: (1) re-grant
  Calendar as "Add Events Only," ask the agent to create an event — must
  succeed on the FIRST attempt and every one after; (2) re-grant Contacts as
  "Limited" via the picker, then look up a contact on a LATER app launch;
  (3) with the add-only grant active, ask a calendar READ question — the
  reply should name the add-only grant and how to widen it, not a generic
  "enable it in Settings." (PASS: all three bars met. Sim-untestable —
  framework permission stores — so this is the only way to confirm the
  2026-08-04 grep-verified fix actually holds.)

**Group 4 — STANDALONE / UNPAIRED (§F2). Disconnect from OJAMD once, run
this whole block, then re-pair.** Est. ~25 min.
- [ ] #61 — Create local sessions with short/ambiguous first turns
  (attachment-only, or a reply that echoes the question), read the drawer.
  (PASS: on-device titles + previews are distinct from each other and from
  the reply's first line. Standalone only — the paired drawer never
  exercises this code path.)
- [ ] #190 — (a) start read-aloud, switch sessions mid-speech; (b) force a
  session-open failure. (PASS: (a) read-aloud stops; (b) a failure banner
  renders instead of a blank/stuck screen.)
- [ ] #123 — Share a URL into the app from Safari, and an image from
  Photos. (PASS: composer receives each, focused, works unpaired on the
  on-device brain.)
- [ ] #123 — PDF ACCEPT path via share sheet (never exercised; A8-3
  substituted `.txt`) (PASS: a real PDF shares in and lands as an
  attachment).
- [ ] #123 — three-share ORDER confirmation (A8-4 confirmed arrival, not
  order) (PASS: three rapid shares land in send order).
- [ ] #124 — Background then foreground with Face ID lock enabled. (PASS:
  the privacy overlay covers the scene root; unlocking offers passcode
  fallback, never biometry-only.)
- [x] ~~#124 — attempt repro of the #272 App Lock re-prompt loop
  (background/foreground churn while the unlock prompt is up).~~ **✅ DONE
  2026-08-09 via §R4 — REPRODUCED, 272-C MET. Do not run this row; the churn
  it asks for was never needed.**
- [ ] #225 (confirmation re-run — see note above) — Standalone,
  hand-launched (NOT via Xcode), on-device brain, fresh chat: "what's the
  weather gonna be in Gulfport tomorrow." (PASS, all four required: B1 the
  turn ends on its own at ≤12 tool calls; B2 non-empty reply text; B3
  honest about any limit rather than inventing data — note #230 shipped a
  real tomorrow forecast since this bar was written, so a correct answer
  now also satisfies it; B4 a normal multi-tool control turn, e.g. "remind
  me to call Shelley tomorrow at 4," still completes normally.)
- [ ] #165 (Insights, unpaired half — moved here from Group 2) — Open
  Insights with no Hermes host configured / disconnected. (PASS: an honest
  NO HERMES HOST CONFIGURED state, not a blank screen or a crash.)

**Group 5 — Mac profile active (batch the one profile switch).**
Est. ~15 min.
- [ ] #21 (Mac side, re-confirm) — Switch the active backend to the Mac
  profile. `probe-t21.pdf` should already sit in the Mac's MobileDL; tap
  the chip. (PASS: preview sheet + ShareLink, matching the 2026-07-20 Mac
  PASS — a light re-confirm, not a first look.)
- [ ] #33 (from tonight's reconciliation) — Still on the Mac profile, from
  the Talaria chat, ask Hermes to write an Apple Note and then read it
  back. (PASS: the note appears in Notes.app with the requested content,
  the #4 confirm gate fired before the write, and the read-back matches.)
  Switch back to OJAMD afterward if anything later needs it.

**Group 6 — Approvals, auto-mode OFF (§F7; needs host-side access to flip
`approvals.mode` on the dashboard).** Est. ~25 min, plus however long F7d's
stall takes (bounded by #145 to 20s/300s — it will not hang forever).
- [ ] F7b — On-device brain, ask for a reminder/calendar create; EDIT a
  field in the confirm card before approving. (PASS: the written record
  matches the EDITED values, not the originally staged ones.)
- [ ] F7c — Same, but background the phone while the card is waiting.
  (PASS: the gate survives suspension — card still there and answerable on
  return, tool not silently resolved either way.)
- [ ] F7d — Set the host's `approvals.mode` to `manual` (it is `off` today,
  dashboard `:9119` or `PUT /api/config`); ask the connected tier for
  something that needs approval; **restore `off` after.** (DISCOVERY, not
  pass/fail — record what actually shows: a hung run that fails cleanly at
  #145's timeout, a silent stop, an inbox item, or nothing at all.)
- [ ] F7e (optional) — Repeat F7d with `smart` instead of `manual`. (Record
  whether Smart prompts at all for ordinary agent work.)

**Group 7 — #93 continuity fabric: kill/relaunch cycles (added 2026-08-06,
batch-3). Batch this with Group 6 above — both need host-side access
(here, the ability to stop/restart the Hermes gateway process). This lane
merged 2026-07-10 (`PR #61`) and has NEVER had a device pass of any kind —
not "unverified since a fix," genuinely never run once. Quoted verbatim
from OPEN_ITEMS #93's own "Device checklist," items (a)–(f).**
Est. ~25–30 min, including the gateway restart's downtime.
- [ ] (a) Kill and relaunch the app mid-conversation. (PASS: the next turn
  resumes the SAME server session — no priming notice.)
- [ ] (b) Stop the gateway, relaunch the app, then restart the gateway.
  (PASS: the next turn shows the transplant notice + priming tokens in
  StatusCard.) (PREREQUISITE: needs the ability to stop/restart the
  gateway process on whichever host is active — see CLAUDE.md's OJAMD
  services section for how the gateway is/isn't a service there.)
- [ ] (c) Switch models mid-conversation. (PASS: the next turn hops with
  the notice, and the new model answers WITH context.)
- [ ] (d) Send local-brain (on-device) turns, then switch back to Hermes.
  (PASS: the transplant carries the local exchange into the next Hermes
  turn.)
- [ ] (e) Airplane mode ON, send a message, then airplane mode OFF. (PASS:
  the send parks as `.queued`, and reconnecting auto-sends it. **Must be
  airplane mode specifically** — this item's own later correction narrows
  `isUnreachableError` so a merely-unreachable/dead host over Tailscale
  surfaces as `.timedOut` → an honest `.failed` + retry, NOT `.queued`;
  only genuine offline, `.notConnectedToInternet`, queues. Using a
  black-holed host instead of airplane mode here would test the wrong
  path and likely read as a false FAIL.)
- [ ] (f) After the above, open session totals. (PASS: a PRIMING row
  appears and the session cost estimate includes priming.)

Separately, and NOT part of tonight's phone session: `CondenserFidelityTests`
(the suite-side fidelity acceptance, requires on-device Apple Intelligence)
has been reported SKIPPED rather than run since at least 2026-07-13 — "a
skip is not a pass." That's a test-run concern for whoever next runs the
full suite on Apple Intelligence hardware, not a device-pass checkbox.

**Group 8 — Voice, Control Center, and Siri: the leaving-the-app phase
(§F6 + new §F9/§F10). Run this block LAST among the runnable groups —
everything in it backgrounds the app or launches it from outside.**
Est. ~60–75 min, the biggest and least predictable group; A1/A1b need a
second person to actually call the phone.
- [ ] #129 — Audition a voice mid-session. Read which engine the
  `voice session starting on engine …` log line names. (PASS: no crash,
  session survives, mic live afterwards.)
- [ ] **#139 residual (added 2026-08-07) — free while tethered, costs no
  extra setup.** #139 itself is CLOSED (139-F MET on OTA 2145: dismiss a
  connecting voice session on BOTH brains, wait a full minute each — *"Mic
  goes off after about 1s. no pop ups scaring me in office today"*), but its
  verdicts were run from the phone in an office, so the engine was
  **INFERRED from the brain setting, not quoted** from the log. Two things
  are therefore still worth capturing on the next TETHERED voice sitting:
  (1) re-run one dismissal per brain and **quote** the
  `voice session starting on engine …` line (`VoiceEngineRouter`), per
  #220's rule that a run which cannot name its engine does not count; and
  (2) the adjacent finding #139 flagged and did not settle — the reachable
  states where realtime is never attempted (`canStartSession` false + the
  overlay skipping readiness) would present a label lie, and the same log
  line settles it for free. Not a bar and not a regression suspicion;
  recorded so it is not lost. Also filed under OPEN_ITEMS #180.
- [ ] #82 residual (new — see note above) — If #129 named an engine that is
  NOT the one #82's 2026-07-16 confirm used (unknown which that was — the
  log line didn't exist yet), repeat #129 once more forcing the OTHER
  engine (airplane mode pins native; paired+healthy pins realtime). (PASS:
  same bar as #129, on whichever engine was still unverified.)
- [ ] E1 residual — Start a native voice session; confirm the log shows a
  real capture format (not rate=0.0) and no `nullptr == Tap()` crash.
  (PASS: real format, no crash — the one leg §E1 couldn't test in sim.)
- [ ] A2b (#221) — Arms 1–3: on-device brain voice session (expect
  `engine native`, Apple TTS, `relayPaired=true`); Hermes brain voice
  session (expect `engine realtime`, OpenAI voice); then the four
  stickiness checks (mid-session switch both directions, cold relaunch,
  after re-pair, after an airplane-mode flap). Network ON throughout — do
  not use airplane mode as the fixture. (PASS: each arm reads the engine
  the setting says it should, and it stays that way across all four
  stickiness checks.)
- [~] §F6's #58/#179 — From the Lock Screen or Home Screen (cold, not from
  inside the app), tap "Ask Hermes" in Control Center. (PASS: Talaria opens
  on the Chat tab and the `.notice` perform log line appears under
  subsystem ~~`org.aethyrion.talaria27`~~ **`org.aethyrion.talaria`,
  category `controls`** — the APP process ran it, not the
  widget extension; a second tap also routes correctly.) Then tap "Talk to
  Hermes." (PASS: the voice overlay opens.)
  - **⚠️ THIS ROW'S STATED LOG LOCATION WAS WRONG — corrected 2026-08-09 in
    place.** The line emits under subsystem **`org.aethyrion.talaria`**, not
    `…talaria27`. A runner grepping the documented subsystem finds nothing and
    records a **false FAIL** on a working feature. (The app mixes both
    subsystems: `AppLock` really does log under `org.aethyrion.talaria27`,
    which is presumably how the wrong one got written here.)
  - **✅ "Talk to Hermes" HALF DONE 2026-08-09** (free, while running R7, build
    2330): `[org.aethyrion.talaria:controls] OpenHermesVoiceIntent.perform
    fired in the APP process — routing hermes://voice`, twice on two separate
    cold launches, voice overlay opened both times. **APP process confirmed —
    that is the clause this bar exists for.**
  - **STILL OWED: the "Ask Hermes" half** (opens on the Chat tab) and the
    second-tap-also-routes clause. Both are cheap; neither has been run.
- [ ] §F10 (new) — #77: type `hermes://session/{a real id}` into Safari's
  address bar. (PASS: the app opens that exact session.) Then, via
  Shortcuts, run "Open URL" with `hermes://ask?q=hello`. (PASS: composer is
  seeded with "hello" and focused, but NOT sent.) Confirm no other
  installed app claims the `hermes` scheme.
- [ ] §F10 (new) — #56 Siri Stop discriminator: "Hey Siri, ask Talaria
  twenty-seven [a question]," say "Stop" IMMEDIATELY (before the ~25s
  hand-off). (PASS: the run actually cancels, vs. the 2026-07-20 PARTIAL
  FAIL where it kept generating.) Repeat with a longer question, say "Stop"
  AFTER the hand-off. (Record whether this is uncancellable by design —
  that would make it a wording defect, not a behavior defect.)
- [ ] §F10 (new) — #56 tailnet-unreachable re-test: airplane mode ON, "Hey
  Siri, ask Talaria twenty-seven [a question]." (PASS: Siri surfaces an
  honest queued/will-auto-send dialog. Current source
  (`AskHermesIntent.swift`'s `.queued` case) suggests this may already be
  fixed via #90's offline compose outbox, but the 2026-07-20 sweep recorded
  a FAIL on this exact scenario after that code had already merged — this
  needs a fresh device confirm, not an inference from source. FAIL looks
  like a "still working" hand-off with no error.)
- [ ] A1 / A1b (needs a second person to call the phone — arrange in
  advance) — Start a live voice session on one engine (airplane mode pins
  native; paired+healthy pins realtime), have them call, and read the
  engine name from the log BEFORE counting the call. Repeat for the other
  engine if time allows. (PASS: the session reports interrupted, and after
  declining/ending the call it resumes or ends cleanly — never a state
  where the UI claims to be listening and nothing is captured.)

### (b) Blocked on a build first

- **#74 (CarPlay Simulator functional pass) — not a phone check at all, and
  not runnable on tomorrow's OTA regardless of build state.** `project.yml:61`
  still has `com.apple.developer.carplay-voice-based-conversation` commented
  out (verified 2026-08-06) — active, it breaks **signed device builds**
  (the restricted entitlement isn't granted). Running this needs a separate
  SIMULATOR-only build with the entitlement uncommented, a CarPlay Simulator
  session on the Mac, and re-commenting it before any device build. Off
  tomorrow's plan entirely; filing Apple's discretionary grant needs no
  phone time either and could happen independently.
- **Nothing else surfaced by tonight's reconciliation is build-blocked.**
  #58 was the suspect item and it checks out merged + regenerated (see the
  note above) — treat it as build-clean.

### Dropped from tomorrow — confirmed dead, annotated in place, not deleted

- **§F1's `#147` row** — MOOT. #238 deleted the notification surface; there
  is no inbox-alert notification left to tap, cold or warm.
- **§F3's `#189` row** — MOOT. Its subject (authorization priming, the
  false-green push panel) no longer exists.
- **§F4's and §F8's `#81` rows** — MOOT. #238's own closure text names this
  as accepted collateral. Confirmed by source grep: zero hits for
  `UNTextInputNotificationAction`, `HERMES_REPLY`, or
  `handleNotificationReply` anywhere in the tree.
- **§F8's `#226` row** — MOOT. Same cause. The one durable fix this item
  produced (`reconcileInFlight` single-flight) already landed and stays;
  nothing left to verify on a phone.
- **This retires the former Sitting 4 entirely** (§F8's only two rows were
  #226 and #81, both dead).

### Not part of tomorrow — needs its own time, not a build blocker

- **#117** — needs sensors switched back on (currently off, deliberately)
  AND a >25-minute induced outage window. Give it a dedicated evening.
- **C2 (#206's row set)** (AMBIGUOUS: its own entry gives no specific check
  beyond "outstanding from the #206 lane" — re-read #206 before scheduling
  it) **and C4** (matched-thermal replication — explicitly "long; only
  worth a dedicated sitting" per its own row).
- **A1/A1b** are listed in Group 8 as runnable IF a second person is
  arranged; if nobody can call, they roll to the next sitting untouched.
- **#21's device-files route-containment check — removed from this queue
  outright, 2026-08-07 (hygiene sweep, OPEN_ITEMS #273).** It was never a
  phone check: it is a server-side confirmation on the relay with no UI
  path, which is precisely what this list flagged AMBIGUOUS about it on
  2026-08-06. Routed to **§G**. Method and reasoning live in the
  out-of-repo security addendum, 2026-08-07 — the row here used to spell
  out a crafted request path, and that is the kind of text #261 moved out
  of the repo.

**Total estimate for Groups 1–8: roughly 4 to 4.5 hours.** This grew from
the ~3–3.5h first cut, honestly, not shaded down — batch-3's addition
(new Group 2's ~20 drawer-checklist items, new Group 7's continuity-fabric
checklist) added roughly an hour on its own. Breakdown: Group 1 ~30 min,
Group 2 ~35–40 min, Group 3 ~15 min, Group 4 ~25 min, Group 5 ~15 min,
Group 6 ~25 min (+ F7d's variable stall), Group 7 ~25–30 min, Group 8
~60–75 min — plus A1/A1b's dependency on someone else's schedule. This is
a full session, not a lunch break — the group boundaries above are natural
pause points if the day doesn't allow it in one sitting.

---

> ### 🗓 SITTING PLAN — the shortest path through this list (written 2026-08-02)
>
> The list is long because it is a queue, not a session. **Three sittings clear
> almost all of it**, and the order matters more than the total:
>
> | # | sitting | what it covers | needs |
> |---|---|---|---|
> | **1** | ✅ **DONE 2026-08-02** — devicectl container pull, corded | **§C5** — `1835BBF9` rescued, 0/10 CONFIRMED; **#200F was already evicted** | see §C5's verdict block |
> | **2** | **The big one — an evening** | **§F5's outage** and everything riding it: **#151** (3 shapes), **#145** (all of A–E(a)), **#180's instance-4 rejudgement**, **#117**. Then §F1's cheap rows (**#133/#143 row count**, **#222** image, **#193**, **#121**, **#122**, **#191**, **#192**) and **§F7a–c** (approvals — no setup) | > 25 min outage window; a build carrying #237–#242 |
> | **3** | **Voice + calls — SCHEDULED TUESDAY 2026-08-04, Shelley confirmed** | **§A1b** (real incoming call), **§A2b** (#221 brain-governs-voice), **§F6** (#129, #58/#179, E1 residual) | someone who will call you ✓ |
>
> | **4** | **⛔ UNCORDED — phone OFF the cable, launched by hand** | **§F8** — **#226** (one banner, not zero and not three) and **#81** (locked-device Reply) | a build with PR #243; **no Xcode session**, log recovered afterwards |
>
> **Sitting 4 is short but cannot share a rig with anything else.** A live Xcode
> launch session never suspends, so every check in §F8 measures the wrong thing
> from the cable — and reads as a PASS while doing it. It is the one sitting where
> the *absence* of instrumentation is the fixture.
>
> **Not in a sitting:** **A2's overnight half** (start before bed, free), the
> **OJAMD counts** (any time you are at that box — two read-only lines), **§F7d/e**
> (host-side `approvals.mode`), and **F3 (fresh install) which deletes the app and
> goes LAST, ever.**
>
> **Sitting 2 is the high-value one** — it closes or advances seven items at once
> because they all need the same fixture. Sitting 1 protects evidence that sitting
> 2 could destroy, which is the only hard ordering on this page.

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
> **✅ DISCHARGED 2026-08-02 — §C5 ran; the whole store (all ten runs) is archived
> off-device at `handoffs/evidence/battery-runs/`. Installs and battery runs no
> longer threaten anything. Kept for the arc: the race was already half-lost —
> #200F's run was evicted before this rule was ever written.**
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
| **§C5** | ✅ **DONE 2026-08-02** | rescued via devicectl container pull; verdict in §C5. The ordering rule above is discharged. |
| **A1** (the top item) | **a second phone, or someone who will call you** | A1 is a real incoming call mid-session. There is no software substitute — the whole point is the OS interrupting us for real. **This is the single prerequisite most likely to end a sitting early.** |
| **A2** | to background the app **overnight** | the system decides when `BGAppRefreshTask` runs; it cannot be forced. Start it before bed on a sitting day, read the log the next morning. |
| **F3** | to **DELETE the app** | ⚠️ **destructive — local sessions and the Keychain stamp go with it.** Export anything you want from Battery Results FIRST. Run F3 **last** in any sitting for this reason. |
| **F5** | a **> 25 minute** induced connector outage | the window IS the check — the original close scored a false PASS on a short one. Do not squeeze this between other checks. |
| **B1 / F6** | the `probe/t27-130-halfduplex` branch **built to the phone** — **but B1 is PARKED, so do not stage it yet** | ~~⛔ §C5 must be exported BEFORE this branch goes anywhere near the phone~~ *(✅ discharged 2026-08-02 — evidence off-device; B1 stays parked regardless).* And B1 is parked by Owen's own instruction — *"leave it parked as a reminder"* — so its blocker was never OTA-vs-corded. **Staging a build for a parked item, onto the phone holding §C5's only evidence, is the wrong move twice over.** It is a separate build from `main`, so it cannot share a sitting with the `main` checks either. |
| **C1–C4** | phone **foregrounded and on power** | backgrounding kills a battery run outright. |
| **⭐ SITTING 2, and most of §F1** | **a build carrying PRs #237–#242** — i.e. `main` at **`578df8c`** or later, **built DEBUG** — a Release build compiles out the battery instruments, Battery Results, AND the Developer screen link (so no verbose-logging toggle); discovered 2026-08-02 when a fresh Release install hid them all | ~~⛔ EXPORT §C5 FIRST~~ *(✅ done 2026-08-02 — evidence off-device, installs are now safe)*. Then: **remote** → `scripts/mac/ota-stage.sh main` on the Mac Mini, install from Safari at `https://owens-mac-mini.tail5663a6.ts.net`; **at the desk** → Xcode bridge `RunProject(tabIdentifier:"windowtab1")`. Both are **upgrade-installs** — same bundle id, app data (and Battery Results) persists. **Checks that NEED this build:** #145's outage rows (Part E(a) shipped in #242), #133/#143's row count (#241), #180's rejudgement (#237). Running them on an older build measures the OLD app and produces a verdict that reads as a pass. |
| **F7d** | **host-side access to turn Hermes YOLO/auto-approve OFF**, and the discipline to restore it after | The other three F7 rows (**F7a–c**, the on-device confirm gate) need **nothing** — run them in any sitting. Only F7d touches the host. It is a **discovery probe, not a pass/fail**: Talaria handles no approval event at all, so the expected outcome is a stalled turn. Bounded by #145 Part A's timeouts now, which is itself worth confirming. |

### Decisions owed by you — no phone, no build, unblock other work

| # | the question | what it unblocks |
|---|---|---|
| **D2** | **Should LAN-hosted backends work at all?** `http://192.168.x` and MagicDNS names are ATS-blocked app-wide today; only the Tailscale CGNAT range is excepted. | If yes, it needs its own measured arm — and note `NSAllowsLocalNetworking` was only ever tested against a **CGNAT** host, never a `192.168.x` one, so do not assume the key does what its name says. If no, we close the ATS thread. |
| ~~**#152**~~ | ~~Pick the pairing-surface label~~ — **WITHDRAWN 2026-08-01. This was not owed; it SHIPPED 2026-07-24.** The row reads **"Pairing & Devices"** in the tree today (`UplinkSettingsScreen.swift:357`, `ConnectHermesHostScreen.swift:38`), merged in **PR #146**. I put it on your plate as an open decision, and repeated it to you verbally — both wrong. If you want a different label it is now a change, not a decision. | Nothing. The device check it left behind is in **§F1**. |
| **#164** | **Close the old UI flake, or formally quarantine it?** | Its own bar is *three consecutive green runs*; we have **one** (2026-08-01, 8/8). I did not close it on your behalf — meeting a bar is not the same as being tired of it. Your call whether the bar still earns its cost. |
| **#170** | **Run #148's discriminator, or close as answered-for-the-world-that-exists?** | Neither shape is reachable on OJAMD — every real job carries a null `model_snapshot`. The discriminator is one read of the Mac's `cron/jobs.json`; I can do it if you want the answer. **→ READ 2026-08-02: the Mac's `jobs.json` exists and holds ZERO jobs — the "one read" discriminator is unrunnable as filed.** Settling it now costs a throwaway job (create → read the written fields → delete) on the Mac's dev gateway. Still cheap, no phone — but it is a create, so it stays your call. |
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

> ## 🔄 REFRESHED 2026-08-02 (evening) — the solo queue emptied a SECOND time.
>
> Six more PRs landed (**#237–#242**), suite **1477 → 1505**, `main` gated green
> after the three-way merge at exactly the predicted count. **The board is again
> waiting on the phone, and it is now waiting harder** — see the four NEW checks
> below.
>
> **Why there is nothing left to pick up solo:** #183's Phase 2 (mutation — the
> only check that PROVES a test works) is gated on your device-pass condition;
> **#188 was DECLINED** under your no-hardening rule, which removed the last
> Phase-5 lane; #223 belongs to the investigation session. What remains in Phase 6
> is verification-shaped (needs the phone) or decisions.
>
> **The one exception, startable any time:** Phase 7's carve-out — a public
> **privacy-policy URL** and the App Store Connect records. Their latency is
> external, so app work can never invalidate them. Ask if you want the draft.
>
> **NEW this evening, all already written into the sections below — do not
> re-derive them:**
> 1. **§F1 — #133/#143's row count.** The honest close for both items; unpair →
>    relaunch → re-pair must add **no** device row. **OJAMD has never been
>    measured** and is where the ×5 actually happened.
> 2. **§F5 — #145 now includes E(a).** A shared 45s deadline caps the whole
>    foreground chain, and any cut is COUNTED — report a non-zero
>    `foregroundActivationsCutShort` as a finding.
> 3. **§F5 — #180's instance-4 rejudgement** rides the same sitting.
> 4. **§F7 — approvals**, the never-exercised path, incl. the discovery of
>    `POST /v1/runs/{id}/approval` on `:8642`.

**Superseded 2026-08-02 — kept for the arc.** *"NOTHING — the solo queue is EMPTY
as of 2026-08-01."* All four lanes ran, and the one remaining candidate is ruled
out (see below). **The next real work needs Owen and the phone, starting with
§C5.**

> ~~⏳ ONE THING IS TIME-SENSITIVE — §C5.~~ **✅ RAN 2026-08-02 — PARTIAL; see
> §C5's verdict. It was indeed time-sensitive: half the evidence was already
> gone.** #216A's re-read landed on a question
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

### C5 · Rescue two battery run records before they are pruned · ✅ **RAN 2026-08-02 — PARTIAL. The race was already half-lost.**

> ## ✅ VERDICT (2026-08-02, corded): `1835BBF9` RESCUED and it CONFIRMS the 0/10. #200F's run was ALREADY EVICTED.
>
> **Method — no share sheet, no app UI, and none was reachable anyway:** the fresh
> corded build turned out to be **Release**, and the entire battery panel including
> Battery Results is `#if DEBUG` — the export surface §C5 assumed did not exist on
> the phone. The records were pulled straight out of the app container instead:
> `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier
> org.aethyrion.talaria27 --source "Library/Application Support/BatteryRuns"`.
> **All TEN surviving runs are archived at `handoffs/evidence/battery-runs/`**
> (local, gitignored) — the whole store is now off-device, not just the named run,
> so no future run or reinstall can touch this evidence. A corded Mac can always
> reach the store this way regardless of build config.
>
> **`1835BBF9` (#214) — the 0/10 is a REAL ZERO.** `call_economy_report`
> (`scripts/classify-battery-run.py`) on the rescued record: the `armed-scopedv2`
> haiku cell logged **zero tool calls across all ten trials** — median=0, max=0,
> empty per-tool Counter. **No silent `readCalendar`. The 0/10 grab count is not a
> text-scoring artifact.** Corroboration inside the same record: the `armed`
> control's haiku grabs 8/10 appear in `toolCalls` as `createReminder`×8 — text
> scoring and the call record agree on both cells. And #216A's soft evidence is now
> hard: the treatment's *"I cannot write a haiku without external tools"* refusals
> came from trials that called **nothing** — an unusable-belt report, not a
> failed-hunt narration.
>
> **#200F's run (2026-07-29) — EVICTED, unrecoverable.** The store held **exactly
> 10 files**, oldest 2026-07-31 19:29Z: the old silent `maxRuns = 10` bound pruned
> it during the 07-31/08-01 lanes, before the bound was raised. **Its
> `armed-scoped` and `armed-createonly` haiku 0/10s stay permanently UNRESOLVED as
> direct evidence** — do not cite them as verified. Closest available inference:
> `armed-createonly`'s belt is identical to `armed-scopedv2`'s (`createReminder` +
> `readCalendar`), which posted a true zero on the same prompt — supportive, not
> probative. This is #219's abstract argument arrived in the concrete, exactly as
> this section predicted: the evidence was destroyed silently and nothing recorded
> that it had existed.
>
> Full analysis recorded in OPEN_ITEMS #216A (resolution block, 2026-08-02).

**The original check, kept for the record:**

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

### C6 · Display Zoom letterbox re-test under beta4 *(added 2026-08-06, from archived #83)*

Set Display Zoom to Larger Text, launch, check for letterboxing; if it
repros, file a NEW item (do not reopen #83). #83 itself is closed as
terminal against a toolchain that no longer exists (Xcode-beta.app /
Xcode-beta3.app were deleted 2026-07-24) — this is a one-line sanity re-test
under beta4, not a reopening. Restore Display Zoom to Default afterward.

---

## D · Spotted, never chased

### D1 · Cold-route timeouts at launch · ✅ **DIAGNOSED 2026-08-02 — the cold-route theory is DEAD; it is duplicate catalog fetches starving on the connector leg**

> ## ✅ VERDICT (2026-08-02, corded cold launch, verbose on — the deliberate launch this item asked for)
>
> **Observed in one launch (16:20:13 local):** `push/register` to `ojamd:8000`
> **succeeded at +0.2s**, a command-catalog fetch **succeeded at +1.8s**
> (`[ChatStore] contextWindow ← 128000 [command catalog]`), and **two more**
> `GET /v1/commands` tasks to the same host:port died −1001 at +5.3s. A cold
> route cannot produce that split — the route was demonstrably warm at +0.2s.
>
> **Mechanism, from source on both ends:**
> 1. **Server side:** `/v1/commands` is not relay-local — it is
>    `send_connector_rpc(method="commands.catalog", timeout_seconds=10.0)`
>    (`relay/app/main.py:1181`). Phone → relay → connector WS → host. The relay's
>    graceful empty-catalog fallback only fires at ITS 10s timeout.
> 2. **App side:** `refreshCommandCatalog` rides the **5s bootstrap probe client**
>    by design (#136), so the app hangs up at 5s — **under** the relay's 10s —
>    and sees −1001 instead of the designed fallback.
> 3. **The duplication:** several launch-path callers invoke it with
>    `force: true` (`AppContainer.swift:1363,1558,2575`) plus the online
>    transition (`:1234`); `force` bypasses the 60s throttle, and
>    `lastCommandCatalogRefreshAt` is stamped only on success (`:2379`). There is
>    **no single-flight guard**, so a cold launch fires ~3 concurrent fetches.
>    One wins; the extras starve on the connector leg (concurrent connector RPCs
>    stalling is #54's territory) and burn their 5s.
>
> **User-visible harm: none found — the catalog ARRIVED.** The −1001s are noise
> from requests the app never needed to make. **Candidate app-side fix (fits the
> no-hardening rule — zero relay change): single-flight `refreshCommandCatalog`**
> so concurrent callers await one in-flight fetch. **FILED 2026-08-02 as instance 1
> of the #227 umbrella** (no single-flight on launch/foreground fan-out) — the same
> sitting found two more: `registerPushToken` ×2 at launch, and #226's reconcile leg,
> which is the one that is user-visible.
>
> **Residual, honestly stated:** the original sighting also had `:8765/models`
> timing out; today's launch showed **no shim timeout**, so that half is
> unreproduced and undiagnosed. If it recurs, note whether the shim was cold.

### D2 · LAN-hosted backends are ATS-blocked · **[DECISION FIRST, THEN TEST]**
`http://192.168.x` and MagicDNS names have **no** ATS exception — only the
Tailscale CGNAT range `100.64.0.0/10` does. This explains the
`listSessions: 'Mac Mini' unreachable` line seen on 2026-08-01.

**Live confirmation 2026-08-02 (corded console, PRE-airplane, 16:34:49 and again
16:46:34):** `listSessions: 'Mac Mini' unreachable — The resource could not be
loaded because the App Transport Security policy requires the use of a secure
connection.` The MagicDNS-named profile is ATS-blocked in production, exactly as
this section predicted — no longer an inference from the exception table.

**Owen decides whether LAN backends should work at all.** If yes, it needs its
own measured arm in #166b's harness (probes inside the app test host, so
`URLSession` obeys the real plist — `curl` does not exercise ATS). Note
`NSAllowsLocalNetworking` was tested only against a **CGNAT** host and has never
been tried against a `192.168.x` one. **That is the untried arm** — do not assume
the key does what its name suggests, because for CGNAT it did not.

---

### D3 · Realtime voice start failed on a stale WebRTC state, fell back cleanly · **[SPOTTED 2026-08-02 — file, don't chase mid-sitting]**

Console, corded, 16:41:02–06: `voice session starting on engine realtime
(relayPaired=true)` → **`Realtime start failed (Failed to set remote answer
sdp: Called in wrong state: closed) — falling back to local voice for this
session`** → `active voice engine → native`. The peer connection was already
CLOSED when the answer SDP arrived — smells like a stale/reused
`RTCPeerConnection` from a prior session teardown. The triggering gesture was
an accidental-but-real user tap (Owen, confirmed same sitting), so this is an
ordinary production path, not a harness artifact. **The fallback worked
exactly as designed** (the user got a working voice session), so this is a
degraded-path finding, not an outage: the paid realtime path silently became
native for that session. Worth one look at `LiveVoiceSessionService`'s peer
connection lifecycle before the §F6 voice sitting; also note for #221's
"should realtime be visibly indicated" question — a silent fallback is exactly
the case an indicator would surface.

Incidental same-window evidence, recorded so they aren't re-derived: **#145
Part D observed live** (`handleAppDidBecomeActive: superseding an in-flight
activation`), and **#192's router instruments** fired on a real brain flip
(`brain preference → hermes [pick+default]`, `activeBrain on-device → hermes`,
`run finished on hermes [stream-ended] — routing lock released`).

### D4 · Run-completion notifications: the #38 background watch is structurally a NO-OP for home-screen backgrounding · **[FOUND 2026-08-02 — four live attempts + source, mechanism complete. FILED as OPEN_ITEMS #226; leg (c) is instance 3 of the #227 umbrella]**

**User-visible truth today: background the app mid-run and you either get NOTHING
(short run) or THREE identical banners at foreground (long run). Never one
banner at the right time.** Four attempts this sitting, two with full console
coverage, all four explained without residue:

| attempt | run length vs background grace | what Owen saw |
|---|---|---|
| 1 (17:1x) | outlived it (or stream dropped) | nothing while waiting → **×3 on foreground** |
| 2 (17:2x, 5-min wait, Notification Center checked: empty) | outlived it | nothing → **×3 on foreground** |
| 3 (17:31) | finished in-process at +49s | **nothing, ever** |
| 4 (17:34) | finished in-process at +9s | **nothing, ever** |

**Mechanism, from source:**
1. `PendingRun` is created **only on `.interrupted`** (stream drop), never during
   healthy streaming (`ChatStore.swift:716`).
2. The scene-phase hook `watchPendingRunIfNeeded()` (`AppEntry.swift:311` →
   `AppContainer.swift:2178`) therefore **silently no-ops at the home-screen
   transition** — the stream is still healthy inside iOS's background grace, so
   there is no pending run to watch. The hook's own comment ("walking away
   mid-run: hand the completion notify off to the relay") describes exactly the
   case its guard excludes.
3. Short run ⇒ finishes in-process during grace ⇒ no orphan, no watch, **no
   notification at all** — the reply silently waits.
4. Long run ⇒ stream dies at suspension, but `.interrupted` → `onRunDetached` →
   `postPushWatch` only executes **on foreground** ⇒ the watch arms against an
   already-completed run ⇒ relay **insta-pushes by design**, once per active
   `push_registrations` row (baseline: this token likely holds 2 — recount will
   confirm), PLUS the reconcile posts the local notify while the activation
   chain is still `.inactive` (`ChatStore.swift:1743`), each with a **unique
   UUID identifier** (`LocalNotificationService.swift:58`) so nothing coalesces
   ⇒ **×3 identical banners over the app you just opened.**

**Fix shape (all app-side, zero relay change):** (a) arm the watch on the
background transition whenever a **stream is in flight**, not only when a
PendingRun exists — the relay watcher is positional, and the code comment
already blesses insta-fire as correct; (b) stable notification identifier
(`hermes.run.completed.<runId>`) so duplicates replace instead of stack;
(c) single-flight the reconcile path — it is the third no-single-flight sibling
found TODAY (D1's catalog fetches, `registerPushToken` ×2 at this evening's
launch — 17:29:45.478/.496 — and this).

**Attempt 5 (the instrumented `sleep 150` run, 18:43) exposed an OBSERVER
EFFECT instead:** send 18:43:05, backgrounded 18:43:08, and `run finished
[stream-ended]` at **18:45:50 — the stream survived 2m42s of home-screen
backgrounding.** A process with a live Xcode launch session (corded, on power)
**never suspends**, so the `.interrupted` branch is unreachable on the
instrumented rig and "no banner" is the correct outcome for ANY run length.
This does not weaken the mechanism — it explains the attempt table's split:
attempts 1–2 (×3 banners) ran under the EXPIRED first launch session, i.e.
normal suspension; every live-session attempt (3–5) rode a process that never
sleeps. **The ×3 branch cannot be instrumented with the corded console at
all.**

**Still owed, and how to get it honestly:** (1) the ×N decomposition arrives
free with the #133/#143 OJAMD recount (N should equal this token's active
`push_registrations` rows + 1 local); (2) one UNINSTRUMENTED long run — launch
the app by hand, not via Xcode, phone off the cable — settles the full chain;
Console.app or a sysdiagnose can recover the log after the fact. (3) **#81
(§F4) must be run uncorded and un-attached** for the same reason — a
lock-mid-stream check on the kept-alive rig would measure nothing real.

### D5 · THE 64-CALL SPIRAL — `searchConversations`, in production, uninstrumented · **[FOUND 2026-08-02 — the worst over-serving instance ever recorded on this project. FILED as OPEN_ITEMS #225. ✅ BOUND BUILT 2026-08-02 — re-run bars in §F1]**

> **✅ THE CAP IS BUILT (per-turn 12, same-tool 4) — but the bars that decide whether
> it WORKED are behavioural and live in §F1's `#225` row.** The suite can only prove
> the cap counts; it cannot prove the model speaks honestly when told "no more tools",
> and **capping the tools is exactly the condition that could turn a silent spiral into
> a fabrication (#199).** Bars were pre-registered in OPEN_ITEMS #225 before the fix
> lane ran.

**Prompt: "what's the weather gonna be in Gulfport tomorrow." Config: on-device
brain, STANDALONE (unpaired mid-#133/#143), hand-launched — no Xcode, no
harness, no battery arming. Production, exactly as a user would hit it.
Result: SIXTY-FOUR tool calls**, observed live at 43-and-growing ("as it goes
through my conversations"), final count 64 from the transcript chips.

**The two structural facts that made it:**
1. **The belt HAS `currentWeather`** (`DeviceReadTools.swift:253`) — but its
   contract is *"live weather conditions and TODAY'S forecast."* "Tomorrow" is
   unmeetable by any tool on the belt.
2. The unmet demand displaced into **`searchConversations`**
   (`DeviceMediaTools.swift:257`) — hunting the user's own chat history for
   weather. This is #216's substitution mechanism verbatim: narrowing showed
   pressure MOVES to whatever remains; here the pressure had a correctly-armed
   belt and no cap, so it moved 60+ times.

**Why this matters beyond the number:** the #200-series named "over-serving on
turns it CORRECTLY arms (tool chaining, the `lookupContact` spiral)" as the
real remaining work — batteries topped out around 10 same-tool calls per trial.
**This is that residual in production at 6× the battery worst case, with
nothing in the loop that bounds it.** Filed as a finding; candidate directions
(not built, not decided): a per-turn tool-call budget in `LocalChatBackend`;
extending the weather tool to WeatherKit's daily forecast (kills this
particular unmeetable demand); loop-dampening on repeated same-tool calls.
Needs an OPEN_ITEMS number — flagged to Owen this sitting.

**The full anatomy, from the transcript chips (screenshots taken 19:11):**
call 1 `currentLocation`, **call 2 `currentWeather Gulfport` — the RIGHT call,
made immediately.** The spiral began AFTER the right tool answered with
today-only data: `searchConversations Gulfport` ×2 → `readCalendar "next 3
days"` → then queries drawn from the MEMORY INJECTION, not the question —
`Shelley`, `work`, `Memorial Hospital`, `Shelley work`, `Talaria` — then ~dozens
of degenerating permutations of *"Talaria tasks/debugging/issue list review
audit notes"*: a classic small-model repetition loop riding the tool channel,
the whole 64 inside ~90 seconds (19:06–19:07). So the failure is NOT
tool-selection — it is **"the right tool's answer did not satisfy the demand,
and instead of reporting the limit, the model hunted, then degenerated."**
Sharpens the fix candidates: a same-tool repeat damper + per-turn budget would
have cut this at ~5 calls; a forecast-capable weather tool would have removed
the trigger. Note the searches stayed on-device (searchConversations is local)
— no privacy egress, but memory-context terms leaking into hunt queries is its
own smell. **CORRECTION that raises severity: 64 is not where it stopped — it
is where OWEN stopped it.** The turn never produced any reply text and was
still calling `searchConversations` when killed. **There is no evidence of ANY
bound on the chain** — the honest statement is "unbounded until user
intervention." (The #199 fabrication question is moot for this run — no text
was ever emitted.) One genuinely good observation: the composer's stop button
cleanly terminated a 64-call spiral mid-loop — cancellation works under the
worst load we have ever put on it.

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
| **#225** ⭐ | **Re-run the exact spiral prompt on a build with the cap:** *"what's the weather gonna be in Gulfport tomorrow"* — **on-device brain, STANDALONE (unpaired), hand-launched** (no Xcode, no battery arming). Count the tool chips. | **FOUR bars, all required — pre-registered in #225 before the fix.** **B1 bounded:** ≤ **12** tool calls and the turn ends on its own *(before: 64 and still climbing when killed)*. **B2 it SPEAKS:** non-empty reply text *(before: none, ever — this is the bar that matters most, a cap that yields silence is not a fix)*. **B3 HONEST:** says it cannot get tomorrow's forecast rather than inventing one — **#199's fabrication risk is live here and was untestable before precisely because no text was emitted**. **B4 no collateral:** a normal multi-tool turn ("remind me to call Shelley tomorrow at 4") still completes; if this fails the budget is too tight and the NUMBER is falsified, not the mechanism |

> **UPDATE 2026-08-06 — this is not actually a first-time check; annotating
> rather than rewriting the row above.** It already ran the night it was
> filed: 2026-08-02's dedicated "Lane 1" device run (OPEN_ITEMS #225) scored
> L1-A/C/D/E PASS and L1-B FAIL on one refusal-grind trial, and produced two
> follow-on findings — **#230** (WeatherKit daily forecast, closes the
> "tomorrow" trigger) and **#232** (the refusal grind) — both BUILT and
> DEVICE-CONFIRMED fixed same week (#232: "ZERO refusals on the control
> prompt (was 57), turn 5.9s (was minutes)," 2026-08-03 night). Tomorrow's
> run against this row's original 4-bar fixture is therefore a
> **confirmation of a very likely-already-fixed defect**, kept in the queue
> only because the original fixture itself hasn't been re-run since the
> compound fix landed. See "Consolidated run 2026-08-07," Group 4 (renumbered
> from Group 3 by the 2026-08-06 batch-3 addendum).
| **#121** | Resume a session that has prior reasoning | thinking panes restore from stored messages. **✅ PASS 2026-08-02** — two resumed sessions verified (one viewed under the on-device brain, one Hermes/cron): expanded AND collapsed reasoning panes restored from stored messages, and the live pane streams on a fresh turn |
| **#122** | Open a session with known usage | spend row shows real numbers; `$0.00` only where genuinely unknown. **✅ PASS 2026-08-02** — Settings → Sessions rows show real `IN/OUT/CALLS` figures including host-run cron sessions (so the wire carries usage, not just phone-side receipts); a brand-new session's line materialized in 14s (`IN 7.4K · OUT 84 · 1 CALLS`); no `$0.00` placeholder anywhere — absent data hides the line by design. Console corroborates: `run finished on hermes [stream-ended]` |
| **#191** | Airplane mode ON with **on-device** active | header title + model pill name the ACTIVE brain, not the stale Hermes session. **✅ PASS 2026-08-02** — verified in BOTH an existing Hermes session and a fresh chat: header + pill read ON-DEVICE in airplane mode. Console: the flip was user-initiated (`activeBrain hermes → on-device initiator=refresh/override`), and the offline errors are honest (`listSessions: 'OJAMD' unreachable — Internet offline`) |
| **#192** | On-device active → ask for a 500-word summary | app does **not** silently switch itself away from on-device. **✅ PASS 2026-08-02** — 500-word Brazil summary generated fully on-device in airplane mode (IN 505 · OUT 587). Console: `sendStreaming routed to on-device` → `run finished on on-device [stream-ended] — routing lock released (#192)`, no brain flip between. Bonus: the composition prompt was `turn routed toolless` — production routing behaving per #215 |
| **#193** | Trigger any destructive-action confirmation | the **Cancel** button renders (iOS 27 regression). **✅ PASS 2026-08-02** — fixture note: sessions have NO delete (archive/pin only, by design), so the confirmation exercised was Servers → Mac Mini profile → Delete: the sheet rendered "Delete Mac Mini" AND **Cancel**, which Owen confirms did not render before the fix |
| **#147** | Inbox-alert notification: **cold** tap, then warm tap | no crash on either. **Cold is the mis-verified case** — a merge commit plus one warm observation is what closed this wrongly last time. **⚠️ PARTIAL 2026-08-02, BLOCKED by a NEW delivery finding.** What ran: three notification taps with the app ACTIVE — no crash (weaker than the specced warm tap, which needs a tap from the backgrounded state). **What blocked it, twice-reproduced: run-completed notifications did NOT present while the app was backgrounded (1-min wait, then a 5-min wait), then presented as THREE duplicates the moment the app foregrounded — both attempts.** Neither specced tap is runnable until delivery works: a backgrounded phone shows nothing to tap. The ×3 rhymes with the OJAMD baseline's **2 APNs tokens with >1 active registration** (relay sends once per active row) — the post-re-pair recount will test that directly. Console coverage gap: the Xcode capture expired at ~17:07, before the push window; evidence is Owen's direct observation ×2. Cold tap STILL OWED once delivery is understood |

> **⚰️ MOOT 2026-08-06 — annotating, not deleting.** OPEN_ITEMS #147 is now
> `⚰️ MOOT` (archived) as of 2026-08-04: **#238 deleted the entire
> notification surface** — "the `UNUserNotificationCenter` delegate this
> crash lived in no longer exists, and notifications, if ever reintroduced,
> are in-app surfaces only (permanent cut)." Confirmed by source grep
> 2026-08-06: zero hits for `UNUserNotificationCenter` anywhere in the tree.
> There is no inbox-alert notification left to tap, cold or warm. Drop this
> row from any future sitting.
| **#146** | Diagnostics push row after a healthy launch | **✅ PASS 2026-08-02** — row reads **`Relay Registered`**, not stuck on `TOKEN HELD · AWAITING RELAY`. Note: seeing the push arrive ×4 does **not** falsify this — that count is #143. *(Corrected 2026-08-02: #143 is **app-side identity churn**, not "relay-side". Measured 99 device rows / 99 distinct installation ids; the relay upserts correctly per identity and the app minted them. Root fixed in #133 — so on a build carrying that fix the multiplicity should not GROW, though pre-existing OJAMD rows still fan out until deactivated.)* |
| **#133/#143** ⭐ | **The row-count check that closes both.** On a build with the durable-identity fix: note the relay's device-row count, then **unpair → force-quit → relaunch → re-pair**, and count again. | **NO new device row**, and no new `push_registrations` row for the same APNs token. This is the honest check — #144's lesson is that a suite proves nothing here, only the row count does. Read it with:<br>`SELECT COUNT(*), COUNT(DISTINCT installation_id) FROM devices;`<br>**Before the fix those two numbers were equal (99/99) — that equality IS the defect.** After it, re-pairing must leave both unchanged. **Do this on OJAMD if at all possible** — it is where the ×5 was actually seen and it has never been measured. **→ OJAMD BASELINE MEASURED 2026-08-02 (read-only sqlite, pre-re-pair): devices total=22, distinct installation_id=22, active=22; push_registrations 15 total / 12 active; 2 APNs tokens currently have >1 active registration.** Two notes: (1) the 22 is news — nothing like the 99-row fan-out is present today (all rows active, all distinct; whether the DB was recreated or rows were deleted is unexplained and deliberately not chased here); (2) the 2 duplicate active tokens predate the check — after the re-pair leg the bar is devices still 22/22/22, push_registrations not grown, and dup count not increased. **MID-POINT MEASURED 2026-08-02 (after Disconnect + relaunch, BEFORE re-pair): all numbers IDENTICAL to baseline — Disconnect is purely client-side; the relay's devices and push_registrations rows are untouched.** Two consequences: the honest test is now entirely about what RE-PAIR does, and **an unpaired phone stays push-registered on the relay** — hygiene note, relevant to D4's push arithmetic. Bonus datum: exactly one device (`f9b7678c…`) holds **2 active push registrations** — if that is this phone, D4's ×3 = 2 remote + 1 local decomposition holds arithmetically. **✅ FINAL VERDICT 2026-08-03: PASS — with a one-time, by-design migration step that a single-cycle read would have mis-scored as FAIL.** Four measurements: baseline 22/22/22 · 15/12 → mid-point (unpaired) IDENTICAL → **after re-pair #1: 23/23/23 · 16/13 (+1 row — looks like the bug!)** → **after re-pair #2: STILL 23/23/23 · 16/13, same row `f3e2c806`/install `913f0656` updated in place.** The +1 was the legacy→durable convergence: the old row's id (`c718cc64`, created 07-23) predates PR #241, so the durable id was fresh-to-relay tonight; cycle 2 proved it STICKS — no mint, clean upsert. The churn equality (every pairing = new id = new row) is broken. **Residuals, filed not fixed: (1) the ×5 IS IN THE TABLE** — token `0aa87bdf…` has **5 active registrations**, token `df04a6a7…` (this phone's, almost certainly) has **3 active** — the relay fans out per row, so the phone's next long-run D4 repro predicts **×4** banners (3 remote + 1 local); **(2) the #144-shape deactivation chore — ✅ EXECUTED same night, Owen approved:** OJAMD now holds **2 active devices + 2 active registrations, zero duplicate tokens** (21 devices + 11 registrations deactivated, never deleted; backup `hermes_mobile.backup-20260803.db` + rollback json beside the DB). The Mac relay's 97 harness device rows went the same way (#144 now fully closed). **D4's ×N arithmetic drops to 1 remote + 1 local = 2 predicted** until D4's app-side fix lands |
| **#112** | Settings → toggle system appearance while foregrounded | Comic Book re-skins villain↔funnies **without relaunch**. **✅ PASS 2026-08-02** — system dark→light toggled while foregrounded; the app re-skinned live, no relaunch |
| **#184/#185** | Exercise all three ChatStore teardown paths; send two attachments with the **same filename** | teardown clears consistently; each attachment resolves to its OWN local file. Sim-only today |
| **#186** | Grant narrow permissions and use the tools: pick **"Add Events Only"** from the calendar sheet, then ask to create an event; grant **limited contacts** (Contact Access Picker), then look up a contact on a LATER launch; with the add-only grant, ask a calendar READ question | Three bars, moved here 2026-08-04 from the entry (one queue): (1) add-only grant → event creation succeeds on the FIRST attempt and every one after; (2) limited contacts → lookup works on the second launch and after; (3) add-only + read question → the reply names the add-only grant and says how to widen it, not "enable it in Settings." Fixes verified on main 2026-08-04 (grep); sim-untestable — framework permission stores |
| **#151** | Settings → Hermes Host → **Test Connection** against the LIVE host | verdict appears **within ~5s** with a latency figure. Shape 1 of 3 — the other two are in **§F5**. Pre-#146 this button was silent and, on a black-holed host, would have hung **five minutes** (the shared client stamps `timeoutInterval = 300`). **✅ PASS 2026-08-02 (shape 1 of 3)** — verdict with latency figure, **29ms**, ojamd:8642 answered. Shapes 2–3 stay in §F5 |
| **#152** | Settings → Hermes Host → **"Pairing & Devices"** → reach Revoke | the renamed row lands on the revoke/disconnect surface, and **Pair New Device (QR)** is present so the screen is not destructive-only. Sim-verified 8/8 already; this is the device leg. **✅ PASS 2026-08-02** — lands on Pairing & Devices, **Pair New Device (QR) on top**, revoke host + disconnect below. Device leg done; #152 is fully closed |
| **#222** | **On-device brain**, attach an image, then ask something OCR **cannot** answer from a list of strings — *"who posted this?"*, *"is this the Safe Harbor group?"*, or anything about layout/colour/what is depicted | **Either answer is informative.** A correct answer ⇒ the model genuinely sees the image and #222's premise falls. A wrong/hedged answer, or a `readImageText` chip firing and it reasoning only over extracted text, ⇒ the transcript really is text-only and the SDK's `ImageAttachment` is an unused capability. **Works in any state — Owen already ran the OCR half on-device in airplane mode.** Do NOT re-run "what's this say" — that already passed and answers the wrong question. **✅ ANSWERED 2026-08-02 — the premise HOLDS: the transcript is text-only and `ImageAttachment` is an unused capability.** Fixture: Facebook post screenshot (Safe Harbor group), "Who posted this?", airplane mode, on-device. A `READIMAGETEXT` chip fired and the reply said outright *"I can't see the image itself, but the text in it mentions 'Owen Jones'…"* — right answer, wrong faculty: the byline happened to be in the OCR text. Console nails it: the router KNEW (`turn routed armed ctx=none img=true`, 15 tools registered) and the model still only got text. Honesty note: the limitation was disclosed, not papered over — no #199 shape |
| **#262-E** ⭐ *(added 2026-08-06)* | Fast-model artifact turn: prompt the agent to write a file mid-turn, watch the reply stream. | Bar text from OPEN_ITEMS #262: "the chip appears under the write_file card and DOES NOT MOVE while text streams beneath; tappable mid-turn; after relaunch/history reload the placement persists (anchor is persisted with the message)." Bars 262-A/B/C/D already MET in-suite + gate; **PR #277 merged, this is the device leg (262-E), rides the first OTA after merge — tomorrow's build is that OTA.** |
| **#78** *(added 2026-08-06)* | Long-press each bubble type (user/Hermes/voice-transcript); Copy/Share/Select Text; Regenerate a MID-history reply; Edit & Resend with and without an attachment; confirm no menu on a streaming bubble. | **Source: OPEN_ITEMS #78's own device checklist**, never previously carried into this file. PASS: all actions work per bubble type; Regenerate truncates from the correct turn; Edit & Resend restores attachments; nothing history-mutating offered mid-stream. Merged (PR #52, confirmed on main); no new files, no xcodegen owed. |
| **#80** ⚰️ **MOOT 2026-08-09 — DO NOT RUN** *(added 2026-08-06, revised, now retired)* | ~~Ask Hermes to create an inbox item, then pull-to-refresh/reopen Inbox; approve it; ask Hermes to read back the verdict.~~ | **UNRUNNABLE, not merely stale.** OPEN_ITEMS #80 closed 2026-08-09 (superseded by #251 Slice 2A). The first leg needs an agent-callable PRODUCER tool; the talaria plugin registers exactly one tool, `talaria_phone_query`, and it is a PULL (`tools.py:29, 146-157`). `hermes talaria send` is a CLI subcommand (`admin.py:21, 93-95`) — Owen at a host shell, not an agent mid-turn. The verdict-readback leg has **no successor at all**. Inbox still works via `TalariaPlatformInboxService`; its device coverage rides #251's own 2A bars. *(Verified on the Mac install; OJAMD's plugin path is a separate question — #149's close-out records it does not exist there.)* |
| **#21 (OJAMD side)** *(added 2026-08-06)* | Ask the OJAMD-backed agent to write a fresh file, tap the chip. | **Source: OPEN_ITEMS #21**, "Valid OJAMD retest: ask OJAMD's agent to WRITE a fresh file... then tap the chip." PASS: preview + ShareLink, matching the Mac-side PASS already recorded 2026-07-20 (the OJAMD side has never been measured). See §F9 for the Mac-side re-confirm. |
| **#21 (route containment)** *(added 2026-08-06; ~~queued here~~ → **routed to §G 2026-08-07**, hygiene sweep #273)* | **NOT a phone check — do not carry this into a sitting.** Server-side confirmation that the device-files route refuses to serve anything outside its configured directory. | **Source: OPEN_ITEMS #21**, "One relay-side check: confirm the device-files route rejects traversal." PASS: refused, not served. Method and reasoning: **out-of-repo security addendum, 2026-08-07**. |
| **#21 (noise, passive)** *(added 2026-08-06)* | No setup — over the course of this session, note whether any ordinary turn that merely *mentions* a MobileDL path grows an unwanted attachment bubble. | **Source: OPEN_ITEMS #21**, "announcement-scan noise... if it grates, narrowing to write-shaped tools is a small follow-up." Record either outcome — an eyeball finding, not strictly pass/fail. |
| **#75** *(added 2026-08-06)* | Chat header at default width, both brains (HERMES / ON-DEVICE), a long model name (e.g. `DEEPSEEK-V4-...`), and a Dynamic Type sweep (Settings → Accessibility → Display & Text Size). | **Source: OPEN_ITEMS #75's own acceptance pass**, never previously carried into this file. PASS: wordmark/status/model chip stay single-line, scale-then-truncate at every size; brain pill never resizes out of shape. Merged (PR #43); no new files, no xcodegen owed. Settings-dependent — batch with the Display Zoom re-test below. |

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

> **⚰️ MOOT 2026-08-06 — annotating, not deleting.** #238 (closed 2026-08-03)
> named "the push-token pipeline (#189)" explicitly in its removal scope.
> `UNAuthorizationStatus` is no longer read anywhere in the app; there is no
> authorization prompt left to observe and no push panel left to read.
> Confirmed by source grep 2026-08-06 (zero hits for `aps-environment`,
> `remote-notification`, `UNUserNotificationCenter`). §F3 has nothing left
> to run — its only other row, #137, was already "not runnable as filed."
| **#137** | ⚠️ **NOT RUNNABLE AS FILED — needs a rewritten check first.** The 2026-07-25 pass scored UNRUNNABLE, and the spec's "revoke/disconnect FIRST" setup is actively wrong: disconnect no longer produces a re-migratable device and neither does deleting the app. **Do not attempt until someone writes a sequence that can actually reach the un-stamped state.** Queued as a WRITING task, not a device task | — |

### F4 · LOCKED DEVICE

| # | check | pass |
|---|---|---|
| **#81** | Let a run finish while the phone is locked | push carries **Reply**; long-press → Reply → headless post lands; the NEXT push also carries Reply. **⛔ MUST BE UNCORDED — see §F8**, which is where this runs; a live Xcode session never suspends, so a kept-alive rig measures nothing real here |

> **⚰️ MOOT 2026-08-06 — annotating, not deleting.** #238's closure text
> (2026-08-03) names this explicitly as accepted collateral: *"Confirmed
> collateral, Owen accepted explicitly: reply-from-the-lock-screen (#47)
> and its failure banner."* Confirmed by source grep 2026-08-06: zero hits
> for `UNTextInputNotificationAction`, `HERMES_REPLY`, or
> `handleNotificationReply` anywhere in the tree. There is no push, no
> Reply action, and nothing to long-press. Drop this row from any future
> sitting — see the matching annotation on the §F8 copy below.

### F5 · INDUCED OUTAGE (longest — run last, or on its own)

| # | check | pass |
|---|---|---|
| **#117** | Induce a connector outage and hold it **> 25 minutes** | drains back off and STAY backed off; outage rate < 50% of healthy. **The window is the check** — the original close scored a false PASS on a short window, and the 27-minute run showed decay. **STATE NOTE 2026-08-02: unrunnable with sensors off, and sensors are OFF on the phone DELIBERATELY** (Owen: turned off a while back to verify the app functions without them — a test state, not neglect; "I can turn them on whenever"). So #117 needs its own evening: opt sensor streaming back in → stage the connector outage on OJAMD (authorization on record above) → >25-min window. Not attempted this sitting rather than run wrong |
| **#151** | Test Connection against a **STOPPED** host (gateway down, port closed) | **REFUSED**, fast — not OFFLINE, not a spinner. Shape 2 of 3. **✅ PASS 2026-08-02** — `http://100.79.222.100:8643` (dead port, firewall off): REFUSED, fast |
| **#151** | Test Connection against a **BLACK-HOLED** host (packets dropped, e.g. an offline tailnet IP) | **NO ANSWER** at **~5s**. Shape 3 of 3, and the one that matters most — this is the case that used to hang for five minutes. **Cheapest setup on the board: point the base URL at an offline tailnet IP; no service needs stopping**. **✅ PASS 2026-08-02** — `http://100.69.76.52:8642`: NO ANSWER at ~5s. **All three shapes now verified on device — #151 is fully CLOSED** |
| **#145** ⭐ | **RIDES #151's BLACK-HOLE FIXTURE — same setup, do them together.** With the base URL pointed at an offline tailnet IP: background the app, then **foreground it**. Then point the URL back at the live host and foreground again. | **(1)** the app stays **responsive** while blocked — you can scroll, open Settings, switch brains. **(2)** the visible state (widget/Live Activity) reflects last-known-good **immediately**, not after minutes. **(3)** when the URL is restored it **recovers on its own — NO phone restart.** ← the whole item. **✅ PASS 2026-08-02, CLEAN — the "expect CLEAN, not merely better" bar was met.** (1) fully navigable throughout, Owen: "no issues getting around in the app in this state"; (2) models stayed loaded (last-known-good), gateway badge honestly OFFLINE, shim honestly online (its URL was never black-holed); (3) restore → foreground → **self-recovery with no restart**: Part D superseded the stale activation, readiness probe flipped voice back to realtime, journal hop re-primed a fresh session (47k condensed tokens), and the **failed send's RETRY delivered** (`run finished on hermes` 20:13:53). **Part A live-proof included:** a send while black-holed showed the working/stop affordance, then died at **21s** (interactive bound) with a retry offered — console `sendStreaming` 20:11:45 → `stream-ended` 20:12:06. **E(a): zero `foregroundActivationsCutShort` the whole window.** Curiosity filed, not chased: two one-off ATS-block lines against IP-URL profiles mid-outage (20:08:50 'OJAMD', 20:13:02 'Mac Mini' — the latter is D2's known MagicDNS case) |

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
> **Fixture endpoints VERIFIED 2026-08-02, ready to paste:**
> - **BLACK HOLE (shape 3, and #145's fixture):** `http://100.69.76.52:8642` —
>   oj-5050, offline on the tailnet >1 day, ping 100% loss from the Mac Mini.
>   (Backup: `100.124.33.64`, ipad153, also offline.)
> - **REFUSED (shape 2):** `http://100.79.222.100:8643` — the Mac Mini, whose
>   firewall is confirmed OFF (no stealth drop) and port 8643 has no listener,
>   so it RSTs instead of dropping. **No service needs stopping for either
>   shape.** Do not use a dead OJAMD port for REFUSED — #136: Windows Firewall
>   silently DROPS there, which is the other shape.
> - OJAMD services at fixture time: relay :8000 ok, gateway :8642 ok (0.19.1),
>   shim :8765 answering. All three up, so "restore the URL" recovers against a
>   genuinely healthy host.
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
> **All four parts PLUS E(a) are BUILT (PRs #233–#235 + the E(a) lane): expect
> CLEAN, not merely better.** E(a) adds ONE shared deadline around the whole
> foreground chain (45s), so even a degraded-but-answering host cannot hold an
> activation indefinitely. **If the app is ever cut short during this check it
> is recorded, not silent** — `foregroundActivationsCutShort` counts it, and a
> non-zero value here is a real finding worth reporting.
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
> **✅ INSTANCE 4 CLOSED 2026-08-02 — Owen's verdict, delivered mid-outage on the
> live fixture:** *"Now that I see the attempt to send, yes, I think that's
> enough."* The deciding observation was the send path itself — working
> affordance → honest 21s timeout → retry — on top of the connection test and
> the server-card badge. No proactive app-wide disconnected signal wanted.
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
| **#82 residual** *(added 2026-08-06)* | If #129 above named an engine (via `voice session starting on engine …`) that is NOT the one #82's 2026-07-16 device confirm used, repeat #129 once more forcing the OTHER engine (airplane mode pins native; paired+healthy pins realtime) | **Source: OPEN_ITEMS #82's own 2026-08-01 flag from the #220 audit** — "This item's device verdict was recorded while NOTHING logged which voice engine was active... the other engine's half is unverified." The engine-naming log line (`VoiceEngineRouter.swift:196`) shipped AFTER #82's 2026-07-16 confirm, with #221 — so which engine that confirm actually exercised is still unknown. PASS: no crash, no `@SpeechOutputService#2` spam mid-session, mic works after — on whichever engine turns out to be the unverified one |

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
| **F7a** | **On-device brain**, ask for a reminder/calendar create. **Tap Cancel, not Approve.** | The decline path. Does the model relay the decline honestly, or fabricate a completed action (#199's shape)? Does the chat stay usable, or enter #176's absorbing state? **⚠️ PARTIAL-PASS 2026-08-02** ("Play black flag at 8:15pm" fixture): card rendered with editable TITLE/DUE/LIST + Cancel/Approve; Cancel worked; **no fabricated completion** — but the model narrated the decline as *"there was an issue creating the reminder"* and offered to retry. `ToolConfirmationCenter` hands it a literal "user declined" result, so this is the model mis-attributing a deliberate decline to a technical failure — softer than #199's shape, same family. Chat stayed fully usable (no #176). UI quibble: the collapsed chip shows the same ✓ checkmark for a cancelled tool as for a success |
| **F7b** | Same, but **edit a field in the card before approving** | The written record matches the EDITED values, not the staged ones. This is the card's headline feature and has never been checked on device |
| **F7c** | Same, and **background the phone while the card is waiting** | The gate survives suspension — card still there on return, still answerable, tool not silently resolved |
| **F7d** | Set the host's **`approvals.mode` to `manual`** (dashboard, or `PUT /api/config`) — it is on **`off`** today — then ask the connected tier for something that needs approval (a shell/file write). **Restore `off` after.** | ⚠️ **DISCOVERY, and the likely outcome is a STALL.** Record what the app shows: a hung run, a silent stop, an inbox item, or nothing at all. **#145 Part A now bounds it** — the turn should FAIL on a real timeout (20s interactive / 300s streaming idle) rather than hang forever. If it hangs past those, that is a #145 finding too. Whatever happens, note whether the host is left waiting on an approval nobody can answer |
| **F7e** | *(optional, same sitting)* Repeat F7d with **`smart`** instead of `manual` | Whether "automatically assess" prompts at all for ordinary agent work. If Smart rarely asks, it may be the honest default for a phone client that cannot answer prompts — an input to **#224** |

**Why F7d matters beyond the check:** if the connected tier can be put into a
state Talaria cannot answer, that is a shipping-relevant gap in the same family
as #180 (the app hides its own degradation) — the user would see a dead turn
with no way to learn an approval is pending. **Do not leave YOLO off**
afterwards unless you mean to; restore whatever state you started in.

### F8 · UNCORDED — **phone OFF the cable, app launched BY HAND, no Xcode session** · **[NEW 2026-08-02]**

> ## ⛔ THE CONSTRAINT IS THE SECTION. Read this before running either row.
>
> **A process with a live Xcode launch session NEVER SUSPENDS** (corded, on power).
> Owen proved it as §D4 attempt 5: an instrumented run survived **2m42s** of
> home-screen backgrounding, so the `.interrupted` branch is **unreachable** on the
> instrumented rig and **"no banner" is the CORRECT outcome there for any run
> length.** These two checks measure what happens when iOS actually suspends the
> app — which the cable prevents by construction.
>
> **Grouped by the constraint, not the gesture.** One is backgrounding and one is
> locking, but both are un-runnable the same way and both need the same setup, so
> they share a sitting. **Recover the log AFTERWARDS** — Console.app on the Mac
> with the phone attached post-hoc, or a sysdiagnose. Do not attach first.
>
> **This section exists because the corded rig produced a wrong-looking-right
> result once already.** Attempts 3–5 in §D4 all read "no banner" and all were
> correct-but-meaningless. A pass recorded from the cable here would be a false
> PASS in exactly #117's shape.

| # | check | pass |
|---|---|---|
| **#226** ⭐ | **On a build carrying PR #243:** start a run, background to the home screen, wait for it to finish, then foreground. Do it twice — once with a SHORT run (finishes inside iOS's grace) and once with a LONG one (outlives it, e.g. ask for a 500-word summary) | **EXACTLY ONE banner, in both cases.** Before this lane: short run → **nothing ever**; long run → **×3**. Leg (a) arms the watch so a short run is no longer silent; leg (b) makes duplicates replace. **If >1: the ×N decomposition owed with #133/#143's OJAMD recount says where the extra came from** (N should be that token's active `push_registrations` rows + 1 local). If 0 on the short run, leg (a) did not arm — capture the log |
| **#81** | Let a run finish while the phone is **locked** | push carries **Reply**; long-press → Reply → headless post lands; the NEXT push also carries Reply. **Same constraint — see the block above.** Duplicated from §F4 deliberately: it is listed there by state (locked) and here by what makes it runnable |

> **⚰️ BOTH ROWS ABOVE MOOT 2026-08-06 — annotating, not deleting. This
> retires §F8 (former Sitting 4) entirely; it had exactly these two rows.**
> - **`#226`:** OPEN_ITEMS #226 is `⚰️ MOOT` (2026-08-04, archived) — "the
>   push-watch surface itself was deleted by #238 (app posts no `push/watch`
>   calls; banners cannot exist without the notification plane)." The one
>   durable piece it produced, the reconcile-leg single-flight fix
>   (`reconcileInFlight`, `0b8aad4`), already landed and stays — nothing
>   left to verify on a phone.
> - **`#81`:** see the matching §F4 annotation above — #238's own text names
>   this feature as accepted collateral, and source grep confirms zero
>   remaining notification code.
> - PR #243 (`4adc0fc`) did merge, for the record — but the feature it
>   fixed was deleted three weeks later, so the merge no longer matters.

---

### F9 · MAC PROFILE ACTIVE — **[NEW 2026-08-06, from tonight's #21/#33 reconciliation]**

Every other section assumes OJAMD is the paired host, since OJAMD is the
default per CLAUDE.md. This is the one state where the Mac Mini is the
active backend profile instead — batch the profile switch, run both rows,
switch back.

| # | check | pass |
|---|---|---|
| **#21** | Switch the active backend to the Mac profile. `probe-t21.pdf` already sits in the Mac's MobileDL as a fixture (staged 2026-07-20) — tap the chip. | Preview sheet presents, ShareLink works. This is a re-confirm of the 2026-07-20 Mac PASS, not a first look — the OJAMD side (never yet measured) is the new ground in §F1. |
| **#33** | Still on the Mac profile, from the Talaria chat, ask Hermes to write an Apple Note and then read it back. | The note appears in Notes.app with the requested content, the #4 confirm gate fired before the write, and the read-back matches. **Source: OPEN_ITEMS #33**, 2026-08-07 reconciliation note — iMessage-from-Talaria-chat was device-verified 2026-07-20 (Shelley send, read receipt), but Notes-from-Talaria-chat never was; the T6 spec's own acceptance scoring called connector end-to-end ⚠️ PARTIAL on exactly this line. This is the one check that closes it. |

### F10 · SIRI / DEEP LINK — leaving the app · **[NEW 2026-08-06]**

Two items whose device checklists were never carried into this file — both
require leaving the app (Safari, Shortcuts, or Siri) to trigger.

| # | check | pass |
|---|---|---|
| **#77** | Type `hermes://session/{id}` (a real session id) into Safari's address bar. Then, via Shortcuts, run "Open URL" with `hermes://ask?q=hello`. | The Safari URL opens that exact session. The Shortcuts URL seeds the composer with "hello," focused, but does **NOT** send — seed-only is the deliberate security posture (any app/webpage can fire a custom scheme; auto-send would let external content inject agent turns). While here: confirm no other installed app already claims the `hermes` scheme. |
| **#56** | Siri Stop discriminator, two runs: "Hey Siri, ask Talaria twenty-seven [a question]," say "Stop" IMMEDIATELY (before the ~25s hand-off); then repeat with a longer question and say "Stop" AFTER the hand-off. | Run 1: the turn actually cancels (`cancelStreaming` path) — the 2026-07-20 sweep scored this a PARTIAL FAIL (kept generating to completion). Run 2: record whether it's uncancellable by design (intent already returned) — if so the defect is wording, not behavior, per the item's own discriminator. |
| **#56** | Tailnet-unreachable re-test: airplane mode ON (off tailnet AND wifi), "Hey Siri, ask Talaria twenty-seven [a question]." | Siri surfaces an honest queued/will-auto-send dialog, not a false "still working." **2026-07-20 scored this a FAIL** (indistinguishable from slow); current source (`AskHermesIntent.swift`'s `.queued` case, riding #90's offline compose outbox) suggests this may already be fixed, but that's an inference from reading code, not a device result — needs a fresh confirm. |

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
- **#21's device-files route-containment check — added 2026-08-07, not a
  phone check.** A server-side confirmation that the relay's device-files
  route refuses to serve anything outside its configured directory. It sat
  in Group 1 and §F1 from 2026-08-06 until the 2026-08-07 hygiene sweep
  (OPEN_ITEMS #273) took it out of both: there is no UI path, so a
  phone-in-hand sitting cannot run it, and the row's old wording carried a
  crafted request path of exactly the kind #261 moved out of the repo.
  **Still owed on #21 — routed, not dropped.** Whoever runs it: method and
  reasoning are in the out-of-repo security addendum, 2026-08-07.
- **#74 (CarPlay Simulator functional pass) — added 2026-08-06, not a phone
  check.** `project.yml:61`'s `com.apple.developer.carplay-voice-based-conversation`
  is commented out today (verified 2026-08-06) — the entry's own text explains
  why: active, it breaks **signed device builds**, because the dev provisioning
  profile can't carry an ungranted restricted entitlement. Running the CarPlay
  Simulator pass needs a dedicated Mac session (uncomment the key, `xcodegen
  generate`, build to the SIMULATOR, run through CarPlay Simulator.app, then
  re-comment before any device build) — it cannot ride a phone-in-hand OTA
  session at all, corded or not. Apple's discretionary grant filing
  (developer.apple.com/contact/carplay/) needs no phone or Mac time and could
  happen independently of a sim pass.

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

### A1b · RE-RUN with the engine PINNED · ✅ **UNBLOCKED — the instrument SHIPPED 2026-08-01**

> **Header corrected 2026-08-02.** This read **[BLOCKED ON AN INSTRUMENT FIX
> FIRST]** for a blocker that was cleared the previous day. **The instrument is on
> `main`:** `VoiceEngineRouter.swift:196` logs
> `voice session starting on engine <name> (relayPaired=<bool>)` at **`.notice`
> with `privacy: .public`** — visible in Console without verbose logging, exactly
> as specced — merged in `7ec8908` with #221's fix.
>
> **A1b is RUNNABLE.** Its only remaining prerequisite is the one it always had:
> **a second person who will call you.** Caught by auditing this document rather
> than trusting it — the same stale-header failure the external audit found on
> #145 the same day, and the reason the standing rule now says a lane re-reads an
> entry's HEADER before committing to it.

**Do not re-run A1 without confirming the engine line appears.** Repeating it blind
would produce another verdict that cannot say what it tested — the entire problem
with the first attempt. The line now exists; **read it in the log before counting
the call**, because a verdict that cannot name its own configuration is what cost
two real phone calls the first time.

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

**ARMED 2026-08-02 (night):** Owen backgrounds a hand-launched (uninstrumented —
Xcode session deliberately stopped first, see D4's observer effect) build
overnight. Read the log next sitting.

---

## §R · Added 2026-08-09 (backlog run) — passive observations and standing watches

Three rows the tracker had queued nowhere. Verified absent before adding:
`grep -n "#256\|#252\|#249\|#250\|island\|Island"` over this file returned zero
matches across 2,130 lines. **One queue — these are not restated in `OPEN_ITEMS.md`.**

### R1 · #256-E (2nd half) + #249F-D — reminder phrasing, PASSIVE

**Prerequisite:** a build at or past `ca895f2` (#249F, PR #273). OTA 2250 and anything
staged after it qualifies; **confirm the build before counting a reading** — an
observation on an older build reads as a miss when it is really a configuration error.

**No forced test — observe on the next NATURAL evening reminder ask.** One ask can
settle both if the time is ambiguous (e.g. "remind me at 8" said in the evening).

- **256-E (2nd half):** an evening "remind me at 8" comes back **offering tonight**
  rather than silently resolving to a past or next-day hour.
- **249F-D:** the reply asks **tonight-or-tomorrow** and makes **no claim that anything
  was set** — the false-positive direction is the dangerous one (user believes a
  reminder exists, relies on it, misses the call).

**Record the model's exact words.** Both are text bars, and the failure mode they guard
against is a *mined phrase*, not a wrong time.

### R2 · #250-E — the Dynamic Island wears the selected icon, STANDING WATCH

**Currently UNTRIGGERABLE on demand** — Owen's own words: he cannot consistently bring
the island up. No Debug harness trigger exists (it would live beside the other harness
buttons — `grep "toollessIndexBatteryButton"` for the pattern). **Do not schedule this;
it is a watch, not a runnable check.**

When an island does appear during real use: its leading icon slot must match the icon
selected in Settings → Appearance → App Icon — both right after a switch, and on a
fresh cold-launch island. Bars 250-A/B/C are MET and the home-screen half is already
confirmed; this is the only unverified half.

*(Whether to build the Debug trigger and make this runnable is Owen's call — see
`handoffs/NEEDS-OWEN-2026-08-09-BACKLOG-RUN.md`.)*

### R3 · #250-A tinted variant — one look, no setup

The tinted app-icon variant's glow was flagged at filing as *"placeholder-grade, judge
on the phone"* and **no verdict was ever recorded**. Next time the home screen is in a
tinted / Focus appearance, look at the Talaria icon and say whether the glow reads as
finished or as placeholder. Not a bar — a one-line judgement.

### R4 · #272 — App Lock re-prompt loop, HARDER-THAN-ORDINARY repro · ~~queued~~ **✅ RAN 2026-08-09 — REPRODUCED ON BOTH GRACE SETTINGS. 272-C MET. DO NOT RE-RUN.**

> **✅ VERDICT, 2026-08-09 — build 2330, corded, Owen driving.** It did not
> need the "harder-than-ordinary" churn this row prescribes: a **plain cancel
> at grace `Immediately` reproduced it on the first attempt**, and the
> `After 1 min` arm reproduced identically (*"same repro, cancelled it and it
> came right back"*). The shade / Control Center / app-switcher variants were
> therefore never needed and are **not owed** — a bug that fires on the
> simplest input does not need the harder ones to be believed.
>
> **Highest `attempt=` reached: 4** in ~7s, ending only at
> `guard=phase(background)` — i.e. **the loop is unbounded and the user
> escapes by leaving the app**, matching Owen's *"I can't get it to sit at
> the screen that has the unlock button."* The clear and the re-fire share a
> timestamp on every rung, so the mechanism is captured directly rather than
> inferred.
>
> **Evidence route worth reusing:** the app was hand-launched, so there was no
> Xcode session and `GetConsoleOutput` could not see it. A rooted
> `sudo /usr/bin/log collect --device-udid <hardware UDID> --last 4h` (Owen
> pastes; hardware UDID from `devicectl device info details`, NOT the
> CoreDevice identifier) read back with `/usr/bin/log show --archive` recovers
> app `Logger` lines **after the fact, from a self-launched build**. That is
> the missing capability for every row on this page whose trigger forbids an
> Xcode launch — including R6/R7 below.
>
> **Full numbers, the mechanism, the narrowed severity, and the two code
> findings the fix lane needs: OPEN_ITEMS #272.** The fix is owed and is now
> the only thing left on that item.

*(original row text follows, kept for the record)*

**Supersedes the bare "background/foreground churn" #272 line in Group 4. Do NOT
schedule a sitting for this alone — ride whatever sitting already touches
Settings/Privacy.**

272-A **reproduced this in a unit test on 2026-08-09**: after a cancelled attempt, ANY
foreground event wipes `didFailAuthentication` and re-fires the prompt with no tap. What
the unit test cannot settle is whether iOS 27 actually delivers that `.active` on Face ID
sheet dismissal — **that is the only thing this row is for.**

Both grace settings (**Immediately**, and **After 1 min**): lock the app, let the Face ID
sheet auto-appear, then **CANCEL it and do nothing else — do not tap UNLOCK.**
- **PASS:** the sheet stays down and the in-app UNLOCK button is the only way forward.
- **FAIL / REPRO:** it comes straight back, unprompted.

Then repeat with churn: cancel + notification shade down/up; cancel + Control Center
open/close; cancel + app switcher and back.

Pull Console and `grep AppLock`. The tell is
`didFailAuthentication true->false on .active (retry flag cleared by foreground,
attempt=N)` immediately followed by `autoAuth FIRED (no tap)`, with `attempt=` climbing.
**Record the highest `attempt=` reached.**

### R5 · #296-C2 — does the host ever SEND `tool.completed.error`?

> **Partial host-side answer obtained 2026-08-09, from Z8's trial rather than
> this row:** the host can go FURTHER than omitting the error field — a
> process killed by the gateway's own shutdown cleanup came back
> `completion_reason:"exited", termination_source:"", exit_code:0` (the exit
> code was the `;`-chained echo's). So when this row runs, ALSO record those
> two fields for the stopped-tool trial, not just the presence/absence of
> `error` on the frame. The row itself is still worth running — it measures
> the FRAME on the runs plane, which Z8's sessions-plane observation does not.

**Developer screen → Runs Transport (Phase 3) ON.** It defaults OFF, so **this row
measures nothing without it.**

Run two turns:
1. a tool call that FAILS ordinarily — `cat /nope/missing.txt`;
2. a long tool STOPPED mid-flight — `sleep 30; echo STOPTEST`.

**Read the FRAMES, not the bubble.** Verbose logging on; watch for
`{"event":"tool.completed", …, "error": …}`.

**Pass/fail is not the point — this is a discovery probe.** If `error` is present and
non-empty, 296-C1's plumbing is live and the chip carries the host's own words. If it is
absent or empty on both, 296-C1 still ships and #296 records that the host does not
populate it — which also settles whether the `exit_code 130` host-log capture ever had a
client-side counterpart at all.

**296-A is unaffected either way and needs no device** — the client knows it stopped.

### R6 · #254-D — voice ghost, REALTIME pin · **⛔ ATTEMPTED 2026-08-09 — UNRUNNABLE ON THE MAC MINI PROFILE. Still OWED; needs a realtime-configured host.**

> **⛔ 2026-08-09, build 2330. Two attempts, neither reached the realtime
> engine — and the second one explains the first.**
>
> **Attempt 1 (13:49, OJAMD-era config, on-device brain):** VOID — wrong engine.
> `active voice engine → native (initial; relayPaired=true)`. Cause: **#221's
> brain gate**, which is checked BEFORE pairing. The on-device brain forbids
> realtime outright, so `relayPaired=true` on that line means nothing. **A
> runner who does not set the brain to HERMES cannot run this row**, and the row
> as written never says so — it says "paired + relay healthy," which is
> necessary and NOT sufficient.
>
> **Attempt 2 (14:00, Mac Mini profile, brain switched to Hermes):** the brain
> switch took (`activeBrain on-device → hermes`), and the probe answered:
> ```
> 14:00:19.188  readiness routed voice to the native engine (configured=Optional(false), state=blocked)
> ```
> **`configured:false` = the Mac Mini's Hermes has no OpenAI key.** There is no
> realtime engine on this host to test. The app behaved correctly; the bar has
> nothing to bind to.
>
> **➡️ To actually run 254-D:** a host where `talk/readiness` reports
> `configured:true`. #221's history implies **OJAMD** was that host — untried
> today, and the obvious next attempt. **Set the brain to HERMES as well as the
> profile.**
>
> **Filed from these attempts: #303** — `VoiceEngineRouter` has no UPGRADE path,
> so a cold Control Center launch pins native even when the brain permits
> realtime. **Masked on this host** (`configured:false` routes native anyway),
> so its cost is unmeasured — bars 303-A/B/C are in the tracker.
>
> **Fourth clean native `LIVE` revoke** captured in passing (179 ms after
> background, Hermes brain selected this time).

*(original row text follows, kept for the record)*

Paired + relay healthy. **Force-quit for a genuinely COLD launch.** Control Center →
"Talk to Hermes". Background the phone **before the header leaves `ESTABLISHING LINK`**;
wait 60s.

**PASS:** silence, mic indicator dark, and the log carries
`#118/#254: app backgrounded with a voice session (STARTING) — revoking it`.

**VOID unless the log also quotes `voice session starting on engine realtime`** (#220's
rule — a verdict that cannot name its own engine tested nothing). Read at
`oslogSeverity: ["all"]` at least once: #198B's `fault` hides under `default`.

If the `(LIVE)` arm fires instead, the connect window closed first and **the trial did
not exercise the race** — retry, do not record it as a pass.

### R7 · #254-E — voice ghost, NATIVE pin (airplane mode, free) · ~~queued~~ **⛔ RAN 2026-08-09 — UNRUNNABLE AS WRITTEN. This row's own fixture defeats its own bar. DO NOT RE-RUN IT AS WRITTEN.**

> **⛔ VERDICT, 2026-08-09 — build 2330, corded, Owen driving. NOT a fail, NOT
> a pass: the check cannot be performed as written, which this document says
> is a defect in the DOCUMENT.**
>
> **Airplane mode pins native by failing the realtime probe — and the same
> failover collapses the connect window the STARTING arm needs to exist.**
> Measured, not argued: `OpenHermesVoiceIntent.perform` at `13:20:52.983` →
> `voice session starting on engine native` at `13:20:53.006`. **23 ms.**
> Owen: *"there is no establishing link, its so fast to failover to local that
> it appears by the time I press talk to hermes, its already listening."*
>
> **What DID run, and it is filed under its own name rather than as this bar:**
> the native **`LIVE`** arm passed — `#118/#254: app backgrounded with a voice
> session (LIVE) — revoking it` 202 ms after background, audio down ~1 s later,
> Owen: *"silence, mic went dark."* That proves the native audio path tears down
> under the #118 guard, which is real value; it says **nothing** about STARTING.
>
> **The native STARTING arm may simply not be reachable from a cold Control
> Center launch at all** — corrected the same day, an hour after this row was
> first written. My first draft said airplane mode was the culprit and that a
> network-keeping native pin (the on-device brain) was the untried candidate.
> **That route was tried within the hour** — the 13:49 254-D attempt ran with
> the network up and the brain on-device — **and it produced the same 22 ms.**
> Native is simply that fast; airplane mode was never the cause. The one door
> still unopened is the realtime→**native FALLBACK**, which needs realtime to be
> attempted and to FAIL — i.e. the **Hermes** brain plus a broken/unconfigured
> realtime path, not merely a network.
>
> **Two things came free from the same logs and are already banked:** Z5's
> `fullBelt=1648tok` (below), and the "Talk to Hermes" half of §F6's #58/#179 —
> **whose documented log location is WRONG, see the §F6 note.**
>
> **New item filed from this run: #302** — the voice session starts ~650 ms
> before App Lock evaluates its cover, so a Control Center launch begins on a
> locked app. Mic state during that interval is UNDETERMINED. Full detail and
> bars: OPEN_ITEMS #254 (device-run block) and #302.

*(original row text follows, kept for the record)*

Same procedure with **airplane mode ON**, which fails the realtime readiness probe and
forces native at zero cost.

**PASS** adds `voice session starting on engine native`. Note `relayPaired=true` may
appear on that line — **pairing does not determine the engine, the probe result does.**

**A 254-D pass says NOTHING about this arm:** realtime speaks through WebRTC's audio
device module on a forced loudspeaker; native speaks through `SpeechOutputService` with
`managesAudioSession == false`. Two different audio paths produce the ghost two different
ways.
