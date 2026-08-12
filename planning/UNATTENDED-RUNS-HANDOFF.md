# Handoff — conducting unattended instrument runs

**For the session that picks this up AFTER the trigger exists.** Written 2026-08-11
alongside `UNATTENDED-INSTRUMENT-RUNNER-PLAN.md`. If the trigger is not built yet, that
plan is your task and this document is not yet actionable.

**Read first, in this order:** `CLAUDE.md` · `planning/DEVICE-BACKLOG-TRIAGE-2026-08-11.md`
(the whole thing — §5's data ruling and §9/§9a's device rules are load-bearing) · this file
· then the specific tracker entry whose bar you are scoring.

---

## 1. The two devices, and the rule that is absolute

| host | what it may run | what it may NEVER run |
|---|---|---|
| **Shelley's iPad Air (M3)**, `4822A154-722B-53EB-81A2-84357FD03719` | write-free FM measurement — the reason it exists is that **simulators cannot generate** and this device can (verified 2026-08-11, `CondenserFidelityTests` 7/7 in 25.3 s) | **calendar, reminders, alarms — ever.** Not "with a container". Not "if reaped". Never. It is not Owen's device. |
| **`whoGoesThere`** (iPhone 17 Pro Max), `91CBCB90-B313-5B09-A405-E0FE284C9D75` | everything, including write cells | — |

**On Owen's phone, his 2026-08-11 ruling:** reminders **allowed** ("not worried about
stragglers"); calendar **allowed** (he has pointed it at a junk calendar that is not
shared); alarms **constrained** — *"please don't have surprise alarms for me while I'm at
work."* Standing consequence: **alarm-writing cells never run unattended.** They run only
when he has said go and is present.

**Apple Notes is NOT covered by that ruling** — he named three apps and Notes was not one.
Ask before running #33. (Notes read/write on the Mac host *does* work — probed
2026-08-11 via `hermes-mac`: AppleScript through Notes.app, write and read confirmed
separately.)

## 2. Preconditions — check, do not assume

Every one of these has failed silently at least once on this project.

- **The device is connected and unlocked.** `xcrun devicectl list devices`. A locked phone
  fails the build with *"needs to be unlocked to enable development services"* — before it
  reaches a test.
- **Auto-Lock is Never** for an unattended run. The battery buttons already set
  `isIdleTimerDisabled`, but only once a run has started.
- **TCC grants exist** for anything EventKit-adjacent on the phone. **A missing record
  HANGS the suite rather than failing it** — measured at ~20 minutes parked on one test,
  and the only tell was a log that stopped growing. Your harness needs a timeout; do not
  rely on noticing.
- **Signing works without an override.** `project.yml` teams `TalariaTests` and
  `TalariaUITests` as of 2026-08-11 (`DEVELOPMENT_TEAM` **and** `CODE_SIGN_STYLE` — XcodeGen
  emits neither `TargetAttributes` entry without the second). If you find yourself adding
  `DEVELOPMENT_TEAM=…` on the command line, something regressed.
- **`DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer`** in every shell.

## 3. The run procedure

