# OPUS-T27-176B + 186 — the belt stops reaching, and stops lying about permissions

**Items:** OPEN_ITEMS #176 (widened) + #186 · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-176b-belt-truth` · **Toolchain:** Xcode-beta4 = **Xcode 27.0 (27A5228h)**, pinned sim
**Evidence scope:** your return MUST state the Xcode build your suite ran on (`xcodebuild -version`). If your
environment cannot build against 27A5228h, say so explicitly — a green on any other SDK is NOT a green here
(2026-07-27: the #189/#147 return did not compile on 27A5228h; Swift 6 isolation strictness differs across SDK builds).
**Baseline:** confirm the current green count before you start · `export GH_PAGER=cat` first

## SHIP BLOCKER (the #176 half). Free tier is standalone on-device.

## ORDERING — read this first

**PR #148 must merge before this branch is cut.** #148 is the vision-specific half of #176: it made
`readImageText`/barcode conditional on an image being in context, added `ImageDependentTool` +
`DeviceToolBelt.offeredTools(from:hasImageInContext:)`, and taught `LocalChatBackend` to recreate the
session when the condition flips. It is correct and correctly scoped. **Do not redo it, do not revert
it, do not widen it in place.** Branch from main after it lands and build on top.

## The observation — the reflex is unconditional, not vision-specific

Device: whoGoesThere, on-device backend, 2026-07-25. Every turn routed to a tool, including turns no
tool can serve:

| Prompt | Tool fired |
|---|---|
| "Remember the number 7" | offered to create a Reminder |
| "Can you tell me about Greece?" | declined to answer, offered to search |
| "What's the capital of Greece" | `SEARCHPLACES` (failed — airplane mode) |
| "What number did I ask you to remember" | `READREMINDERS` |
| "Repeat my previous message word for word" | `READREMINDERS` |
| "What is 2+2" | `SEARCHCONVERSATIONS`, searching the literal string "2+2" |

It **re-selects per turn** — different tools across turns — so this is not a jammed selection. The
selector always picks something.

**The model has the history and ignores it.** Verified: history IS replayed into the
`LanguageModelSession` transcript on every rebuild —
`transcriptTurns(from: currentConversation?.messages ?? [])`, `LocalChatBackend.swift:609`. This is a
**selection** defect, not a context-assembly defect. Do not go looking for missing history.

**Connectivity gating is NOT the fix.** The 2+2 failure happened online with full bars. The network
was never the problem.

## Root cause — already located, start here

`LocalChatBackend.instructionsText(deviceContext:date:hasTools:)`. The tool-bearing branch says:

> You have device tools — [enumerated list] — plus action tools... **Use them to work with the
> user's real data instead of guessing.** ... When a tool reports that a permission isn't granted or
> no data exists, **relay that honestly — never invent a value.**

Two problems, and PR #148 changed neither:

1. **"instead of guessing" frames the model's own knowledge as guessing**, immediately after an
   enumerated tool list. There is no clause anywhere authorizing it to just answer. The tool-LESS
   branch *does* have that clause ("say so plainly instead of guessing") — the asymmetry is the bug.
   Fable already noted this asymmetry in the #148 write-up and correctly left it out of scope.
2. **"relay that honestly" is a good instruction pointed at the wrong thing.** It should govern how a
   tool *result* is reported. Instead the denial becomes the *entire answer*, on every subsequent
   turn.

## The absorbing state — the sharpest consequence

Once any tool returns a denial, every later turn returns the same canned denial text and the user's
actual question is never seen. Observed: two different questions ten minutes apart produced
near-identical denial replies. **The chat is dead with no in-chat exit.** It is reached by declining
a permission the user was never asked to grant.

It compounds with **#190** (the only escape — a new chat — destroys the history). #190 is a separate
lane; do not fix it here.

## Scope

**Part A — instructions (#176).**

- Add an explicit clause authorizing the model to **answer from its own knowledge when no tool
  applies**. Facts it knows are not guesses. General knowledge is not device data.
- Scope the "use tools instead of guessing" instruction to **user-specific and device data** — health,
  location, calendar, reminders, contacts, the user's own conversations — not to the world.
- Add a **recovery clause**: a tool failure or permission denial is *information about the tool*, not
  the answer to the user. Answer the question without the tool, and do not repeat a denial already
  given in this conversation.
- These are prompt edits. Keep them minimal and legible; this file is the app's voice.

**Part B — belt membership (#176).**

- `ConversationSearchTool` advertises *"the current thread's messages plus the titles/previews of
  indexed past sessions."* Standalone has **no** past sessions (#190), so it can only ever see the
  thread already on screen — and the selector reaches for it constantly. Either withhold it from the
  standalone belt or correct its description to state what it actually covers there. **State which
  you chose and why.**
- PR #148's `offeredTools(from:...)` is the seam for any withholding. Reuse it; do not add a parallel
  mechanism.

**Part C — permission accept-lists (#186).** Small, self-contained, patches already known-correct:

- `DeviceActionTools.swift:213–221` — `CalendarEventTool` sends `.writeOnly` to `default:` and reports
  a denial, but `store.save(event:span:commit:)` at `:233` is exactly what `.writeOnly` authorizes.
  **Fix: add `case .writeOnly: break` beside `.fullAccess`.**
- `DeviceReadTools.swift:331–340` — `ContactsTool` rejects `.limited`, though
  `unifiedContacts(matching:)` returns hits from the approved subset normally.
  **Fix: accept `.limited` alongside `.authorized`.** `NSContactsUsageDescription` is present
  (`project.yml:163`); no plist implications.
- `DeviceCalendarTools.swift:28–37` — the events *reader* genuinely cannot read under `.writeOnly`, so
  this is a **message** fix, not a logic fix: name the write-only case and tell the user to widen the
  grant. Today it says "enable it in Settings" to someone who already granted what they were shown,
  with no re-prompt path.

## HARD PROHIBITION — this would ship a crash

**Do NOT swap `requestFullAccessToEvents()` → `requestWriteOnlyAccessToEvents()`** in the
`.notDetermined` branch, however tempting the "we only create events" argument looks.

1. `project.yml:161` declares `NSCalendarsFullAccessUsageDescription` and there is **no**
   `NSCalendarsWriteOnlyAccessUsageDescription`. Calling that API without the key is a hard TCC crash
   at request time, not a soft denial.
2. It poisons the reader: `DeviceCalendarTools.swift:28–37` re-prompts only from `.notDetermined`. If
   the create tool primes write-only, the reader can **never** re-prompt. One use of the create tool
   would permanently cost the user calendar reading.

Talaria both reads calendars and creates events, so full access is the honest ask. Optionally add
`NSCalendarsWriteOnlyAccessUsageDescription` to `project.yml` `info.properties` as insurance against
someone reaching for that API later — and remember `INFOPLIST_KEY_*` build settings are silently
ignored with a generated Info.plist.

## Definition of done

- On-device, offline: "what is 2+2" and "what's the capital of Greece" are **answered**, not searched.
- On-device: a recall question about earlier in the same chat is answered from context, no tool.
- Deny a permission, then ask three unrelated questions — each is answered on its own terms. **No
  canned-denial loop.**
- Health/location/calendar questions still route to tools. Verify the fix did not simply turn tools
  off — that is the failure mode to guard against.
- Grant Calendar "Add Events Only": creating an event succeeds. Grant Contacts limited access: lookup
  works on the second launch and every launch after.
- PR #148's vision gating still holds — its tests stay green, unmodified.
- Device verification is **owed by Owen**; state in the PR body what a device run should check.

## House rules

- Merge commits only, never squash. File-scoped commits.
- **OPEN_ITEMS.md edits in their own separate commit.**
- `xcodegen generate` only when Swift files are added or removed; pbxproj regen as its own commit;
  verify `aps-environment: development` survived.
