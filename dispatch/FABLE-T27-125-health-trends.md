# FABLE T27-125 — Health trends view (native, on-device)

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-125-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #125 (new) · **Size:** one PR, medium
**Baseline:** 755/62 · **Toolchain:** Xcode-beta3.

## Why

The app already collects the data (HealthKit auth granted, `LiveHealthService`
querying 12+ metric kinds) and just merged the render surface (#100:
`ChartSegmentView`, themed Swift Charts). Trends = queries + the existing
chart pipeline, zero server round-trip. This is the free-tier flagship
screen — the App Store screenshot — and it composes with the connected tier
(Hermes commentary on the same data) later.

## The build

1. `HealthTrendsService` (protocol + live + mock): HKStatisticsCollectionQuery
   per metric — daily buckets over 7/30/90-day windows for: resting HR, HRV
   (if authorized), steps, sleep duration, active calories, respiratory rate.
   **Read the authorized-set from the EXISTING auth surface in
   `LiveHealthService` — do not request new HealthKit scopes in this lane;
   render only what's already granted, hide the rest.** Queries off-main;
   results as plain value structs (date, value) — testable without HealthKit.
2. Screen: `Talaria/Features/Health/HealthTrendsScreen.swift` — metric cards,
   each rendering through the #100 chart path (`ChartSpec` → the same view
   ChartSegmentView uses, or a thin shared wrapper — REUSE, do not fork a
   second chart implementation; if ChartSegmentView needs a param to be
   reusable outside a message bubble, that small refactor belongs here).
   Range picker 7/30/90. Empty metric → card hidden (honest absence, house
   rule). Entry point: wherever the health tiles / widget-adjacent surface
   lives today — one navigation link, no tab-bar redesign.
3. Theming through `Design.Colors` exclusively (the #100 rule); VoiceOver
   label per card (metric, range, latest value, trend direction).
4. Trend annotation: a simple 7-day-vs-prior delta ("↑ 4%") computed in a pure
   function — no FoundationModels calls in this lane (LLM commentary is a
   future connected-tier rider; note it, don't build it).

## Tests

Bucketing/windowing math pure + tested (DST boundaries, sparse days, empty);
delta computation; spec-construction from sample series (feeds the #100
tolerance path — over-500-point windows must downsample BEFORE ChartSpec's
budget, tested).

## Constraints & acceptance

- No new HealthKit scopes, no Info.plist changes, no server calls. Regen on
  file add (separate commit, aps-environment verified). Suite ≥ 755/62.
- Device check (PR body): trends screen shows real 30-day resting HR/steps
  matching the Health app's shape; unauthorized metrics absent not empty;
  Midnight Marquee theme check; VoiceOver reads a card sensibly.
