# FABLE T27 #270 — the desktop face v0: the pane that answers "is it actually installed?"

**Tier that EXECUTES this lane: FABLE.** Written 2026-08-09 from a HEAD read
(`t27-295-expiration-recovery` @ `04af0a7`) plus **read-only** probes of the live
Mac install (`~/.hermes`, gateway PID 19532 on `:8642`). No code was written for
this brief; nothing on the live install was modified.

**Goal:** ship a Hermes Desktop pane for `talaria` that turns "is it actually
installed?" from two app restarts and a guess into a clickable, machine-derived
answer — and that renders a friendly "not installed yet — ask Hermes to set it
up" card when it isn't, making the pane double as #269's upgrade prompt surface.

**Lane is NOT blocked.** Every mechanism it needs exists on disk and is verified
below. But it is **bigger than #251 banked it** (§5) and it needs **one live-install
gate** (§8).

---

## 1. Verified state

### VERIFIED — there are **three** plugin systems, not two

CLAUDE.md's standing memory note ("dashboard pane vs agent `~/.hermes/plugins/`
are separate plugin systems") is right and is the reason this lane exists. It is
also **one system short**. The split is documented in the install's own SDK
reference, `~/.hermes/hermes-agent/website/docs/developer-guide/desktop-plugin-sdk.md:23-33`:

> "The three do not share code, APIs, or delivery. Only the backend
> `plugin_api.py` namespace (`/api/plugins/<id>`) is shared between the desktop
> and dashboard SDKs."

| # | System | Root | Entry point | Host process |
|---|---|---|---|---|
| **A** | Agent plugin (Python) | `~/.hermes/plugins/<name>/` | `plugin.yaml` + `register(ctx)` | CLI / `hermes gateway run` |
| **A2** | **Web-dashboard** half of an agent plugin | `~/.hermes/plugins/<name>/dashboard/` | `manifest.json` → `dist/index.js` (+ `plugin_api.py`) | `web_server.py` SPA, **:9119** |
| **B** | **Desktop** plugin | `~/.hermes/desktop-plugins/<id>/` | `plugin.js` (plain ESM, uncompiled) | Electron renderer |

**`plugin.js` belongs to system B, decisively.** There is no
`~/.hermes/plugins/<name>/dashboard/plugin.js` path anywhere in the codebase —
`rg 'plugin\.js'` across `hermes_cli/` returns only `plugin.json` (the unrelated
Agent Plugins v1 manifest, `hermes_cli/agent_plugins.py:98`). The desktop loader
is explicit: `apps/desktop/src/contrib/runtime-loader.ts:182` — *"The on-disk
plugin door: `<hermes home>/desktop-plugins/<name>/plugin.js`"* — scanned at
`:207-303`, path built at `:271`. Root resolved in the Electron main process at
`apps/desktop/electron/main.ts:11547` (`hermes:fs:desktopPluginsRoot`), profile-aware
at `:11552-11554`.

**So the talaria desktop face is TWO directories in TWO systems**, and this is the
single most load-bearing fact in this brief:

1. `~/.hermes/desktop-plugins/talaria/plugin.js` — the pane (system B).
2. `~/.hermes/plugins/talaria/dashboard/manifest.json` + `plugin_api.py` — the
   backend it calls (system A2, living inside the system-A plugin directory).

### VERIFIED — the backend mount, exactly as #251 banked it

- **Definition:** `hermes_cli/web_server.py:17420` — `_mount_plugin_api_routes`.
- **Runs at module import, not in a startup hook:** `web_server.py:17535`,
  commented *"Mount plugin API routes before the SPA catch-all."*
- **Which app:** the dashboard FastAPI `app` created at `web_server.py:313`.
  **Not** the api_server (`gateway/platforms/api_server.py:151`,
  `DEFAULT_PORT = 8642`).
- **Prefix:** `web_server.py:17518` —
  `app.include_router(router, prefix=f"/api/plugins/{plugin['name']}")`.
