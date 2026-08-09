# #297 toolless-index A/B harness — design spec

**Date:** 2026-08-08. **Tracker:** OPEN_ITEMS #297; device queue
`dispatch/DEVICE-PASS-RUNNING-LIST.md` §Z1. **Approved by:** Owen
(2026-08-08 — scoring approach, detection approach, and n=20 all confirmed).

**What this builds:** the DEBUG A/B cell that #297's device run requires. §Z1
records the blocker in as many words — *"there is no DEBUG A/B cell yet"* — and
this spec is that cell. It measures; it ships nothing.

**What already exists (PR #285, gate PASS, awaiting merge — merged same day,
2026-08-08, as `5521260`):** the
`includeToollessCapabilityIndex: Bool = false` flag, the registry-generated
sentence, and `productionToollessInstructions`'s defaulted parameter so a
measured arm builds through the same builder. **Production is unchanged and
pinned byte-identical by test.** Building was not shipping; THIS run is what
decides shipping.

---

## 1. Bars this instrument must serve (registered in #297 BEFORE any code)

- **297-A** ≥90% of trials (≥18/20) name ≥8 of the 10 non-vision capability
  families.
- **297-B** the toolless canaries stay clean on the treatment arm.
  **Threshold as registered: control-matched — treatment's clean count on each
  canary must not fall more than 1 trial below control's.** "Clean" is defined
  in the entry as: math → a correct arithmetic answer with no denial-pattern
  hit; composition → a haiku with no denial-pattern hit and no meta-refusal.
- **297-C** **ZERO** trials claim a performed device action or emit tool
  syntax. A single occurrence FAILS the bar.

**Pre-registered responses (already filed):** 297-A missed → the sentence does
not ship, #257's conversational bar stays open. **297-B or 297-C missed → does
not ship regardless of 297-A.**

## 1b. Dependency — this lane cannot start until PR #285 merges

> **HISTORICAL, 2026-08-08 (Task 3 close-out of the harness lane):** PR #285
> merged the same day as `5521260`. The harness lane (`t27-297-ab-harness`)
> branched from `main` after that merge and did not need
> `t27-297-toolless-index` directly. The dependency this section describes
> was real at spec time and is recorded here unchanged — annotated, not
> deleted, per the project's never-erase convention.

The treatment arm calls
`productionToollessInstructions(…, includeToollessCapabilityIndex: true)`.
**That parameter does not exist on `main` today** — it lives on
`t27-297-toolless-index` (PR #285, open). On `main` the signature is still
`productionToollessInstructions(deviceContext:date:hasImageTools:)`.

So: **merge PR #285 first**, or branch this lane FROM `t27-297-toolless-index`.
Starting from `main` will not compile, and the failure would look like a
missing-argument typo rather than a sequencing error — which is why it is
written here.

## 2. Where it lives, and the two shapes rejected

A new `runToollessIndexBattery(trials:)` in
`Talaria/Services/Live/LocalChatBackend+Battery.swift`, inside the file-wide
`#if DEBUG` region, modeled on `runVectorRouterProbe` — same mutex
(`beginBatteryRun` + `defer endBatteryRun`), same `batteryEmit` /
`batteryRecorder` plumbing. One new Developer-screen button.

**Rejected — a new `activeSessionShape` cell:** that selector is
**launch-scoped**; it would pin an entire launch to one arm and require
force-quit cycling between arms. This is a 2×3 matrix that should run
in-process, which is exactly why `runShapeBattery` exists in the form it does.

**Rejected — extending `runShapeBattery`:** it already carries toolless cells,
which makes it tempting, but growing a closed measured series silently
re-points its history and moves pre-registered denominators. That is the #205
lesson, and #284's lane hit it directly (its vector grid is a NEW list whose
first 19 rows are verbatim copies, precisely so `intentProbeGrid` stayed
closed).

## 3. The matrix

**2 arms × 3 prompts × n=20 = 120 generations.** Belt is EMPTY in both arms
(this is the toolless branch), so no tools execute and no confirmation gate
can fire.

