# FM SDK Seam Survey — 2026-07-28

**What this is:** the consolidated findings of the FoundationModels prior-art survey run
the night of 2026-07-28, during the #200D promotion lane. Trigger: Owen surfaced a
source list compiled by Kimi K3 and asked for independent verification. Method, in
order: (1) direct grep of the local Xcode-beta4 iOS 27 SDK swiftinterfaces (assistant
knowledge cutoff predates WWDC26, so the SDK on disk is the only ground truth);
(2) targeted WebFetch/WebSearch passes; (3) an 8-agent workflow comb (one sonnet agent
per source, structured findings, 8/8 returned, ~800k tokens, ~7 min). Dated OPEN_ITEMS
notes: #200 addendum (SDK seam survey) and #200 addendum 2 (comb synthesis +
correction). Companion artifact: `docs/reference/fmf-beta4-swiftinterface.md` (vendored
doc-commented interface transcription, MIT — see THIRD_PARTY_LICENSES.md).

---

## 1. Verified iOS 27 API surface (all confirmed in the local beta-4 SDK)

| Surface | What it is | Program relevance |
|---|---|---|
| `GenerationOptions.ToolCallingMode` | `.allowed` (default) / `.required` / `.disallowed`, **per-request** (`GenerationOptions(toolCallingMode:)`) and per-profile (`DynamicProfile.toolCallingMode(_:)`) | The structural seam for the D1 clarify-stall → **#200E cell** |
| `.required` loop semantics | Doc comment (via fmf.md, confirmed by WWDC 242): the session **loops until a Tool throws or the mode is changed dynamically**. Apple's exit patterns: `.toolCallingMode(state.done ? .disallowed : .required)` + `.onToolCall { state.done = true }`, or a "final answer" tool that throws `CancellationError` | #200E MUST use the demote pattern; raw `.required` spins into the guillotine |
| `LanguageModelSession.DynamicProfile` | Declarative per-prompt builder: `.model/.temperature/.samplingMode/.maximumResponseTokens/.reasoningLevel/.toolCallingMode/.historyTransform/.transcriptErrorHandlingPolicy/.onPrompt/.onResponse/.onToolCall`, shared state via `@SessionProperty`; `session.transcript` now settable when not responding | Context management (`historyTransform`), #197 recovery (`transcriptErrorHandlingPolicy`, default `.revertTranscript`), the #200E exit mechanism |
| `public protocol LanguageModel` + `LanguageModelExecutor` | Third-party providers back `LanguageModelSession`; capabilities `.toolCalling/.guidedGeneration/.reasoning/.vision`; executor: `init(configuration:)`, `prewarm(model:transcript:)`, `respond(to:model:streamingInto:)` | The Hermes-unification seam (§3) |
| Typed `LanguageModelError` | 9 cases: `contextSizeExceeded`, `rateLimited`, `refusal`, `guardrailViolation`, `unsupportedCapability`, `unsupportedTranscriptContent`, `unsupportedGenerationGuide`, `unsupportedLanguageOrLocale`, `timeout` — payload shapes compiler-verified by Foundation Lab's test suite | We currently diagnose these from raw strings; typed handling is an instrument-hardening candidate |
| **Cross-import overlays** | `_Vision_FoundationModels` → **`OCRTool`, `BarcodeReaderTool`** (real `Tool` conformances, `call → some PromptRepresentable`); `_CoreSpotlight_FoundationModels` → **`SpotlightSearchTool`** (+ `Configuration`, `CoreSpotlightSource/FileSource/SearchSource`); `_FoundationModels_UIKit`, `_FoundationModels_SwiftUI` also exist | See correction (§2). SpotlightSearchTool resolves the "semantic search" claim: it's a Tool over Core Spotlight, not a vector API |
| `PrivateCloudComputeLanguageModel` | Server model conformance: 32K context, entitlement `com.apple.developer.private-cloud-compute`, no API keys, daily per-user quota, free tier < 2M first-time downloads, `reasoningLevel` `.light/.deep` | Talaria already has a `.privateCloud` tier concept (headroom 4096); candidate backend for harder cells |
| Evaluations framework (WWDC26/241) | Swift Testing integration, model-judge qualitative scoring, pitched as quantifying prompt-change impact | **This is the battery, productized by Apple.** Investigate for instrument evolution |
| `logFeedbackAttachment(sentiment:issues:desiredOutput:)` | Sanctioned Feedback Assistant channel for model-behavior reports | The D1–D4 findings are filable to Apple |
| "Foundation Models framework utilities" package | Apple's open-source companion: Skills pattern, `.rollingWindow(size:)` history modifier | Candidate fix for the 8,583-token searchConversations overflow |

