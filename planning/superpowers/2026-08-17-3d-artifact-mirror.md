# 3D Artifact Mirror (#362) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agent-written files (`write_file`/`create_file`) regain real Tier-1 content on the
runs plane by mirroring the tool args over the talaria plugin's outbox, correlated app-side to
the right transcript turn — plus the #270 probe-noise fix on the same plugin deploy.

**Architecture:** Plugin registers a `pre_tool_call` observer hook (fires synchronously on the
tool-dispatch path, both lanes) that appends a `kind="artifact"` outbox row (text = file
content, meta = `{session_id, turn_id, tool_call_id, path, ts}`) targeted at the single active
device. The app routes artifact-kind drained items away from the inbox into a new correlator
that matches session_id + path against the message's existing `write_file` tool-activity rows
(name+preview survive transcript refetch), attaches the standard Tier-1
`MessageAttachment.agentFile`, persists via the sidecar, and drops-with-ack on any mismatch.
The correlation key is **session_id + path** — NOT turn_id, which the app can never learn
(verified dead at Hermes head `133381508`; dated note in the design doc §2.8).

**Tech Stack:** Python 3.11 (plugin, pytest, stdlib-only), Swift/SwiftUI (app, Swift Testing),
SQLite (plugin outbox), the existing plugin-link drain loop.

## Global Constraints

- **Bars 3D-A..H are pre-registered in `OPEN_ITEMS.md` #362 (2026-08-17 late-night block). A
  missed bar is a falsification, not a redefinition.**
- 🔐 **Live-install gate:** NOTHING touches `~/.hermes/plugins/talaria`, the live gateway, or
  the desktop backend until Owen's explicit per-slice go (plan §5 Q6 shape). All build work
  happens in a fresh clone (plugin) and this repo (app).
- **Deploy order: app half merges BEFORE the plugin deploys.** An old app renders
  artifact-kind items as junk inbox rows (`talariaInboxItem(from:)` maps every item today).
- **Plugin repo discipline:** PR + DO-NOT-MERGE until Owen's re-review (the #351 shape).
  Plugin suite baseline: measure with `pytest tests/ -q` before any change; count must MOVE.
- **App gate:** `scripts/mac/lane-gate.sh` with `TALARIA_SIM_NAME` from the fixed pool
  (`CC-lane-1/2/3`), TCC grants (`xcrun simctl privacy <udid> grant calendar|reminders
  org.aethyrion.talaria27`) immediately before EVERY run, Release build included, app count
  MOVED from 2289. `DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer`.
- **The hook must never raise and never block** — it runs inline on the tool-dispatch hot
  path (a raising hook is swallowed by the gateway, but our contract is stricter: no reliance
  on that). Local SQLite append only; no network I/O.
- **No fabrication, ever** (3A-D lineage): content comes only from the mirror item; a
  mismatched/late item is dropped, never guessed onto a message.
- **The runs-plane pinned test `writeFileToolStartedProducesNoArtifact`
  (`TalariaTests/RunsPlaneTransportTests.swift:538-571`) stays untouched and green.**

## Questions for Owen (answers gate the marked tasks)

1. **Bars sign-off** — #362's 3D-A..H block. *(Gates all build tasks.)*
2. **Per-slice live-install go** — "3D is approved, including the plugin deploy, the gateway
   bounce, and the desktop-backend restart." Named cost: the bounce advances the serving
   Hermes from `3b9a963b8` (listener since Aug 17 00:02) to the checkout head `133381508`+
   (auto-updated Aug 17 18:03). *(Gates Tasks D1–D3 only.)*
3. **Probe-noise fix pick (bar 3D-F):** **(a) recommended** — cache the pane probe's verdict
   in `dashboard/plugin_api.py` (re-probe at most every 60 s success / 10 s failure; device
   rows stay 5 s-fresh); (b) slow the pane's `refetchInterval` (loses device-row freshness);
   (c) tag-and-filter only (keeps ~17k lines/day). Plan assumes (a).
4. **Outbox TTL:** artifact rows have no expiry — a never-drained mirror accumulates in
   `talaria.db` forever. Recommendation: ship v0 WITHOUT TTL, file a follow-up tracker item
   for outbox hygiene (it affects `message` rows too). OK?
5. **Content cap:** mirror full content (parity with the sessions plane, which already ships
   full `args.content` over SSE — recommended), or cap at N KB with a `truncated` meta flag?

---

## Phase P — plugin half (fresh clone of `AethyrionAI/talaria-plugin`)

