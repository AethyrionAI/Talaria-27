# G — Artifact preview panes: terrain map (pre-brainstorm exploration, 2026-08-06)

**Headline: the feature is already substantially built.** #21 (SSE
reconstruction) and #99 (in-app preview sheet) shipped 2026-07-12
(FilePreviewSheet.swift / HTMLPreviewView.swift, commits 6917979 /
57bba54). The approved F1 lane is a V2 — closing gaps — not greenfield.

## 1. SSE write_file surface today
- Parsing: SessionsHermesClient.swift `parseWrittenFile` (:1343-1361),
  tolerant envelope (args/arguments/input · path/file_path ·
  content/text), recognizes write_file/create_file. Content present →
  MessageAttachment.agentFile (Tier 1, Message.swift:246-259, bytes
  staged to App Support/Talaria/Attachments); absent →
  fetchableAgentFile (Tier 2 whitelist, :1369-1404).
- **GAP — not actually mid-turn:** producedFiles accumulates during
  streaming (:321-373) but attaches only at run.completed (:442-447).
  The tool pill is live; the tappable preview chip is end-of-turn.
- ToolActivity stores label+detail only, never bytes. No revision
  chain — each write_file on the same path appends a new attachment.

## 2. Transcript/render stack
- Custom markdown renderer, no third-party dep
  (MarkdownContentView.swift; segments incl. codeBlock → CodeBlockView).
- Tool pills: ToolActivityRail.swift, anchored inline.
- Detail-pattern precedents: InboxItemRow → BriefingDetailScreen; chat's
  own agentFileBubble → .sheet → AgentFilePreviewSheet
  (MessageBubble.swift:706-769).

## 3. Preview-adjacent machinery
- WKWebView: exactly one use — HTMLPreviewView.swift, hardened sandbox
  (loadHTMLString baseURL nil, ephemeral store, one-shot nav policy, no
  JS bridge, no popups). Its :4-18 comment is the de facto security
  spec for any new preview surface.
- CodeSyntaxHighlighter.swift: dependency-free, many languages.
- FilePreviewRoute (FilePreviewSheet.swift:21-56): .html/.markdown/
  .code/.unsupported — **.svg falls to .unsupported** (F1's named
  differentiator, unrouted). No QLPreviewController anywhere.
- Features/GenerativeUI is an UNRELATED DEBUG-only IR renderer (P8
  rung) — do not conflate.
- Tests exist: TalariaTests/FilePreviewTests.swift (159 lines).

## 4. Persistence
- Artifact bytes: plain files, App Support/Talaria/Attachments,
  UUID-prefixed, referenced by localStoragePath. Not SwiftData.
- Transcript metadata: SwiftDataLocalSessionStore — Conversation as an
  encoded blob (deliberate, :6-14). **mainContext trap avoided at
  :97-108 (private ModelContext)** — any new SwiftData surface must
  copy that pattern.
- App group exists (group.org.aethyrion.talaria) but the artifact path
  doesn't use it; the session store opts out (groupContainer: .none).

## 5. Constraints
- ATS: single 100.64.0.0/10 exception; today's HTML preview never
  network-loads (loadHTMLString only) — keep it that way or scope a new
  exception deliberately.
- Any new screen uses Design.swift tokens + hudPanel (Arc-Reactor HUD).

## Design questions for the brainstorm (Owen)
1. Close the mid-turn gap (attach as events stream) — worth the
   mutating-attachment state cost?
2. Add SVG route (+ mermaid via the sandboxed WKWebView)?
3. Revision chain across successive writes to one path — now or defer?
   (Needs a data-model change.)
4. Cross-session artifacts gallery in v1, or per-message preview only?
5. Quick Look for richer types (PDF) once real-file delivery lands
   (Phase 3 MEDIA), vs today's ShareLink?
6. Widget/Live Activity "artifact just landed" surface — app group is
   ready but unused for this?
7. Naming/scope honesty: this is an ITERATION on shipped #21/#99.

**Size:** the E-menu's v1 ("render MD/code/HTML with a preview pane")
already EXISTS (S = shipped). The real v2 (mid-turn + SVG/mermaid +
revision chain) is **M**.