## 2. The correction (verification discipline note)

The first survey pass declared `OCRTool`/`BarcodeReaderTool` "NOT in the beta-4 SDK"
after grepping the FoundationModels, Vision, and VisionKit primary interfaces. **That
was a false negative.** Overlay APIs live in separate `_A_B.framework` cross-import
modules that only activate when both parent frameworks are imported — a grep of the
primaries never sees them. The find-anywhere sweep
(`find $SDK -name "*.swiftinterface" | xargs grep -l OCRTool`) hit
`_Vision_FoundationModels` immediately. Kimi K3's original claim was correct. Lesson
(also in session memory): before declaring an SDK symbol absent, sweep every
swiftinterface in the SDK, not the obvious frameworks.

## 3. anthropics/ClaudeForFoundationModels (verified firsthand via `gh api`)

- **Real and active:** Apache-2.0, created 2026-05-20, last pushed 2026-07-24,
  267 stars, "Claude support for Apple Foundation Models." Three core sources read
  raw (not summarized): `ClaudeLanguageModel.swift`, `ClaudeExecutor.swift`,
  `RequestBuilder.swift`.
- **ToolCallingMode maps to Claude's `tool_choice`** wire field directly — the
  Apple-side enum is honored by remote providers too.
- **Client-side tools stay local:** the FoundationModels framework itself invokes
  `Tool` conformances regardless of which `LanguageModel` backs the session. For
  Talaria this is the headline: **Hermes-as-provider would keep our device belt,
  confirmation cards, and gate exactly as they are** — the remote model only plans
  the calls.
- **Transcript handling:** the reference executor resends the full transcript every
  request and leans on Anthropic's server-side prompt caching; no local KV-cache
  logic. `reasoningLevel` maps to Claude effort as a soft hint (silently dropped when
  unsupported, except explicit `fixedEffort`).
- **Auth:** production guidance is App Attest
  (`com.apple.developer.devicecheck.appattest-environment`; simulators throw
  `attestationUnsupported`); a bundled API key is called out as extractable/dev-only.
  If Talaria ever wraps Hermes with a bundled `API_SERVER_KEY`, that is the same
  insecure pattern — the tailnet transport mitigates but the warning stands.