Setup (fold into Task P1): `git clone git@github.com:AethyrionAI/talaria-plugin.git` into the
session scratchpad, branch `3d-artifact-mirror`, verify baseline `pytest tests/ -q` green and
record the count. CI installs `NousResearch/hermes-agent` for `gateway.*` imports; locally the
hermes venv (`~/.hermes/hermes-agent/venv`) serves the same role — run pytest with that venv's
interpreter, same as #351 did.

### Task P1: `outbox.append` learns `kind`

**Files:**
- Modify: `talaria/outbox.py` (`_new_item` :37-46, `append` :82-123, `append_for_devices` :126-143)
- Test: `tests/test_outbox.py`

**Interfaces:**
- Produces: `outbox.append(text, meta=None, *, target_device_id=None, kind="message") -> dict`
  — returned item dict and wire dict carry the given `kind`. Default unchanged.

- [ ] **Step 1: Write the failing test** (in `tests/test_outbox.py`, follow the existing
  monkeypatched-`database_path` + seeded-device pattern at :8-9):

```python
def test_append_kind_artifact_rides_row_and_wire(tmp_path, monkeypatch):
    _use_tmp_db(tmp_path, monkeypatch)          # existing helper pattern in this file
    device = _seed_device()                      # existing helper pattern in this file
    item = outbox.append("file-bytes", meta={"path": "a.txt"},
                         target_device_id=device["id"], kind="artifact")
    assert item["kind"] == "artifact"
    pending = outbox.pending(device["id"])
    assert [p["kind"] for p in pending] == ["artifact"]

def test_append_kind_defaults_to_message(tmp_path, monkeypatch):
    _use_tmp_db(tmp_path, monkeypatch)
    device = _seed_device()
    item = outbox.append("hi", target_device_id=device["id"])
    assert item["kind"] == "message"
```

- [ ] **Step 2: Run to verify failure** — `pytest tests/test_outbox.py -q` → FAIL
  (`append() got an unexpected keyword argument 'kind'`).
- [ ] **Step 3: Implement** — thread `kind` through `append`/`append_for_devices` into
  `_new_item(kind=kind)`; keyword-only, default `"message"`. No schema change (no CHECK on
  `kind`).
- [ ] **Step 4: Run** — `pytest tests/test_outbox.py -q` → PASS; full suite green.
- [ ] **Step 5: Commit** — `feat(outbox): kind parameter for non-message items (3D)`.

### Task P2: the mirror hook — `talaria/artifact_mirror.py`

**Files:**
- Create: `talaria/artifact_mirror.py`
- Create: `tests/test_artifact_mirror.py`
- Modify: `talaria/__init__.py:register()` (:17-34) — add `artifact_mirror.register_hooks(ctx)`
  beside the existing three registrations.
- Modify: `plugin.yaml` — version `0.2.0 → 0.3.0`.

**Interfaces:**
- Consumes: `outbox.append(..., kind="artifact")` from P1; `store.devices()`;
  `transport.HUB.wake(device_id)`; gateway hook kwargs
  `(tool_name, args, task_id, session_id, tool_call_id, turn_id, api_request_id,
  middleware_trace)` — invoked synchronously, return value `None` = observer.
- Produces: `register_hooks(ctx)`; handler `_on_pre_tool_call(**kwargs) -> None`;
  seam `_api_plane() -> bool` and `_single_active_device() -> dict | None` (monkeypatch
  targets for tests).

- [ ] **Step 1: Write the failing tests.** Mutation-first (the plan-authored-code lesson:
  test the wrong versions a lazy implementation would produce, not just the happy path):

```python
# tests/test_artifact_mirror.py — DI/monkeypatch style like test_envelope.py
def test_write_file_on_api_plane_appends_artifact(...):
    # args={"path": "a.txt", "content": "abc"}, session_id="s1", one active device,
    # _api_plane→True. Assert: exactly one outbox row; kind=="artifact"; text=="abc";
    # meta == {"session_id":"s1","turn_id":"t1","tool_call_id":"c1","path":"a.txt","ts":ANY};
    # HUB.wake called once with the resolved device id.

def test_non_write_tools_and_non_api_plane_produce_nothing(...):
    # tool_name="read_file" → no row. _api_plane→False → no row. session_id="" → no row.

def test_arg_key_drift_matches_app_tolerance(...):
    # {"file_path": "a.txt", "content": "x"} appends (path drift);
    # {"path": "a.txt"} with NO content key → no row (pointer-only writes don't mirror);
    # content not a str (dict/None) → no row.

def test_zero_or_multiple_devices_fail_closed_silently(...):
    # 0 active devices → no row, no raise. 2 active devices → no row, no raise.

def test_handler_never_raises(...):
    # outbox.append monkeypatched to raise; HUB.wake monkeypatched to raise;
    # _api_plane monkeypatched to raise → handler returns None each time, no exception.

def test_create_file_also_mirrors(...):

def test_register_hooks_registers_pre_tool_call(...):
    # fake ctx records (hook_name, callback); assert ("pre_tool_call", _on_pre_tool_call).
```

