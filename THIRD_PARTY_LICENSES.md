# Third-Party Licenses and Attribution

Talaria is MIT licensed (see [LICENSE](LICENSE)). This file records external code
that ships in the app, external work used as reference, and the project's own
origin — three different things that are easy to conflate.

---

## Bundled dependencies

Code that is compiled into or linked by shipping builds.

### WebRTC — `stasel/WebRTC` 130.0.0

- Source: https://github.com/stasel/WebRTC
- Used by: voice mode (real-time speech-to-speech transport)
- Declared in: `project.yml` → `packages.WebRTC`; pinned in `Package.resolved`
- License: the underlying WebRTC project is BSD 3-Clause (Copyright the WebRTC
  project authors), distributed here as prebuilt XCFramework binaries.

> **Owed:** the verbatim BSD notice and patent grant should be copied in here
> from the distributed package rather than paraphrased. BSD 3-Clause requires
> reproducing the copyright notice and disclaimer in binary distributions, so
> this matters before any App Store submission. Tracked in OPEN_ITEMS.

This is currently the only third-party package Talaria links.

---

## Reference and inspiration

Work that informed design or architecture but whose **code is not present** in
this repository. No license obligation attaches to reading a project; these are
recorded as credit.

### Hermex — `uzairansaruzi/hermex` (MIT)

- Source: https://github.com/uzairansaruzi/hermex
- License: MIT
- Author: Uzair Ansar

A native SwiftUI iPhone client for a self-hosted agent. Reviewed 2026-07-22 as
architecture and UX reference for an agent-introspection surface Talaria lacks —
scheduled tasks, a skills browser, a memory panel, usage insights, session
projects, and mid-run steering (see OPEN_ITEMS #156).

Two things worth stating precisely:

1. **Hermex targets a different server.** It is a client for
   `nesquena/hermes-webui`, not `NousResearch/hermes-agent`. The projects share
   the word "Hermes" and nothing else. Its endpoint shapes therefore do not
   transfer to Talaria, and any resemblance in these features is convergent
   design against a similar problem, not shared plumbing.
2. **No Hermex source is used.** If that ever changes — if actual Swift is
   adopted rather than the idea of a screen — this entry must be upgraded to a
   full MIT notice reproducing their copyright and permission text, and the
   affected files annotated. Until then this is attribution, not a license
   obligation.

The `UPSTREAM_TESTED_SHA` convention in this repo was also borrowed from Hermex,
which pins the upstream server commit it is tested against.

---

## Project lineage

Not third-party, and not merely reference — this is where Talaria came from.

### Dylan Buck — original author

Talaria's first commit is Dylan Buck's (`c4e5b36`, 2026-03-31,
"scaffold HermesMobile from template"). He authored the original app shell, the
relay foundation, the connector-based host relay, the iOS pairing flow, and the
initial design system. Substantial portions of the connector and MCP surfaces
descend directly from that work, and his commits remain in this repository's
history.

The MIT `LICENSE` is held by "Hermes iOS Contributors", which includes him. This
section exists because a collective copyright line does not, on its own, tell a
reader who built the foundation — and the git history that does is not the first
thing anyone reads.

The current development line (`AethyrionAI/Talaria-27`, targeting iOS 27) is a
continuation of that lineage, not a separate project.

---

## Not covered here

- Apple system frameworks (FoundationModels, HealthKit, CoreMotion, WeatherKit,
  AlarmKit, AVFoundation, and so on) — used under the Apple Developer Program
  License Agreement, no attribution obligation.
- `NousResearch/hermes-agent` — the server Talaria connects to. It is a separate
  program the user installs and runs themselves; Talaria neither bundles nor
  redistributes it.
