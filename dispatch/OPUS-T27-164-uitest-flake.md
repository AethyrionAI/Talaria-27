# OPUS-T27-164 — `testDisconnectReturnsToStandaloneChat` bundle-warm flake

**Item:** OPEN_ITEMS #164 · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-164-uitest-flake` · **Size:** small code, slow verification
**Toolchain:** `export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`
**Pinned sim:** `47F68496-24F9-45D9-93D3-1C778DB6B557`, `CODE_SIGNING_ALLOWED=NO`

## Run this alone

Not because it is hard, but because its close criteria is **three consecutive full-suite bundle
runs green**, at roughly 7–8 minutes each. It will hold the simulator for the better part of an
hour. Do not bundle it with a lane that needs the sim.

## Why it matters despite passing on rerun

It fails on bundle-warm runs and passes solo. Three occurrences logged; the counter was reset at
the third (2026-07-22).

The cost is not correctness, it is **a standing tax on every lane's verification**: each bundle run
needs a manual rerun-and-eyeball to tell this flake apart from a real disconnect regression. And
its failure mode is *exactly the shape a real regression in the disconnect flow would take*. A
flake that impersonates a plausible regression in a flow we rarely touch is the kind that
eventually gets a real bug waved through as "oh, that one again."

It should not survive into the launch-pass test discipline, where "rerun until green" is precisely
the habit to have eliminated.

## Scope

1. **Read the test's own comments** about tap timing and the bundle-warm condition. They were
   written by someone who had just watched it fail; do not skip them.
2. **Reproduce with a full-suite run, not solo.** Solo passes. If you cannot reproduce it warm,
   say so rather than fixing blind — an unreproduced flake "fixed" is just an unverified change.
3. **Prefer fixing the wait condition** — an explicit existence/hittable predicate on the
   post-disconnect standalone-chat element — **over adding sleeps.** A sleep tuned to today's
   machine is tomorrow's flake.
4. **If the wait is already correct** and the flake is genuinely environmental (sim warm-state),
   **quarantine deliberately**: mark the test's known-flaky status in-code with a comment pointing
   at #164. **NOT deletion. NOT a blind retry wrapper** — a retry wrapper would also mask a real
   regression, which is the entire risk this item exists to prevent.

## Close criteria — either one, not neither

- three consecutive full-suite bundle runs green on the pinned sim, **or**
- an explicit quarantine decision recorded in #164 with its reasoning

"It passed this time" closes nothing.

## Verification mechanics

Long runs go in the background and get polled from a fresh shell:

    nohup xcodebuild test -project Talaria.xcodeproj -scheme Talaria \
      -destination 'platform=iOS Simulator,id=47F68496-24F9-45D9-93D3-1C778DB6B557' \
      CODE_SIGNING_ALLOWED=NO > $LOG 2>&1 & echo "pid=$!"; disown

Swift Testing `@Test` suites report separately from XCTest — grep for `Test run with N tests
passed`, not `Executed N tests`. Baseline at spec time: **1091 tests / 98 suites**.

## Commit discipline

File-scoped commits. OPEN_ITEMS.md in its own commit, separate from any code. Merge with
`gh pr merge --merge` — never squash. `export GH_PAGER=cat` before any `gh` command.

## Out of scope

Any other test's flakiness. If the investigation surfaces a second flaky test, **file it, do not
fix it** — a flake-hunting lane that widens is a lane that never closes.