- **What a plugin must provide:** a `dashboard/manifest.json` whose `api` key
  names a Python file inside `dashboard/` exporting a module-level `router`.
  `web_server.py:17510` (`router = getattr(mod, "router", None)`); `:17512` warns
  *"Plugin %s api file has no 'router' attribute"*. The filename comes from the
  manifest, not a hardcoded `plugin_api.py`.
- **Discovery:** `_discover_dashboard_plugins()` at `web_server.py:16802`; search
  roots `:16818-16822`; the manifest gate at `:16845-16847` skips any plugin
  directory with no `dashboard/manifest.json`.
- **Path safety:** `_safe_plugin_api_relpath` (`web_server.py:16765`, called
  `:16884`), re-validated before import at `:17489-17495` (GHSA-5qr3-c538-wm9j).
- **`tab.hidden` is real and does what #270's entry says:**
  `web_server.py:16861-16863` sets `tab_info["hidden"] = True`, documented at
  `:16851-16853` as *"register the plugin component/slots without adding a tab"*.

### VERIFIED — the `plugins.enabled` gate already passes for talaria

`web_server.py:17457-17471` refuses to import a `source == "user"` plugin's
backend unless it is in `plugins.enabled` and absent from `plugins.disabled`.
`~/.hermes/config.yaml:736-739` reads `enabled: [honcho, talaria]`,
`disabled: []`. Confirmed live: `hermes plugins list` shows talaria.
`source == "project"` is refused outright (`web_server.py:17472-17479`).

**This is a documented SECURITY BOUNDARY, not a formality** —
`desktop-plugin-sdk.md:527-535` states the desktop Settings → Plugins toggle is
renderer-side and *"does not import Python"*, and cites **GHSA-mcfc-hp25-cjv7**.
Carry that into #269.

### VERIFIED — `hermes serve` is the desktop's backend, and it mounts these routes

- `hermes_cli/subcommands/dashboard.py:136` defines `serve`; default port **9119**
  at `:27`; `:170` sets `headless_backend=True`.
- Module docstring, `dashboard.py:3-5`: *"`dashboard` is the browser web UI;
  `serve` is the same gateway, headless — what the desktop app and remote backends
  run."*
- `HERMES_SERVE_HEADLESS` is consumed **only** by `mount_spa`
  (`web_server.py:16246`) to disable the SPA. `_mount_plugin_api_routes()` runs
  unconditionally at import (`:17535`), triggered by `main.py:10541`'s
  `from hermes_cli.web_server import start_server`. **So headless `serve` still
  serves `/api/plugins/<name>/*`.**
- The desktop app spawns it: `apps/desktop/electron/main.ts:8167` —
  `['--profile', profile, 'serve', '--host', '127.0.0.1', '--port', '0']`
  (second call site `:8418`). Port 0 = ephemeral, announced on stdout (`:8166`).

### VERIFIED by live read-only probe — the phone can NEVER reach this pane's backend

Per CLAUDE.md's rule I did not infer a `:8642` route from a `web_server.py` grep;
I probed the live listener:

```
POST /api/platforms/talaria/events   (bad key, on purpose)  → HTTP 401
POST /api/platforms/nosuchplugin/events                      → HTTP 503
GET  /api/plugins/talaria/board                              → HTTP 404
GET  /api/plugins                                            → HTTP 404
```

`/api/plugins/*` is **404 on `:8642`**, and it is absent from the verified route
table in CLAUDE.md. **#270's pane lives on a plane the iOS app cannot address.**
That is not a defect — it is the correct division of labour — but it means the
pane's answer and the app's answer are two independent verifications of the same
fact, and #269 must not be specced to reuse this route.

### VERIFIED — what does NOT exist yet

- `~/.hermes/plugins/talaria/` has **no `dashboard/`** (contents: `plugin.yaml`,
  `__init__.py`, `admin.py`, `envelope.py`, `outbox.py`, `platform_adapter.py`,
  `store.py`, `tools.py`, `transport.py`, `tests/`, `README.md`).
