# Log-scored card audit — 10 cards

READ-ONLY static source audit at `/Users/owenjones/Documents/Claude/Talaria-27`, HEAD `7f5aa8de`
(commit count **3147**). No builds, no simulators, no `log collect` run. Every claim below is
`grep`/`sed` evidence with file:line.

---

## Verdict table

| Card | Class | Verbose needed? | One-line reason |
|---|---|---|---|
| **302-323** | STALE-FIXABLE | **No** | All five markers exist and are always-on `.notice`, but two of them (`send deferred`, `compose outbox drain deferred`) **cannot occur under the Steps as written** — the script never sends a chat message while locked. Plus the Control Center tile is no longer called "Talk to Hermes". |
| **415d** | RUNNABLE | **No** | `voice session parked — App Lock cover armed mid-flight (#415)` exists verbatim, always-on `.notice`. Two free extra markers score the resume arm. One caveat on the park line's absence (see below). |
| **303ab** | STALE-FIXABLE | **No** | Engine line exists and is decisive, but its trailing field was renamed `relayPaired=` → `voiceHostPaired=`, and the tile is now "Talk to Talaria". |
| **254d** | STALE-FIXABLE | **No** | "the revoke line" is **never named** — the scar shape. It exists (`#118/#254: app backgrounded with a voice session (STARTING) — revoking it`) but the card must quote it. Also needs a car-audio exclusion in Setup. |
| **198ba** | **UNCERTAIN** | **No** | `AVAudioSession_iOS.mm:978` has **zero emitters in our source** — it is an Apple-internal diagnostic keyed to a line number in Apple's own file, and the device is on a newer OS build (`24A5424a`) than the observation. An absence bar on a marker we don't control fails silently green. |
| **396r12** | RUNNABLE | **No** | `fallback endpointer fired` exists, always-on `.notice`; `1.35` threshold still matches. One genuine hole in the SPLIT-B dichotomy (below). |
| **3eh34** | **UNCERTAIN** | **No** | App half verified (the `/stop` POST is real). The load-bearing marker is a **HOST** log string the card never names and this repo cannot verify. Worse: the app logs **no run_id on the happy path**, so there is nothing to correlate with. |
| **312b** | STALE-FIXABLE | No (**recommended**) | Its FAIL clause ("no priming tokens") contradicts a documented-legitimate state — the Priming row renders `"—"` when tokens are unknown, by design. `/usage` (verbose) makes this card cheap and unambiguous. |
| **329-330** | RUNNABLE | **No** | Nothing stale; the #330 half is correctly marked superseded. Two always-on `#329` notices exist that the card does not name and which would replace most of the screen-driving. |
| **330g** | RUNNABLE | **YES — mandatory** | Every string matches source exactly. `/usage` **and** all three `#330 seam` lines are verbose-gated; with the toggle off the card produces a plausible-looking wrong report rather than nothing. |

**Totals: 4 RUNNABLE · 4 STALE-FIXABLE · 2 UNCERTAIN · 0 UNRUNNABLE.**

---

## 🔴 THREE CROSS-CUTTING FINDINGS — read before running any card in this group

### 1. THE APP EMITS UNDER **TWO** SUBSYSTEMS. A single-subsystem predicate silently drops half the markers.

- `TalariaLog.subsystem` = `Bundle.main.bundleIdentifier` = **`org.aethyrion.talaria27`**
  (`Talaria/Core/TalariaLog.swift:19`; bundle id at `project.yml:116`)
- Several loggers hardcode the **legacy** string **`"org.aethyrion.talaria"`** (no `27`).

Which cards this bites:

| Subsystem | Category | Markers living here |
|---|---|---|
| `org.aethyrion.talaria27` | `AppLock` | `cover=locked locked=true`, `requestUnlock EXIT … result=SUCCESS` (302-323) |
| `org.aethyrion.talaria27` | `Voice` | `voice session parked … (#415)`, `parked voice session resuming/NOT resumed` (415d) |
| `org.aethyrion.talaria` | `LiveVoiceSessionService` / `NativeVoicePipeline` | `capture chain HOT` (302-323, 415d), `fallback endpointer fired` (396r12) |
| `org.aethyrion.talaria` | `VoiceEngineRouter` | the engine line (303ab, 254d, 396r12) |
| `org.aethyrion.talaria` | `AppContainer` | the #254 revoke line |
| `org.aethyrion.talaria` | `ChatStore` / `SessionsHermesClient` | `send deferred`, `compose outbox drain deferred`, all three `#330 seam` lines, both `#329` notices |

