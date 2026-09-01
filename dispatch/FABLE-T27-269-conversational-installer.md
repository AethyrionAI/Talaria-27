# FABLE T27 #269 — the conversational installer: the agent installs its own plugin

**Tier that EXECUTES this lane: FABLE.** Written 2026-08-09 from a HEAD read
(`t27-295-expiration-recovery` @ `04af0a7`) plus **read-only** probes of the live
Mac install (`~/.hermes`, gateway PID 19532 on `:8642`). No code was written for
this brief; nothing on the live install was modified.

**Goal:** the user connects Talaria to Hermes, the app sends a setup prompt, and
the agent — which has hands on its own host — installs and enables the `talaria`
plugin itself. The user never opens a terminal, and the app **verifies the result
by machine**, never by believing the word "Done!".

---

## ⛔ LEAD FINDING — THIS LANE IS PARTIALLY BLOCKED, AND SPLITTING IT IS THE RESULT

Two blockers are real, verified, and neither is fixable inside this lane:

**BLOCKER 1 — the plugin repo is PRIVATE.** `hermes plugins install` accepts a
git identifier and nothing else, and clones with `stdin=DEVNULL` +
`noninteractive_git_env()` (`hermes_cli/plugins_cmd.py:485-492`). Live probe:
`gh repo view AethyrionAI/talaria-plugin --json isPrivate` → **`{"isPrivate": true}`**.
**A user's Hermes cannot clone it.** Not slowly, not with a prompt — the clone
fails with no interactive credential path. Every word of the conversational
install story is unreachable until Owen decides the distribution question (§8.1).

**BLOCKER 2 — there is no reload, so the install cannot complete inside the turn
that performs it.** `discover_and_load` early-returns on `self._discovered`
(`hermes_cli/plugins.py:1341-1349`); the manager is a process-global singleton
(`plugins.py:2264-2272`); there is **no watcher, no SIGHUP→rediscover, and
`force=True` has exactly one non-test call site** (`hermes_cli/main.py:10135`, the
dashboard basic-auth password path — unrelated). The gateway runs the agent
**in-process** (`gateway/run.py:4922`), so "next session" does not re-run
discovery either. **The last step of an install is restarting the process the
agent is running inside.** An agent cannot narrate its own success across that
boundary.

**So the lane splits, and the split is the honest answer:**

| | scope | blocked? |
|---|---|---|
| **269-A — the honest verification half** | the app's machine-verifiable install-state probe + the honest state model + retiring the app's stale terminal-command card | **NO. Buildable today, zero live-install changes, valuable on its own.** |
| **269-B — the conversational install itself** | the app's first-contact prompt, the agent-side skill, the consent + restart choreography | **YES — on Blocker 1 (Owen's call) and on a decided restart story (§4).** |

**Recommendation: open 269-A now, hold 269-B for Owen's ruling.** 269-A is
precisely the sharpening the 2026-08-07 momentum report asked for, it is what
stops the app rendering 👍 off prose, and it is a prerequisite for 269-B rather
than a consolation prize — 269-B has nothing to verify with until 269-A exists.

**One good piece of news, verified:** the #263 reload trap the parent brief asked
about **does not block this lane** (§9.1) — and it is dodged by the very
limitation that creates Blocker 2.

---

## 1. Verified state

### VERIFIED — what "installing a plugin" mechanically IS today

Three steps, no more:

1. **Clone.** `_install_plugin_core()` — `hermes_cli/plugins_cmd.py:462-581`.
   `git clone --depth 1` into a temp dir (`:485-492`, 60s timeout), manifest read
   (`plugin.yaml`/`.yml` native, `plugin.json` portable, `:512-530`),
   `manifest_version` ceiling `_SUPPORTED_MANIFEST_VERSION = 1` (`:73`, `:540-556`),
   then `shutil.move` into **`~/.hermes/plugins/<manifest-name>/`** (`:536`, `:566`).
   Target dir resolved by `_plugins_dir()` (`:76-80`), traversal-guarded (`:83-137`).
2. **Enable.** Append the name to `plugins.enabled` in `~/.hermes/config.yaml`.
   `cmd_install` `:636-655` (tri-state `--enable`/`--no-enable`/prompt, **defaulting
   to False on a non-TTY**, `:646-647`); `cmd_enable` `:880-938`; writers
   `_save_enabled_set()` `:802-809`, `_save_disabled_set()` `:747-754`.
3. **Restart the gateway.** Nothing else makes it load. `cmd_install` prints it
   verbatim at `plugins_cmd.py:665-666`: *"Restart the gateway for the plugin to
   take effect: hermes gateway restart"*.

**CLI surface, verified** (`hermes_cli/subcommands/plugins.py:24-108`, confirmed by
running `hermes plugins --help` read-only): `install`, `update`, `remove`/`rm`/`uninstall`,
`list`/`ls`, `enable`, `disable`. **There is no `reload` subcommand, no `search`,
and no install-by-name from a registry** — the hub is dashboard-only
(`web_server.py:17186`).

