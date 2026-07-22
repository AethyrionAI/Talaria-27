# FABLE-T27-156B — Skills browser: read-only list of the agent's installed skills

**Item:** OPEN_ITEMS #156b (lane of #156), sized by #158, design-referenced by #160, constrained
by #161, semantics re-verified from source + live host 2026-07-22 ·
**Repo:** AethyrionAI/Talaria-27 · **Base:** main (after #135 / 156a) · **Branch:**
`claude/t27-156b-skills-browser` · **Size:** small-medium, one PR
**Staleness check:** re-run at start (`gh pr list --repo AethyrionAI/Talaria-27`,
`git log --grep t27-156b`). OPEN_ITEMS numbers ≠ GitHub numbers.

## Mission

A read-only browser over the agent's installed skills: list, search, category grouping. Joins the
sessions drawer next to SCHEDULED TASKS (the 156a row's own comment anticipates this). Plus one
integration obligation 156a left open: the cron editor's skills field gains a picker fed from the
same data. **Zero new infrastructure** (#161) — one existing gateway endpoint, same auth plane as
chat and Tasks.

Read-only is not a compromise; it is the honest scope. See "Why no toggle" below.

## Verified API surface — semantics, not just existence

`GET /v1/skills` on `:8642`, Bearer `API_SERVER_KEY`. **This is the ONLY skill route** — verified
against the full route table in `api_server.py` (line 1495; the only other grep hits are the
route-index listing and the handler itself). No detail endpoint, no SKILL.md content, no toggle,
no install. Response:

```json
{"object": "list", "data": [{"name": "...", "description": "...", "category": "..."}]}
```

Verified live against the Mac host (hermes-agent 0.19.0):

- **98 skills returned.** Search and grouping are load-bearing, not decoration. Design for ~100,
  not for 10.
- **`category` is `null` for 10 of 98.** The "Uncategorized" bucket is a real path — group nulls
  there, sorted last.
- **Descriptions contain embedded newlines** and run long (one is a full multi-line paragraph).
  List rows must line-limit (2–3 lines); collapse internal newlines to spaces for row display.
- Fields are exactly `{name, description, category}` across all 98. Decode tolerantly anyway:
  every field optional, unknown fields ignored (upstream is not contractual — see
  `UPSTREAM_TESTED_SHA`).
- Server pre-sorts via `_sort_skills`, but do not rely on it — sort client-side.

### Why no toggle (do not "improve" this)

The handler filters to **enabled skills only, and no enabled flag exists in the payload.** The
mechanism is worth recording precisely because the parameter name invites misreading:
`_find_all_skills(skip_disabled:)` in `tools/skills_tool.py:669` — `skip_disabled=True` means
"skip the disabled-*filtering*" (i.e. include disabled skills; it's the config-UI path). The
handler passes `False`, the filtering path, so disabled skills never appear. This matches the
handler's own docstring ("Disabled skills are excluded so the listing matches what the agent
actually loads"). Net contract: **what you see is what the agent can use.** An enable/disable
toggle is impossible on this surface, and hermex independently scoped to the same read-only
conclusion (#160). If you find yourself wanting a toggle, the answer is no — it would need
dashboard-plane or host-file access, both ruled out (#161).

### ⚠️ The two-sources trap — read before writing any code

Talaria **already fetches skills** via a different plane: the relay's `GET /v1/commands`
(consumed by `Talaria/Models/SlashCommand.swift` for composer autocomplete). Under the hood the
connector *scrapes `hermes skills list` CLI table output* (`connector/.../client.py:1370`,
directory-walk fallback at `:1464`) and returns `{name, description}` only — it parses category
from the table and then discards it.

**Decision, binding for this lane:**
- The **browser** (and the D5 picker) read the **gateway** `/v1/skills` — deterministic JSON,
  designed for external clients per its own docstring, carries `category`, same auth seam as
  `CronJobService`.
- The **composer autocomplete keeps the relay catalog.** Do not touch it, do not unify the two,
  do not "refactor" `SlashCommand` onto the gateway source in this lane.
- The two sources CAN disagree (scrape failure vs clean list, timing). That is expected and
  acceptable; do not build reconciliation.

## Deliverables

### D1 — `Talaria/Services/Live/SkillsService.swift`

Same seam as `CronJobService` (read it first): `@MainActor` protocol + implementation taking
`baseURLProvider` / `apiKeyProvider` closures, typed errors reusing the same shape
(`notConfigured` / `unreachable` / `timeout` / `unauthorized` / `invalidResponse`). One method:
`listSkills() async throws -> [Skill]`. ~15s timeout. No caching layer in this lane — fetch on
appear + pull-to-refresh, same posture as Tasks.

### D2 — `Talaria/Models/Skill.swift`

Tolerant `Decodable`: `name` (required in practice — drop records without one rather than
throwing), `description`, `category` all optional-decoded. A computed `displayCategory` returning
"Uncategorized" for nil/empty. A computed single-line `rowDescription` (newlines → spaces,
trimmed). Search matching: case-insensitive over name + description + category.

### D3 — `Talaria/Features/Skills/SkillsScreen.swift`

Grouped list, category headers sorted case-insensitively with Uncategorized **last**, skills
alphabetical within. Search field. Content states, matching the Tasks screen's in-repo pattern
(**match `TasksScreen.swift`'s design language — `MonoLabel`, `Design.*`, hudPanel — not hermex's
SwiftUI idioms**):

- loading + empty → progress ("FETCHING SKILLS" per the Tasks convention)
- error + empty → error + retry
- empty + loaded → "no skills installed on this host"
- **search with no matches → dedicated state echoing the query** ("No skills match "x"") — the
  one state Tasks doesn't have, because Tasks has no search (#160)
- loaded → grouped list, pull-to-refresh

Errors never replace content already on screen (same rule as 156a D3). Tapping a row: nothing to
navigate to (no detail endpoint exists) — an expandable row showing the full untruncated
description is sufficient; do not build a detail screen for three fields.

### D4 — Drawer row

`skillsRow` in `SessionsDrawer.swift`, sibling of `tasksRow` (line ~603), same visual pattern
(suggested glyph: `sparkles` or `wand.and.stars`), label "SKILLS", routing via
`container.router.navigate(to: .skills)` + the new route case. Unconditional presence, matching
`tasksRow` — the screen owns its not-configured state.

### D5 — Cron editor skills picker (the 156a debt)

`TaskScheduleDraft.swift:310` promised this lane a picker for the cron editor's skills field.
Deliver it with the **preserve-unknown-values pattern** (#160 idea 1, already used by the deliver
picker): a multi-select sheet fed from `SkillsService`, seeded with the field's current
comma-separated values; values not present in the fetched list render as "(custom)" rows that
stay selected — editing never clobbers a legacy or hand-typed value. If the skills fetch fails,
the field stays free text exactly as it is today (degrade, don't block). Emits back to the same
comma-separated string the PATCH surface expects — **the wire format does not change.**

### D6 — Tests

Swift Testing. Cover: tolerant decoding (null category, missing description, unknown fields,
record without name dropped), grouping (Uncategorized last, case-insensitive header sort), search
matching incl. the no-results state trigger, `rowDescription` newline collapsing, and D5's
value-preservation (custom values survive a round trip through the picker). Fixture the service;
no network. Baseline to beat: **1007 tests / 88 suites** (post-#135).

## Explicitly out of scope

- Enable/disable toggle — impossible on this surface (see above)
- Skill detail screen / SKILL.md content — no endpoint exists
- Install/search-hub anything — dashboard-plane only
- Touching the composer's relay-catalog path or `SlashCommand`
- Caching/offline for skills — fetch-on-appear is the 156a-consistent posture

## Conventions — non-negotiable

Same as 156A, restated because they keep being violated elsewhere: merge commits only, never
squash; file-scoped commits; **OPEN_ITEMS.md edits in their own commit**; `xcodegen generate`
required (new Swift files) with the pbxproj regen in a **separate commit** and an
`aps-environment: development` check in `Talaria/Talaria.entitlements` after; toolchain
`export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`; build/test on the pinned
sim `47F68496-24F9-45D9-93D3-1C778DB6B557` with `CODE_SIGNING_ALLOWED=NO`; read the Swift Testing
`Test run with N tests in M suites passed` line, not `Executed N tests`. Swift 6.2 strict
concurrency — no mutable `static let shared` singletons, no retroactive conformances on stdlib
types, no block-based NotificationCenter observers (#160's DO-NOT-COPY list).

## Provenance

Informed by reading `uzairansaruzi/hermex` (MIT) as a design reference only — specifically their
no-results search state and read-only scoping. No hermex source is used or adapted; if copying
their Swift becomes tempting, stop and flag it first (`THIRD_PARTY_LICENSES.md` would need
upgrading from attribution to a full MIT notice).
