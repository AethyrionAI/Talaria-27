# Buildable-work verification — six tracker items (2026-08-31)

Read-only. Repo `/Users/owenjones/Documents/Claude/Talaria-27`. No files edited, no
xcodebuild/xcodegen/simctl run.

## Verdict table

| item | classification | one-line reason |
|---|---|---|
| **#211A** | **STILL REAL (code), but SUPERSEDED (scope)** | The described flaw (`no-read-belt` filters only read-tool names) is literally still in the code — but the entry's own 2026-08-27 device runs already diagnosed exactly this, added a real toolless arm, retired the D1 gate, and Owen restated the question into **#417** (fabrication vs. honest-refusal). Scheduling "fix #211A's ceiling arm" would re-do work already done; the real open thread is #417. |
| **#359** | **NOT SCHEDULABLE — WATCH, no trigger fired** | Converted to a WATCH on 2026-08-18 after a real investigation eliminated 5 candidate sites and could not identify the mechanism. Trigger for further work is "any recurrence"; none is recorded since. The named code paths (`holdComposedTurn`, `drainComposeOutboxIfPossible`, `fireHeldTurnIfReady`) still exist unchanged, but there is no known bug to fix — only a provenance witness to build *if it recurs*. |
| **#170** | **PARTIALLY ALREADY FIXED — header is stale** | The literal claim ("presents `model_snapshot` as if it were the job's model") was fixed 2026-07-22 (commit `08dbb9a`, #170a): `TaskDetailScreen.swift` now renders via `CronModelBinding`, never raw `model_snapshot`. The second half ("phone cannot pin a model", #170b) is still true and is upstream-blocked (confirmed: no `model` field in the app's create/edit job code). |
| **#173** | **LARGELY OVERTAKEN — the item as filed is mostly resolved, with one deliberate exception** | Massive work landed since filing: on-device and Private Cloud paths now carry real, discriminating "can't see images" captions (`AttachmentCapabilityCopy.swift`, live). The Hermes-host caption was actually built (PR #327), then **deliberately withdrawn the same day** by Owen because it couldn't discriminate — a considered ruling, not an oversight, and it's the one path where the original "silent degradation" symptom is still literally true today. |
| **#182** | **STILL REAL, exactly as the header says** | Test renamed `testMockPairingViaSettingsEntryPoint` → `testConnectingAHostViaSettingsEntryPointLandsBackInChat` (confirmed at `AppTemplateUITests.swift:108`); old name doesn't exist anymore. Flake counter is 2 (not yet 3, the promotion bar); a bounded re-tap hedge (#164's shape) is confirmed implemented at `completeConnect` (~line 460-469). |
| **#219** | **STILL REAL, actively tracked, tooling pointers resolve** | Live, recurring environmental flake (occurred 2026-08-01, 08-12, 08-26; dedicated 10-hour diagnosis lane 08-27 could not reproduce under synthetic load). A tripwire is armed on `main` (instrumentation committed) so the next natural occurrence self-documents. `lane-gate-classify.sh:156`'s `grep -n 'runner dies mid-bundle' OPEN_ITEMS.md` pointer still resolves (3 hits, including the header). No further build work is currently actionable beyond waiting for a natural recurrence. |

---

## #211A — offer-read ceiling-arm design flaw

**Entry:** `OPEN_ITEMS.md:10526` (header) through `:10997` (huge, heavily-dated entry).

**Check requested:** does `LocalChatBackend+OfferRead.swift` still build the "ceiling" arm
(`no-read-belt`) so it removes only READ tools, making it a weak positive control?

**Confirmed in code**, `Talaria/Services/Live/LocalChatBackend+OfferRead.swift`:
- `enum OfferReadArm` (`:34`) has **four** cases now, not three: `control` (:39),
  `toolRollback` (:60), `noReadBelt` (:90), and a newer `toolless` (:105).
- `noReadBelt`'s belt-building code (`:185`): `belt = tools.filter { !offerReadToolNames.contains($0.name) }`
  — still filters out only the named read tools, exactly the flaw the entry describes.
- `toolless`'s belt-building code (`:191`): `belt = []` — a genuinely empty belt, added
  specifically because `noReadBelt` was proven (device run, 2026-08-27) to still let the
  model act via non-read tools in 25/40 trials, so it was not a valid positive control.
- `offerReadDefaultArms` (`:124`) is explicitly the three original arms (`toolless` is
  excluded from the default battery — comment at `:118-123` says it's a diagnostic only,
  "never a promotion candidate").