- **Known bug worth stealing mitigations from (their issue #13):** structured-output
  requests pay a 30–48s server-side grammar-compilation cost on schema changes, with
  unreliable caching (8–27.5s stalls recur). Mitigations documented: prewarm off the
  critical path at launch, log time-to-first-token + request id, opt-in first-byte
  timeout. Their measured stall phenomenology is a useful analogue to our wedged
  `respond()` hangs.
- **Platform gate:** hard-pinned to OS 27.0 in Package.swift (a community fork
  lowered it with `@available`, so it's a policy gate, not a technical floor).
- WWDC26/339 names Anthropic and Google as first providers ("state-of-the-art Claude
  and Gemini models available to all Swift developers").

## 4. Prior-art findings mapped to the filed diseases

- **D1 clarify-stall.** Independent convergence: `rryam/FoundationModelsKit` ships
  production instructions — "Always execute tool calls directly without asking for
  confirmation … call the RemindersTool immediately" — the same session-instructions
  fix class we measured (#200C) and promoted (#200D). Deeper: Apple's own **on-device
  Siri planner prompt (PLANNER ODM) bakes in "Clarify with user if unclear"** — a
  plausible training-distribution origin of the stall itself. The big-model CATALOG
  planner runs the opposite optional-param policy (omit, never null-fill; ask only
  via a dedicated tool when truly missing).
- **D2 read-for-create substitution.** CATALOG has an explicit "find first when
  ambiguous between creating and finding" rule — prior art for the substitution as
  trained behavior, and a reason our imperative-verb prompts must carve out the
  create case explicitly.
- **D3 grab/over-calling.** Candidate treatment from ODM: a `not_supported`
  escape-valve tool giving the model a cheap "no tool applies" action. Also Apple's
  guidance: 3–5 active tools per request (Talaria's belt is 10) → per-turn
  tool-scoping is a measured-cell candidate.
- **D4 argument corruption + hangs.** Apple's `maximumResponseTokens` doc: a strict
  cap "can lead to the model producing malformed results" — and Talaria caps every
  on-device turn at 1024 (#102 thermal guard, deliberate, measured). Cap-truncation
  is now a live hypothesis for `Sam}` / `"],"` corruption → armed-cap2048/armed-nocap
  cell candidate; #102 does not move without a battery. For loops/hangs: CATALOG's
  hard-stop ("calling the same tool with the same parameters in succession is a hard
  failure") is implementable client-side; canonical date-format examples in param
  descriptions are a corruption treatment candidate.
- **Novelty check:** across all eight sources — Apple sessions, docs, blogs, repos,
  the planner corpus — **zero public prior art describes D1–D4 as measured
  phenomena.** The battery results are original empirical work. (Filable to Apple
  via `logFeedbackAttachment`.)

## 5. Pivot menu (post-#200, Owen routes)

Measured-cell discipline unchanged: nothing promotes without a battery verdict.

| Option | Effort | Expected payoff | Notes |
|---|---|---|---|
| **A. #200E toolmode cell** (`.required` + demote-after-first-call DynamicProfile) | Small — battery instrument reusable as-is | Potentially kills D1 structurally (remind 2/10 → ~10/10?) | Already queued; canary critical (forced grab on misroute); promotion would be router-gated |
| **B. DynamicProfile adoption bundle** (`historyTransform`/`.rollingWindow`, `transcriptErrorHandlingPolicy`, typed `LanguageModelError` handling, `onToolCall` telemetry) | Medium | Fixes the context-overflow class, #197 transcript recovery, string-free error handling, better instrument capture | Mostly engineering, less measurement-risk; can land incrementally |
| **C. Tool-scoping cell** (3–5 tools/turn via router intent) | Small–medium | Apple-recommended; may cut D3 grabs and D4 spirals | Router already classifies; scope the belt per class |
| **D. Cap cell** (armed-cap2048/armed-nocap vs control on corruption rate) | Small | Confirms/kills the D4 cap-truncation hypothesis | #102 thermal tradeoff — measure before touching |
| **E. Hermes-as-LanguageModel spike** (provider protocol, ClaudeForFoundationModels as reference) | Large | One session/tool surface for both chat paths; device belt + cards stay local; kills the dual-path architecture long-term | Architecture item — needs its own dispatch, OS-27-only, auth design (no bundled keys) |
| **F. Evaluations-framework spike** | Small–medium | Battery instrument evolution: Swift Testing + model-judge | Investigate API availability in beta 4 first |
| **G. Escape-valve tool + anti-loop hard-stop + date-format params** (planner-corpus treatments) | Small each | D3/D4 treatments with Apple's own conventions | Each enters as a measured cell |

**Recommendation:** finish #200D re-verify → run A (#200E) since the instrument is
hot and it targets the one disease still unsolved at 2/10 → then B as the
engineering pivot (highest certain value, no measurement risk) with D and G as cheap
cells riding the next battery build → E as a deliberate architecture lane with its
own dispatch once the #200 family closes. F can piggyback whenever the test suite is
next touched.

## 6. Source ledger

| Source | Access | Verdict |
|---|---|---|
| Local beta-4 SDK swiftinterfaces | direct grep (primary + full-SDK find) | Ground truth; overlays lesson (§2) |
| rudrankriyam/Foundation-Models-Framework-Lab + rryam/FoundationModelsKit | cloned, read | High value: fmf.md (vendored), demote pattern code, D1 convergence, error-case test suite |
| samhenrigold iOS 27 system prompts gist | cloned (190 files) | High value: planner corpus (§4); no SDK symbols |
| WWDC26 sessions 241/242/339/237/246 | WebFetch of Apple pages | High value: loop-exit patterns, Evaluations, SpotlightSearchTool resolution, provider quotes |
| anthropics/ClaudeForFoundationModels | `gh api` raw reads | High value (§3) |
| Blake Crosley cluster + ChatForest | WebFetch | Medium: correct on overlays (we were wrong), honest hedging on elided docs; ChatForest AI-authored, one wrong context figure |
| affaan-m ECC skill | cloned | Low: iOS 26 tutorial, no companions, accurate as far as it goes |
| IvanCampos/Foundation-Models-Playgrounds | cloned | Low: LLM-generated iOS 26 stubs; documented-negative baseline only |
| Saharshv/Foundation-Model-Tutorial | cloned | Low: cautionary example (uncaught respond errors, stuck isResponding) |
| r/LocalLLaMA + r/LLMDevs threads | **unreachable** (Reddit blocks fetch + curl 403) | Core claims cross-verified via Apple's 2025 tech report + drobinin.com + Apple dev forums instead |