**`subsystem == "org.aethyrion.talaria"` misses the entire App Lock and #415 corpus.** Use a prefix
match on every pull in this group:

```
log show --archive <path> --info --debug \
  --predicate 'subsystem BEGINSWITH "org.aethyrion.talaria"'
```

(This is the "two app subsystems, grep the prefix" note, now pinned to exact card impact.)

### 2. A DEBUG/Xcode BUILD REPORTS **BUILD `1`**, NOT `3147`.

`project.yml:131` sets `CURRENT_PROJECT_VERSION: "1"`. The real build number is injected **only by
`scripts/mac/ota-stage.sh:36,62`** (`git rev-list --count HEAD`, floored by a high-water mark).
The in-app readouts (`Talaria/Features/Settings/AboutSettingsContent.swift:428`,
`DeveloperSettingsScreen.swift:493`) read `CFBundleVersion` straight through.

⇒ On the fresh **Debug** build the operator is told to use, "Record: Build" will read **`1`**, and
`needs 3022` / `needs 3120` / "quote it — the walk is void on a stale install" (3eh34) cannot be
satisfied by inspection. Substitute the **commit SHA** for the build number on every card in this
group, or stage via OTA. Code-wise both gates are satisfied: HEAD's commit count is **3147**.

### 3. DEBUG GATING IS A NON-ISSUE HERE — VERBOSE GATING IS THE REAL ONE.

**No marker in any of these ten cards is behind `#if DEBUG`.** The only gate that matters is
`TalariaLog.isVerbose` (Developer → **Verbose Logging**, `DeveloperSettingsScreen.swift:200-202`),
which backs three things:

- `Logger.verbose(_:)` → `.debug` — **does not survive `log collect`** (`TalariaLog.swift:66-70`)
- `Logger.verboseNotice(_:)` → `.notice` — **does** survive; written for exactly these device passes
  (`TalariaLog.swift:72-86`)
- the `/usage` slash command (`ChatScreen.swift:1721`, `SlashCommand.swift:104-123`)

Only **330g** needs it. `SlashCommand.swift:102-104` explicitly says it is *not* `#if DEBUG`
because `ota-stage.sh` archives Release — so verbose works on an OTA build too.

---

## Per-card detail

### CARD 302-323 — "The locked-interval log corpus + parked status" — **STALE-FIXABLE**

**Verbose: NOT required.** Every marker is always-on `.notice` with `privacy: .public`.
`AppLockController.swift:40-47` states this in so many words.

| Card's marker | Verdict | Evidence |
|---|---|---|
| `capture chain HOT…(#302-A)` | ✅ **two** emitters | realtime: `Talaria/Services/Live/LiveVoiceSessionService.swift:1092` — `capture chain HOT — RTCAudioTrack.isEnabled=… peerConnection=… (#302-A)`, `.notice`, subsystem `org.aethyrion.talaria` / cat `LiveVoiceSessionService` (decl `:15-16`). native: `Talaria/Services/Live/NativeVoicePipelineService.swift:1173` — `capture chain HOT — AVAudioEngine.isRunning=… inputTap=installed (#302-A)`, `.notice`, cat `NativeVoicePipeline` (decl `:30-31`). Ungated both. |
| `cover=locked locked=true` | ✅ but narrower than it looks | `Talaria/Core/AppLock/AppLockController.swift:122`, inside `scenePhase <old> -> <new> \| pre: cover=<c> locked=<b> authenticating=… didFail=… attempt=…`. Emitted via `note()` → `log.notice` (`:77-79`), subsystem **`org.aethyrion.talaria27`**, cat `AppLock`. |
| `compose outbox drain deferred…(#323-A)` | ✅ exists, ⚠️ unreachable under Steps | `Talaria/Stores/ChatStore.swift:3191` — `compose outbox drain deferred — App Lock is covering the app (#323-A)`, `chatLog.notice` (`ChatStore.swift:5`). |
| `send deferred…(#323-A)` | ✅ exists, ⚠️ unreachable under Steps | `Talaria/Stores/ChatStore.swift:1058` — `send deferred — App Lock is covering the app; waiting for unlock (#323-A)` |
| `requestUnlock EXIT…SUCCESS` | ✅ | `Talaria/Core/AppLock/AppLockController.swift:181` — literal is `requestUnlock EXIT attempt=N result=SUCCESS (episode ends, counter reset)`. Grep `requestUnlock EXIT`, not bare `SUCCESS`. |
| UI `Waiting for unlock…` | ✅ | `Talaria/Stores/TalkStore.swift:340` `static let lockedWaitingMessage = "Waiting for unlock…"`. Durability is real: backed by the `isWaitingForUnlock` flag, not a one-shot string write (`TalkStore.swift:216-223` documents exactly the "survives later voice events" property the card checks). |
| `.obscured` FAIL clause | ✅ matches code | `AppLockGate.swift` — "`.obscured` is NOT locked, and that distinction is load-bearing", gate returns false for it. Card's FAIL wording is accurate. |
| `talaria_phone_query` known-accepted | ✅ matches ruling | `Talaria/Services/Support/AppLockGate.swift:36`, `:202` — deliberately not gated; bar 323-C is the tripwire. |

