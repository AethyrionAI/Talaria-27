# Lane 5 — Models-shim retirement on the v0.20.0 gateway contract (Approach A: per-turn lock)

**Date:** 2026-08-04 · **Item:** OPEN_ITEMS #223 Lane 5 (execution-plan Lane 5 / Phase 1) · **Kills:** #9 (gateway pin hang) · **Retires:** #4's CONFIRM guard (waived by Owen 2026-08-03)

**Approvals:** Owen answered the three design forks directly: pick scope = "One default per host" (2026-08-04 ~00:15); services = "I can stop them remotely when you're done. You can do the app side now"; mechanism = "A for the a/b choice" (Approach A, per-turn lock). Built under the 2026-08-04 goal run ("finish the rest of the open items that are workable"); the in-section design-approval walkthrough was replaced by an in-transcript presentation for async review. **Merge remains Owen's.**

## Probed contract this design stands on (#241 re-test, 2026-08-03 ~23:20 CDT, raw responses in `handoffs/241-retest-2026-08-03/`)

- `GET /api/model/options` (gateway bearer): full catalog — per-provider `slug`, `name`, `authenticated`, `auth_type`/`key_env`/`warning` (unauth), `models` (string ids), `pricing` (display strings: `"$8.00"`, `"free"`, `discount_percent`, `was_*`), `free_tier`, `unavailable_models`, `featured_models`, `capabilities`; **top-level `provider` + `model` = the host's current default.**
- Per-request `model`/`provider` on chat WITHOUT `require_model_lock` is a **silent no-op** (echoed under `runtime.requested`, not honored). WITH `require_model_lock: true`: honored, `model_lock: "confirmed"`, proven cross-provider onto nous (the validating provider).
- Every 0.20.0 chat response and SSE event carries a `runtime` block: resolved `provider`/`model`, `route_source`, `model_lock`, `requested` echo.
- Invalid locked model → upstream 404 delivered as **error-text assistant content** (HTTP 200, `usage` 0/0/0) on both `/chat` and `/chat/stream` — render-safe in today's app.

## Design

### 1. Selection model — one optional pick per profile

- `BackendProfile` gains `selectedModelProvider: String?` and `selectedModelID: String?` (both optional ⇒ decode-tolerant both directions; old JSON decodes on new builds, new JSON decodes on old builds via synthesized-Decodable unknown-key tolerance).
- **No pick ⇒ wire bytes identical to today** and the host default rules. The pick is cleared by choosing the new **HOST DEFAULT** row.
- Loss accepted by Owen (audit block, 2026-08-03): a phone pick no longer changes the HOST's default for Discord/CLI.

### 2. Wire — per-turn lock

- `ChatTurnBody` gains `provider: String?`, `model: String?`, `requireModelLock: Bool?` with explicit `CodingKeys` (`require_model_lock` is snake_case; the client decoder/encoder has no global strategy). Encoded **only when a pick exists**; `require_model_lock` is always `true` when `model` is present — never a bare `model`.
- Applies to all three turn paths (sync chat, stream chat, priming turn) since they share `ChatTurnBody.make` — the selection is a new parameter threaded from `ChatStore`, which reads the active profile's pick at send time. Mid-conversation pick changes therefore apply on the next turn.
- `runtime` parsing: a `TurnRuntime` struct (`provider`, `model`, `routeSource`, `modelLock`, `requestedProvider`, `requestedModel` — all optional) decoded from sync responses and from `assistant.completed`/`run.completed` SSE payloads. `ChatStore` updates the header model name from **resolved** `runtime.model` when present.

### 3. Catalog — gateway-sourced picker