**So: the flaw is real and present in code exactly as described.** But the entry's own
timeline (all dated 2026-08-27, i.e. very recently) already: (1) ran the device battery and
measured the ceiling only reaching 17.5-20% offer rate instead of the required ≥50%; (2)
ruled out thermal throttling as the cause via a controlled re-run; (3) diagnosed the actual
cause (substitution to non-read tools); (4) built and ran a genuine `.toolless` positive
control that confirmed the same ~20% ceiling; (5) discovered — as the actually important
finding — that with no tools the model **fabricates sensor readings** on half of trials
(filed as **#417**); (6) got Owen's ruling to retire the D1 gate entirely and restate the
question as "honest refusal vs. fabrication," which is now #417's, not #211A's own.

A newest dated block, **2026-08-31 ~00:30** (today, per the file), records a follow-up fix
to four stale `allCases`-pinned test assertions in `OfferReadInstrumentRunTests` that had
been silently red on `main` since `690a04db` — evidence this file is being actively worked,
not stale.

**#417 has no standalone `## 417.` entry yet** in `OPEN_ITEMS.md` (grep for `^## 417` finds
nothing; all six `#417` references are inline mentions inside #211A and elsewhere), even
though it's referenced as "FILED AS #417" on 2026-08-27 and appears in very recent git log
subjects (`417: the tool-failure instrument`, `417 RESULT: ...`). This is outside the scope
of the six items asked about, but worth flagging: if #417 is scheduled as this week's real
follow-on to #211A, its own tracker entry may not exist yet under that header — worth a
quick look before dispatching a lane against "#417" by number.

**Bottom line for scheduling:** do not schedule "#211A: fix the ceiling arm's design flaw"
as new build work — that diagnosis is done and superseded. If anything in this lineage is
schedulable, it's whatever #417's own current state actually is (not verified here; out of
the six-item scope).

---

## #359 — Compose fusion

**Entry:** `OPEN_ITEMS.md:14133-14200`. Live-board one-liner at `:169`:
`#359 🐛 compose fusion — one occurrence, mechanism unknown; WATCH on recurrence (2026-08-18)`.

**Check requested:** does the compose/draft code still have the path this describes?

The entry documents a real, single, unreproduced occurrence (2026-08-17, artifact recovered
from OJAMD session `api_1786894582_1a3f2651` row 27938) where an unsent attempt's text minus
its first 11 characters fused onto a retype in one submit body. A first investigation pass
the same evening:
- **Falsified** the dictation-beheading hypothesis (Owen confirmed the prompts were typed,
  not dictated).
- **Eliminated** five candidate merge sites by the artifact's own byte shape (no separator,
  remnant first): #48 ask-seed, share-seed, Stop-restore, outbox drain, `mergedDictationText`.
- Left the mechanism **unidentified**. Remaining suspect: a TextField/keyboard-layer race
  under iOS 27 beta (programmatic `messageText` writes racing live typing).

**Converted to WATCH 2026-08-18** ("unopposed at the ballot"). Next viable step is explicitly
conditioned on recurrence: *"Trigger: any recurrence — then build the send-time provenance
witness... before hypothesizing."*

**Confirmed the named code paths still exist, unchanged in shape** (`ChatStore.swift`):
`holdComposedTurn` (`:3310`), `drainComposeOutboxIfPossible` (`:3170`),
`fireHeldTurnIfReady` (`:3422`) all present. No grep of `OPEN_ITEMS.md`/`OPEN_ITEMS-ARCHIVE.md`
for `#359` turned up any dated block after 2026-08-18, i.e. **no recurrence has been recorded**,
and the trigger for the "next viable step" has not fired.

