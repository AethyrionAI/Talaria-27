# FABLE-T27-137 — Sensor opt-in redesign: kill the post-pair permissions wall

**Item:** OPEN_ITEMS #137. **Branch:** `claude/fable-t27-137-sensor-optin`.
**Why:** public-app posture. Pairing must grant CHAT, nothing else. The all-at-once
`PermissionsOnboardingScreen` after a successful pair (health front and center) torches
adoption of the optional sensor layer at the moment of least trust.

## Scope

1. **Remove `PermissionsOnboardingScreen` from the post-pair flow.** Successful pair pops
   straight to chat (the #71 nav-pop behavior stays; only the permissions interstitial goes).
   Do NOT delete the screen if it's reused as a Settings management surface — discover its
   call sites first and report what you find in the PR description.
2. **New Settings surface: "Sensor Streaming" master opt-in, OFF by default.**
   - Master toggle gates the sensor capture/drain loop (capture side — the upload path stays
     Hermes-gated underneath; the opt-in stacks on top of it, not instead of it).
   - Enabling reveals per-sensor rows (Health, Location, Motion). Each row's enable requests
     OS authorization contextually AT THAT MOMENT — the #69 device-tool-belt pattern: one
     grant, in context, user-driven. No batch prompting.
   - Place it where the existing sensor settings live; follow the established Settings visual
     grammar. The #23 revoke affordances / PRIVACY manage-links must survive unchanged.
3. **Grandfathering migration (non-negotiable).** Existing paired devices already streaming
   sensors migrate with the master toggle ON. One-shot migration: if the device has an active
   pairing AND evidence of prior sensor consent/activity (existing grant state, sensor sync
   preference, non-empty outbox history — pick the most reliable signal in the codebase and
   justify it in the PR), initialize the toggle ON; otherwise OFF. The redesign must not
   silently stop streaming for users who already consented.
4. **HealthKit rules stand:** check `authorizationStatus` before requesting (never
   unconditional re-request); explicit in-app auth request; empty-vs-denied ambiguity stays
   honestly surfaced.

## Interactions to preserve

- Local-brain device tools (#69) request their own contextual grants on first tool use — that
  path is independent of Sensor Streaming and must keep working with the master toggle OFF
  (a local health question still prompts and answers; it just doesn't stream to the relay).
- Unpair/disconnect: leave the opt-in state as-is (it's a device preference, not a pairing
  artifact); re-pair must not re-summon any permissions wall.
- #136 offline-first launch just merged — sensor start is on the local-state-ready critical
  path. The opt-in check must be a fast local read (UserDefaults/store), never a network or
  auth round-trip on the splash path.

## Tests

- Gating: master OFF → capture loop never starts; ON + per-sensor OFF → that sensor idle;
  ON + granted → capture runs.
- Migration: prior-consent device → toggle ON; fresh device → OFF; migration runs once.
- Pair flow: successful pair lands in chat with no permissions interstitial.
- Note the sim HealthKit harness trap: `CODE_SIGNING_ALLOWED=NO` builds strip entitlements —
  do not assert HealthKit auth OUTCOMES in unit/UI tests; test the gating logic around it.

## Constraints (standing)

- File-scoped commits; merge commits only.
- **OPEN_ITEMS.md edits in a SEPARATE commit** — never mixed into feature commits.
- If Swift files are added/removed: `xcodegen generate` in its own commit; re-verify
  `aps-environment: development` survives the regen.
- Real data only — no mock sensor states surfaced to users.

## DoD

- Fresh install → pair → chat, zero permission prompts.
- Settings opt-in produces contextual per-sensor prompts; streaming starts only after opt-in.
- Grandfathered device streams uninterrupted after update.
- Full suite green on current main.
- Device pass (Owen): fresh-install walkthrough + grandfathered-device walkthrough.
