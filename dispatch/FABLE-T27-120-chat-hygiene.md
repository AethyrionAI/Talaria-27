# FABLE T27-120 — Chat-surface hygiene lane

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-120-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #120, #25 (second half), + CFPrefs rider
**Size:** one PR, three small fixes. **Baseline:** 755/62, main @ `588d885`.
**Toolchain:** Xcode-beta3.

## Fix 1 — #120: duplicate ForEach message IDs (undefined rendering)

Two device runs logged: `ForEach<Array<Message>, UUID, …>: the ID
1C6EBACD-… occurs multiple times within the collection` + a LazyVStackLayout
duplicate-child warning. A message UUID appears twice in the rendered array.
Prime suspects, in order: (a) the streaming placeholder and the finalized
message coexisting for one frame with the same id at stream end (look at
`ChatStore` finishStream/append ordering — #110's `finishStream(finishedContent:)`
area); (b) a derived array in `ChatScreen`/`MessageBubble` concatenating
overlapping sources. FIND the duplication with a failing test first (drive the
store through a stream-then-finalize cycle and assert id uniqueness of the
rendered collection), then fix at the source — do NOT paper over it with
`.id(UUID())` or index-keyed ForEach; identity must stay stable for animations
and #78's context-menu targets.

## Fix 2 — #25 second half: CTX gauge flashes wrong before settling

PR #110 fixed resume (cache + honest absence). Remaining symptom: during a
LIVE stream the gauge can briefly render a wrong value before `run.completed`
lands with authoritative usage. Investigate what feeds
`chatStore.currentContextTokens` mid-stream: if any interim/estimated value is
published before `run.completed`, either (a) suppress gauge updates until the
authoritative number arrives (previous session's number may keep displaying —
that's fine and honest), or (b) mark interim values so the gauge skips them.
Do NOT re-derive anything from cumulative session `input_tokens` (see the #25
probe verdict in `dispatch/FABLE-T27-25-ctx-meter.md` — that path is banned).
Note: the denominator legitimately varies per session model (`contextWindow ←
1048576` for one catalog entry vs `128000` for another in the same day's
logs) — that is CORRECT behavior, not part of this bug.

## Fix 3 (rider) — CFPreferences app-group misuse warning

Every launch logs: `Couldn't read values in CFPrefsPlistSource … Domain:
group.org.aethyrion.talaria, User: kCFPreferencesAnyUser … Using
kCFPreferencesAnyUser with a container is only allowed for System Containers,
detaching from cfprefsd`. Someone reads the app-group defaults with the wrong
user domain (likely widget/app shared prefs via a raw CFPreferences or
misconfigured `UserDefaults(suiteName:)` call path). Find the call site (grep
`group.org.aethyrion.talaria` + any CFPreferences usage), switch to plain
`UserDefaults(suiteName: "group.org.aethyrion.talaria")` per-user semantics.
Low risk, but VERIFY the widget round-trip still works (SharedWidgetDataStore
tests exist — extend if the touched path is theirs). If the warning turns out
to originate inside an Apple framework rather than our call, prove it (stack
or code absence) and close the rider as no-op in the PR body.

## Constraints & acceptance

- File-scoped commits; regen only on file add/remove (fail-first tests will
  add — separate commit, verify aps-environment).
- Fail-first test for Fix 1 committed BEFORE the fix commit (house style:
  the #61 lane did exactly this).
- Suite green ≥ 755/62. Device checks for Owen in the PR body: no dup-ID
  warnings across a streamed reply; gauge never shows a transient wrong
  number mid-stream; the CFPrefs warning gone from launch logs.
