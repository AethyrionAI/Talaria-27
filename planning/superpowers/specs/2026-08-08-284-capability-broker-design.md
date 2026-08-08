# #284 CapabilityBroker — design spec

> **OUTCOME 2026-08-08:** Stages 1-2 shipped. The §5 probe ran on device (valid run
> `0AF5A6D8`, build 2225): gate 100% MET, danger 4.76% vs ≤2% MISSED, in-scope exact-set
> 37.5% MISSED (every miss a superset — zero under-arming). Per §5.3's pre-registered
> response, §6 selective arming did NOT ship; §4's toolless question REOPENED by same-day device evidence: the vector routes capability-meta armed, but PRODUCTION's one-Bool router routes it toolless (build 2225, reply named zero families) — the §4 toolless-index arm is live; see the #284 correction note. Verdict:
> OPEN_ITEMS #284, 2026-08-08.

**Date:** 2026-08-08. **Tracker:** OPEN_ITEMS #284. **Approved by:** Owen (scope,
selection mechanism, and probe-first routing all chosen in the 2026-08-08
brainstorming session; vision-union rule added on his question).

**Provenance:** `planning/reports/2026-08-07-open-source-momentum-report.md` §1
(the OpenWork `search_capabilities` pattern, adapted); #284's tracker entry
(grounding validated 2026-08-07 against tracker, code, and the external repos);
the beta4 swiftinterface findings recorded in the entry 2026-08-08.

---

## 1. What this lane delivers

Three stages. Each is independently valuable; later stages are gated on
earlier evidence, and the lane closes honestly at whatever stage the evidence
supports.

1. **CapabilityRegistry** — ships unconditionally. One source of truth
   describing every device-belt tool, derived from the live belt so it cannot
   drift.
2. **Bool-vector router probe** — a measured device experiment with bars
   pre-registered in the OPEN_ITEMS #284 entry **before the run** (the
   post-#215 convention). Owen routes the verdict.
3. **Selective arming** — ships only if the probe clears its bars. If it
   fails, the lane still closes having fixed #257, and context reclaim waits
   for the MCP era (#150), where the in-turn discovery shape — which #217B
   never tested — becomes the candidate.

**Drivers (from the #284 entry):** #257 (the local brain under-describes its
own capabilities — root cause is the hand-written blurb at
`LocalChatBackend.swift:1845`), #229 (belt ≈ 18% of the 8,192-token window on
armed turns), #150 (MCP would multiply capabilities past what any window
holds). #101 stays sequenced behind this lane and consumes the budget this
lane measures free.

## 2. Decisions taken (and their record)

| Decision | Choice | Why |
|---|---|---|
| Lane scope | Registry + **pre-turn** selective arming | The mid-turn re-arm (`init(model:tools:transcript:)`) is real but unnecessary: `preparedSession` already recreates the session whenever the offered tool set changes for a turn (`LocalChatBackend.swift:875`). Pre-turn selection needs zero new session-lifecycle code. |
| Selection vehicle | The **existing router generation**, extended | #217B proved a second field costs the armed/toolless Bool nothing (gate 100% in all four cells). No added latency. |
| Selection schema | **Independent per-domain Bools**, NOT a multiway intent | **#217/#217B falsified multiway intent classification** (all four cells 2.6×–10× over the danger bar; zero abstentions in 380 classifications — the model always commits on a multiway choice). The Bool vector is #217B's own surviving hypothesis: the model demonstrably CAN decline on a binary (200/200 lifetime). Un-parked at Owen's direction 2026-08-08 for this probe. |
| Vision tools | **Excluded from the vector; armed by the #176 image gate, union'd on top** | Image presence is a deterministic client-side signal — strictly stronger than a model guess. See §6, rule V. |

## 3. CapabilityRegistry

### 3.1 Descriptor

```swift
struct CapabilityDescriptor {
    let id: String                // == Tool.name, e.g. "readCalendar"
    let semanticDescription: String
    let source: CapabilitySource  // .device now; .hermes / .mcp / .skill are cases only
    let group: CapabilityGroup    // arming unit, §6
    let riskClass: RiskClass      // .read / .write (write == confirmation-gated)
    let permissions: [String]     // e.g. "HealthKit", "EventKit" — display names
    let argumentSummary: String   // one line, human-readable
}
```

