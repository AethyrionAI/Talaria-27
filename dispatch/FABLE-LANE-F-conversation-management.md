# FABLE LANE F — Conversation management: in-app search + pin/archive

**OPEN_ITEMS:** #96 (search), #97 (pin/archive)
**Branch prefix:** `claude/t27-lane-f-`
**Collision status:** verified clear 2026-07-11 — merge train (#59/#60/#61/#63) landed; only open PR is #65 (Lane D, new-files-only IR). No other lane touches drawer/session surfaces.

## Objective

Both ChatGPT iOS and Claude iOS ship first-class in-app conversation search and
list hygiene (pin, archive). Talaria has neither: search exists only as opt-in
Spotlight indexing (#66) plus a local-brain tool, and the drawer is a flat list.
Close both gaps in one lane since they share the same surfaces (journal store +
drawer).

## Grounding — read these BEFORE designing (probe-first rule)

- `Talaria/Features/Chat/Sessions/SessionsDrawer.swift` — the drawer UI you
  will extend. Understand its data source and row model first.
- `Talaria/Stores/ConversationJournalStore.swift` — local persistence; search
  and pin/archive metadata both live here.
- `Talaria/Models/ConversationJournal.swift` — the entity model.
- OPEN_ITEMS #66 (Spotlight) — indexes the same entities; do not duplicate its
  indexing work, but search results should cover the same corpus.
- OPEN_ITEMS #93 (continuity fabric, MERGED) — the journal is now the primary
  local record; treat it as the search source of truth alongside fetched
  Hermes server sessions.

## Deliverables

### 1. Search (#96)
- New `ConversationSearchScreen` (new file[s]) reachable from the drawer: a
  search field over (a) local `ConversationJournal` entries and (b) fetched
  Hermes server sessions. Match on title + message text where available
  locally; server sessions may be title-only — show what exists, no fabricated
  snippets (real-data-only rule; use "—" when a field is missing).
- Results grouped: local journal hits, then server-session hits. Tapping a
  result opens that conversation exactly as the drawer would.
- Debounced query, case/diacritic-insensitive. No network calls per keystroke —
  server sessions are searched against the already-fetched list.

### 2. Pin / archive (#97)
- Add `isPinned` / `isArchived` metadata to the journal model + store, with
  migration that defaults both false for existing records. Server-session rows
  get the same treatment via a local overlay keyed by session id (the server
  schema is not ours to change).
- Drawer: pinned section floats to top; NO artificial pin cap (ChatGPT caps at
  3 — we deliberately don't). Archived rows hidden from the main list,
  reachable via an "Archived" filter row at the drawer bottom.
- Swipe actions + context menu on rows: pin/unpin, archive/unarchive. No
  delete semantics change in this lane.

### 3. Tests
- Swift Testing (`@Test`) suites: store-level search matching (case,
  diacritics, empty query, no-hit), pin/archive persistence + migration
  defaults, pinned-sort + archived-filter of the drawer's data source.
- UI-independent: test the store/view-model layer, not SwiftUI rendering.

## Hard constraints

- **Do NOT touch** `ChatScreen.swift`, the composer, or the transcript
  surface. Drawer + stores + new files only.
- File-scoped commits: `pbxproj` regen in its own commit; no `OPEN_ITEMS.md`
  edits in this lane (Owen owns those).
- New Swift files ⇒ note in PR that Mac side must run `xcodegen generate` and
  re-verify `aps-environment: development` survives in the entitlements.
- Cloud can't build: author + unit-test logic; the Mac review-then-build loop
  verifies against the iOS 27 SDK. Design so a build failure is unlikely to
  require rework (no exotic APIs; check availability against iOS 27).

## Acceptance

- All new `@Test` suites green (grep for the Swift Testing pass line, not the
  XCTest summary).
- Search finds a known local journal entry by body text and a server session
  by title; missing fields render "—", never placeholder data.
- Pin floats a row above unpinned regardless of recency; archive removes it
  from the main list and the Archived filter shows it. Both survive relaunch.
- PR titled `Lane F — conversation management: search + pin/archive (#96 #97)`.
