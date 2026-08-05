# Lane 5 — Shim Retirement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (inline, this session — goal run 2026-08-04). Spec: `planning/superpowers/specs/2026-08-04-lane5-shim-retirement-design.md`. Executor note: this plan is compressed relative to handoff-grade plans because the author executes it in the same session with the spec in context; signatures below are the contract.

**Goal:** Retire the models shim app-side — picker + pricing from `/api/model/options`, selection as a per-turn `require_model_lock` on chat, one optional pick persisted per profile.

**Architecture:** Approach A (stateless per-turn lock). No pick ⇒ wire identical to today. Runtime blocks give resolved attribution.

**Branch:** `claude/t27-223-lane5-shim-retirement` · **TDD:** watched RED per task · **Gate before PR.**

## Global Constraints

- Never encode `model` without `require_model_lock: true` (silent no-op trap, #241).
- Explicit `CodingKeys` for every snake_case wire field (no global strategy on this client).
- `BackendProfile` new fields optional-only (decode tolerance both directions).
- Real data only: header shows resolved runtime model when known; seeded/pick name otherwise; `"—"`/fallback per existing `ModelSelector` default.
- Counted suite delta pinned in OPEN_ITEMS before the verification run.

### Task 1: Catalog + runtime DTOs and fetch (L5-B)

**Files:** Create `Talaria/Services/Live/GatewayModelCatalog.swift`; Modify `SessionsHermesClient.swift` (add `fetchModelCatalog()`, remove `availableModels()`); Test `TalariaTests/GatewayModelCatalogTests.swift` (fixture = archived `model-options-241.json`, embedded as a test resource string).

**Produces:**
```swift
struct GatewayModelCatalog: Decodable, Sendable {
    let provider: String?; let model: String?           // host current default
    let providers: [GatewayProviderEntry]
}
struct GatewayProviderEntry: Decodable, Sendable {
    let slug: String; let name: String
    let authenticated: Bool; let warning: String?
    let models: [String]; let featuredModels: [String]?
    let pricing: [String: GatewayModelPricing]?         // display strings, shim-compatible
}
struct TurnRuntime: Decodable, Sendable, Equatable {
    let provider: String?; let model: String?
    let routeSource: String?; let modelLock: String?    // route_source / model_lock
}
func fetchModelCatalog() async throws -> GatewayModelCatalog   // GET /api/model/options
```
Steps: failing decode tests off the real fixture (provider count 43, Nous Portal auth+35 models, fireworks unauth+warning, top-level kimi pair, `:free` pricing rows, unknown-key tolerance) → implement → green → commit.

### Task 2: ChatTurnBody selection fields (L5-A)

**Files:** Modify `SessionsHermesClient.swift` (`ChatTurnBody`, `.make`, all three call paths); Test `TalariaTests/ChatTurnBodyEncodingTests.swift` (new).

**Produces:**
```swift
struct ModelSelection: Equatable, Sendable { let provider: String; let modelID: String }
ChatTurnBody.make(message:attachments:selection: ModelSelection?)
// encodes {"provider":…,"model":…,"require_model_lock":true} iff selection != nil
```
Steps: failing tests — (a) nil selection ⇒ encoded JSON keys exactly `["input"]` (byte-compat guard), (b) selection ⇒ the three fields with `require_model_lock: true`, (c) image-parts variant keeps parts shape → implement with explicit CodingKeys → green → commit.

### Task 3: Profile pick + ModelsSettingsModel rewrite (L5-C)

**Files:** Modify `BackendProfile.swift` (+2 optional fields + scoped setter on `BackendProfilesStore`), `ModelsSettingsScreen.swift` (model rewrite: deps = catalog-fetch closure + profiles store + ChatStore; HOST DEFAULT row; `apply` persists, no network; delete `activeOverride`, `PendingConfirm`, `confirmPending/cancelPending`), `ModelTransitionOverlay.swift` (confirm card + `confirmActive` removed). Test: `TalariaTests/ModelsPickerModelTests.swift` (new, scripted catalog).

Steps: failing tests — load populates host-default row + provider rows; `apply` writes profile fields and never touches network; HOST DEFAULT clears pick; decode-tolerance round-trip of `BackendProfile` JSON without the new keys → implement → green → commit.

### Task 4: Send-time threading + attribution + seed swap

**Files:** Modify `ChatStore.swift` (selection read at send; `TurnRuntime` → header name via existing displayedModelName path), `SessionsHermesClient.swift` (decode `runtime` on sync response + `assistant.completed`/`run.completed` events; delete `switchModel`), `AppContainer.swift` (seed swap → `seedActiveModelFromGateway()`; drop `chat.selectModel` pin path). Tests: extend `ContinuityFabricTests` scripted client with runtime payloads; seed test in `AppStoresTests` if present.

Steps: failing tests — turn completion with runtime updates header to resolved id; absent runtime leaves header unchanged; send passes the active profile's pick to the body builder → implement → green → commit.

### Task 5: Retirement sweep (L5-D)

**Files:** Delete `ModelsShimClient.swift`; Modify `AppContainer.swift` (client construction, token boxes, `saveModelsShimToken`), `ServerSettingsScreen.swift` (shim probe rows + binding), `ProvisioningService.swift` (stop applying shim fields), `UserSettings.swift` (mirror no longer read/written; decode stays), affected tests (`ProvisioningServiceTests`, `AppStoresTests` null-client, `TurnReceiptsTests` fixtures → gateway pricing shape, `ServerSettingsTests` probe test), `project.yml` untouched (file removal ⇒ xcodegen regen).

Steps: sweep → `xcodegen generate` → failing-then-updated tests → grep proves zero `ModelsShimClient`/`/models/default` references in app target → commit.

### Task 6: Record + gate + PR

Steps: OPEN_ITEMS #223 Lane 5 build record + bars L5-A…E status + counted delta (pin BEFORE the gate run); #9 closed-by-deletion note; #4 retired note; `scripts/mac/lane-gate.sh` backgrounded + polled; PR with `gh pr create`; no merge (Owen's).
