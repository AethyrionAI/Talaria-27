# FABLE T27-127 — Monetization scaffold: StoreKit 2 freemium gate

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-127-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #127 (new) · **Size:** one PR, medium
**Baseline:** 755/62 · **Toolchain:** Xcode-beta3 · **StoreKit is GREENFIELD** (verified: zero
StoreKit references on main).

## The model (Owen's decision, 2026-07-17)

Freemium. **Free tier = the standalone app**, complete: on-device model, native
voice, OCR, widgets, health tiles. **Paid tier ("Connected") = the BYOK/
connect-your-own-host upgrade**: the Hermes connect flow, backend profiles,
sensor uplink, agent inbox, realtime voice — everything that pairs to a host.
Users pay for the connectivity feature set, not for compute (they bring their
own host/keys; PCC keeps the free tier zero-marginal-cost).

## The build — scaffold only, no store listing work

1. `Talaria/Services/Live/EntitlementService.swift` (+ protocol + mock):
   StoreKit 2. One product to start: non-consumable or annual sub —
   **implement BOTH product-type code paths behind one config constant** so
   the pricing call stays open; product id constant
   `org.aethyrion.talaria27.connected` (placeholder, single source).
   `Transaction.currentEntitlements` on launch + `Transaction.updates`
   listener; publish `isConnectedTierUnlocked: Bool`. Restore = StoreKit 2's
   sync call behind a "Restore Purchases" button.
2. **The gate, minimal and honest:** gating wraps ENTRY POINTS, not plumbing —
   `ConnectHermesHostScreen` (the pairing flow), `ServerSettingsScreen` /
   backend-profile add, and `UplinkSettingsScreen` enable. Locked state shows
   the paywall sheet instead. **CRITICAL: an EXISTING pairing must keep
   working if entitlement checks fail transiently (offline, StoreKit outage) —
   gate the ACT of connecting/adding, never sever a live connection.** Cache
   the last-known entitlement; fail open for already-configured hosts, fail
   closed only for new connects.
3. Paywall sheet: one screen, theme-tokened (`Design.Colors`), lists the
   Connected features, price from `Product.displayPrice` (never hardcoded),
   purchase + restore + "Not now". No dark patterns; dismissible always.
4. `#if DEBUG` developer override toggle (Developer settings screen, pattern
   already exists there) so device testing doesn't require sandbox purchases.
5. **DO NOT gate anything shipped-free today in a way that breaks existing
   users** — this scaffold lands DORMANT: a `monetizationEnabled` flag
   (default false) makes the whole gate inert until Owen flips it at launch.

## Tests

Entitlement decision function pure + tested: entitled/not/cached/transient-
failure × existing-pairing/new-connect matrix — the fail-open rule pinned.
Paywall presentation logic tested. StoreKit sandbox itself is device-land.

## Constraints & acceptance

- File-scoped commits; regen on file add (separate commit, aps-environment
  verified). No project.yml capability changes (in-app purchase needs no
  entitlement key on iOS). Suite green ≥ 755/62.
- PR body: App Store Connect setup steps for Owen (create product id, sandbox
  tester), and the flip-at-launch note. Device check: DEBUG override
  on/off drives the gate; sandbox purchase + restore round-trip.
