# HANDOFF — 2026-07-27 evening: the battery era begins

Read `planning/HANDOFF-2026-07-27-TESTING-WEEKEND.md` for the morning's frame; this supersedes
its "in flight" sections. Everything below happened TODAY.

## Where the day ended

**Merged to main (in order):** #153 (#117 backoff) → #152 (#189/#147 notifications, + a
@preconcurrency compile fix I authored) → #151 (190B, after the device gate CLEARED — open-by-tap
re-verified passing) → #154 (#58 controls, Owen merged; I paid its compile debt with a suite run)
→ #155 (191-192-193, + my makeRouter protocol-widening fix) → #156 (176B/#194/#186, exonerated of
a phantom UI-test regression) → #157 (176C: session-shape instrument + roster-sentence removal,
whole, after the desk A/B convicted the enumeration) → **#158 pending at handoff time** (see
below). #195 (flaky MessageIdentity typeText) fixed direct-to-main, closed.

**Expected main baseline after #158:** ~1235/109 + 15 XCUITest (confirm on first touch).

## The #194/#196 investigation — state of knowledge

Read OPEN_ITEMS #194, #196, #197 fully. The one-line history: creative refusals → 176B licensing
clause fixed FACTUAL fixation (2+2/Greece answered offline, device-verified) → desk A/B convicted
the roster sentence (#157 merged its removal) → refusals persisted anyway → single-shot cells
were declared insufficient (behavior is a probabilistic mixture) → **an in-process rate battery
was built** (one tap in Diagnostics, 4 shapes × 2 prompts × 10 trials, results to Console as
`battery:` lines) and produced the first real measurement, n=10/cell:

| Cell | Haiku content | Haiku clean-open | Reminder grabs | Norway content |
|---|---|---|---|---|
| armed (production) | 6/10 | 2/10 | 8/10 | 4/10 (0 clean) |
| armed-direct | 6/10 | 4/10 | 4/10 | 1/10 |
| armed-noneg | 8/10 | 3/10 | 10/10 | 0/10 |
| toolless | **10/10** | **10/10** | 0 | 0/10 |

**Mechanisms identified (the real payload):**
1. **Task-verb confusion** — "write a haiku" parses as a TODO; the model creates a reminder
   titled "write a haiku" (8/10 in production!). The belt's presence, not its description prose,
   drives creative failure. Fix candidate: ReminderTool description scoped to "only when the
   user asks to be reminded of something" — fix the tool, not the prompt.
2. **Knowledge-denial on composition** — "summarize Norway" → "I can't access external
   knowledge," across ALL tool cells. The model equates composing-about-known-things with
   retrieval. The licensing clause covers recall, not composition. Fix candidate: extend the
   clause — "writing about what you already know is not retrieval."
3. **Tool-less branch never got the licensing clause** (deliberately untouched in 176B) and its
   on-device-only framing produced 0/10 on Norway with the purest denials. Fix candidate:
   extend the clause to the tool-less branch.
4. **armed-direct LOSES** (worse Norway, no haiku gain) — Part 2 dropped from #158 per the
   spec's own readout. Instruction stacking is not the road.

**Next lane (unwritten — first job of the next session):** mechanism-targeted cells, validated
by battery rates, not vibes: (a) ReminderTool description fix, (b) composition-licensing
sentence, (c) clause in the tool-less branch — each its own cell vs production control,
n=10-20. The battery makes each hypothesis a 10-minute experiment. Battery rev needed first:
**log every tool invocation** (read tools fired invisibly — two noneg trials leaked
ConversationSearch output; only action tools log today via the confirmation gate) and consider
n=20 + a third prompt ("What's 2+2" as the always-pass canary).

## PR #158 status

Branch `claude/t27-196-preface-tic` reconstructed at handoff: Part 0 (desk picker) + Part 1
(cells: armed/armed-direct/armed-noneg/toolless) + #197 OPEN_ITEMS filing + the battery
instrument (auto-decline flag on ToolConfirmationCenter + runShapeBattery + Diagnostics button).
**Part 2 (directness sentence in production) DROPPED** — measured a loser. Suite run was in
flight at handoff; merge on green (expected 1235/109). If unmerged when you arrive: verify
`git merge-base --is-ancestor 366519d origin/claude/t27-196-preface-tic` is FALSE, suite log at
/tmp/t27-158b-test.log, then `gh pr merge 158 --merge`.

## The instrument fleet (today's permanent infrastructure)

- **OTA deploy over Tailscale** — `scripts/mac/ota-stage.sh <branch> [Debug|Release]`, serve
  root `~/.talaria-ota/serve_root`, LaunchAgent `com.talaria.ota-http`, phone installs from
  `https://owens-mac-mini.tail5663a6.ts.net`. Debug config REQUIRED for any build that must
  carry the selector/battery (Release compiles them out). CLAUDE.md documents it + the
  do-not-relitigate block (Xcode connect-by-IP is REMOVED per Apple DTS; phone's
  lockdown/RemotePairing ports closed on the tailnet interface; pymobiledevice3 equally dead
  over tailnet).
- **Session-shape selector** — `TALARIA_SESSION_SHAPE` env OR persisted `debug.sessionShape`
  (DEBUG, read once per launch; Diagnostics picker; retired names parse to production).
- **The rate battery** — Diagnostics → Local brain panel → one tap. Auto-declines action-tool
  confirmations (the gate's continuation is deliberately non-cancellable — a headless session
  deadlocks without the flag; two runs wedged before this was understood).
- **Xcode MCP bridge** — works on beta-4 (config verified correct; xcode-select already at
  beta4). Crashes under heavy first calls: open with tiny tailLimit, filter with `pattern:`,
  keep windows small. RunProject device-install over WiFi can exceed the 4-min MCP ceiling —
  the launch usually succeeded anyway. **RunCodeSnippet CANNOT generate with FoundationModels**
  (ModelManagerError 1026 from the snippet host process) — in-app battery is the only harness.

## Open threads, ranked

1. **Next #196 lane** (mechanism-targeted cells, above) — write + send after battery rev.
2. **#197** — raw tool error rendered verbatim in transcript (type names + pointer!) with the
   turn dead + Retry; recovery clause unreachable for machinery-level failures. Filed on the
   PR branch. Design question for the fix: catch in the streaming path, friendly failure line,
   feed the error back as a tool RESULT so the model can recover?
3. **ojamd relay unreachable from the phone on home WiFi** — repeated NSURLError -1001 to
   `http://ojamd:8000/v1/commands` all evening. Relay down, or `ojamd` DNS from the phone?
   Check OJAMD services (memory: gateway is NOT NSSM; relay is `HermesMobileRelay`).
4. **#198 deprecation sweep — NOT YET FILED** (ran out of evening): ~20 warnings, 6 clusters
   (CLGeocoder→MapKit, BGTaskScheduler.submit, installTap, AVAudioSession InterruptionType/
   Options, LanguageModelSession.GenerationError, AlarmKit stopButton, + nonisolated(unsafe)
   DateFormatter ×3 in ConversationSearch). File it, then a disjoint Fable lane someday.
5. **Confirmation-gate cancellation** — the non-cancellable continuation vs #192's
   abandonActiveRun: if a run is abandoned with a card pending, does anything resolve it?
   Worth a deliberate test + possibly its own item.
6. Carried from the weekend, still owed: iPad lanes J/K matrix, Shelley iMessage E2E
   (#107/#114 DoD), connector watchdog install on OJAMD, #110 read-aloud fix verify, #58
   control-tap device pass (#179 decision rides on it), #152's notification device checks.

## Process learnings (new tonight)

- zsh kills shells on bare `===` (word-initial `=` expansion) — that was the session-long
  shell-death mystery. Never echo `===`.
- Never `sleep` >230s inside a DC call (4-min ceiling); poll from fresh short-lived shells.
- Owen's phone defaults carry the LAST picker selection across builds (same bundle id) — the
  "confirmed armed" run that was actually armed-direct cost an hour. **The Console
  `session shape:` notice is the only cell ground truth.**
- Fable's evidence-scope requirement (added to dispatch templates today) works: #155/#156
  declared honestly-uncompiled; both had exactly one compile bug each, caught cheaply in my
  worktree. #157/#158 ran on the real toolchain (Mac-side lane) and needed zero fixes.
- Single-shot cell verdicts on this model are UNRELIABLE — the afternoon "enumeration
  conviction" (n=4) didn't survive n=10. Rates or nothing.
