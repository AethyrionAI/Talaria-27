# OPUS T27 #180 — the honesty umbrella: the register, the rule, and the one lane that is left

**Tier that EXECUTES this lane: OPUS.** Written 2026-08-09 from a HEAD code read
(`t27-295-expiration-recovery`, `35c6234`). **No code was written for this brief and
no tracker file was edited.**

**Goal:** enumerate every live instance of #180, rule each in or out against the
working tree, state the shared design default as a rule a reviewer can apply, and
hand off ONE executable lane for the residue that nobody else owns — while leaving
#296 and #280 to the dispatches that already own them.

> **The headline, and the only sentence that has to survive this document:**
> **at every seam where the app renders state it does not own, the code models the
> seam as two-valued and puts UNKNOWN on the affirmative side** — via a monotonic
> latch, a collapsing `else`, an optimistic default, or a substitution fallback.
> §5 turns that into a review rule.

---

## 1. Header

| | |
|---|---|
| **Label** | `OPUS` |
| **Item** | `OPEN_ITEMS.md` **#180** — 🎨 UMBRELLA — the app hides its own degradation |
| **HEAD read** | `35c6234` on `t27-295-expiration-recovery` |
| **Produces** | one executable lane (three pure display seams + one convention line), a register, and six decisions for Owen |
| **Does NOT produce** | any re-spec of #296 or #280 — both have live dispatches; this lane excludes them by name |

---

## 2. The instance register

**Every row's mechanism was read at HEAD.** "Already spec'd elsewhere?" means a
dispatch document exists that owns the fix. Line numbers are `35c6234`.

