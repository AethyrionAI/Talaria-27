# 429 — Markdown Images Load Only When You Tap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Markdown image in a reply, a streaming transcript, a Markdown file preview or a briefing causes ZERO network requests until the user taps it. Today `MarkdownParser.swift:135` accepts any `http(s)` URL from `![]()` (`:63`) or `<img src>` (`:65`) as an `.image` segment, and `MarkdownContentView.swift:164` puts `AsyncImage(url:)` INSIDE the button's label — so the fetch happens at render and the button only enlarges; a second unguarded `AsyncImage` sits in `ImageViewerScreen` (`:322`). ATS permits arbitrary HTTPS (`project.yml:391-394` — the only exception is the tailnet CIDR for insecure HTTP), and the HTML artifact sandbox's egress block (`HTMLPreviewView.swift:79-96`) does not cover this plane. Owen's ruling (2026-09-04): **TAP TO LOAD** — a placeholder naming the host, nothing fetched until tapped, zero requests by default, no allowlist.

**Architecture:** One component, `RemoteImageView`, becomes the ONLY place in the shipping tree that constructs `AsyncImage`; both former sites (`inlineImageView`, `ImageViewerScreen`) render through it. It consults a per-launch, in-memory `RemoteImageConsent` (a `Set` of absolute URL strings behind an `EnvironmentKey` with a shared default) — unapproved → a placeholder button whose tap APPROVES; approved → today's `AsyncImage` with its phases, whose tap opens the fullscreen viewer as before. Approval is keyed by URL, never by segment id, because `MarkdownSegment.image`'s id is minted per parse (`MarkdownParser.swift:8`, `id: UUID = UUID()`) and a streaming transcript re-parses on every delta. The parser is untouched; `MarkdownInterleavingTests`' segment pins stay. The bar is a hosted render of the real view with a counting `URLProtocol`: zero requests before approval, exactly the request you approved after — with a live control arm, the `HTMLArtifactSandboxTests` standard.

**Tech Stack:** SwiftUI (`AsyncImage`, `UIHostingController` in the app test host) / Foundation `URLProtocol` counting stub / Swift Testing / `RepoSourceWitness` + `NamingSweepTests.shippingSources()`'s enumerator for the structural pins / `scripts/mac/lane-gate.sh`.

**Why this is the shape:** the audit's recommendation is *"require an explicit external-image decision or a narrowly defined trusted-origin policy … test that unapproved Markdown image URLs produce zero network requests … extend the privacy model to every rendering path."* Owen chose the explicit decision, per image, per tap. It needs no allowlist to maintain, no setting to explain, and it makes the privacy sentence (#433) true in one clause: *external images load only when you tap them.* The realistic vector is indirect — a self-hosted agent that read hostile content, or a compromised host — and the leak is bounded to the URL bytes plus IP/User-Agent; tap-to-load closes it at the only point a human is in the loop. The HTML sandbox keeps blocking everything; this plane gets consent instead of a blocker because an image the user WANTS to see is the common case there.

## Global Constraints

