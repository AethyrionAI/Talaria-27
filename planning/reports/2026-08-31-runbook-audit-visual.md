# Runbook card staleness audit — READ-ONLY, static source read at HEAD

HEAD: `7f5aa8de` (2026-08-31). Method: `grep`/`sed` only. No build, no sim, no device.
Cards audited: `350d`, `56uh`, `309b-connect-host`, `163`, `165`, `162`, `33`, `279f`, `224-1f`, `224-2c` (10 of 10).

---

## Verdict table

| Card | Class | One-line reason |
|---|---|---|
| `350d` | **STALE-FIXABLE** | Auto-connect toggle is on **SERVER**, not Uplink — and it is **inert** (no reader); and the drawer footer renders `LINKED · —`, never `CHECKING`, so the PASS is unsatisfiable on one of its two surfaces. |
| `56uh` | **STALE-FIXABLE** | The Siri phrase is **"Ask Talaria"**, not "Ask Hermes" (08-27 sweep). Hostless routing is correct in code; card text quotes a dead phrase. |
| `309b-connect-host` | **RUNNABLE** (2 preconditions) | Every quoted string exists verbatim. Wizard half needs a **hostless profile**; `TIMED OUT` only fires on a real timeout, not on a refused port. |
| `163` | **RUNNABLE** | Both soft passes exist: search empty state echoes the query; `(custom)` row preserves a hand-typed skills value. |
| `165` | **RUNNABLE** | Truncation strip counts the fetched window (`SHOWING THE n MOST RECENT SESSIONS`), gated on `isTruncated`; cap is 3×200 = 600. CTX gauge is a separate surface. |
| `162` | **RUNNABLE** | Once → "At a time" emits ISO with the **device** UTC offset, and the host-clock caveat is deliberately suppressed for `.once` — the card's PASS is exactly the coded intent. |
| `33` | **RUNNABLE** | Nothing app-side to go stale; it is a host-capability card. Profile switch path exists. |
| `279f` | **UNRUNNABLE as written** | The #134 forced-trip harness sends **its own** prompt and appends a `.delivered` assistant row — it never produces a `.failed` row or a Retry affordance. The card cannot reach its PASS/FAIL. |
| `224-1f` | **RUNNABLE** | `Never ask` / `Ask every time` exist verbatim; the refusal string and its do-not-claim clause are real constants. |
| `224-2c` | **RUNNABLE** | `Ask when unusual` exists verbatim; the past-due caution the friction read depends on is a live, documented rule. |

**Totals: 6 runnable · 3 stale-fixable · 1 unrunnable.**

---

## 350d — Dead-host LINKED honesty, cold launch — **STALE-FIXABLE**

### (a) Is there still an auto-connect toggle anywhere in settings? — **Yes, but not where the card says, and it does nothing.**

> **⚠️ SUPERSEDED 2026-08-31 (evening) — the answer is now NO.** This section's
> finding became OPEN_ITEMS #420; Owen ruled the same day to **delete the
> toggle** and keep the persisted key, and the deletion landed that night. The
> control and its search-index row are gone from `ServerSettingsScreen.swift`
> and `SettingsSearchIndex.swift`; `AutoConnectTogglePinTests` now pins that no
> shipping source names the key outside `UserSettings.swift` and
> `DemoData.swift`. **Everything below is the measurement as it stood before
> the deletion — read it as evidence, not as current state.** The card wording
> in "Exact corrected wording" is likewise stale in one clause: there is no
> longer a toggle on Settings → SERVER to explain away, so the setup step is
> simply the base-URL change plus a force-quit.

- It exists: `Talaria/Features/Settings/ServerSettingsScreen.swift:623-632`, label **`"Auto-connect on launch"`**, mounted into the body at `:123`.
- It is on **Settings → SERVER** (card 02), **not Uplink** (card 01). `Talaria/Features/Settings/SettingsChannels.swift:14` fixes the deck order `uplink, server, models, …`; `SettingsChannelsScreen.swift:200-201` maps `.uplink → UplinkSettingsScreen`, `.server → ServerSettingsScreen`. The file header at `ServerSettingsScreen.swift:10-11` says so outright: *"the auto-connect toggle moved here"* (from the retired Relay sub-page).
- Searchable as "Auto-Connect on Launch" → `.server` (`SettingsSearchIndex.swift:65`) — that is how the operator should find it.
- **It is INERT.** `autoConnectOnLaunch` has exactly four appearances outside the toggle's own `get`/`set`: its declaration and Codable plumbing (`Talaria/Models/UserSettings.swift:276, 384, 416, 458, 493`), `DemoData.swift:167`, and one test seed (`TalariaTests/AppStoresTests.swift:3021`). **No production code reads it.** Setting it OFF changes no launch behaviour.