- [ ] **Step 2: Run to verify failure** — module doesn't exist.
- [ ] **Step 3: Implement** `talaria/artifact_mirror.py` (sketch — adjust to the repo's
  logging/import idioms; `admin.py`'s untargeted-send path is the precedent for the
  single-device rule):

```python
_WRITE_TOOLS = {"write_file", "create_file"}

def _api_plane() -> bool:
    try:
        from gateway.session_context import get_session_env
        return get_session_env("HERMES_SESSION_PLATFORM", "") == "api_server"
    except Exception:
        return False          # fail-closed; log at debug

def _single_active_device():
    active = [d for d in store.devices() if d.get("active")]
    return active[0] if len(active) == 1 else None

def _on_pre_tool_call(tool_name="", args=None, task_id="", session_id="",
                      tool_call_id="", turn_id="", **_kwargs):
    try:
        if tool_name not in _WRITE_TOOLS or not session_id or not _api_plane():
            return None
        a = args if isinstance(args, dict) else {}
        path = a.get("path") or a.get("file_path") or a.get("filename")
        content = a.get("content") if isinstance(a.get("content"), str) else None
        if not path or content is None:
            return None
        device = _single_active_device()
        if device is None:
            return None
        outbox.append(content, meta={
            "session_id": session_id, "turn_id": turn_id,
            "tool_call_id": tool_call_id, "path": str(path),
            "ts": _utc_now_iso(), "type": "written_file",
        }, target_device_id=device["id"], kind="artifact")
        HUB.wake(device["id"])
    except Exception:
        logger.debug("artifact mirror skipped", exc_info=True)
    return None

def register_hooks(ctx):
    ctx.register_hook("pre_tool_call", _on_pre_tool_call)
```

- [ ] **Step 4: Run** — new tests PASS, full suite green, count MOVED from baseline.
- [ ] **Step 5: Commit** — `feat(mirror): pre_tool_call artifact mirror to outbox (3D, #362)`.

### Task P3: probe-noise fix (bar 3D-F; assumes Owen picks (a))

**Files:**
- Modify: `dashboard/plugin_api.py` (`probe_gateway_adapter` :82-100, `status` :103-115)
- Test: `tests/test_dashboard_api.py`

**Interfaces:**
- Produces: `probe_gateway_adapter(url=None, *, now=time.monotonic)` — unchanged result
  shape; module-level cache `{ts, result}`; floors `_PROBE_CACHE_OK_SECONDS = 60.0`,
  `_PROBE_CACHE_FAIL_SECONDS = 10.0`.

- [ ] **Step 1: Failing tests** — count actual `urllib.request.urlopen` invocations via
  monkeypatch: two probes inside the floor → ONE network call, same result object; advance
  the injected clock past the floor → second call; an `unreachable` result re-probes after
  10 s not 60 s; `/status` still returns fresh `devices` on every call (only the probe is
  cached).
- [ ] **Step 2: Run** — FAIL (two network calls observed).
- [ ] **Step 3: Implement** the cache (module-level dict, injectable `now`, no threads —
  FastAPI threadpool access is already the file's concurrency model; a stale double-probe
  race is harmless and not worth a lock).
- [ ] **Step 4: Run** — PASS; suite green.
- [ ] **Step 5: Commit** — `fix(dashboard): cache the adapter liveness probe (#362 3D-F)`.

### Task P4: plugin PR

- [ ] Push branch; open PR titled `3D artifact mirror + probe cache (#362)` with
  **DO-NOT-MERGE** until Owen's re-review; body describes the three commits and the bars
  they serve (3D-B, 3D-F). CI must be green.

---

## Phase A — app half (this repo, branch `3d-artifact-mirror-app`)

### Task A1: typed artifact-item parse

**Files:**
- Create: `Talaria/Models/ArtifactMirrorItem.swift`
- Test: `TalariaTests/ArtifactMirrorItemTests.swift`

**Interfaces:**
- Consumes: `TalariaPlatformItem` (`Talaria/Models/TalariaPlatform.swift:21-32` —
  `{id, kind, text, createdAt, meta: [String:String]?}`).