- `~/.hermes/desktop-plugins/` **exists and is empty** (`drwxr-xr-x`, created
  2026-07-29).
- `/Applications/Hermes.app` is installed; **no `hermes serve` process was
  running** at probe time and there is no `:9119` listener.

### VERIFIED — the templates to copy, all on this disk

- **Agent-facing skill, already installed:** `~/.hermes/skills/hermes-desktop-plugins/`
  — `SKILL.md` + `templates/plugin.js`. Its "How to Run" is the install recipe,
  and its Pitfalls section is the review checklist.
- **The best in-tree template** (the only one with BOTH halves):
  `apps/desktop/src/plugins/kanban/plugin.tsx` — header `:1-10` says it reuses
  `plugins/kanban/dashboard/plugin_api.py` via `ctx.rest`, *"No new backend, no
  core edits"*; wiring at `:87`.
- **Backend template:** `~/.hermes/hermes-agent/plugins/kanban/dashboard/` —
  `manifest.json` (`{name,label,description,icon,version,tab:{path,position},entry,css,api}`),
  `plugin_api.py:57` (`router = APIRouter()`). Second example:
  `plugins/hermes-achievements/dashboard/`.
- **SDK surface:** `ctx` type at `apps/desktop/src/contrib/plugin.ts:59-89`;
  `HermesPlugin` shape `:92-106`; `ctx.rest` → `/api/plugins/<id>` at
  `apps/desktop/src/hermes.ts:305`, WS twin `:339`, traversal-normalizer `:277`.
  Areas: `apps/desktop/src/sdk/index.ts:250` (`PANES_AREA`), `:124`
  (`ROUTES_AREA`, `SIDEBAR_NAV_AREA`), `:123` (`PALETTE_AREA`), `:240`
  (`KEYBINDS_AREA`).
- **Styling contract:** `desktop-plugin-sdk.md:453-459` — theme vars only
  (`var(--ui-text-secondary)`, `var(--ui-stroke-secondary)`, `var(--ui-accent)`),
  never hardcoded colors; restated `:598`, `:658`. This is the same discipline as
  our own `Design.Colors` rule, enforced by a different design system — do not
  import Talaria's palette here.

### VERIFIED — the asymmetry that decides the build order

| half | takes effect | needs a restart? |
|---|---|---|
| `desktop-plugins/talaria/plugin.js` | **hot-reload on save**, within seconds | **No.** `SKILL.md` "How to Run" §2; fallback ⌘K → *Reload desktop plugins* |
| `plugins/talaria/dashboard/plugin_api.py` | at backend import | **Yes** — `web_server.py:17535` is import-time; `desktop-plugin-sdk.md:648-649` says so in the troubleshooting entry for a 404 `ctx.rest` |

**Write the pane first.** The moment `plugin.js` lands the user has a surface that
says "not installed yet"; the backend and its restart follow. This ordering is
what makes the chicken-and-egg card in #251 a feature rather than a workaround.

### ASSUMED — carried into the lane as things to check, not facts

- **The `ctx.rest` auth path under headless desktop-spawned `serve` was not read
  end-to-end.** The kanban backend's docstring (`plugin_api.py:16-28`) asserts
  plugin HTTP routes go through `web_server.auth_middleware` and that an `/events`
  WebSocket needs `?token=`. Not confirmed for the `serve` configuration.
  **Task 1 verifies this before any auth-sensitive field is designed into v0.**
- **The desktop Settings → Plugins toggle vs `config.yaml` interaction.** The docs
  (`desktop-plugin-sdk.md:527-535`) say the gates are independent;
  `plugins-store.ts` was not read.
- **Whether `/Applications/Hermes.app` was built from this checkout is unknown.**
  `~/.hermes/desktop-build-stamp.json` exists and was not read. Every SDK claim
  above comes from the source tree; if the shipped app is older, the SDK surface
  may differ. **Task 1 resolves this and it gates the lane.**
