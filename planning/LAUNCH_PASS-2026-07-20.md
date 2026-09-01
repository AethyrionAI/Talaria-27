# Talaria-27 — Launch Polish Pass

**Date:** 2026-07-20 · **Status:** Approved plan (Owen, this date)
**Decisions recorded:**
- iPad IS in v1.0 scope (Lane J matrix is launch-blocking, not deferrable)
- Crash/perf reporting is **MetricKit-only** (no third-party SDK)
- The consolidated device-verification sweep (Part 1) is the first move

Sources: live OPEN_ITEMS.md @ main `89e76b4` (2026-07-20). Item numbers are
OPEN_ITEMS numbers, not GitHub numbers. Results from each sweep session write
back to the corresponding OPEN_ITEMS entries as usual (separate doc commits).

---

## Part 1 — Device Verification Sweep

~20 open items are merged with only a device pass owed. Grouped into six
focused sessions so they burn down in days, not weeks. Checklists below are
distilled from each item's own DoD text — the item text remains canonical.

### Session V — Voice (whoGoesThere)

- [ ] **#128** Active voice session → Settings → audition several voices →
      apply one. No crash (`CreateRecordingTap` NSException gone); session
      degrades or recovers per #129 behavior. Re-verify stands on its own
      evidence — PR #127 does NOT close it (2026-07-20 record correction).
- [ ] **#129** Mid-session audition + apply: no crash, session keeps running,
      mic live after. Outside a session: full-fidelity previews. **Verdict
      owed:** accept the native-engine tail-drop behavior, or order the third
      dedicated preview instance (~4 lines, deferred pending your device feel).
- [ ] **#118** Start voice → background the app → system mic indicator OFF.
      Repeat in CarPlay sim → indicator stays ON (CarPlay exemption).
- [ ] **#119** Barge-in racing an already-completed response → no error banner
      (classified + swallowed). Header tracks live session state past
      CONNECTING through a full conversation. setActive warning wall reduced.
- [ ] **#130** A/B the probe branch (PR #128, DO-NOT-MERGE) vs main: TTS
      crispness, vpio render-err flood gone, barge-in cost (tap-or-gap vs
      talk-over), mic sensitivity post-#106. Verdict = productionize half-
      duplex or close as status-quo-accepted.
- [ ] **#131** Composer mic tap with instrumentation live — the silent-swallow
      catch names the failing error. Discriminators: dev-override gate OFF →
      retry; confirm mic worked pre-2026-07-17 build.
- [ ] **#84** Talk preflight checklist: (1) mic permission off → actionable
      banner + OPEN SETTINGS, never LISTENING; (2) grant → speak → no hint;
      (3) silent 12s+ → flatline hint, first words clear it; (4) mute through
      window → no hint until unmuted-silence; (5) ROUTE line updates on BT
      attach/detach; (6) Diagnostics Voice/Talk panel shows real states.
      Note the #84 branch's known preflight misclassification ('no input' as
      'permission denied') stays a separate owed fix.

### Session C — Chat & attachments (whoGoesThere)

- [ ] **#120** Stream replies (on-device brain + forced trip + relay-paired
      variants) → Console shows zero ForEach/LazyVStack duplicate-ID warnings.
- [ ] **#61** Attachment-only/empty user turn → card title and preview are
      distinct, neither echoes the reply's first line. If a card still
      degenerates, the log line names the path — that answer is the point.
- [ ] **#31** Paste image into composer → send → arrives at the agent.
      Full paste-then-send flow, never re-verified post-#43 merge.
- [ ] **#57** .txt/.md/.csv/.json attachments reach the agent as text parts;
      Extract Text on a screenshot + a multi-page PDF; UI truth (forge badge,
      send held on un-extracted PDF, text chips on sent bubbles).
- [ ] **#59** Multi-minute voice memo end-to-end OFFLINE (airplane mode:
      record → transcribe → stage → play), then send over tailnet. Check
      finalized-result concatenation spacing on a real memo.
