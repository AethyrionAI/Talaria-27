# OPUS T27-241 — client-side immunity: no Talaria session stores the gateway's self-name

**Item:** OPEN_ITEMS **#241** (TRACK-UPSTREAM half continues in parallel — this
lane does not wait on PR #72739 and does not touch upstream). **Difficulty:
OPUS** — a request-body change plus a resolution rule, with the evidence
already gathered. Ruled OPEN at the 2026-08-09 decision pass: *"the highest-
value unrouted work on the board."* Written 2026-08-10.

> **✅ EXECUTED 2026-08-10 on branch `t27-241-session-model-immunity`.** The
> lane-start fork in §2 resolved to **path 2 (catalog default) — bar 241-B
> stands as written, NOT rewritten.** `GatewayModelCatalog` does carry the
> default marker (`provider`/`model` at the top level) and the live OJAMD
> payload's value is a real id (`kimi-coding` / `kimi-k3`), not the alias.
> §1's first bullet below is now HISTORICAL — see its strike. Bars, evidence
> and the close-out live in `OPEN_ITEMS.md` #241.

## 1. Verified state

- ~~**The vulnerable call, at HEAD:** `SessionsHermesClient.createBareSession`
  (`SessionsHermesClient.swift:1178-1185`) posts **`EmptyBody()`** to
  `POST /api/sessions`.~~ **FIXED 2026-08-10 — this is the state the lane
  found, not the state it left.** `createBareSession` now resolves and sends
  an explicit `model`; `EmptyBody` is deleted from the file. Upstream still
  persists `model = body.get("model") or self._model_name` — that half is
  unchanged and is why the ops rule holds — but Talaria no longer takes the
  fall-through.
- **Live blast radius (dossier, verified on OJAMD 2026-08-09):** every
  `source: api_server` session on the production host carries
  `"model": "hermes-agent"`, while `cron` carries `kimi-k3` and `desktop`
  carries `deepseek-v4-flash` — it is specific to our bare-create path.
- **Why it is a hazard, not a curiosity:** the alias is compared against the
  sentinel at request time (`api_server.py:2345`); any divergence (profile
  rename, the "API server model name" field, a different host) turns every
  stored-alias session into a request for a nonexistent model → non-retryable
  404 delivered as HTTP 200 (#241's founding incident). Hermes-native planes
  (session chat, `/v1/runs`) have **no** `allow_bare_model` safety net.
- **What the app already knows:** a client-side `ModelSelection`
  (`BackendProfile.swift:39` — provider + model + `require_model_lock`,
  both-nil = default) persisted per profile by the picker
  (`ModelsSettingsScreen.apply`, #223 Lane 5); every turn already carries the
  lock trio when a pick exists (`SessionsHermesClient.swift:1937-1947`).
  **The vulnerable population is sessions created while selection is nil.**

## 2. Fix shape — resolution rule at create

`createBareSession` sends an explicit `model` resolved in this order:

1. **The profile's `ModelSelection`, if set** — the user's own pick.
2. **The host's real default from the catalog** (`GatewayModelCatalog`, fed by
   `/api/model/options`) — **IF the catalog identifies a default with a real
   provider-model id.** ⚠️ VERIFY AT LANE START whether the catalog carries a
   default marker — read `GatewayModelCatalog.swift` first; the 0.20.0 probes
   confirmed the route but not this field.
3. **If neither resolves: create bare (today's behaviour) and pin AFTER the
   first turn** — the first response's `runtime` block carries the RESOLVED
   real `provider`/`model` (wire-verified in #241's probe rounds);
   `POST /api/sessions/{id}/model` (the session pin, on the verified route
   table) stores it. Degrade, never block session creation.

**The trade, stated because it is the point:** an immunized session is PINNED
to its create-time model and stops following later host-default changes. That
is what immunity means — the follows-default behaviour IS the fragile
aliasing. It also ends the guessed-context-window cost (a real id resolves a
real context length). Ruled acceptable when the lane was opened.

## 3. Bars — copy into #241's entry before the run

- **241-A (RED→GREEN, unit):** with a `ModelSelection` set, the create body
  carries that model — and never the string `hermes-agent`. RED first
  (today's body is empty).
- **241-B (unit):** selection nil + catalog default available → the create
  body carries the catalog's real id. If lane-start verification finds NO
  default marker, this bar is REWRITTEN before the run to pin-after-first-turn
  (path 3) and says so in the entry — a missed bar is a falsification, not a
  redefinition.
- **241-C (unit):** selection nil + catalog unavailable → create succeeds
  bare (no thrown error, no blocked session), and the fallback is logged.
- **241-D (guard):** the literal `"hermes-agent"` never appears in any create
  or pin body the client builds — asserted as a test, not a review comment.
- **241-E (live, rides the OJAMD sitting — already queued in
  `handoffs/HANDOFF-2026-08-09-OJAMD-SESSION.md` §10):** one session created
  from the phone stores a real model id on the production host.
- **241-F:** `GATE: PASS`, counts MOVED.

## 4. Traps

- **`/v1/models` is a trap by design** — it advertises exactly ONE entry: the
  alias. Never source the explicit model from it. The catalog
  (`/api/model/options`) is the real per-provider list; that difference is
  this lane's whole subject.
- **Do not send `require_model_lock` on the CREATE body** — the lock trio is
  the per-turn contract; create takes a bare `model` string. Mixing the two
  changes turn semantics this lane must not touch.
- **Existing sessions are out of scope.** This lane immunizes creation;
  retro-pinning the stored alias on old sessions is a separate decision
  (host-side data, Owen's) — name it in the close-out, don't do it.
- The priming-turn path (`postPrimingTurn`, `:1198`) already carries
  `modelSelection` — verify it still composes; the create change must not
  double-apply.

## 5. Owen's to decide

Nothing before start. If lane-start verification finds the catalog default
marker ABSENT, bar 241-B's rewrite (pin-after-first-turn) is reported in the
entry as the design taken — no new ruling needed, the fallback was specified
here.
