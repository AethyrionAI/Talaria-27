# OPUS-T27 — Wave leftovers triage: #45, #72, #74, #75, #77, #80, #81

**Label:** OPUS
**Items:** #45, #72, #74, #75, #77, #80, #81 — the oldest live 🔧 entries on the board
**Goal:** for each, verify at HEAD (not from the header) whether it is actually shippable, actually
device debt, actually waiting on Apple, or actually dead, and bucket it accordingly — no code
written, no `OPEN_ITEMS.md` edits made.

**Headline finding, not in the original brief's item list but load-bearing for two of them:** #80's
entire relay-based foundation (`LiveInboxService`, `RelayInboxItem`, the connector's relay-facing
producer path) was **deleted 2026-08-06** by #251 Slice 2A (bar 2A-E, PR #272) and replaced with a
plugin-outbox architecture. #80's header, its device checklist, and its row in
`dispatch/DEVICE-PASS-RUNNING-LIST.md` all still describe the deleted mechanism. This is the same
shape as #238's retirement of #81 five weeks apart — read in full below.

---

## 1. The triage table

| Item | What shipped (file:line) | What's left | Bucket | Size | Already in device queue? |
|---|---|---|---|---|---|
| **#75** HUD header wrap/truncate | `hudSingleLine(minScale:)` — `Talaria/Core/HUD/HUDComponents.swift:476`. Used in the real chat header: `Talaria/Features/Chat/ChatScreen.swift:779,783,906`; also `TasksScreen.swift`, `InsightsScreen.swift`, `ConversationSearchScreen.swift`. PR #43 merged 2026-07-08, GitHub #42 closed. | On-device/sim acceptance pass only (narrow width, both brains, long model name, Dynamic Type sweep) — no code work anticipated. | **DEVICE-DEBT** | — | **YES** — Group 3, `DEVICE-PASS-RUNNING-LIST.md:577-582`. Unrun (`[ ]`). |
| **#77** `hermes://` scheme + `ask?q=` | `CFBundleURLTypes`/`hermes` scheme — `project.yml:133-137`, mirrored `Talaria/Resources/Info.plist:606-618`. `AppEntry.swift:261 handleDeeplink` → `Talaria/Core/DeeplinkRouter.swift:54-65` → `ChatStore.seedComposer`/`consumeComposerSeed` (`ChatStore.swift:38-46`). PR #51 merged 2026-07-08, GitHub #48 closed. | Device checklist only (Safari open, Shortcuts seed-not-send, scheme-collision check). | **DEVICE-DEBT** | — | **YES** — §F10, `DEVICE-PASS-RUNNING-LIST.md:744-748`. Unrun (`[ ]`). |
| **#80** Inbox + agent-initiated producer tools | The **2026-07-08 relay-based build shipped and later worked** — but `LiveInboxService`/`RelayInboxItem` and everything downstream of them were **deleted 2026-08-06** (bar 2A-E MET, PR #272). Current live Inbox is `Talaria/Services/Live/TalariaPlatformInboxService.swift`, wired at `AppContainer.swift:506`, reading a **local cache filled by a plugin drain loop** — no network call of its own. Reachable: `ContentView.swift:241-242` (`.inbox` → `InboxScreen()`), tray button `ChatScreen.swift:655-657`. | Nothing under #80's own scope. Its functional successor is `#251` Slice 2A, which has its **own** pre-registered device bars, mostly MET (2A-A/C/D/E/F/G MET; only 2A-B's transport-leg timing instrumentation is still owed, and that's tracked under #251, not #80). | **CLOSE** (superseded — header + device-pass row both stale) | — | Its OLD row (`DEVICE-PASS-RUNNING-LIST.md:487-492`) describes pull-to-refresh against a service that no longer makes network calls — that row is **itself dead**, same as #81's rows below. |
| **#81** Lock-screen reply | Fully built and merged (PR #55, 2026-07-08: `UNTextInputNotificationAction`, `HERMES_REPLY` category, `AppContainer.handleNotificationReply`) — then the **entire notification surface was deleted 2026-08-03** by #238 ("notification removal," PR #252), whose own closure text names *"reply-from-the-lock-screen (#47)"* as accepted collateral. **Verified independently:** zero hits anywhere in the working tree (`Talaria/`, `TalariaTests/`, `TalariaUITests/`) for `UNTextInputNotificationAction`, `HERMES_REPLY`, `handleNotificationReply`, or `UNUserNotificationCenter`. | Nothing. Deliberately deleted; Owen already accepted the loss in the #238 filing. | **CLOSE** (dead, tracker stale) | — | Already annotated **MOOT** in `DEVICE-PASS-RUNNING-LIST.md` (§F4/§F8's `#81` rows, lines 792-800, 1803-1813, 844). |
| **#45** CarPlay entitlement / voice mode | Scaffold on `main` (`CarPlaySceneDelegate.swift`, `CarPlayVoiceManager.swift`, `Talaria/CarPlay/`, 305 lines); CarPlay scene declared in `project.yml`. `com.apple.developer.carplay-voice-based-conversation` **never shipped** — commented out at `project.yml:53-61`, absent from `Talaria/Talaria.entitlements`. **No record anywhere in `OPEN_ITEMS.md`, the archive, or `handoffs/` that the discretionary grant was ever filed** at `developer.apple.com/contact/carplay/` — the last dated note (2026-07-07) says explicitly *"Apple's discretionary grant NOT yet filed."* | The filing itself (Owen's own action, external to this repo) + Apple's decision. | **WAITING** | — | N/A — external. |
| **#72** PCC tier | `PrivateCloudComputeLanguageModel` used behind a master gate, `Self.pccGrantConfirmed = false` (`Talaria/Services/Live/LocalChatBackend.swift:226`, guarding lines 232/241/260/280/315/1184) — a deliberate crash-prevention stopgap (PR #104, 2026-07-16) since constructing the type without the grant SIGTRAPs uncatchably. `com.apple.developer.private-cloud-compute` **not** in `project.yml`/`Talaria.entitlements`. | Apple's SBP → PCC-request → entitlement chain. Ambiguous in the record whether the SBP step has actually been submitted (see §4). | **WAITING** | — | N/A — external. |
| **#74** CarPlay voice upgrade (auto-start / observation / routing) | Code **MERGED** (PR #40, 2026-07-07): auto-start on connect (`CarPlayVoiceManager.configure()` → `startSessionDirectly()`), `withObservationTracking` replacing a 500ms poll, audio-route reassertion on `.carAudio`. All confirmed on `main`. | The **CarPlay Simulator functional pass** — and this does **not** need Apple's grant, only a dedicated Mac-only build (uncomment the entitlement, `xcodegen generate`, build to the **Simulator**, run through CarPlay Simulator.app, re-comment + rebuild before any device build). | **ACTIONABLE** | **M** | Explicitly **excluded** from the phone queue — `DEVICE-PASS-RUNNING-LIST.md:773-781,1901-1911` says outright *"not a phone check at all... could happen independently."* This is correct exclusion, not an omission. |

