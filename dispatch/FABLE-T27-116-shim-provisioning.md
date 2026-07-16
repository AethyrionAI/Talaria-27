# FABLE T27-116 — Post-pair provisioning bundle + honest shim probe

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-116-*`
**Dispatch date:** 2026-07-16 · **Tracks:** OPEN_ITEMS #116
**Merged-PR check done 2026-07-16:** nothing exists; item logged yesterday.
**Delivery:** TWO PRs. PR 1 server-side (relay + connector, pytest), PR 2
app-side (Swift), stacked or sequential — PR 2 consumes PR 1's endpoint.

## Why

#114's device pass proved the pain: adding the Mac profile meant hand-locating
`~/.hermes/talaria_shim_token` on the host and iMessaging it to the phone, and
`SHIM ONLINE` glowed green off unauthenticated `/healthz` while the token field
sat empty. Every future profile add — and every future user — hits both.
Target UX: **scan the pairing QR once; the profile keys itself.**

## PR 1 — server side (relay + connector; the fork, NOT upstream hermes-agent)

### Provisioning payload, connector → relay

The connector already registers its host with the relay and holds host-local
knowledge. Extend it to supply a provisioning descriptor on
register/heartbeat (implementation's choice, but it must refresh when values
change):

```
{ "shim_base_url": "http://<host>:8765",
  "shim_token": "<contents of ~/.hermes/talaria_shim_token>",
  "gateway_base_url": "http://<host>:8642" }
```

- Connector reads the token file lazily; absent file → omit shim fields (a
  host may legitimately run no shim).
- **Gateway API key is EXCLUDED by design** — Owen's deliberate manual gate
  (#108's "paired — add your key in Uplink" nudge stays the flow). Do not
  add it "for completeness."

### Device endpoint, relay

`GET /v1/device/provisioning` — authenticated by the device bearer token
(same auth class as `/v1/device/files`). Returns the host's current
descriptor or an explicit empty shape. Store the descriptor server-side
wherever host metadata already lives (`hermes_hosts` table has precedent —
follow the existing migration pattern in `relay/`; the relay is DB-backed,
никаких in-memory registries).

### Tests (pytest, both suites)

Connector: descriptor built from a real temp token file; absent-file omission;
refresh on change. Relay: endpoint auth (401 unauthed), round-trip, empty
shape. Baselines to not regress: relay 117, connector 105 (macOS).

## PR 2 — app side

1. **Auto-fill on pair:** after a successful pairing redeem for profile P
   (`PairingStore.pair()` — PRESERVE #94 redeem-first ordering and the
   per-profile clean-slate from #114), call the new endpoint with P's fresh
   tokens and fill P's `shimBaseURL` + `shimToken` (Keychain, profile-keyed
   via `BackendProfileScopedKeys`) — **only if the user hasn't already set
   them** (never clobber manual values). Same treatment for an empty
   `gatewayBaseURL` (fill the URL; never the key).
2. **Honest shim probe:** `ServerSettingsScreen`'s probe layer — when P has a
   shim token, follow `/healthz` with an authenticated shim call and render
   answering-but-unkeyed distinctly, mirroring the gateway probe's 401/403
   treatment. NOTE: the probe helpers are now `static` with an accumulator-box
   pattern — a deliberate iOS-27-SDK region-checker workaround (see the file's
   comments and OPEN_ITEMS #114 findings). Do NOT refactor them back to
   instance methods or `withTaskGroup`; extend within the pattern.
3. **Re-provision affordance:** small "refresh provisioning" action on the
   profile card/editor for token rotation later.

### App tests

Auto-fill fills empty fields only; manual values survive; per-profile Keychain
writes; probe classification (mock the authed call).

## Constraints

- Relay/connector code is the FORK (dylan-buck lineage) — free to modify.
  `~/.hermes/hermes-agent/**` (upstream) is off-limits, as always.
- Real data only: probes reflect actual responses; provisioning absence
  renders as absent, never as fake-configured.
- The OJAMD deploy of PR 1 rides `ojamd-deploy` rebase (Owen's gate) — note
  it in the PR; Mac deploy is the local checkout the services already run from
  (a relay/connector restart on the Mini is part of device verification).

## Definition of done

Factory-reset simulation on device: forget the Mac profile's pairing → re-pair
via QR → shim URL + token auto-fill within seconds → shim probe shows
authenticated-online → models surface works — zero manual token handling.
