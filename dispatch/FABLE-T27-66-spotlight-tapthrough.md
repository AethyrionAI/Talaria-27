# FABLE T27-66 — Spotlight tap-through doesn't open the session

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-66-*`
**Dispatch date:** 2026-07-16 · **Tracks:** OPEN_ITEMS #66, GitHub issue #88
**Size:** micro-PR. One file plus a config test.

**Merged-PR check done 2026-07-16:** PR #24 landed the indexing half; no fix
branch for the tap-through failure exists. The bug is live. Issue #88 validated
against source at HEAD, not against its own text.

## The bug

Device pass 2026-07-13 (eve): **FAILED.** Spotlight search surfaces the
session; tapping the result does not open it. Indexing works
(`SpotlightIndexingService` → `CSSearchableIndex.default().indexAppEntities`);
the launch is what's broken.

## Prime suspect — we just proved this exact mechanism on #58

`Talaria/Intents/SpotlightEntities.swift:89` `OpenSessionIntent` combines:

- `static let openAppWhenRun = true`
- `perform()` → `.result(opensIntent: OpenURLIntent(url))`  (`hermes://session/{id}`)

That is the **identical pair** PR #100 (merged today, 2026-07-16) removed from
`TalariaWidgets/Controls/HermesControls.swift` to fix #58 — where the same
combination made Control Center silently swallow the tap. Main now carries an
explicit comment at `HermesControls.swift:52-57` saying the OpenURLIntent IS
the launch and `openAppWhenRun` must stay absent. Symptom here matches to the
letter: the surface fires, nothing opens.

`OpenAgentFileIntent` (same file, ~:104) has the SAME shape and is presumed
broken the same way — it has never been device-verified. Fix both.

## The honest caveat — instrument before you "fix"

#58's intents were `AppIntent`. These are `OpenIntent`, which has its own
`openAppWhenRun` semantics (the protocol is *about* opening the app). It is
plausible that for `OpenIntent` the correct shape is the opposite: keep
`openAppWhenRun` and DROP the returned `OpenURLIntent`, letting the system open
the app and hand over the resolved entity, with navigation done from the entity
rather than a deep link. Do not assume the #58 fix transfers verbatim.

## The lane

1. **Instrument first, and keep it** (the #58 lesson — one instrumented run
   named the culprit in minutes after days of theorizing). `os.Logger`
   `.notice`, public privacy, in BOTH `perform()`s and in
   `ChatSessionEntityQuery.entities(for:)` /
   `AgentFileEntityQuery.entities(for:)`. Log the resolved id and the URL.
   Console must be able to answer, forever after:
   - did the entity query resolve? (Spotlight → entity)
   - did `perform()` fire? (entity → intent)
   - did the deep link get built, and with what?
   The failure could live at ANY of those three joints. Instrumentation
   distinguishes them without a rebuild.
2. **Then fix**, per whichever joint the evidence indicts. Prime hypothesis
   first: drop `openAppWhenRun` from `OpenSessionIntent` +
   `OpenAgentFileIntent`, mirroring `HermesControls.swift`, and comment WHY so
   it isn't helpfully re-added.
3. If instrumentation shows `perform()` never fires, the defect is in the
   entity/donation shape, not the launch — say so in the PR and stop; do not
   flail at the deep link.
4. `AppEntry.handleDeeplink`'s `hermes://session/{id}` route is believed
   innocent (`AppEntry.swift:269` — lands on Chat, then adopts the session;
   `hermes://` routes verified in #77). Verify by reading, don't rewrite it.

## Constraints (house)

- File-scoped commits; no `OPEN_ITEMS.md` edits. `xcodegen generate` only if
  files add/remove (a test file may — then regen, separate commit, verify
  `aps-environment` survives).
- Toolchain **Xcode-beta3**. Baseline **691 tests / 58 suites**.
- Cloud cannot test Spotlight. Mark the PR device-verify-owed.

## Acceptance

- Both open intents instrumented and their launch shape corrected + commented.
- A static-configuration test in the spirit of `HermesControlsTests` (which
  pins #58's fix): assert the intents' config so a future refactor can't
  silently restore the conflict.
- Build + suite green.
- Device check (Owen's): Spotlight → search a session → tap → app opens TO THAT
  SESSION. Then repeat for a Hermes file result. Console shows the three
  `.notice` lines in order.