---

## 2. Verified state

**VERIFIED (read the code, the SDK, and git/GitHub directly):**
- #75: `hudSingleLine` exists and is used in the real chat header (`ChatScreen.swift:779,783,906`), not just declared. PR #43 merged.
- #77: URL scheme registered in both `project.yml` and the built `Info.plist`; `DeeplinkRouter` wired from `AppEntry.handleDeeplink`; `ChatStore.seedComposer`/`consumeComposerSeed` exist. PR #51 merged.
- #80: `LiveInboxService` / `RelayInboxItem` are **absent** from the current tree (grep, zero hits, in the main worktree only — stale hits exist only in old `.claude/worktrees/*` checkouts, which are not `HEAD`). `TalariaPlatformInboxService` is the live wiring at `AppContainer.swift:506`. PR #272 merged 2026-08-06, confirmed via `gh pr view`.
- #81: notification surface fully absent from the main worktree (`UNTextInputNotificationAction`, `HERMES_REPLY`, `handleNotificationReply`, `UNUserNotificationCenter` — zero hits). PR #55 (built it) and PR #252 (deleted it) both confirmed merged via `gh pr view`.
- #45/#74: `project.yml:53-61` — the CarPlay entitlement line is commented out today; `Talaria/Talaria.entitlements` (the generated file) confirms it is absent from the actual signed capability set. `Talaria/CarPlay/` exists (305 lines across 2 files). PR #40 merged.
- #72: `pccGrantConfirmed = false` at `LocalChatBackend.swift:226`; entitlement absent from `Talaria.entitlements`. PR #37 (feature) and PR #104 (stopgap) both merged.
- **The exact PCC API surface used in code was checked directly against the Xcode-beta4 SDK's own swiftinterface** (not memory, per the standing "never blame Apple first" rule):
  `/Applications/Xcode-beta4.app/.../iPhoneOS.sdk/.../FoundationModels.swiftmodule/arm64e-apple-ios.swiftinterface`.
  `grep -n "PrivateCloudComputeLanguageModel"` returns the full type — `.availability`, `.isAvailable`
  (line 59/266), `.quotaUsage`, `.limitIncreaseSuggestion`, `LanguageModel` conformance — all present,
  matching what `LocalChatBackend.swift` calls line for line. **The API is not the blocker; only the
  entitlement is.**