- New fetch on `SessionsHermesClient`: `fetchModelCatalog()` → `GatewayModelCatalog` DTO (top-level `provider`/`model` + `[GatewayProviderEntry]`). Existing `availableModels()` (unused flattening of the same route) is subsumed/removed.
- `ModelsSettingsModel` drops its `shim` dependency; deps become the catalog fetch + `ChatStore` + the profiles store (for pick persistence). `options` becomes the gateway DTO.
- Rows: **HOST DEFAULT** first (subtitle = host's current `provider/model`, selected when no pick), then providers grouped as today: authenticated providers list models; unauthenticated providers show the catalog `warning` (setup hint) exactly as the shim's needs-setup rows did.
- `apply(provider:model:)` = persist pick on the active profile + set header name + done (no network). `applyingModelID` stays for row-spinner continuity but clears synchronously; the overlay's success phase fires. `activeOverride` (the shim-cache workaround) is deleted — the pick IS the state.
- "Refresh models" = plain re-fetch of `/api/model/options` (no `?refresh` knob — waived).
- Pricing: `ModelPricingCatalog.ingest` adapts to the gateway pricing dict (same display-string vocabulary as the shim's; `TurnReceipts` consumers unchanged).
- Seed: `seedActiveModelFromShim()` → `seedActiveModelFromGateway()` — header name = profile pick if present, else catalog top-level `model`; same `activeModelName == nil` guards at the three call sites.

### 4. Retirements (app side; box services are Owen's remote stop, later)

| What | Disposition |
|---|---|
| `ModelsShimClient.swift` | deleted (xcodegen regen) |
| `switchModel(_:)` + `pinSessionInBackground` (`/model` slash-command pin) | deleted — **#9 closes** (the hang path no longer exists) |
| CONFIRM flow: `PendingConfirm`, `confirmPending/cancelPending`, overlay confirm card | deleted — #4 annotated (guard retired with the shim; pricing stays visible in rows) |
| ServerSettings shim probe rows (`probeShim`, `/healthz` + raw `/models` GET) + the `modelsShimBaseURL` binding | deleted; `UserSettings.modelsShimBaseURL` stays decode-tolerant, no longer read/written by UI |
| `ProvisioningService` shim fields (`shimBaseURL`, `shimToken`) | no longer applied; relay descriptor keys tolerated and ignored; tests updated |
| `AppContainer`: shim client construction, `saveModelsShimToken`, shim token boxes/rebinding | deleted (Keychain rows left in place, harmless, downgrade-safe) |
| `BackendProfile.shimBaseURL` | **field stays** (decode tolerance + downgrade safety), UI/consumers stop reading it |

### 5. Error handling

- Catalog fetch failure → existing `errorMessage` panel (unchanged pattern).
- Invalid/unavailable locked pick → the turn renders the gateway's error text as an assistant message (verified shape); the header keeps showing the pick's name; user recourse = pick HOST DEFAULT or another model. No special-case UI in this lane.
- Old gateway (< 0.20.0, e.g. a stale Mac process): `/api/model/options` may 404 → picker shows the error panel; **chat is unaffected** (no pick ⇒ no new fields; a pick against an old gateway would be silently ignored on the kimi-class path — mitigated by the runtime block being absent, in which case the header falls back to the seeded name; documented, not engineered around).

## Testing (bars pre-registered in OPEN_ITEMS #223 before the verification run)

- **L5-A (wire):** `ChatTurnBody` with a pick encodes exactly `provider`/`model`/`require_model_lock: true` alongside `input`; without a pick the encoded JSON is byte-identical to today's. Text-only and image-parts variants both covered.
- **L5-B (catalog):** the archived real payload (`handoffs/241-retest-2026-08-03/model-options-241.json`) decodes: provider count, auth flags, unauth `warning`, pricing ingest (paid + `:free` rows), top-level current pair. Unknown keys tolerated.
- **L5-C (behavior):** scripted-client `ModelsSettingsModel`: load populates rows + host-default row; `apply` persists the pick per-profile and touches no network; HOST DEFAULT clears the pick; `TurnRuntime` from a scripted turn updates the header to the resolved model.
- **L5-D (retirement):** app target has zero references to `ModelsShimClient`/`/models/default`; provisioning ignores shim fields (updated `ProvisioningServiceTests`); suite + Release build green (the gate).
- **L5-E (device, owed to next OTA):** on OJAMD — pick `deepseek/deepseek-v4-flash-0731` → next turn's SSE `runtime` shows `model_lock: "confirmed"` + resolved deepseek id, header updates; HOST DEFAULT → turn runs kimi-k3 with no lock fields; invalid pick shape renders as message text.

Counted suite delta: pinned in the OPEN_ITEMS entry once tests are written, BEFORE the verification run.