- [ ] **#99** HTML preview: agent-written single-file HTML renders in the
      sandboxed sheet; ShareLink in toolbar. **Pre-launch decision rider:**
      remote subresource fetches are not yet blocked (WKContentRuleList gap
      from the PR #78 merge note) — accept for v1.0 or order the follow-up.
- [ ] **#100** Numeric table → chart toggle renders themed; tap → fullscreen;
      VoiceOver reads the label; malformed fence degrades to code block;
      re-check under Midnight Marquee. (App surface already PASSed once
      2026-07-17 on template data — this is the real-data + theme pass.)
- [ ] **#136** Cold launch with OJAMD relay+shim STOPPED, machine UP (the
      firewall black-hole case) → chat in seconds, standalone fully
      functional. Restore services → state upgrades live without relaunch.

### Session S — System integration (whoGoesThere)

- [ ] **#56** Remaining sub-checks: >25s long-run hand-off ("still working" →
      reply lands in-app), Siri Stop, tailnet-unreachable error surface.
- [ ] **#58** Control Center "Ask Hermes" → app launches to chat + perform
      log line in Console (subsystem org.aethyrion.talaria27.widgets). Talk
      control: the #82 wedge excuse is dead (root cause was ours, fixed
      PR #106) — verify it too; if still inert, it's a real defect now.
- [ ] **#66** Spotlight → search a session → tap → opens TO THAT SESSION;
      repeat for a Hermes file result; three SpotlightOpen .notice lines in
      order (entity query → perform → deep link).
- [ ] **#133** Fresh launch with both profiles paired → at most one push
      registration line per profile (2 max, not 5); exactly one background
      app-state report per backgrounding; sensor pipeline unaffected.
- [ ] **#137** Two passes: (1) fresh-install — pair → chat with ZERO prompts,
      then Settings sensor opt-in fires contextual per-sensor prompts;
      (2) grandfathered — update whoGoesThere, streaming continues, master
      shows ON. Watch the first PAIR DEVICE tap for the dropped-tap race —
      if it reproduces, log as its own item.
- [ ] **#126** AFTER OJAMD deploy + host cron half: six-step checklist from
      the PR #126 body (payload → push → inbox row → detail markdown+chart →
      read-aloud both paths → widget → deep link back).

### Session D — Dual-host / Connected tier

- [ ] **#21** `probe-t21.pdf` fixture in Mac MobileDL: task the Mac → tap
      chip → preview + ShareLink; repeat against OJAMD. Eyeball: (1)
      announcement-scan noise (any MobileDL mention grows a bubble — grate
      check); (2) the relay's device-files route-containment check —
      server-side, NOT a phone check, so it does not belong in this
      session; mechanics in the out-of-repo security addendum, 2026-08-07
      (OPEN_ITEMS #273).
- [ ] **#107** The Shelley iMessage send from Talaria chat (after-hours
      slot). Closes #107 AND the #114 residual DoD.
- [ ] **#116** AFTER Mini relay+connector restart on main + ojamd-deploy
      rebase: forget Mac pairing → re-pair via QR → shim token auto-fills →
      shim dot honest (NO KEY vs ONLINE) → models surface works. Repeat
      against OJAMD once deployed.

### Session J — iPad matrix (Shelley's iPad Air M3 — LAUNCH-BLOCKING per
### the iPad-in-v1.0 decision)

- [ ] J-3 resize matrix: full screen both orientations, Split View 1/2 +
      1/3, Slide Over, Stage Manager free resize; Deep Field + one Lane E
      complex theme; Dynamic Type spot check.
- [ ] External keyboard sweep: ⌘N, ⌘K (sidebar reveal + filter focus in
      regular width), ⌘, , ⌘1–⌘9, Return sends / ⇧Return newline
      (hardware-only), Esc closes drawer/search/settings/models/attachments.
- [ ] Mid-STREAM Stage Manager boundary crossing (highest-risk case):
      composer draft + staged attachments survive, transcript re-anchors.
- [ ] Column transparency: atmosphere spans behind both columns — if columns
      paint system backgrounds, Deep Field reads black (known risk).
