# dispatch(#223): the ZERO-SETUP investigation — can Talaria run on "install Hermes, paste one key"?

**Written 2026-08-02 for a dedicated investigation session (Owen's call: "should we make a
new session and investigate it thoroughly? It'd be awesome if we could eliminate any
additional setup needed. Really takes the scary part out of it for non power users.").**
This is an ARCHITECTURE INVESTIGATION, not a build lane. Its deliverable is a verdict and
a phased, Owen-routable migration plan filed into `OPEN_ITEMS.md` #223 — not code.

Read first: `CLAUDE.md` (standing rules), `OPEN_ITEMS.md` #223 (the consolidation target
and its tenant inventory), #21's 2026-08-02 supersede watch (file-API archaeology), #173's
2026-08-02 probe notes (model-API archaeology), #38 (the push watch), #113 (connector
supervision), #144 (what test pollution did to the relay DB).

---

## The question

Today a full Talaria deployment runs FOUR host-side things: the Hermes gateway (core),
the relay (`:8000`), the models shim (`:8765`), and the connector. The target: **gateway
only** — a non-power-user installs Hermes, pastes `API_SERVER_KEY` into the app, done.
No NSSM, no sidecars, no scary parts.

Chat already speaks gateway-direct. The 2026-08-02 probes established models and files
can too. What actually pins the sidecars is **sensors** and **run-completion push**. The
investigation is whether those two can be re-homed with zero additional host setup —
and at what feature cost.

## What is already established (do NOT re-derive; re-VERIFY where marked)