- CARPLAY.md, referenced by #45's own text ("Full reference + weekend sim plan in `CARPLAY.md`"), has
  **never existed in this repo's git history** (`git log --all -- CARPLAY.md` and
  `git log --all --diff-filter=A --name-only | grep -i carplay.md` both empty).
- `dispatch/DEVICE-PASS-RUNNING-LIST.md` cross-checked directly for all 7 items' presence/absence and
  current run state (unrun `[ ]` vs struck `[x]`) as of the 2026-08-07 reconciliation, which is still
  the latest touch on any of these seven — the 2026-08-08/09 batch (Z1-Z7) is unrelated new work
  (#284/#286/#295/#297) and does not move any of these seven rows.

**ASSUMED / could not fully verify:**
- Whether Apple's SBP (the approval-chain first step named in #72's own text: *"SBP submitted → PCC
  request → entitlement"*) has actually been submitted. The phrasing is ambiguous — it could mean "step
  1 done, chain pending on steps 2-3" or it could be naming the chain's steps generically. No later note
  updates this. **Needs Owen's direct confirmation**, not inferable from the repo.
- Whether the #251/Slice-2A plugin gives the **agent itself** (mid-conversation, not Owen via the
  `hermes talaria send` CLI) a way to push an item into a user's Inbox — i.e., whether #80's
  "agent-initiated" half has a true successor. The 2A build ships `talaria_phone_query` (a pull tool)
  and an **admin CLI** `hermes talaria send` (2A-C's own bar text). Nothing in `OPEN_ITEMS.md` states
  whether an agent turn can call an equivalent push action. The plugin lives in its own repo
  (`~/.hermes/plugins/talaria`, `github.com/AethyrionAI/talaria-plugin`), outside this checkout, so it
  could not be inspected directly from here.
- Whether the CarPlay entitlement grant, if it were filed today, would actually be favorable — no
  Apple response of any kind (approval, denial, or acknowledgment) appears anywhere in the record.
- Live GitHub issue state (open/closed) for the underlying issues (#42/#45/#47/#48/#19/#30) was not
  separately re-checked via `gh issue view` — the PR merge records above are the load-bearing evidence,
  and are sufficient for the bucket calls.

---

## 3. ⚠️ Tracker corrections

1. **#80's header and body are stale in a way that changes its bucket, not just its wording.** The
   header ("🔧 Inbox wired + agent-initiated producer tools") and every note through 2026-08-06 late
   night describe a relay-backed implementation (`LiveInboxService`, connector `send_inbox_item`/
   `get_inbox_verdict` via `/internal/inbox/create`, `INTERNAL_API_KEY`) that **no longer exists**. The
   #80 entry's own last edit (2026-08-06 late night, declining the server-side `kind`-validation half)
   appears to have been written the same night #251's Slice 2A deleted the entire mechanism it was
   discussing (2A built overnight 2026-08-06, ~23:00-02:30) — the two sessions likely didn't know about
   each other. **This item should be closed with a pointer to #251, not carried forward as its own
   device debt.**
2. **`DEVICE-PASS-RUNNING-LIST.md`'s `#80` row (line 487-492, "pull-to-refresh the Inbox screen") is
   also now dead**, for the same reason #147/#189/#81/#226 were marked MOOT by #238: the service it
   describes pulling from doesn't make network calls anymore. It should get the same MOOT annotation
   treatment those rows got — not deleted, annotated in place — though that edit is out of this brief's
   scope (no `OPEN_ITEMS.md`/tracker edits made here; flagging for whoever owns that file next).
3. **#45's own text cites `CARPLAY.md`** as the full reference — that file has never existed in this
   repo. Either it lived only in the original GitHub issue body and was never committed, or the
   citation was aspirational from the start. Either way, the pointer is dead and should be removed or
   replaced next time #45 is touched.
4. **Neither #45 nor #72 has ever been updated past 2026-07-13** with any filing status. Both entries
   still read as though the grant process is imminent ("only way to know is to file," "Apple approval
   chain pending"), four weeks stale. Nothing found suggests either filing happened in the interim —
   this reads less like "waiting on Apple" and more like "waiting on someone to file," which is a
   different board fact (see §5).
5. **Minor:** #74's header still separately worries about "Wave 5" naming and cites its own now-merged
   PR #40 correctly — no correction needed there beyond what's already captured by its own 2026-07-13
   audit note. Included here only to say it was checked and found accurate.

---

## 4. The CarPlay entitlement question

**Two items sit on this gate — #45 (the filing + the base scaffold) and #74 (the auto-start/
observation/routing code, whose only remaining functional gap is a Simulator pass that does *not*
need the grant).** Splitting them changes the board fact from "two items waiting on Apple" to "one
item waiting on Apple, one item actionable today":

- **Requested?** No evidence found that it has been. The entitlement line is commented out
  (`project.yml:53-61`), the last dated status ("NOT yet filed," 2026-07-07) is the newest one on
  record, and no `handoffs/*.md` file (searched all that mention CarPlay) adds anything past that date.
- **Granted?** No — moot if never filed, and confirmed absent from the committed `Talaria.entitlements`
  regardless.
- **Never pursued?** This is the honest read of the evidence: **the filing step itself — going to
  `developer.apple.com/contact/carplay/` — appears to have never happened.** That is Owen's own action
  (a developer-account, discretionary-capability request); nothing in this repo can complete it.
- **Does #74 share the same gate as #45?** Partially. #74's Simulator functional pass is **independent**
  of the grant (the local entitlement key, once uncommented, is sufficient to run the CarPlay Simulator
  scene — the grant is only required for *signed device builds*, per the 2026-07-07 hotfix note). So
  #74 has real, actionable, non-Apple-gated work; #45 does not.

---

## 5. Per-item detail

**#75 — HUD header.** The fix is real and reachable: `hudSingleLine(minScale:)` isn't a dead helper,
it's load-bearing in the actual chat header (wordmark, status line, model chip) and reused in three
other screens. Nothing to build. What's left is a plain acceptance pass — narrow widths, both brains,
a long model name, Dynamic Type sweep — already queued and unrun in the device list.

**#77 — `hermes://` scheme.** Also fully wired and reachable, not merely declared: the scheme is in
both the source-of-truth `project.yml` and the generated `Info.plist`, and the seed-only `ask?q=` path
runs through the real `ChatStore` composer-seed mechanism, not a stub. Device checklist only.

**#80 — Inbox.** This is the item that changed the most between "what the header says" and "what's
actually there." The 2026-07-08 build genuinely shipped and worked end to end (verified live that
evening per the item's own note). But on 2026-08-06 the entire relay-facing half of it — the piece the
header and every subsequent note describe — was deleted as part of #251's architecture change (the
"plugin venture," replacing the relay/connector stack with a Hermes plugin). The replacement,
`TalariaPlatformInboxService`, is live and reachable today (`ContentView.swift:241`, tray button in
`ChatScreen.swift:655`), but it is a different implementation with different behavior (no network call
of its own; items arrive via a plugin drain loop keyed on scene-activate, not a pull-to-refresh against
a relay). #251/Slice 2A already has its own pre-registered, mostly-met device bars covering this exact
functionality. Carrying #80 forward as a separate device-debt item would mean re-verifying something
#251 already verified, against a mechanism that doesn't exist anymore.

**#81 — Lock-screen reply.** Same shape as #80, cleaner outcome: fully built, then deliberately and
explicitly deleted five weeks ago as accepted collateral of #238's notification removal (the pivot to
a hostless-by-default app, where push can never work for the default user). This is not a discovery —
#238's own closure text names it by number as intentional collateral, and `DEVICE-PASS-RUNNING-LIST.md`
already marked its rows MOOT on 2026-08-06. The only correction owed is #81's own header in
`OPEN_ITEMS.md`, which is unchanged since 2026-07-08 and still reads as live work.

