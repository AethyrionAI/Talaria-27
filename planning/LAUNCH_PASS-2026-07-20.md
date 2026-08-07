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