| item | mechanism (code-grounded) | spec'd elsewhere? | shares a fix with | status |
|---|---|---|---|---|
| **#180 inst. 1 = #173** — confident replies over dropped attachments | No capability signal exists to check against. `GatewayModelCatalog` (`Talaria/Services/Live/GatewayModelCatalog.swift:12-46`) carries `provider/model/authenticated/warning/models/featured_models/pricing` — **no `capabilities` key of any kind**. `TurnRuntime` (`:70-82`) names which model *served* the turn but no modality. Repo-wide grep for `supports_vision` / `supportsVision` / `visionCapab` in `Talaria/` + `Shared/`: **zero hits.** So the app has no basis on which to notice, and no wording that declines to claim | no | — (decision-blocked, alone) | **LIVE — DECISION-BLOCKED.** See §8.1; the 2026-08-02 probe's option (a) is now also *upstream*-blocked |
| **#180 inst. 2** — stale skills offered as live after a profile switch | **FIXED 2026-08-02.** `HostFedListPresentation.swift` exists and is the convention; `SkillsStore`/`CronJobsStore`/`InsightsStore` gained `reset()` + a `loadGeneration` guard wired from `AppContainer.handleActiveProfileChanged` | n/a | — | **FIXED** |
| **#180 inst. 3** — refresh failures invisible after first success | **FIXED 2026-08-02.** The three hand-rolled `!hasLoaded` gates were replaced by `HostFedListPresentation.emptyBranchState` — verified in use at `InsightsScreen.swift:86`, `TasksScreen.swift:82`, `SkillsScreen.swift:73` | n/a | — | **FIXED** |
| **#180 inst. 4** — no disconnection indicator | **CLOSED 2026-08-02 by Owen's rejudgement** on a #237–#242 build: *"Now that I see the attempt to send, yes, I think that's enough."* Reactive convention accepted; no app-wide proactive signal | n/a | — | **CLOSED (Owen)** |
| **#296** — an INTERRUPTED tool renders with a ✓ | `cancelStreaming` (`ChatStore.swift:1267`) clears `isActive` on every activity; the rail is two-valued (`MessageBubble.swift:566`) so not-streaming-and-not-active draws `finishedSummary`'s `Image(systemName: "checkmark")` (`ToolActivityRail.swift:87`). **All three line numbers re-confirmed at `35c6234`** | **YES** — `dispatch/OPUS-T27-296-interrupted-tool-state.md` | — | **LIVE — EXCLUDED from this lane** |
| **#280** — a dictated-only thread's blank card title | `appendVoiceTranscript` (`ChatStore.swift:1550-1596`) never calls `finalizeOnDeviceIntelligence()`; the eligibility guard tests `== .hermes` while voice replies are `.voiceHermes`. Title stays `Conversation.defaultTitle` (`Conversation.swift:7`) → `LocalChatBackend.swift:1976` maps it to nil → the drawer row prints its preview twice. **`LocalChatBackend.swift:1973/1976/1977/1991` re-confirmed exactly at `35c6234`** | **YES** — `dispatch/OPUS-T27-280-dictated-thread-title.md` | **#177** — same render seam, opposite end | **LIVE — EXCLUDED from this lane** (but see §6.2: this lane builds its belt) |
| **#177** — connected-mode cards show title and preview as the same line | `SessionsHermesClient.listSessions` maps the server's row verbatim (`SessionsHermesClient.swift:892-906`, `title: row.title` at `:895`, `preview: row.preview` at `:896`), and `ChatScreen.sessionSummary` (`ChatScreen.swift:551-565`) substitutes the preview as the title when `title` is empty, then uses that same preview as the subtitle at `:562`. **Hermes derives both fields from the first user message**, so on the server-fed drawer the two are near-identical by construction | no | **#280** (same function, different cause) | **LIVE.** Owner was filed as "Hermes-side"; **the app-side half is real and is the only remedy we control** — §6.1 |
| **#139 residual** — the app names an engine it is not running | `TalkSessionSnapshot.engine` **defaults to `.realtime`** (`Talaria/Models/VoiceState.swift:178-180`, doc: *"Defaults to `.realtime` — the historical engine"*). `TalkStore.voiceEngine` defaults `.realtime` (`TalkStore.swift:35`) and `reset()` returns it to `.realtime` (`:203`); it is only corrected by `applySnapshot` (`:235`). **`NativeVoicePipelineService.swift:71` is the ONLY producer that stamps `engine:`** — the realtime service rides the default. `VoiceOverlayScreen.sessionHeaderLabel` (`:156-166`) therefore renders **"VOICE LINK · CONNECTING"** for `.idle/.checking/.ready/.connecting` in every state where no engine has been chosen yet — including the up-to-12s realtime start budget (`VoiceEngineRouter.realtimeStartTimeout`, `:97`) that ends in a fallback to native | no | — (rides §6 lane as L2) | **LIVE.** Has **no tracker number**: it exists only as prose inside #180 |
| **#170** — task detail presents `model_snapshot` as the job's model | **170a FIXED.** `CronModelBinding` is a three-case enum at `CronJob.swift:193`, resolved per axis at `:166-173`; `.followsHostDefault` renders the snapshot only as a dated historical line. **170b upstream-blocked** (`model` absent from the job create body and PATCH whitelist). The 2026-08-02 lead found the *same disease one API layer over* — create-time `runtime.model` echoing a nonexistent model id — but that is **Hermes-side** | no | — | **MEMBER, app-side FIXED; remainder UPSTREAM** |
| **#186** — accept-lists reject valid grants | **FIXED, re-verified at HEAD by grep:** `DeviceActionTools.swift:529` re-reads the settled status after a request and `:532` accepts `.fullAccess, .writeOnly`; `DeviceCalendarTools.swift:45` has the named `.writeOnly` branch; `DeviceReadTools.swift:685` accepts `.limited`. Only device confirmation remains (running list §F1) | no | — | **MEMBER, FIXED** |
| **#189** — notifications false-green panel | **DEAD BY DELETION.** `#238` removed the notification subsystem: **zero `import UserNotifications`, zero `UNUserNotificationCenter`, zero `UNAuthorizationStatus`** anywhere in `Talaria/` or `Shared/` at HEAD. There is no panel left to be falsely green | no | — | **MEMBER, MOOT.** ⚠️ the entry does not say so — §4.1 |
| **#235 / #246** — a dead stream leaves a spinner claiming a live turn | **FIXED.** 235-E MET on build 1987; #246 closed 2026-08-04 with its device bar met | no | — | **MEMBER, FIXED** |
| **#187** — gateway ignores `min_messages` | The app asks for a filter and does not get it, then filters client-side and **routes the header stat and the ⌘1…⌘9 ordinals through the filtered list**, so no surface claims a count the shelf does not show. Watch re-fired 2026-08-04 (0.20.0 still ignores) | no | — | **NOT A MEMBER.** The app is not claiming anything it cannot support; it is compensating visibly and Owen decided the divergence. It is a *host-contract* item, not an honesty item |
| **NEW — the share-sheet size label** (`#123` residual (b), never numbered) | `ShareInboxCore.swift:127` caps at `20 * 1024 * 1024` (base-2). `ShareViewController.swift:217` renders *"Too large to hand off (limit \(byteLabel(…)))"* and `byteLabel` (`:100-102`) is `ByteCountFormatter(.file)` — **base-10** → **"21 MB"**. A 20,999,999-byte file also renders as "21 MB" and is refused, so the message reads *"21 MB is too large — limit 21 MB."* **The number the app shows cannot explain the decision the app made.** Filed only as a note inside #123 (`OPEN_ITEMS.md:2619-2621`, *"One call site; honesty-family, alongside #180"*) | no | — (rides §6 lane as L3) | **LIVE, UNNUMBERED** |
| **NEW — the health permission card** (`#181` residual, home item CLOSED and archived) | `LiveHealthService.authorizationStatus` initialises `.notDetermined` (`:59`) every launch and `refreshAuthorizationStatus()` (`:83-107`) **cannot recover it** — its own comment says *"we can't distinguish denied from not-asked for read"* — and then **assigns `.notDetermined` anyway** (`:104`). `PermissionStatus.notDetermined.displayLabel` is **"Not Set"** (`PermissionStatus.swift:15`) with the action label **"Enable"** (`:39`). So after a real grant, every cold launch tells the user they have not granted health access. Home item `#181` closed MOOT 2026-07-24 but its own text still reads *"Option (a), still the presumed fix, still owed"* (`OPEN_ITEMS-ARCHIVE.md:5352`) | no | — | **LIVE, UNNUMBERED, and it is the rule violated in the NEGATIVE direction** — §5.4 |
| **#292 / #295-C / #222** — a *comment* claims what the code does not do | Real, and all three were treated as first-class (295-C was a registered bar). But the assertion is made to a **developer**, not a user | n/a | — | **NOT A MEMBER — boundary case, see §5.5.** Naming this boundary is what stops the umbrella swallowing half the board |
| **#257 / #297 / #181-as-filed** — the app UNDER-sells what it can do | #297's device verdict landed 2026-08-08: 297-A **MISSED** 7/20. The model improvises a 3-of-15 answer instead of naming its belt | no | — | **NOT A MEMBER — the umbrella's INVERSE**, and the archive already says so about #181 (*"there, the app hid its degradation; here, it would have advertised it"*, `OPEN_ITEMS-ARCHIVE.md:5361`). §5.4 shows the two are one rule |
| **#282 / #279 / #289** — silent data loss / duplication | The transcript loses or duplicates a row. Nothing is *claimed*; something is *destroyed* | no | — | **NOT A MEMBER.** Correctness family, not honesty family |