- [ ] Pointer hover effects on buttons/rows/chips/cards/gauge.
- [ ] Hermes-switch nudge ("paired — add your key in Uplink"): confirm the
      `claude/t27-hermes-switch-nudge` branch (ef5dbd9) merge state FIRST —
      if unmerged, it's a pre-launch micro-merge.

### Sweep logistics

- Sessions V, C, S are iPhone-only and independent — any order. Session D
  needs the Mini deploy + ojamd-deploy rebase first (Claude preps both, you
  gate the OJAMD DC switch). Session J needs the iPad and ideally the nudge
  merge resolved.
- After each session I write results back to OPEN_ITEMS (surgical doc
  commits) and flip items to ✅ where the DoD closes.

---

## Part 2 — New polish lanes (proposed, not yet in OPEN_ITEMS)

Candidate OPEN_ITEMS entries — say the word and I append them (own commits,
max-number check first). Ordered by launch impact. Dispatch-ability noted.

### P-1 Empty & error states audit (Fable-dispatchable, medium)
Sweep every user-facing surface for: empty states (conversation list, Health
Trends pre-data, inbox, files) and error copy. Standard: the #71 banner
pattern — reason-specific, actionable, no raw HTTP codes or "gateway"
jargon on free-tier surfaces. DoD: inventory doc + fixes; a free-tier user
never sees a Hermes-internals term in an error.