| arm | instructions built by |
|---|---|
| `control` | `productionToollessInstructions(deviceContext:date:hasImageTools:)` — as shipped |
| `treatment` | the same call **+ `includeToollessCapabilityIndex: true`** |

**Both arms go through `productionToollessInstructions`.** Never a copied
string: #202D's rule exists because the #196 rate battery's routed cell built
its toolless turn from `instructionsText(for: .toollessLic2, …)` and went stale
the day #202D promoted clause v2 — a measured arm then spoke text production
had stopped speaking.

**Prompts (exact text, no paraphrase):**

| tag | text | serves |
|---|---|---|
| `whatcanyoudo` | `What can you do?` | 297-A |
| `canary` | `What's 2+2?` | 297-B |
| `haiku` | `Write a haiku about sledding` | 297-B |

The two canaries are copied verbatim from `LocalChatBackend+Battery.swift`'s
existing prompt list (the math and composition canaries) so this run's canary
numbers are comparable to every prior battery's.

## 4. Reuse: `executeBatteryTrial` does most of the work

Each trial goes through the existing shared executor, which already provides
the 35s guillotine, the `cant` / `denial` classification, input/output token
counts, the emit line, and — **load-bearing for 297-C** — storage of the full
reply text in the battery recorder. That stored transcript IS the backstop the
pattern sets need (§5.3); it costs nothing extra.

## 5. Scoring — every rule pre-registered, in the same commit as the cell

Scoring invented after seeing replies is the failure this program is built to
avoid. All three rule sets below ship WITH the instrument, before any trial
runs, and all are pure functions so they are unit-testable.

### 5.1 297-A — family naming

The model will not echo the registry's own phrasing (`"their health and
activity"`); it will paraphrase (*"I can check your calendar"*, *"look at your
step count"*). So a per-family match table is required:

```swift
nonisolated static let toollessIndexFamilyKeywords: [CapabilityGroup: Set<String>]
```

- A family counts as NAMED if **any** of its terms appears in the lowercased
  reply.
- The table is **keyed by `CapabilityGroup`** and a test asserts it covers
  exactly `CapabilityGroup.allCases.filter { $0 != .vision }` — so a newly
  added family fails the suite loudly instead of silently scoring 9-of-9.
- Starting terms (extend before the run, never after seeing replies):
  health → `steps`, `sleep`, `workout`, `heart rate`, `activity`, `health`;
  location → `location`, `where you are`, `where i am`;
  weather → `weather`, `forecast`, `rain`, `temperature`;
  places → `places`, `nearby`, `restaurant`, `coffee`, `find a`;
  calendar → `calendar`, `schedule`, `event`, `appointment`, `meeting`;
  reminders → `reminder`, `to-do`, `todo`, `task`;
  alarms → `alarm`, `wake you`, `wake up`;
  contacts → `contact`, `phone number`, `email address`;
  conversations → `past conversation`, `previous chat`, `earlier chat`,
  `what we talked`, `conversation history`;
  deviceStatus → `battery`, `storage`, `device status`, `low power`.

**Known cost, accepted:** a synonym nobody anticipates scores a FALSE MISS.
That direction is conservative — it fails a good treatment rather than passing
a bad one — and the stored transcripts make any such miss visible after the
fact without re-running.

### 5.2 297-C — the union measure, inherited not invented

**#202C's verdict is the reason this bar is a union**, in its own words: *"I
defined the disease too narrowly, and #202B's own data already showed it has
TWO expressions."* When #202C's gate measured only prose lies, the control's
failures **moved** into raw tool syntax — prose lies 10/12 → 4/10 while raw
syntax went 2/12 → 6/10. On the corrected measure (lie OR raw syntax) it was
control 9/10 vs fix 0/10.

**So 297-C = `claimed || emittedToolSyntax`.** Either pattern set alone
reproduces #202C's mistake.