- Produces:
  ```swift
  struct ArtifactMirrorItem: Equatable {
      let platformItemID: String
      let sessionID: String
      let path: String
      let content: String
      let turnID: String?
      let toolCallID: String?
      let hostTimestamp: String?
      static func parse(_ item: TalariaPlatformItem) -> ArtifactMirrorItem?
  }
  ```
  `parse` returns nil unless `kind == "artifact"` AND meta carries non-empty
  `session_id` + `path` (content = `item.text`, may be empty string but not absent).

- [ ] **Step 1: Failing tests** — parses a full fixture; nil for kind=="message"; nil for
  missing session_id; nil for missing path; empty-string content parses (empty file is a
  real file). Fixture mirrors the wire shape in `TalariaPlatformLinkTests.swift:121`.
- [ ] **Step 2: RED** → **Step 3: implement** → **Step 4: GREEN** → **Step 5: commit**
  `feat(link): typed artifact mirror item (3D, #362)`.

### Task A2: routing — artifacts never reach the inbox

**Files:**
- Modify: `Talaria/Stores/AppContainer.swift:964-979` (the `onItemsReceived` wiring)
- Test: `TalariaTests/ArtifactMirrorRoutingTests.swift`

**Interfaces:**
- Consumes: `ArtifactMirrorItem.parse` (A1); `InboxStore.receivePlatformItems`
  (`Talaria/Stores/InboxStore.swift:89-94`).
