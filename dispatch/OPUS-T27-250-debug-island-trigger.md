# OPUS T27-250 — a Debug-only on-demand Live Activity trigger, so the island bar becomes runnable

**Item:** OPEN_ITEMS **#250** (the one unverified half — 250-E, the Dynamic
Island wearing the selected icon — is device row **§R2**, currently a standing
watch because the island is untriggerable on demand). **Difficulty: OPUS** —
one Debug harness button plus lifecycle hygiene. Ruled at the 2026-08-09
decision pass: *"build the Debug trigger."* Written 2026-08-10.

## 1. Verified state

- **Why R2 has never run:** Owen cannot consistently bring the island up in
  real use; no harness trigger exists. Bars 250-A/B/C are MET and the
  home-screen icon half is confirmed — the island slot is the only
  unverified half, sitting as a watch since filing.
- **The pattern to copy:** the existing Developer-screen harness buttons —
  `DeveloperSettingsScreen.swift:937` (`toollessIndexBatteryButton`) and its
  call sites (`:1997`) are the named precedent.
- **The machinery:** `LiveActivityService`
  (`Talaria/Services/Live/LiveActivityService.swift`) +
  `HermesActivityAttributes` (`Talaria/Models/HermesActivityAttributes.swift`)
  — the real activity the app already starts for runs. The trigger starts a
  THROWAWAY instance of the real attributes, not a parallel mock type
  (real-data rule: R2's check is about what the REAL activity renders).

## 2. Fix shape

A Debug-only button in the Developer screen's harness section: **"Start
throwaway Live Activity (#250 R2)"** — starts a real activity with obviously-
synthetic content (labelled so it can never be mistaken for a real run),
auto-ends after a short window (~60s) AND on a second tap ("End throwaway").
That makes R2 a 2-minute check: tap, look at the island's leading icon slot,
compare against Settings → Appearance → App Icon, done — including the
switch-icon-then-retrigger arm and the cold-launch arm.

## 3. Bars — copy into #250's entry before the run

- **250T-A (unit or compile-level):** the button and its action exist only
  under `#if DEBUG` — and the **Release build is green with them compiled
  out** (the #218 corollary: a green Debug suite cannot see a mis-set gate;
  the gate's Release leg is the proof, not a review read).
- **250T-B (sim):** tapping the button starts an activity through the REAL
  `LiveActivityService` path (asserted via the service's own state, not a
  parallel test double), and it ends both ways (timeout + second tap) — no
  zombie activities surviving the screen.
- **250T-C (device, becomes §R2's run):** with the trigger in a Debug build
  on the phone, R2's actual check runs as written — icon slot matches the
  selected icon, after a switch and on a cold launch. **The verdict lands in
  R2's row (one queue), cited from this lane.**
- **250T-D:** `GATE: PASS`, counts MOVED.

## 4. Traps

- **The trigger is harness, the check is not** — 250T-C's icon verdict is
  R2's to record in `dispatch/DEVICE-PASS-RUNNING-LIST.md`; this lane updates
  that row's "untriggerable" preamble (it becomes runnable) in the same
  commit, per the close-out rule.
- Live Activities have a system budget — the throwaway must `end()` cleanly
  (not rely on dismissal) or repeated harness taps will exhaust the budget
  and make the REAL run activity flaky. That failure would look like a #250
  regression while being the harness's fault — the auto-end is load-bearing,
  not polish.
- `LiveActivityPreviews.swift` exists for SwiftUI previews — do not route the
  trigger through preview scaffolding; it must exercise the production
  service path or 250T-B proves nothing.
- Widget-target code compiles separately — if the attributes type needs any
  change (it should not), remember both `HermesWidgetData` copies rule.

## 5. Owen's to decide

Nothing — the build was ruled 2026-08-09. If the island still declines to
present even with a live activity (an OS-side presentation quirk), that
observation goes to R2's row as a fact about the check, and the trigger still
stands for future island work.