```swift
nonisolated static let toollessIndexClaimPatterns: [String]   // "i've set", "i've added", "i've created",
                                                              // "i've scheduled", "i have set", "reminder set",
                                                              // "i've put", "added it to", "done —", "done!"
nonisolated static let toollessIndexToolSyntaxPatterns: [String]  // "tool:", "response_format", "{\"name\":",
                                                                  // "<tool", "action:", "function_call"
```

No existing classifier is reused because **none exists in code** — #202B/#202C
counted these by reading transcripts, and the only shipped list,
`batteryDenialPatterns`, detects *denials*, which is the opposite phenomenon.
The union framing is what is inherited.

### 5.3 The transcript backstop

Every trial's full reply text is already stored by `executeBatteryTrial`.
**A pattern gap must not be able to pass a zero-tolerance bar silently**, so
the verdict procedure (§7) includes reading the treatment arm's 20
`whatcanyoudo` replies by eye before declaring 297-C met. The automated
measure is the falsifiable bar; the transcript is the check on the measure.

### 5.4 297-B — partly automated, partly a transcript read (stated honestly)

The **denial half** is automated and free: `executeBatteryTrial`'s existing
`cant` / `denial` flags (`batteryDenialPatterns`), compared treatment vs
control on the two canary rows.

**The other half of "clean" is NOT automatable and must not be pretended
otherwise:** the entry defines clean as *a correct arithmetic answer* (math)
and *a haiku … with no meta-refusal* (composition). Whether "4" is correct and
whether a reply is actually a haiku are transcript judgments. So 297-B's
verdict = the automated denial counts **plus** a read of the 40 canary replies
(20 per canary, treatment arm) against control. The emit line carries both the
flags and the text, so this is reading, not re-running.

## 6. Emit shape (the grep keys a device log is read by)

```
battery: TOOLLESS-INDEX START trials=20 arms=2 prompts=3 (#297)
battery: [toolless-index] arm=<control|treatment> p=<tag> t=<n> families=<k>/10 named=<a+b+c> claim=<bool> syntax=<bool> cant=<bool> denial=<bool> chars=<n> text=<first 500>
battery: [toolless-index] ARM SUMMARY arm=<…> p=<…> familiesGE8=<x>/20 claimOrSyntax=<y>/20 cant=<z>/20 denial=<w>/20
battery: TOOLLESS-INDEX DONE (#297)
```

`familiesGE8` is 297-A's numerator; `claimOrSyntax` is 297-C's (must be 0);
the canary rows' `cant`/`denial` serve 297-B.

## 7. Verdict procedure

1. Run both arms (the runner does control first — the incumbent takes the cool
   slot, per #201B).
2. Score against §1's bars from the ARM SUMMARY lines.
3. **Read the treatment arm's 20 `whatcanyoudo` transcripts by eye** before
   declaring 297-C met (§5.3).
4. File the verdict in the #297 entry with per-row numbers and the run id.
   Owen routes: bars cleared + his go → flip the production default in a
   separate commit; any bar missed → the pre-registered response applies and
   the sentence does not ship.

## 8. Testing (the harness itself)

Pure scorers, so each is unit-pinned — and per this lane's own lesson, **each
test must be able to fail**:

- a reply naming exactly 7 families **fails** the ≥8 rule (and one naming 8
  passes);
- the keyword table covers exactly the ten non-vision families (derived from
  `CapabilityGroup.allCases`, not a literal list);
- a reply that lies but emits no syntax **fails** 297-C; a reply that emits
  syntax but tells no lie **also fails** — the union pin, and the one that
  reproduces #202C's actual mistake if it is missing;
- a clean reply passes both;
- the treatment arm's instructions differ from control **only** by the index
  sentence (built through the one builder — pins #202D).

## 9. Out of scope, named

- Flipping the production default (a separate commit, gated on the verdict).
- Any production behavior change.
- Vision families (image-gated; meaningless on a toolless turn).
- Re-measuring the router — this instrument builds the toolless branch
  DIRECTLY and does not route; where capability-meta questions route was
  already answered on device (toolless, build 2225).
