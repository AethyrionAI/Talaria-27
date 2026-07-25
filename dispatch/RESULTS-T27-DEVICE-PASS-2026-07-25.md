# RESULTS — OPUS-T27 DEVICE PASS

**Build SHA:** `1ea7e23` (contains `b7e47bd` — verified ancestor)
**Device:** whoGoesThere, iPhone 17 Pro Max (iPhone18,2), iOS 27.0, UDID `00008150-000E794C3C47801C`
**Bundle:** `org.aethyrion.talaria27` — installed 2026-07-24 23:42 CDT, built 23:41 same session
**Toolchain:** Xcode-beta4 (27.0), Team DNL25ZFSD2
**Driver:** Owen · **Support:** Claude (Mac Mini)

Outcomes: PASS / FAIL / PARTIAL / UNRUNNABLE. Partials are not rounded up.

**Sessions:** 1 — 2026-07-24 23:42 → 2026-07-25 01:30 CDT, phone corded (A1–A7).
2 — 2026-07-25 afternoon, phone **not** corded (A8). Code under test is unchanged between them:
`1ea7e23..3083cc2` touches only `OPEN_ITEMS.md` and two `dispatch/` files, zero Swift.

---

## Preflight

| Service | Mac Mini (100.79.222.100) | OJAMD (100.110.102.59) |
|---|---|---|
| Relay `:8000` | **UP** — `/v1/health` 200, env `production` | **UP** — `/v1/health` 200, env `development` |
| Gateway `:8642` | **UP** — 401 on `/api/sessions` (auth-gated, alive), PID 10405 `hermes gateway run --replace` | **UP** — 401 on `/api/sessions` |
| Shim `:8765` | **UP** — 401 on `/models`, PID 1880 `shim.py` | **DOWN** — connect timeout, no listener |
| Connector | **UP** — PID 10423 `hermes-mobile-mcp` under watchdog | **UNVERIFIED** — not reachable from the Mac |

Notes:
- Relay has no `/health`; the real route is `/v1/health`. A 404 on `/health` is not an outage.
- Both extensions embedded in the installed build: `TalariaShare.appex`, `TalariaWidgets.appex`.
- `idevicesyslog` capture running, filtered to: `Talaria 27`, `TalariaWidgets`, `TalariaShare`,
  `chronod`, `appintentsd`, `siriappintentsd`, `AppIntentsLiveEntityService`, `ControlCenter*`,
  `SpringBoard`, `apsd`, `useractivityd`, `kernel`.

### Preflight defects

1. **OJAMD shim `:8765` is down.** Blocks nothing in this pass (A11/#116 targets the Mini, whose
   shim is up; model switching is not a pass item), but it is a stated preflight condition and it
   is not met. Restart needs elevation — Owen pastes.
   **Cleared at the start of session 2** — OJAMD shim `:8765`, gateway `:8642` and relay `:8000` all
   answer. The preflight condition is now met on both hosts.

---

## GROUP A — both hosts paired

| # | Item | Check | Result | Notes |
|---|---|---|---|---|
| A1 | #58 #179 | Control Center handoff | **FAIL** | Every tap rejected by the OS. Root cause below. |
| A2 | #151 | Test Connection | **PASS** | All 4 branches verdict'd correctly. Detail below. |
| A3 | #152 | Pairing & Devices naming | **PASS** | Title, "Pair New Device (QR)", leads with connected state. |
| A4 | #153 | Profile menu + delete confirm | **PASS** | All stated criteria met. Declared Cancel button does not render — see below. |
| A5 | #172 | Deliver picker return path | **PASS** | USE LIST returns; typed value survives as `home (custom)`, checkmarked, still selected. |
| A6 | #128 #129 | Voice preview mid-session | **UNRUNNABLE** (mid-session half) | No UI path reaches Settings during a session. See DOC-2. |
| A7 | #124 | Face ID app lock (7 checks) | **PASS 7/7** | Incl. the two unit tests can't see (app-switcher cover, cover-above-sheet). #7 re-run after granting authorization: 3 pushes delivered, 0 drops, banner shown, **UI stayed locked**. |
| A8 | #123 | Share extension (7 checks) | **PASS 6/7**, 1 **UNRUNNABLE** | Every runnable check passed. The video check is impossible by construction — see DOC-3. Size guard verified separately with a valid fixture. |
| A9 | #112 | Comic Book adaptive theme | **PASS** | Live re-skin on the system Light/Dark toggle, no relaunch. Both known seams accepted as-is by Owen. All 31 app icons present, Lane L's 13 in their own Special Edition / Midnight Marquee sections. |
| A10 | #81 | Lock-screen reply | **BLOCKED** | Cannot run until the notification-tap crash is fixed — same delegate method. |
| A11 | #116 | Shim token auto-fill | **UNRUNNABLE** as written | The documented path cannot establish the check's own precondition — see DOC-4. Infrastructure verified healthy; the dispatch's restart step was unnecessary. |
| A12 | #133 | Push registration idempotency | **NOT RUN** | Strong prior evidence already gathered — see the ×4 side finding (36 device rows / 1 phone). |