> **✅ SUPERSEDED 2026-08-12 by #333 (merged `f8ec228`) — steps 3–5 are now ONE command:**
>
> ```bash
> DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer \
>   scripts/mac/run-instrument.sh --device <name-or-udid-fragment> \
>   --instrument <registry-name> --trials <n> [--timeout seconds]
> ```
>
> It does the baseline fetch, env launch (`DEVICECTL_CHILD_*`), wall-clock-bounded
> polling, artifact fetch, and the positive-completion check. Exit 0 = `completed` or
> `refused` (read the artifact's `status`/`refusalReason`); exit 1 = `failed`; exit 2 =
> TIMEOUT (store snapshots auto-fetched for the post-mortem, on-device app terminated);
> exit 3 = precondition (incl. a LOCKED device — it fails fast rather than burning the
> timeout). Artifacts land in `~/.talaria-instrument-runs/<stamp>-<instrument>/`.
> Registry names: see `InstrumentRegistry.swift` (~~45 entries; **16 unattended-eligible**~~
> **48 entries since #334, 2026-08-12; 19 unattended-eligible** — the three new
> FM measurement instruments write nothing, so all three are eligible on the iPad —
> alarm-writing instruments refuse unattended by Owen's ruling, and the iPad refuses all
> EventKit writers in-app). Run the harness BACKGROUNDED with an absolute project path
> and a tool timeout above `--timeout`. Steps 1–2 and 6 below still apply verbatim.

1. Pick the host by §1. If the instrument has *any* write cell, it is the phone.
2. Confirm the device is connected, unlocked, and grants are in place.
3. ~~Launch with the trigger env vars; **background it and poll with an `until` loop.**~~
   *(superseded above)*
4. ~~Fetch the artifact (`xcrun devicectl device copy from`) and assert on the JSON.~~
   *(superseded above)*
5. **Check the completion flag before reading any numbers.** A file that exists is not a
   run that finished. *(The harness enforces this; it holds for manual fetches too.)*
6. Score the bar from the artifact, at the bar's own home in `OPEN_ITEMS.md`.

## 4. Scoring — the rules that make a result count here

- **Bars are pre-registered in the OPEN_ITEMS entry, before the run.** A missed bar is a
  falsification, not a redefinition. If a bar turns out to describe a state production
  cannot reach, that is a **correction with evidence** — amend it, say why, and say plainly
  that it was amended. #327-A is the worked example: its pre-registered fixture was
  unreachable and the amended bar was *harder*.
- **A battery rate is a PRODUCTION rate only if the row was ROUTED** (#215). An unrouted
  cell arms every trial by construction and measures a configuration the app never enters.
  Read `runActionBattery`'s `routed-production` cell as the routed arm; every other wrapper
  is unrouted.
- **Instrument the error path.** A band with no error counter reports fail-safe noise as
  data. Constant denominators let swallowed trials read as clean.
- **Never collapse a union bar.**
- **Close-out rule:** the lane does not close until every entry, doc and CLAUDE.md line
  the result falsifies is corrected in the same commit, at the stale claim's own home.
  Archive corrections are append-only dated pointer blocks; archived bytes are never edited.

## 5. Hazards a new session will not otherwise know

- **`tokenCount` concurrent with a live streaming turn KILLS the turn.** #257's pre-flight
  must run outside a turn.
- **Model wall-clock is not a stable measurement on this hardware.** The same test measured
  **123.0 s, 20.9 s and 16.9 s** across three runs on two devices. Never pin a bar to
  elapsed time; pin token counts, call counts, and classifications.
- **The simulator cannot generate.** `availability == .available` and then a throw —
  `Code=5000` on beta4, an un-bridged `LanguageModelError -1` wrapping `ModelManagerError
  1026` on beta5, `contextSize == 0`. **Availability has lied twice.** Prove generation by
  generating.
- **This box has produced five distinct non-product failure signatures.** SIGKILL under
  memory pressure (zero tests, no count line); the `HTMLArtifactSandboxTests` 5 s WebKit
  budget under ≥3 concurrent builds (#324-W2); "runner hung before establishing connection"
  at low load, cleared by a sim reboot + TCC re-grant; ActivityKit's five-activity budget
  exhausted by a parallel test host (#326); and a stale-incremental green. **Check load and
  `pgrep -fl xcodebuild` before believing a failure — and never launder a real failure as
  environment.** The discriminator is a re-run on a quiet box at the same commit, and you
  say which one you used.
- **Never exceed 3 booted simulators.** Around 7, this Mac locks up and needs hands-on
  recovery.
- **Owen's phone's gateway runs on this same Mac.** Heavy builds starve it — a chat turn
  died at ~12 s during a three-lane evening. If he is using the phone, hold builds.
- **A count that did not move is the stale-binary signature.** After editing tests, confirm
  the reported count changed; if it did not, discriminate (look for the `SwiftCompile` line
  for your file) rather than assuming.

## 6. The queue, once the trigger exists

Roughly in value order. Host per §1.

| bar | instrument | host | note |
|---|---|---|---|
| #257 tokenCount pre-flight | ~~never built~~ **`tokencount-preflight`** (#334, 2026-08-12) | iPad | runs outside any turn by construction — no generation at all |
| #324-W3 | ~~not built~~ **`fm-asymmetries`** (#334) — all three bands in one run: `tokenCount` 4096-vs-8192, `variant.displayName`, `maximumResponseTokens` throw-vs-truncate | iPad | ⚠️ **beta5 runtimes ONLY** — the variant band is a new-in-beta5 symbol and a beta4 runtime kills the app at dyld launch (#324) |
| #211A | offer-instead-of-act on READ paths | iPad | read-only prompts by construction |
| #210A / #210 residual | ~~never measured~~ **`condensation-fit`** (#334) — one instrument answers both: does ONE forced condensation fit 8,192? | iPad | a trial scores only if ARMED (pre-count measured >8,192); if none arms, the residual stays open |
| #205E | ctx-a long-row probe | iPad | ~3,500-char prior turn + words-only counterpart |
| #208 | D4 corruption re-suspect | iPad | exploratory; the class has no standing suspect |
| #225 B1–B4 | the spiral cap: ≤12 calls, non-empty, honest, no collateral | **phone** | B4 writes a reminder; B3's honesty clause needs a human read — log the transcript |
| #199A | calendar misattribution | **phone** | writes; auto-accept |
| #279-F | retry question appears exactly once | **phone** | needs the #134 forced trip, currently a Developer button |

## 7. What to do with what you find

Findings go into `OPEN_ITEMS.md` at the owning entry, the same day, with the measurement
quoted rather than summarised. New defects get a number the day they are found (#268 — "a
phase name is not a filing"). If a result falsifies something already written — including
something *this* document says — correct it at its home in the same commit and say it was
corrected.

The device work on 2026-08-11 produced four new defects (#327, #328, #329, #330) and
corrected four confident claims that turned out wrong. **That ratio is normal here and is
the reason the runs are worth doing.**