**#45 — CarPlay entitlement/voice mode.** The scaffold is real code, not vaporware — `CarPlaySceneDelegate`
and `CarPlayVoiceManager` exist, compile, and are declared in the project. But the entire item exists to
gate a filing that, as far as the record shows, has never been submitted. Its cross-reference to a
"weekend sim plan" in `CARPLAY.md` points at a file that was never committed. Its dependency on voice
working first (→ old #47) is cleared — voice has worked since #82's fix, 2026-07-16.

**#72 — PCC tier.** The engineering here is unusually solid for an externally-blocked item: not only
did the code ship, a crash was found and a real stopgap was built and merged specifically because the
un-granted entitlement makes the SDK type SIGTRAP on construction. The stopgap (`pccGrantConfirmed`)
is a single static gate covering all eight call sites, correctly preventing any PCC construction until
flipped. The SDK surface it calls was independently confirmed present and byte-matching in the beta4
`.swiftinterface` — this is not an "Apple hasn't shipped the API" situation, it's purely an
entitlement-approval situation.

**#74 — CarPlay voice upgrade.** The only genuinely different bucket in this set. The functional code
(auto-start, observation tracking, audio routing) is merged and done. What's left — the CarPlay
Simulator pass — needs a build most other work on this board doesn't: entitlement uncommented,
`xcodegen generate`, build targeted at the **Simulator** (not device, which would fail signing with the
restricted entitlement active), run through CarPlay Simulator.app or the Simulator's External Displays
menu, then revert before any device build. This is real, boundable, schedulable work that doesn't touch
Apple at all.

---

## 6. Proposed bars — ACTIONABLE items only

**#74 — CarPlay Simulator functional pass** (the only actionable item in this set):

- **74-A (connect auto-starts):** connecting to the CarPlay Simulator with Talk ready auto-starts a
  session — no dead "Tap Start" screen, matching the merged auto-start code.
- **74-B (blocked state renders):** with Talk not ready, the scene shows the `blocked` voice-control
  state with a reason string (≤80 chars), never a dead idle screen.
- **74-C (mic + agent audio + barge-in):** a live back-and-forth works in the simulator scene — mic
  capture, agent audio playback, barge-in mid-response.
- **74-D (interruption recovery):** a simulated phone-call/nav-prompt interruption recovers cleanly.
- **74-E (disconnect/reconnect):** disconnecting the CarPlay scene leaves the session running on the
  phone side; reconnecting re-syncs state rather than restarting.
- **74-F (entitlement reverted):** after the pass, the entitlement line is re-commented and a signed
  **device** build succeeds again (guards against re-shipping the 2026-07-07 signing break).

All six are sim-only and Mac-only — no phone, no Apple response needed. A pass/fail on 74-A through
74-E is what actually answers the open question of whether the grant is worth filing at all.

---

## 7. What is OWEN'S to decide

- Has the CarPlay discretionary-capability request ever actually been filed at
  `developer.apple.com/contact/carplay/`? (The repo's record says no as of 2026-07-07 and nothing
  since updates it.)
- Has the PCC entitlement's SBP step actually been submitted, or is "SBP submitted → PCC request →
  entitlement" in #72 naming a chain rather than reporting progress on it?
- Should #74's CarPlay Simulator pass be scheduled now (it's genuinely unblocked), independent of
  whether/when the #45 filing happens?
- OK to close #80 with a pointer to #251 (superseded), rather than continuing to carry it as its own
  open item?
- OK to close #81 as dead (feature deliberately removed by #238, already accepted)?
- Does the #251 plugin give the agent itself a way to push an Inbox item mid-conversation, or is
  `hermes talaria send` an Owen-only CLI action today? (Needed to know whether #80's "agent-initiated
  producer tools" half has any successor at all, or whether that specific capability was quietly
  dropped in the rewrite.)

---

## 8. Recommended order

1. **#74's CarPlay Simulator pass** — the only actionable item, fully unblocked, bounded to one Mac
   session, and its outcome (does the voice UX actually work in a car) is the real information Owen
   needs before deciding whether the #45 filing is worth his time at all.
2. **#75 and #77's device-pass rows** — both already queued in Group 3 / §F10 of
   `DEVICE-PASS-RUNNING-LIST.md`; no new work to schedule, just run them as part of whatever sitting
   reaches that point in the existing queue.
3. **Everything else (#80, #81, #45, #72)** needs no engineering — #80 and #81 need a tracker sweep
   (Owen's call per §7), and #45/#72 need Owen's own external action or an explicit decision to keep
   waiting.