### A1 — FAIL · `openAppWhenRun is not supported in extensions` (iOS 27)

**Verdict: FAIL, deterministic, both controls, every tap.** A1's "EXPECTED, NOT A FAIL" clause does
**not** apply — this is not #179's cold-start swallow. The OS names the reason explicitly and fails
identically on warm taps.

**What the log shows.** Four taps, four hard failures ~6–11 ms after action start:

| # | Control | Action start | Failure | Δ |
|---|---|---|---|---|
| 1 | Ask Hermes | 23:47:28.022907 | 23:47:28.029473 | 6.6 ms |
| 2 | Ask Hermes | 23:47:31.464153 | 23:47:31.470019 | 5.9 ms |
| 3 | Talk to Hermes | 23:47:36.278487 | 23:47:36.288942 | 10.5 ms |
| 4 | Talk to Hermes | 23:47:39.891609 | 23:47:39.898877 | 7.3 ms |

```
chronod(ChronoCore) <Error>: Failed to execute LNAction with error: ...runnerClientError(
  Error Domain=LNContextErrorDomain Code=2001
  "openAppWhenRun is not supported in extensions")
SpringBoard(ChronoUIServices) <Error>: [[...control.askHermes:-]:Live]
  Button control action failed with error: ... Code=2001
SpringBoard(ControlCenterUIKit) <Error>: Failed to perform control ... action with error: ... Code=3
```

**`perform()` never ran — zero times.** The `handOffToApp` line
(`"…perform fired — handing off hermes://chat"`) appears 0× across the whole capture. LinkServices
goes `Idle → Connecting → Completed` and errors out *before* dispatching into the extension, so
`ControlHandoffStore` is never written and the app is never launched.

Capture validity control: app-authored `os_log` **is** visible in this session — 98 lines tagged
`Talaria 27(Talaria 27.debug.dylib)` (e.g. `handleSystemLaunch: entered`). The widget extension
produced **zero** lines from its own code. The absence is real, not a logging artifact.

**Regression, and where it came from.** The line is 5 hours old:

| Commit | Change |
|---|---|
| `de46bb9` | original: `openAppWhenRun = true` **+** returned `OpenURLIntent` |
| `6174a14` | **removed** it — "conflicted with the OpenURLIntent result … Do not re-add it" |
| `a62503f` | **re-added** `openAppWhenRun = true` (ships in `b7e47bd`, this build) |

`a62503f`'s reasoning — that with a plain `IntentResult` there is "no second mechanism left to
compete with" — is sound about *competition* but lands on an API iOS 27 refuses in an extension
context at all. Both the old shape and the new shape are dead; they just die differently.

**The unit suite is green on a control that is 100% dead.**
[HermesControlsTests.swift:28](TalariaTests/HermesControlsTests.swift:28) was flipped in the same
change to `#expect(OpenHermesChatIntent.openAppWhenRun == true)`. It asserts a static constant the
OS rejects at dispatch, so it can never catch this. Whatever the fix, that test needs to stop
pinning `openAppWhenRun`.

**SDK facts (Xcode-beta4, iPhoneOS 27 SDK, deployment target iOS 27.0 — no availability gating
needed):**

- `openAppWhenRun` is `@available(iOS, deprecated: 26.0, message: "Please provide 'supportedModes' instead")`
- `IntentModes` — `.background`, `.foreground` (`.immediate` / `.deferred` / `.dynamic`)
- `allowedExecutionTargets: IntentExecutionTargets` is `@available(anyAppleOS 27.0, *)`, with
  `.default`, `.main`, `.appIntentsExtension`, `.widgetKitExtension`

The `ExecutionTargets.main` upgrade path named in
[HermesControls.swift:34-36](TalariaWidgets/Controls/HermesControls.swift:34) as "verify the SDK
shape on a Mac session first" — **verified present and usable at this deployment target.** Moving
execution to `.main` would also make the whole `ControlHandoffStore` app-group indirection
unnecessary, since the real app intents could then perform in the app process. Not attempted during
the pass; recorded as the candidate fix.

### A2 — PASS · all four branches produce a correct, fast, named verdict

| Fixture | Expected branch | Observed |
|---|---|---|
| OJAMD `:8642` (live) | `.passed` | `ONLINE` + host + "answered the Sessions API" |
| Mac Mini `:8642` (live) | `.passed` | `ONLINE · 31 MS` + host + "answered the Sessions API" |
| `100.69.76.52:8642` — offline tailnet node | `.timedOut` | **`NO ANSWER`** within 5s + "No reply within 5s…" |
| `100.79.222.100:8641` — live host, dead port | `.refused` | **`REFUSED`**, instant + "Nothing is listening on that port…" |