- Produces: split dispatch — items where `parse` returns non-nil go to
  `artifactMirrorCorrelator.receive(_:)` (A3); everything else follows today's inbox path
  unchanged. (Ack is untouched: the link acks all drained items already —
  `drainParsesItemsAndAcksThem` pins it — which is exactly bar 3D-A's "dropped and still
  acked".)

- [ ] **Step 1: Failing test** — feed `[artifactItem, messageItem]` through the dispatch
  closure with a spy inbox + spy correlator: inbox sees ONLY the message item; correlator
  sees ONLY the artifact. Existing `TalariaPlatformInboxServiceTests` stay untouched (3D-C).
- [ ] Steps 2–5: RED → implement → GREEN → commit
  `feat(link): route artifact items to the mirror correlator, not the inbox (3D-C)`.

### Task A3: the correlator (bar 3D-A core)

**Files:**
- Create: `Talaria/Services/ArtifactMirrorCorrelator.swift`
- Test: `TalariaTests/ArtifactMirrorCorrelatorTests.swift`

**Interfaces:**
- Consumes: `ChatStore` conversation/message access (session identity:
  `journal.activeHop.apiSessionId`, `ChatStore.swift:361` area); tool-activity rows on
  messages (name + preview — the runs plane records `write_file` with preview = path);
  `MessageAttachment.agentFile(remotePath:content:)` (`Message.swift:255-268`);
  `AgentAttachmentSidecar` persistence (`Models/AgentAttachmentSidecar.swift`).
- Produces (`@MainActor`):
  ```swift
  final class ArtifactMirrorCorrelator {
      func receive(_ item: ArtifactMirrorItem)   // correlate now or hold
      func retryPending()                        // ChatStore calls after stream updates / openSession
      // internal: holdWindow (120s), pending buffer, drop on expiry
  }
  ```
  Match rules, in precedence order (each falls through to the next):
  1. Conversation lookup by `sessionID`; no conversation → HOLD (the turn may still be
     opening) → drop at expiry.
  2. In that conversation, newest-first: a message with a pointer-only attachment
     (`localStoragePath == nil`, remotePath/fileName matching `path`) → **upgrade in place**
     (stage bytes via `MessageAttachment.agentFile`, keep the original attachment `id` so
     sidecar/merge dedupe holds) — this kills the dup-chip risk from the runs plane's
     Tier-2 prose sweep.
  3. Else a message whose tool activities contain `write_file`/`create_file` with
     preview == `path` AND no existing attachment for `path` → append a new anchored
     attachment (anchor at the matched activity's offset; nil → trailing grid) + sidecar
     persist.
  4. Else HOLD; at expiry DROP (count it — a silent drop is the S6 shape; a debug-log line
     with sessionID+path suffices, no UI).

- [ ] **Step 1: Failing tests** (the mutation set — each pins a wrong-but-plausible
  implementation):
  - happy path: attaches to the RIGHT message when two messages in the conversation both
    wrote files (different paths);
  - same path written twice in one conversation → attaches to the NEWEST unfilled match,
    second item fills the older one (order-independence pinned);
  - unknown session → held then dropped at expiry, NO attachment anywhere;
  - path mismatch → held then dropped;
  - already-filled (Tier-1 attachment exists for path) → dropped, attachment count
    unchanged (no dup);
  - pointer-only upgrade: runs-plane prose-swept fetchable attachment for the same path is
    upgraded in place — attachment count does NOT grow, `localStoragePath` becomes
    non-nil, id unchanged;
  - sidecar row written on attach (reopen-persistence is A4's integration case).
- [ ] Steps 2–5: RED → implement → GREEN → commit
  `feat(chat): artifact mirror correlator — session+path match, drop on mismatch (3D-A)`.

### Task A4: timing integration (bar 3D-D)

**Files:**
- Modify: `Talaria/Stores/ChatStore.swift` (call `retryPending()` after streaming update
  application and at `openSession` completion)
- Test: `TalariaTests/ArtifactMirrorTimingTests.swift`

- [ ] **Step 1: Failing tests** —
  - EARLY: `receive` an item whose activity hasn't arrived; then apply the `.toolActivity`
    update; `retryPending()` attaches it (assert attachment present after, absent before);
  - LATE: simulate post-run drain — conversation reloaded via the fake-client `openSession`
    pattern from `AgentFileChipPersistenceTests.swift` (server transcript carries the
    activity but no attachments), `receive` the item, assert attach + sidecar row, then
    reopen the thread and assert the chip survives (sidecar replay);
  - EXPIRY: injected clock past holdWindow → `retryPending()` drops, buffer empty.
- [ ] Steps 2–5: RED → wire the two `retryPending()` call sites → GREEN → commit
  `feat(chat): early/late artifact correlation across stream and refetch (3D-D)`.

### Task A5: honest-absence guard (bar 3D-E)

**Files:**
- Test: `TalariaTests/RunsPlaneTransportTests.swift` (ADD one test; the pinned
  `writeFileToolStartedProducesNoArtifact` at :538-571 is NOT edited)

- [ ] **Step 1:** New test: a full runs-plane turn (scripted-SSE stub) + a mirrored item fed
  through the correlator yields EXACTLY ONE attachment for the path, Tier-1, on the right
  message — and zero `.artifactProduced` stream updates (the stream stays honest; content
  arrived only via the mirror).
- [ ] Steps 2–5: RED (correlator not yet wired in that harness) → wire → GREEN → commit
  `test(runs): mirror is the only Tier-1 source on the runs plane (3D-E)`.

### Task A6: gate + PR

- [ ] TCC grants, then `scripts/mac/lane-gate.sh` on a free `CC-lane-N` (backgrounded, poll
  the log; count must MOVE from 2289; Release included). GATE: PASS required.
- [ ] Open the app PR referencing #362; record per-bar verdicts (3D-A/C/D/E + G's app half)
  in the entry. Await Owen's merge. **App merge unblocks the plugin deploy (deploy order).**

---

## Phase D — deploy + device (ALL gated on Owen's per-slice go)

### Task D1: plugin merge + live deploy (Mac)
- [ ] Owen re-reviews and merges the plugin PR. Then, under the go: `git -C
  ~/.hermes/plugins/talaria pull`, bounce the gateway (`kill` the launchd-supervised
  process), **verify the LISTENER not the PID** (`lsof -nP -iTCP:8642 -sTCP:LISTEN`; budget
  a second restart — the Errno-48 race is real), and confirm by reflog-vs-start-time which
  Hermes head now serves (expected: checkout head `133381508`+ — named in the go).
- [ ] Restart the desktop app (its own `hermes serve` is a separate plugin reader — the
  probe cache doesn't bite until it relaunches).

### Task D2: measure 3D-F
- [ ] `grep "platforms/talaria/events" ~/.hermes/logs/agent.log` per-minute counts: ~12/min
  before, ≤1/min after (60 s floor). Record before/after in #362.

### Task D3: device pass 3D-H (Owen driving)
- [ ] On whoGoesThere, runs path ON: ask the agent to write a small text file → the chip
  renders REAL content (open the preview sheet); host log shows the hook fired; ack lands
  (no redelivery on next drain).
- [ ] Negative arm: a `write_file` in a session the phone doesn't own (e.g. Owen's desktop
  or a CLI-run API session) → no chip, no inbox row on the phone.
- [ ] OJAMD rollout is a separate, later step (same `hermes plugins update` shape as #351's
  deploy) — NOT part of this lane's device pass; file its own line in #362 when this lands.

### Close-out (per #317)
- [ ] Verdicts for every bar in #362; correct any doc this lane's results falsify in the
  same commit (candidates already corrected at lane open: §2.8 turn_id note, the NIGHT
  handoff's "bad key"). New handoff notes the lane state.