`install` accepts **git only** — `_resolve_git_url()` `plugins_cmd.py:154-218`.
`owner/repo` shorthand expands to `https://github.com/{owner}/{repo}.git` (`:211`).
A bare local directory path is **rejected** (`:214` raises `ValueError`); a local
install requires `file:///abs/path` pointing at a real git repo (`:604-608` warns).

### VERIFIED — the agent DOES have the hands, and the gaps are exactly two

Built-in tools (`tools/registry.py`, `ToolRegistry` at `:414`):

| tool | registered | toolset |
|---|---|---|
| `read_file` | `tools/file_tools.py:2617` | `file` |
| `write_file` | `tools/file_tools.py:2618` | `file` |
| `patch` | `tools/file_tools.py:2619` | `file` |
| `terminal` | `tools/terminal_tool.py:3614-3622` | `terminal` |
| `execute_code` | `tools/code_execution_tool.py:2066-2078` | `code_execution` |

**There is no `run_command`, `bash`, `shell`, or `execute` tool.** The shell tool
is named **`terminal`** — any prompt or skill that names another one will fail.

**Gap (a) — the agent cannot write `config.yaml`.** `write_file`/`patch` refuse it
**unconditionally**, `tools/file_tools.py:692-702`, with the rationale in the code:

> *"approvals.mode and other security settings live here; a malicious or
> prompt-injected agent could silently disable exec approval by writing to this
> file."*

So the enable step **must** shell out to `hermes plugins enable <name>` — the
subprocess writes the config via `save_config()`. That is the sanctioned path, not
a workaround, and the split is deliberate: a reviewed CLI mutates the security
file, the agent's raw file tool cannot.

**Gap (b) — no reload.** Blocker 2 above.

Writing into `~/.hermes/plugins/<name>/` is otherwise unrestricted: it is neither
a sensitive path nor a protected instruction file — `file_tools.py:809-812`
explicitly exempts everything under `~/.hermes/` from the `AGENTS.md`/`CLAUDE.md`
protection family.

### VERIFIED — the consent moment already exists in Hermes, and it is OFF on this box

Approvals: `tools/approval.py`. Config read `_get_approval_config()` `:2917-2928`;
decision path `check_dangerous_command()` `:3416`; order = hardline blocklist →
`approvals.deny` user rules (`:542`, applied `:3776-3780`) → **bypass** (`:3784-3786`)
→ permanent allowlist (`:3788`) → prompt. Bypass predicate
`is_approval_bypass_active_for_session()` `:2937-2955` (`--yolo`, session `/yolo`,
or `approvals.mode == "off"`).

`hermes gateway stop|restart` is a DANGEROUS_PATTERN (`approval.py:791`), so on a
default install the restart step **prompts the user in chat by itself** — which is
exactly the consent surface #251 wanted, arriving free.

**But this Mac reads `approvals: {mode: 'off', ...}` (`~/.hermes/config.yaml:516-525`).**
On this box the agent shells out with **no prompt at all**. Two consequences the
lane must hold:

- **We cannot dogfood the consent moment on this machine as configured.** Testing
  269-B's consent here proves nothing about a user's experience — it is the
  `#215` shape (measuring a configuration production never enters).
- **The app's prompt must never be the only consent.** On a `mode: off` host,
  an app-authored prompt would drive a silent install. The app asks *its* user
  before sending; Hermes asks *its* user before executing. Neither substitutes.

There is also a **verified probe CLI** worth using rather than guessing:
`hermes approvals test [-- <cmd>]` (`hermes_cli/subcommands/approvals.py:79-113`)
dry-runs the real guards without executing — exit 0 allow / 2 ask / 3 deny.

### VERIFIED — restart mechanisms exist; none of them is an agent tool

- **CLI:** `hermes gateway restart` — parser `hermes_cli/subcommands/gateway.py:130-144`;
  dispatch `hermes_cli/gateway.py:6740`, `:6780-6796`.
- **Self-restart signal:** `SIGUSR1` → `runner.request_restart(...)`,
  `gateway/run.py:27427-27428` (`request_restart` defined `:10315`); senders
  `hermes_cli/gateway.py:242-252`, `:255-286`.
- **HTTP:** `POST /api/gateway/restart` — `hermes_cli/web_server.py:4038-4052`.
- **Slash command:** `/restart` — `gateway/slash_commands.py:1524`, gated by
  `approvals.destructive_slash_confirm` (currently `true`, config.yaml:521).

**No tool named `gateway_restart` is in the registry.** The only agent-reachable
route is `terminal` running `hermes gateway restart` — i.e. the agent kills its own
process. Blocker 2, stated as a mechanism.

### VERIFIED — a machine-verifiable install probe EXISTS TODAY, with zero plugin changes

Per CLAUDE.md I did not infer a `:8642` route from a grep. I probed the live
listener, read-only, with a deliberately invalid key so the request dies at the
adapter's verifier before any state change:

```
POST /api/platforms/talaria/events        (bad key)  → HTTP 401   ← adapter REGISTERED
POST /api/platforms/nosuchplugin/events   (bad key)  → HTTP 503   ← adapter ABSENT
                                                       {"code": "platform_unavailable"}
GET  /api/plugins/talaria/board                      → HTTP 404
GET  /api/plugins                                    → HTTP 404
```

