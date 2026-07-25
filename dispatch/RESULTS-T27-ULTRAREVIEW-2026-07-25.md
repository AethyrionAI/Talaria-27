# RESULTS — T27 Ultrareview, Passes A & B — 2026-07-25

Companion to `dispatch/RESULTS-T27-DEVICE-PASS-2026-07-25.md`. Two `/ultrareview`
runs against the merged-train state of `main` (`1ea7e23`), plus local verification
of every claim they made.

**Every finding below was re-checked against source before being recorded here.**
Where the reviewer and the source disagree, the source wins and the disagreement
is documented — one severity call was inverted and one suggested patch would have
shipped a crash.

---

## Run accounting

| | |
|---|---|
| Free runs (one-time, never refresh) | 3 |
| Consumed | 2 — Pass A, Pass B |
| Remaining | **1** |
| Hard limits | 500 files / 8,000 lines per review |
| Cost after free runs | ~$5–25 in usage credits |

Pass A **failed at final report assembly** after every substantive stage passed
(Setup ✓, Find 3 candidates ✓, Verify 3 confirmed / 0 refuted ✓, Dedupe produced
3 issues). The credit was consumed anyway — a run counts once the cloud session
starts. The report payload was recovered by scrolling the raw output pane before
closing the session; it is not retrievable afterward (`/tmp/bughunter_work/` lives
in the remote sandbox).

---

## Findings summary

| # | Finding | Location | Reviewer severity | Verified severity |
|---|---|---|---|---|
| 1 | `openSession` leaks stale `pendingRun` into another session's reconcile | `ChatStore.swift:1297` | normal | normal — **confirmed** |
| 2 | `reset()` teardown gap | `ChatStore.swift:1343` | "latent hygiene, not an active defect" | **active, cross-host — reviewer wrong** |
| 3 | `mergeAttachments` aliases duplicate filenames | `ChatStore.swift:1764` | nit | nit — confirmed, trigger narrower than stated |
| 4 | `CalendarEventTool` rejects `.writeOnly` | `DeviceActionTools.swift:213` | — | **confirmed** |
| 5 | `ContactsTool` rejects `.limited` | `DeviceReadTools.swift:331` | — | **confirmed** |

---

## Pass A — findings 1 & 2: ChatStore teardown asymmetry

The reviewer merged these as `merged_bug_001`. They are one root defect surfacing
in two teardown paths.

### Mechanism

`clearConversation()` (`ChatStore.swift:735–761`) is the canonical teardown. It
cancels `reconcileTask`, fires `onRunResolved` for any abandoned `pendingRun`,
nils `pendingRun`, cancels `streamingTask`, ends the Live Activity, and stops
speech.

Two sibling paths also abandon the current run and do **not** match it:

| | `streamingTask` | `pendingRun` / `reconcileTask` | Live Activity |
|---|---|---|---|
| `clearConversation` (:735) | ✓ | ✓ | ✓ |
| `openSession` (:1297) | ✓ | ✗ | ✓ |
| `reset()` (:1343) | ✗ | ✗ | ✗ |

`pendingRun` is declared at :202, carries a `sessionId` (:207), is set at :611,
and is cleared in exactly two places — :741 (abandon) and :1512 (reconcile
completion). The reconcile loop reads it unconditionally at :1444 / :1451 / :1459
on a 2-second tick.

The reason a stale `pendingRun` corrupts a *different* session:
`reconcileFromServer()` takes no session argument. `ChatBackendRouter:373–378`
delegates straight to `hermes.reconcileFromServer()`, and the client's internal
session has already been switched by `openSession`. So the reconcile compares S1's
pending against S2's server view.

### Harms, all persisted

- `:1487` — S1's `partialReasoning` written onto a matched S2 reply's `reasoning`
- `:1498` — `turnDuration` computed as S2-reply-minus-S1-send; a nonsense span stamped as the turn receipt
- `:1514` — `onRunResolved?(S1)` withdraws the S1 relay watch, so S1's real completion push (#38) is silently dropped
- `:1516` / `:1520` — polluted messages hit `saveConversationCache`, and the journal hop waterline advances over the spurious exchange

Reach extends past ChatStore: `AppContainer:1416` and `:1948` both route off
`chatStore.pendingRunSessionId`.

### Correction — the `reset()` severity is inverted

The report states: *"I verified that `reset()` has no callers in this branch — a
repository-wide grep returns only `journal?.reset()` INSIDE its own body. So the
harm the finder describes there is not reachable today."*