### P-2 Accessibility pass (split: Fable audit lane + Owen device pass)
VoiceOver labels on custom surfaces (voice overlay, ToolConfirmationCard,
ChartCanvas, briefing widget); Dynamic Type at XXL/accessibility sizes
(#75 HUD truncation rides this lane); Reduce Motion honored by Lane E
atmospheres; contrast check across all 8 Midnight Marquee palettes + Deep
Field. Payoff: honest Accessibility Nutrition Label claims on the listing.
DoD: VoiceOver end-to-end chat + voice session; no truncation at largest
Dynamic Type on HUD/settings/cards; Reduce Motion verified.

### P-3 Release-build hygiene + MetricKit (Claude/Fable, small-medium)
**Decision: MetricKit-only.** (a) Audit every DEBUG harness is compiled out
or env-gated in Release: #134 forced-trip, #120 UITEST_DUPID_PROBE seam,
wire probes, #131 instrumentation, TALARIA_IOS27_INTENTS flag state.
(b) Add an MXMetricManager subscriber: persist crash/hang/energy payloads
locally, surface in Diagnostics (no network egress — matches the privacy
posture). (c) os_log level sweep: .notice instrumentation added during
debugging (Spotlight, controls, push) demoted or kept deliberately —
decided per line, not left by accident. DoD: Release archive audit clean.

### P-4 App Store package (Owen + Claude, no code)
- Screenshots: 6.9" + 13" iPad sets (iPad in scope); Midnight Marquee
  themes are the visual asset. Preview video: voice session + chart render.
- Privacy nutrition labels: HealthKit, location, motion, mic, speech,
  contacts (iMessage tooling is host-side — verify what the APP declares
  vs what Hermes does; the label covers the app binary only).
- Reviewer notes: free tier is fully standalone (the #71/#137 reviewer
  path); Connected tier explained so nobody attempts to pair; demo
  instructions if App Review asks.
- Boring blockers: privacy policy URL, support URL, age rating, export
  compliance (standard HTTPS answer). EULA note for BYOK/Connected tier.
- ASC product + sandbox purchase for #127 (already tracked; pre-flip gate).

---

> **Runbook added 2026-08-09 (#166f, bar 166-F).** The four subsections below are
> hermex's runbook skeleton translated onto Talaria — **Stop Conditions, Review
> Notes, Known Risk Register, Definition of Ready.** #166f's own instruction is
> *"fold into the existing launch-pass doc rather than a new file,"* and the
> second half of that bar is the part that gets forgotten: **no new runbook
> document exists outside `dispatch/`** — `find . -path ./.claude -prune -o -iname
> '*RUNBOOK*' -print` returns only `dispatch/OPUS-T27-166-8-appstore-runbook.md`.
>
> Statuses below were read at HEAD `bfbd154` on 2026-08-09. **The single largest
> unknown in this whole section is the Developer Portal / App Store Connect state,
> which is not inspectable from the repo** — it is 166e, it is Owen's, and its
> checklist lives in `handoffs/OWEN-166e-PORTAL-CHECKLIST.md`.

#### P-4.1 Stop Conditions

**Any one of these unmet means the submission does not go.** Not a preference — a
stop.

| # | condition | state 2026-08-09 | owner |
|---|---|---|---|
| S1 | **Privacy-policy URL live and linked** from at least one public surface | 🔴 **BLOCKED — none exists.** `grep -rniE 'privacy.?polic' README.md SECURITY.md docs/*.html` returns nothing. #166a's hard stop | Owen (Claude can draft the text from real data flows) |
| S2 | **Support URL live** | 🟠 not confirmed | Owen |
| S3 | **ASC app record exists** for `org.aethyrion.talaria27` | 🟠 ASSUMED, unverifiable from the repo | Owen |
| S4 | **Export compliance answered** | ✅ `project.yml:352` — `ITSAppUsesNonExemptEncryption: false` ships, so ASC stops asking per upload | done |
| S5 | **Monetization gate inert** — no reachable purchase surface | ✅ `MonetizationGate.swift:29` `isEnabled = false`. **Three** paywall presentation sites — `ContentView.swift:233-234` (inline `ConnectedPaywallView()`), `ServerSettingsScreen.swift:230-231` and `UplinkSettingsScreen.swift:163-164` (both `.sheet(isPresented: $paywallPresented)`) — and **four** gate checks that are the only way to reach them (`ContentView.swift:233`, `ServerSettingsScreen.swift:456` and `:470`, `UplinkSettingsScreen.swift:566`), every one testing `container.connectGateVerdict(for:)`. With `isEnabled = false` the verdict is `.allow`, so none renders. `MonetizationGateTests` pins dormancy — *"the test fails loudly on flip day"* (#127) | done, re-verify at archive |
| S6 | **Release archive validates clean** — zero ITMS errors | 🔴 never run. Bar 166-C | archive = Claude · **Validate = Owen** |
| S7 | **Purpose strings name the app, not the host** | 🔴 14 of 16 say "Hermes". Bar 166-D; proposal in `handoffs/DRAFT-166-PURPOSE-STRINGS.md` | Owen approves, then Claude edits `project.yml` |
| S8 | **Portal capabilities match the binary** — incl. **WeatherKit** | 🟠 ASSUMED. If WeatherKit is not on the App ID **the archive fails** | Owen (166e) |
| S9 | **Age rating set** | 🟠 not confirmed | Owen |

**And the standing one that outranks all of them:** *outward-facing submissions need
Owen's read of the exact text plus his explicit go.* Nothing in P-4 sends anything.

#### P-4.2 Review Notes (166c — drafted, AWAITING OWEN'S APPROVAL)

**Bar 166-B: a person who has never seen this repo must be able to read this and
predict what the app does when launched cold.** Five paragraphs, ≤2 pages. This is
the text that goes in App Store Connect's *Notes for Review* field. **Owen approves
the exact wording before it goes anywhere near ASC.**

> **1 — No account, no login, nothing to configure.**
> Talaria has no sign-up, no sign-in, and no server of ours behind it. Launch it and
> it works. There is no demo account to provide because there are no accounts at all.
> Nothing is required from the reviewer beyond installing and opening the app.
>
> **2 — The on-device brain is the reviewable product.**
> The app's chat runs entirely on-device using Apple's FoundationModels framework. No
> network connection of any kind is needed to exercise the core experience: open the
> app, type a message, get a streaming reply. Sessions persist locally, read-aloud
> works, and the device tool belt (calendar, reminders, contacts, weather, health,
> alarms and timers) runs against the reviewer's own device with the system's normal
> permission prompts. **The app works in airplane mode**, and that is the intended
> default experience, not a fallback.
>
> **3 — The optional "paired" features need hardware the reviewer does not have, and
> that is normal for a self-hosted client.**
> Talaria can additionally connect to a *Hermes* AI agent that the user installs and
> runs on their own computer, over their own private network. There is no hosted
> service to point it at — by design, since the entire premise is that the user owns
> the machine. Features in this tier (server-side chat sessions, the user's desktop
> model roster, the sensor pipeline, realtime voice, the agent inbox) therefore cannot
> be exercised without the reviewer standing up their own server, and we do not ask
> them to. This is the same shape as any self-hosted client — an SSH client, a NAS
> app, a home-automation controller — where the server is the user's own. **Every
> paired feature degrades to a clearly-labelled unavailable state rather than an
> error**, and the app never blocks on pairing.
>
> **4 — Why background location and background audio are declared, and why sensors
> are off by default.**
> `UIBackgroundModes` includes `location` and `audio` (`project.yml:353-357`).
> **Background audio** is real and straightforward: voice mode is a continuous
> speech-to-speech conversation that must keep running when the screen locks.
> **Background location** exists only for the optional sensor pipeline in the paired
> tier, which delivers location, health and motion context to the user's own machine.
> **That pipeline is opt-in and ships OFF** — the user must enable it explicitly in
> Settings, per sensor, and it is unreachable entirely for a user who has not paired a
> host. No location data is collected on a default install. Each permission is
> requested just-in-time at the moment the feature is first used, never at launch.
>
> **5 — No purchase flow is reachable in this build.**
> The app contains scaffolding for a future paid "Connected" tier. It ships **dormant**:
> the gate constant is `false`, every one of the three paywall presentation sites is
> behind that gate, and a test in the suite fails loudly if it is ever flipped without
> intent. **There is no purchasable item, no restore flow, and no paywall a reviewer
> can reach.** If and when the tier is enabled, it will be submitted with its product
> configured and exercisable.

**Do not add to these notes:** any claim about *why* the ATS exception works. The
mechanism is disputed in-repo (#166b vs #167) and unresolved pending bar 140-D. **The
notes are shorter and safer without it, and nothing above needs it.**

#### P-4.3 Known Risk Register (#166a–j, statuses at 2026-08-09)

| id | risk | status at HEAD | evidence / next step |
|---|---|---|---|
| **166a** | Privacy manifests missing | ✅ **DONE** 2026-07-22 (`6d1515e`, under #167) | `Talaria/Resources/PrivacyInfo.xcprivacy`, `TalariaWidgets/PrivacyInfo.xcprivacy`, `TalariaShare/PrivacyInfo.xcprivacy` all exist. **#166's own entry still describes this as open — see the tracker corrections.** *Its separate half — the public privacy-policy URL — is stop condition S1 and is NOT done* **⟵ 2026-09-01: "DONE" was true for EXISTENCE and premature for COMPLETENESS — the manifests declared only UserDefaults while the app grew three more required-reason API uses. Closed in PR #401 (`562267f6`) with a source-derived drift tripwire; the policy URL published 2026-08-10.** |
| **166b** | Global ATS exception (`NSAllowsArbitraryLoads`) | ✅ **DONE** 2026-07-22 (PR #138, `d3c962d`) — **with a caveat** | `project.yml:345-348` — range-scoped `NSExceptionDomains` keyed `"100.64.0.0/10"`. **What shipped is not in dispute; *why it works* is.** #166b (load-bearing, four-arm **sim** experiment) vs #167 (inert; bare IPs unpoliced). Bar **140-D** decides it and needs a device. **Consequence here is narrow: the review notes and the App Privacy answers must not repeat a mechanism we cannot defend** |
| **166c** | Review-notes framing | 🟡 **DRAFTED 2026-08-09** — P-4.2 above | Re-scoped by Owen 2026-08-01 to a writing task, under one condition: the monetization gate ships dormant. **Condition re-verified at HEAD (S5) — the ruling stands.** Corollary: *the day "Connected" becomes purchasable, the reviewer-reachable-host question comes back* |
| **166d** | Export-compliance key absent | ✅ **DONE** 2026-07-22 (under #167) | `project.yml:352`. **#166's entry still describes this as open** |
| **166e** | Portal capability pre-flight | 🔴 **NOT STARTED — Owen's.** Checklist written 2026-08-09 | `handoffs/OWEN-166e-PORTAL-CHECKLIST.md`. **The filed checklist was wrong three ways**: push must come OUT (`aps-environment` absent from `project.yml` and all three `.entitlements`; #238), Siri is not an entitlement we carry (App Intents need none), and **WeatherKit was missing entirely** (`project.yml:52`) — without it on the App ID, **the archive fails** |
| **166f** | Runbook skeleton | ✅ **DONE 2026-08-09** — this section | Folded into P-4, not a new file. `find … -iname '*RUNBOOK*'` returns only the dispatch |
| **166g** | TestFlight upload rehearsal *(absorbs #8)* | 🔴 **NOT STARTED, and correctly blocked** | Prereq chain: **166e → Release archive → 166-C Validate → internal testers → Beta App Review (external only)**. #8's four filed clauses are all falsified — see the tracker corrections. **No build is created by this lane** |
| **166h** | **NEW** — CarPlay scene declared with no CarPlay entitlement | 🟠 **CONFIRMED at HEAD, unresolvable from the repo** | `project.yml:364-370` ships `CPTemplateApplicationSceneSessionRoleApplication` → `CarPlaySceneDelegate` while the entitlement at `:61` is **commented out** (correctly — #45/#74 parked). App builds and runs; the scene never connects. **Risk is at upload validation.** Surfaces at *Validate App* (S6). **Do not pre-emptively strip the manifest** — it may validate clean, and removing it undoes #74's local CarPlay-Simulator path |
| **166i** | **NEW** — every permission dialog says "Hermes"; `NSHealthUpdateUsageDescription` claims a write we never do | 🔴 **CONFIRMED at HEAD.** Proposal drafted | 14 of 16 app purpose strings begin "Hermes" (`project.yml:150-158`, `:165-175`) while the display name is `Talaria27` (`:116`) and the default user is hostless. **`LiveHealthService.swift:70` passes `toShare: []` and no `healthStore.save` exists anywhere — so `NSHealthUpdateUsageDescription` (`:152`) should be DELETED, not reworded.** Bar 166-D; text in `handoffs/DRAFT-166-PURPOSE-STRINGS.md`. **Launch-blocking subset of #255 — must not wait for the full de-branding sweep** |
| **166j** | **NEW** — background location + background audio have no recorded defence | ✅ **DEFENCE NOW WRITTEN** — P-4.2 ¶4 | `project.yml:353-357`. Both are defensible (sensors opt-in and off by default per #137; voice mode is real background audio) — the gap was that the defence existed only in tracker entries. **Option A of the purpose-string draft moves it into the permission dialogs themselves**, which is the cheapest place to make it |

**Two risks that belong to other lanes and are named so they are not re-discovered:**
`docs/index.html:91` and `README.md:34` both say *"NO APP STORE · NO TESTFLIGHT"* — true
today, **false the moment 166g runs** (owned by #140's public-face lane, deliberately
deferred there); and #255's full de-branding, of which only 166i's strings move now.

#### P-4.4 Definition of Ready

**Submission is ready when every line is true.** Not "mostly" — this is the checklist
that replaces judgement at 2am.

- [ ] **All nine Stop Conditions (P-4.1) green.** S1 (privacy-policy URL) is the one
      that gates everything and has no in-repo workaround.
- [ ] **166e complete** — three bundle IDs, App Group on all three targets, HealthKit
      on app **and** widgets, **WeatherKit on the app**, **no push**, **no SiriKit**,
      CarPlay not requested.
- [ ] **Purpose strings pass bar 166-D** —
      `grep -n 'UsageDescription' project.yml | grep -i hermes` returns nothing, and
      `NSHealthUpdateUsageDescription` is gone. **`xcodegen generate` re-run and the
      generated `Info.plist` confirmed to carry them** (these keys are silently
      dropped if written as `INFOPLIST_KEY_` settings — the #58 lesson).
- [ ] **`scripts/mac/lane-gate.sh` PASS with a positive Release marker** (bar 166-E).
      A green Debug suite cannot see a mis-set gate — #218's corollary.
- [ ] **Release archive produced**, then **Owen presses Validate**, and it returns
      **zero ITMS errors** (bar 166-C). This is the only check that can see 166h's
      CarPlay mismatch and any ITMS-91053 the privacy manifests missed.
- [ ] **Review notes (P-4.2) approved by Owen verbatim** and pasted into ASC's *Notes
      for Review*.
- [ ] **App Privacy questionnaire answered**, and its answers **cross-checked against
      `SECURITY.md`** — specifically: health is read-only, no push, no data collected
      by us, location only via the opt-in sensor pipeline. A questionnaire that
      contradicts our own security doc is worse than a slow review.
- [ ] **Screenshots** — 6.9″ **and** 13″ iPad sets **if iPad is still in v1.0 scope.**
      ⚠️ **That decision is this doc's own header line (`:5`) and has gone unre-confirmed
      since 2026-07-20; #109 is still open on the live board. It doubles the most
      expensive job in P-4. Owen re-affirms or drops it before the batch is shot.**
- [ ] **#127's IAP product created but NOT submitted** — creating
      `org.aethyrion.talaria27.connected` early unblocks the sandbox round-trip;
      submitting it for review against an inert gate is the 2.3.1 shape. **Create
      early, submit at the flip.**
- [ ] **The public "no App Store / no TestFlight" copy is corrected in the same change
      that makes it false** — `docs/index.html:91`, `README.md:34`, and
      `docs/index.html:215`. Close-out rule: upstream, same commit.

### P-5 Feature discoverability — TipKit (Fable-dispatchable, small)
Three or four dismissible tips, first-eligible-moment triggered: Siri phrase
is "Ask Talaria27" (surface after first successful chat), share extension
(after first attachment), Talk mode (after N text turns), chart toggle
(first numeric table). No onboarding tour. DoD: tips fire once, dismiss
persists, VoiceOver-accessible.

### P-6 Feel polish (Fable-dispatchable, small)
Haptics: send (light), tool-confirm approve (success), voice session
start/stop (rigid/soft), briefing arrival. Launch-screen-to-first-frame
continuity with the active theme (check against #136's faster splash drop).
Scroll perf spot-check on a 200+ message transcript under Midnight Marquee.

---

## Part 3 — Already-tracked items promoted to launch-critical

- **#104** Sensor outbox churn: the cap + debounce have never been exercised
  under a real outage — battery/thermal is a review-visible risk. Device
  verify under a forced connector outage.
- **#111** Verify the ModelManager XPC flood is gone from Console on the
  next device build (fix merged PR #104; this is the ✅ condition).
- **#113** Connector watchdog INSTALL on OJAMD (your gate) — unsupervised
  connector died silently for 9 days once (#103); not shipping Connected
  tier with that exposure.
- **#127** ASC product + sandbox purchase before any monetization flip.
- **#24e** Diagnostics-panel check — fold into Session S if convenient.

---

## Part 4 — Sequencing

**Phase 1 (now):** Sessions V + C + S on whoGoesThere — pure device time,
nothing blocks them. In parallel: Claude preps the Session D deploys (Mini
restart on main; ojamd-deploy rebase queued for your DC switch) and drafts
the P-1/P-5/P-6 dispatch specs (staleness-checked per the hard rule).

**Phase 2:** Session D (dual-host) + Session J (iPad) once prerequisites
clear. Fable lanes P-1, P-5, P-6 run concurrently — none collide with the
sweep surfaces if sequenced after Session C closes chat items.

**Phase 3:** P-2 accessibility (wants a stable UI, so after P-1/P-6 land),
P-3 release hygiene + MetricKit, then the P-4 App Store package against
the near-final build. #127 sandbox purchase last, gate flip at launch.

**Exit criteria for "shiny":** all Part 1 boxes checked, P-1..P-6 DoDs met,
Part 3 items ✅, remaining growth items (#101, #109, #123–125 unbuilt
halves, CarPlay #45/#74) explicitly deferred to post-launch in OPEN_ITEMS.