**Bottom line for scheduling:** this is not buildable work today. There is no known bug to
fix — the entry itself explicitly says not to spend a lane on it (a single occurrence, "not
worth blocking 3C on"), and the one thing that *would* unblock it (a recurrence) hasn't
happened. Scheduling a day against #359 this week would mean either (a) speculatively
building a provenance witness with no confirmed bug to catch, or (b) idle waiting — worth
surfacing to whoever is scheduling, exactly the "impossible work nobody noticed" class this
verification pass exists to catch.

---

## #170 — `model_snapshot` display / no phone-side model pin

**Entry:** `OPEN_ITEMS.md:2866-3061`.

**Check requested:** does `TaskDetailScreen.swift` (or siblings) still render `model_snapshot`
as if it were the job's model?

**No — this was fixed 2026-07-22** (commit `08dbb9a`, item's own "170a" sub-fix), and the
header (`⚠️ Task detail presents model_snapshot as if it were the job's model...`) is stale
relative to the entry's own body — a live instance of the exact "stale header" hazard
CLAUDE.md warns about.

Confirmed in code:
- `Talaria/Models/CronJob.swift:166-193` — a three-case `CronModelBinding` enum
  (`.pinned` / `.followsHostDefault` / `.unknown`) computed from `model`/`modelSnapshot`
  independently for both provider and model axes (`:166-173`).
- `Talaria/Features/Tasks/TaskDetailScreen.swift:304-315` — renders via
  `job.modelBinding` / `job.providerBinding` and their `.displayValue`/`.displayDetail`,
  never the raw `model_snapshot` field directly.

So the **specific claim in the item's header is FIXED**. The **second half** (170b — "the
phone cannot pin a model at all") is **still true and unchanged**: grepped
`TaskScheduleDraft.swift` and `CronJobService.swift`, both of which explicitly comment that
`model`/`provider` are "CLI/tool-only — deliberately no [UI for them]" — matching the
2026-08-06 dated update in the entry ("`model` is still absent from the job create body and
the PATCH whitelist"). This half is upstream-blocked (Hermes's job create/PATCH API doesn't
accept a model field), not something Talaria code can fix alone.

**Bottom line for scheduling:** the display-mislabeling bug (170a) is done; do not schedule
it again. 170b (no phone-side pin) is real but is not app-buildable work — it's blocked on
an upstream Hermes API change that this repo can't make (standing no-PRs-against-hermes-agent
rule, #159).

---

## #173 — Silent degradation on attachments

**Entry:** `OPEN_ITEMS.md:3061-3322`. This is the item flagged in the brief as "most likely
to have been overtaken" — confirmed correct.

**Check requested:** is this still true, or did #390/#380/guardrail work already address it?

Extensive work landed after filing (2026-07-23):
- **2026-08-20:** PR #327 merged (`f02d1c38`) building the "never-claim floor" — bars 173-A
  through E, all met.
- **Same day, re-ruling by Owen (device-driven):** 173-A (a Hermes-host caption) was **built,
  shipped, and then deliberately withdrawn** because — with no vision-capability signal
  reaching the app at all — it fired on every image turn regardless of whether the model
  could actually see, so it couldn't discriminate ("a caption that cannot discriminate is
  furniture"). This is recorded as a re-ruling, not a bug: Owen's own question/answer pair
  is quoted in the entry.
- The **on-device** and **Private Cloud (#390)** captions **did** ship and remain live —
  confirmed in `Talaria/Services/Support/AttachmentCapabilityCopy.swift`: `Destination`
  has three cases (`hermesHost`, `onDevice`, `privateCloud`); `hermesHost` explicitly
  `return nil` (no caption — a documented ruling, `:87-91`); `onDevice` and `privateCloud`
  each return one of two real, discriminating strings depending on whether image input is
  actually enabled for that turn (`:92-96`, strings at `:100-123`).
- `Talaria/Features/Chat/ChatInputBar.swift:226` wires `visionCapabilityHint(visionCaption)`
  into the compose UI, with an accessibility id (`:630`) — this is live, not dead code.
- 173-E (a Settings-copy rider from #380) was found **already met** by a pre-existing string
  (`PrivacySettingsScreen.swift:338`) that predates #380's filing.

**So: the literal symptom the item was filed about — a Hermes-host image turn producing a
confident reply with no signal the host couldn't see it — is STILL TRUE TODAY**, but only
because Owen deliberately decided a non-discriminating caption was worse than no caption,
not because nobody looked. The broader "silent degradation" problem the item worried about
is now solved for the two paths (on-device, PCC) where the app can actually tell the truth,
and left honestly unsolved (by design, watched) for the one path (Hermes host) where it
can't yet tell the truth from a lie.

**Bottom line for scheduling:** do not schedule this as "build the fix" — the fix was built,
shipped, and pulled by the product owner on the same day, for a documented reason. The only
thing that would reopen it is an upstream `supports_vision` signal plus an app-side decode
of it (parked explicitly as a no-trigger watch) — not schedulable work today.

---

## #182 — Flaky UI test rename / launch timeout

**Entry:** `OPEN_ITEMS.md:3701-3776`.

**Check requested:** current test name, does it still exist, any sign the flake was fixed?

Confirmed:
- `TalariaUITests/AppTemplateUITests.swift:108` — `func testConnectingAHostViaSettingsEntryPointLandsBackInChat()`,
  with a doc comment at `:105-106`: *"Renamed from `testMockPairingViaSettingsEntryPoint` with
  the flow it drives; the claim is unchanged."* The old name (`testMockPairingViaSettingsEntryPoint`)
  does not exist anywhere in the test targets (grep returned zero hits for the old name as a
  function).
- The rename happened because the underlying flow changed (the deleted pairing screen ->
  Connect Host wizard), not because the flake was fixed.
- Flake counter is now **2** (flaked twice during the #309 Lane B gate runs, at the CONTINUE
  tap — "a synthesized tap landing without invoking the action"), proven a flake rather than
  a regression by re-running the gate's exact invocation over identical bytes (14/14 clean).
  The item's own promotion bar is **3** same-signature occurrences — still below it.
- A hedge matching #164's fix shape (a bounded re-tap loop, not a longer timeout) is
  confirmed implemented: `completeConnect` in the same file has re-tap logic around
  `:460-469` (comment: *"After thirty re-taps a diagnostic finally named the mechanism"*)
  and a separate dismiss-tap hedge at `:181`.

**Bottom line for scheduling:** the entry is accurate as written. This is a genuine WATCH at
count 2/3 — real, tracked correctly, not yet a promotable fix lane per the item's own bar.

---

## #219 — XCUITest runner dies mid-bundle

**Entry:** `OPEN_ITEMS.md:10397-10525`.

**Check requested:** does the described failure mode still have a live referent, and do the
gate's tooling pointers still resolve?

Confirmed:
- `scripts/mac/lane-gate-classify.sh:156` prints `grep -n 'runner dies mid-bundle' OPEN_ITEMS.md`
  as its failure-advice pointer. That exact string is present in `OPEN_ITEMS.md` (3 hits,
  including the header at `:10397`: *"XCUITest runner dies mid-bundle: four tests fail with
  NO assertion text."*) — the pointer resolves.
- `scripts/mac/lane-gate-classify-test.sh` (the self-test that is supposed to catch a
  broken pointer) exists at the expected path and is executable.
- The failure signature (test suite reports zero tests + N failures with **no** assertion
  text or `.swift:NN: error:` line anywhere in the log — a runner restart, not a real
  failure) has recurred multiple times since filing: 2026-08-01 (original), 2026-08-12
  (#337, root-caused to `load average 604` with 6 booted sims), 2026-08-26 (#224, root-caused
  partly to load and partly to a newly-identified second cause — a killed-mid-run simulator
  left in a bad `testmanagerd` state), and a dedicated 2026-08-27 ten-hour diagnosis lane
  that could **not** reproduce it under seven induced-load attempts (up to load 186, all
  green) — concluding every historical occurrence coincided with *real* concurrent gate/sim
  activity, not something synthesizable.
- A tripwire (2 lines of instrumentation bracketing the flaky tap) was committed to `main`
  from that diagnosis lane specifically so the *next* natural occurrence self-documents into
  its own `.xcresult`, rather than requiring another reproduction hunt.

**Bottom line for scheduling:** this is a live, correctly-tracked environmental WATCH with
working tooling references. It is not "buildable work" in the sense of a code fix waiting to
be written — the diagnosis lane already concluded the mechanism is host-load-related and
armed a tripwire; the next actionable step is passive (wait for the tripwire to fire on a
natural recurrence). If scheduled as "a day of work," there is nothing concrete to build
against yet.

---

## NOT VERIFIED / caveats

- **#417's own tracker entry**: no `## 417.` header found in `OPEN_ITEMS.md` despite being
  referenced as "FILED AS #417" within #211A (2026-08-27) and appearing in very recent git
  log commit subjects (today's date). Not required by this task's scope, but flagged because
  #211A's own "what's actually open" now points there.
- **#173's upstream watch (route b, `supports_vision` forwarding)**: I did not re-probe the
  live Hermes gateway (out of scope — static/read-only task); confirmed only that the app-side
  decode still doesn't exist via grep (`GatewayModelCatalog.swift` still has no `capabilities`
  key per the entry's 2026-08-09 finding — not independently re-verified against the current
  file in this pass, only cited from the entry's own text).
- **#182's occurrence-count claim ("flaked twice... together with its two sibling journeys")**:
  took the entry's own account of the gate run at face value; did not independently locate
  the raw gate logs from that date to re-derive the count.
- **#219's historical occurrence dates/root-causes**: taken from the entry's own dated blocks
  (which include measured evidence like load averages and xcresult paths); did not open the
  referenced `planning/reports/2026-08-27-xcuitest-relaunch.md` or the `.talaria-instrument-runs`
  artifacts to independently re-verify the numbers inside them.
- No build/test/simulator commands were run, per the hard constraint — all findings are from
  static reads of `OPEN_ITEMS.md`, `OPEN_ITEMS-ARCHIVE.md`, and the named Swift source files.
