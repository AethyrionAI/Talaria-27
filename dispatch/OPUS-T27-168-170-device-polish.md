# OPUS-T27-168/169/170a — Device-found polish: three labelling and affordance fixes

**Items:** OPEN_ITEMS #168 (a defect + a polish), #169, #170a · all found during the #171 device pass ·
**Repo:** AethyrionAI/Talaria-27 · **Base:** main · **Branch:** `claude/t27-168-170-device-polish` ·
**Size:** small, one PR, five file-scoped commits
**Staleness check:** re-run at start (`gh pr list --repo AethyrionAI/Talaria-27`,
`git log --grep t27-168`). OPEN_ITEMS numbers ≠ GitHub numbers.

## Mission

Three independent fixes across three files, bundled because each is a few lines and they
share a root cause: **a correct value under a label or affordance that invites a wrong
belief.** None is a data bug. All three were invisible to the 1088-test suite and were
found by a human tapping through the app (#171).

Every claim below was verified against source at the cited line before this spec was
written. Do not re-derive; do verify the line numbers still match before editing.

Each part is independently revertable. If one turns contentious, ship the others.

---

# PART A — #168 Skills picker (`TaskSkillsPicker.swift`)

## D1 — 168a: exit from EDIT AS TEXT (the only real defect in this lane)

`@State private var useFreeText` has exactly **one write site** — `useFreeText = true`
at ~line 122. Nothing sets it back. Tapping EDIT AS TEXT swaps the picker for a raw
`TextField` permanently, for the life of the sheet.

The caption at ~line 90 already promises the missing control:
`"COMMA-SEPARATED — PICKER AVAILABLE WHEN NOT EDITING AS TEXT"`. **The UI documents a
return path the code never implemented.**

**Fix:** in `freeTextField`, when `pickerSkills != nil`, render a control that sets
`useFreeText = false`. Mirror the existing EDIT AS TEXT styling (`MonoLabel`, size 8,
`Design.Tracking.mono`, `Design.Brand.accent`); suggested label `USE PICKER`.

**When `pickerSkills == nil` the toggle must NOT appear** — free text is then the only
available mode, and offering a picker that cannot open is a second dead end. Replace the
now-redundant "PICKER AVAILABLE WHEN…" caption in the picker-available case (the button
is self-describing); keep the `"COMMA-SEPARATED SKILL NAMES ON THE HOST"` caption for the
nil case unchanged.

**What this unblocks:** the "(custom)"-value preservation property (156b D5, #160 idea 1)
is currently **unverifiable on device** — you cannot type an unknown value in text mode
and return to the picker to see it pinned, because you cannot return. Model-level tests
cover the logic; this makes it reachable. #171 records that assertion as owed and it gets
re-run after merge.

## D2 — 168b: retry from the degraded state (polish)

Root cause, verified — an earlier "nothing ever re-fetches" claim was WRONG and is
corrected in #168:

- `TaskEditSheet.swift:78-82` already has `.task { await skillsStore?.refresh() }` —
  every create/edit sheet retries on appear.
- `TaskEditSheet.swift:187` gates on success:
  `skills: (skillsStore?.hasLoaded == true) ? skillsStore?.skills : nil`
- `SkillsStore.refresh()` sets `hasLoaded = true` **only on success**; its catch block
  deliberately preserves prior rows and leaves `hasLoaded` alone.

So a cold-offline launch correctly degrades to free text — but `TaskSkillsPicker` takes
`skills` as a plain `let`, and the retry only fires on sheet appear. Restoring
connectivity mid-sheet changes nothing until dismiss-and-reopen. Owen's device repro
matched exactly.

**Fix (preferred):** in the nil-list free-text case, add a RETRY affordance that re-invokes
the store refresh so the field can upgrade to a picker in place. `TaskSkillsPicker` needs a
way to ask its parent to refetch — **pass a closure down; do not give the view its own
store reference.** `SkillsStore.refresh()` already no-ops while `isLoading`, so a
disabled/spinner state during the attempt is sufficient guarding.

> **⚠️ Do NOT "fix" this by making `SkillsStore.refresh()` set `hasLoaded` on failure.**
> That would break the browser's keep-rows-on-failure contract, which passed device
> verification in #171 (airplane refresh kept all 98 rows behind a `Refresh failed —
> showing last fetch` strip). `SkillsStore` is off limits in this lane.

## D3 — 168 label clarity

EDIT AS TEXT reads as single-skill editing. Owen — who knows the field is a
comma-separated list — still read the raw text box as "edit this one skill's name" during
device testing. If the person who designed the data model misreads it, users will.

Relabel to something unambiguous about editing the whole list (e.g. `EDIT LIST AS TEXT`),
and/or keep the existing placeholder (`skill-one, skill-two (optional)`) visible as a hint.
Label/hint change only — no layout redesign.

---

# PART B — #169 Insights cost caveat (`InsightsScreen.swift`)

The totals card renders a 2×2 grid (TOKENS IN / TOKENS OUT / TOOL CALLS / API CALLS) with
`EST COST ~$2.59 — COVERS 21 OF 230 SESSIONS` as a full-width row **inside the same card**,
directly beneath the grid.

The coverage caveat belongs to the cost figure **alone** — the four totals above it cover
all fetched sessions. Sharing a card makes "COVERS 21 OF 230" read as a footnote on the
entire panel, i.e. as though the token and call totals were also computed from only 21
sessions. That is a factually wrong reading of correct data, and it **understates the
totals by an order of magnitude**. Owen's verbatim reaction on device: *"made me double
take thinking that was the cost for everything above it."*

## D4 — separate the cost element

**Preferred fix:** move the EST COST row **out of the totals card** into its own adjacent
card, making the caveat's scope structural rather than typographic.

Acceptable alternatives if that reads badly in the layout: fold the scope into the label
itself on one line (`EST COST · 21 OF 230 SESSIONS WITH COST DATA`), or add a hairline
separator plus indent so the row reads as a distinct block.

> **Do NOT solve this by dropping the coverage caveat.** It is the honest-absence rule
> working: only 21 of 230 sessions carry a nonzero `estimated_cost_usd`, and
> `actual_cost_usd` is null on all of them (verified live). The caveat is the honest part;
> only its apparent scope is wrong.

Note for context: the #156d spec predicted this row would be ABSENT on this host. That
prediction was wrong — the Mac host has 21 sessions with real costs, so the cost path
renders and was exercised on device. Tolerant decoding handled a case the spec did not
anticipate.

---

# PART C — #170a Task detail model labelling (`TaskDetailScreen.swift`)

## D5 — stop presenting a snapshot as a pin

`TaskDetailScreen.swift:297-298`:

```swift
let model = job.model ?? job.modelSnapshot
let provider = job.provider ?? job.providerSnapshot
```

The coalescing **collapses a distinction that matters.** Verified against the live host for
a phone-created job:

```
model             = None          <- job is UNPINNED
provider          = None
model_snapshot    = 'MiniMax-M3'
provider_snapshot = 'minimax-oauth'
```

So the card renders the snapshot under a bare "Model" label, which reads as *"this job runs
on MiniMax-M3."* The truth is *"this job runs on whatever the host's global default is **at
fire time**; the default happened to be MiniMax-M3 when it was created."*

Upstream is explicit (`cron/jobs.py:1026`): *"Agent cron jobs with unpinned provider/model
follow global config at fire time. Capture the current resolution for each unpinned axis so
a later [swap] ... is detected"*. `_resolve_default_model_snapshot` (`:969`) exists purely
for that drift guard. **The snapshot is frozen at creation and never updates.**

Concrete consequence on Owen's setup: he set MiniMax as the Mac's global default
deliberately (cheaper for testing, saving kimi-k3 for real work). When he flips the default
back, every unpinned job silently starts running k3 — while the app displays "Model:
MiniMax-M3" forever.

**Fix:** distinguish the two cases. The model layer already keeps them separate
(`CronJob.swift:19-22`: `model`, `provider`, `providerSnapshot`, `modelSnapshot` all decode
independently), so this is view logic only:

- `job.model != nil` → render `metaRow("Model", model)` as today. The job IS pinned and the
  plain label is correct.
- `job.model == nil` but a snapshot exists → render something that conveys "follows the host
  default, and that default was X at creation". Suggested:
  `metaRow("Model", "Follows host default — was \(snapshot)")`, or a two-line row. Exact
  wording is the implementer's call; the requirement is that a reader cannot come away
  believing the job is pinned.
- Same treatment for provider.

Keep the `hasContent` gate behaviour unchanged (the panel should still appear when only a
snapshot exists).

**Out of scope, deliberately:** adding a model *picker*. #170b established that the phone
cannot pin a model at all on hermes-agent 0.19.0 — `_handle_create_job`
(`api_server.py:4259-4264`) reads only `name`/`schedule`/`prompt`/`deliver`/`skills`/`repeat`,
and the PATCH whitelist excludes model too. Do not work around this with a relay endpoint
that writes `jobs.json` directly; that bypasses upstream validation and desyncs the drift
guard.

---

# D6 — Tests

Swift Testing. Extend existing files rather than adding new ones where possible
(`SkillsPickerSelectionTests` for Part A; the Insights aggregation/view tests for Part B;
`CronJob`/detail tests for Part C).

Coverage that matters:

- **Mode toggle round-trips** (regression guard for D1): entering free text then returning
  yields the same selection set.
- **A custom value typed as text survives the round trip** and is reported by
  `customValues(knownNames:)` — the assertion device testing could not reach.
- **With `skills == nil`, no picker/return affordance is offered** (D1's second dead-end
  guard).
- **Model labelling (D5)**: pinned job → plain label; unpinned-with-snapshot → the
  follows-default form; neither → row absent. This is pure view logic, so if it is awkward
  to assert directly, lift the label decision into a small testable function rather than
  leaving it uncovered.

If the picker's mode is pure `@State` and awkward to test, lift it into a small testable
value type — but do not restructure the field's public shape (`skillsText` binding +
`skills` array stays).

**Baseline to beat: 1088 tests / 96 suites.**

---

## Explicitly out of scope

- `SkillsStore` / `SkillsService` / `Skill` — see the warning in D2
- `SkillsScreen` (the browser) — all its device checks passed in #171
- Any model picker or model-write path — #170b, upstream-blocked
- The deliver picker — it shares the one-way-door pattern but was NOT reported broken.
  If the implementer notices it has the same defect, **FILE it in OPEN_ITEMS, do not fix
  it here.**
- Any API or wire-format change; the skills field stays a comma-separated string

## Conventions — non-negotiable

Merge commits only, never squash. **File-scoped commits — five here, one per deliverable
area, so any single fix can be reverted alone.** OPEN_ITEMS.md edits in their own commit.
`xcodegen generate` only if files are added (this lane likely adds none — if so, skip the
regen and say so in the handoff); if you do regen, verify `aps-environment: development`
survived in `Talaria/Talaria.entitlements`.

Toolchain: `export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`. Pinned
sim `47F68496-24F9-45D9-93D3-1C778DB6B557`, `CODE_SIGNING_ALLOWED=NO`. Read the Swift
Testing `Test run with N tests in M suites passed` line, **not** `Executed N tests` (that
one counts only the 8 XCUITests).

Swift 6.2 strict concurrency. No mutable `static let shared` singletons, no retroactive
conformances on stdlib types, no block-based `NotificationCenter` observers (#160's
DO-NOT-COPY list).

**Known flake:** `testDisconnectReturnsToStandaloneChat` (#164, three occurrences, counter
currently at 0) may fail on the warm bundle run. Solo-rerun to confirm and **DISCLOSE it in
the handoff** — do not silently retry. A green bundle run counts toward #164's
3-consecutive close criteria.

## Handoff should report

- Which fix option was chosen for D2 and D4, and why
- Whether the deliver picker shares the D1 defect (filed, not fixed)
- #164 bundle-run outcome, explicitly
- Confirmation that `SkillsStore` was not modified