- **Zero requests by default, on EVERY render site.** `AsyncImage(` may appear in exactly one shipping file (`RemoteImageView.swift`); the parser's `.image` segment shape is unchanged; user-authored bubbles follow the same rule (decision 3).
- **Consent is per launch, in memory, keyed by absolute URL (decision 2).** Never persisted; never a setting; never an allowlist. The same URL approved in one bubble is approved in another for the life of the process — a re-parse, a scroll-off/scroll-on, a fullscreen open must not re-ask.
- **The placeholder names the HOST and shows the alt text; the copy is Talaria's** (CLAUDE.md naming: no "Hermes" on a phone-facing surface). Accessibility label carries the same words (#371-E's rule).
- **Live control arm or it is not a bar** (`HTMLArtifactSandboxTests`' standard): the counting harness must be shown to see a request when one is allowed, or a zero proves only that the harness is blind.
- **`HTMLPreviewView`'s egress block is untouched** — a different plane with a different (stricter) rule; #259's tests stay green.
- **Redirects and private-network destinations** (the audit's aside): consent is to the URL as written; `AsyncImage` follows redirects and offers no delegate. Recorded as an accepted residual in the RESULT block, not silently.
- **`docs/` publishes on merge.** If decision 5 puts the privacy sentence in this lane, the PR is HELD for Owen's read of the exact sentence (the #390-F / 422-N precedent).
- **Gate + merge protocol:** worktree isolation; RED-first with the mutation named per bar; `xcodegen generate` after adding files; `TALARIA_SIM_NAME=CC-lane-N scripts/mac/lane-gate.sh`, ≤ 3 booted, kill only your recorded PID; positive `GATE: PASS`; merge on green; RESULT block in entry 429.
- **Plan-authored code is unreviewed code.** Task 0 measures the one premise the render bar rests on — that a hosted `MarkdownContentView` in the test host issues `AsyncImage`'s request through a registered `URLProtocol` — before the bar is pinned. If it does not, design B (below) is the fallback and the entry says so.

## Decisions for Owen (one AskUserQuestion round — recommended arm first)

1. **Tap to load (recommended — your 09-04 ruling):** placeholder naming the host; nothing fetched until tapped; no allowlist. Alternative: trusted origins (configured hosts + the tailnet range load automatically, everything else tap-to-load). Alternative: block entirely (placeholder only, never loads; the URL is shown and copyable).
2. **Approval lasts for the LAUNCH, keyed by URL (recommended):** tap once, that image stays loaded everywhere it appears until the app relaunches; nothing written to disk. Alternative: per tap only (scrolling away and back re-asks). Alternative: persisted per message (a `Message` field; survives relaunch — the #42 decode rule applies).
3. **User-authored bubbles follow the same rule (recommended):** one rule, no exception to reason about. Alternative: images in YOUR OWN messages load immediately (you typed the URL).
4. **Placeholder copy (recommended):** `IMAGE · example.com` on the first line in the mono label style, `Tap to load` beneath, the alt text as a third line when present; accessibility label `Image from example.com, not loaded. Tap to load.` Alternative: `Image from example.com — tap to load` in body type.
5. **The privacy sentence ships WITH this lane (recommended):** `docs/privacy.html`'s third-party list gains `Any website an image in a reply points to — only when you tap that image to load it.` — Owen reads the exact sentence; the PR holds for it. Alternative: hand the sentence to #433 and keep this lane code-only.

## Session contract

1. Read `OPEN_ITEMS.md` entry 429 (the audit's A4 evidence and Owen's default), entry 433 (the privacy page), `OPEN_ITEMS-ARCHIVE.md` #259 (the HTML egress block — the standard for a network bar), #371 (accessibility labels). Pre-register bars 429-A..GATE in entry 429 BEFORE Task 0.
2. Task 0 first, alone (the hosted-render probe; ~1 hour). Its answer chooses design A or B below and pins 429-B's exact assertion.
3. One worktree lane (Opus): Tasks 1–4, RED-first, mutations named, gate; PR HELD if decision 5 = here; merge on green + Owen's read; RESULT block. Fable only for a falsified bar.
4. Device: one §01 runbook eyeball card (the placeholder's look on Deep Field and Paper Tape; tap loads; fullscreen opens) — not a bar; the render test is the evidence.

## Two designs, chosen by Task 0

- **Design A (preferred if the probe sees the request):** keep `AsyncImage`; gate it behind consent inside `RemoteImageView`. The render bar counts real `URLSession.shared` requests.
- **Design B (fallback if the probe reads zero on the control arm):** `RemoteImageView` owns the load through an injectable `RemoteImageLoading` (`URLSession.shared.data(from:)` → `Image(uiImage:)` by default); the render bar counts calls on the injected loader; a structural pin bans `AsyncImage(` from shipping sources entirely. Same UI, same consent, different instrument.

## File structure

**Create:**
- `Talaria/Features/Chat/RemoteImageConsent.swift` — `@MainActor @Observable final class RemoteImageConsent` (`approve(_:)`, `isApproved(_:)`, keyed by `url.absoluteString`), the `EnvironmentKey`/`EnvironmentValues.remoteImageConsent` with `RemoteImageConsent.shared` as its default, and `enum RemoteImagePolicy` (pure: `host(of:)`, `placeholderTitle(host:)`, `placeholderAccessibilityLabel(host:)`).
- `Talaria/Features/Chat/RemoteImageView.swift` — the ONE `AsyncImage` site (design A) or the loader-owning view (design B); `init(url:altText:mode:onOpen:)` with `mode: .inline` (260×200 fit, rounded) / `.fullscreen` (fit, ignores safe area).
- `TalariaTests/RemoteImageConsentTests.swift` — bar 429-A.
- `TalariaTests/RemoteImageRenderTests.swift` — bars 429-B and 429-D (hosted render + counting `URLProtocol`).
- `TalariaTests/RemoteImageSitePinsTests.swift` — bars 429-C and 429-E (structural + copy).
- `TalariaTests/RemoteImageProbeTests.swift` — Task 0 (TEMPORARY; deleted at the end of the lane).

**Modify:**
- `Talaria/Features/Chat/MarkdownContentView.swift` — `:160-200` `inlineImageView` → `RemoteImageView(url:altText:mode: .inline, onOpen: { fullscreenSegment = segment })`; `:312-340` `ImageViewerScreen` → `RemoteImageView(url:altText:mode: .fullscreen)` (its save-to-Photos and dismiss chrome unchanged).
- `docs/privacy.html:130-133` — decision 5.
- `TalariaTests/NamingSweepTests.swift` — the new literals are Talaria-safe (no change expected; the sweep's enumerator is reused by 429-C).

**Interfaces (the names every task uses):**

```swift
@MainActor @Observable
final class RemoteImageConsent {
    static let shared = RemoteImageConsent()
    private(set) var approved: Set<String> = []          // absolute URL strings, per launch, never persisted
    func approve(_ url: URL) { approved.insert(url.absoluteString) }
    func isApproved(_ url: URL) -> Bool { approved.contains(url.absoluteString) }
}

extension EnvironmentValues { @Entry var remoteImageConsent: RemoteImageConsent = .shared }

enum RemoteImagePolicy {
    static func host(of url: URL) -> String { url.host ?? url.absoluteString }
    static func placeholderTitle(host: String) -> String { "IMAGE · \(host)" }
    static let placeholderAction = "Tap to load"
    static func placeholderAccessibilityLabel(host: String) -> String { "Image from \(host), not loaded. Tap to load." }
}

struct RemoteImageView: View {
    enum Mode { case inline, fullscreen }
    let url: URL
    let altText: String
    let mode: Mode
    var onOpen: (() -> Void)? = nil
    @Environment(\.remoteImageConsent) private var consent
    // body: consent.isApproved(url) ? loadedImage (AsyncImage phases, tap → onOpen) : placeholder (tap → consent.approve(url))
}
```

## Bars (paste into entry 429 as a dated block BEFORE Task 0)

- **429-A — consent semantics (unit, pure).** A fresh `RemoteImageConsent` approves nothing; `approve(u)` → `isApproved(u)`; a different URL stays unapproved; two `.image` segments minted from two parses of the same markdown carry DIFFERENT ids and the SAME URL, and approval keyed by URL covers both (the streaming re-parse premise, pinned). `RemoteImagePolicy.host(of:)` on `https://images.example/pixel.png?x=1` is `images.example`; the title/label copy is byte-pinned. Mutation: key approval on the segment id → the two-parse test reds.
- **429-B — zero requests before consent, the request after (hosted render, counting `URLProtocol`, live control).** Register `CountingURLProtocol` (counts every `startLoading`, answers 404 immediately); host `MarkdownContentView(content: "![chart](https://images.example/pixel.png)", isStreaming: false)` with a FRESH `RemoteImageConsent` injected via `.environment(\.remoteImageConsent, consent)` in a `UIHostingController` inside a key `UIWindow`; pump the run loop 1.0 s → `count == 0`. Then `consent.approve(url)`, pump 1.0 s → `count ≥ 1` and every counted request's URL is exactly `https://images.example/pixel.png`. **The control arm is the same harness on the UNMODIFIED tree** (Task 0 records its count — that number is the RED). Mutation: remove the `isApproved` gate in `RemoteImageView` → the pre-consent count is ≥ 1 → RED.
- **429-C — every render site, structurally.** Over `NamingSweepTests.shippingSources()`'s enumerator: `AsyncImage(` occurs in exactly one file, `RemoteImageView.swift` (design A) or zero files (design B); `MarkdownContentView.swift` contains `RemoteImageView(` at least twice (inline + viewer) and `AsyncImage(` zero times; `MessageBubble.swift`, `FilePreviewSheet.swift`, `BriefingDetailScreen.swift` contain `AsyncImage(` zero times (they render through `MarkdownContentView` — pinned so a future direct `AsyncImage` there reds). Mutation: add a stray `AsyncImage(` to a scratch shipping file → RED; remove it.
- **429-D — the streaming transcript (hosted render).** `MarkdownContentView(content:isStreaming: true)` with the image, re-rendered with three growing `content` values (the delta re-parse) → `count == 0` throughout; approve → the image loads on the next render; the placeholder does not return on a fourth delta (consent survived the re-parse). Mutation: as 429-A's.
- **429-E — copy and accessibility.** The placeholder's visible strings are `IMAGE · images.example` and `Tap to load` plus the alt text when non-empty; `accessibilityLabel` is `Image from images.example, not loaded. Tap to load.`; no `Hermes` token in either file (the naming sweep's rule). Pinned on the pure policy + a source read of `RemoteImageView.swift` for the `.accessibilityLabel(` call.
- **429-P — the privacy sentence (decision 5).** `docs/privacy.html` contains `only when you tap that image to load it` (exact wording Owen approves); the "third parties, exhaustively" list names arbitrary image hosts. Held for Owen's read.
- **429-GATE** — positive `GATE: PASS`; the `MarkdownInterleavingTests` pins at `:29,49` byte-untouched and green; count moved by exactly this lane's tests.

## Task 0: Does the harness see the request? (no production code; ~1 hour)

**Files:** `TalariaTests/RemoteImageProbeTests.swift` (temporary).

- [ ] **Step 1 — the counting protocol:**

```swift
final class CountingURLProtocol: URLProtocol, @unchecked Sendable {
    static let hits = OSAllocatedUnfairLock<[URL]>(initialState: [])
    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme?.hasPrefix("http") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let url = request.url { Self.hits.withLock { $0.append(url) } }
        let response = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
```

- [ ] **Step 2 — the hosted render on the CURRENT tree:** `URLProtocol.registerClass(CountingURLProtocol.self)`; `let host = UIHostingController(rootView: MarkdownContentView(content: "![chart](https://images.example/pixel.png)", isStreaming: false))`; `let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844)); window.rootViewController = host; window.makeKeyAndVisible(); host.view.layoutIfNeeded()`; pump `RunLoop.main.run(until: .now + 1.0)` (or `try await Task.sleep` + `await Task.yield()` on the main actor — record which form actually lets `AsyncImage` start); print `CountingURLProtocol.hits`.
- [ ] **Step 3 — read the number.** `≥ 1` with the exact URL ⇒ **design A**, and this number IS 429-B's RED (record it verbatim). `0` ⇒ try once more with `window.rootViewController?.view.setNeedsLayout()` + a 2 s pump and `URLCache.shared.removeAllCachedResponses()` first; still `0` ⇒ **design B** (`AsyncImage` does not route through a registered protocol in this host, or does not start without a display link) — file the finding and switch 429-B's instrument to the injected loader.
- [ ] **Step 4 — file** the probe output in entry 429 as `429-T0`; pin 429-B's assertion; delete the probe file before the PR.

## Task 1: Consent + policy (bar 429-A)

**Files:** create `RemoteImageConsent.swift`, `TalariaTests/RemoteImageConsentTests.swift`.

- [ ] **Step 1 — RED tests:**

```swift
@Suite("429-A remote image consent")
@MainActor
struct RemoteImageConsentTests {
    @Test func approvalIsKeyedByURLNotBySegmentIdentity() throws {
        let markdown = "![chart](https://images.example/pixel.png)"
        let first = try #require(parseMarkdownSegments(markdown).first { if case .image = $0 { return true }; return false })
        let second = try #require(parseMarkdownSegments(markdown).first { if case .image = $0 { return true }; return false })
        #expect(first.id != second.id, "the premise: a re-parse mints a new segment id")
        guard case .image(_, let url, _) = first else { return }
        let consent = RemoteImageConsent()
        #expect(!consent.isApproved(url))
        consent.approve(url)
        #expect(consent.isApproved(url))
        guard case .image(_, let url2, _) = second else { return }
        #expect(consent.isApproved(url2), "same URL from a later parse must still be approved")
        #expect(!consent.isApproved(URL(string: "https://images.example/other.png")!))
    }
    @Test func thePolicyCopyIsPinned() {
        let host = RemoteImagePolicy.host(of: URL(string: "https://images.example/pixel.png?x=1")!)
        #expect(host == "images.example")
        #expect(RemoteImagePolicy.placeholderTitle(host: host) == "IMAGE · images.example")
        #expect(RemoteImagePolicy.placeholderAction == "Tap to load")
        #expect(RemoteImagePolicy.placeholderAccessibilityLabel(host: host) == "Image from images.example, not loaded. Tap to load.")
    }
}
```

- [ ] **Step 2 — RED (compile).** **Step 3 — implement** the interface block. **Step 4 — GREEN + mutation** (key on the id → RED). **Commit:** `429-A: RemoteImageConsent — per-launch, keyed by URL (a re-parse mints new ids); the placeholder copy pinned`.

## Task 2: `RemoteImageView` and the two sites (bars 429-B, 429-C, 429-D, 429-E)

**Files:** create `RemoteImageView.swift`; modify `MarkdownContentView.swift:160-200, 312-340`; create `RemoteImageRenderTests.swift`, `RemoteImageSitePinsTests.swift`.

- [ ] **Step 1 — RED tests:** 429-B (the Task 0 harness with a fresh consent injected via `.environment(\.remoteImageConsent, consent)`: `count == 0` after 1 s; `consent.approve(url)`; `count ≥ 1` after 1 s, all hits equal to the URL); 429-D (three growing streaming contents, then approve, then a fourth); 429-C (the enumerator over shipping sources — counts of `AsyncImage(` per file as specified); 429-E (a source read of `RemoteImageView.swift` contains `.accessibilityLabel(` and `RemoteImagePolicy.placeholderAccessibilityLabel(`; neither new file contains `Hermes`).
- [ ] **Step 2 — RED:** 429-B's pre-consent count is Task 0's number (≥ 1); 429-C fails on `MarkdownContentView.swift` still containing `AsyncImage(` twice.
- [ ] **Step 3 — implement:** `RemoteImageView` — unapproved: a `Button { consent.approve(url) }` whose label is a `VStack` of `MonoLabel(RemoteImagePolicy.placeholderTitle(host:))`, `Text(RemoteImagePolicy.placeholderAction)` in `Design.Typography.caption`, and the alt text when non-empty, on `Design.Colors.surface` with `Design.CornerRadius.md`, `.accessibilityLabel(RemoteImagePolicy.placeholderAccessibilityLabel(host:))`, `.buttonStyle(.plain)`; approved: today's `AsyncImage` phases moved verbatim from `:164-200` (inline) / `:322-340` (fullscreen) with the tap calling `onOpen` in `.inline` mode. Rewire the two sites; `ImageViewerScreen` keeps its chrome and passes `.fullscreen`.
- [ ] **Step 4 — GREEN + mutations:** remove the `isApproved` gate → 429-B/D red; add a stray `AsyncImage(` to a scratch shipping file → 429-C red (remove it). Run `MarkdownInterleavingTests` untouched and green. **Commit:** `429-B/C/D/E: RemoteImageView — the one AsyncImage site, gated by consent on every render path; zero requests before the tap (RED witnessed at N)`.

## Task 3: The privacy sentence (bar 429-P, decision 5)

- [ ] **Step 1 — RED:** a test in `RemoteImageSitePinsTests` reads `docs/privacy.html` via `RepoSourceWitness.source("docs/privacy.html")` and requires `only when you tap that image to load it`.
- [ ] **Step 2 — the sentence** in the "Third parties, exhaustively" list (`:130-133`): `<li><strong>Any website an image in a reply points to</strong> — only when you tap that image to load it. Nothing is fetched until you do.</li>`. **⚠️ `docs/` is the live Pages root: merging publishes. Owen reads the exact sentence; the PR HOLDS for his go.**
- [ ] **Step 3 — GREEN. Commit:** `429-P: the privacy page names image hosts and the tap-to-load rule (held for Owen's read)`.

## Task 4: Gate, PR, RESULT block, runbook card, close-out

- [ ] `xcodegen generate`; delete `RemoteImageProbeTests.swift`; `TALARIA_SIM_NAME=CC-lane-N scripts/mac/lane-gate.sh` (background, PID-poll); positive `GATE: PASS`; count moved by exactly this lane's tests.
- [ ] PR (HELD for the privacy sentence if decision 5 = here); merge on green + Owen's read; RESULT block in entry 429: bars A–E met with RED + mutation outputs, Task 0's count, the design chosen (A/B) and why, the accepted residuals (redirects; the viewer's second fetch is the same approved URL).
- [ ] **Close-out rule (same commit):** entry 433's third-party clause gets a dated line (*the image-origin omission is closed by #429's sentence — or handed over, per decision 5*); the `MarkdownContentView` doc comment (`:3-7`, *"tappable async-loaded previews"*) is rewritten to say tap-to-load; the #259 archive block gets an append-only dated pointer that the Markdown plane now has its consent gate (a different rule, deliberately).
- [ ] `scripts/mac/ota-stage.sh main Debug`; one §01 runbook eyeball card: a reply with `![](https://…)` shows the placeholder on Deep Field and Paper Tape; tap loads; tap again opens fullscreen; a second bubble with the same URL is already loaded.

## Out of scope, and why

- **A trusted-origins allowlist or a setting** — not elected (decision 1's default); the ballot re-offers it.
- **Refusing cross-host redirects** — `AsyncImage` offers no delegate; design B could add one later if Owen wants it; recorded as a residual.
- **Attachment images (`ChatScreen.swift:1723`'s `.image` is the ATTACHMENT enum, not the Markdown segment)** — local data, no fetch, untouched.
- **The HTML sandbox** — stays a blocker (#259); it is the stricter plane and correct as is.

## Self-review (2026-09-04, at plan-writing time)

- Every line number was read tonight: the gate `MarkdownParser.swift:132-140` (`url.scheme == "http" || url.scheme == "https"` is the whole test; the comment says "unconditionally"); the two regexes `:63,:65`; the segment id minted per parse `:8`; `AsyncImage(` at exactly `MarkdownContentView.swift:164` and `:322` and nowhere else in `Talaria/`, `TalariaWidgets/`, `TalariaShare/` (grep tonight); the button-wraps-AsyncImage shape `:160-166`; the `.fullScreenCover` at `:69-78`; the five `MarkdownContentView(` call sites (`MessageBubble.swift:185,583,617`, `FilePreviewSheet.swift:199`, `BriefingDetailScreen.swift:54`); `HTMLPreviewView.swift:79-96`; `project.yml:391-394`; `docs/privacy.html:130-133`; the `MarkdownInterleavingTests` pins at `:29,49`.
- No test in the target hosts a SwiftUI view today (`UIHostingController`: zero hits in `TalariaTests/`) — which is exactly why Task 0 is a measurement and design B exists.
- What this plan does NOT claim: that `AsyncImage` uses `URLSession.shared` in a way a registered `URLProtocol` intercepts in the test host (Apple's documentation says the shared session; Task 0 measures it); that a redirect target is covered by consent (it is not, and the RESULT block says so).
- Type consistency: `RemoteImageConsent.shared/approve(_:)/isApproved(_:)/approved`; `EnvironmentValues.remoteImageConsent`; `RemoteImagePolicy.host(of:)/placeholderTitle(host:)/placeholderAction/placeholderAccessibilityLabel(host:)`; `RemoteImageView(url:altText:mode:onOpen:)` with `Mode.inline/.fullscreen`; `CountingURLProtocol.hits` — used consistently across Tasks 0–3.
