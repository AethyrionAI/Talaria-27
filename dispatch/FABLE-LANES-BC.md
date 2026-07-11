# FABLE — Lanes B & C

Both probe-independent, pure-Swift, unit-test-heavy — fire in parallel with Lane A.
**Repo:** AethyrionAI/Talaria-27, base `main` @ 75dd6b3 (except Lane C item 5 — see note).
Pin every `gh` with `--repo AethyrionAI/Talaria-27`. Fable = implement + Swift Testing tests;
build / simulator / device validation is Mac-side.

---

## LANE B — Markdown rendering depth
**Branch:** `claude/t27-lane-b-markdown`

**Current state (confirmed at 75dd6b3):** `Talaria/Core/MarkdownParser.swift` (177 lines) —
`MarkdownSegment` has only THREE cases: `.prose`, `.codeBlock`, `.image`. Renderer:
`Talaria/Features/Chat/MarkdownContentView.swift`.

**Add:** headings, tables, block quotes, lists (ordered / unordered / nested), and syntax
highlighting for `.codeBlock` (use the existing `language`). Extend BOTH the `MarkdownSegment`
enum + parser AND `MarkdownContentView`.

**Tests:** one Swift Testing suite per new node type — parse correctness, nesting, and that mixed
prose / image / code interleaving order is preserved.

**Why:** daily-life readability win; compounds the shipped context-menu / copy work.

---

## LANE C — Correctness batch
**Branch:** `claude/t27-lane-c-correctness` (items 1-4). Item 5 is on a DIFFERENT branch — see its note.

1. **`/save` reports success on silent failure + never offers a share sheet.** In
   `ChatScreen.swift`, `case "save":` (`:975`) unconditionally appends "Conversation saved to
   Documents folder." (`:977`). Make the success message conditional on the write actually
   succeeding; on failure, surface the error; offer a share sheet.
2. **`HapticEngine.error()` defined but never called.** Defined at `HapticEngine.swift:20`; grep
   at HEAD shows ZERO call sites. Wire it into the failed-send path so failures buzz.
3. **Stale tracking comment.** `SessionsSettingsScreen.swift` header comment block (~lines 1-16).
   Verify against current behavior; update or remove if stale.
4. **#58 — inbox decoder skip-bad-rows hardening.** Decoder in `InboxStore.swift`
   (status enum in `InboxItemStatus.swift`). Today one bad-`kind` row poisons the WHOLE inbox
   fetch (manifests app-side as "relay offline"). Make decode per-row resilient — skip / quarantine
   unparseable rows, keep the rest. Valid kinds: alert / approval / notification / reminder /
   suggestion. Add tests with a mixed good/bad-row payload.
5. **#84 — preflight third state.** NOTE: preflight does NOT exist on `main` — grep confirms it.
   Base this on branch `claude/t27-84-talk-preflight` (@ c9e909e, green 13/13). Today the preflight
   misclassifies "no mic input" as "permission denied." Add a THIRD state: permissions OK + no mic
   input -> guidance "try rebooting." Pure logic + unit tests now; device verify post-seed. Keep the
   branch green; it merges (Mac-side) after the device checklist AND this fix.

---

## Merge sequencing (Mac-side)
- Lane B is independent — merge anytime.
- Lane C items 1-4 are independent; item 5 stays on the `claude/t27-84-talk-preflight` branch.
- Lane C touches `ChatScreen.swift` (`/save`); Lane A also touches `ChatScreen` — **merge C before A**
  so A rebases onto it.
- Every branch: `xcodegen generate` if Swift files are added/removed (SEPARATE regen commit).
  Swift Testing suites report as "Test run with N tests passed" — grep that, not XCTest "Executed N".
- Line refs confirmed at 75dd6b3 — re-confirm at branch HEAD.