`availability` and `privacyClass` from the report's sketch are **deliberately
dropped this lane** (YAGNI): availability is a live question answered per-turn
by the tools themselves (the belt's honesty rule — a tool that can't answer
says why), and privacyClass has no consumer until the memory layer (#101).
The struct gains fields when a consumer exists.

### 3.2 Construction and drift protection

- Each belt tool type declares its own descriptor via a small protocol
  (`CapabilityDescribing`). The registry is **built from the live belt
  instances** at the existing single build site (`AppContainer.swift:940-957`)
  — it structurally cannot describe a tool the belt doesn't carry.
- **Pinning tests, the `actionToolNames` pattern (#200), bidirectional:**
  every belt tool has a descriptor; every descriptor's id names a real belt
  tool; every tool maps to exactly one group; every group maps to at least
  one tool. A new tool that forgets its descriptor fails the suite.
- `CapabilitySource` has `.hermes`/`.mcp`/`.skill` cases **unpopulated** —
  the shape #150/#163 land into, not features built now.

## 4. The #257 fix — honest self-description

Two surfaces:

**Armed instructions.** The blurb at `LocalChatBackend.swift:1845` keeps every
measured behavioral clause byte-identical. Only the capability *enumeration*
("their health, location, schedule, reminders, contacts, and past
conversations") becomes registry-generated — from the **offered subset for
this turn**, preserving the #176 invariant already stated at
`LocalChatBackend.swift:905-907`: the persona never advertises a tool this
session wasn't given. A new tool then appears in the persona's self-description
automatically; #257's staleness class is closed structurally.

**The toolless trap — measured, not guessed.** "What can you do?" plausibly
routes toolless today, where the instructions read "no external tools in this
mode" — the model would *deny* capabilities it has. The probe grid (§5) gets a
"what can you do?" row to establish where it actually routes:

- Routes **armed** → the registry-generated armed blurb already answers it;
  no toolless change.
- Routes **toolless** → a one-line registry-generated capability index is
  added to the toolless branch ("you can read the user's health, calendar, …
  when asked — offer to do so"). That edits the measured toolless-lic2
  payload (60/60 on device), so it runs as **its own measured arm in the same
  device run** — never a silent edit to promoted text.

**The #257 bar (first bar of the lane):** a fresh session asked "what can you
do?" names every capability family in the belt — device-verified, the #257
screenshot shape inverted.

## 5. The Bool-vector probe

### 5.1 Schema

One guided generation — the same call, session shape, and options as the
production router — generating the gate Bool plus ~10 independent domain
Bools: `wantsCalendar`, `wantsReminders`, `wantsAlarms`, `wantsHealth`,
`wantsWeather`, `wantsPlaces`, `wantsContacts`, `wantsConversations`,
`wantsDeviceStatus`, `wantsLocation`. No vision field (§2). No multiway enum
anywhere in the schema.

Guide text follows #217B's v2 finding (the one thing that consistently
helped): each Bool carries a positive test it must meet; the framing is a
certainty rule, not an exclusion list. Per #217B's teach-to-the-test
discipline, the guide must not name the trap rows' domains
(music/navigation/photos/etc.).

### 5.2 Grid

Reuse #217B's 19-row grid (retained in `+IntentRouting.swift` as DEBUG
artifacts for exactly this), extended with:

- multi-intent rows ("what's my day look like" → calendar+reminders+weather),
- the "what can you do?" row (§4),
- the out-of-vocabulary traps **kept** (music, driving-time, bottle label) —
  under the vector the correct answer is all-false → full belt.

n=5 per row (#217B: zero variance in 380 classifications; n=10 bought
nothing).

### 5.3 Bars — exact numbers copied into the OPEN_ITEMS #284 entry before the run

- **Gate:** armed/toolless Bool ≥95% (must not degrade; #217B measured 100%
  with a second field across four schemas — ten fields is what this probe
  tests, not assumes).
- **Dangerous ≤2%**, where dangerous = *the narrowed belt lacked a tool that
  full-belt production behavior would have used on that prompt*, scored
  against each grid row's expected-tool annotation (the #217B scoring
  discipline — expectations written into the grid, not judged after the
  fact). This is the #217B bar, unchanged, because the harm is unchanged: a
  wrong narrowing IS #257's symptom.
- **In-scope groups exact-set ≥90%** (the exact expected group set on rows
  with a non-empty expectation — as registered in the OPEN_ITEMS entry; a
  looser earlier phrasing stood here until 2026-08-08).
- **Reclaim, measured:** `tokenCount(for:)` of the narrowed belt vs the full
  belt across the grid's armed rows — the number #101's sequencing waits for.
  No pass/fail bar; it is the lane's measured prize, reported alongside the
  verdict.

A missed bar is a falsification, not a redefinition. **Pre-registered
response to a failed danger bar: selective arming does not ship** — the lane
closes at stage 1+2 (registry, #257 fix, probe verdict recorded), exactly as
#217B closed. Owen routes the verdict either way.

## 6. Selective arming (ships only on a cleared probe)

- Route result becomes `(needsDeviceTool: Bool, groups: Set<CapabilityGroup>)`,
  stored per-turn beside `turnRoutedToolless`.
- `effectiveOfferedTools` filters the belt through the registry's group
  mapping. The existing recreate seam (`sessionToolNames` comparison,
  `LocalChatBackend.swift:875`) rebuilds the session when the set changes —
  no new lifecycle code.
- **Fail-open rules, each unit-pinned:**
  - **O1:** armed + **all Bools false** → full belt (abstention is safe by
    construction).
  - **O2:** router error/throw → full belt (today's exact fail-safe,
    unchanged).
  - **O3:** routing disabled for the launch (DEBUG legacy cells) → full belt;
    the measured cells stay pure.
  - **V:** **an image in context always unions the vision tools onto whatever
    the vector armed** — the #176 gate arms vision; the vector can narrow
    everything else but can never take vision away.
- Multiple true Bools arm the union of their groups.
- The #229 overflow retry stays routed-toolless, untouched.
- The armed blurb enumerates the offered subset (§4), so instructions and
  belt cannot disagree.
- **Rollback is one flag:** selective arming off → armed turns get the full
  belt — today's behavior, byte-identical instructions.
- All promoted code lives outside `#if DEBUG`; the lane gate's Release build
  is the check (#218).

## 7. Measured budgets

`recordSessionBudgetIfVerbose` grows a registry-backed line: measured token
cost of the offered belt this turn, and of the full belt for contrast, via
`tokenCount(for:)`. **Between turns only** — `tokenCount()` concurrent with a
live streaming turn kills the turn on device (ModelManagerError 1001; the
recorded hazard in the #284 entry). This turns #229's one-off "≈18%" into a
per-turn number and produces #101's freed-budget figure.

## 8. Testing

- **Unit:** registry↔belt bidirectional pinning (§3.2); blurb generation
  deterministic and never names an unoffered tool; fail-open paths O1–O3 and
  V; group mapping total.
- **Device:** the probe run (§5) + the #257 bar.
- **Gate:** `scripts/mac/lane-gate.sh` (Debug suite + Release build) before
  any PR.

## 9. Out of scope, named

- MCP / Hermes / Skills registry population (enum cases only — #150/#163
  land here later).
- The in-turn `searchCapabilities` discovery tool (the OpenWork surface
  itself) — the MCP-era candidate, untested by #217B either way.
- Any new UI. (The Developer screen's verbose logging picks up §7's lines
  for free.)
- #101 — sequenced behind this lane by its own entry.
- `availability` / `privacyClass` descriptor fields (§3.1).

## 10. Sequencing inside the lane

1. Registry + pinning tests + registry-generated armed blurb (no behavior
   change beyond the enumeration text).
2. Probe schema + grid extension (DEBUG), bars copied into the OPEN_ITEMS
   entry, device run, verdict filed.
3. On a cleared verdict and Owen's promotion: selective arming + fail-open
   pins + budget lines. On a failed verdict: close-out with the verdict
   recorded, stages 1's deliverables shipped, arming untouched.

Every stage ends with the close-out rule applied: any entry, doc, or
CLAUDE.md line the stage's result falsifies is corrected in the same commit.
