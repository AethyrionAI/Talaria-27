# FABLE-T27-283-3B — Host approvals on our plane: answer `approval.request` from the phone

**Tier that executes:** FABLE ·
**Item:** OPEN_ITEMS **#283** is slice 3A and is CLOSED-with-bars-met; **slice 3B needs its own
number — recommend #298** (§5, §6) · **Parent arc:** #251 · **Plan of record:**
`design/PHASE3-RUNS-MIGRATION-PLAN-2026-08-07.md` §2.2 / §3 · **Adjacent design:**
`design/APPROVAL_MODES_PROPOSAL-2026-08-07.md` (deliberately a DIFFERENT actor — see §5) ·
**Repo base:** `main` @ `35c6234` · **Proposed branch:** `claude/t27-298-3b-host-approvals` ·
**Size:** **L** (the plan says M — falsified, see §4 C3)

**Goal in one sentence:** when the Hermes host gates a dangerous action mid-turn, the phone
shows the host's own question with the host's own choice set and resolves it over
`POST /v1/runs/{run_id}/approval` — and in every state where the question cannot be shown,
says so honestly instead of inventing one.

---

> # ⛔ LIVE-INSTALL GATE — READ BEFORE PLANNING THE DEVICE ARM
>
> **BARS 298-H AND 298-I CANNOT RUN UNTIL A HOST HAS `approvals.mode` SET TO `manual`
> (OR `smart`). THE LAST RECORDED STATE IS `off` ON OJAMD (#224, 2026-08-05) AND
> UNRECORDED ON THE MAC. EDITING `config.yaml` ON A LIVE HERMES INSTALL AND BOUNCING
> THE GATEWAY TO LOAD IT IS A LIVE-INSTALL EXPERIMENT AND REQUIRES OWEN'S EXPLICIT
> PER-EXPERIMENT GO** (CLAUDE.md standing rule; the 2026-08-06 blanket clearance expired
> with that day). **DO NOT SET IT. DO NOT ASK THE AGENT TO SET IT. ASK OWEN, NAME THE
> EXPERIMENT, AND WAIT FOR THE WORD.**
>
> **BARS 298-A THROUGH 298-G NEED NO LIVE-INSTALL CHANGE AT ALL** — they are pure client
> work against a route that already exists, verifiable offline with fixtures. Build all of
> them first. The lane is shippable-with-device-debt exactly the way 3A was.
>
> Read-only probes of `~/.hermes/hermes-agent` source and throwaway loopback servers remain
> free. Everything in §2 below was obtained that way; nothing was modified or bounced.

---

## 2. Verified state

**Provenance discipline for this section.** Every Hermes claim is a read of the LIVE Mac
install at `~/.hermes/hermes-agent`, head **`3dcbe9001`** (2026-08-08), version string
`0.20.0`. Every Talaria claim is a read at `main` **`35c6234`**. `file:line` throughout.
Where a claim is a report of someone else's run rather than my read, it is labelled and
sourced. **This lane's whole risk is designing against a route table from memory, so the
route table was re-read today rather than cited.**

### 2.1 VERIFIED — the wire

**The route exists and is in the authoritative table.** `_http_route_table()` at
`gateway/platforms/api_server.py:2041`; the runs family occupies `:2082-2086`:

```
("POST", "/v1/runs",                        self._handle_runs)          # :2082
("GET",  "/v1/runs/{run_id}",               self._handle_get_run)       # :2083
("GET",  "/v1/runs/{run_id}/events",        self._handle_run_events)    # :2084
("POST", "/v1/runs/{run_id}/approval",      self._handle_run_approval)  # :2085
("POST", "/v1/runs/{run_id}/stop",          self._handle_stop_run)      # :2086
```

**There is no `/api/config` anywhere in that table** (grep for `"/api/config` in
`api_server.py` returns nothing). Re-verified today, at the current head. This is the fact
that settles the scope ruling in §5.

**`/v1/capabilities` advertises the feature:** `"run_approval_response": True` (`:3122`),
`"approval_events": True` (`:3124`), and `"run_approval": {"method": "POST", "path":
"/v1/runs/{run_id}/approval"}` (`:3151`).

**The answer handler — `_handle_run_approval`, `api_server.py:6929`.** Exact contract:

| condition | response |
|---|---|
| run id unknown to `_run_statuses` | **404** `run_not_found` (`:6938-6942`) |
| body not JSON | 400 (`:6945-6947`) |
| `choice` not in `{once, session, always, deny}` after aliasing | **400** `invalid_approval_choice` (`:6953-6959`) |
| no `_run_approval_sessions[run_id]` | **409** `approval_not_active` (`:6961-6969`) |
| `resolve_gateway_approval` returned 0 | **409** `approval_not_pending` (`:6986-6993`) |
| resolved ≥ 1 | **200** `{object:"hermes.run.approval_response", run_id, choice, resolved}` (`:7010-7015`) |

Aliases: `approve` / `approved` / `allow` → `once` (`:6950`). The body also accepts
`all` / `resolve_all` booleans (`:6971-6974`), which resolve **every** pending approval in
the session at once. On success the handler sets status `running` / `last_event
"approval.responded"` (`:6996`) and pushes an `approval.responded` frame **only if a stream
is still registered** (`:6997-7008`).

**The request frame — and its shape is NOT fixed.** `_approval_notify`
(`api_server.py:6621-6647`) takes the approval core's dict, re-redacts `command` through
`gateway.run._redact_approval_command`, and overlays `{event: "approval.request", run_id,
timestamp, choices}`. **`choices` is COMPUTED PER REQUEST** by `_approval_event_choices`
(`api_server.py:73-76`):

- `smart_denied` true → `["once", "deny"]`
- else `allow_permanent is not False` → `["once", "session", "always", "deny"]`
- else → `["once", "session", "deny"]`

**Four different producers feed it, with four different payloads** (`tools/approval.py`):

| producer | line | payload notes |
|---|---|---|
| dangerous-command gate (gateway branch) | `:3267-3274` | `command`, `pattern_key`, `pattern_keys`, `description`, `allow_permanent: True`, `allow_session: True` |
| `check_all_command_guards` | `:4020-4034` | same + `allow_permanent` conditional on `has_permanent_capable and not smart_denied_for_owner`; adds `smart_denied` |
| `check_execute_code_guard` | `:4393-4402` | same shape — **`command` is Python code, not a shell command** |
| **MCP elicitation consent** | `:4504-4509` | `{command: <the elicitation MESSAGE>, description, pattern_key: "mcp_elicitation", pattern_keys: [...]}` — **no `allow_permanent`, no `allow_session`** |

**Consequence the plan does not carry: `approval.request` is not always a shell command, and
`command` is not always a command.** A card that says "run this command?" and hardcodes four
buttons is wrong on two of the four producers. **Render the choice set from the frame.**

**The timeout.** `_get_approval_timeout()` reads `approvals.timeout`, **default 300s**
(`tools/approval.py:2966-2977` — the docstring itself records that 60s "proved too tight in
practice"). `_await_gateway_decision` (`:3604`) blocks the agent thread for the whole window
in 1s slices with activity heartbeats (`:3673-3712`). On expiry it returns
`{"resolved": False}` and the caller produces a BLOCKED result whose text ends
*"Silence is not consent."* (`:3722-3733` / `:3290-3311`).

**`is_interrupted()` inside the wait resolves the approval as `deny`** (`tools/approval.py:3695-3703`)
— so `POST /v1/runs/{id}/stop` on a parked run gives a clean deny and unwinds, rather than
hanging for the rest of the window. That is an escape hatch we already have wired app-side.

**NEW FINDING — nothing in the tracker or either design doc carries this: after an approval
TIMES OUT, the run status keeps reading `waiting_for_approval` for the rest of the run.**
`_set_run_status(run_id, "running", …)` fires in exactly one place, `_handle_run_approval:6996`.
An expiry resets nothing, and `_make_run_event_callback._push` re-stamps whatever the *current*
status is (`:6364-6368`), so every later event preserves `waiting_for_approval` until the
terminal set (`:6726` cancelled / `:6742` failed / `:6757` completed). **`GET /v1/runs/{id}`
is not a pending-approval oracle.** Only a 409 `approval_not_pending` settles it.

**NEW FINDING — the ANSWER channel does not depend on the SSE stream.**
`resolve_gateway_approval` works off `_gateway_queues[session_key]`
(`tools/approval.py:2503-2519`); the run→key mapping `_run_approval_sessions[run_id]`
(`api_server.py:6555`) is popped only in the run's own `finally` (`:6840`, `:7085`). So a
client that lost the stream **can still POST an answer and it will land** — it simply cannot
see the question. This upgrades N6's "reconnect or deny" from a hopeful phrase to a
source-proven capability, and it is what makes bar 298-D(i) a real state rather than a
shrug.

**The stream has no replay, confirmed at this head.** `_handle_run_events`'s `finally` pops
`_run_streams[run_id]` (`:6921-6923`), so a re-subscribe 404s; the registration race is
20 × 0.05s ≈ 1s (`:6885-6890`); keepalive comments every 30s (`:6907-6910`). Status TTL
`_RUN_STATUS_TTL = 3600` (`:6344`).

**Approvals are per-run by design:** `approval_session_key = run_id` (`api_server.py:6547-6555`)
— two concurrent runs cannot unblock each other. **Note the vocabulary trap this creates:**
a `session` choice is scoped to `approval_session_key`, which IS the run id, so "session" on
this plane means *this one run*, not this conversation.

**A deny REASON has a slot in the core and no slot on the wire.**
`resolve_gateway_approval(session_key, choice, resolve_all, reason)` (`tools/approval.py:2486-2489`)
relays a free-text reason into the agent-facing BLOCKED message (`:3294-3296`), but
`_handle_run_approval` never passes one (`:6976-6983`). The phone cannot attach a reason today.

**PROVEN ON THE WIRE, someone else's run (S13, 2026-08-05; `OPEN_ITEMS.md:5716-5726`):** submit
with `session_id` → run parks `waiting_for_approval` + emits `approval.request` →
`POST /v1/runs/{id}/approval {"choice":"once"}` → `resolved: 1` → run resumes → `run.completed`
(runs `run_ea99…`, `run_e6bb…`). The timeout arm was proven the same session by accident —
approving after the window returned `approval_not_pending` and the run self-completed blocked.

**PROVEN, the Sessions plane's side (S15 / #224 update, code-read then relied on):**
`_bind_api_server_session` hardwires `platform="api_server"` (`api_server.py:5946-5955` at
the plan's head), so `_is_gateway_approval_context()` is true, the gate takes the gateway
branch, finds no notify callback, and **queues for an unreachable `/approve`**
(`tools/approval.py:3322-3340` at this head) while handing the agent
*"⚠️ This action is potentially dangerous … Asking the user for approval."* Re-read today:
that queue-and-narrate branch is verbatim still there. **`register_gateway_notify` is called
from exactly one place in the whole api_server — inside `_handle_runs`, at `:6681`.**

### 2.2 VERIFIED — what the app has today

- **The frame is parsed and deliberately thrown away.** `parseRunsFrame`'s `default` arm
  returns `.ignored(name)` and its own doc names `approval.request` / `approval.responded`
  as "known-but-unused" — `Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift:160`,
  `:190-195`. **A green test pins the discard:**
  `TalariaTests/RunsFrameParserTests.swift:37-38 approvalAndSubagentAreIgnoredNotDropped`.
  3B's first act is to invert that test in place.
- **The status poll already treats a parked run as live.**
  `RunStatusSnapshot.liveStatuses` includes `"waiting_for_approval"` —
  `SessionsHermesClient+RunsTransport.swift:230`. So a recovery poll waits on a parked run
  and gives up at **`runsPollBudget` = 120s** (`SessionsHermesClient.swift:72`), which is
  **shorter than the 300s approval window**. That interaction is already documented as a
  pathology to bound (`SessionsHermesClient.swift:66-69` names "a run parked in
  `waiting_for_approval`" as a reason the budget exists). 3B changes its meaning: parking is
  no longer pathological.
- **The endpoint pin exists and the comment already anticipates approvals.**
  `activeRunContext: (runID: String, profileID: UUID?, endpoint: ResolvedEndpoint)?` —
  `SessionsHermesClient.swift:101`, whose doc says it is what
  *"`POST /v1/runs/{id}/stop` (and a future `/approval`) addresses"* (`:92-94`). #285's Part 3
  froze the endpoint at turn birth; `hardStopActiveRun()` rides it at
  `SessionsHermesClient+RunsTransport.swift:1018-1031`.
- **But the slot is single and short-lived.** Set at submit (`:398`, `:630`), cleared on the
  turn's terminal exit (`defer` at `:310-316`; sync `defer` at `:631-638`). #283 records the
  single-slot limitation ("an overlapping sync send and a streamed turn contend, so Stop can
  address the wrong run").
- **The forwarding seam for a run-scoped command is established.**
  `HermesClientProtocol.swift:180` declares `hardStopActiveRun()`, `:212-214` gives no-op
  defaults, `ResilientHermesClient.swift:79-80` forwards to `primary` only, and
  `ChatBackendRouter.swift:519-521` routes by the brain holding the lock. An
  `answerApproval` follows that exact shape.
- **`StreamingUpdate` has 12 cases** (`Talaria/Models/StreamingUpdate.swift:25-64`) and one
  exhaustive consumer — `ChatStore.swift:666-1010`.
- **The device confirm gate is a DIFFERENT ACTOR and shares nothing but a shape.**
  `ToolConfirmationCenter` (`Talaria/Services/Live/DeviceTools/ToolConfirmationCenter.swift`)
  suspends a Swift continuation (`:138-142`), defaults closed (`:11-14`), is **single-slot and
  auto-declines a second concurrent request** (`:134-137`), and gates exactly three CREATE
  tools on this phone. Card at `Talaria/Features/Chat/ToolConfirmationCard.swift`, rendered
  inline in the transcript at `ChatScreen.swift:1060-1067`. A host approval is a network
  round trip against a run id with a server-side deadline — **none of the continuation model
  transfers**, and the two can be on screen simultaneously.
- **`InboxItemType.approval` exists with no producer.**
  `Talaria/Models/InboxItemType.swift:4`; the only constructions are
  `Talaria/Components/DemoData.swift:68`, `:127` and a test at
  `TalariaTests/TalariaPlatformInboxServiceTests.swift:308`. Unchanged since #224 §F7.
- **No `once/session/always/deny` grant vocabulary exists in the app.** `MCPToolGrantStore`
  from `dispatch/FABLE-T27-150B-mcp-tools-approval.md` was never built —
  `Talaria/Services/Support/` contains no MCP files. 3B introduces this vocabulary for the
  first time, so whatever it establishes becomes the precedent 150B would inherit.
- **The Developer switch:** `UserSettings.useRunsTransport` (`Talaria/Models/UserSettings.swift:414`,
  default `false` at `:551`), armed at `AppContainer.swift:787`, toggled at
  `DeveloperSettingsScreen.swift:210-215`. **3B is unreachable with it off.**

### 2.3 ASSUMED — not verified, do not build as though it were

- **OJAMD's approval handler bodies.** #283 records OJAMD was *route-probed* and carries all
  four runs routes. The handler bodies in §2.1 were read on the **Mac** install only.
  Nothing here is a claim about OJAMD.
- **Either host's current `approvals.mode`.** Last record is `off` on OJAMD (#224, 2026-08-05,
  Owen's own change); the Mac is unrecorded. **Under `off` no approval ever fires**, so the
  whole lane is unexercisable until that changes — the live-install gate above.
- **The `smart_denied` two-choice arm has never been seen on the wire.** It needs
  `approvals.mode: smart` *and* a Smart DENY verdict. Code-read only. The client handles it
  by construction (it renders `choices` as received), but no bar claims it.
- **MCP elicitation raising `approval.request` on the runs plane** is code-read (S19),
  never probed.
- **Whether an `always` choice survives `hermes update`.** `approve_permanent` +
  `save_permanent_allowlist` (`tools/approval.py:3317-3320`) write a persistent allowlist;
  its file and its update-survival were not traced. Matters because O1 asks whether the phone
  may mint host policy.
- **What a DENIED tool call looks like on the runs event stream.** Whether it arrives as
  `tool.completed` with an `error` (a field the client currently discards,
  `SessionsHermesClient+RunsTransport.swift:472-473`), or not at all. Settle it on the wire
  during 298-I — do not guess, because #296 is exactly the failure of guessing here.

---

## 3. The goal — what a user sees when it ships

Owen asks his agent to do something with teeth. The turn runs on the runs plane; a tool
reaches a gated command. Instead of the agent narrating *"asking the user for approval"* into
a void, a card appears inline in the transcript:

> **HERMES · MAC MINI wants to run something**
> `rm -rf ~/Projects/scratch/build` *(as the host sent it — already redacted host-side)*
> Matched: destructive recursive delete
> [ ONCE ] [ THIS RUN ] [ ALWAYS ] [ DENY ]

The buttons are exactly the ones the host offered, no more. Tapping ONCE resumes the run and
the answer arrives normally. Tapping DENY produces the host's own BLOCKED text and the agent
adapts instead of retrying.

And in the states where the phone *cannot* show the question, the card is replaced by
something true rather than something reassuring:

- lost the stream, host still parked → *"The host is waiting on an approval. This connection
  can't show you what it is. You can deny it, or reopen the conversation to see."* — and the
  deny lands, because the answer channel does not need the stream (§2.1).
- window closed → *"Too late — the host denied it after 5 minutes of silence."*
- a Siri or widget turn → *"The host is waiting on an approval that this shortcut can't
  show. Open Talaria to answer it."*

The distinguishing claim is not "we added a card." It is **there is no state in which this
feature lies to you**, which is the #180 rule applied to a surface that has never existed.

---

## 4. ⚠️ Tracker corrections

Corrections go UPSTREAM, to each stale claim's own home, in the same commit series as the
result that falsifies them (THE CLOSE-OUT RULE). **Do not edit OPEN_ITEMS.md while writing or
reading this dispatch** — these are the corrections the LANE owes when it lands.

**C1 — every `api_server.py:NNNN` citation in the Phase 3 corpus is stale.** The Mac install
advanced **31 commits**, `01a1037d1` → `3dcbe9001` (2026-08-08), while the version string
stayed `0.20.0` — precisely the trap CLAUDE.md warns about ("verify by process start time,
not version string"). Measured drift in the runs region, ≈ +150 lines:

| claim | cited | actual at `3dcbe9001` |
|---|---|---|
| `_handle_runs` | `:6298` | **`:6455`** |
| `register_gateway_notify` (sole site) | `:6524` | **`:6681`** |
| `_RUN_STATUS_TTL = 3600` | `:6187` | **`:6344`** |
| runs `tool.started` (no `args`) | `:6222-6229` | **`:6381-6386`** |
| stream popped on disconnect | `:6765-6766` | **`:6921-6923`** |
| `/events` registration race | `:6729-6731` | **`:6885-6890`** |
| `_handle_run_approval` | `:6772` | **`:6929`** |
| approval redaction + choices | `:6470-6478` | **`:6621-6631`** |
| `approval_session_key = run_id` | `:6371-6375` | **`:6547-6555`** |
| `liveStatuses` source | `:1525` | **`:1586`** |

Lands as a dated note in `design/PHASE3-RUNS-MIGRATION-PLAN-2026-08-07.md`,
`design/APPROVAL_MODES_PROPOSAL-2026-08-07.md`, #283, #224, **and the Swift doc comments in
`SessionsHermesClient+RunsTransport.swift`** (`:213-217`, `:227`, `:264`, `:400-402`,
`:770-772`), which a lane reads far more often than it reads a design doc. Text: *cite the
head you read; re-resolve before quoting.*

**C2 — 3B has no tracker entry.** #283 is titled and scoped to slice 3A and its bars are all
MET. Under #268 ("a phase name is not a filing"), 3B gets its own number the day it is named.
Recommend **#298**. Highest live number today is #297 (`OPEN_ITEMS.md`).

**C3 — the plan sizes 3B as "M" (§3 slice table). Falsified.** It is the same shape as 3A,
which was L: a new `StreamingUpdate` case, a new exhaustive-switch branch, a new store, a new
view, a new client method and protocol member, two new files (→ `xcodegen`), plus four states
where the question cannot be shown. Correct the size row rather than discovering it mid-lane.

**C4 — N6 is understated in both the plan (§2.2 bullet 5) and #224's 2026-08-06 update.**
Both say a dropped-stream approval is visible "as a state but not as a question." True, and
incomplete: **the answer channel is stream-independent**, so the honest degraded state
includes a working Deny. Say so; otherwise the next reader designs a dead end.

**C5 — NEW, nothing carries it: a timed-out approval leaves `GET /v1/runs/{id}` reporting
`waiting_for_approval` for the remainder of the run** (§2.1). Lands in the plan §2.2 and in
#283, whose `liveStatuses` reasoning
(`SessionsHermesClient+RunsTransport.swift:226-232`) implicitly assumes the status tracks
reality. It does not.

**C6 — `/v1/runs/{id}/stop` on a parked run resolves the approval as `deny`**
(`tools/approval.py:3695-3703`), not as a hang. The plan §2.5 treats `/stop` only as the
mid-prose steering fallback. **CLAUDE.md's `:8642` paragraph describes `/stop` only as "a
REAL hard interrupt"** — accurate but incomplete now.

**C7 — promote the approval family into CLAUDE.md's `:8642` section**, the way #283 promoted
the runs family, with the three behaviours that would otherwise be re-probed: the choice set
rides the frame; `command` is not always a command (MCP elicitation reuses the field); the
status object never carries the question.

**C8 — #224's head matter still reads as a blanket shelving.** The 2026-08-04 note
("structurally blocked AND operationally unneeded") is true of *reading/writing the host's
mode* — re-verified today, no `/api/config` in `_http_route_table()` — and says nothing about
*answering*, which the entry's own 2026-08-06 footer already routes to 3B. Put the pointer at
the head, not only at the foot; a reader who stops at the shelving note concludes the wrong
thing.

---

## 5. Scope ruling

**ONE lane ships. ONE more gets a number and stays unbuilt. ONE thing is explicitly not a
slice.**

### Ships — **#298, slice 3B: answer host approvals on the streamed runs path.** Size **L**.

Everything needed to make a gated remote turn resolvable from the phone, including every
state where the question cannot be rendered. It is one lane and not three because the honest
states **are** the design of the card — splitting them ships a card that lies in the states
it does not handle, which is the #218 shape (two paths, one tested) plus the #180 violation.
All of it rides the existing `useRunsTransport` Developer switch; nothing is reachable to a
user who never opens Developer.

### Filed, NOT built — **#299: approvals that outlive the screen.**

A producer for `InboxItemType.approval` and a push path, so an approval arriving while the app
is backgrounded or closed is still answerable. Genuinely separate: it depends on the platform
link, on #238's notification cuts, and on a product decision about whether a dangerous host
command should be approvable from a lock screen at all. Named now because #268 says
named-but-unstarted work gets a number the day it is named. **Do not build it inside 3B, and
do not silently drop it either** — 3B's answer to "the app was away" is that the host denies
by timeout, and that is a real user cost that deserves a filing rather than a shrug.

### NOT a slice — **mode SELECTION. 3B ships mode-aware HANDLING only.**

The brief asks whether 3B ships mode selection or handling. **Handling, and this is settled by
code, not preference.** `approvals.mode` is a profile-scoped config key exposed on the
**dashboard app at `:9119`** (`hermes_cli/web_server.py:963-967`,
`hermes_cli/approval_mode.py:16`); `_http_route_table()` on `:8642` has no `/api/config` —
verified again today at `3dcbe9001`. Reading or writing the mode from the phone means a second
port and a second auth scheme, against the zero-setup goal. **#224 half (2)'s mode half stays
parked; only its "answer the request" half moves**, exactly as #224's own 2026-08-06 update
routed it. The app never displays, mirrors, or claims to know the host's mode — and the copy
must not imply otherwise.

### Deferred *within* 3B, each for a stated reason

- **The deny REASON** — no wire slot (`_handle_run_approval` never forwards
  `resolve_gateway_approval`'s `reason`). Not ours to add; an upstream ask is ruled out
  (Owen's standing no-upstream-PR ruling, S12).
- **`resolve_all` / the `all` flag** — the wire supports resolving every pending approval at
  once; there is no UI story for it and no observed case of two pending in one run
  (`approval_session_key = run_id`). Build nothing.
- **The `smart_denied` two-choice arm** — handled by construction (choices come from the
  frame) but unprobed, so no bar claims it. Record, do not verify.
- **Reusing `ToolConfirmationCenter`** — rejected. Different actor, different lifetime,
  different failure mode, and its single-slot auto-decline (`:134-137`) would silently drop a
  host approval that arrives while a device card is up. Build a sibling.

---

## 6. Pre-registered bars

> ## THESE BARS MUST BE FILED INTO THE TRACKER, IN FULL, BEFORE ANY CODE.
> **Recommendation: a NEW entry #298** (not #283 — that entry is slice 3A, its bars are met,
> and appending a second slice's bars to it re-creates exactly the "a phase name is not a
> filing" problem #268 exists to stop). Record the pre-lane gate baseline unit count in the
> same commit. The bars live in the OPEN_ITEMS entry; this dispatch is a copy for the
> executor, not the filing (CLAUDE.md, "Where the BARS live"). **A missed bar is a
> falsification, not a redefinition.**

| bar | claim | evidence | needs |
|---|---|---|---|
| **298-A** | `approval.request` decodes to a typed value carrying `run_id`, `command`, `description`, `pattern_key`, and **the `choices` array exactly as received**. Three fixtures: four-choice, `smart_denied` `["once","deny"]`, and the MCP-elicitation shape (`pattern_key:"mcp_elicitation"`, no `allow_permanent`). **A hardcoded four-button card is a bar FAILURE.** | `TalariaTests/RunsApprovalTests.swift` (new); `RunsFrameParserTests.swift:37` inverted in place | unit only |
| **298-B** | `once` and `deny` each POST `/v1/runs/{id}/approval` with exactly `{"choice": …}`, to the run's **frozen** endpoint, **at most once per card** regardless of tap count. | URLProtocol fixture asserting request count, body, and host | unit only |
| **298-C** | Every 4xx renders distinctly and **none renders as success**: 409 `approval_not_pending` → "the window closed, the host denied it"; 409 `approval_not_active` → distinct; 404 `run_not_found` → distinct. | unit, three arms | unit only |
| **298-D** | The three unanswerable states, each honest and each inventing nothing: **(i)** stream lost + status `waiting_for_approval` + no question → the app offers Deny, says it cannot show what it would deny, **and the Deny POST is still issued and lands** (the stream-independent channel, §2.1); **(ii)** `runsPollBudget` expires while the run is legitimately parked → `.interrupted`, **never** a failure claim; **(iii)** `syncTurnViaRuns` meets `waiting_for_approval` → a message naming the parked approval, **never** "did not answer in time." | unit, three arms | unit only |
| **298-E** | Answering does not disturb terminal discipline: `.finished` still yields **exactly once** (#237 shape pinned absent); a card outstanding when the driver exits is torn down, not left tappable against a cleared `activeRunContext`; a duplicate `approval.responded` is idempotent. | unit | unit only |
| **298-F** | **Status is not an oracle.** After a simulated timeout the status object still reads `waiting_for_approval`; the app must NOT raise a card from status alone. Only a stream frame raises a question. | unit, fixture per §2.1 | unit only |
| **298-G** | `scripts/mac/lane-gate.sh` → literal **`GATE: PASS`**: units **and** XCUITest **and** a green **Release** build; unit count **MOVED** from the baseline recorded in #298. | the gate log | Mac |
| **298-H** | **Device + live host.** A real remote turn hits a gated command; the run parks; the phone shows the card **with the host's own choice set**; `once` resumes it and the command executes. **Evidence is the host's `agent.log`, not the screen.** | host log | **device + LIVE-INSTALL GATE** |
| **298-I** | **Device + live host, the deny arm and the escape hatch.** `deny` produces the host's BLOCKED text and the agent does **not** retry or rephrase; and separately, tapping **Stop** on a parked run resolves it as a deny (`tools/approval.py:3695-3703`) rather than hanging for the window. Also **observe what a denied tool call renders as** and record it (§2.3's open unknown, #296's family). | host log | **device + LIVE-INSTALL GATE** |

**298-A…G need no live host and no device.** Build and land them first; 298-H/I are device
debt in the 3A pattern, queued in `dispatch/DEVICE-PASS-RUNNING-LIST.md`.

---

## 7. Task breakdown

TDD throughout: RED first, observe it fail **for the right reason**, then GREEN. The 3A lane's
own practice — *"every inverted test was first run against the UNFIXED code and observed to
fail for the right reason … no never-failed-test enters this entry as evidence"* (#283) —
is the standard here. See also the standing memory: a post-fix test is usually pinned to text
the fix did not touch.

**T0 — file #298.** The §6 bars verbatim, the §5 scope ruling, the §8 questions, and the
pre-lane gate baseline unit count. **No code in this commit.**

**T1 — decode (RED → GREEN).** New `TalariaTests/RunsApprovalTests.swift`:
`approvalRequestFrameCarriesTheHostsOwnChoiceSet`,
`smartDeniedFrameOffersOnlyOnceAndDeny`,
`mcpElicitationFrameIsNotRenderedAsAShellCommand`. Then extend
`SessionsHermesClient.RunsEvent` (`SessionsHermesClient+RunsTransport.swift:135-144`) with
`.approvalRequest(...)` / `.approvalResponded(choice:)` and add the arms to `parseRunsFrame`
(`:171-195`). **Invert `RunsFrameParserTests.swift:37 approvalAndSubagentAreIgnoredNotDropped`
in place** — narrow it to the subagent cases, move the approval assertion to the new file,
delete nothing.

**T2 — the value type.** New `Talaria/Models/RunApprovalRequest.swift`. `choices` decodes as
`[String]` with a display mapping, **not** a closed enum — `_approval_event_choices` is
upstream code that can grow a fourth shape, and an unknown choice must render rather than
vanish. Carry the run's `ResolvedEndpoint` **on the value**, not read from the client's live
slot (§9, the #285 trap). **New file → `xcodegen generate`.**

**T3 — the stream contract.** Two cases on `Talaria/Models/StreamingUpdate.swift:25-64`.
The exhaustive consumer is `ChatStore.swift:666-1010`; find every other switch with
`grep -rn "case .interrupted" Talaria/ TalariaTests/`.

**T4 — the answer call (RED → GREEN).** `answerApproval(runID:choice:endpoint:)` in
`SessionsHermesClient+RunsTransport.swift`, modelled on `hardStopActiveRun()` (`:1014-1044`)
including its hard-won discipline: **the POST reaching the host is what makes a state true**
(the #279 review finding — `markSelfStopped` moved *after* the POST for exactly this reason).
Protocol seam: declare beside `hardStopActiveRun()` at `HermesClientProtocol.swift:180`, no-op
default at `:212-214`, forward `primary`-only in `ResilientHermesClient.swift:79-80` and by
routing lock in `ChatBackendRouter.swift:519-521`. Tests:
`onceAnswerPostsExactlyOneChoiceBody`,
`answerRidesTheRunsFrozenEndpointAcrossAProfileSwitch` (reuse #285's mid-turn base-URL flip
harness, `aMidTurnBaseURLChangeCannotRedirectALiveTurnsRequests`).

**T5 — the store (RED → GREEN).** New `Talaria/Stores/HostApprovalStore.swift`, small and
`@Observable`: at most one live request per run id, cleared on terminal, plus the degraded
poll-only state. **Recommended over adding a fourth responsibility to `ChatStore`.** Tests:
`aCardOutstandingAtTurnEndIsTornDownNotLeftTappable`,
`statusAloneNeverRaisesAQuestion`. **New file → `xcodegen generate`.**

**T6 — the 4xx arms (RED → GREEN).** `expiredWindowRendersAsHostDenied`,
`noActiveApprovalSessionIsDistinctFromExpired`, `noFourXXRendersAsSuccess`.

**T7 — the sync path (RED → GREEN).** `syncTurnViaRuns` (`:597-690`) and
`pollRunToTerminal` (`:788-836`) currently classify `waiting_for_approval` as `.live`
(`:230`), so a parked Siri turn silently burns its 20s and throws the generic
did-not-answer-in-time string (`:657-659`). Add a distinct classification and message. Test:
`aSyncTurnParkedOnAnApprovalSaysSoRatherThanTimingOut`.

**T8 — the card.** New `Talaria/Features/Chat/HostApprovalCard.swift`, a **sibling** of
`ToolConfirmationCard.swift`, rendered beside it at `ChatScreen.swift:1060-1067`. Copy must
name the actor (whose host, which profile), show `command` **as received** (already redacted
host-side — never reformat, never re-highlight, never truncate a path), and build buttons
from `request.choices`. HUD discipline: the `Design.Brand.forge` header treatment of
`ToolConfirmationCard.swift:15-20`; `Design.Colors.danger` only if Owen wants deny in red.
Both cards can be on screen at once (§9) — they must be visually distinguishable at a glance.
VoiceOver labels state the **consequence**, not the choice name (the 224-1D precedent). Theme
sweep including Paper Tape. **New file → `xcodegen generate`.**

**T9 — XCUITest.** Attempt only if the card is reachable behind the Developer switch with a
fixture host. If it is not, **say so in the PR** rather than shipping a test that exercises a
mock and reads as coverage.

**T10 — the gate.** `xcodegen generate` first (T2/T5/T8 all add files). Then background
`scripts/mac/lane-gate.sh` and poll its log with an `until` loop:
```
until grep -q 'GATE: PASS' <log>; do sleep 30; done
```
**Never arm a Monitor; never wait on a notification.** Kill the waiter the moment the answer
arrives another way (standing memory: background waiter hygiene). Confirm the unit count
MOVED — a stale `.xctest` will happily re-report the old number.

**T11 — close-out.** Land C1–C8 upstream in the same commit series (§10).

---

## 8. Open questions that are OWEN'S

**Not answered here. Do not answer them in the lane either — surface them under a
"Questions for Owen" header and wait.**

### #224's eight, triaged against 3B

**NONE of #224's eight blocks 3B.** Stating that plainly because the brief asks. #224's
questions govern **our own on-device gate**; 3B governs **the host's**. They are different
actors and the proposal says so in as many words (§3.8: *"No control, display, or mirroring
of the host's `approvals.mode`; no `approval.request` SSE handling; no
`POST /v1/runs/{id}/approval` client."*). Specifically: Q1 (build the app-side modes at all /
Phase 0 first), Q2 (global vs per-profile), Q3 (does Off ship), Q4 (refuse vs card), Q5
(Smart as rules), Q6 (Privacy screen home) — all independent, all stay open.

Two are **non-blocking but coupled**, and the lane should say so rather than let them drift:

- **Q7 (transcript receipts for auto-approved actions)** — 3B's answered cards raise the same
  question for the same reason, and answering it two different ways in two lanes is exactly
  the drift the proposal warns about. 3B should adopt whatever Q7 decides, or state that it
  deliberately left no receipt.
- **Q6 (Privacy → "Agent Actions" home)** — if 3B ever grows a persisted preference (it does
  not today), it must not land in that section without first deciding whether the two are one
  control or two. Two controls a screen apart, one saying "actions" and one saying
  "approvals," is a confusion we would be manufacturing.
- **Q8 (the 30-second `/approvals smart` slash probe)** — still Owen's, still not blocking.
  Worth noting 3B does not change the answer: there is no slash dispatch in `api_server.py`
  on either plane.

### 3B's own, and these DO block

- **O1 — `always` and `session`: may the phone write host policy? BLOCKING; it determines the
  card.** `always` calls `approve_permanent(pattern_key)` + `save_permanent_allowlist`
  (`tools/approval.py:3317-3320`) — one tap on a phone permanently allowlists a
  dangerous-command pattern on your box, across sessions, and (**unverified**, §2.3) possibly
  across `hermes update`. Separately, **`session` is scoped to `approval_session_key`, which
  IS the run id** (`api_server.py:6547-6555`) — so a button labelled "Session" means *this one
  run*. Options: render all four as the host offers them; render only `once`/`deny` and drop
  the persistent scopes from the phone entirely; or render all four with the persistent ones
  behind a second confirm.
- **O2 — the live-install go.** 298-H/I need `approvals.mode: manual` on a host and a gateway
  bounce. Per-slice go or per-deploy? (Plan §5 Q6 asked the general form; this is the concrete
  instance, and it is genuinely yours — the rule exists because a probe once assumed it.)
- **O3 — which host.** The Mac is observable (`agent.log`, launchd) and is where 3A's device
  pass ran; OJAMD is your daily driver but its approval handler bodies are unread here. My
  reading favours the Mac for the bars and OJAMD untouched by this lane, but the choice is
  yours because it is your box's config being changed.
- **O4 — `approvals.timeout`.** The plan's §5 Q5 recommended 300s; that is now the code
  DEFAULT (`tools/approval.py:2966-2977`), so this is only a question if a host overrides it.
  Confirm neither box does.
- **O5 — the sync/Siri path.** An approval on a `send()` turn has no surface. Refuse honestly
  and let the host time out (300s of a blocked agent burning a slot), auto-deny it from the
  client, or extend `runsSyncBudget`? Three different user experiences, none obviously right.
- **O6 — does 3B change the default?** #283 left "make runs the default" as your call, not
  evidence. 3B is unreachable with the switch off, so shipping it changes nothing for anyone
  who never opens Developer. Say whether that is the intent or a step toward flipping.

---

## 9. Traps and interactions

- **#285's endpoint pin — inherited only if you route through it, and the pin is not
  enough.** `activeRunContext` carries the frozen `endpoint`
  (`SessionsHermesClient.swift:101`) and `hardStopActiveRun` rides it
  (`RunsTransport.swift:1018-1031`), so a stop after a profile switch still reaches the right
  host. **But `activeRunContext` is a SINGLE SLOT cleared on the turn's terminal exit**
  (`:310-316`, `:632`). An approval answered even a beat after the driver returned would
  address nothing. **Carry the endpoint on the approval request VALUE, not read it from the
  live slot.** #283 already records the single-slot contention (an overlapping sync send vs a
  streamed turn); approvals are the first surface that makes it user-visible.
- **#292 — the producer `Task` is never cancelled** (`SessionsHermesClient.swift:322-350`, no
  `continuation.onTermination`), so every `if Task.isCancelled` in the runs driver is
  unreachable from a consumer walk-away. With approvals a park can last 300s while
  `runsPollBudget` is 120s, so the poll gives up first — the *good* direction here, but
  292-A is still unmet and an abandoned parked turn still burns requests. **3B must not add a
  second uncancelled loop.** If the card needs a watcher, it rides the existing driver.
- **#295 — recovery arming reads `currentRunIsServerRecoverable`**
  (`HermesClientProtocol.swift:110`) **before** `abandonActiveRun()` clears it, pinned by a
  test. A run parked on an approval IS server-recoverable, so the expiration path arms a
  `PendingRun` and will reconcile the eventual BLOCKED answer. Correct. **But it will never
  surface the question** — that is exactly 298-D(i). **Do not "improve" this by raising a card
  from a `PendingRun`**: the question is not in the status object (§2.1) and a card built from
  a `PendingRun` would have to invent one.
- **#263's rule, generalised.** 3B touches no gateway internals, so the late-binding rule does
  not apply literally; its sibling does. **Resolve run id and endpoint per call. Never cache a
  run-scoped handle in a property that outlives the run.**
- **#264 — the headless gateway.** The answer POST shares the `:8642` listener with chat and
  everything else. A connection-refused answer must render as **"could not reach the host,"
  with the card still live** — never as denied, never as approved. One truth, one banner
  (plan §2.7).
- **#296 — an interrupted tool renders with a ✓.** A DENIED tool call is the same honesty
  family: the host returns BLOCKED, nothing ran, and the pill must not read as completed. The
  client currently **discards** `tool.completed`'s `error` field
  (`RunsTransport.swift:472-473`). **Do not guess what a deny emits — observe it in 298-I and
  record it**, because guessing here is how #296 happened.
- **#237's duplicate shape.** Every new terminal path is a duplicate-yield risk; 298-E is the
  pin.
- **The two cards can coexist.** `ToolConfirmationCenter` is single-slot and **auto-declines a
  second concurrent request** (`ToolConfirmationCenter.swift:134-137`). A remote turn that also
  calls a device tool can put a host approval card and a device confirm card on screen at the
  same moment. They are different actors with different consequences and must not look alike.
- **#21 / #258 are unchanged by 3B** — the runs stream still carries no tool `args`
  (re-verified today, `api_server.py:6381-6386`). **Do not let an approval card become a place
  someone reconstructs a written file** from `command` or `preview`; that is the 3A-D
  honest-absence bar, still binding.
- **The Sessions plane is unaffected and must stay so.** With `useRunsTransport` off, a host
  in `manual` still produces the dead turn S15 describes. **That is not a regression 3B
  introduces and 3B must not paper over it** — the fix for the sessions plane is 3E's cutover,
  not a second code path.

---

## 10. Close-out

**Gate.** `scripts/mac/lane-gate.sh` after `xcodegen generate`, backgrounded, polled with an
`until` loop. Literal **`GATE: PASS`**; units **and** XCUITest **and** Release; unit count
**MOVED** from the baseline recorded in #298 at T0. A green Debug suite cannot see a mis-set
`#if DEBUG` gate (#218) and `test-without-building` will happily re-run a stale `.xctest`.

**`xcodegen generate` is mandatory** — T2, T5 and T8 each add a Swift file, and the project
uses generated explicit source references. Run it before any build and before the gate.

**Upstream text this lane's result falsifies** (land in the same commit series, each in the
stale claim's own home):

| correction | home |
|---|---|
| C1 file:line drift | both design docs, #283, #224, **and `SessionsHermesClient+RunsTransport.swift`'s own comments** |
| C2 3B has no entry | new #298 |
| C3 3B is L, not M | plan §3 slice table |
| C4 N6 understated — the answer channel survives | plan §2.2 bullet 5; #224's 2026-08-06 update |
| C5 status stays `waiting_for_approval` after a timeout | plan §2.2; #283; the `liveStatuses` comment at `RunsTransport.swift:226-232` |
| C6 `/stop` on a parked run = deny | plan §2.5; **CLAUDE.md `:8642` paragraph** |
| C7 promote the approval family's three behaviours | **CLAUDE.md `:8642` paragraph** |
| C8 #224's shelving note reads as blanket | #224 head matter |

Plus whatever 298-H/I falsify on the wire — in particular §2.3's open unknown about what a
denied tool call emits, which becomes a recorded fact either way.

**PR.** Branch `claude/t27-298-3b-host-approvals`, base `main`. The body discloses: **O1 as
Owen ruled it**; the single-slot `activeRunContext` limitation and how the lane worked around
it; whether 298-H/I ran or are device debt; and **every bar's status with its evidence**, not
its expectation. **No external submission without Owen's read of the exact text and an
explicit go** (standing rule — "file it" instructions do not cover the submission moment).

**If any bar is MISSED, it is a falsification, not a redefinition.** Record the miss in #298,
stop, and surface it. #297's 297-A was recorded as MISSED the day before this dispatch was
written; that is the standard.
