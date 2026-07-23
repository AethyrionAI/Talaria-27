# FABLE-T27-168 — Skills picker: give EDIT AS TEXT a way back, and free text a retry

**Item:** OPEN_ITEMS #168 (168a defect, 168b polish, plus a label note) ·
**Repo:** AethyrionAI/Talaria-27 · **Base:** main · **Branch:** `claude/t27-168-skills-picker-return-path` ·
**Size:** small, one PR
**Staleness check:** re-run at start (`gh pr list`, `git log --grep t27-168`).

## Mission

Two dead ends in the cron editor's SKILLS field, both found on device during the #163
checklist, both confirmed in source. Neither loses data; both trap the user in a mode
they cannot leave. Fix is confined to two view files.

**Do not touch `SkillsStore`, `SkillsService`, or `Skill`.** The store's
keep-rows-on-failure behaviour is a verified contract (#163 Check 4, passed on device) —
changing it to fix 168b would break the browser.

## D1 — 168a: exit from EDIT AS TEXT (the actual defect)

`TaskSkillsPicker.swift`: `@State private var useFreeText` has exactly one write site
(`useFreeText = true`, ~line 122). Nothing sets it back. Tapping EDIT AS TEXT swaps the
picker for a raw `TextField` permanently, for the life of the sheet.

The caption already promises the missing control — it reads
`"COMMA-SEPARATED — PICKER AVAILABLE WHEN NOT EDITING AS TEXT"` when a host list exists.
The UI documents a return path the code never implemented.

**Fix:** in `freeTextField`, when `pickerSkills != nil`, render a control that sets
`useFreeText = false` — mirror the existing EDIT AS TEXT button's styling (`MonoLabel`,
size 8, `Design.Tracking.mono`, `Design.Brand.accent`) with a label such as
`USE PICKER`. When `pickerSkills == nil` the toggle must NOT appear: free text is the
only available mode and offering a picker that cannot open would be a second dead end.

Replace the now-redundant caption text in the picker-available case with something that
does not describe a state (the button is self-describing); keep the
`"COMMA-SEPARATED SKILL NAMES ON THE HOST"` caption for the nil case unchanged.

**Consequence being unblocked:** the "(custom)"-value preservation property (D5 of 156b,
idea 1 from #160) is currently UNVERIFIABLE on device — you cannot type an unknown value
in text mode and return to the picker to see it pinned, because you cannot return.
`SkillsPickerSelectionTests` covers the model round-trip, so the logic is believed
intact; this lane makes it reachable. Owen re-runs that device assertion after merge.

## D2 — 168b: retry from the degraded state

Root cause, verified — the earlier "nothing ever re-fetches" claim was WRONG:

- `TaskEditSheet.swift:78-82` already has `.task { await skillsStore?.refresh() }`, so
  every create/edit sheet retries on appear.
- `TaskEditSheet.swift:187` gates on success:
  `skills: (skillsStore?.hasLoaded == true) ? skillsStore?.skills : nil`
- `SkillsStore.refresh()` sets `hasLoaded = true` only on success; its catch block
  deliberately preserves prior rows and leaves `hasLoaded` alone.

So a cold-offline launch correctly degrades to free text — but `TaskSkillsPicker` takes
`skills` as a plain `let`, and the retry only fires on sheet appear. Restoring
connectivity mid-sheet changes nothing until dismiss-and-reopen.

**Fix (pick the smaller of these two, implementer's judgement):**
- (a) In the nil-list free-text case, add a RETRY affordance that re-invokes the store
  refresh, so the field can upgrade to a picker in place; or
- (b) Re-run the refresh when the sheet returns to the foreground (scene-phase active),
  so backgrounding to toggle connectivity is enough.

(a) is preferred — it is explicit, testable, and needs no scene-phase plumbing. Either
way `TaskSkillsPicker` needs a way to ask its parent to refetch (a closure passed down
is fine; do not give the view its own store reference).

Guard the affordance so it cannot spam: `SkillsStore.refresh()` already no-ops while
`isLoading`, so a disabled/spinner state during the attempt is sufficient.

## D3 — label clarity (design note, not a bug)

EDIT AS TEXT reads as single-skill editing. Owen — who knows the field is a
comma-separated list — still read the raw text box as "edit this one skill's name" during
device testing. If the person who designed the data model misreads it, users will.

Relabel to something unambiguous about editing the whole list (e.g. `EDIT LIST AS TEXT`),
and/or lean on the existing placeholder (`skill-one, skill-two (optional)`) by keeping it
visible. Keep it to a label/hint change — no layout redesign in this lane.

## D4 — Tests

Swift Testing, extending the existing `SkillsPickerSelectionTests` file rather than adding
a new one. The view-state logic worth covering:

- The mode toggle round-trips: entering free text then returning yields the same
  selection set (this is the regression guard for 168a).
- A custom value typed as text survives the round trip and is reported by
  `customValues(knownNames:)` — the assertion device testing could not reach.
- With `skills == nil`, no picker/return affordance is offered (168a's second dead-end
  guard).

If the toggle is pure `@State` inside the view and awkward to test directly, lift the
mode into a small testable value type rather than leaving it untested — but do not
restructure the field's public shape (`skillsText` binding + `skills` array stays).

Baseline to beat: **1088 tests / 96 suites** (post-#137).

## Explicitly out of scope

- `SkillsStore` / `SkillsService` / `Skill` — see the warning at the top
- Any change to the browser (`SkillsScreen`) — all six of its device checks passed
- The deliver picker — same escape pattern, but not reported broken; leave it alone
  (if the implementer notices it shares the one-way-door bug, FILE it in OPEN_ITEMS,
  do not fix it here)
- Any API or wire-format change; the field stays a comma-separated string

## Conventions — non-negotiable

Merge commits only, never squash; file-scoped commits; OPEN_ITEMS.md edits in their own
commit; `xcodegen generate` only if files are added (this lane likely adds none — if so,
skip the regen and say so in the handoff); `export
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`; pinned sim
`47F68496-24F9-45D9-93D3-1C778DB6B557`, `CODE_SIGNING_ALLOWED=NO`; read the Swift Testing
`Test run with N tests in M suites passed` line, not `Executed N tests`.

Known flake: `testDisconnectReturnsToStandaloneChat` (#164, three occurrences) may fail on
the warm bundle run. Solo-rerun to confirm and DISCLOSE it in the handoff — do not
silently retry. A green bundle run counts toward #164's 3-consecutive close criteria.
