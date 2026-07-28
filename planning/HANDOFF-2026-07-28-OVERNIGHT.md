# HANDOFF — 2026-07-28 overnight (#196 batteries 3+4, the routed cure, autonomous device runs)

**Session:** local Claude Code (Fable 5) on Owen's Mac, checkout `/Users/owenjones/Documents/Claude/Talaria-27`.
**Owen's standing goal (set ~00:10, /goal):** "fix the internal model and make it compatible with
Talaria. It should be able to answer those 3 [canary/haiku/norway — he corrected '4'→'3'] 100%
of the time." Owen is asleep; phone is NOT corded (be battery-considerate: at most one more
device run overnight; iterate on the Mac harness instead).

## Branch / PR topology (read this before touching git)

- `main` @ `dac495b` — has the battery-3 OPEN_ITEMS results note. Docs go direct to main.
- [PR #160](https://github.com/AethyrionAI/Talaria-27/pull/160) `claude/t27-196-decomposition-cells`
  @ `26094e8` — battery 3 (six decomposition cells). **UNMERGED — the auto-mode classifier
  blocks `gh pr merge`; Owen must merge.** Suite was 1244/109 green.
- [PR #161](https://github.com/AethyrionAI/Talaria-27/pull/161) `claude/t27-196-routed-cure`
  (stacked on #160, base = decomposition branch) @ `b45ec7b` + uncommitted auto-battery seam
  (see "In flight"). Suite 1247/109 green (verified the new tests RAN — see gotcha below).
- Merge order: #160 → #161. Both carry evidence-scope statements in their bodies.

## Battery 3 (decomposition) — RUN, VERDICTED, FILED

Six cells, n=20/cell, Debug `26094e8`, whoGoesThere, 2026-07-27 23:32–23:50 CDT. Full table +
analysis filed in OPEN_ITEMS #196 (`dac495b`). Headlines (all classified from raw text):

| Cell | Canary (clean) | Haiku (clean) | Grabs | Norway (clean) |
|---|---|---|---|---|
| armed | 13/20 (5) | 15/20 (2) | 19/20 | 5/20 (0) |
| armed-noinstr | 16/20 (12) | 15/20 (6) | 18/20 | 1/20 (0) |
| toolless-noinstr | 18/20 (0) | 16/20 (2) | 0 | 1/20 (0) |
| armed-readonly | 17/20 (13) | 6/20 (0) | 0 | 6/18 (0) |
| armed-nocall | 14/20 (5) | 19/20 (0) | 0 | 1/20 (0) |
| armed-noschema | 17/20 (8) | 10/20 (0) | 0 | 2/19 (0) |

**The decomposition:** (1) GRABS = action-schema VISIBILITY (noinstr grabs 18/20 with zero
instructions; noschema 0/20 with tools callable but schemas hidden; nocall/readonly 0
structurally). (2) DISCLAIMERS = belt PRESENCE (nocall: haiku 19/20 content but 0/20 clean —
schemas in context sustain the tic with calling impossible). (3) READONLY IS A TRAP (haiku
collapsed to 6/20 — read-only belt deepens the "data-reader" identity). (4) toolless-noinstr
FALSIFIED the Shortcuts-replica premise: the bare session hallucinates a tool harness
(`tool:`/`response_format:`/JSON/XML) — instructions SUPPRESS the scaffold, they're
load-bearing. (5) Norway sick everywhere structurally; licensing prose remains the only cure.
THE BAR not met by any cell. ERROR trials (excluded): readonly norway t9 (Weather), t14
(Health), noschema norway t20 (Health) — #197's family. Classification caveat: my "clean" bar
is stricter than battery-2's "clean opens" — compare within-run only.

Part 0 SDK findings (verified, drove the v2 dispatch): `GenerationOptions.toolCallingMode`
(.allowed/.required/.disallowed, per-call, iOS 27) and `Tool.includesSchemaInInstructions`
(iOS 26, per-tool, default true — pinned by a bare-conformance probe test).

## Battery 4 (the routed cure) — BUILT, DEPLOYED, RESULTS PENDING

**Architecture (PR #161):** per-turn guided-generation ROUTER (few-shot, greedy, 64-token cap,
fail-safe to armed) classifies each turn. Device turns → production armed session, untouched.
Words-only turns → `toolless-lic2`: the licensed bare branch + TWO device-observed canary
fixes — a math/facts license ("Simple math and everyday factual questions you answer directly
yourself.") and an output-format mandate ("Reply in plain conversational prose — never JSON,
XML, code blocks, or tool syntax unless the user asks for them."), with NO belt registered.
Live path rides the #176 session-recreate seam (`turnRoutedToolless` set in preparedSession;
gates in effectiveOfferedTools/effectiveInstructionsText). WWDC26 session 242 sanctions
contextual tool withholding (their own sample flips toolCallingMode on app state).
`batteryCells = [armed, toolless-lic, toolless-lic2, armed-routed]`; armed-routed battery
trials log `route=` lines; new Diagnostics "Router probe n=20" button measures classification
alone.

**Mac-host evidence (26.5-gen model — DIRECTIONAL ONLY, 4096 ctx, does NOT reproduce the
device's canary disease):** harness at scratchpad `fmprobe/` (battery.swift / router2.swift /
final.swift + logs). Router few-shot: **200/200 at n=20** across 10 probes. CRITICAL finding:
the guide-only router framing misroutes EVERY creative verb to the device (haiku/norway/joke
0/8) — the #196 task-verb confusion lives in classification too; few-shot examples fix it
completely; flipped polarity ("answerableWithWordsAlone") collapses to always-true. lic2:
59/60 clean (the 1 miss = a #102-family repetition loop; the phone's breaker collapses those).
Baseline lic swept 24/24 locally; my augmented v2/v3 variants caused persona meltdowns —
dropped. Doc gather: WWDC26 242 (toolCallingMode intent + agentic patterns), Apple's internal
prompt templates (special tokens `specialToken.chat.role.*`, short imperative prompts,
few-shot + format mandates = in-distribution), tech report arXiv 2507.13575.

## In flight RIGHT NOW (background task b06a928qz)

The **auto-battery seam** (uncommitted on `claude/t27-196-routed-cure`, 4 files):
- `LocalChatBackend`: `batteryEmit(_:)` — battery/router lines to BOTH os_log and stdout
  (text prefix widened 180→500 for classification); all 9 battery+probe log sites converted.
- `DeviceToolBelt`: ToolEventRelay battery `tool=` lines mirrored to stdout.
- `AppContainer` (end of file): `runAutoBatteryIfArmed()` — `TALARIA_AUTO_BATTERY=n` /
  `TALARIA_AUTO_ROUTER_PROBE=n` launch env runs battery then probe headlessly;
  `isIdleTimerDisabled` for the duration; same auto-decline contract as the button.
- `AppEntry`: calls it after `container.initialize()` (DEBUG only).

Device build+install running in background. NEXT STEPS when it lands:
1. Commit the seam (file-scoped) on `claude/t27-196-routed-cure`, push (updates PR #161).
2. Launch headless: `DEVICECTL_CHILD_TALARIA_AUTO_BATTERY=20 DEVICECTL_CHILD_TALARIA_AUTO_ROUTER_PROBE=20 xcrun devicectl device process launch --console --device 91CBCB90-B313-5B09-A405-E0FE284C9D75 org.aethyrion.talaria27 > capture.log` (backgrounded; ~20 min; SILENCE in the log = stale binary, rebuild with Intermediates purge). Bundle id `org.aethyrion.talaria27`; device UDID above; app path `…/DerivedData/Talaria-gzpowyfsuofejnbsytskngrskzkm/Build/Products/Debug-iphoneos/Talaria 27.app`.
3. Classify from raw text (content = the answer/haiku/summary delivered; clean = no disclaimer
   open/decline-apology/tool offer/garble; exclude ERROR trials from denominators, list them).
4. VERDICT vs the goal: `armed-routed` needs 20/20 CONTENT ×3 prompts + router probe holding
   both directions on the 27b4 model. If met → goal met; file OPEN_ITEMS note (own commit,
   direct to main) + report. If NOT met → iterate the payload prose ON THE MAC harness
   (fmprobe/), one more device run at most tonight (phone uncorded), else leave the next
   device run for Owen with everything staged.
5. Promotion to production (armed-routed → default) is a SEPARATE decision — Owen's verdict
   desk. Do NOT ship it into the Release path overnight. The held battery-2 candidates stay
   untouched.

## Gotchas learned tonight (also in auto-memory)

- **Xcode-beta4 stale incrementals (bit TWICE):** build-for-testing can silently reuse stale
  objects (exit 0; old test binary ran 1244 instead of 1247; earlier: undefined-symbol link
  vs old memberwise inits). ALWAYS grep the test log for a NEW test's name; fix =
  `rm -rf <DerivedData>/Build/Intermediates.noindex`. DerivedData for this checkout is
  `Talaria-gzpowyfsuofejnbsytskngrskzkm` (NOT the CLAUDE.md one — different checkout path).
- **Xcode MCP bridge RunProject times out** on clean device builds (exceeds request cap);
  warm builds are ~2s. GetConsoleOutput is per-launch-session — a devicectl-launched process
  has NO bridge session; that's why the auto-battery mirrors to stdout.
- **`gh pr merge` is classifier-blocked** in auto mode. Owen merges.
- **FoundationModels runs on this Mac** (26.5-gen host model, Apple Intelligence enabled) —
  a plain `swiftc -framework FoundationModels` CLI works; the fmprobe/ harness is reusable.
  toolCallingMode is iOS/macOS 27-only — nocall-style cells canNOT be iterated locally.
- devicectl env passing = `DEVICECTL_CHILD_` prefix; `--console` bridges stdout only.

## Questions for Owen (morning)

1. Merge PRs #160 → #161 (classifier blocks me).
2. Battery-4 device verdict will be in the final report / OPEN_ITEMS — if armed-routed cleared
   the bar, decide promotion (router in the production path: one extra ~1s guided generation
   per turn — acceptable latency?).
3. The `armed haiku t11` fabrication ("I've also created a reminder" after decline) from
   battery 2 still wants its own OPEN_ITEMS item.
4. #197 (ToolCallError machinery) keeps surfacing in batteries (3 more tonight) — priority?
