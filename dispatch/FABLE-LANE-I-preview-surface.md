# FABLE LANE I — In-app preview surface for agent files (#99)

**OPEN_ITEMS:** #99 (interactive artifact / in-app preview)
**Branch prefix:** `claude/t27-lane-i-`
**Supersedes** the "queued behind PR #65" gate — Lane D is MERGED (#106), so
this spec is written ON TOP of the landed IR, not around it.

## Objective

Both ChatGPT iOS and Claude iOS render generated HTML/interactive content
in-app; Talaria reconstructs agent-written files into a ShareLink bubble only.
Add an in-app preview surface: tap an agent-file bubble → full-screen preview
sheet. v1 scope is single-file HTML (WKWebView) plus text/code files (reusing
the shipped #92 renderer); everything else keeps the ShareLink-only behavior.

## Grounding — read these BEFORE designing (probe-first rule)

- `Talaria/Features/Chat/MessageBubble.swift` — where the agent-file bubble +
  ShareLink live today (#21 Tier 1 reconstruction). The preview entry point
  hangs off this bubble; the ShareLink stays (preview AND share, not either/or).
- `Talaria/Features/Chat/MarkdownContentView.swift` + the #92 code
  highlighter — reuse for text/code file preview; do not build a second one.
- `Talaria/Services/Live/GenerativeUI/` (GenUISchema, GenUIDecoder + renderer,
  merged in #106) — REFERENCE ONLY in this lane; no edits. But design the
  preview sheet's container so a future P8 rung can present a rendered IR
  surface in the same chrome (title bar, dismiss, share) without rework —
  i.e., the sheet takes "a content view + a title," not "an HTML string."

## Deliverables

### 1. Preview sheet (new files)
- `FilePreviewSheet` presented from the agent-file bubble: title bar (file
  name), dismiss, and the existing ShareLink relocated into the sheet's
  toolbar. Content slot is a generic `some View` per the grounding note.
- Routing by file type: `.html`/`.htm` → WKWebView; text/code/markdown →
  the #92 rendering stack; anything else → a "no in-app preview" card with
  the ShareLink (honest placeholder, never a blank sheet).

### 2. HTML preview (WKWebView) — SANDBOXED
- Load via `loadHTMLString(_:baseURL: nil)` from the reconstructed file
  content. No file-URL loading, no read access grants.
- `WKWebViewConfiguration` hardening: no JS-to-app bridges (`no
  WKScriptMessageHandler`), block navigation away from the initial content
  (`decidePolicyFor` → cancel non-initial navigations; external links open
  via `UIApplication.open` prompt or are simply cancelled — pick one, state
  it in the PR), and disable `allowsLinkPreview`. Agent HTML is
  model-generated content rendering inside the owner's app — treat it like
  untrusted web content anyway; the cost is near-zero.
- Inline JS within the single file MAY run (that is the point of interactive
  artifacts) — the sandbox is about egress and app-bridge surface, not about
  disabling the artifact.

### 3. Tests
- Swift Testing: file-type routing (html/text/code/other), preview-content
  plumbing from a reconstructed-file fixture, and the navigation-policy
  delegate (initial load allowed, subsequent navigation cancelled).
  WKWebView rendering itself is not unit-testable — the policy delegate is.

## Hard constraints

- MessageBubble.swift edits: MINIMAL — the tap affordance + sheet
  presentation only. No transcript-layout changes, no ChatScreen.swift
  contact, no composer contact.
- GenerativeUI/ files: read, don't touch (P8 model wiring is a separate
  future lane; this lane only shapes the sheet so IR can slot in later).
- OUT OF SCOPE (state in PR if tempted): in-app code EXECUTION, multi-file
  artifacts, editing, the #100 charts work, any Hermes/relay changes.
- New Swift files ⇒ PR notes the Mac side runs `xcodegen generate` +
  re-verifies `aps-environment` survives.
- File-scoped commits; no `OPEN_ITEMS.md` edits; no pbxproj in feature
  commits.
- Cloud can't build: check every WKWebView/WKNavigationDelegate API you use
  against the iOS 27 SDK availability, and remember the review loop just
  caught an NSNumber `as? Bool` bridging bug (#106) — be suspicious of
  Foundation bridging shortcuts.

## Acceptance

- Tapping an agent-file HTML bubble opens the sheet and renders the page;
  inline JS in the artifact runs; tapping an external link does NOT navigate
  the preview anywhere.
- A text/code agent file previews through the #92 stack with highlighting.
- An unsupported type shows the honest no-preview card with a working
  ShareLink; ShareLink works from the sheet toolbar for all types.
- All `@Test` suites green (Swift Testing ✔ line). PR titled
  `Lane I — in-app preview surface for agent files (#99)`.