The reported host tracked the configured Base URL in every case, and the latency line
(`ONLINE · 31 MS`) renders as designed — so the dispatch's "host **and** latency" criterion is met
in full, not half.

**Method note — the host was NOT stopped.** Attempts to kill the Mac Mini gateway were blocked by
the permission classifier; the gateway ran untouched (PID 18507) for the whole check. The two
failure branches were driven by address fixtures instead, verified from the Mac first:
`100.69.76.52:8642` drops with no RST (curl: 8.0s, no response) and `100.79.222.100:8641` refuses
instantly (curl: 1.9 ms, exit 7). These drive the same `URLError` codes the probe maps
(`.timedOut` / `.cannotConnectToHost`), and they cover strictly more than stopping the gateway
would have — a stopped gateway yields only `REFUSED`, never the black-hole case
[`probeTimeout = 5`](Talaria/Features/Settings/UplinkSettingsScreen.swift:380) exists for.

### A3 — PASS

Title **Pairing & Devices**, add action **Pair new device (QR)**, and the screen leads with
connected state ("Your Hermes agent is ready") rather than only offering to add. No trace of the old
label on this path.

The surviving `"Pair Device"` at
[ConnectHermesScreen.swift:206](Talaria/Features/Onboarding/ConnectHermesScreen.swift:206) is
**onboarding**, outside A3's scope. Owen's call, 2026-07-25: correct as-is — onboarding genuinely
only offers to add, so the string matches but the situation differs. **No item.**

### A4 — PASS, with one unintended deviation

All three stated criteria met: the `⋯` menu button is visible without long-pressing, the same
actions remain on long-press, and Delete confirms with the message naming the removed credentials
and "Other profiles are untouched."

**Deviation — the declared Cancel button does not render.** All three dialogs on this screen declare
`Button("Cancel", role: .cancel)`
([:130](Talaria/Features/Settings/ServerSettingsScreen.swift:130),
[:150](Talaria/Features/Settings/ServerSettingsScreen.swift:150),
[:168](Talaria/Features/Settings/ServerSettingsScreen.swift:168)); on device the Delete confirm
shows no Cancel, and dismissal is tap-outside only.

Not a fail against A4's criteria — the confirmation happens and reads correctly — but it is a
code/behavior mismatch on a **destructive** action, and tap-outside is far less discoverable than a
button, particularly under VoiceOver.

**Cause — discriminated on device, 2026-07-25.** Two hypotheses were live: (a) the three stacked
`confirmationDialog` modifiers
([:117](Talaria/Features/Settings/ServerSettingsScreen.swift:117),
[:134](Talaria/Features/Settings/ServerSettingsScreen.swift:134),
[:154](Talaria/Features/Settings/ServerSettingsScreen.swift:154)) colliding, or (b) an iOS 26/27
presentation change that drops Cancel by design.

The *Forget Pairing* dialog was checked: it shows only "Forget Mac Mini Pairing" — **no Cancel
either.** Forget is the **middle** modifier, so (a) is refuted (a stacking collision would cost the
*last* modifier, not the middle one). Both dialogs render their correct title and message and drop
only the cancel button ⇒ **(b), a presentation-style change.**

**Consequence:** the three `Button("Cancel", role: .cancel)` declarations are dead code that no
longer describes what ships. Either delete them so the source matches the device, or move these
confirms to `.alert`, which still renders an explicit cancel — the better option for destructive
actions under VoiceOver. Needs an item.

### A6 — UNRUNNABLE as written (mid-session half)

**Owen, on device: "There's no way to get to settings in an audio session without ending the session
first."** Confirmed in source, and it is structural, not an oversight in how the check was attempted.

`VoiceOverlayScreen` is presented as a **`fullScreenCover`**
([ContentView.swift:96](Talaria/ContentView.swift:96), [:153](Talaria/ContentView.swift:153)) — it
covers the entire UI, so Settings cannot be reached while it is up. And its
[`.onDisappear`](Talaria/Features/Talk/VoiceOverlayScreen.swift:91) unconditionally tears the session
down 500 ms after dismissal; the sole exemption is `showLiveCameraOverlay`, the nested camera cover.
Its own header line says it: *"Auto-starts a voice session on appear and tears it down on dismiss."*

So `talkStore.isSessionActive` can never be `true` while `VoiceSettingsScreen` is on screen, which
means [`previewInstance(sessionActive: true, …)`](Talaria/Services/Live/SpeechOutputService.swift:166)
— the native-instance branch that **is** the #129 fix — is not reachable through the documented path.

**And it never was, on any build this fix has existed on.** Dated:

| Date | Commit | |
|---|---|---|
| 2026-04-05 | `3d090e8` | "fix session not ending on dismiss" — teardown behavior lands |
| 2026-04-06 | `e40469f` | session-persistence follow-up |
| **2026-07-20** | `0e669af` | **fix(#129)** — mid-session previews ride the session-less instance |

The teardown predates the fix by **three months**. A6's PATH could not have worked on any build
since April.

**Unresolved, worth an item — not device time.** Two readings, and this pass cannot choose between
them: either #128 was originally reproduced by some route other than Settings-during-session (in
which case A6 needs that route written down, and #129 may still be load-bearing), or #129 guards a
state the UI can no longer produce (in which case it is defensive dead code and the item should be
closed as unreachable rather than "verified"). What is certain is that **the documented path is
closed**, and that no one can verify #129 by tapping.

**Runnable half — outside a session, previews at full `.playback` fidelity (#130):** see table.

### A8 — PASS 6/7, one check unrunnable by construction

_Run 2026-07-25 session 2. Phone not corded for this block, so no syslog — every A8 check is
Owen-visible by design, so nothing was lost except failure diagnostics._

| # | Check | Result | Note |
|---|---|---|---|
| 1 | Safari → Share → URL in composer | **PASS** | |
| 2 | Photos → Share → image chip | **PASS** | |
| 3 | Files → Share a file → file chip | **PASS**, substituted | `.txt`, not the PDF the doc names. See gap below. |
| 4 | Rapid successive shares all land | **PASS** | Three shares, all merged into the composer. Order not separately confirmed. |
| 5 | ~25 MB video → polite refusal | **UNRUNNABLE** | Impossible by construction — **DOC-3**. |
| 6 | Share while force-quit → lands next launch | **PASS** | |
| 7 | `hermes://ask` still works | **PASS** | Warm path. Two sub-cases unexercised — below. |
| — | **Extra:** oversize guard, valid vehicle | **PASS** | Not scored as A8-5. See below. |

**Landing in the newest chat rather than a new one is correct, not a defect.** Observed on 1, 2, 3
and 6 and checked against source: the drainer produces a `ShareComposerSeed` and
`ChatStore.seedComposerFromShare` parks it in a slot; nothing in the path creates or selects a
session. A8's own criterion is "lands in the composer", which is what happens.

**DOC-3 — the video check cannot be performed, by two independent mechanisms.** A video can never
reach the size guard:

1. `project.yml:444-448` declares `SupportsWebURL / SupportsImage / SupportsFile / SupportsText` —
   there is **no `NSExtensionActivationSupportsMovieWithMaxCount`**. Photos therefore never offers
   Talaria for a video at all. This is exactly what Owen observed ("videos don't give an option to
   share").
2. Even routed in from Files, `StageableTypeCatalog.isStageable` accepts only `image/*`, 14 text
   MIME types and `application/pdf`; `.mov`/`.mp4` map to `application/octet-stream`. That fails the
   **type** guard at [ShareViewController.swift:209](TalariaShare/ShareViewController.swift:209),
   which returns before the **size** guard at :214. A video's refusal would read "Talaria can't
   accept this file type" — never "Too large to hand off".

The dispatch asked for a check the app makes impossible. Not a product failure; whether the absence
of video support is itself worth an item is a separate product question, not a pass result.

**Extra — the size guard does work, verified with a vehicle that can reach it.** A valid 25.07 MiB
single-page PDF (uncompressed DeviceRGB noise, exact byte count, generated on the Mac and delivered
via iCloud Drive) was shared from Files. Result, verbatim on device:

```
Too large to hand off (limit 21 MB)
```

That is the size branch at `ShareViewController.swift:214`, rendering in the share sheet — no crash,
no silence. **Recorded as its own result, not as A8-5**, per the dispatch's rule that a substitute
check does not score the original.

**Minor, from that string:** the cap is 20 MiB (`20 * 1024 * 1024` = 20,971,520) but the label runs
through `ByteCountFormatter(countStyle: .file)`, which is base-10, so it prints **21 MB**. A user
handed "limit 21 MB" who tries a 20.5 MB file is refused by a limit the UI told them they were
under. Cosmetic, one call site, worth a line in #123 rather than its own item.

**Gaps this block leaves open — recorded, not rounded up:**

- **PDF's accept path is untested.** Check 3 substituted `.txt`, and the only PDF put through the
  extension was deliberately oversize and correctly refused. PDF is one of only three stageable
  families, so the family that matters most for documents has been proven to *refuse* and never
  proven to *accept*. One small PDF closes this.
- **Share ordering** (check 4) was not separately confirmed. `pendingEnvelopes()` sorts by
  `createdAt` ascending and the drainer joins with `\n`, so ordering is a real assertion the check
  is meant to make; three shares landing is necessary but not sufficient.
- **`hermes://ask` cold path.** Check 7 passed warm, from a non-Chat tab with the app backgrounded —
  the `onChange` consumption path. The cold-launch path consumes via a separate `onAppear` and is
  unexercised.
- **The ask/share collision named in the check's own parenthetical was never exercised** — the
  earlier shares had already drained. The two slots have deliberately opposite contracts:
  `consumeShareSeed` **appends**, `consumeComposerSeed` **replaces**
  ([ChatScreen.swift:1161](Talaria/Features/Chat/ChatScreen.swift:1161)). So an ask-seed landing on
  a pending share should wipe the share's *text* while its attachments survive in a different array.
  The replace is called "by contract" at :1169, so this may be intended — but the check exists to
  ask the question, and the question is still open.

**Two "FAIL"s reported during this block were test-harness errors, not app defects**, and are
recorded as such rather than as findings: the first `hermes://ask` attempt was typed with unescaped
spaces, which Safari's omnibox resolves as a search rather than a URL; the second dropped the `q`
parameter name (`?=hello`), which parses to an empty value and is correctly guarded out by
`seedComposer`. Verified against the real code path — `hermes://ask?=hello` yields `host = ask`,
`q = ""`; `?q=hello` yields `q = "hello"`; `%20` survives encoding. The app behaved to spec in all
three cases.

### A11 — UNRUNNABLE as written · the path cannot create the precondition

**The dispatch's setup step was unnecessary, and was not performed.** It says "restart relay +
connector on the Mini before this". Checked instead of assumed — the Mini relay already holds a
complete, current descriptor, read straight out of `hermes_mobile.db`:

| field | value |
|---|---|
| `gateway_base_url` | `http://100.79.222.100:8642` |
| `shim_base_url` | `http://100.79.222.100:8765` |
| `shim_token` | 43 chars, **byte-identical** to `~/.hermes/talaria_shim_token` |

That token authenticates for real: `GET /models` on the live shim returns **HTTP 200, 6 models**.
The connector is connected (`last_seen_at` current). A restart would have republished an identical
descriptor and would not even have bumped `provisioning_updated_at` — `_apply_host_provisioning`
writes only on change. **No service was restarted or stopped.**

**Why the check cannot run.** `ProvisioningService.applyProvisioning` fills conservatively:
`shimBaseURL` and `gatewayBaseURL` only when blank, and the token only when
`stored.isEmpty || (mode == .refresh && stored != token)`. Owen ran the documented path — forget the
Mac pairing, return to the profile — and reported the shim token **still present**, models
refreshing successfully against it.

That is correct behaviour, not a defect. `PairingStore.forgetPairing` clears the paired relay
configuration and the session; it never touches Keychain material. The app states the distinction
itself at [ServerSettingsScreen.swift:359](Talaria/Features/Settings/ServerSettingsScreen.swift:359)
— Delete "purges Keychain credentials, so it is strictly more destructive than Forget Pairing."
The shim token is Keychain material, so Forget leaves it by design.

So after the documented path the stored token is non-empty and unchanged: `shouldWrite` is false on
both clauses, nothing is written, and **there is nothing for the check to observe**. A pass and a
failure are indistinguishable here — which is what makes it unrunnable rather than a FAIL.

**The path that would work**, for whoever picks this up: **Delete** the profile (the only action
that purges the Keychain), then re-pair by QR against an empty token slot. Caveat worth stating
before someone runs it — Delete removes the profile outright, so that exercises "provision a new
profile", which is adjacent to but not identical to "re-pair an existing one". If #116's contract is
specifically about re-pairing an existing profile, the app currently offers **no** route to an empty
token slot for an existing profile, and that gap is the thing to resolve before rewriting A11.

**Not attempted:** the OJAMD half, which the dispatch gates behind the `ojamd-deploy` rebase and
Owen's manual approval. Asked; the session paused before it was answered.

### 🔴 MAJOR FINDING — notifications are silently dead: authorization is `NotDetermined`

Surfaced while staging A7 check 7. **Every user-visible notification on this build is being dropped
by iOS**, and the app reports itself healthy while it happens.

The push reached the device and SpringBoard refused it, naming the reason:

```
SpringBoard(UserNotificationsCore): [org.aethyrion.talaria27] Dropping notification 6C7F-699F
  as it's not authorized with status 'NotDetermined'
SpringBoard(UserNotificationsCore): [org.aethyrion.talaria27] NOT delivering user visible push
  notification 6C7F-699F [ error=UNErrorDomain Code=2003 "Repository could not save notification.
  Source is not authorized." UserInfo={UNAuthorizationStatus=NotDetermined} ]
```

**`NotDetermined`, not `Denied`** — the app has never *asked*. A fresh install resets notification
authorization, and this build was installed at 23:42 today.

**Why it was never asked.** The prompt is deliberately deferred (#31 "contextual priming") to the
first *long run*, and both triggers are narrower than they look:

- [`ChatStore.swift:408`](Talaria/Stores/ChatStore.swift:408) — `if continuedSend != nil`, but two
  lines up `continuedSend = attachments.isEmpty ? nil : beginContinuedSend?(…)`. **This path fires
  only for messages carrying attachments.** A plain text message, however long-running, never
  triggers it.
- [`ChatStore.swift:623`](Talaria/Stores/ChatStore.swift:623) — fires when a run detaches, and only
  while foregrounded ("best-effort" by its own comment).
- [`LocalNotificationService.swift:15`](Talaria/Services/Live/LocalNotificationService.swift:15) —
  `guard !didRequestAuthorization` is an in-memory flag, so at most one attempt per app launch.
- Otherwise only [`PermissionsStore.requestPermission(.notifications)`](Talaria/Stores/PermissionsStore.swift:46),
  reached from onboarding or the Privacy screen.

So after any reinstall, a user who sends plain-text messages and never happens to have a run detach
while watching gets **no notifications at all, forever**, with nothing on screen to say so.

**The diagnostics show a false green.** Owen checked during the pass: the app's own Notifications
settings and About & Diagnostics both report *active* and *relay registered*. Both are true and both
are irrelevant — `registerForRemoteNotifications()` yields an APNs token and a relay registration
**independently of user authorization**. The app is reporting the transport as healthy while iOS
discards every notification it produces. Against this project's "real data only, show `—` where a
value isn't knowable" convention, a Notifications panel that cannot see
`UNAuthorizationStatus` is asserting something it does not know.

**Blocks:** A7 check 7, **A10 / #81 entirely** (no completion push can arrive), and the push half of
A12. Needs its own item, and probably a high one — it is a total, silent loss of a headline feature
on any fresh install.

### 🔴 MAJOR FINDING — tapping any notification crashes the app (main-thread violation)

Exposed the instant notification authorization was granted. Previously unreachable: with
authorization `NotDetermined` no notification was ever delivered, so no one could tap one. **Two
defects stacked, the first hiding the second.**

**Crash report:** `Talaria 27-2026-07-25-005838.ips`, iPhone OS 27.0 (24A5390f), app 1.0.0.
`EXC_CRASH / SIGABRT`, "Abort trap: 6", `NSInternalInconsistencyException` —
**"Call must be made on main thread"**. 50 ms after the tap-launch.

Symbolicated faulting thread — **thread 13, not main**:

```
10  Foundation              -[NSAssertionHandler handleFailureInMethod:object:file:lineNumber:description:]
11  UIKitCore               -[UIApplication _performBlockAfterCATransactionCommitSynchronizes:]
12  UIKitCore               -[UIApplication _updateStateRestorationArchiveForBackgroundEvent:…windowScene:]
13  UIKitCore               -[UIApplication _updateSnapshotAndStateRestorationWithAction:windowScene:]
14  Talaria 27.debug.dylib  @objc closure #1 in HermesAppDelegate.userNotificationCenter(_:didReceive:)
…
22  libswift_Concurrency.dylib  completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*)
```

**Mechanism.** [`userNotificationCenter(_:didReceive:)`](Talaria/AppEntry.swift:141) is declared
`nonisolated … async`. The compiler bridges that async method to the ObjC
completion-handler form; frame 14 is that generated bridging closure. When the async body finishes,
the closure invokes UIKit's completion, which does snapshot + state-restoration work — **on
whatever thread the continuation resumed on**, a Swift concurrency worker (frame 22), never the main
thread. UIKit asserts and aborts.

`handleNotificationTap` itself is fine — it hops to the main actor. The violation is in the
**return** path, after the body completes, which is why nothing in the app's own code appears above
frame 14.

**This is the cost of a deliberate choice**, and the code says so at
[AppEntry.swift:137-140](Talaria/AppEntry.swift:137): the async variant was picked so the system
would keep a possibly scene-less process alive for the #47 headless-reply ordering, "with no
completion handler to send across an isolation boundary". That reasoning holds for the **reply**
branch. It was not sound for the **tap** branch, which returns into UIKit work that is main-thread
only.

**⚠️ CORRECTION, 2026-07-25 session 2 — this fix was already shipped, and it does not work.**

This section originally proposed "annotate the delegate method `@MainActor`" as the candidate fix.
Checking the history before writing it into a dispatch showed that had already been done:

```
22f92e1  fix(#147): @MainActor on HermesAppDelegate — notification completion bridge must fire
         on main; cold launch-by-notification hit UIKit state-restoration assert off-main
```

`git merge-base --is-ancestor 22f92e1 1ea7e23` → **true**. The fix was **in the build that crashed**.
`22f92e1` is a one-line commit: it adds `@MainActor` to the **class**
([AppEntry.swift:87](Talaria/AppEntry.swift:87)).

**Why it has no effect on this crash:** both `userNotificationCenter` overloads are declared
`nonisolated` ([AppEntry.swift:124](Talaria/AppEntry.swift:124) and
[:141](Talaria/AppEntry.swift:141)), and `nonisolated` on a member explicitly opts that member out of
its type's actor isolation. The class annotation cannot reach them. #147 is merged, marked fixed, and
the defect it names still reproduces — on 2026-07-25 00:58, on a build containing it.

**The fix has to remove `nonisolated` from the tap overload**, not annotate the enclosing type. Still
needs checking against the #47 headless path before adopting — that path has no window scene, so it
may not hit the same UIKit work, but it must not lose the process-lifetime guarantee the async form
was chosen for. Reopening #147 with this evidence is the first step, not writing a new item.

**Blocks:** A7 check 7's tap half, and **A10 / #81** — the lock-screen reply path runs through the
same delegate method.

### SIDE FINDING — the ×4 push duplication has an app-side root, not a relay-side one

Raised by Owen mid-pass ("why does it fire 4 notifications every time?"). The dispatch scopes ×4
delivery to **#143, relay-side, different repo**. Evidence from the Mac Mini relay DB says the relay
is behaving correctly and the root is **app-side device-identity churn**.

**Mac Mini relay DB, 2026-07-25:**

| Measure | Value |
|---|---|
| `push_registrations` rows | **36** |
| …of those, `is_active = 1` | **36** (every one) |
| distinct `apns_token` | **4** |
| distinct `device_id` | **36** |
| `devices` rows | **36**, across only **3** distinct `device_name` |

One physical phone has registered as **36 separate devices**, each carrying its own active push
registration, collapsing onto just **4** real APNs tokens (≈ 4 install generations).

**The relay then fans out per registration, not per token.**
[`send_push`](relay/app/main.py:1951) loops `for reg in registrations:` and calls
`send_alert_push(reg.apns_token, …)` with **no dedup by token**. A single
`POST /v1/push/send` fired during this pass returned:

```json
{"data":{"sent":36,"total":36}}
```

36 APNs sends from one logical notification. Note also that all 36 reported `SENT` — so the
`PushResult.TOKEN_INVALID → reg.is_active = False` reaping at
[main.py:2020](relay/app/main.py:2020) never fires, and the pile-up is never self-limiting.

**"4 distinct tokens ⇒ ×4 banners" — HYPOTHESIS REFUTED.** The push fired above was the experiment
and it came back negative: Owen received **0**, and the device log shows exactly **one** of the 36
sends actually reached the phone — token `df04a6a7…` (the newest registration, `c2c28294`):

```
00:44:55.494342 apsd: receivedPushWithTopic org.aethyrion.talaria27 token df04a6a7…
00:44:55.497100 SpringBoard(ApplePushService): Delivering message from apsd
```

The other 35 went to tokens this device no longer holds — APNs 200s them and discards them silently,
which is also why the `TOKEN_INVALID` reaping never fires and the rows never get cleaned up. So only
**1** of the 4 tokens is live, and ×4 is **not** explained by token count. Its real cause is still
unknown, and it must have been observed **before** today's reinstall (see the authorization finding
below — nothing at all is being delivered now).

**What survives:** the 36-registrations-for-one-phone pile-up and the missing per-token dedup in
`send_push` are both real and worth fixing. They are just not the ×4 explanation.

**Consequence for #143:** the relay is faithfully delivering to the registrations it holds. Fixing
the fan-out relay-side (dedup by token) treats the symptom; the pile-up will keep growing while the
app mints a new device identity per launch. That churn is the same root as **A12 / #133**, and it
suggests #143 may be mis-filed as relay-side.

---

## GROUP B — both hosts disconnected

| # | Item | Check | Result | Notes |
|---|---|---|---|---|
| B1 | #61 | Degenerate conversation cards | **NOT RUN** | |
| B2 | #172 | USE LIST absent when disconnected | **NOT RUN** | Positive half passed in A5. |

## GROUP C — connector stopped

| # | Item | Check | Result | Notes |
|---|---|---|---|---|
| C1 | #117 | Health-drain deferral under outage | **NOT RUN** | Needs sensor health collection ON, and Claude to stop the Mini connector. |

## GROUP D — migration reset

| # | Item | Check | Result | Notes |
|---|---|---|---|---|
| D1 | #137 | Fresh-install migration | **NOT RUN** | |

## Optional

| # | Item | Check | Result | Notes |
|---|---|---|---|---|
| — | #130 | TTS fidelity A/B (separate build) | — | |

---

## Document defects found during the pass

_(Per the dispatch: if a check cannot be performed as written, that is a defect in the document.
Recorded here rather than substituted with an improvised check.)_

**DOC-1 — A1 names a control that does not exist.** The dispatch says to add "**Open Talaria**"
and "**Talk to Hermes**". Source ([HermesControls.swift:136-166](TalariaWidgets/Controls/HermesControls.swift:136))
defines exactly two controls, and neither is called "Open Talaria":

| Gallery label (`displayName`) | Symbol | Intent | Destination |
|---|---|---|---|
| **Ask Hermes** | `text.bubble` | `OpenHermesChatIntent` | `hermes://chat` |
| **Talk to Hermes** | `waveform` | `OpenHermesVoiceIntent` | `hermes://voice` |

A1's own PASS criterion ("Talaria opens on the **Chat** tab") matches **Ask Hermes**, so the
intended check is unambiguous — only the label is wrong. Read A1 as "Ask Hermes"; the check is
runnable as intended.

**DOC-2 — A6's mid-session PATH does not exist.** "Start an active voice session, then Settings →
Voice & Talk" cannot be performed: the voice overlay is a `fullScreenCover` that ends the session on
dismiss, and has been since 2026-04-05 — three months before the #129 fix A6 exists to verify. Full
analysis in the A6 section. The outside-a-session half remains runnable and was run.

**DOC-3 — A8's video check is impossible by construction.** "A ~25 MB video → a polite refusal in
the share sheet", flagged in the dispatch as "the one that matters most", cannot be performed: the
share extension declares no movie activation rule, so Photos never offers Talaria for a video; and
video MIME types are not stageable, so a video routed in from Files hits the *type* refusal before
the *size* refusal. Full analysis in the A8 section. The underlying size guard was verified
separately with a 25.07 MiB PDF and is recorded as its own result, not as A8-5.

**DOC-4 — A11's path cannot establish A11's precondition.** "Forget the Mac pairing → re-pair via
QR" does not clear the shim token, because Forget Pairing deliberately leaves Keychain material
alone (only Delete purges it). With a non-empty stored token, `applyProvisioning` writes nothing, so
auto-fill has nothing to fill and pass is indistinguishable from failure. Full analysis in the A11
section, including the Delete-then-re-pair route that would work and the reason it is not a
like-for-like substitute. The dispatch's "restart relay + connector first" step in the same item was
also unnecessary — verified, not assumed, and skipped.

---

## Device / environment state as of the 2026-07-25 01:30 stop

Changed during the pass — carry forward, do not re-derive:

| Thing | State | Changed by |
|---|---|---|
| Installed build | `1ea7e23`, signed device build, 23:42 | Claude (fresh install) |
| **Notification authorization** | **GRANTED** (was `NotDetermined`) | Owen, to unblock A7-7 |
| App Lock | **ON**, grace last set to **After 1 min** | Owen, during A7 |
| Control Center | **Ask Hermes** + **Talk to Hermes** controls added | Owen, during A1 |
| Active profile | **OJAMD**, PAIRED | pre-existing |
| Base URL | restored to original after the A2 fixtures | Owen, verified `ONLINE · 31 MS` |
| Custom DELIVER value | a task carries a `home (custom)` row from A5 | Owen — harmless, clean up if unwanted |
| Sensor health collection | **untouched** — still needs turning ON for C1/D1 | — |

Services: nothing was stopped by Claude (the gateway kill was blocked by the permission classifier;
the A2 failure cases used address fixtures instead). The Mac Mini gateway self-restarted once
unprompted, `10405 → 18507`, cause unknown. **OJAMD shim `:8765` is still DOWN** and still needs an
elevated `Start-Service TalariaModelsShim`.

Background processes: `idevicesyslog` **stopped and confirmed gone**. Nothing else left running.

### Session 2 delta (2026-07-25 afternoon)

| Thing | State | Changed by |
|---|---|---|
| OJAMD shim `:8765` | **UP** — was the one open preflight defect | resolved between sessions |
| OJAMD gateway `:8642` / relay `:8000` | **UP** | — |
| Phone | **not corded** — no syslog for A8; blocks A12 and the diagnostic half of A10 | — |
| iCloud Drive | holds `talaria-oversize-share-test.pdf`, **25.07 MiB** | Claude, for the A8 size fixture — **delete when done** |
| Two Talaria bundles on device | `org.aethyrion.talaria` + `…talaria27` | deliberate fork discriminator; `talaria27` → `talaria` before launch, per Owen. Not a defect. |
| **Mac Mini pairing** | **FORGOTTEN during A11** — Owen returned to the profile and models refreshed, but whether it was re-paired by QR is unconfirmed | Owen, during A11 — **check this first next session** |
| Comic Book theme | selected during A9; app icon unchanged | Owen — cosmetic, revert if unwanted |

Services: nothing stopped or restarted by Claude in session 2 — the A11 restart step was verified
unnecessary rather than performed. No background processes left running (the session-2
`idevicesyslog` never attached, since the phone was not connected, and was cleaned up).

## Artifacts

`handoffs/2026-07-25_device-pass-artifacts/` (gitignored):

- `Talaria 27-2026-07-25-005838.ips` — the notification-tap crash, symbolicated in this doc
- `A1-control-openAppWhenRun-failures.log` — all four control taps + the 2001 errors
- `notification-authorization-and-deliveries.log` — the `NotDetermined` drops and every delivery
- `crash-uncaught-exception.log` — the raw termination block
- `make_oversize_pdf.py` — regenerates the A8 size fixture (valid 25.07 MiB single-page PDF)
- `askparse.swift` — reproduces `handleDeeplink`'s `ask` parse; run with `xcrun swift` to check any
  `hermes://ask?…` form before blaming the app

The full 496 MB `idevicesyslog` capture was in the session scratchpad and is **not** preserved; the
excerpts above carry everything cited here.