- **Native model API on `:8642`** — `GET /api/model/info` / `/options` /
  `/recommended-default` / `/auxiliary`, `POST /api/model/set`. `/api/model/options`
  answered **HTTP 200 live on the Mac gateway**, chat-plane Bearer auth, payload carries
  providers + pricing + per-model `capabilities` (`{fast, reasoning}` — no vision key;
  that fix is upstream, see #173). The shim wraps the SAME `build_models_payload` — the
  shim is already redundant in 0.19.1.
- **File API in 0.19.1 code** — `GET /api/files` (+ `/read`, `/download`), upload +
  upload-stream + mkdir + delete, `/api/fs/{list,read-text,write-text,read-data-url,git-root}`,
  `/api/media`. `/api/files/download` is auth-gated (standard middleware + `?token=`
  query variant), path-policied (`_resolve_managed_path`, `locked_root`, sensitive-path
  blocklist), size-capped (`_MANAGED_FILE_MAX_BYTES`). **The Mac's RUNNING process is
  mid-version (models routes 200, files routes 404) — every file-API claim needs
  re-verification on a CURRENT process (OJAMD, or the Mac gateway after a restart).**
- `/api/chat/image-upload` is a dashboard-TUI bridge (stages bytes for the `/image`
  command), NOT a Sessions-API attachment channel.
- **Skills, config, `.env`, and sessions survive `hermes update`; core edits do not.**
  Anything host-side this plan adds must be a skill/config artifact, never a core patch.
- iOS suspends backgrounded apps: **the phone can never HOST a server.** The viable
  direction is deposit-based — the phone pushes data up; host-side logic must be
  process-free (skills) or Apple-side (CloudKit, APNs).

## The architecture hypothesis to test

**Sensors — the deposit model.** The app owns the sensor store on-device and
periodically uploads snapshots/aggregates through the gateway file API. Host-side, a
**Hermes skill** (data, not a process; survives updates) gives the agent query access to
the deposited data. This eliminates the relay AND the connector for sensors. Open
questions: snapshot format (JSON aggregates vs a whole SQLite file), cadence vs battery,
retention split (app-side history vs host-side window), and whether skill-mediated
queries match the quality of today's `hermes_mobile` MCP tools.

**Push — the irreducible sender, four options in preference order:**
1. **CloudKit subscriptions (the zero-setup prize, UNVERIFIED — and Owen's provisional
   pick, 2026-08-02: "if that's an option, we can set it up and just put it in the
   privacy notice").** Apple runs the push sender: the app subscribes to a CloudKit
   record; anything that writes the record via CloudKit Web Services (one signed HTTPS
   call) triggers APNs. IF Hermes has a usable run-completion extension point (hook,
   cron-on-completion, platform delivery — enumerate from `~/.hermes/hermes-agent`
   source on the Mac Mini), the host's entire push infrastructure becomes one outbound
   HTTPS call from a skill/config artifact. No resident process. Verify: entitlement +
   container setup, server-to-server key handling (host-side key, same trust class as
   `API_SERVER_KEY`), and real background delivery reliability.
   **Design rule (Owen-endorsed): PING-ONLY payloads** — the record/notification carries
   "session X finished," never content; the reply stays on the tailnet and the app
   fetches it directly on wake. Same disclosure class as today: #38's relay push
   already transits APNs with a `session_id` payload, so CloudKit changes the SENDER,
   not what Apple carries. Privacy notice discloses iCloud as the notification trigger;
   no airplane-mode caveat needed beyond the universal one (remote push fails without a
   radio for every app; APNs queues and delivers on reconnect).

   **REQUIRED CONTROL (Owen, 2026-08-02): an app-level notifications OFF switch in
   Settings, and OFF means the app NEVER CALLS OUT** — not a display preference. OFF
   disables the entire push path: no CloudKit subscription or record traffic, no watch
   registrations, no push-token enrollment for this purpose (and for coherence, no
   relay watch posts while that path still exists). This is distinct from — and
   stronger than — the iOS notification permission, which only governs display. Owen
   would run OFF himself; the switch is a first-class privacy feature, not an edge
   case. Degrade per #180's conventions: with it OFF, the app states plainly that
   replies arrive on next open. Open product choices for the lane: default state
   (presumably ON with the switch prominent) and whether onboarding surfaces it.
2. **BGTask polling (zero setup, degraded).** The app already has #198's BGTask
   machinery. Measure real-world wake cadence on whoGoesThere before judging it —
   minutes-to-hours, iOS decides.
3. **Platform delivery (zero ADDITIONAL setup).** Hermes cron/platforms already deliver
   to Discord ("one token away" per CLAUDE.md); a run-completion delivered there rides
   Discord's own push. Another app's notification, but free.
4. **A tiny push service — the power-user opt-in, never the requirement.** The relay's
   push role, shrunk to one small supervised service. This is the fallback that keeps
   today's UX for those who want it.

## The verification checklist (the session's actual work)

1. **Current-process probe:** on OJAMD (or a restarted Mac gateway): `/api/model/options`
   → 200? `/api/files` → 200? Both under `API_SERVER_KEY`. The Mac probe script pattern
   is in this repo's session history; OJAMD runs PowerShell (`Invoke-RestMethod`, or
   `curl.exe` — never bare `curl`).
2. **File-API contract:** does `locked_root` cover the agent working dir (`O:\Hermes\`)?
   Can an UPLOAD land where the AGENT can read it (and a skill can find it)? Size cap
   value vs realistic sensor snapshots. Windows path round-tripping.
3. **Skill prototype:** install a throwaway skill that reads a deposited fixture file
   and answer "what was my heart rate yesterday" through the agent. Compare against the
   `hermes_mobile` MCP tools' answers. This is the go/no-go for the deposit model.
4. **Run-completion extension points:** enumerate what Hermes 0.19.x actually offers —
   hooks? cron `on`-triggers? per-run platform delivery? Read the installed source; do
   not trust recall (the never-blame-Apple-first rule generalizes: check before
   declaring "no API exists").
5. **CloudKit spike:** minimal record + subscription + a hand-made Web Services call →
   does the phone wake reliably? (Sim + device.)
6. **BGTask latency baseline:** instrument and measure actual wake cadence over a day.
7. **Pairing collapse:** what does onboarding become in a gateway-only world, and what
   is the migration story for the existing paired install (profiles, keychain, #15/#94
   ladders)?
8. **Transition honesty:** the app must work against BOTH shapes during migration —
   capability-detect per profile, degrade per #180's conventions (visible, stamped,
   never silent).

## Standing constraints (non-negotiable, from CLAUDE.md)

Never patch Hermes core. Owen routes every merge and lane. Bars in writing before any
measured run. `xcodegen generate` after file adds; `DEVELOPER_DIR` export in every
shell; the lane gate before any PR. OPEN_ITEMS numbers ≠ GitHub numbers — always say
which.

## Deliverable

A #223 entry update containing: the verdict per tenant (sensors / push / pairing), the
chosen push option with measured evidence, the phased migration plan (each phase a
routable lane with its blocker named), and the explicit feature trades Owen accepted or
declined. If the deposit model or CloudKit fails, say so plainly — a falsified
hypothesis filed honestly beats a limping architecture.