- `SKILL.md` contradicts itself on reloads — "How to Run" §2 says the directory is
  watched and *"No reload step"*; "Procedure" §5 says *"ask the user to run Reload
  desktop plugins"*. Treat hot-reload as unproven until observed (bar **270-A**).

---

## 2. The goal — what a user sees when it ships

Owen opens Hermes Desktop and finds a **Talaria** pane. It shows one of exactly
three states, and it is never wrong about which:

- **Not installed** — a card: *"Talaria isn't set up on this machine yet. Ask
  Hermes to install it."* This is the state that productizes the confusion; it is
  also #269's prompt surface.
- **Installed but not live** — the plugin is on disk and enabled, but the backend
  hasn't been restarted, or the gateway has no adapter. The card says which, and
  says what to do.
- **Live** — plugin name, version, and the paired devices with their last-seen
  times. The question in the pane's name gets a clickable answer.

The failure that created this lane — two Hermes Desktop restarts hunting for
`talaria` in the one pane that **cannot** show it by design — becomes impossible,
because now there is a pane that can.

---

## 3. ⚠️ Tracker corrections

Corrections go UPSTREAM to the stale claim's own home (THE CLOSE-OUT RULE). Three
of these belong in **#270's entry**, one in **CLAUDE.md's memory note**, one in
**#251's Phase 2 block**. **I edited nothing** — the orchestrator files them.

1. **#270 and #251's "two of everything" is three of everything.** Both entries
   frame the split as desktop pane vs agent plugin. The install documents a third:
   the **web-dashboard half** of an agent plugin (`~/.hermes/plugins/<n>/dashboard/`,
   `manifest.json` → `dist/index.js`, served at `web_server.py:17332` under
   `/dashboard-plugins/`). It matters here because talaria's backend lives in the
   dashboard tree while its pane lives in the desktop tree — a lane that thinks
   there are two systems will put both halves in one directory and get a 404.
   → correct **#270's "Carry into the lane"** bullet and the **CLAUDE.md memory
   note** `hermes-two-web-apps.md`.

2. **#270's mechanism sentence reads as one path; it is two trees.** The entry's
   *"desktop `plugin.js` (SDK: PANES/ROUTES/SIDEBAR areas, theme vars, `ctx.rest`)
   → `/api/plugins/talaria/…` → FastAPI `router` in `plugins/talaria/dashboard/plugin_api.py`"*
   is **correct in every clause** and verified above — but it omits that the
   left-hand side lives in `~/.hermes/desktop-plugins/talaria/`, not in
   `plugins/talaria/`. Add the path. → **#270**.