This is very likely what burned the earlier session's budget: the toggle is real, is not on Uplink, and toggling it is a no-op.

### (b) Do chat and settings use different derivations, and can chat render ONLINE?

**Yes, two derivations, and the divergence is deliberate.**

- `Talaria/Core/ConnectionSignal.swift:78-91` — one `state(_:for:)` with two surface arms.
- Chat: `chatState(direct:)` at `:94-96` — takes **only** `direct`; `hostFallback`/`hostConfigured` are ignored by construction. Callers: `ContentView.swift:212`, `ChatScreen.swift:799`.
- Settings: `settingsState(container:hostStore:)` at `:127-139` — reads all three, with the predicate `hostConfigured = activeProfile?.hasGateway == true` (`:117-119`; `hasGateway` is a **non-empty URL only** — `Talaria/Models/BackendProfile.swift:119-121`). Callers: `UplinkSettingsScreen.swift:119`, `SettingsChannelsScreen.swift:497`, `AboutSettingsContent.swift:88`.
- **Chat can render ONLINE on exactly one input: `direct == .connected`.** `directConnectionStatus` starts `.disconnected` (`ChatStore.swift:66`) and only becomes `.connected` via `refreshDirectHealth()` after a successful `hermesClient.connect()` (`ChatStore.swift:3096`), via the turn-teardown copy (`:1705`), or via the `guard !isStreaming` branch that asserts `.connected` **unprobed** (`:3086-3093`, the #394-instrumented path). None of those can fire on a cold launch against a closed port, so the card's chat-side FAIL is unreachable by construction. That is good news for the card's intent — and it is *not* what the card actually asks you to observe.

### The defect in the card's PASS

The card: *"both surfaces read `CHECKING` with a dim pip"*.

- **Settings strip — CORRECT.** `settingsState` → `.checking` → `SettingsCardValues.statusStrip` (`SettingsChannels.swift:146-162`, `.checking → "CHECKING"` at `:159`) renders **`CHECKING · <PROFILE> · <MODEL>`**. Pip is `effectiveConnectionState == .online ? Design.Brand.accent : Design.Colors.mutedForeground` (`SettingsChannelsScreen.swift:373-377`) → **muted = dim ✔**.
- **Drawer footer — WRONG.** `chatState(.disconnected)` → `.checking` → `ChatConnectionPresentation.sessionsHostDetail` (`ChatScreen.swift:10-21`) returns **`"LINKED · —"`** for `.checking` (`:17-19`), fed at `ContentView.swift:123` / `:150`. The pip is `hostOnline ? Design.Brand.accent : Design.Brand.forge` (`SessionsDrawer.swift:1062`) → **amber, not dim**.

So the footer never prints the word CHECKING, and its pip is amber. It is *not* a FAIL under the card's own FAIL clause (it is neither `LINKED · ONLINE` nor a green pip), but a careful operator cannot reach the stated PASS.

### Observation window — fine

The health poll **sleeps before its first probe** (`ChatScreen.swift:610-616`, interval `responsiveInterval = 10 s` at `ChatHealthPollPolicy.swift:19, 28-29`). So the pre-probe window at cold launch is ~10 s — comfortably observable even against an instantly-refused port.

### Exact corrected wording

> **Setup:** base URL → the verified-refused `:12399` (Settings → **Uplink** → Base URL). *No auto-connect step* — the toggle lives on Settings → **SERVER** ("Auto-connect on launch") and is currently read by nothing, so it cannot affect this card. Force-quit the app (cold launch is the point).
>
> **Steps:** Relaunch; within ~10 s (the first health probe is on a 10 s delay) read the drawer footer AND the settings strip.
>
> **PASS** — the **settings strip** reads `CHECKING · <PROFILE> · <MODEL>` with a dim/grey pip; the **drawer footer** reads `LINKED · —` with an amber pip. The red banner appears only AFTER the measured fail.
> **FAIL** — any `LINKED · ONLINE`, `CONNECTED`, or an accent/green pip on either surface against the closed port; or the banner firing during CHECKING or while unpaired.

*(If Owen wants the footer to literally say CHECKING, that is a product change to `ChatScreen.swift:17-19`, not a card edit — file it, don't silently re-word the PASS to hide it.)*

---

## 56uh — Siri on a hostless install — **STALE-FIXABLE**

- **The phrase is dead.** `Talaria/Intents/StartVoiceSessionIntent.swift:54-64` registers the Ask shortcut with `"Ask \(.applicationName)"`, `"Ask \(.applicationName) a question"`, `"Ask \(.applicationName) something"`, `"Send \(.applicationName) a question"`, `shortTitle: "Ask Talaria"`. The intent's own title is `"Ask Talaria"` (`AskHermesIntent.swift:33`), and the code comment at `:30-32` records the 08-27 sweep ruling explicitly. **"Ask Hermes …" is gone.**
- **The type name is deliberately still `AskHermesIntent`** (`:26-32`) — do not read that as a missed rename; it is a pinned orphaning fence.
- **Hostless behaviour is correct by code, so the card's question is worth asking.** `needsReachabilityPreflight(hermesAPIKey:)` returns false on an empty key (`:98-100`), so the unreachable preflight is skipped entirely (`:141-158`) and `chatStore.sendMessage` routes to the on-device brain. The doc comment at `:89-97` names exactly the failure the card would otherwise hit.
- ⚠️ **Uncertain: the literal wake phrase.** `.applicationName` resolves from the bundle's display name, which is **`Talaria27`** (`project.yml:134`, `:147`), and there is **no `AppShortcuts.strings`** in the tree (no `.strings` file anywhere). So Siri may want "Ask Talaria27". Settle it on device by reading the Shortcuts app's suggested phrase before speaking — that is a 10-second check, not a card blocker.
- ⚠️ **Likely sweep miss the operator will photograph:** the Siri result card header is hardcoded `monoHeader("HERMES", …)` at `AskHermesIntent.swift:457`, and the pip/status word beside it (`:445-451`). On a hostless install the answering brain is local, so this reads as an app-meaning "Hermes". The card already says *"screenshot if odd"* — this is the odd thing. (Contrast `:87`, where the hand-off dialog was correctly swept to *"Talaria is still working on it."*)

### Exact corrected wording

> **Steps:** On the unpaired install, invoke the Siri phrase — **"Ask Talaria"** (confirm the exact suggested phrase in the Shortcuts app first; the bundle display name is `Talaria27`, so Siri may want that). Watch whether the intent completes against the local brain.
> **Record:** … plus a screenshot of the result card — its header currently reads `HERMES`, which is a candidate 08-27 sweep miss.

---

## 309b-connect-host — **RUNNABLE**, with two preconditions

Every user-visible string the card quotes exists at HEAD, in `Talaria/Features/Settings/ConnectHostCopy.swift`:

| Card quote | Source |
|---|---|
| `START LOCALLY` | `:46` `localOptionTitle` |
| blurb names Apple's Private Cloud, no "nothing leaves the device" | `:61-62` — literally *"…or Apple's Private Cloud when you pick that model. No account. No host."* |
| no lock icons / no "LIMITED" | `ConnectHostWizard.swift:150` comment states the rule; **no `"LIMITED"` string exists anywhere in `Talaria/`** |
| `Not now` top-right | `:75` `notNow`; rendered `ConnectHostWizard.swift:99-103` (a11y id `connectHostWizard.notNow`) |
| `Enter it manually` | `:83` |
| `Type it instead` | `:312` `scannerTypeInstead` |
| `hermes talaria pair-qr` | `:223`, and in `:81`, `:107`, `:311` |
| `Address reachable` | `:122`; `NOT REACHED` `ConnectHostProbe.swift:34` |
| `NOTHING WAS SAVED` | `:153` — full string `"NOTHING WAS SAVED. YOU ARE STILL ON-DEVICE."` |
| `Key accepted` · `REFUSED`, third row `—` | `:124`; `ConnectHostProbe.swift:129-134` (`keyAccepted: .failed("REFUSED")`, `hermesGateway: .notConcluded` → `"—"` at `:35`) |
| `MODELS SEEN` | `:163` |
| `LAST ANSWERED` | `:164` |
| `Check now` | `:166` |
| `NOT ANSWERING` | `:207` `statusNotAnswering` |
| `SAVED ≠ REACHABLE` | vocabulary rule 2, `:21-23` |
| `hermes talaria unpair` | `:266`, `:289` |
| `RUNNING LOCALLY` | `:214` |
| the "Connect Host" entry itself | `:202` `screenTitle`; rendered as a **GlowButton** on Uplink at `UplinkSettingsScreen.swift:399`, with `:395-398` confirming it replaced "Pairing & Devices" |

**Precondition 1 — the wizard needs a hostless profile.** `AppContainer+ConnectHost.swift:101-105`: `startsInWizard = !hasGatewayCredentials(forProfileID:)`, and the decision is **frozen at push time** (`:6-19`) so it cannot flip mid-flow. On a device that already has a host, tapping Connect Host lands on `ConnectHostScreen` (manual), and checks 1–3 of the card are unreachable. Running this card end to end therefore **destroys and rebuilds the device's host config** — schedule it accordingly, because cards `33`, `165` and `162` all need a live host.

**Precondition 2 — "TIMED OUT" is only one of three no-answer details.** `GatewayHermesHostService+ConnectProbe.swift:63` emits `"TIMED OUT"` only for `URLError.timedOut`; anything else is `"NO ANSWER"` (`:63,65`) and a malformed URL is `"BAD ADDRESS"` (`:48`). A **refused** port (e.g. `:12399` on a live host) will read `Address reachable · NO ANSWER`, not `TIMED OUT`. To get the card's literal string, use a black-holed address (an offline tailnet IP), not a closed port on a live host.

Optional card sharpening (intent unchanged): *"wrong address → `Address reachable · TIMED OUT` (use an unreachable IP; a merely-closed port reads `NO ANSWER`, which is equally correct)"*.

---

## 163 — Skills: the two soft passes — **RUNNABLE**

- **Echoing empty state:** `Talaria/Features/Skills/SkillsScreen.swift:308` — `Text("No skills match \u{201C}\(searchText.trimmed)\u{201D}")`. Echoes the query inside curly quotes. Search field prompt is `"Search skills…"` (`:173`).
- **`(custom)` skills value:** `Talaria/Features/Tasks/TaskSkillsPicker.swift:310` — `row(title: "\(value) (custom)", …, isSelected: true)`; the preservation property is documented at `:36`, `:107`, `:268`. The same pattern for the delivery field is at `TaskEditSheet.swift:397, 424`.
- Both steps executable as written; PASS/FAIL reachable.

---

## 165 — Insights: truncation strip + CTX non-contradiction — **RUNNABLE**

- **Strip text:** `Talaria/Features/Insights/InsightsScreen.swift:188-205`, reading **`SHOWING THE <n> MOST RECENT SESSIONS`** where `n = store.rows.count` — i.e. it counts the **fetched window**, exactly the card's PASS. Gated on `store.isTruncated` (`:112-115`).
- **The 600 precondition is real:** `InsightsService.swift:47-49` — `maxPages = 3`, 200/page ⇒ a 600-session window; truncation is only reported when the crawl hit the cap.
- **CTX is a separate surface, by design:** `InsightsScreen.swift:12` says so; the gauge is `ChatScreen.swift:1017` (`CTX <n>%`) fed from `SessionUsageIndexStore` (`AppContainer.swift:499`), which never reads the Insights window. So "uncontradicted" is structurally likely, but the card is still worth running as a read-check.
- Breakdown sections are `BY SOURCE` / `BY MODEL` (`:130-133`) — consistent with the card's note that the old fixed "expected set" is stale.

---

## 162 — Tasks: once-absolute fires locally — **RUNNABLE**

- **The control exists:** `TaskEditSheet.swift:441-459` (segmented "Schedule kind" picker) → `.once` → `onceControls` at `:513-539`, whose inner picker offers **"From now" / "At a time"**; "At a time" is a `DatePicker` bounded `Date.now...`.
- **The card's PASS is the coded intent, not a hope.** `TaskScheduleDraft.swift:139-144` — a once-absolute emits `isoWithDeviceOffset(from:)`, i.e. ISO 8601 **with the device's UTC offset spelled out**, documented at `:151-154` as *"the stored instant is exactly the wall-clock the phone displayed (no host-tz reinterpretation)"*.
- **The host-clock caveat does NOT apply here** and won't confuse the operator: `usesHostClock` is `false` for `.once` (`:193-198`), so the *"Times run on the Hermes host's clock…"* text (`TaskEditSheet.swift:584`, gated at `:467-469`) is suppressed in this mode. Worth knowing, because that string looks like it contradicts the card and does not.

---

## 33 — Notes read + write from Talaria chat — **RUNNABLE** (host-side card)

Nothing in this card names an app control beyond "from chat", so there is no app-side text to have gone stale. Its preconditions are all host/ops:

- Profile switching is on **Settings → SERVER** (`SettingsChannels.swift:41` chip `BACKEND PROFILES`; `ServerSettingsScreen.swift:1-12`), so "Mac Mini profile ACTIVE" is settable in-app.
- Note the standing repo caveat that the profile the phone normally talks to is OJAMD; switching to the Mac Mini for this card and switching back is an extra step the card does not spell out. Suggest adding: *"Setup: Settings → SERVER → tap the Mac Mini card to activate (confirm sheet). Switch back to OJAMD when done."*

---

## 279f — Local-brain retry, no duplicate bubble — **UNRUNNABLE as written**

**The named method cannot produce the state the card observes.** The card says: *"Trip a generation error mid-turn: the Developer forced-trip harness (#134) is the reliable way. … Send a message, trip the failure, see the failed row. Tap RETRY."*

What the #134 harness actually does:

1. **It sends its own prompt, not yours.** `ChatStore.swift:4921-4941` (`debugRunForcedTrip`) calls `await sendMessage("Force repetition trip — #134 debug harness")`. There is no seam for the operator's own message. So "count YOUR message's bubbles" has no referent.
2. **It never fails.** `LocalChatBackend+Harnesses.swift:77-137` streams synthetic degenerate snapshots, trips the #102 repetition breaker, collapses the tail, and appends `Message(sender: .hermes, content: latestFull, status: .delivered)` at `:130-131`. **`.delivered`, not `.failed`.**
3. **No Retry affordance appears.** Both retry buttons are gated on `message.status == .failed` — `MessageBubble.swift:207-214` ("Retry", user row) and `:329-336` ("Regenerate", assistant row). A delivered row shows neither.
4. The Developer screen's own success text confirms the harness's purpose is different: *"Tripped — check the chat reply, the #102 Console notice, and that the next send still works."* (`DeveloperSettingsScreen.swift:1148-1150`). It is a #102/#110 instrument, not a failure injector.

**The fix under test still exists** — `ChatStore.retryMessage` at `:2817-2845` carries the #279 comment and the adoption-tail fix — so the card's *intent* is live. It just needs a method that actually manufactures a `.failed` user row on the local brain.

### Corrected wording (verify on device before adopting)

The one path in the source that produces a **`.failed` user row with the "Retry" button** without a host is the cold-load recovery scrub:

> **Setup:** the LOCAL brain (not Hermes, not airplane mode — those were #329's).
> **Steps:**
> 1. Send a message to the local brain and **force-quit the app while the reply is still streaming**.
> 2. Relaunch. The interrupted turn's user row settles `.failed` and shows **Retry** (`ChatStore.swift:915-925` marks a `.sending` user row failed on cold load; `:998-1010` `settleRestoredRowAsFailed` covers the #329-restored case; the affordance is `MessageBubble.swift:207-214`).
> 3. Tap **Retry**. Count YOUR message's bubbles in the transcript.
>
> **PASS** — exactly one user bubble; the retry answers it. **FAIL** — your message appears twice (the pre-fix shape).

⚠️ I could not verify statically that a force-quit mid-local-stream reliably leaves the row in `.sending` (as opposed to the turn being torn down cleanly). If it does not reproduce in two tries, this card should be re-filed as needing a purpose-built DEBUG failure injector rather than burning device minutes hunting one. **Do not spend the budget re-trying the #134 harness — it is proven not to be the path.**

---

## 224-1f — The Off floor — **RUNNABLE**

- **Path exists verbatim:** Settings → PRIVACY (`SettingsChannels.swift:35`, chip `PERMISSIONS`) → `// Agent Actions` section header (`PrivacySettingsScreen.swift:412, 424`), rows from `ApprovalMode.selectable` (`:428-431`).
- **Labels exact:** `ApprovalModeCore.swift:51-56` — `.manual → "Ask every time"`, `.smart → "Ask when unusual"`, `.off → "Never ask"`. The card's "set it back to Ask every time … Manual is the default" matches `defaultMode = .manual` (`:57`).
- **The refusal and its clause are real strings, not aspiration:** `ApprovalFloor.refusal(nothingHappened:flagged:)` at `:236-240`, composed from `doNotClaimClause` — *"This action was refused and did not run — do not tell the user it happened."* (`:218-219`) — plus `followUpClause` (*"Tell the user what was flagged and ask them to confirm what they meant…"*, `:222-223`). That is precisely the card's FAIL discriminator, and it is verbatim-quotable.
- Gate wiring: `.off` → `hasCaution ? .refuse : .autoApprove` (`:159`), mode read globally from `UserSettings.approvalMode` (`AppContainer.swift:974`, `ToolConfirmationCenter.swift:61`).
- "needs 3101" — satisfied by any build off HEAD; nothing in this behaviour has changed since.

---

## 224-2c — Smart parity + evening-alarm friction — **RUNNABLE**

- `Ask when unusual` exists verbatim (`ApprovalModeCore.swift:54`), with the row detail *"Goes ahead unless the action trips a caution — an early-morning hour, or a time that has already passed. Those still ask."* (`:107-108`).
- **The friction read's premise is documented in the source itself**, which is unusually good news for the card: `:96-104` records that an evening-set next-morning alarm trips #249's past-due rule (`ALREADY PASSED TODAY — RINGS TOMORROW`), and that the copy was deliberately written around it. So the card's "the past-due rule fires, so Smart CARDS it" is a coded fact, not a guess — the operator only has to supply the judgment.
- Parity half (`clean creates go through with no card`) maps to `:158-159` (`.smart` → card only on caution).
- "needs 3101" — satisfied.

---

## Cross-cutting notes

1. **The 08-27 Hermes→Talaria sweep touched exactly one audited card's text: `56uh`.** The surviving user-visible "Hermes" strings I checked are host-meaning and legitimate under the standing ruling — `"NO HERMES HOST CONFIGURED"` (`InsightsScreen.swift:58`), `"Sessions stored on the Hermes host"` (`SessionsSettingsScreen.swift:385`), `"Hermes Sessions API endpoint…"` (`UplinkSettingsScreen.swift:332`), `"HERMES HOST"` drawer fallback (`ContentView.swift:122`), `"Share Sensors with Hermes"` (`PrivacySettingsScreen.swift:311`).
   **One candidate miss found, and it is app-meaning:** `AskHermesIntent.swift:457` `monoHeader("HERMES")` — the Siri result card's header, shown even when the local brain answered. Contrast `ChatScreen.swift:930`, which correctly renders `isLocalBrainActive ? "TALARIA" : "HERMES"`. Worth filing separately; it is not mine to fix in a read-only pass.

2. **Sequencing hazard.** `309b` needs a **hostless** profile to see its first three checks and ends by disconnecting; `33`, `165` and `162` all need a **live host**. Run `309b` last in any sitting, or budget the host re-entry.

3. **`350d`'s cost driver was structural, not a typo.** The card named a control by the screen it *used to* live on. Two of the ten cards (`350d`, `279f`) fail the same way — they name a mechanism (`the auto-connect toggle`, `the #134 harness`) rather than an observable, and the mechanism moved or never did that job. Cards that quote *strings* (`309b`, `224-*`, `163`) all survived intact. That is a reusable authoring signal.

---

## NOT AUDITED

None of the ten requested cards was skipped. Two limits on what a static read could settle, both stated inline above:

- **`56uh`** — the literal Siri wake phrase `.applicationName` expands to (`Talaria` vs `Talaria27`). Settle by reading the suggested phrase in the Shortcuts app; no build needed.
- **`279f`** — whether a force-quit mid-local-stream reliably leaves a `.sending` user row for the cold-load scrub to flip to `.failed`. Settle with two device attempts; if it does not reproduce, the card needs a new DEBUG failure injector rather than a re-word.

I did not audit the other ~25 cards in `open-cards.txt` (out of scope for this pass).
