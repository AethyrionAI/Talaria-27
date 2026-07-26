# OPUS-T27-SESSIONS-DRAWER — 2b: the thumb-anchored session shelf

**Items:** sessions-drawer redesign (no OPEN_ITEMS entry yet — see note at foot) · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-sessions-drawer-2b` · **Toolchain:** Xcode-beta4, pinned sim
**Baseline:** 1121 tests / 103 suites + 8 UI · `export GH_PAGER=cat` first
**Staleness check:** run `gh pr list --repo AethyrionAI/Talaria-27 --state all --limit 20`.
Verified clean 2026-07-26 — no open PR touches the drawer. Re-verify before starting.
**Design source:** Claude Design study, turns 1–3. Owen holds the HTML. **Every number you
need is inline below — do not block on the file.**

## What this is

Rebuild `ConversationListPane` as the **2b** shape: thumb-anchored action dock, one search,
bare rows on hairlines, nav collapsed to a 44pt four-up rail inside the dock, panel owning its
own safe-area inset. It was chosen over the top-anchored variant (2a) on density and one-handed
reach — and 2a survives as the **iPad** form via a single property, so this is one component,
not two layouts.

---

## PHASE 0 IS MANDATORY — confirm before writing code

The layout below was designed against source by a reader that could not compile. Turn 2 of that
study made two claims that turned out wrong (a suppression API that does not exist, and a pt
budget that did not reconcile). **Assume at least one premise here is also wrong.** Report Phase 0
before proceeding; if a confirm contradicts the spec, STOP that item and report rather than
implementing the guess.

1. **Is the list a `ScrollView` + `LazyVStack`, or a `List`?** Everything in section 1.05 —
   gradient masks plus a bottom content inset equal to the dock — assumes you can set content
   insets and overlay a mask. If it is a `List`, say so before designing around it.
2. **Do `tasksRow` / `skillsRow` / `insightsRow` / `archivedFilterRow` exist as discrete views?**
   The rail replaces them. If they are inlined, the delete surface is different.
3. **Confirm `SessionsDrawerModel.grouped()` owns grouping and is safe to leave untouched.**
   The filter in section 3 must slot in without rewriting it.
4. **Is the active session's identity reachable inside the pane?** `HermesSessionInfo.isActive`
   exists and is mapped (`SessionsHermesClient.swift:628–631`) — confirm the pane can see it.
   Section 3 is unsafe without it.
5. **Where does the header's thread count come from?** Section 3 changes what it counts.

---

## 1 · Spine — the six defects

All six are visible in the Deep Field device screenshot; do not treat any as hypothetical.

**01 · Header collision.** Panel content starts at the safe-area inset (59pt), not
`Spacing.xxl` from the panel top. The chat's hamburger animates to `opacity 0`. The stat stops
reflowing because it stops being a sentence — `0 ACTIVE` is suppressed at zero, count alone is
the resting state.

**02 · Chrome hidden, not merely deafened.** `.allowsHitTesting(!sessionsOpen)` keeps its
**four** existing call sites and gains `.opacity(sessionsOpen ? 0 : 1)` on the same modifier
chain, animated at `Motion.standard`. Pixels and taps leave together. Hit-testing flips at the
*start* of the transition so nothing is tappable while still faintly visible. This is the only
fix that survives a 0.35 scrim on a light palette.

**03 · One search.** Delete the header chip. The single field filters as you type; the last
result row is always `SEARCH EVERYTHING FOR "…"`, the only route to `ConversationSearchScreen`.

**04 · Nav ≤50pt.** Four 40pt rows plus `hudPanel` chrome become one 44pt four-up rail —
icon over an 8pt mono label, 76pt each, hit target 76×44. Every destination stays one tap away.

**05 · Scroll edges.** Observed failure is worse than "sliced mid-row": the sixth card is cut
horizontally through the **cap-height of its own title**, keeping its top corner radius and
border, then stopping on a raw straight edge with the nav card's border starting on the same
pixel row. Fix is a 24pt (top) / 28pt (bottom) gradient from the drawer colour to clear, above
the list, **plus a bottom content inset equal to the dock** so the last row can always scroll
clear. The chrome carries a 1pt `Colors.divider` hairline **only while scrolled**. The same fade
language runs horizontally on truncated subtitles.

**06 · Footer holds a real hostname.** Observed: `OWENS-MAC-` / `MINI.LOCAL` — wrapped at the
hyphen, mid-token, across a 3-line footer. Fixed 52pt, two lines, never reflows. Line 1 is the
hostname at `mono(11)` / `Tracking.mono` with `lineLimit(1)`, `minimumScaleFactor(0.85)`,
**`.truncationMode(.middle)` and `.allowsTightening(false)`** — degradation must be
`OWENS-MAC-….LOCAL`, keeping machine and `.local` suffix. `lineLimit(1)` alone eats the suffix.
Line 2 is status. 24-char hostnames must fit without scaling.

---

## 2 · Layout and pt budget

Dock = 184pt of controls, 218pt including bottom safe area. Chrome 325, list 527, sum 852.
This table reconciles; hold to it, and if your build diverges, report the delta rather than
silently absorbing it.

| Component | 2b @ L | 2b @ XXL |
|---|---|---|
| Safe area, top | 59 | 59 |
| Header row (telemetry + ✕) | 40 | 40 |
| Gap above list | 8 | 8 |
| **LIST — scrolls** | **527** | **521** |
| Dock hairline + top pad | 12 | 12 |
| Dock · nav rail | 44 | 44 |
| Dock · two 10pt gaps | 20 | 20 |
| Dock · search + New | 48 | 54 |
| Footer hairline + pad | 8 | 8 |
| Host footer | 52 | 52 |
| Safe area, bottom | 34 | 34 |
| **TOTAL** | **852** | **852** |

Rows: 52pt with title + subtitle, 40pt title-only. Group headers 26pt, sticky, mono.
Bare rows on `Colors.divider` hairlines inset to the text leading — no card borders anywhere.
Current row = 3pt `Brand.accent` bar in a gutter every row reserves, title stepping to
`foregroundBright` at medium weight, timestamp moving from `dimForeground` to `Brand.accent`.
**Three signals, none of them lightness-of-fill** — `accentTint(.12)` is inside the drawer
gradient's own range on Deep Field and does not carry.

`NEW` takes a 1.5pt full-strength `Brand.accent` border and an `accentBright` label — **not** a
solid fill. Solid accent is the live-state signifier; a permanently-lit slab of it devalues the
current-session marker.

Panel stays **opaque on compact** (`Colors.drawerGradient` over `Colors.scrim`) and
**transparent on regular**. Do not move the drawer gradient down into the pane "for consistency" —
that is the one edit that would chop the iPad atmosphere.

---

## 3 · Empty-session filter — the new behaviour

**Root cause is OPEN_ITEMS #187:** `fetchSessionList` already requests `?min_messages=1` and the
gateway silently ignores it. Verified against the live gateway 2026-07-26. The client-side filter
is the decided answer (Owen, 2026-07-26).

No DTO work — `HermesSessionInfo` already carries `messageCount`, `preview`, `lastActive`,
`isActive`.

**Rule:** hide rows where `messageCount == 0`, with two exemptions:

- **The active session** (`isActive == true`). Without this, tapping NEW CHAT creates a
  zero-message session that is invisible in the shelf you just opened, and the current-row
  accent bar has nothing to mark. **This exemption is not optional.**
- **Any pinned session** (`ConversationListStateStore.isPinned`). An explicit user act outranks
  a heuristic.

**The header count must count what is visible, not what was fetched.** A header reading
`14 THREADS` above 9 rows is the same class of lie the filter exists to remove.

**Toggle — "Show empty sessions".** `UserSettings` bool, default OFF (filter active). Owen wants
it user-facing. If placing it in the Settings information architecture turns out to be more than
adding a row, **ship the filter without the toggle and report** — the filter is the requirement,
the toggle is the nice-to-have.

Do **not** drop the `min_messages=1` query param in this lane. It is harmless, and #187 owns
that decision.

---

## 4 · Dynamic Type

Rows grow, never reflow. Title and subtitle keep `lineLimit(1)` at every size and degrade
horizontally into the existing fade; a third line is never allowed. 52 → 62 and 40 → 45 —
growth is the line boxes only, the 14pt vertical padding is a spacing token and does not scale.
Group headers 26 → 30. Rail holds 44pt and drops its mono labels (icon 16 → 20). Search + New
48 → 54, with `NEW` collapsing to a 56pt icon-only pill so the field keeps 226pt.

**Footer holds at XXL** — 19 + 2 + 16 = 37pt in a 44pt usable box, 7pt spare.
**It gives at AX1**, not XXL: the stack reaches 45pt in a 44pt box. **Line 2 is what drops** —
status leaves the footer, the pip carries it via colour plus `accessibilityValue`, and the
hostname keeps the whole box on one line. The 52pt frame never moves; the dock is what the thumb
has memorised.

---

## 5 · Reduce Motion

The chrome cross-fade **stays**. Cross-fade is the substitution Reduce Motion asks *for*; the
setting targets travel, parallax and scale. What changes:

- **The panel stops travelling.** With `accessibilityReduceMotion`, the leading-edge slide is
  replaced by an in-place cross-fade at the same duration on both channels, so the chat does not
  disappear before the panel arrives.
- **Interactive drag is exempt.** A finger on the peek strip still moves the panel 1:1 — direct
  manipulation, not animation. Only the release settle drops to opacity.
- **Scroll-edge fades, the current-row bar and the NEW glow are unaffected** — static, not
  transitions.

---

## 6 · VoiceOver

2b deliberately breaks reading-order = visual-order, and should: the dock is at the bottom
because that is where a thumb is, and VoiceOver does not have a thumb. Set traversal explicitly
with `.accessibilitySortPriority` inside an `.accessibilityElement(children: .contain)` panel:

`1` header (`.isHeader`) → `2` search → `3` New chat → `4` list (headers + rows, visual order)
→ `5` rail → `6` host/settings → `7` close, **last**.

- `.accessibilityAction(.escape)` on the panel so two-finger scrub dismisses from anywhere.
- Rail labels live on the Button and always read the full word — "Scheduled tasks", not "TASKS".
  The visible mono caption is `.accessibilityHidden(true)` at every size, so dropping it at XXL
  changes nothing VoiceOver hears.
- Rows are one element each. Current-row is a **trait**, not a shape. Empty rows (when shown via
  the toggle) read "Untitled, no messages, 1:41" and expose Pin / Archive as custom actions.

---

## 7 · iPad — one property, not a second layout

`ConversationListPane` gains `actionAnchor: .bottom | .top`, defaulted from
`horizontalSizeClass`. The same VStack emits the same elements in the other order — 2b **becomes**
2a at regular width. That is the entire iPad delta.

The bottom bar renders correctly in a column (it inherits the window's bottom safe area), but is
ergonomically wrong there — hence the flip. Scroll-edge fades stay in the column. ⌘K keeps its
existing `requestSearchFieldFocus()` path and reveals the column when hidden; Esc has nothing to
dismiss and goes quiet. The ✕ becomes the sidebar toggle.

---

## Verification

Full suite on pinned sim `47F68496-24F9-45D9-93D3-1C778DB6B557`, `CODE_SIGNING_ALLOWED=NO`.
Report against **1121 / 103 + 8 UI** and account for the delta. `xcodegen generate` **only** if
Swift files are added or removed — if run, verify `aps-environment: development` survived and
commit the regen separately.

New tests owed: the filter's two exemptions (active session visible at zero messages; pinned
session visible at zero messages), and the header count reflecting visible rows.

**Device verification is Owen's and is owed, not done:** the scroll edge under the dock mid-scroll;
the footer against the real `OWENS-MAC-MINI.LOCAL`; XXL and AX1; VoiceOver traversal order; iPad
regular width including the atmosphere spanning both columns.

## Commit discipline

File-scoped commits. OPEN_ITEMS.md separate from code — **do not mix OPEN_ITEMS edits into
feature commits.** `gh pr merge --merge`, never squash.

## Out of scope

- **The empty-sweep cleanup banner.** Designed across turns 2–3 (`EmptySweepDismissal`,
  hide-here vs archive-all). The client-side filter makes it unnecessary for empties. **Do not
  build it.** The dismissal machinery is a candidate for the untitled-but-not-empty population
  in a later lane.
- **Host-side archive or delete.** `/api/sessions/{id}` answers `Allow: DELETE,GET,PATCH`, but
  nothing here calls them. Archive stays a device-local overlay.
- The gateway-side half of #187.
- 2a and 2c as standalone layouts. Push-and-scale (1c) is dead.
