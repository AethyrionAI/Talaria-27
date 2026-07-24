# OPUS-T27-183 — SWEEP: tests that pass without exercising what they name

**Item:** OPEN_ITEMS #183 · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-183-masked-tests` · **Toolchain:** Xcode-beta4, pinned sim
**Baseline:** 1121 tests / 103 suites + 8 UI (post-PR #144)

## Why this lane exists

Three instances of one shape are now on record, found independently:

1. **`ConversationManagementTests`** failed-refresh case — answered from a fresh snapshot and never
   reached the throwing client. Passed while testing nothing. Found and fixed in PR #144.
2. **#154's unreachable-fallback trap** — a test asserting on a branch behind an always-true
   `#available` guard would still pass, and would have *validated* deleting live code. Came back
   clean, but only because someone was told to look.
3. **#93's `CondenserFidelityTests`** — SKIPPED on sim ("requires the on-device Apple Intelligence
   model"). The tracker already records the right verdict: **a skip is not a pass.** It has been
   sitting green-by-omission since 2026-07-13.

The suite is the primary evidence for every merge decision in this project. A test that cannot fail
is worse than a missing test, because a missing test is visible in coverage and a masked one reads
as protection. **1121 green is only meaningful if the green means something.**

## Scope — two phases, cheap first

### Phase 1 — static sweep (no runs needed)

Find and classify, do not fix yet:

- **Vacuous suites:** test functions containing no `#expect` / `XCTAssert` at all
- **Skip-guarded tests:** anything that returns early or is conditionally disabled on sim.
  `CondenserFidelityTests` is the known one; find the rest.
- **Never-invoked doubles:** mocks whose methods are never called by the test that installs them.
  A double that records nothing and is asked nothing is a strong signal.
- **Assertions on constants:** `#expect` against a literal or a value the test itself just set,
  with no production code in between.

Report counts per category before touching anything.

### Phase 2 — targeted mutation check

**This is the only check that actually proves a test works.** For a prioritised sample: deliberately
break the production code the test names, and confirm the test goes RED. Any test that stays green
is masked, by definition.

Do NOT attempt this across 1121 tests. **Prioritise by blast radius** — the tests guarding
invariants where a silent failure would be expensive:

- `#137` sensor migration (consent inversion — the most expensive failure on this list)
- `#61` `degenerateCardReason` guards, including the new exact-prefix branch
- `#133` push-registration idempotency and `#146`'s derived-Bool replacement
- `#127` monetization gate (fail-open behaviour, dormant but launch-critical)
- `#172` / `#168a` field-mode types
- `#174` downscale bounds

Revert every mutation. **Do not commit a single one.** Work on a scratch branch or `git stash` per
mutation; a stray mutation reaching main would be a far worse outcome than the bug being hunted.

## Fix policy — narrow deliberately

- **Fix** the clear-cut cases: a test that can be made to exercise its subject with a small change,
  the way `force: true` fixed `ConversationManagementTests`.
- **File, do not fix**, anything needing a redesign of the test's setup, or any test whose subject
  turns out to be untestable in the current harness.
- **`CondenserFidelityTests` is explicitly NOT this lane's job to make runnable** — it needs a
  device with the on-device model (#93's owed gate). Record it honestly as skip-not-pass and move
  on. Making it run is a device lane.

**This lane widens easily and must not.** If Phase 1 turns up thirty candidates, fix the obvious
handful and file the rest as a single follow-up item with the list. A sweep that tries to fix
everything it finds does not land.

## Close criteria

- Phase 1 categories reported with counts
- Phase 2 run against the prioritised list, with a per-test PASS (goes red when mutated) or
  MASKED verdict
- Clear-cut fixes landed, remainder filed
- Full suite green, counts reported against **1121 / 103** and the delta accounted for

**A test count that goes DOWN is a legitimate outcome** if a vacuous test is deleted rather than
repaired — say so explicitly rather than quietly keeping it to protect the number.

## Commit discipline

File-scoped commits. pbxproj regen its own commit if any test file is added or removed.
OPEN_ITEMS.md separate from code. `gh pr merge --merge`, never squash. `export GH_PAGER=cat`.

## Out of scope

#164 and #182 (the two UI-test flakes) — a flake fails visibly and is a different problem from a
test that cannot fail at all. #147/#145. Anything in Bundle B's out-of-scope list.