**This is wrong.** `chatStore.reset()` has two live callers, both on the pairing
lifecycle:

- `AppContainer.swift:1557`, inside `handlePairingActivated()` (:1552) — wired to `PairingStore.onPairingChanged`, and followed immediately by `await initialize()` against the new pairing
- `AppContainer.swift:2243`, inside `handlePairingRemoved()` (:2231)

`AppContainer.swift` was excluded from the Pass A bundle (2,459 lines, cut for
budget). The reviewer's "repository-wide" grep covered the 29-file slice, not the
repository. It hedged with "in this branch" and then drew a conclusion about the
app.

This makes `reset()` the **more** serious half: pair or unpair mid-stream and
`conversation` goes nil while `streamingTask` keeps running and `pendingRun` stays
armed, then `initialize()` runs against a **different host**. Cross-host leakage,
not cross-session.

Both call sites carry `#136` comments about a half-flight background bootstrap
landing state into freshly reset stores — the same race class, reasoned about for
the bootstrap and missed for the streaming task. Note also that
`handlePairingRemoved` calls `LiveActivityService.endAllActivities()` and
`handlePairingActivated` does not.

### Correction — trigger analysis overstates frequency

The step-by-step proof visibly self-corrects mid-argument ("wait, T=-3600 is NOT >
T=0.0") and lands on the claim that S2 commonly holds a Hermes message timestamped
after the S1 send. That doesn't hold — prior S2 activity is by definition earlier
than the S1 send. The real trigger is a single path: drop on S1 → switch to S2 →
send on S2 → that reply matches the filter. Plausible, but one path, not "common."

### Fix

One private `abandonPendingRun()` on ChatStore; `clearConversation`, `openSession`,
and `reset()` all call it. Firing `onRunResolved` on the way out is deliberate —
the user chose to walk away, so the relay watch should stand down rather than stay
armed against a session ChatStore has stopped tracking (AppContainer expects paired
watches).

---

## Pass A — finding 3: `mergeAttachments` aliases duplicate filenames

`ChatStore.swift:1764`. Each remote attachment is resolved via
`localAttachments.first(where: { fileName == && mimeType == })`, which never
dequeues the match. N remote attachments sharing `(fileName, mimeType)` all
resolve to `localAttachments[0]`.

The `?? localAttachments[safe: index]` fallback shows the intent was "pair by
identity, index as backup" — but it only fires when `first(where:)` returns nil,
which never happens when duplicates exist. **The safeguard is defeated in exactly
the case it was written for.**

Fields wrongly copied: `localStoragePath`, `voiceMemoAudioPath` (#9),
`remotePath` and `remoteProfileID` (#21 Tier 2). Tapping the second bubble opens
the first bubble's bytes; ShareLink hands out the wrong file; a Tier 2 re-fetch
targets the wrong remote path.

The sibling message-level merge directly above (`:1668–1687`) already models the
right pattern — prefer `id`, then `clientMessageID`, then `jobID` — and
`MessageAttachment.id` survives the round trip (copied verbatim at `:1773`).

### Correction — the voice-memo trigger does not exist

The report cites "voice memos the recorder saves under a stable name" as a
trigger. Verified false:

- `PendingAttachment.voiceMemoFileName` (`PendingAttachment.swift:252`) produces `Voice Memo 2026-07-06 14.30.05.txt` — second-resolution timestamps
- the on-disk recording is `VoiceMemo-{UUID}.m4a` (`VoiceMemoRecorder.swift:141`)

Two memos would have to be recorded within the same second, which record → stop →
attach makes impossible.

The Photos path is genuinely safe as the report says — `PendingAttachment.image`
auto-generates `photo_{UUID.prefix(8)}.jpg` (`:158`). **The only real trigger is
the file picker**, which uses `url.lastPathComponent` verbatim (`:194`, `:197`):
two same-named files attached across separate picker rounds. Severity "nit" is
correct, for one of the two reasons given.

### Fix

Match `remote.id` first, fall back to `(fileName, mimeType)`, and dequeue matches
from a mutable copy so two duplicates cannot claim the same local entry. Retain
`localAttachments[safe: index]` as same-index insurance. The reviewer's patch is
correct as written.

---

## Pass B — findings 4 & 5: permission accept-lists reject valid grants

Both tools treat a *narrower but sufficient* grant as a denial, then report that
denial to the model. `LocalChatBackend` instructs the model to relay
permission-denied results faithfully — so the user is told to go enable a
permission they already granted. That is precisely the fabrication the tool belt
exists to prevent.

### Finding 4 — `CalendarEventTool` rejects `.writeOnly`

`DeviceActionTools.swift:213–221`. The switch handles `.notDetermined` and
`.fullAccess`; `.writeOnly` falls through to `default:` and returns *"Calendar
permission is not granted — nothing was created."*

But `store.save(event, span: .thisEvent, commit: true)` at `:233` is exactly what
`.writeOnly` authorizes. And the `.notDetermined` branch calls
`requestFullAccessToEvents()` (`:215`), which returns `false` when the user picks
"Add Events Only" from Apple's sheet — so the false denial lands on the first
attempt and every one after.

**Fix: add `case .writeOnly: break` beside `.fullAccess`. Do not change the
request call.**

### Finding 5 — `ContactsTool` rejects `.limited`

`DeviceReadTools.swift:331–340`. `status != .authorized` catches iOS 18's Contact
Access Picker grant, even though `unifiedContacts(matching:)` returns hits from
the approved subset normally.

It works exactly once: the `.notDetermined` path uses `requestAccess(for:)`, which
returns `true` for a limited grant, so the first lookup passes through. Every
launch after that hits the status check and fails.

**Fix: accept `.limited` alongside `.authorized`.** `NSContactsUsageDescription`
is present (`project.yml:163`), so there are no plist implications.

### REJECTED refinement — `requestWriteOnlyAccessToEvents()` would ship a crash

A proposed refinement was to also swap `requestFullAccessToEvents()` →
`requestWriteOnlyAccessToEvents()` in the `.notDetermined` branch, on the grounds
that the tool only creates events and full access is over-requesting. **Do not
apply this.** Two independent reasons:

1. **It crashes.** `project.yml:161` declares `NSCalendarsFullAccessUsageDescription`
   and there is no `NSCalendarsWriteOnlyAccessUsageDescription`. Calling
   `requestWriteOnlyAccessToEvents()` without that key is a hard TCC crash at
   request time, not a soft denial.

2. **It poisons the reader.** `DeviceCalendarTools.swift:28–37` — the calendar
   reader — has the identical switch shape: `.notDetermined` →
   `requestFullAccessToEvents()`, `.fullAccess` → break, `default:` → denied. If
   the create tool primes with write-only, the reader then sees `.writeOnly`,
   falls to `default:`, and can **never re-prompt** because the status is no
   longer `.notDetermined`. One use of the create tool would permanently cost the
   user calendar reading.

The "over-requesting" framing is true of that tool in isolation and false of the
app: Talaria both reads calendars and creates events, so full access is the honest
ask.

### Deployment-target claim — right answer, wrong method

The refinement also proposed dropping `#available(iOS 17/18, *)` guards, reasoning
that FoundationModels and AlarmKit are imported unguarded. The conclusion is
correct but was inferred rather than checked. Verified directly:
`project.yml:6–7` sets `deploymentTarget.iOS: "27.0"`. No guards needed.

### Open — write-only dead end on the read side

Not a reviewer finding; surfaced during verification. Apple's *full-access* sheet
itself offers "Add Events Only," so `.writeOnly` is reachable from the **existing**
code path. A user who picks it gets a reader that says "enable it in Settings"
when they already granted what they were shown, with no re-prompt path.

The reader genuinely cannot read under write-only, so this is a message fix rather
than a logic fix: the `default:` branch should name the write-only case and tell
the user to widen the grant to full access. Same defect family — a truthful-looking
message that misdescribes the user's actual state.

### Verified correct as-is — no change needed

- `ReminderCreateTool` (`DeviceActionTools.swift:107–116`) — same switch shape, but EventKit has no write-only state for reminders
- `DeviceCalendarTools.swift:92–100` (reminders reader) — same, correct
- `DeviceCalendarTools.swift:28–37` (events reader) — logic correct; only the denial message needs work (above)

---

## Related — correction to the device-pass results doc (#147)

Surfaced while verifying `RESULTS-T27-DEVICE-PASS-2026-07-25.md`; recorded here so
it is not lost.

That doc names *"annotate the delegate method `@MainActor`"* as the candidate fix
for the notification-tap crash. **That change is already in the build that
crashed:**

```
22f92e1  07-21 20:11  fix(#147): @MainActor on HermesAppDelegate — notification
                      completion bridge must fire on main; cold launch-by-
                      notification hit UIKit state-restoration assert off-main
```

Verified ancestor of the tested build `1ea7e23`. It annotated the **class**, which
fixed the cold-launch case. But `AppEntry.swift:141` still reads
`nonisolated func userNotificationCenter(_:didReceive:) async`, and the explicit
`nonisolated` on the method opts back out of the class-level isolation. #147 is
defeated at the one method that matters.

The real fix must remove or narrow that `nonisolated` while preserving the #47
process-lifetime guarantee the comment at `:137–140` protects — a harder call than
the doc implies. Do not write a lane from that doc's candidate fix as stated.

---

## Process lessons

**1. A subset review cannot make reachability claims. Discount them to zero.**
This cost us a severity inversion on the most serious finding. The reviewer cannot
distinguish "no callers in the repository" from "no callers in my slice," and it
will report the second as the first. The remedy is *not* to bundle
`AppContainer.swift` into every pass — 2,459 lines is 31% of the budget for a DI
file. It is to treat every reachability claim as unverified and grep locally, which
took two commands. **Add to the dispatch template.**

**2. Read the step-by-step proofs, not the summaries.** Both Pass A findings had
sound mechanisms and unsound trigger analysis — one self-corrected mid-proof and
recovered onto a false claim, the other invented a voice-memo trigger that does not
exist. The mechanism sections were reliable; the "when does this fire" sections
were not.

**3. Any permission-API change needs a plist/entitlement check before it ships.**
The single highest-value catch in this whole exercise was noticing that a suggested
one-line swap had no matching usage-description key. Verify against
`project.yml` `info.properties` — remember `INFOPLIST_KEY_*` build settings are
silently ignored with a generated Info.plist.

**4. Verify platform claims against `project.yml`, not against import style.**
Right answer, wrong method is still a coin flip.

**5. A failed run still burns a credit — and the payload is recoverable.** If the
final assembly fails, scroll the raw output pane before closing the session. That
is the only reason Pass A's findings exist.

---

## Proposed lanes

**Lane 1 — unified teardown (findings 1 + 2).** Private `abandonPendingRun()` on
ChatStore, called by `clearConversation`, `openSession`, and `reset()`. Tests:
pending on S1 → `openSession(S2)` → assert no reconcile fires against S2;
streaming on S1 → `handlePairingActivated()` → assert task cancelled and
`pendingRun` nil. The second belongs beside the existing #136 reset-race tests,
which is where this should have been caught.

**Lane 2 — `mergeAttachments` id-first + dequeue (finding 3).** Small,
self-contained, patch already correct.

**Lane 3 — permission accept-lists (findings 4 + 5).** Add `.writeOnly` to
`CalendarEventTool`, `.limited` to `ContactsTool`. Optionally add
`NSCalendarsWriteOnlyAccessUsageDescription` to `project.yml` as cheap insurance
against anyone reaching for that API later, and improve the calendar reader's
write-only denial message.

**Not a lane yet — #147.** Needs a design decision on the `nonisolated` /
process-lifetime tradeoff before it can be specified.

---

## Appendix — pass composition and reproduction

Base ref for both passes: `ultrareview-void` (`a7623a2d`), a synthetic root commit
with an empty tree and no parents. Sharing no merge base with `main` makes the
whole subset present as all-new code, so a *diff* reviewer performs a *full-file*
review of exactly the chosen files.

| | Pass A | Pass B |
|---|---|---|
| Branch | `ultrareview-subset` | `ultrareview-pass-b` |
| Files | 29 | 20 |
| Lines | 7,848 | 7,812 |
| Scope | notifications, push/device identity, controls handoff, ChatStore, voice lifecycle | native vs realtime voice engines, standalone fallback, device tools |
| Outcome | report assembly failed; payload recovered by hand | clean |

Excluded from both: `AppContainer.swift` (2,459 lines) — the direct cause of
lesson 1 above.

Worktree used: `/Users/owenjones/Documents/Claude/t27-ultrareview` (separate
worktree, so the main checkout is never switched out from under an open session).

```bash
# build a subset branch without touching the working tree
export GIT_INDEX_FILE=/tmp/ur-index && rm -f /tmp/ur-index
git ls-tree -r HEAD -- $(cat /tmp/ur-files.txt) | git update-index --index-info
TREE=$(git write-tree)
C=$(git commit-tree $TREE -p $(git rev-parse ultrareview-void) -m "subset")
git branch -f ultrareview-subset $C
unset GIT_INDEX_FILE

# review it
cd /Users/owenjones/Documents/Claude/t27-ultrareview
git switch ultrareview-subset
# /ultrareview ultrareview-void
```

Cleanup when finished: `git worktree remove ../t27-ultrareview`, then delete
`ultrareview-void`, `ultrareview-subset`, `ultrareview-pass-b`.
