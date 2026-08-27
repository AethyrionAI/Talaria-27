# APPROVAL MODES — mirroring Hermes's Manual / Smart / Off in Talaria (OPEN_ITEMS #224)

> **✅ PHASES 1+2 LANDED 2026-08-26 — this document is now the DESIGN OF
> RECORD FOR SHIPPED BEHAVIOUR, not a proposal.** Owen approved all eight
> questions on 2026-08-10 (Phase 0 built the same week) and elected Phases 1+2
> on 2026-08-26 (*"Smart is a part of hermes, makes sense that we should have
> that too. Orchestrate that as a lane please"*), discharging ruling 1's hold.
> **What ships:** the `// Agent Actions` control on the Privacy screen with all
> three modes; `.smart` auto-approving clean staged actions and CARDING
> caution-tripping ones; `.off` auto-approving clean ones and REFUSING
> caution-tripping ones through the floor. **What does NOT:** Phase 3's
> transcript receipts (ruling 7 — still deferred, auto-approvals log to
> `os_log` and render nothing) and everything under §3.8 / "not a phase".
> **Read §3 as built, with these caveats:** §3.3's insertion point named
> `locationSection`, which has not existed since #137 — the control sits
> between `sensorStreamingSection` and `appLockSection`, the same reading
> order; §6's Phase 1–3 sketch bars are still NOT the pre-registration, which
> lives in OPEN_ITEMS #224 (bars 224-1A..1F / 224-2A..2D, formalized
> 2026-08-26 with nine re-resolved anchors listed there). Bar-by-bar results
> are in that entry.

**Status: ~~PROPOSAL, awaiting Owen's approval. Nothing gets built before you answer.~~
APPROVED 2026-08-10 (all eight) · PHASE 0 BUILT 2026-08-11 · PHASES 1+2 BUILT 2026-08-26.**
Written 2026-08-06 evening for a morning read, in the #258 pattern: one document, every
open question carries a recommendation, say "approved" or name what you'd flip.
**Scope:** design only. No code was written and nothing on the Hermes install was
modified — every Hermes claim below is a read of `~/.hermes/hermes-agent` with a
`file:line`.

