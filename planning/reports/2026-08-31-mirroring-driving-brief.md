# Reusable brief: driving whoGoesThere through iPhone Mirroring

Paste this into every card-driving subagent prompt. Every line here was paid
for once already — the #350-D pilot spent ~40% of 182k tokens rediscovering it.

## Tools
- ONE call: `ToolSearch {query: "computer-use", max_results: 30}`.
- "iPhone Mirroring" is ALREADY GRANTED (tier full). **Never call `request_access`.**
- `open_application` → `"iPhone Mirroring"`.

## Cost discipline (the primary constraint)
Screenshots are images and every turn re-sends all prior ones, so cost grows
with the SQUARE of the screenshot count.
- **`computer_batch` for everything.** Predict 3–6 actions, ONE screenshot at
  the end. Never screenshot after each action.
- Handle timing with in-batch `{"action":"wait","duration":N}` — never spend a
  round trip on waiting.
- `zoom` only when text is genuinely unreadable. Aim it off the LAST full
  screenshot's coordinates; a mis-aimed zoom costs the same as a screenshot.
- Budget: state a target and a HARD CAP. Stop at the cap and report.

## Known device/mirroring facts (measured 2026-08-31)
- The phone must be **LOCKED** to connect. Owen runs auto-lock=Never, so it may
  sit unlocked and mirroring shows **"iPhone in Use"** → STOP and report; do not
  retry in a loop. He presses the side button and you resume.
- Expect an "Unlock Your iPhone" → Connect flow; one retry is normal.
- **Force-quit: the bottom-edge swipe does NOT work through mirroring.** Use the
  menu bar: **View → App Switcher**, then swipe the app card away. Confirm it is
  gone from the switcher before claiming a cold launch.
- Face ID is OFF and auto-lock is Never for these sittings.
- App name on the Home Screen: **Talaria 27**.

## Evidence discipline (why this project distrusts screens)
- **Never return a PASS/FAIL verdict.** Report what you OBSERVED: exact quoted
  on-screen text, pip/dot colors named explicitly, and the ORDER + TIMING of
  what appeared. The verdict is decided upstream against the card's bars.
- **Say when you cannot tell.** "I could not tell dim-green from grey" is worth
  more than a confident wrong reading. False green signals are this project's
  recurring failure mode.
- If the card references a control you cannot find, **do not substitute one** —
  report it as a card/build mismatch. That is a finding, not a failure.

## Care with Owen's device
- **Record any setting you change, verbatim, BEFORE changing it** — and restore
  it at the end. Confirm the restore in your report.
- Change nothing the card does not require.

## Always report
- `SCREENSHOTS TAKEN: <n>` · `BATCHES USED: <n>` · settings restored? y/n
- Any blocker, early, with the count so far.
