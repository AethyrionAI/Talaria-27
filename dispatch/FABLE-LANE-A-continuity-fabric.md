# FABLE — Lane A: P1 Continuity Fabric

**Branch:** `claude/t27-lane-a-continuity-fabric`
**Status:** GREENLIT — P1 transplant-fidelity probe PASSED 2026-07-09 (OPEN_ITEMS #89).
**Repo:** AethyrionAI/Talaria-27, base `main` @ 75dd6b3. Pin every `gh` with `--repo AethyrionAI/Talaria-27`.
**Verification model:** Fable = implement + Swift Testing unit tests. Build / simulator / device
validation is Mac-side (Xcode-beta, iOS 27 SDK) per the review protocol — do NOT assume you can
build iOS in the cloud. Authoritative design = the 10x doc P1 section (Owen has it); this file is
the grounded delta + guardrails.

## Goal
Make the on-device **journal** the durable primary object, and **transplant** condensed context into
a FRESH Hermes session at every "brain hop" instead of leaning on one long-lived server session.
Decouple conversation identity from the server `apiSessionId`.

## Why now (probe result, #89)
The transplant MECHANISM is validated: a condensed ~10:1 priming turn read as continuous *context*
(recall + cross-turn inference + a mid-stream correction all survived), indistinguishable from the
original session and from a raw replay. The residual risk is NOT the mechanism — it's condenser
fidelity / pruning discipline. That is made an explicit acceptance test below.

## Current state (confirmed live at 75dd6b3)
- `SessionsHermesClient` holds a single `private var apiSessionId: String?`
  (`SessionsHermesClient.swift:27`; cleared `:55` / `:281`; assigned `:371`); `ensureSession()`
  (`:418`) assumes one session. **This is the single-session coupling to break.**
- Condensation primitives already exist in `LocalIntelligenceService.swift`:
  `trimmed(_:toTokenBudget:)` (`:140`), `condensedLine(_:limit:)` (`:206`),
  `measuredTokenCount(of:)` (`:156`), `conversationCard(...)` (`:47`); falls back to truncation
  when the on-device model is unavailable.
- Offline-outbox pattern to COPY: `SensorUploadService` + `UserDefaultsAppPersistenceStore` +
  `AppPersistenceStoreProtocol` (queued items persist across launches, drain on connectivity).
- Token **receipts** already surface in `StatusCardView` / `MessageBubble` / `ChatStore`.

## Build
1. **Journal as durable primary.** Conversation record persists on-device, independent of any
   server session id (design per 10x doc P1).
2. **Decouple identity from `apiSessionId`.** Introduce a local conversation identity; make
   `apiSessionId` an ephemeral, swappable per-hop server handle — not the conversation's identity.
   Refactor `ensureSession()` and the single `apiSessionId` var accordingly.
3. **Context transplant at each brain hop.** On a new hop (fresh server session), compose a
   condensed priming turn from the journal via `LocalIntelligenceService` and send it as turn 1.
4. **Offline compose outbox.** Copy the SensorUpload/persistence-store pattern: compose turns
   offline, persist, drain when the Sessions API is reachable.
5. **Surface priming token cost** through the existing receipts (priming is not free).

## ACCEPTANCE TEST — condenser fidelity (REQUIRED; this is the probe's residual risk)
Swift Testing unit tests that feed the condenser a messy multi-turn transcript containing
(a) two corrections and (b) two irrelevant distractor facts, then assert the produced priming:
- preserves each corrected value at its LATEST value (never regresses to the pre-correction value);
- does NOT carry the distractors (pruning discipline = token cost);
- stays within the target token budget.
Rationale: the probe used the full Hermes model as an OPTIMISTIC proxy; the on-device
`LocalIntelligenceService` is weaker and likely needs pruning discipline MORE. This test is the guardrail.

## Guardrails
- Main refactor point: the single-session assumption at `SessionsHermesClient.swift:27` / `:418`.
- Repo discipline: `xcodegen generate` after adding/removing Swift files; the regen commit is
  SEPARATE from the feature commit.
- Possible merge overlap with Lane C on `ChatScreen.swift` — small; Lane C merges first, A rebases.
- Line refs confirmed at 75dd6b3 — re-confirm at your branch HEAD (standard practice).