**Corrections needed:**

1. **Setup/Steps 1 — "Control Center → Talk to Hermes" is STALE.** The tile was retitled to
   **"Talk to Talaria"** by #415: `Shared/HermesControlIntents.swift:162` (`static let title:
   LocalizedStringResource = "Talk to Talaria"`, retitle noted at `:158`),
   `TalariaWidgets/Controls/HermesControls.swift:63,66`, dated at
   `Talaria/Core/DeeplinkRouter.swift:60-61`. An operator hunting the old label will not find it.
2. **Two Record markers cannot occur.** `send deferred` and `compose outbox drain deferred` fire
   only when a **chat send** is attempted or an outbox drain is triggered while covered. The Steps
   are voice-only. Either add a step ("while locked, type and send a chat message"), or move those
   two lines under an explicit "only if a send was attempted" heading. As written this is the
   documented scar shape — a Record item keyed on a marker the run cannot emit.
3. **`cover=locked locked=true` is a PRE-state on a scene-phase transition only.** The cover
   *arming* does not print that substring (`refreshCover()`'s own line reads
   `cover none -> locked: new lock episode…`, `AppLockController.swift:215`, and only when
   `episodeAttempt != 0`). The card's script does produce transitions, so it will appear — but do
   not treat its absence during a quiet locked stretch as evidence of anything.

**Cheaper:** the whole PASS bar (`no capture chain HOT inside the locked interval`) is readable
from the log alone by intersecting the two `AppLock` rows with the `capture chain HOT` rows. Only
the `Waiting for unlock…` screenshot genuinely needs the screen.

---

### CARD 415d — "The covered session parks — your CC repro, inverted" — **RUNNABLE**

**Verbose: NOT required** — explicitly by design (`Talaria/Stores/TalkStore.swift:84-90`:
"always on, `.notice`, `privacy: .public`, and NOT behind Verbose Logging").

| Marker | Verdict | Evidence |
|---|---|---|
| `voice session parked — App Lock cover armed mid-flight (#415)` | ✅ **verbatim** | `Talaria/Stores/TalkStore.swift:253`, `Self.log.notice`, subsystem **`org.aethyrion.talaria27`**, cat `Voice` (decl `:91`) |
| `capture chain HOT` (must be absent under cover) | ✅ | as 302-323 above |
| Tile "Talk to Talaria" | ✅ **correct** | this is the one card whose label matches HEAD |
| App Lock ON, grace "Immediately" | ✅ | `AppLockGracePeriod.immediate.displayLabel == "Immediately"`, `Talaria/Services/Support/AppLockCore.swift:26`; UI at `Talaria/Features/Settings/PrivacySettingsScreen.swift:523-556` |
| needs 3120 | ✅ code-wise (count 3147) | but see cross-cutting finding #2 — a Debug build will *say* `1` |

**Two free markers the card does not name — add them, they score step 3 directly:**

- `parked voice session resuming after unlock (#415)` — `Talaria/Stores/TalkStore.swift:289`
- `parked voice session NOT resumed — abandoned under the cover (#415)` — `TalkStore.swift:286`

Both always-on `.notice`, same subsystem/category. **"resumes by itself, exactly once"** becomes a
count of line 289 occurrences — a log verdict instead of an eyeball one. This is the single biggest
cheapening available in the group.

**One caveat to write into the card:** if the pre-start gate is already closed when the intent runs,
the start parks in `deferUntilUnlocked()` instead — and **that path emits nothing at all** (read the
function: it sets `isWaitingForUnlock` and `statusMessage` and awaits, with no log call). So an
absent `#415` park line is *not* automatically a FAIL; it can mean the other, also-correct path ran.
The invariant that holds across both is: **no `capture chain HOT` under the cover.** Score on that.
(The card's own premise — the warm process and the ~1.2 s gate-open window documented at
`TalkStore.swift:211-233` — makes the mid-flight path the likely one, so the line should appear.)

---

### CARD 303ab — "Cold Control Center launch — which engine?" — **STALE-FIXABLE**

**Verbose: NOT required.**

| Marker | Verdict | Evidence |
|---|---|---|
| the log's engine line | ✅ | `Talaria/Services/Support/VoiceEngineRouter.swift:291` — `voice session starting on engine <native\|realtime> (voiceHostPaired=<true\|false>)`, `.notice`, subsystem `org.aethyrion.talaria`, cat `VoiceEngineRouter` (decl `:30`). Ungated, and `:283-290` documents it as "the line a device verdict quotes", emitted unconditionally per session. |
| engine values `realtime` / `native` | ✅ | `Talaria/Models/VoiceState.swift:74-76` — raw values are exactly `realtime` and `native` |
| the #320 indicator | ✅ | `Talaria/Features/Talk/RealtimeVoiceIndicator.swift:3`; consumed at `Talaria/Features/Talk/VoiceOverlayScreen.swift:173` |
| VOID clause (#220, "either arm can't name its engine") | ✅ still meaningful | `VoiceState.swift:209-224`: `engine` is `VoiceEngine?` and **nil is a real state** ("no engine has been selected yet"); the header then reads `VOICE · …`, not `LOCAL VOICE`/`VOICE LINK` (`VoiceOverlayScreen.swift:216-224`) |

**Corrections needed:**

1. **"Control Center → 'Talk to Hermes'" is STALE** → **"Talk to Talaria"** (same evidence as 302-323).
2. **The engine line's trailing field was renamed.** It is now `voiceHostPaired=`; the historical
   spelling `relayPaired=` is still quoted in `TalariaTests/TalkStoreBackgroundRevokeTests.swift:12`
   as the #254-F pin. A card recording the line "verbatim" against the old expectation will read as
   a mismatch. **Grep on `starting on engine`** — that substring is stable across both spellings.

**Cheaper:** the card already offers "the #320 indicator **or** the log's engine line". Prefer the
log for both arms — it is unambiguous, timestamped, and one grep covers cold and warm in a single
pull. The visual indicator read is then optional confirmation, not the verdict.

---

### CARD 254d — "Background during CONNECTING — the revoke" — **STALE-FIXABLE**

**Verbose: NOT required.**

| Marker | Verdict | Evidence |
|---|---|---|
| "the revoke line" | ✅ exists — but **the card never names it** | `Talaria/Stores/AppContainer.swift:1253`: `#118/#254: app backgrounded with a voice session (LIVE\|STARTING) — revoking it`. `containerLog.notice` (`AppContainer.swift:5`), subsystem `org.aethyrion.talaria`, cat `AppContainer`. Ungated. Grep: `#118/#254`. |
| engine line ("void without it") | ✅ | `VoiceEngineRouter.swift:291`, as 303ab |
| header `VOICE LINK · CONNECTING` | ✅ producible | `Talaria/Features/Talk/VoiceOverlayScreen.swift:211-232` `sessionHeaderLabel(engine:connectionState:duration:)`; the `.realtime` + `.connecting` combination yields exactly that string (pinned in `TalariaTests/NativeVoicePipelineTests.swift:375`) |

**Corrections needed:**

1. **Name the marker.** "the log carries the revoke line" is precisely the shape CLAUDE.md warns
   about — an unnamed marker means the next operator greps for a guess. Replace with the literal
   above and expect the **`STARTING`** arm (the card backgrounds during CONNECTING). `AppContainer.swift:1249-1252`
   documents that the arm word exists specifically so a verdict can say which one fired.
2. **Add a car-audio exclusion to Setup.** The revoke is gated by
   `TalkBackgroundRule.shouldEndSession(isSessionActive:isStartingSession:routeHasCarAudio:)` =
   `(isSessionActive || isStartingSession) && !routeHasCarAudio`
   (`Talaria/Services/Support/TalkSessionRules.swift:59-65`). **If the phone is on CarPlay or car
   Bluetooth, the revoke correctly does NOT fire** and the card would score a false FAIL. Setup must
   say "not connected to car audio".
3. **Note the header may read `VOICE · CONNECTING` first.** `engine` is nil until the router stamps
   it (`VoiceState.swift:209-224`), so a cold Control Center start shows the neutral `VOICE ·
   CONNECTING` before flipping to `VOICE LINK · CONNECTING`. Both are inside the window the card
   wants; an operator waiting for the literal string may background later than intended.
4. Tile label: same "Talk to Hermes" → "Talk to Talaria" fix.

**Cheaper:** with the marker named, this card is 100% log-scored — the PASS is
`#118/#254 … (STARTING) … revoking it` present **and** no `capture chain HOT` after its timestamp.
No screenshot needed.

---

### CARD 198ba — "Memo record→play→stop — zero session faults" — **UNCERTAIN**

**Verbose: NOT required** (the marker is not ours).

**The load-bearing marker has ZERO emitters in this repo.** `AVAudioSession_iOS.mm:978` appears only
in **code comments and a test docstring**:

- `Talaria/Services/Support/TalkSessionRules.swift:22` (comment)
- `Talaria/Services/Live/VoiceMemoPlayer.swift:60` (doc comment)
- `Talaria/Services/Live/VoiceMemoRecorder.swift:62` (doc comment)
- `TalariaTests/VoiceMemoAttachmentTests.swift:238` (test doc)

It is an **Apple AVFAudio-internal** diagnostic naming a line number inside Apple's own
`AVAudioSession_iOS.mm`. Consequences:

- **The bar is an ABSENCE bar on a string we do not control**, on a device now running
  `24A5424a` — newer than the OS the original observation was made on. If Apple renumbered the file
  or reworded the fault, the grep returns zero and the card reads **PASS**. That is the project's
  scar inverted: a check that always *succeeds* rather than always fails, which is worse.
- Nothing in our source can confirm the marker is still emittable. This cannot be settled statically.

**What would settle it:** run the memo sheet **deliberately on the main thread path** (or simply
grep the collected archive for the bare filename with **no line number**):
`log show … --predicate 'eventMessage CONTAINS "AVAudioSession_iOS.mm"'` at severity ALL.
- Any `AVAudioSession_iOS.mm:<N>` lines at all ⇒ the mechanism is alive; `978` is a meaningful test.
- The filename entirely absent from a session that exercises the audio session ⇒ the bar is
  uninterpretable on this OS build and the card should record that, not "PASS".

**Card recommendation:** change the grep from `AVAudioSession_iOS.mm:978` to `AVAudioSession_iOS.mm`
and record **every** line number seen. A renumber then becomes visible instead of invisible.

**The premise the card states IS in the code** (so the intent is valid):
- Off-main + awaited: `VoiceMemoRecorder.swift:63-65` (`deactivateAudioSession`), `:68-74`
  (`activateForRecording`); `VoiceMemoPlayer.swift:61-63`, `:70-76`. All via
  `AudioSessionOffMain` (`Talaria/Services/Support/TalkSessionRules.swift:150`).
- Single-flight: `VoiceMemoRecorder.swift:49` (`isTransitioning`), `:56` (`startGeneration`),
  guards at `:102-105`. The card's "double-tap the play button" re-entrancy check maps to a real guard.
- `needs 3022`: satisfied code-wise (count 3147) — see cross-cutting finding #2 on the Debug `1`.

---

### CARD 396r12 — "Local-engine cut-off — who ends the turn?" — **RUNNABLE**

**Verbose: NOT required.**

| Marker | Verdict | Evidence |
|---|---|---|
| `fallback endpointer fired` | ✅ **verbatim prefix** | `Talaria/Services/Live/NativeVoicePipelineService.swift:462` — full literal `fallback endpointer fired (no final from transcriber)`, `Self.logger.notice`, subsystem `org.aethyrion.talaria`, cat `NativeVoicePipeline`. Ungated. |
| `engine native` | ✅ | via `VoiceEngineRouter.swift:291`'s engine line; substring `engine native` matches |
| "OUR 1.35 s watchdog" | ✅ still accurate | `NativeVoicePipelineService.swift:39` — `nonisolated static let endpointSilence: TimeInterval = 1.35` |

**One real hole in the dichotomy — worth writing into the card before it runs.** The emit sits inside
`startEndpointWatchdog()`'s poll loop behind **two guards** (`NativeVoicePipelineService.swift:448-465`):

```swift
guard let self, self.connectionState == .connected else { continue }
guard self.turnTask == nil else { continue }
```

So a cut-off that happens **while a reply is in flight** (`turnTask != nil`) cannot produce the line
*even if our watchdog is conceptually the cause* — the loop simply skips. SPLIT B as written
("line absent across witnessed cut-offs ⇒ Apple's finalizer") therefore has a **third** explanation:
our own watchdog was gated out. Fix cheaply by recording, per cut-off, whether a reply was streaming
at that instant; only cut-offs during user speech with no reply in flight discriminate.

**Cheaper:** already fully log-scored. The only screen work is noting each cut-off's wall clock, and
even that can come from the engine/turn lines' own timestamps.

---

### CARD 3eh34 — "Stop proven from the HOST log · leave-thread-and-return" — **UNCERTAIN**

**Verbose: NOT required.**

**App-side premise: VERIFIED.** The app really does issue the interrupt:
`Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift:1442` builds
`POST /v1/runs/{runID}/stop` inside `hardStopActiveRun()` (`:1430-1465`), on the run's own frozen
endpoint (`:1436-1438`, #285).

**Host-side marker: NOT VERIFIABLE FROM THIS REPO, and the card does not name it.** "Read the HOST's
own log for the interrupt" names no string — the exact shape CLAUDE.md warns about. From CLAUDE.md's
#304 entry the host logs **`exit_code 130`** / **`interrupted_by_user`** on a real hard interrupt;
the card should quote those two so the operator is not guessing at the desk.

**A harder problem — the device log cannot hand you a run_id to correlate with.** Grepping every
`runsTransportLogger` call in `SessionsHermesClient+RunsTransport.swift`: the run id appears only on
**failure/edge** paths (`:556`, `:679`, `:1060`, `:1066`, `:1070`, `:1078`, `:1177`, `:1195`,
`:1455`, `:1511`, `:1517`, `:1524`). There is **no happy-path line naming the accepted run id**, and
`hardStopActiveRun()` logs **nothing on success** — its only log is the error branch:

```
Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift:1455
  "runs: stop request for <id> did NOT reach the host — <err> — NOT marking self-stopped, …"
```

⇒ On a successful stop the device log is silent and carries no run id, so the operator must find the
interrupt in the host log by **timestamp alone**. Two usable consequences for the card:
- **Absence** of the `did NOT reach the host` line is weak-but-real evidence the POST landed; record it.
- If it *is* present, it names the run id — and the card should then grep the host log for that id.

**Also verify at the desk:** "which host" — the Mac gateway is launchd-supervised and a bounce can
leave it headless (CLAUDE.md); confirm the `:8642` **listener**, not the process, before the run.

**Cheaper:** not much — this card's verdict is host-side by construction and that is correct
(#328's lesson). The cheap win is naming `interrupted_by_user` / `exit_code 130` up front.

---

### CARD 312b — "Gateway dead across an app relaunch → transplant notice" — **STALE-FIXABLE**

**Verbose: not required as written; RECOMMENDED (see below).**

| Card's claim | Verdict | Evidence |
|---|---|---|
| "the transplant notice" | ✅ exists | `Talaria/Services/Support/ContextTransplanter.swift:217-219` — `[Context transplanted into a fresh session — <N> tokens]`, and a **no-usage variant with no token clause**: `[Context transplanted into a fresh session]` (`:218`) |
| "priming tokens in the StatusCard" | ⚠️ **the FAIL bar is wrong** | `Talaria/Features/Chat/StatusCardView.swift:96-103` |
| kill-listener / second-kick ops | ✅ matches known hazard | (CLAUDE.md's Errno-48 headless-gateway note) |

**The correction.** `StatusCardView.swift:96-103`:

```swift
// P1 (#90): context-transplant priming, separate from metered
// chat turns — priming is not free and must be visible. "—"
// when the hops reported no usage (unknown, not zero).
if totals.primingHops > 0 {
    statusRow("Priming (\(totals.primingHops) hop…)",
              value: totals.primingTokens > 0 ? "… tokens" : "—")
}
```

So **`"—"` is a documented-correct rendering**, and card **330g** already carries the right rule
("the number arrives LATE and the row re-renders seconds later… never-arrives reads `—`, never `0`").
312b's `FAIL — no transplant notice or no priming tokens` has not been updated and will score a
correct app as a failure. **Rewrite FAIL as:** *no transplant notice, or **no Priming row at all***.
A Priming row reading `—` is a PASS with a note. (The late-arrival mechanism is real:
`ChatStore.swift:790-808` `adoptResolvedPrimingUsage` rewrites both the row's usage and the notice
text when the number lands.)

**Cheaper — and this is a strong recommendation.** Turn **Verbose ON** and type `/usage` instead of
screenshotting the card. `ChatStore.usageDiagnosticReport()` prints, as text:

```
Totals PRESENT · metered <N> · priming <N>
  in … · out … · priming tokens <label> · model time …
```

(`Talaria/Stores/ChatStore.swift:385-392`) — which distinguishes *absent* from *unknown* from *zero*
unambiguously, something the screenshot cannot do. Same evidence, no screen-driving, and it is
pasteable.

---

### CARD 329-330 — "Cold-launch classification + the SESSION block — OBSERVE" — **RUNNABLE**

**Verbose: NOT required** (the `/usage` half is the superseded #330 step the card tells you to skip).

**Nothing stale.** The #329 fix is present at HEAD, so the operator will be on the post-fix shape and
the card's "on build 2998 (pre-fix) you'd still see the old Retry shape" is now historical only:

- `Talaria/Stores/ChatStore.swift:959-993` `restorePendingRunFromRecordIfPossible` — the
  reconcile-first path (Owen's 329-C ruling, named in the doc comment)
- `Talaria/Models/PendingRunRecord.swift`, `Talaria/Services/Support/UserDefaultsAppPersistenceStore.swift:12`
  — the durable record that survives process death

**Two always-on markers the card does not name — this is the cheapening.** Both `chatLog.notice`,
subsystem `org.aethyrion.talaria`, cat `ChatStore`, **ungated**:

| Line | Marker | Scores |
|---|---|---|
| `ChatStore.swift:992` | `cold load: durable run record found — consulting the run's own status before classifying (#329)` | *the reconcile actually ran* — distinguishes the fixed shape from the old guess-first shape without reading the screen |
| `ChatStore.swift:1009` | `cold-load recovery concluded without an answer — restored row settled failed (#329)` | *the row was settled by verdict, not by guess* — this is the honest-`.failed` terminal |

With these, most of step 1's "Record EXACTLY what's offered" becomes a log read; the screen is then
only needed for the **answer count** (the actual dup bar) and the airplane arm.

**Caveats to carry:** the "#330 half is SUPERSEDED, skip step 4" instruction is correct and matches
the code (the `openSession` wholesale replace is real — `ChatStore.swift:3643` + the seam-2 line
built at `:448-462`). The airplane arm has **no marker** and stays screen-scored.

---

### CARD 330g — "The SESSION block SURVIVES the reopen" — **RUNNABLE**

## ⚠️ VERBOSE LOGGING IS MANDATORY, AND FAILING TO SET IT PRODUCES A *PLAUSIBLE WRONG ANSWER*, NOT AN ERROR.

`/usage` is intercepted only under the verbose gate:

```swift
// Talaria/Features/Chat/ChatScreen.swift:1721
if TalariaLog.isVerbose, command.name == "usage", argument?.isEmpty ?? true {
    appendSystemMessage(chatStore.usageDiagnosticReport()); return
}
```

and the command itself only exists in the local catalog under the same gate
(`Talaria/Models/SlashCommand.swift:104-123` `verboseDiagnosticCommands`, `:121-123`
`localCommandsIncludingDiagnostics`). **With verbose OFF, `/usage` falls through to the Hermes agent
pass-through** (`ChatScreen.swift:1726-1735`) **and the HOST answers with its own `/usage`.** The
operator gets a real-looking report that is not this instrument. Add a tell to the card:

> **If the first line is not `Conversation <8 hex> · rows <N>`, verbose was off — the host answered. Void the run.**

`SlashCommand.swift:102-104` notes it is deliberately **not** `#if DEBUG` (because `ota-stage.sh`
archives Release), so verbose works on any build.

**Every string in the card matches source exactly.** All from `ChatStore.usageDiagnosticReport()`:

| Card text | Source |
|---|---|
| `Totals PRESENT · metered N · priming N` | `ChatStore.swift:385-387` |
| `Totals ABSENT · metered 0 · priming 0 · SESSION BLOCK HIDDEN` | `ChatStore.swift:398` |
| `Carriers usage 1` | `ChatStore.swift:417-422` (`Carriers usage N · turnDuration N · servingModel N · isContextPriming N`) |
| `· system · … · PRIMING` row | `ChatStore.swift:432,438` — row format `  #N · <sender> · <usage> · <dur> · <model> · <PRIMING\|—>`; `system` is the literal raw value (`Talaria/Models/MessageSender.swift:11`) |
| `Conversation <id>` (must differ after reopen) | `ChatStore.swift:380-381` |
| `[Context transplanted into a fresh session — N tokens]` | `Talaria/Services/Support/ContextTransplanter.swift:219` |
| status card `Priming (1 hop)` | `Talaria/Features/Chat/StatusCardView.swift:99` — `"Priming (\(hops) hop\(hops == 1 ? "" : "s"))"` |
| `Est. cost` | `StatusCardView.swift:107-113` |

**The three `#330 seam` lines all exist — and all three are `verboseNotice` (`.notice`, verbose-gated,
survives `log collect` by design):**

| Seam | file:line | Literal prefix |
|---|---|---|
| 1 | `Talaria/Services/Live/SessionsHermesClient.swift:690-695` | `#330 seam 1 · fetchSessionConversation '<id>': stored N → mapped N (refused N) · roles … · rows carrying usage 0 …` |
| 2 | emitted `Talaria/Stores/ChatStore.swift:3643`; built `ChatStore.swift:448-462` | `#330 seam 2 · openSession '<id>' REPLACE: departing [rows … · metered … · priming … · totals PRESENT\|ABSENT · id …] → arriving [...]` |
| 3 | `Talaria/Stores/ChatStore.swift:2682-2686` | `#330 seam 3 · priming notice MINTED: sender=system · isContextPriming=true · usage … · servingModel …` |

The card's `grep "#330 seam"` → "three lines tell the story" and its FALSIFIED clause's
`grep "#330 seam 2"` are both **exactly right**.

**Two small clarifications worth adding:**

1. **Verbose must be ON *during* the run, not merely at pull time.** `verboseNotice` short-circuits
   at emit (`TalariaLog.swift:83`); flipping the toggle after the fact recovers nothing.
2. **Step 2's expected transcript string has a nil-usage form.** Before the priming usage resolves
   the notice reads `[Context transplanted into a fresh session]` with **no** `— N tokens` clause
   (`ContextTransplanter.swift:218`); it is rewritten to the token form when the number lands
   (`ChatStore.swift:803-808`). Match on `[Context transplanted into a fresh session`, not the full
   token string, or the step can read as a miss on a correct app.

**Cheaper:** already the cheapest card in the group — three text pastes plus one log grep. Note that
the `/usage` text output makes the status-card screenshots optional: `Totals … · metered … · priming …`
is the same fact the SESSION block renders.

---

## NOT AUDITED

Nothing in the assigned set was skipped. All ten cards were examined.

**Limits of this audit, stated explicitly:**

- **No build, no run, no log collection** (per constraints) — every finding is static. Absence bars
  (198ba especially) cannot be closed this way.
- **Host-side markers are out of repo.** 3eh34's verdict string lives in Hermes's own log on the Mac
  gateway / OJAMD; nothing here can confirm its spelling. Same for the `hermes talaria pair-qr` /
  `unpair` CLI surfaces other cards reference.
- **UI-surface labels were spot-checked, not swept.** I verified the Control Center tile, the
  `Waiting for unlock…` string, the App Lock grace labels, the `VOICE LINK · CONNECTING` header and
  the StatusCard rows because the cards depend on them. Other on-screen copy in these cards was not
  audited (that is the UI group's job).
- **Log *retention* not assessed.** Per the project's own decay note, app-subsystem rows are evicted
  in hours — the "same-day pull" instruction on 330g/415d/293b is a real constraint I could not verify.
