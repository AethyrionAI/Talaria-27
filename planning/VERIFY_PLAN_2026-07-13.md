# Device Verify & Cleanup Plan — 2026-07-13

**Target:** whoGoesThere (iPhone 17 Pro Max) · UDID `91CBCB90-B313-5B09-A405-E0FE284C9D75`
**Repo:** `AethyrionAI/Talaria-27` · `main @ cf5609f` (OPEN_ITEMS accuracy audit merged today)
**Sim (fallback):** iPhone 17 Pro · UDID `CA43C8CF-D393-4E0E-BB1A-0F465135F349`
**Why tonight:** the 2026-07-13 audit found ~25 items that are *merged on main, one device pass from ✅*. This session clears that backlog and isolates what's actually left.

## How to run this (with Sonnet/Opus driving)
1. Work top-down; each BATCH is one sitting on the same surface — do them without switching context.
2. For each item, open `OPEN_ITEMS.md` at the cited line and read its **Mac-session checklist** — that's the exact API/edge list. This doc is the driver + verdict log, not a replacement for the item's own criteria.
3. Log a verdict inline on each line: `✅` clean / `🔧` partial (note what's left) / `❌` fail.
4. **At session end**, batch the flips into OPEN_ITEMS.md in one commit: `✅` for clean passes, leave `🔧` + a dated note for partials, open a `🐛` for anything that fails.

## Prereqs (same planes as the 07-10 doc)
- **Chat plane:** DIRECT → `ojamd:8642`, API key in Keychain (Host badge: LINKED·DIRECT).
- **Relay plane:** paired; Tailscale up; OJAMD relay live at `100.110.102.59:8000` (Reachability leaves STANDBY).
- A **real Hermes conversation** open to work in.
- Themes for legibility spot-checks: **Deep Field** (dark) + **Paper Tape** (light).

---

## BATCH 1 — Chat / message surface  *(one chat session)*

- [ ] **#18** session shelf — open the shelf. **Expect:** scrim dims chat and the toolbar behind it is **non-tappable**. **Fail if:** a toolbar button fires through the scrim. · `OPEN_ITEMS.md:454`: Pass
- [ ] **#31** paste image → **send** — copy an image, paste into composer, send it. **Expect:** inlines and the agent actually receives it (full paste→send round-trip). **Fail if:** paste previews but send drops it. · `:955`
- [ ] **#57** attachment inline + OCR — send `.txt/.md/.csv/.json` (should reach the agent as text) and run **Extract Text** on a screenshot + a multi-page PDF. **Expect:** text parts arrive; PDF OCRs into `## Page N`; un-extracted PDF holds send with a badge. · `:1655`
- [ ] **#59** voice-memo attachment — **airplane mode**: record a multi-minute memo → on-device transcribe → stage → play; then send over tailnet. **Expect:** no truncation on the long memo; audio never transmits; transcript sends as text. · `:1716`
- [ ] **#75** HUD single-line — drive a long header label. **Expect:** stays single-line (no wrap/truncate). · `:2298`
- [ ] **#77** `hermes://` deep link — fire `hermes://chat` and `hermes://…ask?q=…` from Safari/Shortcuts. **Expect:** opens the right surface; `ask?q=` pre-fills. (Base already proven during #58 triage.) · `:2369`
- [ ] **#78** message context menu — long-press a message: copy / share / select / regenerate / edit. **Expect:** all five work. · `:2405`
- [ ] **#99** interactive HTML preview — get the agent to emit an HTML artifact, open preview. **Expect:** renders. **Known v1 gap:** remote subresource fetches not yet blocked (WKContentRuleList) — note it, don't fail on it. · `:3196`
- [ ] **#93** continuity — only unconfirmed piece is the **CondenserFidelity** run (journal→transplant fidelity). Use the §3a brain-hop transplant from the 07-10 doc. · `:3027`

## BATCH 2 — Voice / talk mode  *(one talk session)* Voice wedged. Tests not performed.

- [ ] **#56** Ask Hermes intent — remaining sub-checks only (core passed 07-11): **>25s long-run hand-off** ("still working" then reply lands in-app), **Siri Stop** cancels, **tailnet-unreachable** surfaces the real error. **Product call:** the bound phrase is "Ask Talaria27" (= CFBundleDisplayName); decide accept-as-is vs rename. · `:1615`
- [ ] **#73** native fallback voice — SpeechAnalyzer → active backend → AVSpeechSynthesizer, end-to-end. **Expect:** speak → transcribe → reply → spoken back. · `:2169`
- [ ] **#84** talk preflight — open Talk. **Expect:** blocks with guidance, does **not** hang or falsely show "Connected"; mic-denied → Settings deep link; capture-wedged (#82) → **reboot** wording. · `:2735`
- [ ] **#67** LocalChatBackend — switch to the on-device brain, run its device checklist. · `:1944`
- [ ] **#68** ChatBackendRouter — two-brain seam switches cleanly; **2 product decisions owed** (read the item). · `:1979`
- [ ] **#102** local-brain generation health — trigger **organically** (not forced): confirm no phrase-loop / thermal runaway in normal use. · `:3218`

## BATCH 3 — OS integrations  *(each needs a specific system action)*

- [ ] **#63** background wake — BGAppRefresh + BGContinuedProcessing fire a run in the background. · `:1850`: Pass
- [ ] **#64** health widget — tiles read HealthKit directly (grant perms first). · `:1874`: Pass
- [ ] **#65** AlarmKit `/alarm` — set an alarm via the confirm gate; it **rings through Silent mode**. · `:1895` Pass
- [ ] **#66** Spotlight — search surfaces a session → tap → OpenSessionIntent opens it. · `:1917` Fail
- [ ] **#61** on-device titles/previews — FoundationModels names/previews conversations on device. · `:1787` Fail - repeats the first line of conversation given by the model on both lines. Not performed
- [ ] **#81** lock-screen reply — reply to a Hermes notification from the lock screen (UNTextInputNotificationAction). · `:2579`: not performed

## BATCH 4 — Onboarding + themes

- [ ] **#71** standalone onboarding — best on a **fresh install**: launch with no pairing → app is usable without the pairing wall. · `:2089`: Pass
- [ ] **#50** terminal accent lock — Terminal theme keeps its locked accent (`lockedAccentSlot`) regardless of the accent picker. · `:1481`: Pass
- [ ] **#112** Midnight Marquee / Comic Book — **live-switch:** Settings → toggle system appearance while foregrounded → villain↔funnies re-skins **without relaunch**; spot-check the 13 new icons; light-chrome pass on **Pulp Noir / Sticker-Bomb**. Two known seams to eyeball: (a) picker card previews the presented-surface variant while a fixed theme forces the scheme; (b) cold light-mode launch may flash the villain half for one frame. · `:3401` Not performed (waiting on build at home)

## BATCH 5 — Relay + data path  *(relay up + phone together)*

- [ ] **#53** sensor drain — location/health outboxes decoupled: confirm no drain/backlog storm; outboxes flush independently. · `:1508` Pass
- [ ] **#21** Tier-2 file fetch — ⚠️ **app-side fetch isn't built yet** — build it first, then verify agent-generated files download in-app. · `:515` Make spec to have this built. 

## BATCH 6 — iPad  *(Shelley's spare)*

- [ ] **#108** iPad split view — run the universal + native split-view device matrix. · `:3336` Fail. Needs work for iPad side. I could get her device to talk to the local model after it downloaded, but not to hermes. 

---

## NOT verify — real bugs (need a fix; a device pass won't close them)
- **#25** 🐛 CTX meter — device-verify already FAILED (0 on some sessions, absent on old ones, flashes wrong); root cause unpinned. Next: capture a live session w/ Verbose Logging + `run.completed` payloads, ground-truth vs Hermes's own context check. · `:823`
- **#58** Ask-control wiring bug localized in `HermesControls.swift` (rest of item passed; Talk control is #82-wedged, not a defect). Fable-sized fix. · `:1684`
- **#60** `_thinking` delta-key device probe — still investigating. · `:1743`
- **#104** sensor-outbox churn — full rewrite owed (rewrites whole file each tick, main actor, unbounded backlog). · `:3238`
- **#110** read-aloud speaks the collapsed loop — breaker-trip vs speech-queue. · `:3373`
- **#111** 🐛 PCC availability check churns doomed ModelManager sessions on every UI tick. · `:3383`

## Blocked / elsewhere — don't queue these on the device tonight
- **Apple entitlement grant:** #45 + #74 (CarPlay voice), #72 (PCC tier).
- **OJAMD deploy owed:** #85 (hermes_delegate path), #86 (QueuePool fix) — deploy from the relay host, not the phone.
- **Mac / server work:** #34 + #107 (T6 Mini execution), #80 (server-side #58 inbox), #24e (diagnostics panel), #51/#52/#62 (Mac test-infra + stale xcscheme).

## Session verdict log
| # | verdict | note |
|---|:--:|---|
|   |    |    |

*When done: fold verdicts back into `OPEN_ITEMS.md` (flip clean → ✅, keep partials 🔧 + dated note, open 🐛 for fails), one commit. Then this doc can be renamed to a `HANDOFF-2026-07-13-*` like the others.*