> **⚠️ 2026-08-09 (#304 lane, dispatch `FABLE-T27-283-3B-approvals.md` §4 C1):
> every `api_server.py:NNNN` citation in this document is STALE.** The Mac
> install advanced to `3dcbe9001` (2026-08-08) — an unknown real distance, the
> checkout being shallow — while the version string stayed `0.20.0`. Measured
> drift in the runs region is ≈ +150 lines (e.g. `_handle_run_approval`
> `:6772`→`:6929`; full table in the dispatch §4 C1). **Cite the head you read;
> re-resolve any line number here before quoting it.** Note also that the HOST's
> approval gate is now answerable from the phone on the runs plane — that lane
> is **#304** (slice 3B), a deliberately different actor from this proposal's
> on-device gate; this proposal's scope statement (§3.8) is unchanged.

---

## 0. The honest framing first

**#224 is SHELVED, and most of the reasons still hold.** The 2026-08-04 shelving note says
half (2) — controlling the HOST's approval mode from the phone — is both structurally
blocked and operationally unneeded, and that half (1) — modes for our own gate — is "a
comfort feature with no expressed discomfort." **I am not asking you to un-shelve half (2).
This proposal leaves it parked and adds evidence for why.**

Two things I found tonight are new, and they're the reason this is worth a read rather
than a "still shelved" note:

1. **Our confirm gate already contains the deterministic risk classifier that "Smart"
   needs.** `DeviceActionTools.dueCaution(for:now:)`
   (`Talaria/Services/Live/DeviceTools/DeviceActionTools.swift:305-315`) already
   classifies a staged reminder as past-due / early-morning / next-morning. #224 assumed
   Smart "implies a classifier" and warned it can't be handed to the same model that
   produced the #200-series grabs. **It doesn't have to be — the classifier is already
   shipped, it's rules, and it's the exact structure Hermes's Smart uses.** That inverts
   the item's own risk assessment for Smart, so it deserves to be said out loud.

2. **I found the mechanism, not just the symptom, for why the host's mode can't reach us.**
   #224's 2026-08-04 probe showed a Sessions-API `run.started` id 404s on `/v1/runs/{id}`.
   The cause is one line: `register_gateway_notify` appears **exactly once** in the whole
   api_server, inside `_handle_runs` (`gateway/platforms/api_server.py:6524`, method at
   `:6298`). The Sessions chat path never registers an approval notifier at all. Same
   verdict, firmer footing — and it tells us what an upstream ask would have to be.

**One correction I made mid-investigation, recorded because the repo's rule is that
corrections beat confident guesses.** I first read the approval gate as *failing open* for
Sessions-API turns — i.e. under host `manual` mode a dangerous command would silently
auto-approve. That was wrong. `_bind_api_server_session` hardwires `platform="api_server"`
(`gateway/platforms/api_server.py:5946-5955`, called from `_run_agent` at `:6013`), which
makes `_is_gateway_approval_context()` return **true** (`tools/approval.py:243-261`), so
the gate takes the gateway branch and **blocks** instead. The real behaviour is in §4. I
nearly published the wrong version; the chokepoint's own docstring caught it.

---

## 1. What Hermes's three modes actually DO (evidence, not assumption)

**It is a first-class config key with a schema.** `hermes_cli/web_server.py:963-967`
declares `approvals.mode`, type `select`, description "Dangerous command approval mode",
options `["manual", "smart", "off"]`. The canonical validator agrees:
`VALID_APPROVAL_MODES = ("manual", "smart", "off")` (`hermes_cli/approval_mode.py:16`).

**The declared behaviour** (`website/docs/user-guide/security.md:30-58`):

| Mode | Documented behaviour |
|---|---|
| **smart** (their default) | Auxiliary LLM assesses risk. Low-risk auto-approved *for that command only*. Genuinely dangerous auto-denied. Uncertain escalates to a manual prompt. |
| **manual** | Always prompt on dangerous commands. |
| **off** | Disable approval checks — equivalent to `--yolo`. |

**Four structural facts that matter more than the table, and that the #224 entry does not
have:**

- **The scope is dangerous SHELL COMMANDS, not every tool call.** The gate runs after a
  pattern detector; if nothing matched, there is no prompt and no mode question.
  `tools/approval.py:3756-3762` — the warnings list is built from a matched
  `DANGEROUS_PATTERNS` entry (`:692`) or a tirith finding, and `if not warnings: return
  {"approved": True}`. **This is the single biggest asymmetry with us:** our gate has no
  detector, because every action tool is side-effecting by construction, so 100% of our
  action calls are "flagged" where a small fraction of theirs are.
- **Smart runs only on already-flagged commands, and is a false-positive REDUCER.**
  `tools/approval.py:3764` is literally headed "Phase 2.5: Smart approval," it runs inside
  the `if approval_mode == "smart"` branch after the detector, and its own user prompt says
  "Many flagged commands are false positives" (`:2951-2954`). Verdicts are
  APPROVE / DENY / ESCALATE (`:2969-2975`); an APPROVE is deliberately **not** persisted at
  pattern level ("Pattern-level persistence would let one benign command suppress review of
  later commands," `:3782-3785`); an LLM failure returns `escalate`, i.e. it **fails toward
  asking the human** (`:2976-2978`).
- **The reviewer is a SEPARATE model, not the primary agent.** `_smart_approve` calls
  `call_llm(task="approval", …)` into the auxiliary client
  (`tools/approval.py:2957-2966`; `agent/auxiliary_client.py:8562`), with a
  prompt-injection-hardened system prompt, shell comments stripped, the command wrapped in
  `<command>` delimiters, and an operator-customizable trusted policy appended to the
  SYSTEM channel only (`approvals.smart_policy`, `:2871-2883`, `:2937-2943`). **Smart's
  entire safety story rests on an independent second reviewer.** We do not have one on the
  phone — the only model available is the same ~3B FoundationModels instruct model that
  produced the #200-series grabs. Any "Smart" we build cannot be a faithful copy of theirs
  by that route.
- **Off is NOT the bottom. There is a floor below it.** The hardline blocklist trips
  before the approval layer and survives `--yolo`, `/yolo`, `approvals.mode: off`, cron
  approve mode, and an explicit "allow always"; it returns an explanatory error to the
  agent and nothing runs (`security.md:92-112`, `UNRECOVERABLE_BLOCKLIST` in
  `tools/approval.py`). `approvals.deny` is its user-editable sibling, also consulted
  before Off (`security.md:114-116`). **"Off" in Hermes means "never prompt me," not "no rules
  apply."** This is the fact the whole §3 design hangs on.

Adjacent keys, for completeness: `timeout` (300s), `cron_mode` (`deny` default — cron
denies side effects silently, which #224 already noted from #251), `mcp_reload_confirm`,
`destructive_slash_confirm` (`security.md:33-48`).

**What surface exposes it.** Profile-scoped config (`~/.hermes/config.yaml`), not
per-session and not conversation state — `hermes_cli/approval_mode.py:3-6` says so
explicitly and notes the change takes effect immediately because approval.py re-reads
config per check. Writable through `set_config_value` (`:57-62`), which is the managed-
policy chokepoint. Reachable from: `hermes config set approvals.mode`, the `/approvals
[manual|smart|off]` slash command in the CLI (`hermes_cli/cli_commands_mixin.py:2894`) and
in gateway platforms (`gateway/slash_commands.py:3616-3631`, **admin-gated** — non-admins
may read but not set), and the dashboard's config UI on **:9119**. Session-scoped `/yolo`
is a separate, narrower mechanism and is not the model (`security.md:61-88`).

---

## 2. Our current state — where Manual lives and what it gates

> **⛔ SUPERSEDED 2026-08-26 (Phases 1+2): the sentence below is FALSE now.**
> There is a user-facing mode — Privacy → `// Agent Actions`, three rows,
> global on `UserSettings.approvalMode` — and the gate is Manual only by
> DEFAULT. Everything the paragraph says about the gate's mechanics
> (`pending`, the checked continuation, the second-request auto-decline,
> default-closed, edited values are what get created) is unchanged and still
> accurate.

**One always-on Manual gate, no user-facing mode.** `ToolConfirmationCenter`
(`Talaria/Services/Live/DeviceTools/ToolConfirmationCenter.swift:15-17`): staged card in
`pending` (`:48`), tool suspends on a checked continuation (`:138-142`), a second
concurrent request auto-declines rather than queueing (`:134-137`), the gate
**defaults closed** — if the app dies with a card pending, nothing was created (`:11-14`).
Edited field values are what get created (`:19-20`, `:145-150`).

**Exactly three flows are gated, and all three are CREATES:**

| Tool | Gate call | Card |
|---|---|---|
| `createReminder` (`DeviceActionTools.swift:98`) | `:228` | "Create this reminder?" + title/due/list, **plus a caution row** |
| `createCalendarEvent` (`:410`) | `:484` | "Add this event to the calendar?" + title/starts/duration/location — ~~**no caution**~~ |
| `scheduleAlarm` (`:601`) | `:626` | "Schedule on this iPhone?" + "It will ring through Silent mode and Focus." — ~~**no caution**~~ |

> **⛔ SUPERSEDED 2026-08-11 by #224 PHASE 0 — the two "no caution" cells are
> now FALSE, and that was the whole point of the phase.** `createCalendarEvent`
> stages `STARTS IN THE PAST` / `EARLY MORNING START — CHECK AM/PM`
> (`CalendarEventTool.startCaution(for:now:)`), and `scheduleAlarm` stages
> `EARLY MORNING — CHECK AM/PM` / `ALREADY PASSED TODAY — RINGS TOMORROW`
> (`AlarmTool.caution(for:now:calendar:)`). **All three gated tools carry a
> caution layer now.** The `:NNN` line citations in this table were read at a
> pre-Phase-0 head and every one below `:410` has drifted — re-resolve by
> symbol, never by line (the #304 C1 rule). Evidence: OPEN_ITEMS #224, bars
> 224-0A/0B/0C/0D.

(Two extra `createReminder` / `createCalendarEvent` structs at `:339`, `:377`, `:567` are
pinned rollback seams from the #209/#200 lanes, not additional flows.)

**Eleven tools are NOT gated at all** — `deviceStatus`, `currentLocation`, `readMotion`,
`currentWeather`, `searchPlaces`, `lookupContact`, `readHealth`, `readCalendar`,
`readReminders`, `readImageText`, `readBarcode`, `searchConversations`. They are reads,
governed by OS permission grants, the #260 privacy master switch, and the #225/#232
governor — **not** by the card. Any mode we add must not touch them, and the Settings copy
must not imply it does (real-data-only rule).

**Modes exist today only as DEBUG battery flags** — `autoDeclineForBattery` (`:58`) and
`autoAcceptForBattery` (`:67`), both inside `#if DEBUG`, both documented "Never set outside
the battery." So the shape of "a mode that changes what the gate does" is already proven
mechanically; what's missing is a production, persisted, user-visible one.

> **⛔ AND THE UPDATE BELOW IS ITSELF SUPERSEDED 2026-08-26 (Phases 1+2): the
> mode IS user-visible now, `ApprovalMode.selectable` is all three, and the
> decoder's clamp is a no-op on every value this build produces (it stays as
> the guard for the next NARROWING). `.manual` is still the default. The
> battery flags are still untouched and still short-circuit ahead of the mode
> read.**
>
> **📌 UPDATED 2026-08-11 (#224 Phase 0): a production, persisted mode now
> exists — and is deliberately NOT user-visible.** `ApprovalMode`
> (`Talaria/Services/Support/ApprovalModeCore.swift`) ships `.manual` /
> `.smart` / `.off`, persisted as the GLOBAL `UserSettings.approvalMode`
> (ruling 2), read by the gate through
> `ToolConfirmationCenter.modeProvider`. **`.manual` is the only value the
> build can resolve to**: `ApprovalMode.selectable == [.manual]` and the
> settings decoder clamps through `ApprovalMode.resolved(_:)`, so even a blob
> that names `"off"` decodes to `.manual`. The battery flags are untouched and
> still short-circuit ahead of the mode read. So "what's missing" is now just
> the user-visible half, which is Phase 1's and holds per ruling 1.

**The deterministic caution layer already exists, on one tool.**
`DeviceActionTools.dueCaution(for:now:)` (`:305-315`) returns a forge-amber warning string
for three rules: `isPastDue` (5-minute grace, `:57-59`), `isEarlyMorning` (hour ≤ 6,
`:50-52`), `isNextMorning` (asked after 17:00, lands 07:00–11:59 next day, `:65-72`).
Two of those three are #233 and #249 — defects caught **on the card**, which is exactly why
the shelving note calls the cards load-bearing.

> **⛔ "on one tool" SUPERSEDED 2026-08-11 — it is on all three now** (#224
> Phase 0). The three PREDICATES are unchanged and are shared: the new rules
> reuse `isPastDue` and `isEarlyMorning` verbatim rather than restating their
> thresholds. `isNextMorning` stays reminder-only — it reads an evening ask
> resolving to a next-morning DUE, a shape neither an event start nor an alarm
> clock time has. One difference worth knowing before Phase 2 reads these:
> **the two new tools' rows carry no formatted date or time** (the #233-E /
> #249-F rule, asserted digit-free), while the reminder's three still carry
> `displayDate`/`timeOnly` — those predate the rule and were left alone
> deliberately, being #233/#249's shipped, device-validated surface.

**We handle no host approval event.** The SSE switch in `SessionsHermesClient.swift`
handles `run.started` (`:337`), `assistant.delta` (`:342`), `tool.started`/`tool.completed`
(`:348`), `assistant.completed`, `run.completed` (`:407`). There is no `approval.request`
case anywhere in the app, and `InboxItemType.approval` has no producer outside `DemoData`.
That matches #224 §F7 and is unchanged.

**Persistence precedent for what we'd add.** `UserSettings` is one global Codable struct
with hand-written `CodingKeys` and a decoder where every key is
`decodeIfPresent(…) ?? default` (`Talaria/Models/UserSettings.swift:505-543`) — so a new
key is additive and old blobs decode unchanged. `AppLockGracePeriod`
(`Talaria/Services/Support/AppLockCore.swift:11-31`) is the exact precedent for an
enum-valued setting: `String, Codable, CaseIterable, Sendable` + a `displayLabel`.

---

## 3. The design

### 3.1 Scope — what these modes govern

**Our own on-device confirm gate, and nothing else.** Not the host's `approvals.mode`, not
MCP (which `design/MCP_CLIENT_DESIGN.md:75-92` already routes through this same gate and
which stays Manual in its first version regardless), not reads. The Settings copy says so
in words.

Proposed name, to keep it un-confusable with the host's setting and with iOS permissions:
**"Action confirmations"**, values **Ask every time / Ask when unusual / Never ask**.
Internally `ToolApprovalMode { .manual, .smart, .off }` so the mapping to Hermes stays
one-to-one in code and in the tracker.

### 3.2 Global or per-profile? — **GLOBAL. Recommendation: `UserSettings`.**

Backend profiles exist (`Talaria/Models/BackendProfile.swift`,
`Stores/BackendProfilesStore.swift`) and per-profile scoping is a real pattern here. It is
the wrong home for this. The gate governs **this phone's own writes** — EventKit, AlarmKit,
Reminders — which happen identically whether the turn came from the local brain, OJAMD, or
the Mac Mini, and which happen at all when no host is configured (the hostless default of
the launch pivot). Making the safety posture change when you switch hosts is a footgun with
no upside. One key on `UserSettings`, decoded with a `.manual` default.

### 3.3 Where the control sits — **Privacy → a new `// Agent Actions` section**

`PrivacySettingsScreen.swift` already composes `permissionsSection`,
`sensorStreamingSection`, `locationSection`, `appLockSection`, `spotlightSection`,
`revokeSection`, `manageSection` (`:164-170`). Insert **`agentActionsSection` between
`locationSection` and `appLockSection`** — after "what the phone shares," before "who can
open the app," which is the right reading order for "what the agent may do without asking."

Rejected alternatives, briefly: **Developer** — no, this is a real user setting, not an
internal tool (`SettingsChannels.swift:37` calls that channel "INTERNAL TOOLS"). **A new
top-level channel** — no, `SettingsSubsystem` (`SettingsChannels.swift:8-9`) is nine cards
and this is one control; PRIVACY/"PERMISSIONS" already means "what may happen without me."

**HUD form** — reuse what's there, invent nothing: `MonoLabel("// Agent Actions", size: 10,
tracking: .monoXWide, color: .mutedForeground)` as the section header; a three-row selector
inside one `.hudPanel` with `Design.Colors.hairline` dividers, matching `permissionRow`'s
geometry (`:225-247`); each row = `StatusPip` + title + a one-line `MonoLabel` explanation +
a right-aligned selected mark. Colour discipline: **Manual and Smart use
`Design.Brand.accent`; Off uses `Design.Brand.forge`** (the warning amber). Not
`Design.Colors.danger` — danger is for actual danger, and per §3.6 Off still has a floor.
The section subtitle names the blast radius in real terms: *"Reminders, calendar events,
and alarms this phone creates. Reading your data always follows the permissions above."*

### 3.4 What each mode means, per gated flow

| | `createReminder` | `createCalendarEvent` | `scheduleAlarm` | reads (11 tools) |
|---|---|---|---|---|
| **Manual** (default) | card, as today | card, as today | card, as today | unaffected |
| **Smart** | auto-approve when no caution fires; **card when one does** | same, once caution exists | same, once caution exists | unaffected |
| **Off** | auto-approve when no caution fires; **refuse + say so when one does** | same | same | unaffected |

### 3.5 Smart without a classifier — the part I'd most like you to look at

**Smart = `caution == nil` → auto-approve; `caution != nil` → show the card.**

That is not a shortcut around Hermes's design; it is the same shape. Hermes runs a
deterministic detector first and only escalates what it flags; Smart is the layer that
*downgrades noise* on already-flagged items. We have the inverse ratio (everything is
flagged), so the honest translation is: **let the deterministic rules decide which staged
actions are unusual, ask only about those.** Zero model calls, zero added latency, zero
new failure mode — and the rules that would drive it are the ones that already caught #233
and #249.

~~**Precondition, and it is a hard one: `createCalendarEvent` and `scheduleAlarm` pass no
`caution:` today.**~~ Shipping Smart without fixing that would auto-approve *every alarm*,
including a 4 AM one — the precise defect #233 exists to prevent. So Phase 0 below extends
the caution rules to those two tools before any mode ships. If you approve nothing else in
this document, Phase 0 is worth doing on its own merits: it makes the *Manual* card better
too.

> **✅ PRECONDITION DISCHARGED 2026-08-11 — Phase 0 ran and both tools pass a
> `caution:` now.** Smart is no longer blocked on this. Two things Phase 2 must
> read before it uses these rules as its auto-approve discriminator, neither of
> which this section anticipated:
>
> 1. **The wee-hour rule fires on the CANONICAL morning alarm.**
>    `isEarlyMorning` is hours 0–6, so `"6:30am wake up"` — the ordinary alarm,
>    not a defect — carries `EARLY MORNING — CHECK AM/PM` on every card. Under
>    Manual that is one amber line on a card the user is already tapping.
>    **Under Smart it means every pre-7 AM alarm CARDS instead of
>    auto-approving**, which is conservative in the safe direction but is not
>    "ask only about the unusual." Phase 2 should decide deliberately whether
>    that is the behaviour it wants; the threshold is #233's and changing it is
>    that lane's call to make in writing, not a detail to discover in use.
> 2. **The `/alarm` SLASH COMMAND is a different gate and got nothing.**
>    `ChatScreen.swift`'s `.alert("Schedule on this iPhone?", …)` (#193) is a
>    separate consent surface from `ToolConfirmationCenter`, with no caution
>    row and no mode. Phase 0's bars named the `scheduleAlarm` TOOL and that is
>    what was built; if a mode ever ships, this second door has to be answered
>    for or "Never ask" will be untrue of one path into AlarmKit.

**What I deliberately do NOT propose:** routing a staged action through
`LanguageModelSession` for a risk verdict. We already ship one on-device LLM classifier
(`LocalChatBackend+IntentRouting.swift:223-266`, ~1s, fails safe to armed) and the
#200-series is a long record of this model mis-assessing intent. A second one, sitting on
the safety path, would be the worst place to spend that reliability. If you ever want a
model in this loop, it should be the *host's* auxiliary LLM, which is a different item.

### 3.6 Does "Off" belong on a phone? — **Yes, but only with a floor. Here is the argument.**

**For:** the entire blast radius is three CREATE tools. No delete, no send, no modify, no
network egress, no spend. Every artifact lands in Apple's own apps where it is visible and
removable in one tap. That is a categorically smaller radius than the `rm -rf` Hermes's Off
is gambling with — and Hermes ships Off anyway.

**Against, and it is the stronger half:** AlarmKit alarms ring through Silent mode and
Focus — the card's own copy says so (`DeviceActionTools.swift:628`). A wrong alarm is not a
tidy-up-later artifact, it is being woken at 4 AM. And #233 **was caught on a card**: the
model staged an early-morning reminder and the card's caution row is what stopped it. Off,
naively built, would have shipped that.

**Resolution — mirror Hermes exactly: Off has a floor.** Their hardline blocklist trips
before the approval layer, survives `--yolo` and `mode: off`, does not prompt, and returns
an explanatory error to the agent so nothing runs. **Our floor is the caution rules.** In
Off, a staged action that trips a caution rule is **refused, not carded** — the tool returns
the existing refusal-shaped string ("No reminder was created. The requested due time falls
in the early morning…" — `:211`), the model relays it, the user can restate. Off never
prompts, so the name stays honest; the known-defect shapes still don't happen, so it stays
safe.

Note this makes Off ≠ Smart in a way that is easy to say in one line, which is how I'd
know the design is right: **Smart asks you about the unusual ones; Off refuses them.**

### 3.7 The receipt — flagged as a real UI question, not a detail

Under Manual, the transcript carries a card for every write, so the record is complete. If
Smart or Off auto-approves silently, the transcript loses that record and the user's only
evidence is the artifact appearing in another app. The real-data-only rule points one way:
**auto-approved actions should still render in the transcript — as a non-blocking result
row ("Reminder created — Undo"), not a prompt.** I have not designed that row, and it may
be the largest single piece of work here. It is Phase 3 and it is separable; Phases 1–2 are
coherent without it, they just log to `os_log` instead. **Recommendation: ship 1–2 first,
live with it, then decide whether the receipt is wanted.**

### 3.8 What is NOT in this design

No control, display, or mirroring of the host's `approvals.mode`; no `approval.request` SSE
handling; no `POST /v1/runs/{id}/approval` client. §4 says why.

---

## 4. Wire / API reality

**Nothing in this design touches the gateway.** All three modes are app-side, work with no
host configured, and degrade nowhere — that is the strongest argument for building it in
this order.

For completeness, and because #224 asks the question directly, here is what the gateway
supports today:

- **No config plane on the chat port.** `approvals.mode` is readable/writable via
  `/api/config` on the **dashboard app, :9119, dashboard auth** — not on **:8642**. The
  route table (`_http_route_table()`, `gateway/platforms/api_server.py:1980`; the approval
  route sits inside it at `:2024`) has no `/api/config`. This is #224's own 2026-08-02 retraction and it still holds.
- **The approval wire exists on :8642 and is advertised.** `/v1/capabilities` reports
  `"run_approval_response": True` and `"approval_events": True` (`:3050`, `:3052`) and lists
  `run_approval: POST /v1/runs/{run_id}/approval` (`:3079`); the handler is at `:6772` and
  accepts `once | session | always | deny` (`:6796-6799`).
- **But it belongs to the runs plane only.** `register_gateway_notify` appears exactly once
  in the api_server — `:6524`, inside `_handle_runs` (`:6298`). `_handle_session_chat`
  (`:3515`) and `_handle_session_chat_stream` (`:3632`) call `_run_agent` (`:5957`)
  directly and register nothing. So a Sessions-API turn has no approval emitter and no
  answer channel, which is the mechanism behind #224's "the planes are disjoint" probe.
- **What a Talaria chat turn actually does under host `mode: manual`** (code read, not a
  live probe — see the caveat below): `_bind_api_server_session` hardwires
  `platform="api_server"` (`:5946-5955`), so `_is_gateway_approval_context()` is **true**
  (`tools/approval.py:243-261`); the gate enters the gateway branch, finds no notify
  callback, and takes the path whose own comment reads *"No notify callback (e.g. API
  server without an attached chat): queue for /approve /deny review, agent sees
  approval_required"* (`tools/approval.py:3154-3171`). **So it is neither a hang nor a
  silent auto-approve: the command is blocked, a pending approval is queued where nobody on
  our plane can answer it, and the agent is handed "⚠️ This action is potentially dangerous
  … Asking the user for approval," which it will narrate as prose.** The user sees the agent
  say it is asking, and then nothing. That is a sharper description of §F7d's failure than
  "dead turn," and it is worth putting in the tracker either way.
- **Slash commands are not processed on the Sessions plane.** `GatewaySlashCommandsMixin`
  is mixed into `GatewayRunner` (`gateway/run.py:5704`) and nothing else; there is no slash
  dispatch in `api_server.py`. So sending "/approvals smart" as a Talaria chat message is
  just text handed to the model. **Flagged as code-read, not probed** — if we ever wanted
  the cheap version of half (2), a 30-second live probe would settle it, and it is the only
  probe I would spend on this item.
- **Degradation:** none required. If the phone is talking to a host in any mode, our modes
  govern our writes and the host's mode governs the host's; the two never negotiate. The
  only honest thing we owe the user is copy that does not claim otherwise.

---

## 5. Risks, and what holding costs

**Risks of building it**

1. **We would be adding an off switch to the one control that caught #233 and #249.** The
   floor (§3.6) is what makes that acceptable, and the floor is only as good as the caution
   rules — which is why Phase 0 is a precondition and not a nice-to-have.
2. **A caution-rule gap becomes a silent auto-approve.** Under Manual a missing rule costs
   nothing (you still see the card); under Smart/Off it is the whole gate. Mitigation: the
   rules are unit-testable pure functions today, and Phase 0's bars are about coverage.
3. **Off could be enabled and forgotten.** Mitigation: forge-amber row colour, plus the
   Privacy hero already reflects state — worth reflecting Off there too so it is visible
   from the Settings deck without opening the screen.
4. **New persisted key.** Genuinely cheap: additive `CodingKeys` + `decodeIfPresent ??
   .manual`, the pattern every setting in that file uses.
5. **Test surface.** Three modes × three tools × caution/no-caution is 18 cases; they are
   fast unit tests against pure functions plus the existing `DeviceActionToolsTests`
   harness, but the count is real.

**What NOT building costs — stated plainly, because the rule is to write down the failure
mode of the hold**

Honestly: **not much, today.** You have not asked for the cards to stop. #233 happened on a
card. The 2026-08-04 shelving reasoning is still correct on its own terms, and I am not
going to dress this up as urgent.

What the hold actually costs is three things, none of them a crisis:

- **Friction concentrates on the best flow.** The cards are cheapest when actions are rare
  and most expensive during rapid capture — three reminders in a row is three taps on the
  one interaction where speed is the whole value.
- **A launch-facing asymmetry.** The pivot sells a self-contained local brain that can act;
  every action stopping for a tap is a defensible default but it is a default, and we
  currently cannot offer the alternative to anyone.
- **No vocabulary if you ever do want fewer prompts.** That is the real cost of the hold,
  and it is the one this document pays off regardless of your answer: the design exists,
  the floor is argued, the bars are drafted. If the answer is "not now," we have lost
  nothing and the next session does not re-derive it.

**The failure mode of building it anyway** is the more interesting risk: a comfort feature
lands, Off gets set once, and a caution gap we have not found yet turns into an artifact
nobody approved. That is precisely what Phase 0 → Phase 1 ordering is defending against.

---

## 6. Bars sketch (not final) and size per phase

Bars go in the OPEN_ITEMS entry before any run, per the 2026-08-01 convention. These are a
sketch for your review, not the pre-registration.

**Phase 0 — extend the caution layer (precondition). Size: S.**
Worth doing even if every later phase is declined; it improves the Manual card.
- **224-0A:** `scheduleAlarm` stages a caution row for an early-morning alarm and for a
  past-due one; wording carries no formatted date that a model could mine into a fabricated
  success claim (the #233-E / #249-F rule).
- **224-0B:** `createCalendarEvent` stages a caution row for past-due and early-morning
  starts.
- **224-0C:** unit tests cover each rule per tool at boundaries (06:59 / 07:00, the 5-minute
  past-due grace); suite count moves.

> **⚠️ DO NOT CITE THE SKETCH NUMBERS ABOVE — they are not the pre-registration,
> and their letters do not line up with the ones that are.** The bars of record
> were pre-registered in OPEN_ITEMS #224 on 2026-08-11 and RAN that day.
> **Registered 224-0C is the RED-first bar** (the 0A/0B tests must fail before
> the change), and **the boundary coverage above became registered 224-0D**;
> the registration also adds **224-0E** (the mode scaffold), **224-0F** (the
> model-free pin, pulled forward from the Phase 2 sketch's 224-2B) and
> **224-0G** (the gate). A reader who cites "224-0C" from this page means a
> different bar from the one the tracker scored. **Phases 1–3 below remain a
> SKETCH and are NOT pre-registered** — they hold un-dispatched until Owen asks
> for fewer prompts in so many words (ruling 1).

**Phase 1 — Manual / Off, with the floor. Size: S–M.**
- **224-1A:** default is `.manual` on a fresh install AND on a pre-existing settings blob
  with no key present.
- **224-1B:** in `.off`, a clean staged action creates with no card; a caution-tripping one
  creates **nothing** and returns the refusal string.
- **224-1C:** in `.off`, no read tool changes behaviour and no OS permission is bypassed.
- **224-1D:** the Privacy row renders in every theme incl. Paper Tape; Off reads as forge,
  not danger; VoiceOver labels state the consequence, not the mode name alone.
- **224-1E:** gate PASS (units + XCUITest + **Release**), unit count moved.
- **224-1F (device, Owen):** set Off, ask for a normal reminder — it appears with no tap;
  ask for a 4 AM one — nothing is created and the agent says why.

**Phase 2 — Smart. Size: M.**
- **224-2A:** in `.smart`, clean actions auto-approve and caution-tripping ones **card**
  (not refuse) — the one-line difference from Off holds in test.
- **224-2B:** no `LanguageModelSession` is constructed on the approval path (asserted, so a
  later lane cannot quietly add one).
- **224-2C:** measured on device across the #200-series action prompts: create rate under
  Smart matches Manual-with-approve, and every caution-flagged trial still produced a card.
- **224-2D:** gate PASS, count moved.

**Phase 3 — transcript receipts for auto-approved actions. Size: M. Optional, decide later.**
- **224-3A:** every auto-approved action renders a non-blocking result row with an Undo
  affordance; nothing about it re-enters the model's context (the #200F echo rule).

**Not a phase, and not proposed:** anything that reads or writes the host's
`approvals.mode`, handles `approval.request`, or calls `/v1/runs/{id}/approval`.
**Size if you ever want it: L**, and most of it is upstream, not ours.

---

## 7. Questions for Owen

Each has my recommendation. "Approved" means all of them as recommended.

1. **Build this at all, or leave #224 shelved with this document attached as the design?**
   *Recommendation:* **Do Phase 0 now; hold Phases 1–3 until you actually want fewer
   prompts.** Phase 0 is a Manual-card improvement that stands alone, and it is the
   precondition for everything else, so doing it costs nothing if you never ask for modes.

2. **Global setting, or per backend profile?**
   *Recommendation:* **Global (`UserSettings`).** The gate governs this phone's writes, which
   are identical across hosts and still happen with no host at all.

3. **Does "Off" ship?**
   *Recommendation:* **Yes — but only with the floor** (caution-tripping actions are refused,
   never silently created). Without the floor my answer flips to no, because #233 was caught
   on a card.

4. **Is the floor's behaviour right — refuse rather than card?**
   *Recommendation:* **Refuse.** It mirrors Hermes's hardline blocklist exactly (no prompt,
   explanatory error, nothing runs) and it keeps the name "Off" honest. Carding instead would
   make Off silently identical to Smart.

5. **Smart as deterministic rules, or not at all?**
   *Recommendation:* **Rules, or not at all — never the on-device model.** If rules feel too
   thin to call "Smart," I would rather ship two modes (Manual / Off) and leave the third
   name unused than put the ~3B model on the safety path.

6. **Privacy screen, between Location and App Lock — right home?**
   *Recommendation:* **Yes.** If you would rather it sat next to the chat controls, that is a
   real alternative, but there is no chat-settings surface today and creating one for a single
   control is worse.

7. **Do auto-approved actions need a transcript receipt (Phase 3), or is os_log enough for
   now?** *Recommendation:* **Defer.** Ship 1–2, live with it a week, then decide — the
   answer depends on whether silent creates actually feel unaccountable in use, which neither
   of us can predict from here.

8. **Do you want the 30-second probe on whether `/approvals smart` typed into Talaria reaches
   the host's slash handler?** *Recommendation:* **Not now.** The code says no (§4), your host
   has approvals off, and the probe only matters if you want half (2) — which stays parked.
   Say the word if you want it settled anyway; it is cheap.

---

**What I need from you:** "approved", or the numbers you'd flip. Nothing gets built before
you answer.
