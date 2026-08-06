# F1 — Artifact panes v2: design proposal for Owen

**Status: PROPOSAL, awaiting Owen's approval.** Written 2026-08-06 while
Owen is in meetings, to replace a seven-question brainstorm with one
read. Every question from the terrain map (`G-preview-panes-terrain.md`)
has a recommendation; say "yes" or name the ones you'd change.

## The honest framing first

**Your idea already half-exists.** #21 (SSE file reconstruction) and #99
(in-app preview sheet) shipped 2026-07-12: agent-written files already
arrive as tappable chips that open a sheet rendering Markdown, code with
syntax highlighting, and HTML in a hardened WKWebView sandbox. So this
lane is not "build preview panes" — it is **"close the four gaps that
keep it from feeling like the desktop's artifact panel."** That's a
smaller, sharper lane than the feature menu implied, and worth saying
out loud before we scope it.

## The four gaps, and what I'd do about each

### 1. It isn't actually live mid-turn — FIX (the headline)
Today the file chip appears only at `run.completed`, because attachments
are assigned to the message in one shot at the end
(`SessionsHermesClient.swift:442-447`), even though the bytes stream in
during the turn (`:321-373`). The tool pill shows immediately; the thing
you can *open* does not.

**Recommendation: fix it.** This is the difference between "a file
appeared after the answer" and "watch the artifact take shape" — the one
place we can beat the desktop, since we already hold the content client-
side. Cost is real but contained: attachments become append-as-you-go
instead of assign-once, which touches streaming state we hardened in
#235/#237, so it needs care and tests, not just a move.

### 2. SVG (and mermaid) render as "unsupported" — FIX
`FilePreviewRoute` handles `.html/.markdown/.code/.unsupported`;
**`.svg` falls through to unsupported** even though the feature menu
named SVG/mermaid diagrams as the differentiator. Both are trivially
renderable in the WKWebView sandbox that already exists (SVG directly;
mermaid needs a bundled JS renderer, which is a bigger call).

**Recommendation: add `.svg` now; mermaid as a follow-on.** SVG is a
few lines through the existing hardened path. Mermaid means bundling a
JS library into the app and letting it execute in the sandbox — a real
supply-chain and review question I don't want to sneak into a polish
lane.

### 3. No revision history — DEFER
Successive `write_file`s to the same path currently append separate
attachments; there's no "v1 → v2 → v3" chain or diff. The feature menu
called this free; it isn't — it needs a data-model change (attachments
keyed by path with an ordered history) plus UI.

**Recommendation: defer.** It's the least-used capability of the four
and the most invasive. Revisit once you've lived with mid-turn rendering
for a week and know whether you actually want it.

### 4. No cross-session gallery — DEFER
"Show me everything Hermes has written for me" needs an index across
conversations; today artifacts are reachable only through the message
that produced them.

**Recommendation: defer to a separate small lane** after this one — it's
genuinely useful but it's a browse feature, not a preview feature, and
it wants the #21 Tier 2 (real file delivery) story settled first, which
is Phase 3's MEDIA pipeline.

## The other three questions, answered

- **Quick Look (`QLPreviewController`) for PDFs and friends?** Not now.
  It only pays off once real binary files arrive over the wire (Phase 3
  media), and today's `ShareLink` already covers "get it out of the app."
- **Widget / Live Activity "artifact just landed"?** No. The app group
  exists but the artifact path doesn't use it, and this is decoration on
  a feature you haven't lived with yet.
- **Naming/scope honesty:** the tracker entry should say "artifact panes
  v2 (iteration on #21/#99)", not imply a new subsystem.

## So the proposed lane is exactly two things

1. **Mid-turn artifact rendering** — the chip and its preview appear and
   update while the turn is still streaming.
2. **SVG route** — diagrams render instead of reading "unsupported."

Plus the honest tracker naming. Everything else deferred with a reason.
That's an **S-to-M lane**, one gate, one OTA — not the multi-week thing
"artifact preview panes" sounds like.

## Bars I'd pre-register (before any code, per the standing rule)

- **F1-A:** during a live turn where the agent writes a Markdown file,
  the file chip appears BEFORE `run.completed` and opens to the current
  content; no duplicate chip after completion.
- **F1-B:** an agent-written `.svg` opens and renders as an image (not
  "unsupported"); malformed SVG degrades to the code view, never a blank
  pane or a crash.
- **F1-C:** no regression in the #235/#237 streaming machinery — the
  existing recovery, dedupe and stall tests stay green unmodified.
- **F1-D:** gate PASS (units + XCUITest + Release), unit count moved by
  the new tests.
- **F1-E (device, Owen):** ask Hermes to write something on a real turn
  — the artifact shows up while it's still talking, and an SVG diagram
  renders.

## What I need from you

Just: **"approved"**, or which recommendations to flip (most likely
candidates: promote mermaid into scope, or pull the gallery forward).
Nothing gets built before you answer.