The mechanism, read at `gateway/platforms/api_server.py`: route registered at
`:2073`; handler `_handle_platform_event_callback` at `:1869`; a missing adapter
returns **503 `platform_unavailable`** via `_get_platform_callback_adapter`
(`:1876-1890` region); a present adapter delegates to
`verify_http_event_request`, and a bad credential returns **401**.

**So `401 ≠ 503` is a real, deterministic, already-shipping installation-state
signal.** 269-A can be built without touching the plugin at all.

**And `/api/plugins/*` is 404 on `:8642`** — so **#270's desktop pane and this
lane's probe are on different planes**, and 269-A must not be specced against the
pane's route. (That plane is the dashboard/`hermes serve` one; see the #270
dispatch.)

### VERIFIED — the envelope is where richer verification belongs

`~/.hermes/plugins/talaria/envelope.py:97-109` — `dispatch()` handles exactly five
verbs: `pair`, `drain`, `ack`, `query_result`, `unpair`. Unknown → `unknown_event_type`.

`verify()` at `:66-75` accepts **either** the gateway `API_SERVER_KEY` **or** a
stored device token. That is the load-bearing detail for 269-A: **the app can
authenticate a pre-pair capability probe with the API key it already holds from
the existing handshake** — no new credential, no new route.

A `describe` verb returning `{plugin, version, protocol_version, capabilities,
installation_state}` is therefore a **six-line addition to an existing dispatch
table**, not a new endpoint. This is what the tracker's own 2026-08-07 update
meant by *"Rides the existing authenticated plugin surface … not a new endpoint
invented for it"* — and it supersedes the momentum report's sketch (§3.3).

### VERIFIED — the app ships the exact onboarding #269 exists to abolish

`Talaria/Features/Settings/ConnectHermesHostScreen.swift:100-115` renders a card
headed **SETUP** with a `terminal` SF Symbol (`:103`) and three literal commands
(`:110-112`):

```
1  hermes-mobile setup           "One-time registration"
2  hermes-mobile pair-phone      "Scan the code in-app"
3  hermes-mobile service install  "Background uptime"
```

**This is doubly stale.** It is the "just run one command" story Owen said *"fails
the actual audience on contact"*, **and** `hermes-mobile` is the legacy venv CLI
family that #251 Phase 1 says the plugin **deletes** (replaced by
`hermes talaria pair|status|unpair`, `~/.hermes/plugins/talaria/admin.py`). A user
following this card today runs commands that the venture has retired.

**Retiring this card is the smallest honest win in the whole lane**, it is inside
269-A, and it does not depend on either blocker.

### VERIFIED — the app's PLUGIN LINK row believes a local token, not the host

`Talaria/Features/Settings/ServerSettingsScreen.swift:65-68`:

```swift
static func resolve(hasActiveProfile: Bool, deviceToken: String?) -> TalariaLinkState {
    guard hasActiveProfile else { return .unknown }
    return (deviceToken?.isEmpty == false) ? .paired : .notPaired
}
```