3. **The `hermes serve` double-cron-ticker hazard is NOT introduced by this
   slice.** #270's entry carries it as a thing "the face must account for", and
   the #251 update at OPEN_ITEMS.md:8778-8783 calls it a hazard "for the
   desktop-face slice (#270)". But the desktop app spawns `hermes serve --port 0`
   **whenever it runs** (`main.ts:8167`), pane or no pane. The second ticker
   exists the moment Owen opens Hermes.app. **2C neither creates nor worsens it**;
   it inherits an ambient condition. The correct carry is: *v0 must not write
   cron-adjacent state* (which it won't — it is read-only), and the ticker itself
   is a separate finding that should not be scored against this lane's bars.
   → correct **#270** and the **#251 update at :8778**.

4. **#251's Phase 1 note "the running gateway sees the plugin at its next
   restart" understates the current state.** The agent plugin is loaded now
   (`talaria` answers 401 on its events route, i.e. the adapter is registered),
   but a `dashboard/` added later will need a *backend* restart that is a
   different process from the gateway — the desktop-spawned `serve`. Two restart
   surfaces, not one. → note in **#251's Phase 2 block**.

5. **Nothing in #270's entry was falsified.** Its recon held up line-for-line
   against the source, including `tab.hidden` and the `plugins.enabled` mount
   gate. Record that: #251's 2026-08-05 recon was accurate, and this lane starts
   from evidence rather than re-derivation, exactly as the entry asked.

---

## 4. Scope ruling

**One lane — but roughly twice what #251 banked, and the difference is real work,
not padding.**

#251 banked "the `plugin.js` pane". The shippable unit is:

- a **desktop ESM plugin** (system B) — new tree, new SDK, new styling contract;
- a **FastAPI backend** (system A2) — new `dashboard/` subtree in the plugin repo,
  new manifest, and a route surface that must not leak device tokens;
- a **state model** that can distinguish *not installed* / *installed-not-live* /
  *live* — which is the actual product, and which is shared vocabulary with #269.

It is still one lane because all three land in one repo pair with one reviewer and
one demo. It is **not** a "write a pane" afternoon.

**Two things keep it from growing further, and they should be enforced:**

- **v0 is READ-ONLY.** No install buttons, no enable toggles, no unpair. #251 is
  explicit — *"NOT an installer, but the verification layer of the install
  story"*. The moment the pane can mutate, it needs an auth review it does not
  need today.
- **`paired-devices + outbox columns` is the GROWTH path, not v0.** #251 says
  v0 "grows" those. Keep the outbox column out of the bars; a device list is
  already enough to answer the pane's question.

**Sequencing:** #270 can start **before, during, or after #269** — the halves are
independent trees. But the pane's three-state vocabulary should be settled first
because #269's chat wording must agree with it (§9).

---

## 5. Proposed bars

Pre-registered here in full **for the orchestrator to file into #270's entry
before any code is written** (CLAUDE.md, "Where the BARS live"). A missed bar is a
falsification, not a redefinition. **I did not edit `OPEN_ITEMS.md`.**

- **270-A (the pane exists, and hot-reload is real).** With `plugin.js` written to
  `~/.hermes/desktop-plugins/talaria/`, a Talaria pane appears in Hermes Desktop
  **without restarting the app**, and a subsequent save re-renders it. No "Plugin
  talaria failed to load" toast.
  *Evidence:* screenshot of the pane + screenshot after an edited save.
  **LIVE HOST (Mac) + Hermes.app running. No device.**
  *Falsifies:* the `SKILL.md` self-contradiction (§1 ASSUMED). If a ⌘K reload is
  required, the bar is MISSED and the fact is recorded — do not restate the bar.

- **270-B (the not-installed card is the DEFAULT, not a fallback).** With
  `plugin.js` present and **no** `~/.hermes/plugins/talaria/dashboard/`, the pane
  renders the "not installed yet — ask Hermes to set it up" card. It must reach
  that state from a `ctx.rest` 404, not from a hardcoded default: with the backend
  later present, the same code path must show *live*.
  *Evidence:* two screenshots from one unedited `plugin.js`, plus the 404 in the
  backend log.
  **LIVE HOST. No device.**

- **270-C (three states, each machine-derived).** The pane distinguishes
  *not installed* / *installed-not-live* / *live*, and each verdict traces to a
  distinct observable — respectively a `ctx.rest` 404, a 200 whose payload reports
  no registered platform adapter, and a 200 with an adapter plus ≥1 device.
  **No state may be inferred from the absence of another.**
  *Evidence:* a table in the close-out mapping each rendered state to the exact
  HTTP status + payload field that produced it.
  **LIVE HOST. No device.**
  *This is the bar the lane is actually for.* #180's honest-degradation family:
  the pane must never render "live" off a hopeful default.

- **270-D (the backend restart requirement is DEMONSTRATED, not assumed).**
  Adding `dashboard/plugin_api.py` while the desktop backend is running leaves
  `ctx.rest` 404ing; the pane shows *not installed*; after the backend restarts,
  the same pane shows *live* with no `plugin.js` edit.
  *Evidence:* timestamped before/after, plus `~/.hermes/logs/errors.log` checked
  for `Failed to load plugin talaria API routes`.
  **LIVE HOST. 🔐 GATE — see §7.**

- **270-E (no secrets on the wire, and no theme crimes).** The
  `/api/plugins/talaria/*` responses contain **no device tokens and no API key** —
  device rows expose id, name, active flag, last-seen only (`store.py` hashes
  tokens; the pane must not undo that). And `plugin.js` contains zero hardcoded
  colors: every color is a `var(--ui-*)`.
  *Evidence:* the recorded JSON response body, plus
  `rg -n '#[0-9a-fA-F]{3,6}|rgb\(|rgba\(|\bblack\b|\bwhite\b' plugin.js` → no hits.
  **LIVE HOST for the body; the grep is offline.**

- **270-F (the plugin repo's suite stays green, and the app's gate is untouched).**
  `~/.hermes/plugins/talaria`'s own pytest suite passes with the new
  `dashboard/` present (it was 60/60 in the #263 worktree), and **no Talaria-27
  Swift file changes in this lane** — so `scripts/mac/lane-gate.sh` is *not*
  required and must not be claimed as evidence.
  *Evidence:* pytest output with the count stated. **Offline.**
  *Rationale:* stating this up front prevents the reflex of running the app gate
  and reporting a green suite that proves nothing about this lane — the
  `xcodebuild-beta4-stale-incrementals` family of false green.

**Deliberately NOT bars** (so the lane cannot quietly grow into them): the outbox
column; any mutating control; the web-dashboard (`:9119`) tab; OJAMD (that is
#271).

---

## 6. Task breakdown

Real paths. Plugin work happens in the **`talaria-plugin` repo**, not in
Talaria-27. Follow #263's precedent and develop in a worktree
(`~/Documents/Claude/t27-263-plugin/talaria` was that lane's) rather than editing
`~/.hermes/plugins/talaria` in place — the clone IS the install, so an in-place
edit is a live-install modification.

**Task 1 — resolve the two blocking ASSUMEDs (read-only, no gate).**
Read `~/.hermes/desktop-build-stamp.json` and confirm `/Applications/Hermes.app`
matches the `~/.hermes/hermes-agent` checkout the SDK claims come from. Read
`web_server.auth_middleware` and confirm whether it covers `/api/plugins/*` under
headless `serve`. **If the shipped app predates the SDK surface, STOP and report —
the whole lane is written against source that isn't running.**

**Task 2 — the state model, on paper, before any code.**
Write the three states and the exact observable that produces each (bar 270-C's
table, filled in as a design, then verified). Settle the *wording* here, because
#269's chat prose must agree with it (§9).

**Task 3 — `dashboard/manifest.json`.**
New: `~/.hermes/plugins/talaria/dashboard/manifest.json`, modelled on
`~/.hermes/hermes-agent/plugins/kanban/dashboard/manifest.json`.
`{"name": "talaria", "api": "plugin_api.py", ...}` — `name` **must** equal
`plugin.yaml`'s `name` and the desktop `plugin.id`, because the mount prefix is
`plugin['name']` (`web_server.py:17518`). Set `tab.hidden: true`
(`web_server.py:16861`) so the web dashboard stays clean — v0 is a desktop
surface only.

**Task 4 — `dashboard/plugin_api.py`.**
Exports a module-level `router = APIRouter()` (`web_server.py:17510` requires the
attribute by that name). One route is enough for v0 — a status route that returns
the plugin version from `plugin.yaml`, whether the platform adapter is registered,
and the device rows from `store.devices()` **with tokens excluded** (270-E). It
runs inside the backend process, so it may import from the plugin package
directly. Reuse `admin.py`'s existing status logic rather than re-deriving it —
and note `admin.py:_print_transport_counters` already documents the
in-process-counters trap: the *backend* process is not the *gateway* process, so
transport counters read from here will be zeros. **Do not render those zeros as a
health signal in v0.**

**Task 5 — `plugin.js`.**
New: `~/.hermes/desktop-plugins/talaria/plugin.js`. Start from
`~/.hermes/skills/hermes-desktop-plugins/templates/plugin.js`; use
`apps/desktop/src/plugins/kanban/plugin.tsx` as the both-halves reference.
Constraints from `desktop-plugin-sdk.md` and the skill's Pitfalls: `jsx()` calls
only (no JSX syntax — the file loads uncompiled); imports limited to
`@hermes/plugin-sdk`, `react`, `react/jsx-runtime`; `useQuery` with a
`refetchInterval` of a few seconds, never a hand-rolled poll loop; every
identifier used in a `jsx()` call must appear in the import line; theme vars only.
Register `area: PANES_AREA` with a `placement` hint.

**Task 6 — wire and observe (🔐 GATE, §7).**
Install both halves onto the live Mac install, restart the desktop backend, walk
the three states, capture the evidence for 270-A…E.

**Task 7 — close out.**
Results into #270 against the filed bars; corrections from §3 into their upstream
homes in the **same commit**.

---

## 7. 🔐 GATE — THIS LANE REQUIRES A LIVE-INSTALL MODIFICATION

**TASKS 6 AND ANY IN-PLACE EDIT OF `~/.hermes/plugins/talaria` NEED OWEN'S
EXPLICIT PER-EXPERIMENT GO.** Under CLAUDE.md's standing rule, read-only probes
and throwaway loopback servers are free; **this is neither.** Specifically gated:

- **WRITING `~/.hermes/desktop-plugins/talaria/plugin.js`** — a new file into a
  live `$HERMES_HOME`, auto-loaded by the desktop app on landing.
- **WRITING `~/.hermes/plugins/talaria/dashboard/`** — new files inside the live
  agent-plugin install, imported into the backend process.
- **RESTARTING THE DESKTOP-SPAWNED BACKEND** (bar 270-D) — a restart performed *to
  load experimental code* is part of the experiment and rides the same gate, even
  though Mac gateway restarts are otherwise routine.

The 2026-08-06 time-boxed clearance ("you are cleared for modifications,
especially if you're removing it afterwards") **expired with that day**. Do not
cite it.

The gate is cheap to satisfy and the ask is small: one sitting, both halves, with
a clean removal path (`rm -rf ~/.hermes/desktop-plugins/talaria` and the
`dashboard/` subtree; neither touches `config.yaml`, since talaria is already
enabled). State the removal path when asking.

---

## 8. What is OWEN'S to decide

1. **The gate in §7.** One go, covering Tasks 6 and the in-place writes.
2. **Does the pane ship in the `talaria-plugin` repo, and does that repo go
   public?** It is **private** today (`gh repo view AethyrionAI/talaria-plugin` →
   `isPrivate: true`). Private is fine for a desktop face Owen installs by hand;
   it is **fatal to #269** (see that dispatch). If the answer is "public
   eventually", the pane's copy should not assume a private-repo install path.
3. **Pane or full page?** v0 as a `PANES_AREA` pane is the smallest thing that
   answers the question. `ROUTES_AREA` + `SIDEBAR_NAV_AREA` would give Talaria a
   sidebar row — more presence, more surface. #251 says "pane"; confirm before
   Task 5, because it changes the SDK areas used.
4. **The three state names, as user-visible strings.** They are the product here
   and they must match #269's chat wording. Proposed:
   **NOT INSTALLED · INSTALLED, NOT LIVE · LIVE**.
5. **Whether v0 shows device rows at all.** It is the difference between "the
   plugin is here" and "the plugin is here and your phone is on it". Recommend
   yes — it is the honest answer to the pane's own question — but it puts device
   names on a desktop screen, which is a privacy call, not an engineering one.

---

## 9. Traps and interactions

- **#263(a), the split hub — mostly NOT this lane's trap, and that matters.**
  (a) as filed was **FALSIFIED** (OPEN_ITEMS.md:7364-7375): the loader replaces
  only the parent package object, submodules stay cached, and 8 forced
  `discover_and_load(force=True)` passes held every HUB id. It survives as a
  WATCH. But the split **shape** is real via two recorded routes, and **route (1)
  is manifest-name divergence** (`plugins.py:1874-1876` — the slug comes from the
  manifest key, so one directory loaded under two names yields two HUBs). **Task 3
  writes a new manifest with a `name` field.** Get it wrong and you have
  hand-built the #263(a) shape. `dashboard/manifest.json`'s `name`,
  `plugin.yaml`'s `name`, the directory name, and the desktop `plugin.id` must
  **all** be `talaria`. Call this out in review.
- **#263(b) is FIXED and irrelevant here** — the cross-loop wake landed
  (`83525ac` in the plugin repo). The pane does not touch the transport. Do not
  re-litigate it, and do not use transport counters as a pane health signal
  (Task 4).
- **#264, the bind race — applies to the *backend* restart, in a mutated form.**
  The ops rule is "after ANY gateway bounce verify the LISTENER, never the
  process." Here the backend is `serve --port 0`, an *ephemeral* port announced on
  stdout (`main.ts:8166`), so there is no fixed port to `lsof`. **The equivalent
  check is a successful `ctx.rest` round-trip**, not a healthy Electron child PID.
  Bar 270-D is written to force exactly that.
- **#264's app-side consequence is the design precedent for 270-C.** OPEN_ITEMS.md:7258-7260 —
  *"the Server screen must not show PLUGIN LINK as PAIRED-and-healthy while chat is
  refusing — both facts come through the same door, so it is one banner and one
  truth."* The pane inherits that discipline: **one truth, machine-derived.**
- **#113 is CLOSED (archived 2026-07-25) — do not cite it as a live supervision
  gap.** Its surviving half is **#188** (OPEN_ITEMS.md:4647-4667), and #188's
  watchdog half was **DECLINED** under the no-hardening rule. Neither touches this
  lane: the pane observes, it does not supervise.
- **⛔ THE RELAY-HARDENING RULE — this lane is clean, and here is the argument.**
  The pane adds **zero** relay or connector surface. It is on the DELETION side of
  the ledger: it is a piece of the plugin venture (#251) whose Phase 4 is relay
  decommission. If a task ever appears to need a relay change to make the pane
  honest, that is the signal to stop and raise it with Owen as a decision, not to
  build it.
- **THE TWO-OF-EVERYTHING RULE, in its sharpest form for this lane.** Three route
  planes are in play and it is easy to mix them: `:8642` api_server (the phone —
  and `/api/plugins/*` is **404** there, probed), `:9119` `web_server` /
  desktop-spawned ephemeral `serve` (the pane), and the desktop renderer's own
  in-process SDK. **Never claim a `:8642` route from a `web_server.py` grep.**
- **#269 interaction — the pane is the other half of the same product.** #269's
  installer is what makes the "not installed" card actionable, and this pane is
  what makes #269's "Done!" verifiable to a human eye. **They must use the same
  three words for the same three states** (§8.4). Ship whichever first, but
  settle the vocabulary once.

---

## 10. Close-out

This lane closes when:

1. **Bars 270-A…F have written verdicts in #270's entry**, each MET or MISSED
   against the text filed *before* the build. A MISSED bar is recorded as a
   falsification and kept, not reworded.
2. **The §3 corrections land UPSTREAM in the same commit** — #270's entry (items
   1–3, 5), #251's Phase 2 block and its :8778 update (items 3–4), and the
   `hermes-two-web-apps.md` memory note (item 1). THE CLOSE-OUT RULE: a lane does
   not close until every line its result falsifies is corrected at the stale
   claim's own home.
3. **The live install is verified clean or verified intentional** — after the
   §7 gate, state which files remain in `~/.hermes/desktop-plugins/` and
   `~/.hermes/plugins/talaria/dashboard/`, and confirm `config.yaml` is unchanged
   (it should be — talaria is already enabled). Follow #251's own precedent for
   this: git status on the plugin repo, diff against `origin/main`, and a
   listener/round-trip check.
4. **The three state names are recorded as the shared vocabulary for #269**, so
   that lane starts from a decided word list rather than inventing its own.
5. **The plugin repo's pytest count is stated and moved** if tests were added —
   an unchanged count after adding tests is the stale-artifact tell.
