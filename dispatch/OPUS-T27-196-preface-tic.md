# OPUS-T27-196 — "I can't do that, but here it is": kill the preface, keep the honesty

**Items:** OPEN_ITEMS #196 (residual of #194/#176) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-196-preface-tic` · **Toolchain:** Xcode-beta4 = **Xcode 27.0 (27A5228h)**, pinned sim
**Evidence scope:** your return MUST state the Xcode build your suite ran on (`xcodebuild -version`). If your
environment cannot build against 27A5228h, say so explicitly — a green on any other SDK is NOT a green here.
**Baseline:** confirm the current green count before you start (expected ~1235 tests / 109 suites) · `export GH_PAGER=cat` first

**Confirm-then-fix**, the #192/176C shape: instrument, desk A/B, verdict, then the labeled
provisional fix ships or drops. 176C is the direct precedent and its verdict is the origin story
here — read `dispatch/OPUS-T27-176C-194-creative-suppressor.md` and OPEN_ITEMS #194/#196 first.

## The defect

Post-#157 (production armed is roster-less; content delivery fully restored), every on-device
reply opens with a disclaimer it then contradicts:
- "I can't write a haiku for you, but here's one I've seen on the topic:" → an original haiku
- "I can't write a poem for you, but here's one inspired by bobsledding:" → the poem
- "I can't directly calculate that for you, but 2 + 2 is 4."
Observed on turn TWO of a fresh chat — NOT imitation of earlier in-context refusals. Absent in
the Shortcuts base-model probe (no tools, no instructions), so the session shape is again the
carrier — but this is a **preamble reflex**, not #194's capability gate. Treat it as its own
mechanism.

## Suspects (undiscriminated — the cells decide)

1. **Negative-flavored instruction sentences priming "can't" language** — the honesty sentence
   ("When a tool reports that a permission isn't granted… relay that honestly — never invent a
   value") and the recovery clause ("A failed or denied tool is never the answer…"). Both have
   REAL JOBS (#176's absorbing-state exit); production must keep their function whatever the fix.
2. **Tool registration itself** biasing hedged prefaces wholesale.
3. Counter-instruction insufficiency — maybe nothing removes it and it must be overpowered.

## Part 0 — fold in the desk instrument (do this first)

Branch `claude/t27-176c-desk-ab` (commit `8f92385`, verified 1235/109 on 27A5228h) holds the
desk A/B enablement that PR #157 merged WITHOUT: the DEBUG-only UserDefaults fallback on
`activeSessionShape` (read once per process, launch env wins, launch-scoped invariant kept) and
the Diagnostics segmented picker with the active-cell label. **Cherry-pick or faithfully
reimplement it as this lane's first commits** — it is proven, it is how Owen runs cells from a
desk over OTA, and this lane is unusable without it. Then delete is NOT yours to do: leave the
side branch alone; Owen tidies branches.

## Part 1 — the new cells

Rework `SessionShape` for this question (the 176C cells did their job; `armed-noprose` and
`prose-notools` are moot now that production armed IS roster-less — remove them):

- **`armed`** — current production text, tools registered. The control; the tic lives here.
- **`armed-direct`** — production text PLUS one sentence, placed with the licensing clause:
  "Answer directly — never begin a reply by saying you can't do something you are then going to
  do." (Wording yours to refine; keep it ONE sentence, this file is the app's voice.)
- **`armed-noneg`** — production text MINUS the honesty sentence and the recovery clause.
  **Measurement cell only, never shippable** — it removes #176's absorbing-state protections;
  say so in a comment, the `prose-notools` precedent.
- **`toolless`** — the production tool-less branch, unchanged text, no tools. Discriminates
  suspect 2: if the tic appears here too, tool registration is exonerated.

Keep: the once-per-process read, the per-session-build Console notice, Release compile-out
(prove it with a Release build again). Update the DeviceToolBeltTests instruction-variant pins
to the new cells; state the test-count delta and why.

## Owen's desk A/B (write into the PR body)

Debug OTA build, per cell: picker → force-quit → relaunch → **confirm the active-cell label** →
airplane mode → fresh chat → probes: "Write a haiku about spring", "What's 2+2", and in
tools-registered cells one calendar question. Score each reply BOTH ways: content delivered
(yes/no) AND preface present (yes/no). The readout:
- `armed-direct` clean + content intact → counter-instruction works → Part 2 ships.
- `armed-noneg` clean but `armed-direct` ticky → the negative clauses are the source → report
  back; the fix becomes REWORDING the honesty/recovery clauses to keep their function without
  the "can't" framing — a follow-up, not Part 2, because noneg itself must never ship.
- `toolless` ticky → tools exonerated as the carrier, instructions are the whole game.
- Everything ticky including `armed-direct` → report back, do not stack more sentences on vibes.

## Part 2 — provisional fix (labeled inert tip, the 176C pattern)

Add the `armed-direct` sentence to the PRODUCTION armed branch. Final commit, labeled
**"Part 2 — do not merge-cherry-pick until the device A/B clears armed-direct"**, trivially
droppable. Adjust only the substring anchors it breaks; every other #176B/#148 anchor stays
green unmodified.

## HARD CONSTRAINTS

- #194 must not regress: creative content keeps flowing in every tools-registered cell — a
  poem request produces a poem. That is the negative guard above all others.
- #176 must not regress IN PRODUCTION: the honesty and recovery functions survive (deny a
  permission → later unrelated questions each answered on their own terms, no canned loop, no
  invented values). `armed-noneg` is a thermometer, not a treatment.
- #148 vision gating and its tests: green, untouched. Real-data tool routing survives.
- Tool-less branch production text: unchanged (the `toolless` cell reads it as-is).
- No model-choice assertions in tests; the sim has no model.

## Definition of done

- Suite green on 27A5228h, count delta stated; Release build proves the seam compiles out.
- Four cells reachable from the Diagnostics picker on a Debug OTA build, self-labeling.
- Part 2 present as the labeled inert tip.
- PR body carries the desk A/B checklist with the two-axis scoring (content / preface).

## House rules

- Merge commits only, never squash. File-scoped commits.
- **OPEN_ITEMS.md edits in their own separate commit.**
- `xcodegen generate` only if Swift files are added or removed (none should be); pbxproj regen
  as its own commit; verify `aps-environment: development` survived.