**The whole signal is "do I hold a token".** A phone that paired once and whose
host has since had the plugin removed, disabled, or downgraded still reads
**PAIRED**. That is the same defect class #264's update warned about
(OPEN_ITEMS.md:7258-7260 — *"must not show PLUGIN LINK as PAIRED-and-healthy while
chat is refusing … one banner and one truth"*), and it is exactly what a
machine-verifiable probe fixes. 269-A's natural home.

The app already pairs itself over the envelope
(`Talaria/Services/Live/TalariaPlatformLink.swift:142-173`), so the transport for a
probe is built and epoch-guarded (`:148`, `:168`).

### ASSUMED — carried as open questions, not facts

- **What a desktop-only user's "gateway" actually is.** `hermes serve` is the
  desktop backend (`main.ts:8167`), and `dashboard.py:3-5` calls it *"the same
  gateway, headless"* — but `web_server.py` exposes `start_gateway` (`:12706`) and
  `restart_gateway` (`:4039`), which implies the platform-serving
  `hermes gateway run` is a **separate** process the backend manages. **If so, the
  restart a desktop user needs may be "quit and reopen Hermes", or a button the
  app's backend already has — a far friendlier ask than a terminal command.**
  Not traced. **This is the single most valuable unknown in the lane** and it may
  soften Blocker 2 substantially. Task A1 resolves it.
- **`POST /api/gateway/restart` (`web_server.py:4038-4052`) appears to lack a
  `_require_token(request)` call**, unlike every `/api/dashboard/agent-plugins/*`
  route. Module-level middleware was not traced. **Flagged, not designed against**
  — if it is genuinely unauthenticated it is an upstream security report, not a
  feature to build on. Do not use this endpoint in any design.
- Whether a real user's default `approvals.mode` differs from this box's `off`.
  Assume it does; verify with `hermes approvals test` before claiming a consent
  moment exists.
- I did not test-run any install, enable, or restart. Every behavioural claim
  above is source-read or a read-only HTTP probe.

---

## 2. The goal — what a user sees when it ships

**Today.** Owen's real users install Hermes as a desktop app from a GitHub
release. They open Talaria, connect it, and hit a card telling them to run
`hermes-mobile setup` in a terminal they did not know existed and may not have.

**When 269-A ships.** The app stops guessing. The Server screen's PLUGIN LINK row
says what is actually true on the host — not what this phone happens to remember —
and when the plugin is not live the app says so plainly and offers the next step
instead of a command.

**When 269-B ships.** The user connects Talaria and reads, in chat, in their own
agent's voice:

> *Talaria wants me to install its bridge plugin so it can reach your phone.
> I'll clone it into `~/.hermes/plugins/`, enable it, and restart myself —
> I'll be back in about twenty seconds. Want me to?*

They say yes. Hermes asks its own approval question for the restart. The agent
goes away and comes back. **The app — not the agent's prose — confirms it worked**,
and the Talaria pane in Hermes Desktop (#270) shows the same verdict in the same
words. Nobody typed a command.

> **⚠️ CORRECTED 2026-09-01 (the 269-B app-half lane) — the sample prose above
> is FALSIFIED by Owen's 2026-08-25 ruling and must not be built.** *"…and
> restart myself — I'll be back in about twenty seconds"* is exactly the step
> the ruling forbids: **the agent and the app NEVER restart the gateway**, and
> the flow ends by pointing the user at the host's own Restart Gateway
> affordance (the statusbar Gateway popover's power button, or the Command
> Palette entry). Task A1 is what settled it — a desktop-only user already has
> that control, shipped, two ways — and upstream's own comment says the button
> was visually isolated *"so it can't be hit by mistake."* There is no
> "goes away and comes back" moment to design for, and no Hermes approval
> question for a restart the agent never requests. The shipped first-contact
> prompt (`TalariaPluginSetupPrompt.firstContact`, pinned by 269-B-I) says
> *"Do not restart the gateway"* in so many words. Read the rest of this
> section — the app confirms, not the prose; nobody types a command — as still
> current; only the restart choreography is superseded.

**The wording IS the product here, and it is bars-worthy** (270's three states,
shared; §5's 269-B-C). Two specific claims must never be made: the app must not
claim a capability on the agent's behalf that the agent's host will refuse (the
#257 family), and neither surface may say "installed" off a "Done!".

---

## 3. ⚠️ Tracker corrections

Corrections go UPSTREAM to the stale claim's own home (THE CLOSE-OUT RULE).
**I edited nothing** — the orchestrator files these.

1. **#269's entry does not know the lane is blocked.** It reads NOT STARTED with
   three open design questions. The two blockers in the lead are load-bearing and
   neither is a design question — one is a distribution decision (Owen's), one is
   an upstream limitation. → **#269**, plus the **#268 roadmap table row for 2B**
   (OPEN_ITEMS.md:7059), which currently says only "NOT STARTED".

2. **The momentum report's proposed probe shape is wrong for this architecture,
   and #269's own update already half-corrected it.** The report
   (`planning/reports/2026-08-07-open-source-momentum-report.md:335-348`) sketches
   `GET /talaria/capabilities`. **A plugin cannot add a `:8642` route.** The
   platform-adapter contract gives it exactly two hooks —
   `verify_http_event_request` and `dispatch_http_event`
   (`~/.hermes/plugins/talaria/platform_adapter.py:66-72`) — behind the single
   registered route `POST /api/platforms/{platform}/events`
   (`api_server.py:2073`). The capability probe **must** be an envelope verb.
   #269's update says "rides the existing … surface, not a new endpoint"; make it
   explicit that this is an architectural constraint, not a preference.
   → **#269's update note** and a supersession line in the **momentum report §4**.

3. **The app's SETUP card teaches retired commands.** `ConnectHermesHostScreen.swift:110-112`
   ships `hermes-mobile setup|pair-phone|service install`. #251 Phase 1 records
   those venv CLIs as deleted and replaced by `hermes talaria …`. **The tracker
   says they are gone; the app still tells users to run them.** → file against
   **#269** (269-A owns the fix) and note it in **#251's Phase 1 block**, whose
   "deletes the venv CLIs" claim is true of the plugin and false of the app UI.

4. **`hermes plugins enable` prints a message that will make an agent lie.**
   `plugins_cmd.py:928` prints *"Takes effect on next session."* For the gateway
   that is **false** — the manager is a process-global singleton that early-returns
   on `_discovered` (`plugins.py:1341-1349`, `:2264-2272`), and the agent runs
   in-process (`gateway/run.py:4922`). `cmd_install`'s *"Restart the gateway"*
   (`:665-666`) is the accurate one. **An agent that reads the enable message and
   reports success to the app is not hallucinating — it is believing its own
   tooling.** This is an upstream-report candidate and a hard reason 269-A must
   exist before 269-B. → **#269**; candidate upstream ask alongside #264's.

5. **The parent brief's "#113 supervision gap" is a stale pointer.** #113 **closed
   2026-07-25** (`OPEN_ITEMS-ARCHIVE.md:2573`) when its duplicate-connector premise
   was refuted. The surviving half is **#188** (OPEN_ITEMS.md:4647-4667), whose
   watchdog fix was **DECLINED** under the no-hardening rule. Neither bears on this
   lane. → note in **#269** so the next reader does not chase it.

6. **#263(a) does not block this lane, and the reason is worth recording** (§9.1).
   → **#269**.

---

## 4. Scope ruling

**Not one lane. Two, and the seam is verification vs. installation.**

#251 banked 2B as a single routed shape. Held against the code it is one buildable
lane and one blocked one:

**269-A — the honest verification half. UNBLOCKED, build now.**
The app's machine-verifiable install-state probe; the state model; PLUGIN LINK
telling the truth about the host instead of about its own keychain; the stale
SETUP card retired. Touches the iOS app plus (optionally) one envelope verb. **No
live-install modification if the 401/503 signal is judged sufficient** — see §7.

**269-B — the conversational install. BLOCKED, hold.**
The app's first-contact prompt, the agent-side skill, the consent + restart
choreography. Blocked on Owen's distribution ruling (Blocker 1) and on a decided
restart story (Blocker 2 / §1 ASSUMED).

**269-A is bigger than "add a probe", for one honest reason.** From the app's
side, these three host states are **indistinguishable** — all three return 503:

- the plugin was never installed
- the plugin is on disk but not in `plugins.enabled`
- the plugin is enabled but the gateway has not restarted

The app can prove *whether* the bridge is live. It **cannot** prove *why not*.
Neither can #270's pane, for the same reason — its backend needs the same enable +
restart. **Only the agent can, because only the agent can read the filesystem and
run `hermes plugins list`.**

That is not a defect to engineer around; it is the actual architecture, and it
should be designed for deliberately:

> **The agent narrates *why*. The app verifies *whether*. Neither is sufficient
> alone, and the app must never upgrade the agent's narration into a verdict.**

269-A owns the *whether* and the honest "I don't know why" copy. 269-B owns the
*why*.

**What keeps 269-A from growing:** no install controls in the app, no remote
enable, no new HTTP route. If a task starts reaching for one, it has crossed into
269-B.

---

## 5. Proposed bars

Pre-registered here in full **for the orchestrator to file into #269's entry
before any code is written** (CLAUDE.md, "Where the BARS live"). A missed bar is a
falsification, not a redefinition. **I did not edit `OPEN_ITEMS.md`.**

### 269-A — the verification half (build now)

- **269-A-A (the probe distinguishes live from absent, on a real host).**
  Against a gateway with the plugin registered, the app's probe resolves **live**;
  against one without it, **not live**. Both verdicts trace to the observed HTTP
  status (401 vs 503 `platform_unavailable`), not to a stored token.
  *Evidence:* the two statuses captured from the app's own networking with the
  rendered state beside each. **LIVE HOST. Device not required** (a second
  gateway/profile or a URL pointed at a host without the plugin gives the negative
  arm; see §7 for why no live-install change is needed).

- **269-A-B (PLUGIN LINK stops believing the keychain).**
  A phone holding a valid device token, pointed at a host where the adapter is
  absent, renders **NOT LIVE** — not PAIRED. `TalariaLinkState.resolve`'s
  token-only signal (`ServerSettingsScreen.swift:65-68`) no longer decides the row
  by itself.
  *Evidence:* a unit test pinning the new resolution, plus the on-host screenshot.
  **Unit offline; screenshot LIVE HOST.**
  *This is the bar that repays #264's "one banner and one truth".*

- **269-A-C (the app never claims to know WHY).**
  In the not-live state the app's copy states what it observed and does **not**
  assert a cause it cannot distinguish (§4). A reviewer reading the strings cannot
  find a sentence claiming "not installed" when the app only knows "not
  reachable".
  *Evidence:* the exact strings quoted in the close-out, each mapped to the
  observation that licenses it. **Offline.**
  *#180's honest-degradation family, applied to prose.*

- **269-A-D (the stale SETUP card is gone).**
  `ConnectHermesHostScreen.swift:110-112`'s three `hermes-mobile` commands are
  removed or replaced. `rg -n 'hermes-mobile' Talaria/` returns no user-visible
  string.
  *Evidence:* the grep. **Offline.**

- **269-A-E (the gate).**
  Full `scripts/mac/lane-gate.sh` PASS — units + XCUITest + **Release** — with the
  unit count **moved** by the net new tests. A count that did not move is a stale
  `.xctest`, not a pass.
  *Evidence:* the gate's positive success marker and the before/after counts.
  **Offline (Mac).**

### 269-B — the conversational install (file now, run only after §8.1 and §8.2)

> **⚠️ 269-B-A AMENDED 2026-09-01 (recorded, not redefined) — the restart is
> the USER'S step, per Owen's 2026-08-25 ruling.** The bar below was written
> 2026-08-09, before A1 established that a desktop-only user already has a
> shipped Restart Gateway control. "The agent installs + enables + restarts"
> is now "**the agent installs + enables and STOPS; the user restarts the
> gateway from the host's own affordance; the app's 269-A probe — not the
> agent's prose — flips to live.**" Everything else about the bar stands
> unchanged, including its evidence and its 🔐 gate. The app half shipped
> 2026-09-01 (bars 269-B-F..J) with the prompt saying *"Do not restart the
> gateway"* verbatim; B-A still needs a live host and a per-experiment go.

- **269-B-A (a clean install completes end-to-end, agent-driven).**
  From a host with no talaria plugin: the app sends its prompt, the agent installs
  + enables + restarts, and **the app's 269-A probe** — not the agent's prose —
  flips to live. Zero terminal keystrokes by the user.
  *Evidence:* the chat transcript beside the app's probe result and the timestamps.
  **LIVE HOST. 🔐 GATE (§7).**

- **269-B-B (the half-install is DETECTED and named).**
  Injected partial states — cloned but not enabled; enabled but not restarted;
  clone failed on a private repo — each leave the app in **not live** and the
  agent's message names the actual state. **The app never renders live during
  any of them.**
  *Evidence:* one row per injected state: what was broken, what the agent said,
  what the app rendered. **LIVE HOST. 🔐 GATE.**
  *This is the bar the lane is for.* #269's entry says it plainly: *"a partial
  install is the realistic failure, not a clean one."*

- **269-B-C (the wording lands — measured, not assumed).**
  The consent and result messages are scored against pre-registered criteria over
  **N ≥ 10 trials on the target model**: does the agent state what it will do
  before doing it; does it avoid claiming success it cannot verify; does it use
  the #270-shared state vocabulary. **Instrument the error path** — a trial that
  threw is not a trial that passed.
  *Evidence:* the scored table with the denominator and the throw count stated
  separately. **LIVE HOST.**
  *#200-series discipline, which #269's entry invokes by name: measure the
  behaviour, do not assume the instruction landed. Note #215's warning — score
  only the configuration production actually enters (§1: `approvals.mode` matters).*

- **269-B-D (honest degradation where the agent has no hands).**
  On a host where the agent cannot write `~/.hermes/plugins/` or the clone fails,
  the flow **says so** and falls back to the documented CLI path. It does not
  retry silently and does not claim success.
  *Evidence:* the transcript from a permission-denied arm. **LIVE HOST. 🔐 GATE.**
  *#180's rule, which #269's entry cites.*

- **269-B-E (consent is not the app's to give).**
  On a host with approvals enabled, the restart step prompts **in Hermes**, and
  declining it leaves the app in **not live** with honest copy. On a
  `approvals.mode: off` host the flow still asks in-app before sending the prompt.
  *Evidence:* both arms, plus `hermes approvals test` output establishing which
  configuration each arm ran under. **LIVE HOST. 🔐 GATE.**

---

## 6. Task breakdown

### 269-A (no live-install modification required)

**A1 — resolve the restart question (read-only, no gate).** Trace whether a
desktop-app-only user has a `hermes gateway run` at all, or whether the desktop
backend manages it (`web_server.py:12706` `start_gateway`, `:4039`
`restart_gateway`; `apps/desktop/electron/main.ts:8167`). **This is the highest-value
unknown in the lane** — if the desktop app can bounce its own gateway, Blocker 2
becomes "ask the user to click a thing", and 269-B may be far closer to viable
than the lead finding assumes. Report either way before A2.

**A2 — decide the probe's depth (a design call, then Owen's, §8.3).** Either
(i) **401/503 only** — zero plugin change, ships today, tells you *whether*; or
(ii) **+ a `describe` envelope verb** — six lines in
`~/.hermes/plugins/talaria/envelope.py:97-109`'s dispatch table, authenticated by
the existing API-key path (`:66-75`), returning plugin name, version,
protocol version, capabilities, installation state. (ii) is what catches a
**stale** install — a phone talking to an old plugin — which (i) cannot see at
all. Recommend (ii), but (i) is a real ship.

**A3 — the app-side probe.** Extend `TalariaPlatformLink`
(`Talaria/Services/Live/TalariaPlatformLink.swift`), which already owns the envelope
POST (`:439-451`) and the epoch discipline (`:122`, `:148`, `:168`). Treat 503 and
401 as **distinct**, not as one failure — today `logEnvelopeError` (`:454-472`) flattens
both into a log line.

**A4 — the state model and the strings.** Reuse #270's three states verbatim
(proposed: **NOT INSTALLED · INSTALLED, NOT LIVE · LIVE**) — and note the app can
only distinguish the last from the first two (§4), so the app's middle copy must
be honest about that. Settle with Owen (§8.4).

**A5 — PLUGIN LINK.** Rework `TalariaLinkState.resolve`
(`ServerSettingsScreen.swift:50-69`) to take the probe result. Keep `.unknown`
meaning "not knowable yet" — its doc comment at `:46-49` already has the right
instinct; do not let a probe-in-flight render as NOT LIVE.

**A6 — retire the SETUP card.** `ConnectHermesHostScreen.swift:100-116`.

**A7 — gate + close-out.** `scripts/mac/lane-gate.sh`; corrections from §3 upstream
in the same commit.

### 269-B (hold for §8.1 / §8.2)

**B1 — distribution.** Whatever Owen rules in §8.1, implemented: public repo, a
mirror, or a bundled/vendored path. **Until this exists, B2–B5 cannot be tested on
any host but Owen's.**

**B2 — the agent-side skill.** Owen's *"a skill more or less"*. Model it on the
installed precedent — `~/.hermes/skills/hermes-desktop-plugins/SKILL.md` is a real,
working, agent-facing install skill with a How to Run / Pitfalls / Verification
shape. **It must name `terminal`, not `bash`/`shell`** (§1). Note #269's own
constraint: the skill cannot ship inside the plugin it installs, so first contact
rides the app's prompt.

**B3 — the app's first-contact prompt.** The text the app sends. This is a
**capability claim made by the app on the agent's behalf** (#257 family) and it
must not promise what a given host will refuse.

**B4 — the restart choreography**, per A1's answer.

**B5 — the measured wording pass** (269-B-C), with the error path instrumented.

---

## 7. 🔐 GATES — WHAT NEEDS OWEN'S EXPLICIT PER-EXPERIMENT GO

**269-A NEEDS NO GATE IF IT TAKES PATH (i).** The 401/503 probe requires no change
to the live install; the negative arm is obtained by pointing the app at a host or
profile without the plugin, not by removing anything. **Prefer this.** It is also
the fixture discipline the `bash-classifier-blocks` memory note recommends: get a
negative arm from a client-side configuration, never by stopping a service.

**🔐 GATE 1 — ADDING A `describe` VERB TO THE LIVE PLUGIN (269-A path (ii)).**
`~/.hermes/plugins/talaria` **is** the install (the clone IS the install). Develop
in a worktree, as #263 did (`~/Documents/Claude/t27-263-plugin/talaria`); **installing
it and bouncing the gateway to load it NEEDS OWEN'S GO.** A restart performed *to
load experimental code* is part of the experiment.

**🔐 GATE 2 — EVERY 269-B BAR (269-B-A, -B, -D, -E).** These install, enable,
remove, and restart against a live Hermes by construction. **Each run needs its own
go**, with the intended end state and the rollback stated when asking.

**🔐 GATE 3 — ANY `config.yaml` MUTATION.** `plugins.enabled` is a documented
security boundary (`web_server.py:17457-17471`; GHSA-mcfc-hp25-cjv7), and the agent's
`write_file` refuses the file by design (`file_tools.py:692-702`). Changing it via
`hermes plugins enable` is the sanctioned route and is still a live-install
modification.

The 2026-08-06 time-boxed clearance ("you are cleared for modifications, especially
if you're removing it afterwards") **expired with that day.** Do not cite it.

**Free without a gate:** read-only probes (everything in §1), `hermes approvals test`
(dry-run by construction, `approvals.py:79-113`), throwaway loopback servers, and
all app-side work.

---

## 8. What is OWEN'S to decide

1. **⛔ Does `AethyrionAI/talaria-plugin` go PUBLIC?** It is private today
   (verified). `hermes plugins install` is git-only and non-interactive, so a
   user's Hermes cannot clone it. **269-B does not exist as a user story until
   this is answered.** Options: make it public; publish a mirror; vendor the plugin
   into a release artifact; or accept 269-B as Owen-only forever and ship 269-A
   alone. This is a product decision with a security dimension, not an engineering
   one.
2. **The restart story**, once A1 reports. If a desktop user's gateway is
   bounced by the desktop app, "ask the user to click restart" is a good answer and
   269-B is much closer to viable. If it genuinely needs `hermes gateway restart`
   in a terminal, **269-B contradicts its own premise** and should be re-scoped or
   parked.
3. **Probe depth: 401/503 only, or add the `describe` verb?** (ii) catches stale
   installs and satisfies the momentum report's sharpening; it costs Gate 1.
4. **The three state names, as user-visible strings** — shared with #270, settled
   once. Proposed: **NOT INSTALLED · INSTALLED, NOT LIVE · LIVE**. Given the app
   cannot distinguish the first two (§4), Owen may prefer the app show a
   two-state vocabulary and let #270's pane and the agent carry the third.
5. **Does the app send a setup prompt automatically, or behind a button?**
   Automatic is the smoother story and is closer to *"the app SENDS THE SETUP
   PROMPT"*. But on an `approvals.mode: off` host it drives a silent install
   (§1). Recommend: **always behind an explicit in-app confirmation.**
6. **Whether 269-A ships before 269-B is unblocked.** Recommend yes — it fixes a
   live wrong answer (269-A-B) and retires stale UI (269-A-D) regardless.

---

## 9. Traps and interactions

**9.1 — #263's split-singleton reload: ASKED AND ANSWERED. It does not block this
lane.** The parent brief flagged that an agent installing into a running gateway
would hit #263(a)'s split hub. Two verified reasons it does not:

- **#263(a) as filed was FALSIFIED** (OPEN_ITEMS.md:7364-7375): the loader replaces
  only the parent package object, submodules stay cached under their own keys, and
  **8 forced `discover_and_load(force=True)` passes** held every HUB id constant.
  It survives as a WATCH with counters, not as a defect.
- **More decisively, an install cannot trigger a discovery pass at all.** There is
  no reload, no watcher, no SIGHUP handler, and `force=True` has exactly one
  non-test call site unrelated to installs (`main.py:10135`). The plugin loads only
  in a **fresh process**, and a fresh process starts aligned — the entry says so
  itself (OPEN_ITEMS.md:7276-7279).

**The trap is dodged by the very limitation that creates Blocker 2.** But the
split **shape** is still reachable by **manifest-name divergence**
(`plugins.py:1874-1876` — the slug comes from the manifest key). An installer that
clones into a differently-named directory, or a plugin whose `plugin.yaml` name
drifts from its directory, hand-builds it. **269-B's install must assert that the
directory name, `plugin.yaml`'s `name`, and the enabled key all read `talaria`** —
`_install_plugin_core` derives the target from the manifest name
(`plugins_cmd.py:536`), so a manifest edit silently relocates the install.

**9.2 — #264's bind race, and why it is worse here.** After a bounce the api_server
can lose the `:8642` bind and **never retry**, leaving a healthy PID with no chat
plane (OPEN_ITEMS.md:7231-7244). **269-B's flow ends in a deliberate restart**, so it
walks into this on purpose, every run. Consequences:

- **The ops rule is a bar-level requirement, not a footnote:** after the restart,
  verify the **LISTENER** (`lsof -nP -iTCP:8642 -sTCP:LISTEN`), never the process.
- **269-A's probe is what makes this survivable** — a 503 after a restart is
  exactly the "not live" verdict, so the app degrades honestly instead of hanging.
  **The failure mode #264 describes is one of 269-B-B's injected states**; add it.
- Do not let a #264 casualty be scored as an install failure. They look identical
  from the phone and are told apart only by the listener check.

**9.3 — ⛔ THE RELAY-HARDENING RULE. This lane is clean, and it is on the right side
of the ledger.** #269 adds **zero** relay or connector surface; it is a piece of
#251, whose Phase 4 is relay decommission. It is also the shape the rule points
at — *"Fix app-side instead, and this is not a consolation prize"*: **269-A is
entirely app-side** and fixes a real wrong answer with no host change at all.
If a task ever appears to need a relay change, stop and raise it as a decision.

**9.4 — TWO-OF-EVERYTHING, three planes.** `:8642` api_server (this lane's probe;
`/api/plugins/*` is **404** there, probed) · `:9119` `web_server` and the
desktop-spawned ephemeral `serve` (**#270's** plane) · the desktop renderer's
in-process SDK. **Never claim a `:8642` route from a `web_server.py` grep** — read
`_http_route_table()`. And `hermes plugins list` is the only trustworthy answer to
"is the agent plugin installed"; the desktop Settings → Plugins pane **cannot show
it by design** (that confusion is what created #270).

**9.5 — #270 is the same product's other face.** #270's pane makes the
not-installed state actionable on the desktop; 269-A makes it verifiable on the
phone. **They must use the same words for the same states** (§8.4). Neither can
distinguish *not installed* from *not enabled* from *not restarted* — only the
agent can (§4), which is the strongest single argument that 269-B is worth
unblocking.

**9.6 — #257's family: the app must not oversell the agent.** #269's entry places
the prompt wording in the same family as the on-device model under-selling its
toolbelt. The inverse risk is live here: an app-authored prompt that asserts the
agent *can* install, on a host where it cannot. **269-B-D is the bar for that**,
and #257's own device verdict (7/20 MISSED on compression, 2026-08-08) is the
warning: **a carefully written sentence is not a landed behaviour.** Measure it.

**9.7 — #188, not #113.** #113 closed 2026-07-25 (`OPEN_ITEMS-ARCHIVE.md:2573`);
its surviving half is #188, whose watchdog fix was **DECLINED** under the
no-hardening rule. Neither bears on this lane; the pointer is corrected in §3.5 so
the next reader does not chase it.

---

## 10. Close-out

This lane closes when:

1. **269-A's bars have written verdicts in #269's entry**, MET or MISSED against
   text filed before the build. **269-B's bars are filed and explicitly marked
   BLOCKED with the blocker named** — a filed-and-blocked bar is a result, not an
   omission.
2. **The §3 corrections land UPSTREAM in the same commit** — #269 (items 1, 2, 4,
   5, 6), #268's 2B roadmap row (item 1), #251's Phase 1 block (item 3), the
   momentum report §4 (item 2). THE CLOSE-OUT RULE.
3. **A1's answer is recorded in #269 whichever way it falls.** If the desktop app
   can bounce its own gateway, say so loudly — it materially changes 269-B's
   viability and the lead finding of this brief should be updated to match.
4. **The private-repo blocker is either resolved or filed as Owen's open
   decision.** It must not sit only in this dispatch: a dispatch is where a
   decision was surfaced, not where it lives (#268 — *"a phase name is not a
   filing"*).
5. **The upstream-report candidates are filed**, alongside #264's: the misleading
   `"Takes effect on next session."` (`plugins_cmd.py:928`), and the apparently
   token-less `POST /api/gateway/restart` (`web_server.py:4038-4052`, **flagged as
   ASSUMED — trace the middleware before reporting it**).
6. **The shared state vocabulary is recorded** so #270 starts from a decided word
   list rather than inventing its own.
