# OPUS-T27-190 — standalone sessions: a real store, not a single slot

**Item:** OPEN_ITEMS #190 (touches #26, #19, #104) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-190-local-session-store` · **Toolchain:** Xcode-beta4, pinned sim
**Baseline:** confirm the current green count before you start · `export GH_PAGER=cat` first

## SHIP BLOCKER. Free tier is standalone on-device.

## The observation

Device: whoGoesThere (iPhone 17 Pro Max), on-device backend, 2026-07-25/26.

Start a new chat and the previous local conversation is **gone** — not unlisted, unreachable. Make a
new chat, hit New again, and that one is gone too. The sessions drawer shows nothing for past local
chats. Hermes history on the same device restores correctly, so only the standalone path is affected.

## This is not a persistence bug — do not go looking for one

Already established in source. Do not re-derive it; start from here.

The standalone path stores exactly **one** conversation, at every layer:

- `AppPersistenceStoreProtocol` — `loadConversationCache() -> Conversation?` is a **single optional,
  not a keyed collection**. `saveConversationCache(_:)` overwrites. There is no id-keying.
- `LocalChatBackend.listSessions()` (`:563`) returns a **one-element array** synthesized from
  whatever conversation is currently loaded, or `[]`.
- `LocalChatBackend.openSession(id)` (`:569`) throws `sessionNotFound` unless the id **is** the
  conversation already open.

Marked `// MARK: - Sessions (local-only by design)` and `#26`. It was a deliberate scope cut. It is
now a ship blocker.

Contrast **#19**: connected-mode history comes from the Hermes Sessions API, which is why the
connected path is unaffected and must stay unaffected by this lane.

## Direction — decided, not open for re-litigation

**SwiftData.** Owen's call, 2026-07-26.

**Explicitly rejected: scaling the UserDefaults blob to N conversations.** See **#104** — the sensor
outbox already demonstrates that pathology (whole-blob rewrite on every tick, on the main actor).
Doing it with full transcripts would be materially worse. If you find yourself adding a
`[String: Conversation]` to `UserDefaultsAppPersistenceStore`, stop.

## Scope

**Phase 1 — model + store.**

- A SwiftData model for a local session: id, title, created/lastActive, and its messages. Decide
  whether messages are a SwiftData relationship or an encoded blob on the session row, and **write
  down why** — a relationship is queryable and migratable; a blob is simpler and matches how
  `Conversation` is already encoded. Either is acceptable; an unstated choice is not.
- A store type behind a protocol, in the same shape as the existing persistence protocols so it is
  testable without a live container.
- `AppPersistenceStoreProtocol`'s single-slot conversation cache **stays** for now — it is the
  kill/relaunch restore path and other things read it. Do not delete it in this lane.

**Phase 2 — back the backend with it.**

- `LocalChatBackend.listSessions()` returns every stored local session, most recent first.
- `LocalChatBackend.openSession(id)` loads by id and succeeds for any stored session.
- New-chat stops destroying: whatever teardown runs on New must **persist the outgoing conversation**
  before the new one becomes current.
- Session identity: a local session needs an id that survives the app. `Conversation.id` already
  exists — use it rather than minting a parallel one, and confirm it is stable across a relaunch.

**Phase 3 — migration.**

- Existing installs hold exactly one conversation in the UserDefaults cache. On first run of the new
  store, adopt it as the first session. **Do not drop it.** A user who upgrades must not lose the
  conversation they had.
- Migration must be idempotent — running twice must not produce two copies.

**Phase 4 — drawer.**

Design is decided; implement it, don't redesign it:

- **One unified list**, sorted globally by recency. **Not** two lanes, **not** grouped by source.
- Origin carried by a small glyph in the row's **existing leading element** — not a text badge, which
  costs horizontal room the row does not have.
- **Suppress the origin affordance entirely until sessions from more than one source exist.**
  Free-tier users have exactly one source; the marker is pure noise for them.
- Unresumable sessions (Hermes sessions after unpair) stay **visible and dimmed with a reason**, not
  hidden. Hiding them makes the drawer lie about the user's history.

## Explicitly out of scope

- The connected/Hermes session path. If a change would alter connected behavior, it is out.
- **#176**'s tool-selection defect. Related by consequence (see below) but a separate lane.
- Deleting or reworking `saveConversationCache`.

## Why the compounding matters, for context only

With #176's unconditional tool reflex, a local chat can reach a state where every turn returns the
same canned tool denial. The only escape is a new chat — which today destroys the history. The two
defects form a trap with no exit, reachable in under a minute from a fresh install. **Fixing this
lane alone removes the data loss half of that trap.** Do not try to fix the other half here.

## Definition of done

- Two local chats exist simultaneously; both appear in the drawer; both open with their messages.
- New chat does not destroy the previous one. Kill and relaunch — both still there.
- A pre-existing single cached conversation survives the upgrade and appears as a session.
- Connected-mode session list and restore behave exactly as before — verified, not assumed.
- Deterministic tests for: list ordering, open-by-id, new-chat persistence, migration idempotency.
- Device verification is **owed by Owen** — do not mark the item closed on a green suite. State in
  the PR body exactly what a device run should check.

## House rules

- Merge commits only, never squash. File-scoped commits.
- **OPEN_ITEMS.md edits go in their own separate commit** — this has been flagged repeatedly.
- `xcodegen generate` if and only if Swift files are added or removed; keep the pbxproj regen as its
  own commit; verify `aps-environment: development` survived afterwards.
- New test files require a regen before the build gate can be trusted.