**Live instances with no owner after this brief: three** — #173 (decision), the voice
engine label, the share size label. Plus two that already have dispatches (#296,
#280) and one that needs a number and a decision (the health card).

---

## 3. Verified state

### VERIFIED — read at `35c6234`

**The umbrella's own fixed half is real, and its convention file is the model for
everything below.**
- `Talaria/Core/HostFedListPresentation.swift` exists (48 lines) and its doc comment
  carries **four numbered rules** plus the reason the umbrella exists.
- `emptyBranchState` is called from all three list screens —
  `InsightsScreen.swift:86`, `TasksScreen.swift:82`, `SkillsScreen.swift:73`. The
  hand-rolled `!hasLoaded` gates are gone.

**Both existing dispatches' line numbers hold exactly at HEAD.** `git diff --stat
04af0a7..35c6234` touches only `OPEN_ITEMS.md`, `DeveloperSettingsScreen.swift`,
`LocalChatBackend{,+Battery,+IntentRouting}.swift`, three test files and docs.
Spot-checked and confirmed: `MessageBubble.swift:566`, `ToolActivityRail.swift:87`,
`ChatStore.cancelStreaming` at `:1267`, `Conversation.defaultTitle` at `:7`,
`LocalChatBackend.swift:1973/1976/1977/1991`. **Neither dispatch needs re-basing.**

**The "never echo" rule already exists in this codebase — in exactly one place.**
`LocalIntelligenceService.fallbackCard` (`:444-466`) borrows the reply's first line
for the title and steps the preview to the reply's NEXT line, with the comment:

> *"Give the preview a DISTINCT source … a title-only card is honest; two copies of
> one line is not."* — `LocalIntelligenceService.swift:452-458`

It was written for a **2026-07-11 device-pass FAIL** and never generalized to the
server-fed drawer row, which reproduces the same render through
`ChatScreen.sessionSummary`. **This is #180's thesis in one hunk** — the same shape
as instance 2, where the profile-reset block existed and every store added after
Lane M missed it.

**The optimistic default has exactly one instance in `Talaria/Models/`.** A sweep of
`Talaria/Models/*.swift` for `= true` / `= .realtime` / `= .hermes` / `?? true` on
stored properties returns **one hit**: `VoiceState.swift:180`. That is a useful
negative — the form is rare, which makes it cheap to keep rare.

**The three seams this lane touches are all pure or trivially extractable.**
- `ChatScreen.sessionSummary(from:activeProfileID:)` is already
  `static`, already `internal`-for-tests since #190 (comment at `:549-550`), already
  under test at `TalariaTests/LocalSessionHistoryTests.swift:740-750`, and has one
  production caller (`ChatScreen.swift:498`).
- `VoiceOverlayScreen.sessionHeaderLabel` (`:156-166`) is a **private computed
  property on a View** — not testable today. Extracting it as a `nonisolated static
  func` is the house pattern (`ChatScreen.sessionSummary`,
  `ChatStore.voiceTranscriptMessages`) and is a precondition of bar 180-C.
  `VoiceEngineRouter`'s statics are already tested in
  `TalariaTests/NativeVoicePipelineTests.swift:103-130`.
- `ShareViewController.byteLabel` (`:100-102`) is already `static`.

**#189's surface is gone and the device list already knows.**
`dispatch/DEVICE-PASS-RUNNING-LIST.md:790-791` lists §F3's `#189` row under *"Dropped
from tomorrow — confirmed dead"*, and `:1607-1614` annotates it **⚰️ MOOT** in place
with the grep evidence. `OPEN_ITEMS.md:4702` still says *"fresh-install device
verification owed."*

### ASSUMED — flagged, not claimed

- **That Owen's #177 sighting reproduces on the current gateway.** The observation is
  2026-07-23 against 0.19.x; OJAMD is 0.20.0 now. The *client* substitution at
  `ChatScreen.swift:555-557` is unconditional and verified, but whether Hermes still
  sends title ≈ preview on 0.20.0 was not re-probed. **The app-side fix is correct
  either way** — it makes the row honest for any server that sends a duplicate — but
  do not claim the server behaviour without a probe.
- **The size of the #139-residual window in practice.** The router publishes
  `eventHub.stream(initial: active.snapshot)`, so a subscriber gets the *currently
  selected* engine immediately — which is `activeEngine`'s **init guess**
  (`VoiceEngineRouter.swift:63-66`: brain-permitted ∧ relay-paired). That guess is
  correct whenever `refreshReadiness()` has run and the host's talk is configured. The
  lie is bounded to the states #139 named: readiness skipped, or a realtime start that
  will fall back. **Reachability is verified from source; frequency is not measured.**
- **Whether `.notDetermined` is user-visible on the health row for a user who granted.**
  The code path is verified; whether Owen's own device currently shows it depends on
  `isHealthCollectionEnabled()`, which re-asserts the grant per launch
  (`SensorUploadService.swift:495`). **With sensor streaming OFF — Owen's stated posture
  since 2026-07-23 — the re-assert does not run and the card reads "Not Set".** Not
  observed on device.
- **That #177 is still worth Hermes-side effort.** Filed as *"Owner: Hermes-side."*
  Nothing in this brief changes that; §6.1 only claims the app-side half.

---

## 4. ⚠️ Tracker corrections

**Per THE CLOSE-OUT RULE these go UPSTREAM, into each stale claim's own home, in the
commit that acts on them — not only into this dispatch.** The orchestrator files
them; this brief does not edit `OPEN_ITEMS.md`.

### 4.1 #189's header still asks for a check of a surface that no longer exists

> `OPEN_ITEMS.md:4702` — *"Notifications never authorized on a fresh install + a
> false-green panel — FIX MERGED (PR #152); **fresh-install device verification
> owed**"*, and inside: *"the fresh-install device check, queued as device-list §F3.
> **It is the last blocker-SHAPED verification**."*

**#238 deleted the notification subsystem.** At HEAD there is not one
`import UserNotifications`, `UNUserNotificationCenter` or `UNAuthorizationStatus` in
`Talaria/` or `Shared/`. `dispatch/DEVICE-PASS-RUNNING-LIST.md` annotated this **MOOT**
on 2026-08-06 (`:790-791`, `:1607-1614`); the tracker entry was never annotated.
**Correction owed at #189:** a dated supersession saying the panel and the priming
path were removed with #238, that §F3 has nothing left to run, and that the
"last blocker-shaped verification" line is void. *This is the close-out rule's exact
failure mode — the correction went downstream to the runnable queue and never came
back upstream to the item.*

### 4.2 #180's own "still open under the umbrella" list is stale in three places

> `OPEN_ITEMS.md` #180 — *"Still open under the umbrella — decisions, not mechanisms,
> all queued for Owen: #173's detection approach, instance 4's app-wide disconnection
> indicator …, **#197's automatic retry, #187's `min_messages` param.**"*

- **Instance 4 is settled** by Owen's own rejudgement, recorded higher in the same
  entry. It should not appear in the still-open list; the entry contradicts itself.
- **#197 is CLOSED** (2026-08-04, `OPEN_ITEMS-ARCHIVE.md:6138`). Its automatic-retry
  question went with it.
- **#187 is a WATCH, not an umbrella decision** — Owen decided it 2026-08-02
  (*"Keep, annotated"*) and the watch re-fired 2026-08-04. §2 rules it out of the
  family entirely.

**Correction owed at #180:** the list reduces to **#173's detection approach**, plus
the new entries §8 proposes.

### 4.3 #180's instance list predates three members and omits its own residual

The body still reads *"four instances"* and names four. Since filing, **#296** was
explicitly filed into this family, **#139's residual** was routed here by name
(2026-08-07 tidy pass) and never numbered, and **two more** are identified in §2 (the
share size label, the health card). **Correction owed:** the register in §2 replaces
the four-item list, and the header's *"four instances"* becomes the as-filed count
with a pointer.

### 4.4 #177's "Owner: Hermes-side, not app-side" is half true and reads as a won't-do

The *cause* is Hermes-side — verified: `SessionsHermesClient.swift:892-906` maps the
row verbatim, so the app invents nothing. **But the render is ours**, and
`ChatScreen.swift:555-557` is an app-side substitution that turns a server duplicate
into a printed duplicate, while the identical problem in the local-brain path was
solved app-side a month earlier (`LocalIntelligenceService.swift:452-458`).
**Correction owed at #177:** the header should say *host-side cause, app-side
mitigation available* — the current wording has kept it parked as someone else's
problem for 17 days.

### 4.5 #173's 2026-08-02 amendment overstates how close option (a) is

> #173 — *"capability surfacing is ONE FIELD away"*, *"an upstream fix reaches shim
> and gateway alike."*

True about Hermes's internals. **False as a statement about what the app can read
today:** `GatewayModelCatalog` at HEAD decodes seven keys and **`capabilities` is not
one of them** — not the `{fast, reasoning}` map the probe saw on the wire, and
certainly not a `vision` key that has never existed. So option (a) needs **two**
changes, not one: the upstream `supports_vision` forward *and* an app-side decode
that does not exist. **Correction owed at #173:** state the app-side gap, and record
that the shim's retirement (#223 Lane 5) removed the fallback path that amendment
leaned on.

### 4.6 #170's "another instance of #180" correction is right and should not be re-litigated

`OPEN_ITEMS.md:3975` records that an in-session reading of the absent Model row as a
#180 instance was **wrong** — `CronModelBinding.unknown` renders nothing because
there is genuinely nothing to state, which is the rule *obeyed*. Verified at HEAD
(`CronJob.swift:166-173`, `:193`). **No correction owed. Named here so a future sweep
does not re-file it**, because "the app went quiet" and "the app is honestly absent"
look identical from a screenshot and this umbrella invites exactly that mistake.

### 4.7 What the entries get RIGHT

#296's mechanism (all three sites), #280's symptom chain, #180's diagnosis of
instances 2 and 3, #186's four fixes, #235/#246's closure. **The two existing
dispatches are sound and current at `35c6234`; do not re-derive them.**

---

## 5. THE SHARED DESIGN DEFAULT

### 5.1 The one sentence

> **At every seam where the app renders state it does not own, the code models the
> seam as two-valued and puts UNKNOWN on the affirmative side.**

"State it does not own" is the load-bearing phrase: a Hermes host, an OS permission,
a framework's async lifecycle, a stream that may never end, a model that may not have
seen the image. In every one of those, the app has **three** possible answers — *yes*,
*no*, and *I have not been told* — and the render has **two** branches.

### 5.2 The four syntactic forms, each with its verified instance

| form | what it looks like | verified instance |
|---|---|---|
| **the monotonic latch** | a success flag that only ever rises, used to gate the failure message | `else if let message = store.lastErrorMessage, !store.hasLoaded` — #180 instance 3, three screens, identically wrong |
| **the collapsing `else`** | `if running { … } else { done }`, where `else` is the whole rest of the universe | `isStreaming && contains(\.isActive)` → `finishedSummary` → ✓ — **#296** |
| **the optimistic default** | a stored property whose declared default is the affirmative value, corrected only if a producer bothers to stamp it | `var engine: VoiceEngine = .realtime` (`VoiceState.swift:180`); `var voiceEngine = .realtime` (`TalkStore.swift:35`, `:203`) — **#139 residual** |
| **the substitution fallback** | a missing value replaced by a **different** value from the same row, rather than marked absent | `title ?? preview` (`ChatScreen.swift:555-557`) — **#177 + #280**; `model_snapshot` under the label "Model" — **#170a**; `_ = await post(…)` then `return .delivered` — #286 |

### 5.3 The review rule

> **Every expression that renders external state must be able to produce THREE
> outcomes, and UNKNOWN must be the DEFAULT branch, not the `else` branch.**
>
> Point at the boolean, the latch, the `??`, or the `else` sitting between what the
> app knows and what it draws, and ask: **"what does this draw when the answer never
> arrived?"** If the answer is the same pixels as success, it is an instance.
>
> Corollary — **a fallback may NARROW a claim; it may never SUBSTITUTE a different
> one.** `title ?? "—"` narrows. `title ?? preview` substitutes, and substitution is
> how a UI comes to assert something no layer beneath it ever said.

### 5.4 The rule is symmetric, and that is why #181 and #257 belong to the same pass

The archive already noticed half of this — #181 is called *"the umbrella's inverse …
there, the app hid its degradation; here, it would have advertised it"* — and treated
it as a different problem. **It is the same problem.** The health card's mechanism is
`refreshAuthorizationStatus()` writing `.notDetermined` on a value its own comment
says it cannot know (`LiveHealthService.swift:100-105`), and `.notDetermined` renders
as the definite words **"Not Set" + "Enable"** (`PermissionStatus.swift:15`, `:39`).
Unknown collapsed to a definite answer — the *negative* one. The user is told they
have not granted something they granted.

So the rule does **not** say "prefer the pessimistic branch." It says **unknown gets
its own branch.** Under-claiming (#257's improvised 3-of-15 capability answer, the
health card's "Not Set") and over-claiming (#296's ✓, #177's duplicate row) are the
same defect with the sign flipped, and a fix that just flips defaults from optimistic
to pessimistic ships instance six.

### 5.5 The boundary — what this umbrella is NOT

**The assertion has to be made to a USER.** #292's comment claiming the producer is
cancelled, #295-C's three sites promising a recovery route the code never walked, and
#222's comment describing a choice as a limitation are all real, all serious, and all
lies told to a *developer*. They have their own precedent and their own bar shape
(295-C was registered and met). **Keep them out**, or the umbrella swallows half the
board and stops being actionable — which is the failure mode #266 exists to prevent.

Likewise **data loss is not dishonesty.** #282, #279 and #289 destroy or duplicate a
row; nothing claims anything. Different family.

### 5.6 Why the convention is the deliverable

The tracker already recorded this lesson once — *"#180's lesson is that the
convention is the deliverable"* (`OPEN_ITEMS.md:9905`) — and the 2026-08-02 lane
proved it: it shipped `HostFedListPresentation.swift`, one written-down convention
plus one shared decision function, and **that** is what stopped the three screens from
drifting apart again. The evidence that a convention only helps where it is written
down is sitting in this codebase: `fallbackCard` solved "never print one line twice"
on 2026-07-11, in a doc comment, in one file — and the server-fed drawer row
reproduced the same render for the next month because nobody generalized it.

**So bar 180-F is not paperwork.** Rule 5 in `HostFedListPresentation.swift` is the
part of this lane with the longest half-life.

---

## 6. Lane proposal

### 6.0 The shape, and what it deliberately is not

**This is not one giant lane, and #180 must not become one.** #291 and #294 were split
because *"they are separate items because the fixes are different"*, and that logic
holds here with force: #296 changes a model + a render, #280 changes a call site + two
predicates, #173 is a product decision, the health card needs a `PermissionStatus`
decision. **Four different fixes.**

What is left after those are removed is a residue of **three pure display-derivation
seams**, each ~10–30 lines, each with an existing test file, each too small to justify
a lane alone. They share the RULE and the TEST SHAPE; **they do not share a call
graph, and this brief will not pretend they do.** They are bundled because the
convention is written once and because a lane that fixes one label seam and leaves two
standing is how instance seven gets filed.

### 6.1 Lane 180-L — the claim lane

**Branch:** off `main`. **Device: none — every bar is unit-testable.**

**L1 — the drawer row (this is the one that is genuinely a SHARED fix).**
`ChatScreen.sessionSummary` (`:551-565`). Apply `fallbackCard`'s existing rule: when
the chosen subtitle would equal the chosen title, **step to the next rung of the
subtitle ladder** (`:558-565` already has `messageCount` and `"No messages"` rungs)
rather than printing the string twice. Do not delete the substitution — a row whose
only text is its preview should still show it; it should show it **once**.

- Closes **#177's app-side half** — the only remedy we control, since the cause is
  Hermes deriving both fields from the first user message.
- **Belts #280** — the drawer symptom becomes impossible even when the on-device
  generator throws, which it does on the test host (`Code=5000`, no assets) and on any
  device without model assets. **It does not close #280:** 280-A asserts
  `conversation.title != Conversation.defaultTitle`, which this change does not touch,
  so #280's lane still goes RED under its B1. **State that in both PRs.**

**L2 — the voice header.** Give `VoiceEngine` an unknown state at the *snapshot*
level, or have `VoiceEngineRouter.forward(_:engine:)` stamp `activeEngine` onto every
snapshot it republishes — it already knows the value it is failing to write. Then
extract `sessionHeaderLabel` (`VoiceOverlayScreen.swift:156-166`) as a
`nonisolated static func` so it can be tested, and make the pre-selection label
engine-neutral (**"VOICE · CONNECTING"**, not "VOICE LINK").

- Settles the **#139 residual** that closure explicitly left unasserted — and settles
  it **without the tethered device sitting** that entry said it needed, because the
  defect turns out to be a default in a struct, not a runtime routing question. *That
  is the finding: #139 filed this as needing a quoted log line; it needs a unit test.*

**L3 — the share refusal.** `ShareViewController.swift:217` + `byteLabel`
(`:100-102`). Make the stated limit and the displayed file size answer to the same
arithmetic, so the number in the refusal can explain the refusal. Owen picks the
direction (§8.4).

- Closes the unnumbered `#123` residual (b) that the tracker itself routed here.

**L4 — rule 5.** Add the §5.3 rule to `HostFedListPresentation.swift`'s doc comment,
naming the four forms and the "narrow, never substitute" corollary, and cross-linking
`LocalIntelligenceService.swift:452-458` as the precedent. The file's title says *"THE
CONVENTION for any surface fed from a Hermes host"*; L2 and L3 are not host-fed, so
either widen that sentence or note the widening explicitly — **do not rename the type
in this lane** (it has three call sites and a rename buries the diff).

**Ordering:** L4 first (write the rule, then obey it), then L1, L2, L3. **L2 and L3
are independently droppable** — if the lane runs long, ship L1 + L4 and file L2/L3
with their bars intact. They do not depend on each other.

### 6.2 What stays separate, and why

| item | why it is not in this lane |
|---|---|
| **#296** | Owned by `dispatch/OPUS-T27-296-interrupted-tool-state.md`. Different fix: a new `ToolActivity` field, a three-state derivation, a `cancelStreaming` marking loop, a wire-field rescue. **Carries a data-loss hazard (296-E) this lane has none of.** Do not re-spec |
| **#280** | Owned by `dispatch/OPUS-T27-280-dictated-thread-title.md`. Different fix: invoke the generator on the voice path, widen two sender predicates. **Its own §4 documents a no-op trap; that trap is not this lane's** |
| **#173** | Decision, not code — and now double-blocked (§4.5). Nothing is executable until Owen picks between capability-surfacing and the never-claim floor |
| **the health card** | Needs a `PermissionStatus.unknown` case (which ripples through **every** permission row, the Privacy screen, and `SubsystemHero`) **or** a persisted grant flag that changes what `collectSnapshot()` gates on — #16's territory. Bigger blast radius than the whole lane above. **Needs a tracker number first** |
| **#170b, #187 gateway half, #177's server half** | Not ours |
| **#186, #189, #235/#246, instances 2/3/4** | Fixed, moot, or closed |

---

## 7. Proposed bars

**BARS LIVE IN THE OPEN_ITEMS ENTRY. These are PROPOSALS; the orchestrator files them
into #180 before any code.** Refine wording, not strictness.

### 7.1 Carried VERBATIM — do not rewrite

**#296-A/B/C**, exactly as they stand in the `OPEN_ITEMS.md` #296 entry:

> **(296-A)** a tool in flight when Stop is tapped does NOT render a ✓;
> **(296-B)** a genuinely completed tool still does; **(296-C)** a host-reported tool
> error reaches the chip instead of being dropped.

`dispatch/OPUS-T27-296-interrupted-tool-state.md` §3 proposes refinements and two
additions (296-D, 296-E). **Those are proposals, not filings** — that dispatch says so
itself. This brief does not adopt, alter, or supersede any of them.

**#280-A…F** as proposed in `dispatch/OPUS-T27-280-dictated-thread-title.md` §5. Not
yet filed; carried by reference, unmodified.

**#295-A/B/C** are MET (2026-08-08) and are historical here.

### 7.2 New bars for lane 180-L

Every one is unit-testable, **no device**, and each states how it goes RED **on the
defect** — the anti-pattern being avoided is a test pinned to text the fix never
touched.

---

**180-A — no session row prints the same string as its title and its subtitle.**
For every `HermesSessionInfo` the drawer can receive, `ChatScreen.sessionSummary`
returns `title != subtitle`.

- *Evidence:* rows in `TalariaTests/LocalSessionHistoryTests.swift` beside the
  existing `sessionSummaryMapsOriginAndUnresumableState` (`:740`).
- **How it goes RED on the defect:** two rows, each red for a different cause.
  (i) **#177's shape** — `title` and `preview` set to the same non-empty string (what
  Hermes sends): today `:555` takes the title branch and `:562` takes the preview, and
  the assertion fails on two identical strings. (ii) **#280's shape** — `title: nil`,
  `preview` non-empty: today `:557` substitutes the preview as the title and `:562`
  repeats it. **Neither row can be satisfied by editing a string constant**, which is
  the point.
- *Device:* no.

**180-B — a row with a genuinely distinct title keeps BOTH lines.**
Distinct `title` + distinct `preview` → the title is the title and the subtitle is the
preview, unchanged from today.

- *This is the regression bar.* It is what stops the lane from "fixing" 180-A by
  deleting the subtitle, and it must also cover the three ladder rungs #190 already
  owns: `unresumableReason`, the message count, and `"No messages"`.
- **RED check:** it is GREEN today by construction — that is correct and it must be
  stated in the commit, because a bar that was never red is a *pin*, not a proof. Its
  job is to fail if L1 over-reaches.
- *Device:* no.

**180-C — the overlay does not name an engine before one has been selected.**
The extracted `sessionHeaderLabel` derivation, given a `TalkStore` in its initial
state (no snapshot applied), returns a label containing **neither** "VOICE LINK" nor
"LOCAL VOICE".

- *Evidence:* new rows in `TalariaTests/NativeVoicePipelineTests.swift`, beside the
  existing `VoiceEngineRouter` static tests (`:103-130`).
- **How it goes RED on the defect:** today the derivation reads
  `talkStore.voiceEngine == .native`, `voiceEngine` defaults to `.realtime`
  (`TalkStore.swift:35`), and `.idle` falls to `:162` → **"VOICE LINK · CONNECTING"**.
  The assertion fails on the literal string "VOICE LINK". **The test cannot pass
  without the unknown state existing**, so it cannot be satisfied by re-wording.
- **Second red, and it is the one that proves the mechanism:** construct a
  `TalkSessionSnapshot` with no `engine:` argument and assert its engine is not
  `.realtime`. Today `VoiceState.swift:180`'s default makes it `.realtime` — the
  optimistic default, caught directly.
- *Device:* no.

**180-D — a session that HAS selected an engine still names it.**
Once a snapshot carrying `.native` is applied, the label reads "LOCAL VOICE"; once one
carrying `.realtime` is applied, it reads "VOICE LINK" / "VOICE SESSION" per
`:158-166`. The `LOCAL VOICE · ON-DEVICE PIPELINE` badge (`:138-145`) still appears on
native.

- *This is the regression bar for L2.* #18's whole point is that local voice is never
  silently substituted for the Realtime experience; an unknown state must not erase
  the distinction it exists to draw.
- **RED check:** as with 180-B, green today; stated as a pin.
- *Device:* no.

**180-E — the number in the size refusal explains the refusal.**
For the byte count the guard is the largest to ACCEPT, `byteLabel` renders a value
`≤` the stated limit; for the smallest it REFUSES, it renders a value `>` the stated
limit.

- *Evidence:* `TalariaTests/ShareInboxCoreTests.swift` (or `ShareExtensionConfigTests`).
- **How it goes RED on the defect:** `defaultMaxEnvelopeBytes` is `20 * 1024 * 1024`
  = 20,971,520; `ByteCountFormatter(.file)` is base-10, so the limit renders **"21 MB"**
  and 20,999,999 bytes — which the guard REFUSES — also renders **"21 MB"**. The
  assertion `refusedLabel > limitLabel` fails on two equal strings. **The defect is
  arithmetic, so the test cannot be satisfied by changing copy.**
- *Device:* no.

**180-F — the convention is written down and names the four forms.**
`HostFedListPresentation.swift`'s doc comment carries §5.3's rule as rule 5, names the
latch / collapsing-else / optimistic-default / substitution forms, states the
narrow-never-substitute corollary, and cites
`LocalIntelligenceService.swift:452-458` as the in-repo precedent.

- *Evidence:* the file.
- **Why it is a bar rather than a nicety:** #180's own recorded lesson is that the
  convention is the deliverable (`OPEN_ITEMS.md:9905`), and this codebase has a
  worked example of what happens without it — `fallbackCard` solved this exact render
  on 2026-07-11 in one file's doc comment, and the server-fed row reproduced it for a
  month. **A bar is the only thing that makes the writing survive a time-boxed lane.**
- *Device:* no.

### 7.3 Bars this lane deliberately does NOT propose

- **Nothing for #173.** A bar written before Owen picks a detection approach would
  pre-empt the decision.
- **Nothing for the health card.** Same reason, plus it has no tracker number yet.
- **No umbrella-wide "no surface may claim…" bar.** Unfalsifiable as written, and
  #180's existing instance list is the standing evidence that a stated principle
  without a code seam does not hold anything.

---

## 8. What is OWEN'S to decide

### 8.1 #173 — capability surfacing, or the never-claim floor?

**New fact since the 2026-08-02 amendment:** the amendment's option (a) is not one
field away from the app. `GatewayModelCatalog` at HEAD decodes seven keys and carries
**no `capabilities` map at all** (§4.5) — so option (a) needs the upstream
`supports_vision` forward **and** an app-side decode, and the shim that was the
fallback is retired (#223 Lane 5).

**Recommendation:** ship the **never-claim floor** ("not known to support images",
never a hard block — the wording #173 already specifies) and demote the capability
half to a **watch** on the gateway payload, same posture as #187's. It costs one
string and closes the user-visible harm; the capability half can arrive free if
Hermes ever forwards the flag.

### 8.2 Does the umbrella stay an umbrella?

**Recommendation: keep it, and RE-CHARTER it — from a container of instances to the
rule plus the register.**

The argument for dissolving is real: every live member now has, or should have, its
own number and its own lane, and the split precedent (#291/#294 — *"separate items
because the fixes are different"*) says an item whose members have four different
fixes is not one item.

The argument for keeping is stronger, and it is empirical. Two members were found by
this brief **only because the umbrella existed to look under** — the share-sheet
label, which was a note inside a closed-ish feature item, and the health card, whose
home item is closed and archived and whose own text still says the fix is owed.
Neither would have surfaced from a per-item sweep. And #180's most durable output was
never a fix; it was `HostFedListPresentation.swift`.

**So:** #180 owns (a) the rule in §5, (b) the register in §2 with each member's home,
and (c) **nothing executable**. Every instance is worked in its own numbered item.
The umbrella's only recurring job is the one it just did: catch instance five before
a user does.

### 8.3 Three things need tracker numbers before they can be worked

**"A phase name is not a filing" (#268) applies to instances too.**

1. **The #139 residual** — currently prose inside #180's body, with no number, no
   bars, and a mechanism (§2) that turns out to be a struct default rather than the
   device question its closure assumed.
2. **The share-sheet size label** — currently a bullet inside #123's 2026-08-06 note,
   already tagged *"honesty-family, alongside #180."*
3. **The health permission card** — currently a paragraph inside **archived** #181,
   which says the fix *"remains owed"* in a file nobody reads for open work.

Numbers can be assigned as members of the register, or as three new entries. **They
cannot stay where they are** — (3) in particular is one archive sweep from invisible,
which is precisely why the 2026-08-07 tidy pass pulled #139's residual up here.

### 8.4 The share-refusal arithmetic — which way?

Two honest fixes: **(a)** make the cap base-10 (20,000,000 bytes) so every label the
extension shows is the same arithmetic as the guard, or **(b)** keep the base-2 cap
and render the limit with a base-2 formatter ("20 MiB"). (a) is simpler and matches
the numbers Files and Photos show the user; (b) is more precise and uglier. **Owen
picks; the bar (180-E) is the same either way.**

### 8.5 HUD copy for the unknown voice state

**"VOICE · CONNECTING"** is a proposal. The label lives on the overlay Owen looks at
during every voice sitting, and #18's rule is that local voice is *never silently
substituted* — so the neutral wording must not read as a third engine. **Owen
approves the string before the PR.**

### 8.6 The health card — three options, and it is not a free choice

**(a)** Add `PermissionStatus.unknown` rendering as `"—"` per CLAUDE.md's real-data
rule. Most correct; ripples through every permission row, the Privacy screen and
`SubsystemHero`. **(b)** Persist the grant (`didGrantHealthAccess` on a successful
`requestAuthorization()`) — #181's own recommendation, and it changes what
`collectSnapshot()` gates on, i.e. it touches the sensor pipeline (#16). **(c)**
Accept it and write the acceptance down.

**Recommendation: (a), scoped to the health row only** — the other permission types
*can* read their real status, so `unknown` should be reachable only where the
framework genuinely hides it, and `LiveHealthService`'s own comment already names that
as the one place. But this is Owen's, and it should not ride lane 180-L.

---

## 9. Close-out

**The gate.** `scripts/mac/lane-gate.sh` — Debug suite (units + XCUITest) **and** a
Release build, positive marker from each. It takes minutes: background it and poll the
log with an `until` loop. **Never arm a Monitor, never wait for a notification.**

```bash
cd /Users/owenjones/Documents/Claude/Talaria-27
nohup scripts/mac/lane-gate.sh > /tmp/lane-gate-180.log 2>&1 &
until grep -qE 'GATE: (PASS|FAIL)' /tmp/lane-gate-180.log; do :; done
grep -E 'GATE: (PASS|FAIL)' /tmp/lane-gate-180.log
```

The literal string **`GATE: PASS`** is the only acceptable result — absence of failure
text is not success (`lane-gate.sh:18-25`).

**Confirm the test count MOVED.** This lane adds rows to `LocalSessionHistoryTests`,
`NativeVoicePipelineTests` and a share test file. If the count does not move,
`test-without-building` re-ran a stale `.xctest`; purge
`<dd>/Build/Intermediates.noindex` and run plain `test`. Resolve the DerivedData hash
from `info.plist`, never from memory — this checkout is
`Talaria-gzpowyfsuofejnbsytskngrskzkm`, and every worktree gets its own.

**`xcodegen generate`** only if L3 lands in a NEW test file; adding rows to the three
existing files needs no regen.

**Upstream text this lane's result FALSIFIES — corrected in the same commits, per THE
CLOSE-OUT RULE:**

| Where | What becomes false | Correction owed |
|---|---|---|
| `OPEN_ITEMS.md` #180 body | *"four instances"*; the still-open list naming instance 4, #197 and #187 | Replace with the §2 register; reduce the still-open list to #173 (§4.2, §4.3) |
| `OPEN_ITEMS.md` #180 | the residual paragraph says settling the #139 residual *"needs a tethered run that quotes the `voice session starting on engine …` line"* | **False.** The mechanism is `VoiceState.swift:180`'s default plus `TalkStore.swift:35/:203`; it is unit-testable and 180-C settles it with no device |
| `OPEN_ITEMS.md` #177 | *"Owner: Hermes-side, not app-side"* | Host-side **cause**, app-side **mitigation** — and the mitigation shipped a month earlier in the local path (§4.4) |
| `OPEN_ITEMS.md` #189 | *"fresh-install device verification owed"*, *"the last blocker-SHAPED verification"* | #238 deleted the surface; §F3 is empty. The device list annotated this 2026-08-06 and the entry never was (§4.1) |
| `OPEN_ITEMS.md` #173 | *"capability surfacing is ONE FIELD away"* | Two fields: the upstream forward AND an app-side decode `GatewayModelCatalog` does not have (§4.5) |
| `OPEN_ITEMS.md` #123, 2026-08-06 note (b) | the size-label bug recorded as a note with no number | Numbered as a #180 register member; bar 180-E |
| `OPEN_ITEMS-ARCHIVE.md` #181 | *"Option (a), still the presumed fix, still owed"* sits in the archive | Per #261's rule, a correction to a closed item goes on the **live** board — the health-card residual gets a number there (§8.3) |
| `Talaria/Core/HostFedListPresentation.swift` doc | *"THE CONVENTION for any surface fed from a Hermes host"* — L2/L3 are not host-fed | Widen the sentence with rule 5, or note the widening. **Do not rename the type in this lane** |
| `dispatch/OPUS-T27-296-interrupted-tool-state.md` close-out table | its row *"#180 … the umbrella's instance list predates this"* | Still owed and still correct; this brief supplies the register it asks for |

**Nothing in `CLAUDE.md` is falsified by this lane.** Checked: its *"Real data only in
UI — show `"—"` where a value isn't knowable"* convention is exactly what §5 is a
restatement of, and this lane strengthens rather than contradicts it. **If Owen takes
§8.6 option (a)**, that line becomes worth a cross-reference to
`PermissionStatus.unknown` — a small addition, not a correction.

**The PR.** Branch off `main`. Body states which bars are MET with the evidence line
for each, quotes the literal `GATE: PASS` line, names each RED step and what it failed
on, and says plainly that **#296 and #280 are NOT touched by this lane** and that
**L1 belts #280's symptom without meeting 280-A**. Owen routes the merge, and #280's
lane must merge on top rather than beside it — if #280 lands first, L1's 180-A row (ii)
must still be red against a `title: nil` `HermesSessionInfo` constructed directly,
which it is, because 180-A tests the mapping function and not the generator.
