# OPUS-T27-184 + 185 — one teardown primitive, and attachments that match themselves

**Items:** OPEN_ITEMS #184 + #185 (touches #136, #9, #21, #38) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-184-185-chatstore-integrity` · **Toolchain:** Xcode-beta4, pinned sim
**Baseline:** confirm the current green count before you start · `export GH_PAGER=cat` first

**Both findings are fully written up already** — read
`dispatch/RESULTS-T27-ULTRAREVIEW-2026-07-25.md` before starting. Everything there was verified
against source. Do not re-derive; do read the corrections, which matter.

---

## Part 1 — #184: three teardown paths, three different subsets

| | `streamingTask` | `pendingRun` / `reconcileTask` | Live Activity |
|---|---|---|---|
| `clearConversation` (`:735`) | ✓ | ✓ | ✓ |
| `openSession` (`:1297`) | ✓ | ✗ | ✓ |
| `reset()` (`:1343`) | ✗ | ✗ | ✗ |

`reconcileFromServer()` takes **no session argument** — `ChatBackendRouter:373–378` delegates
straight through after `openSession` has already switched the client's internal session. So a stale
`pendingRun` from S1 is compared against S2's server view. Harms, all persisted: S1's
`partialReasoning` written onto an S2 reply (`:1487`), a nonsense `turnDuration` (`:1498`),
`onRunResolved?(S1)` withdrawing the relay watch so S1's real completion push is dropped (`:1514`),
and the polluted messages reaching `saveConversationCache` with the journal waterline advancing over
them (`:1516`/`:1520`).

**`reset()` is the more serious half, and the reviewer got it backwards.** It has two live callers,
both on the pairing lifecycle — `AppContainer.swift:1557` in `handlePairingActivated()` and `:2243`
in `handlePairingRemoved()`. Pair or unpair mid-stream and `conversation` goes nil while
`streamingTask` keeps running and `pendingRun` stays armed, then `initialize()` runs against a
**different host**. Cross-host leakage, not cross-session. Both call sites already carry `#136`
comments reasoning about this exact race class for the bootstrap and missing it for the stream.

**Fix:** one private `abandonPendingRun()` on ChatStore; `clearConversation`, `openSession`, and
`reset()` all call it. Firing `onRunResolved` on the way out is deliberate — the user chose to walk
away, so the relay watch should stand down rather than stay armed against a session ChatStore has
stopped tracking (AppContainer expects paired watches).

**Widen the aim while you are here.** Three further instances of *state a transition should have
released and did not* were found the same weekend: **#191** (backend switch leaves the conversation
intact), **#192** (a switch guard that is never cleared), and this item's two paths. There is no
single complete "switch the conversation context" operation in T27; every path hand-rolls a different
subset. If `abandonPendingRun()` can reasonably be shaped as **the** primitive every switch path
calls — with the differences expressed as parameters rather than as separate subsets — do that. If it
cannot, say why in the PR body so the next lane knows.

Also note: `handlePairingRemoved` calls `LiveActivityService.endAllActivities()` and
`handlePairingActivated` does not. Decide whether that asymmetry is intentional.

**Trigger frequency, corrected:** the reviewer's "commonly" is wrong. The real trigger is one path —
drop on S1, switch to S2, send on S2, that reply matches the filter. Plausible, not common. Do not
let a frequency argument shrink the fix; `reset()`'s cross-host case is the reason this ships.

## Part 2 — #185: `mergeAttachments` aliases duplicate filenames

`ChatStore.swift:1764`. Each remote attachment resolves via
`localAttachments.first(where: { fileName == && mimeType == })`, which never dequeues the match. N
remote attachments sharing `(fileName, mimeType)` all resolve to `localAttachments[0]`.

The `?? localAttachments[safe: index]` fallback shows the intent was "pair by identity, index as
backup" — but it only fires when `first(where:)` returns nil, which never happens when duplicates
exist. **The safeguard is defeated in exactly the case it was written for.**

Wrongly copied: `localStoragePath`, `voiceMemoAudioPath` (#9), `remotePath` and `remoteProfileID`
(#21 Tier 2). Tapping the second bubble opens the first bubble's bytes; ShareLink hands out the wrong
file; a Tier 2 re-fetch targets the wrong remote path.

**Fix:** match `remote.id` first, fall back to `(fileName, mimeType)`, and dequeue matches from a
mutable copy so two duplicates cannot claim the same local entry. Retain `localAttachments[safe:
index]` as same-index insurance. `MessageAttachment.id` survives the round trip (copied verbatim at
`:1773`), and the sibling message-level merge directly above (`:1668–1687`) already models the right
pattern — prefer `id`, then `clientMessageID`, then `jobID`.

**Trigger, corrected:** the voice-memo trigger cited in the review **does not exist** — voice memos
carry second-resolution timestamps (`PendingAttachment.swift:252`) over `VoiceMemo-{UUID}.m4a`
(`VoiceMemoRecorder.swift:141`), and record→stop→attach makes two-in-one-second impossible. Photos
are safe too (`photo_{UUID.prefix(8)}.jpg`, `:158`). **The only real trigger is the file picker**,
which uses `url.lastPathComponent` verbatim (`:194`, `:197`): two same-named files across separate
picker rounds. Severity nit is correct — write the test against the picker case, not the voice case.

## Definition of done

- Pending run on S1 → `openSession(S2)` → assert no reconcile fires against S2.
- Streaming on S1 → `handlePairingActivated()` → assert the task is cancelled and `pendingRun` is nil.
  **Put this beside the existing #136 reset-race tests** — that is where it should have been caught.
- Two same-named files attached across separate picker rounds resolve to distinct local entries.
- No behavior change to the single-attachment and single-session paths — verified, not assumed.

## House rules

Merge commits only, never squash. File-scoped commits. **OPEN_ITEMS.md edits in their own separate
commit.** `xcodegen generate` only when Swift files are added or removed; pbxproj regen as its own
commit; verify `aps-environment: development` survived.
