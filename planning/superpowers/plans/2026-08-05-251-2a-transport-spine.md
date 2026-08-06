# #251-2A Transport Spine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The phone auto-pairs to the gateway's `talaria` platform, agent-initiated messages land durably in the app Inbox (relay feed retired), and `talaria_phone_query` answers live from the phone via a long-poll drain.

**Architecture:** Plugin side: a pure-python envelope core (`outbox.py`, `transport.py`, `envelope.py` — unit-testable without hermes imports where possible) wrapped by a thin `TalariaPlatformAdapter(BasePlatformAdapter)` shell registered via `ctx.register_platform`; inbound rides the existing `POST /api/platforms/talaria/events` on `:8642`. App side: `TalariaPlatformLink` (foreground drain loop + auto-pair), `PhoneQueryResponder` (structured catalog → belt read machinery), `TalariaPlatformInboxService` replacing `LiveInboxService`.

**Tech Stack:** Python 3 + pytest (hermes venv) for the plugin; Swift 6 / Swift Testing / XCUITest for the app; xcodegen; `scripts/mac/lane-gate.sh`.

**Spec:** `planning/superpowers/specs/2026-08-05-251-2a-transport-spine-design.md` (+ its Addendum section — two plan-time mechanics: the payload `auth` field, and query results as `{"text": …}` prose).

## Global Constraints

- Never patch Hermes core; never touch `relay/` or `connector/` (⛔ standing).
- Plugin work happens IN `~/.hermes/plugins/talaria` (the clone IS the install); commits push to `AethyrionAI/talaria-plugin` `main`.
- App work on branch `claude/t27-251-2a-spine` in Talaria-27; `xcodegen generate` after any file add/delete; `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in every xcodebuild shell.
- Never print `API_SERVER_KEY` (read it into shell vars from `.env`; tests use fakes).
- Tokens stored SHA-256 server-side; records deactivated, never deleted (#144).
- Tool results are ordinary OUTPUT, never a throw (#197); an executed call is not a refusal (#232).
- Envelope auth semantics: `pair` requires the API key; `drain`/`ack`/`query_result`/`unpair` require the device's own token bound to `device_id`. Header authenticates (route 401s), payload `auth` field authorizes (dispatch checks).
- Real data only in UI; "—" where unknowable.
- App Swift tests: `TalariaTests` (Swift Testing, `@Test`/`#expect`); run via the CC-* sims by id, and verify the reported test COUNT MOVED after adding tests.
- Long-poll hold ≤25s server-side; app URLSession per-request timeout 40s; `check_fn` liveness window 60s.
- Plugin catalog kinds (exact strings): `location`, `health`, `motion`, `weather`, `calendar`, `reminders`, `deviceStatus`.
- Privacy gates app-side: `sensorStreamingEnabled` (master) + `healthCollectionEnabled` / `locationCollectionEnabled` / `motionCollectionEnabled` gate health/location/motion/weather; calendar/reminders/deviceStatus follow iOS permissions only.

---

## Part 1 — Plugin (`~/.hermes/plugins/talaria`)

### Task 1: Test runner + durable outbox (`outbox.py`)

**Files:**
- Create: `~/.hermes/plugins/talaria/outbox.py`
- Create: `~/.hermes/plugins/talaria/tests/__init__.py` (empty)
- Test: `~/.hermes/plugins/talaria/tests/test_outbox.py`

**Interfaces:**
- Consumes: nothing new (mirrors `store.py`'s `_load/_save` JSON pattern).
- Produces: `append(text: str, meta: dict | None = None) -> dict`, `pending() -> list[dict]`, `mark_delivered(item_ids: list[str]) -> list[str]`, `_outbox_path() -> Path` (monkeypatch seam). Item shape: `{"id": <12-hex>, "kind": "message", "text", "created_at": <iso>, "meta": {}, "delivered_at": None, "active": True}`.

- [ ] **Step 1: Install pytest into the hermes venv (one-time)**

```bash
~/.hermes/hermes-agent/venv/bin/pip install --quiet pytest
~/.hermes/hermes-agent/venv/bin/python -m pytest --version
```

If the pip install is denied by the shell classifier, stop and report BLOCKED — do not improvise a different interpreter.

- [ ] **Step 2: Write the failing tests**

`tests/test_outbox.py`:

```python
import importlib

from .. import outbox


def _redirect(monkeypatch, tmp_path):
    monkeypatch.setattr(outbox, "_outbox_path", lambda: tmp_path / "outbox.json")


def test_append_then_pending(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    item = outbox.append("hello phone", meta={"source": "test"})
    assert item["kind"] == "message"
    assert item["text"] == "hello phone"
    rows = outbox.pending()
    assert [r["id"] for r in rows] == [item["id"]]


def test_pending_is_oldest_first_and_excludes_delivered(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    first = outbox.append("one")
    second = outbox.append("two")
    outbox.mark_delivered([first["id"]])
    rows = outbox.pending()
    assert [r["id"] for r in rows] == [second["id"]]


def test_mark_delivered_is_idempotent_and_reports_only_real_acks(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    item = outbox.append("one")
    assert outbox.mark_delivered([item["id"], "nonsense"]) == [item["id"]]
    assert outbox.mark_delivered([item["id"]]) == []


def test_outbox_survives_reload(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    item = outbox.append("durable")
    # Fresh read from disk — nothing cached in module state.
    rows = outbox.pending()
    assert rows and rows[0]["id"] == item["id"]
    raw = (tmp_path / "outbox.json").read_text(encoding="utf-8")
    assert "durable" in raw
```

- [ ] **Step 3: Run to verify failure**

```bash
cd ~/.hermes/plugins/talaria && ~/.hermes/hermes-agent/venv/bin/python -m pytest tests/test_outbox.py -v
```

Expected: FAIL — `No module named 'talaria.outbox'` (or attribute error).

- [ ] **Step 4: Implement `outbox.py`**

```python
"""Durable agent→phone outbox for the Talaria plugin.

Same JSON-file family as store.py (HERMES_HOME/talaria/), same #144
convention: items are marked delivered, never deleted. `pending()` is
fetch-on-connect by construction — the first drain after days away gets
the whole backlog, oldest first.
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path

from hermes_constants import get_hermes_home


def _outbox_path() -> Path:
    return Path(get_hermes_home()) / "talaria" / "outbox.json"


def _load() -> dict:
    path = _outbox_path()
    if not path.exists():
        return {"items": []}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        backup = path.with_suffix(".json.corrupt")
        try:
            path.rename(backup)
        except OSError:
            pass
        return {"items": []}


def _save(data: dict) -> None:
    path = _outbox_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    tmp.chmod(0o600)
    tmp.replace(path)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def append(text: str, meta: dict | None = None) -> dict:
    item = {
        "id": uuid.uuid4().hex[:12],
        "kind": "message",
        "text": text,
        "created_at": _now_iso(),
        "meta": meta or {},
        "delivered_at": None,
        "active": True,
    }
    data = _load()
    data["items"].append(item)
    _save(data)
    return item


def pending() -> list[dict]:
    data = _load()
    return [
        i for i in data.get("items", [])
        if i.get("active") and not i.get("delivered_at")
    ]


def mark_delivered(item_ids: list[str]) -> list[str]:
    wanted = set(item_ids or [])
    data = _load()
    acked: list[str] = []
    for item in data.get("items", []):
        if item.get("id") in wanted and not item.get("delivered_at"):
            item["delivered_at"] = _now_iso()
            acked.append(item["id"])
    if acked:
        _save(data)
    return acked
```

Also create empty `tests/__init__.py` so relative imports work.

- [ ] **Step 5: Run to verify pass**

Same command as Step 3. Expected: 4 passed.

- [ ] **Step 6: Commit**

```bash
cd ~/.hermes/plugins/talaria && git add outbox.py tests/ && git commit -m "feat(2A): durable outbox — append/pending/mark_delivered, #144 semantics"
```

### Task 2: In-memory transport hub (`transport.py`)

**Files:**
- Create: `~/.hermes/plugins/talaria/transport.py`
- Test: `~/.hermes/plugins/talaria/tests/test_transport.py`

**Interfaces:**
- Consumes: stdlib only (`asyncio`, `time`).
- Produces: `class TransportHub` with `touch(device_id)`, `is_live(window_seconds=60.0) -> bool`, `async park(device_id, timeout=25.0)`, `wake(device_id=None)`, `enqueue_query(device_id, kind, params) -> tuple[str, asyncio.Future]`, `take_queries(device_id) -> list[dict]`, `resolve_query(query_id, result=None, error=None) -> bool`, `freshest_device() -> str | None`; module singleton `HUB = TransportHub()`. Query payload shape: `{"id", "kind", "params"}`.

- [ ] **Step 1: Write the failing tests**

`tests/test_transport.py`:

```python
import asyncio

import pytest

from ..transport import TransportHub


def test_is_live_tracks_touch_within_window():
    now = [100.0]
    hub = TransportHub(time_fn=lambda: now[0])
    assert hub.is_live(60) is False
    hub.touch("dev1")
    assert hub.is_live(60) is True
    now[0] += 61
    assert hub.is_live(60) is False


def test_freshest_device_prefers_latest_touch():
    now = [100.0]
    hub = TransportHub(time_fn=lambda: now[0])
    hub.touch("old")
    now[0] += 5
    hub.touch("new")
    assert hub.freshest_device() == "new"


@pytest.mark.asyncio
async def test_park_returns_early_on_wake():
    hub = TransportHub()
    task = asyncio.create_task(hub.park("dev1", timeout=5.0))
    await asyncio.sleep(0.01)
    hub.wake("dev1")
    await asyncio.wait_for(task, timeout=0.5)  # returns well before 5s


@pytest.mark.asyncio
async def test_park_expires_on_timeout():
    hub = TransportHub()
    await asyncio.wait_for(hub.park("dev1", timeout=0.05), timeout=0.5)


@pytest.mark.asyncio
async def test_parked_device_counts_as_live():
    hub = TransportHub(time_fn=lambda: 100.0)
    task = asyncio.create_task(hub.park("dev1", timeout=0.2))
    await asyncio.sleep(0.01)
    assert hub.is_live(60) is True
    await task


@pytest.mark.asyncio
async def test_query_cycle_enqueue_take_resolve():
    hub = TransportHub()
    qid, future = hub.enqueue_query("dev1", "location", {})
    taken = hub.take_queries("dev1")
    assert taken == [{"id": qid, "kind": "location", "params": {}}]
    assert hub.take_queries("dev1") == []  # take drains
    assert hub.resolve_query(qid, result={"text": "here"}) is True
    assert (await asyncio.wait_for(future, 0.5)) == {"text": "here"}
    assert hub.resolve_query(qid, result={}) is False  # already resolved


@pytest.mark.asyncio
async def test_resolve_with_error_resolves_future_with_error_dict():
    hub = TransportHub()
    qid, future = hub.enqueue_query("dev1", "health", {"metric": "steps"})
    hub.resolve_query(qid, error="permission_denied")
    assert (await asyncio.wait_for(future, 0.5)) == {"error": "permission_denied"}
```

Add `pytest-asyncio` alongside pytest if the async tests error with "async def functions are not natively supported":

```bash
~/.hermes/hermes-agent/venv/bin/pip install --quiet pytest-asyncio
```

and create `~/.hermes/plugins/talaria/pytest.ini`:

```ini
[pytest]
asyncio_mode = auto
```

(With `asyncio_mode = auto` the `@pytest.mark.asyncio` decorators are redundant but harmless.)

- [ ] **Step 2: Run to verify failure** — same pytest invocation, `tests/test_transport.py`. Expected: import error.

- [ ] **Step 3: Implement `transport.py`**

```python
"""In-memory transport state for the Talaria platform adapter.

Ephemeral BY DESIGN (spec §1.2): parked drains, pending phone queries and
their futures live for the gateway process's lifetime only. A restart
drops parked queries and the tool answers "unreachable" — honest.
"""

from __future__ import annotations

import asyncio
import time
import uuid


class TransportHub:
    def __init__(self, time_fn=time.monotonic):
        self._time = time_fn
        self._last_seen: dict[str, float] = {}
        self._events: dict[str, asyncio.Event] = {}
        self._parked: set[str] = set()
        self._queries: dict[str, list[dict]] = {}
        self._futures: dict[str, asyncio.Future] = {}

    # -- liveness ---------------------------------------------------------
    def touch(self, device_id: str) -> None:
        self._last_seen[device_id] = self._time()

    def is_live(self, window_seconds: float = 60.0) -> bool:
        if self._parked:
            return True
        now = self._time()
        return any(now - seen <= window_seconds for seen in self._last_seen.values())

    def freshest_device(self) -> str | None:
        if not self._last_seen:
            return None
        return max(self._last_seen, key=self._last_seen.get)

    # -- long-poll parking --------------------------------------------------
    def _event(self, device_id: str) -> asyncio.Event:
        if device_id not in self._events:
            self._events[device_id] = asyncio.Event()
        return self._events[device_id]

    async def park(self, device_id: str, timeout: float = 25.0) -> None:
        event = self._event(device_id)
        event.clear()
        self._parked.add(device_id)
        try:
            await asyncio.wait_for(event.wait(), timeout=timeout)
        except asyncio.TimeoutError:
            pass
        finally:
            self._parked.discard(device_id)

    def wake(self, device_id: str | None = None) -> None:
        if device_id is not None:
            self._event(device_id).set()
            return
        for event in self._events.values():
            event.set()

    # -- phone queries --------------------------------------------------------
    def enqueue_query(self, device_id: str, kind: str, params: dict) -> tuple[str, asyncio.Future]:
        query_id = uuid.uuid4().hex[:12]
        future: asyncio.Future = asyncio.get_event_loop().create_future()
        self._queries.setdefault(device_id, []).append(
            {"id": query_id, "kind": kind, "params": params or {}}
        )
        self._futures[query_id] = future
        self.wake(device_id)
        return query_id, future

    def take_queries(self, device_id: str) -> list[dict]:
        return self._queries.pop(device_id, [])

    def resolve_query(self, query_id: str, result: dict | None = None, error: str | None = None) -> bool:
        future = self._futures.pop(query_id, None)
        if future is None or future.done():
            return False
        future.set_result({"error": error} if error else (result or {}))
        return True


HUB = TransportHub()
```

- [ ] **Step 4: Run to verify pass** — 7 passed.

- [ ] **Step 5: Commit**

```bash
cd ~/.hermes/plugins/talaria && git add transport.py tests/test_transport.py pytest.ini && git commit -m "feat(2A): transport hub — parked drains, liveness, query futures"
```

### Task 3: Store extensions for adapter pairing

**Files:**
- Modify: `~/.hermes/plugins/talaria/store.py` (append after `deactivate`)
- Test: `~/.hermes/plugins/talaria/tests/test_store_pairing.py`

**Interfaces:**
- Consumes: existing `_load/_save/_now_iso`.
- Produces: `create_paired_device(install_id: str, name: str) -> tuple[str, str]` (deactivates prior actives with same install_id — #144 re-pair rotation), `device_for_token(token: str) -> dict | None` (active row whose sha256 matches), `touch_device(device_id: str) -> None` (persists `last_seen`). Device rows gain optional `install_id`.

- [ ] **Step 1: Write the failing tests**

`tests/test_store_pairing.py`:

```python
import hashlib

from .. import store


def _redirect(monkeypatch, tmp_path):
    monkeypatch.setattr(store, "_store_path", lambda: tmp_path / "devices.json")


def test_create_paired_device_persists_hash_not_token(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    device_id, token = store.create_paired_device("install-1", "Owen's iPhone")
    rows = store.active_devices()
    assert len(rows) == 1
    assert rows[0]["id"] == device_id
    assert rows[0]["install_id"] == "install-1"
    assert rows[0]["name"] == "Owen's iPhone"
    assert rows[0]["token_sha256"] == hashlib.sha256(token.encode()).hexdigest()
    assert token not in (tmp_path / "devices.json").read_text()


def test_repair_same_install_rotates(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    old_id, old_token = store.create_paired_device("install-1", "phone")
    new_id, new_token = store.create_paired_device("install-1", "phone")
    actives = store.active_devices()
    assert [d["id"] for d in actives] == [new_id]
    assert store.device_for_token(old_token) is None
    assert store.device_for_token(new_token)["id"] == new_id
    # Old row kept, deactivated — never deleted.
    assert len(store.devices()) == 2


def test_device_for_token_rejects_garbage(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    store.create_paired_device("install-1", "phone")
    assert store.device_for_token("not-a-token") is None


def test_touch_device_stamps_last_seen(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    device_id, _ = store.create_paired_device("install-1", "phone")
    store.touch_device(device_id)
    assert store.active_devices()[0]["last_seen"] is not None
```

- [ ] **Step 2: Run to verify failure** — AttributeError on `create_paired_device`.

- [ ] **Step 3: Implement (append to `store.py`)**

```python
def create_paired_device(install_id: str, name: str) -> tuple[str, str]:
    """App-driven pairing (2A): mint a device bound to a durable install id.

    Re-pairing the same install deactivates the prior row first (#144 —
    rotate, never accumulate; rollback stays possible).
    """
    data = _load()
    for device in data.get("devices", []):
        if device.get("active") and device.get("install_id") == install_id:
            device["active"] = False
            device["deactivated"] = _now_iso()
    token = secrets.token_urlsafe(32)
    device_id = uuid.uuid4().hex[:12]
    data["devices"].append({
        "id": device_id,
        "token_sha256": hashlib.sha256(token.encode("utf-8")).hexdigest(),
        "created": _now_iso(),
        "active": True,
        "last_seen": None,
        "name": name or None,
        "install_id": install_id,
    })
    _save(data)
    return device_id, token


def device_for_token(token: str) -> dict | None:
    digest = hashlib.sha256((token or "").encode("utf-8")).hexdigest()
    for device in active_devices():
        if device.get("token_sha256") == digest:
            return device
    return None


def touch_device(device_id: str) -> None:
    data = _load()
    for device in data.get("devices", []):
        if device.get("id") == device_id and device.get("active"):
            device["last_seen"] = _now_iso()
            _save(data)
            return
```

- [ ] **Step 4: Run to verify pass** — 4 passed (and re-run the FULL plugin suite: prior tests still green).

- [ ] **Step 5: Commit**

```bash
cd ~/.hermes/plugins/talaria && git add store.py tests/test_store_pairing.py && git commit -m "feat(2A): store — app-driven pairing, token lookup, last_seen"
```

### Task 4: Envelope service (`envelope.py`) — verify + dispatch, all five types

**Files:**
- Create: `~/.hermes/plugins/talaria/envelope.py`
- Test: `~/.hermes/plugins/talaria/tests/test_envelope.py`

**Interfaces:**
- Consumes: Task 1 `outbox`, Task 2 `TransportHub`, Task 3 store functions.
- Produces: `class EnvelopeService(api_key_provider, hub, store_mod, outbox_mod, hold_seconds=25.0, touch_throttle_seconds=60.0)` with `verify(auth_header: str) -> tuple[bool, str]` and `async dispatch(payload: dict) -> dict`. Error responses: `{"error": <msg>, "code": <slug>}`, never an exception. Payloads carry `auth` (spec Addendum): header authenticates at the route, the payload field authorizes per-type.

- [ ] **Step 1: Write the failing tests**

`tests/test_envelope.py`:

```python
import asyncio

import pytest

from .. import outbox, store
from ..envelope import EnvelopeService
from ..transport import TransportHub

API_KEY = "test-api-key-64chars-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"


@pytest.fixture
def env(monkeypatch, tmp_path):
    monkeypatch.setattr(store, "_store_path", lambda: tmp_path / "devices.json")
    monkeypatch.setattr(outbox, "_outbox_path", lambda: tmp_path / "outbox.json")
    hub = TransportHub()
    service = EnvelopeService(
        api_key_provider=lambda: API_KEY,
        hub=hub,
        store_mod=store,
        outbox_mod=outbox,
        hold_seconds=0.05,
        touch_throttle_seconds=0.0,
    )
    return service, hub


def test_verify_accepts_api_key_and_device_token(env):
    service, _ = env
    assert service.verify(f"Bearer {API_KEY}") == (True, "")
    _, token = store.create_paired_device("i-1", "phone")
    assert service.verify(f"Bearer {token}") == (True, "")
    assert service.verify("Bearer wrong")[0] is False
    assert service.verify("")[0] is False


async def test_pair_requires_api_key_and_mints(env):
    service, _ = env
    refused = await service.dispatch({"type": "pair", "auth": "junk", "install_id": "i-1", "device_name": "p"})
    assert refused["code"] == "pair_requires_api_key"
    ok = await service.dispatch({"type": "pair", "auth": API_KEY, "install_id": "i-1", "device_name": "p"})
    assert ok["device_id"] and ok["device_token"]


async def test_drain_returns_backlog_immediately(env):
    service, _ = env
    paired = await service.dispatch({"type": "pair", "auth": API_KEY, "install_id": "i-1", "device_name": "p"})
    outbox.append("waiting for you")
    result = await service.dispatch({
        "type": "drain", "auth": paired["device_token"],
        "device_id": paired["device_id"], "wait": True,
    })
    assert [i["text"] for i in result["items"]] == ["waiting for you"]
    assert result["queries"] == []


async def test_drain_wrong_token_rejected(env):
    service, _ = env
    paired = await service.dispatch({"type": "pair", "auth": API_KEY, "install_id": "i-1", "device_name": "p"})
    other = await service.dispatch({"type": "pair", "auth": API_KEY, "install_id": "i-2", "device_name": "q"})
    crossed = await service.dispatch({
        "type": "drain", "auth": other["device_token"],
        "device_id": paired["device_id"], "wait": False,
    })
    assert crossed["code"] == "device_auth_mismatch"


async def test_drain_longpoll_wakes_on_send(env):
    service, hub = env
    paired = await service.dispatch({"type": "pair", "auth": API_KEY, "install_id": "i-1", "device_name": "p"})
    service_hold = EnvelopeService(
        api_key_provider=lambda: API_KEY, hub=hub, store_mod=store,
        outbox_mod=outbox, hold_seconds=5.0, touch_throttle_seconds=0.0,
    )
    drain = asyncio.create_task(service_hold.dispatch({
        "type": "drain", "auth": paired["device_token"],
        "device_id": paired["device_id"], "wait": True,
    }))
    await asyncio.sleep(0.02)
    outbox.append("fresh")
    hub.wake(paired["device_id"])
    result = await asyncio.wait_for(drain, timeout=1.0)
    assert [i["text"] for i in result["items"]] == ["fresh"]


async def test_ack_marks_delivered(env):
    service, _ = env
    paired = await service.dispatch({"type": "pair", "auth": API_KEY, "install_id": "i-1", "device_name": "p"})
    item = outbox.append("one")
    result = await service.dispatch({
        "type": "ack", "auth": paired["device_token"],
        "device_id": paired["device_id"], "item_ids": [item["id"]],
    })
    assert result == {"acked": [item["id"]]}
    assert outbox.pending() == []


async def test_query_flows_through_drain_and_result(env):
    service, hub = env
    paired = await service.dispatch({"type": "pair", "auth": API_KEY, "install_id": "i-1", "device_name": "p"})
    qid, future = hub.enqueue_query(paired["device_id"], "location", {})
    drained = await service.dispatch({
        "type": "drain", "auth": paired["device_token"],
        "device_id": paired["device_id"], "wait": False,
    })
    assert drained["queries"] == [{"id": qid, "kind": "location", "params": {}}]
    resolved = await service.dispatch({
        "type": "query_result", "auth": paired["device_token"],
        "device_id": paired["device_id"], "query_id": qid,
        "result": {"text": "at home"},
    })
    assert resolved == {"ok": True}
    assert (await asyncio.wait_for(future, 0.5)) == {"text": "at home"}


async def test_unpair_deactivates(env):
    service, _ = env
    paired = await service.dispatch({"type": "pair", "auth": API_KEY, "install_id": "i-1", "device_name": "p"})
    result = await service.dispatch({
        "type": "unpair", "auth": paired["device_token"], "device_id": paired["device_id"],
    })
    assert result == {"ok": True}
    assert store.active_devices() == []


async def test_unknown_type_is_clean_error(env):
    service, _ = env
    result = await service.dispatch({"type": "surprise", "auth": API_KEY})
    assert result["code"] == "unknown_event_type"
```

- [ ] **Step 2: Run to verify failure** — import error on `envelope`.

- [ ] **Step 3: Implement `envelope.py`**

```python
"""Envelope core for the Talaria platform adapter (spec §1.1).

Pure logic, dependency-injected for tests; platform.py wraps it. The
route verifies the HEADER (authentication — bad creds 401 before
dispatch); dispatch authorizes from the payload's `auth` field (spec
Addendum): pair requires the API key, device ops require the device's
own token bound to the claimed device_id. Every failure is a clean
error dict — the route 500s on raised exceptions, so nothing raises.
"""

from __future__ import annotations

import hmac
import time


def _bearer(auth_header: str) -> str:
    if not (auth_header or "").startswith("Bearer "):
        return ""
    return auth_header[7:].strip()


class EnvelopeService:
    def __init__(self, api_key_provider, hub, store_mod, outbox_mod,
                 hold_seconds: float = 25.0, touch_throttle_seconds: float = 60.0):
        self._api_key = api_key_provider
        self._hub = hub
        self._store = store_mod
        self._outbox = outbox_mod
        self._hold = hold_seconds
        self._touch_throttle = touch_throttle_seconds
        self._last_store_touch: dict[str, float] = {}

    # -- route-level authentication ---------------------------------------
    def verify(self, auth_header: str) -> tuple[bool, str]:
        token = _bearer(auth_header)
        if not token:
            return False, "missing_bearer"
        key = self._api_key() or ""
        if key and hmac.compare_digest(token, key):
            return True, ""
        if self._store.device_for_token(token) is not None:
            return True, ""
        return False, "invalid_talaria_auth"

    # -- per-type authorization helpers ------------------------------------
    def _is_api_key(self, value: str) -> bool:
        key = self._api_key() or ""
        return bool(key) and hmac.compare_digest(value or "", key)

    def _device_authorized(self, payload: dict) -> dict | None:
        device = self._store.device_for_token(payload.get("auth") or "")
        if device is None or device.get("id") != payload.get("device_id"):
            return None
        return device

    # -- dispatch -----------------------------------------------------------
    async def dispatch(self, payload: dict) -> dict:
        handler = {
            "pair": self._pair,
            "drain": self._drain,
            "ack": self._ack,
            "query_result": self._query_result,
            "unpair": self._unpair,
        }.get(payload.get("type"))
        if handler is None:
            return {"error": "Unknown event type", "code": "unknown_event_type"}
        return await handler(payload)

    async def _pair(self, payload: dict) -> dict:
        if not self._is_api_key(payload.get("auth") or ""):
            return {"error": "Pairing requires the gateway API key", "code": "pair_requires_api_key"}
        install_id = (payload.get("install_id") or "").strip()
        if not install_id:
            return {"error": "install_id is required", "code": "missing_install_id"}
        device_id, token = self._store.create_paired_device(
            install_id, (payload.get("device_name") or "").strip()
        )
        return {"device_id": device_id, "device_token": token}

    def _touch(self, device_id: str) -> None:
        self._hub.touch(device_id)
        now = time.monotonic()
        last = self._last_store_touch.get(device_id, 0.0)
        if now - last >= self._touch_throttle:
            self._last_store_touch[device_id] = now
            self._store.touch_device(device_id)

    async def _drain(self, payload: dict) -> dict:
        device = self._device_authorized(payload)
        if device is None:
            return {"error": "Token does not authorize this device", "code": "device_auth_mismatch"}
        device_id = device["id"]
        self._touch(device_id)
        items = self._outbox.pending()
        queries = self._hub.take_queries(device_id)
        if not items and not queries and payload.get("wait"):
            await self._hub.park(device_id, timeout=self._hold)
            self._touch(device_id)
            items = self._outbox.pending()
            queries = self._hub.take_queries(device_id)
        return {"items": items, "queries": queries}

    async def _ack(self, payload: dict) -> dict:
        if self._device_authorized(payload) is None:
            return {"error": "Token does not authorize this device", "code": "device_auth_mismatch"}
        return {"acked": self._outbox.mark_delivered(payload.get("item_ids") or [])}

    async def _query_result(self, payload: dict) -> dict:
        if self._device_authorized(payload) is None:
            return {"error": "Token does not authorize this device", "code": "device_auth_mismatch"}
        resolved = self._hub.resolve_query(
            payload.get("query_id") or "",
            result=payload.get("result"),
            error=payload.get("error"),
        )
        return {"ok": bool(resolved)}

    async def _unpair(self, payload: dict) -> dict:
        device = self._device_authorized(payload)
        if device is None:
            return {"error": "Token does not authorize this device", "code": "device_auth_mismatch"}
        self._store.deactivate(device["id"])
        return {"ok": True}
```

- [ ] **Step 4: Run to verify pass** — full plugin suite green (`python -m pytest tests/ -v` from the plugin root).

- [ ] **Step 5: Commit**

```bash
cd ~/.hermes/plugins/talaria && git add envelope.py tests/test_envelope.py && git commit -m "feat(2A): envelope service — pair/drain/ack/query_result/unpair, payload-auth binding"
```

### Task 5: Adapter shell, structured phone_query, `talaria send`, registration

**Files:**
- Create: `~/.hermes/plugins/talaria/platform.py`
- Modify: `~/.hermes/plugins/talaria/tools.py` (full rewrite of schema + handler + check_fn)
- Modify: `~/.hermes/plugins/talaria/admin.py` (add `send` subcommand)
- Modify: `~/.hermes/plugins/talaria/__init__.py` (register platform)
- Test: `~/.hermes/plugins/talaria/tests/test_tools.py`

**Interfaces:**
- Consumes: `EnvelopeService` (Task 4), `HUB` (Task 2), `outbox.append` (Task 1).
- Produces: `TalariaPlatformAdapter` (constructed by `register_platform`'s factory); rewritten `talaria_phone_query` (params `kind` enum + `params` object, `is_async=True`); `hermes talaria send <text>`.

- [ ] **Step 1: Write the failing tests (tool layer — adapter shell is import-smoked, not unit-tested, because it needs hermes)**

`tests/test_tools.py`:

```python
import asyncio

import pytest

from .. import tools
from ..transport import TransportHub


@pytest.fixture
def hub(monkeypatch):
    hub = TransportHub(time_fn=lambda: 100.0)
    monkeypatch.setattr(tools, "_hub", lambda: hub)
    return hub


def test_check_fn_false_when_no_device(hub):
    assert tools._transport_available() is False


def test_check_fn_true_when_recent_drain(hub):
    hub.touch("dev1")
    assert tools._transport_available() is True


async def test_phone_query_unreachable_when_dead(hub):
    text = await tools.phone_query({"kind": "location"})
    assert "unreachable" in text.lower()
    assert "retry" in text.lower()


async def test_phone_query_round_trip(hub, monkeypatch):
    monkeypatch.setattr(tools, "_QUERY_TIMEOUT", 1.0)
    hub.touch("dev1")

    async def answer_soon():
        await asyncio.sleep(0.02)
        [q] = hub.take_queries("dev1")
        # Task-4 fix round bound queries to their owner device.
        hub.resolve_query(q["id"], result={"text": "Currently at: Home"}, device_id="dev1")

    answering = asyncio.create_task(answer_soon())
    text = await tools.phone_query({"kind": "location", "params": {}})
    await answering
    assert text == "Currently at: Home"


async def test_phone_query_timeout_is_honest(hub, monkeypatch):
    monkeypatch.setattr(tools, "_QUERY_TIMEOUT", 0.05)
    hub.touch("dev1")
    text = await tools.phone_query({"kind": "health", "params": {"metric": "steps"}})
    assert "did not answer" in text.lower()


async def test_phone_query_error_result_reported_plainly(hub, monkeypatch):
    monkeypatch.setattr(tools, "_QUERY_TIMEOUT", 1.0)
    hub.touch("dev1")

    async def deny_soon():
        await asyncio.sleep(0.02)
        [q] = hub.take_queries("dev1")
        # Task-4 fix round bound queries to their owner device.
        hub.resolve_query(q["id"], error="permission_denied", device_id="dev1")

    denying = asyncio.create_task(deny_soon())
    text = await tools.phone_query({"kind": "health"})
    await denying
    assert "permission" in text.lower()
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Rewrite `tools.py`**

```python
"""Tool surface for the Talaria plugin.

2A: the structured phone-query catalog goes LIVE over the platform
adapter's drain transport. check_fn flips on transport liveness so the
model never burns a turn on a dead transport (Phase 1 rule, kept).
"""

from __future__ import annotations

import asyncio

from . import store

_QUERY_TIMEOUT = 25.0
_LIVE_WINDOW_SECONDS = 60.0

_KINDS = ["location", "health", "motion", "weather", "calendar", "reminders", "deviceStatus"]

_SCHEMAS = {
    "talaria_phone_query": {
        "type": "function",
        "function": {
            "name": "talaria_phone_query",
            "description": (
                "Ask the paired Talaria iPhone for its own data at query time "
                "(nothing is ingested or stored server-side). Kinds: location, "
                "health (params.metric: steps|calories|heartRate|sleep|summary), "
                "motion, weather, calendar (params.window_days), reminders, "
                "deviceStatus. Fails honestly when no phone is reachable."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "kind": {"type": "string", "enum": _KINDS},
                    "params": {
                        "type": "object",
                        "description": "Kind-specific string parameters, e.g. {\"metric\": \"steps\"}.",
                    },
                },
                "required": ["kind"],
            },
        },
    },
}


def _hub():
    from .transport import HUB
    return HUB


def _transport_available() -> bool:
    return _hub().is_live(_LIVE_WINDOW_SECONDS)


async def phone_query(args: dict, **kwargs) -> str:
    kind = ((args or {}).get("kind") or "").strip()
    if kind not in _KINDS:
        return f"Unknown query kind \"{kind}\" — supported: {', '.join(_KINDS)}."
    hub = _hub()
    if not hub.is_live(_LIVE_WINDOW_SECONDS):
        if not store.active_devices():
            return (
                "Phone unreachable: no Talaria device is paired with this host. "
                "The user can pair by opening the Talaria app. Do not retry this turn."
            )
        return (
            "Phone unreachable: the paired phone is not connected right now "
            "(the app is probably closed). Do not retry this turn."
        )
    device_id = hub.freshest_device()
    _, future = hub.enqueue_query(device_id, kind, (args or {}).get("params") or {})
    try:
        answer = await asyncio.wait_for(future, timeout=_QUERY_TIMEOUT)
    except asyncio.TimeoutError:
        return "The phone did not answer in time — it may have just gone to background. Do not retry this turn."
    if isinstance(answer, dict) and answer.get("error"):
        if answer["error"] == "permission_denied":
            return "The phone declined: that data stream is disabled in Talaria's privacy settings."
        return f"The phone could not answer: {answer['error']}."
    if isinstance(answer, dict) and isinstance(answer.get("text"), str):
        return answer["text"]
    return "The phone sent an unreadable answer."


def register_tools(ctx) -> None:
    for name, schema in _SCHEMAS.items():
        ctx.register_tool(
            name=name,
            toolset="talaria",
            schema=schema,
            handler=phone_query,
            check_fn=_transport_available,
            is_async=True,
            description=schema["function"]["description"],
            emoji="\U0001fabd",
        )
```

- [ ] **Step 4: Create `platform.py`**

```python
"""Webhook-mode platform adapter (spec §1.1).

Thin shell: BasePlatformAdapter obligations + delegation to
EnvelopeService. No socket — inbound rides the api_server's existing
POST /api/platforms/talaria/events (verified route, api_server.py
~:1808). Platform("talaria") resolves via the enum's _missing_()
pseudo-member exactly as plugins/platforms/google_chat does.
"""

from __future__ import annotations

import os
from typing import Any, Dict, Tuple

from gateway.config import Platform
from gateway.platforms.base import BasePlatformAdapter

from . import outbox, store
from .envelope import EnvelopeService
from .transport import HUB


def _api_key() -> str:
    return os.environ.get("API_SERVER_KEY", "")


class TalariaPlatformAdapter(BasePlatformAdapter):
    def __init__(self, config):
        super().__init__(config, Platform("talaria"))
        self._envelope = EnvelopeService(
            api_key_provider=_api_key,
            hub=HUB,
            store_mod=store,
            outbox_mod=outbox,
        )

    # -- BasePlatformAdapter obligations ---------------------------------
    async def connect(self, *, is_reconnect: bool = False) -> bool:
        return True  # webhook mode: being registered IS being connected

    async def disconnect(self) -> None:
        return None

    async def send(self, chat_id: str, text: str, **kwargs) -> Any:
        item = outbox.append(text, meta={"chat_id": chat_id})
        HUB.wake()
        return item["id"]

    async def get_chat_info(self, chat_id: str) -> Dict[str, Any]:
        return {"name": "Talaria", "type": "device"}

    # -- HTTP events (the whole transport) --------------------------------
    def verify_http_event_request(self, auth_header: str) -> Tuple[bool, str]:
        return self._envelope.verify(auth_header)

    async def dispatch_http_event(self, envelope: Dict[str, Any]) -> Dict[str, Any]:
        return await self._envelope.dispatch(envelope)
```

- [ ] **Step 5: Add `send` to `admin.py` and register the platform in `__init__.py`**

In `admin.py`, add alongside the existing subcommands (match the file's existing registration style exactly — read it first; the handler body is):

```python
def _cmd_send(args) -> None:
    from . import outbox
    text = " ".join(getattr(args, "text", []) or []).strip()
    if not text:
        print("Usage: hermes talaria send <text>")
        return
    item = outbox.append(text, meta={"source": "cli"})
    print(f"Queued outbox item {item['id']} — delivered on the phone's next drain.")
```

In `__init__.py`, replace the register function with:

```python
from . import admin, tools


def register(ctx) -> None:
    tools.register_tools(ctx)
    admin.register_cli(ctx)
    from .platform import TalariaPlatformAdapter
    ctx.register_platform(
        name="talaria",
        label="Talaria",
        adapter_factory=lambda cfg: TalariaPlatformAdapter(cfg),
        check_fn=lambda: True,
    )
```

(The `platform` import stays inside `register` so the tools/CLI half never breaks if gateway modules are unavailable in a bare CLI context — if `register_platform` or the import fails, catch `Exception`, log via `print`, and continue: tools + CLI must survive.)

Wrap accordingly:

```python
    try:
        from .platform import TalariaPlatformAdapter
        ctx.register_platform(
            name="talaria",
            label="Talaria",
            adapter_factory=lambda cfg: TalariaPlatformAdapter(cfg),
            check_fn=lambda: True,
        )
    except Exception as exc:  # pragma: no cover — CLI-context guard
        print(f"[talaria] platform registration skipped: {exc}")
```

- [ ] **Step 6: Run the full plugin suite + import smoke**

```bash
cd ~/.hermes/plugins/talaria && ~/.hermes/hermes-agent/venv/bin/python -m pytest tests/ -v
~/.hermes/hermes-agent/venv/bin/python -c "import sys; sys.path.insert(0, '/Users/owenjones/.hermes/plugins'); from talaria.platform import TalariaPlatformAdapter; print('adapter imports OK')"
```

Expected: suite green; "adapter imports OK".

- [ ] **Step 7: Commit**

```bash
cd ~/.hermes/plugins/talaria && git add -A && git commit -m "feat(2A): platform adapter shell, structured phone_query live, talaria send"
```

### Task 6: Enable on the Mac gateway + live curl smoke + push

**Files:** none in-repo (config + live verification), then `git push` of the plugin repo.

- [ ] **Step 1: Enable the platform** — add to `~/.hermes/config.yaml` under the existing `platforms:` block (keep `bluebubbles` untouched):

```yaml
  talaria:
    enabled: true
```

- [ ] **Step 2: Restart the Mac gateway.** Try `pkill -f "hermes gateway run"` then relaunch the way the box does it (check `~/.hermes/scripts/` for the launcher; otherwise `nohup hermes gateway run >/tmp/gateway.log 2>&1 &`). If the kill is denied by the shell classifier, STOP and ask Owen to restart it. Wait ~20s, then `curl -s localhost:8642/health` (expect 200) and confirm the process start time is fresh: `ps -p $(lsof -nP -iTCP:8642 -sTCP:LISTEN -t) -o lstart=,etime=`.

- [ ] **Step 3: Live smoke (never print the key):**

```bash
KEY=$(grep '^API_SERVER_KEY=' ~/.hermes/../hermes/.env 2>/dev/null | cut -d= -f2)
# If that path is empty, locate the Mac's HERMES_HOME .env first (printenv HERMES_HOME; default ~/.hermes/.env or ~/Library/... — find it, do NOT cat it).
PAIR=$(curl -s -X POST localhost:8642/api/platforms/talaria/events -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d "{\"type\":\"pair\",\"auth\":\"$KEY\",\"install_id\":\"smoke-1\",\"device_name\":\"curl-smoke\"}")
echo "$PAIR" | python3 -c "import json,sys; d=json.load(sys.stdin); print('paired:', d['device_id'])"
TOKEN=$(echo "$PAIR" | python3 -c "import json,sys; print(json.load(sys.stdin)['device_token'])")
DEV=$(echo "$PAIR" | python3 -c "import json,sys; print(json.load(sys.stdin)['device_id'])")
hermes talaria send "smoke hello"
curl -s -X POST localhost:8642/api/platforms/talaria/events -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "{\"type\":\"drain\",\"auth\":\"$TOKEN\",\"device_id\":\"$DEV\",\"wait\":false}"
```

Expected: drain response contains "smoke hello". Then ack it and verify a second drain is empty. Finally `hermes talaria unpair` (or an unpair envelope) to clean the smoke device, and confirm `hermes plugins list` still shows talaria enabled.

- [ ] **Step 4: Push the plugin repo**

```bash
cd ~/.hermes/plugins/talaria && git push
```

---

## Part 2 — App (Talaria-27, branch `claude/t27-251-2a-spine`)

### Task 7: Platform DTOs + scoped key + `TalariaPlatformLink` pairing

**Files:**
- Create: `Talaria/Models/TalariaPlatform.swift`
- Modify: the file declaring `BackendProfileScopedKeys` (find it: `grep -rn "enum BackendProfileScopedKeys" Talaria/ --include='*.swift'`) — add one static.
- Create: `Talaria/Services/Live/TalariaPlatformLink.swift`
- Test: `TalariaTests/TalariaPlatformLinkTests.swift`
- Run `xcodegen generate` after creating files.

**Interfaces:**
- Consumes: `SecureStoreProtocol` (`store/retrieve/delete`, @MainActor), `BackendProfilesStore.activeProfile`, `AppContainer.gatewayAPIKey(for:)` pattern (the link takes the key via a closure to stay store-agnostic), `AppSessionStore.state.installationID`.
- Produces: `TalariaPlatformLink` with `func start()`, `func stop()`, `func ensurePaired() async -> Bool` (harness-visible), `func drainOnce(wait: Bool) async -> DrainOutcome`; DTOs `TalariaPairResponse`, `TalariaDrainResponse`, `TalariaPlatformItem`, `TalariaPlatformQuery`. Keychain key: `BackendProfileScopedKeys.talariaDeviceToken(_:)`.

- [ ] **Step 1: DTOs — `Talaria/Models/TalariaPlatform.swift`**

```swift
import Foundation

// #251-2A: envelope DTOs for the talaria platform transport. Server sends
// snake_case; params are string-valued by contract (spec §Addendum).
struct TalariaPairResponse: Decodable, Sendable {
    let deviceID: String
    let deviceToken: String

    enum CodingKeys: String, CodingKey {
        case deviceID = "device_id"
        case deviceToken = "device_token"
    }
}

struct TalariaPlatformItem: Decodable, Sendable, Equatable {
    let id: String
    let kind: String
    let text: String
    let createdAt: String
    let meta: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, kind, text, meta
        case createdAt = "created_at"
    }
}

struct TalariaPlatformQuery: Decodable, Sendable, Equatable {
    let id: String
    let kind: String
    let params: [String: String]?
}

struct TalariaDrainResponse: Decodable, Sendable {
    let items: [TalariaPlatformItem]
    let queries: [TalariaPlatformQuery]
}

struct TalariaEnvelopeError: Decodable, Sendable {
    let error: String
    let code: String
}
```

- [ ] **Step 2: Scoped key** — in the file declaring `BackendProfileScopedKeys`, add (matching the existing statics' style/prefix conventions exactly — read the neighbors first):

```swift
    /// #251-2A: the talaria-platform device token minted by auto-pair.
    static func talariaDeviceToken(_ scopeID: String) -> String {
        "talaria.platform.device-token.\(scopeID)"
    }
```

- [ ] **Step 3: Write the failing tests** — `TalariaTests/TalariaPlatformLinkTests.swift`. Use a `URLProtocol` stub (copy the registration pattern from an existing Live-service test — grep `URLProtocol` under TalariaTests) plus an in-memory secure store:

```swift
import Foundation
import Testing
@testable import Talaria

@MainActor
final class MemorySecureStore: SecureStoreProtocol {
    var values: [String: String] = [:]
    func store(key: String, value: String) async { values[key] = value }
    func retrieve(key: String) async -> String? { values[key] }
    func delete(key: String) async { values[key] = nil }
}

@MainActor
struct TalariaPlatformLinkTests {
    private func makeLink(
        secureStore: MemorySecureStore,
        handler: @escaping @Sendable (URLRequest) -> (Int, Data)
    ) -> TalariaPlatformLink {
        TalariaStubURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TalariaStubURLProtocol.self]
        return TalariaPlatformLink(
            gatewayBaseURL: { "http://stub.local:8642" },
            apiKey: { "test-key" },
            installID: { "install-abc" },
            deviceName: { "TestPhone" },
            credentialScopeID: { "scope-1" },
            secureStore: secureStore,
            responder: nil,
            onItemsReceived: { _ in },
            session: URLSession(configuration: config)
        )
    }

    @Test func pairStoresTokenInKeychainSlot() async {
        let secure = MemorySecureStore()
        let link = makeLink(secureStore: secure) { request in
            (200, Data(#"{"device_id":"dev12","device_token":"tok-1"}"#.utf8))
        }
        #expect(await link.ensurePaired() == true)
        #expect(secure.values[BackendProfileScopedKeys.talariaDeviceToken("scope-1")] == "tok-1")
    }

    @Test func pairSkippedWhenTokenAlreadyStored() async {
        let secure = MemorySecureStore()
        secure.values[BackendProfileScopedKeys.talariaDeviceToken("scope-1")] = "existing"
        var called = false
        let link = makeLink(secureStore: secure) { _ in called = true; return (200, Data()) }
        #expect(await link.ensurePaired() == true)
        #expect(called == false)
    }

    @Test func drainParsesItemsAndAcks() async {
        let secure = MemorySecureStore()
        secure.values[BackendProfileScopedKeys.talariaDeviceToken("scope-1")] = "tok-1"
        secure.values[BackendProfileScopedKeys.talariaDeviceToken("scope-1") + ".device-id"] = "dev12"
        var bodies: [String] = []
        var received: [TalariaPlatformItem] = []
        let link = TalariaStubbedLinkFactory.make(secure: secure, onItems: { received = $0 }) { request in
            let body = TalariaStubURLProtocol.bodyString(request)
            bodies.append(body)
            if body.contains("\"drain\"") {
                return (200, Data(#"{"items":[{"id":"i1","kind":"message","text":"hi","created_at":"2026-08-05T21:00:00+00:00","meta":{}}],"queries":[]}"#.utf8))
            }
            return (200, Data(#"{"acked":["i1"]}"#.utf8))
        }
        let outcome = await link.drainOnce(wait: false)
        #expect(outcome == .delivered)
        #expect(received.map(\.id) == ["i1"])
        #expect(bodies.contains { $0.contains("\"ack\"") && $0.contains("i1") })
    }

    @Test func unauthorizedDrainRepairsOnce() async {
        let secure = MemorySecureStore()
        secure.values[BackendProfileScopedKeys.talariaDeviceToken("scope-1")] = "stale"
        var pairCalls = 0
        let link = makeLink(secureStore: secure) { request in
            let body = TalariaStubURLProtocol.bodyString(request)
            if body.contains("\"pair\"") {
                pairCalls += 1
                return (200, Data(#"{"device_id":"dev13","device_token":"tok-2"}"#.utf8))
            }
            return (401, Data(#"{"error":"bad","code":"invalid_talaria_auth"}"#.utf8))
        }
        _ = await link.drainOnce(wait: false)
        #expect(pairCalls == 1)
        #expect(secure.values[BackendProfileScopedKeys.talariaDeviceToken("scope-1")] == "tok-2")
    }
}
```

Notes for the implementer: `TalariaStubURLProtocol` is a small URLProtocol you add in this test file (static `handler`, static `bodyString(_:)` reading `httpBodyStream`/`httpBody`); `TalariaStubbedLinkFactory.make` is a tiny local helper mirroring `makeLink` but exposing `onItemsReceived` — keep both in the test file. Adjust assertions to the exact `DrainOutcome` you implement, but the four BEHAVIORS above (pair-stores, pair-skips, drain-parses+acks, 401-repairs-once) are the bars.

- [ ] **Step 4: Run to verify failure** (build error: `TalariaPlatformLink` undefined). Use the CC sim by id per repo practice:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer xcodebuild -project Talaria.xcodeproj -scheme Talaria -destination "id=$CC_SIM_ID" test -only-testing:TalariaTests/TalariaPlatformLinkTests 2>&1 | tail -20
```

- [ ] **Step 5: Implement `TalariaPlatformLink` (pairing + single drain + ack + 401-repair; the LOOP arrives in Task 8)**

```swift
import Foundation
import os

/// #251-2A: the phone side of the talaria platform transport — auto-pair
/// with the profile's gateway API key, then drain the durable outbox and
/// answer phone queries. Foreground-only by design (spec §2.1); the
/// durable outbox upstream is what makes closed-app time safe.
@MainActor
final class TalariaPlatformLink {
    enum DrainOutcome: Equatable {
        case delivered      // got items and/or queries, all handled
        case idle           // clean empty response
        case unauthorized   // 401 after the one re-pair attempt
        case failed         // transport/decoding error
        case notConfigured  // no profile/API key
    }

    private static let logger = Logger(subsystem: TalariaLog.subsystem, category: "TalariaPlatformLink")

    private let gatewayBaseURL: () -> String?
    private let apiKey: () async -> String?
    private let installID: () -> String
    private let deviceName: () -> String
    private let credentialScopeID: () -> String?
    private let secureStore: any SecureStoreProtocol
    private let responder: PhoneQueryResponding?
    private let onItemsReceived: ([TalariaPlatformItem]) -> Void
    private let session: URLSession
    private var repairedThisCycle = false

    init(
        gatewayBaseURL: @escaping () -> String?,
        apiKey: @escaping () async -> String?,
        installID: @escaping () -> String,
        deviceName: @escaping () -> String,
        credentialScopeID: @escaping () -> String?,
        secureStore: any SecureStoreProtocol,
        responder: PhoneQueryResponding?,
        onItemsReceived: @escaping ([TalariaPlatformItem]) -> Void,
        session: URLSession = .shared
    ) {
        self.gatewayBaseURL = gatewayBaseURL
        self.apiKey = apiKey
        self.installID = installID
        self.deviceName = deviceName
        self.credentialScopeID = credentialScopeID
        self.secureStore = secureStore
        self.responder = responder
        self.onItemsReceived = onItemsReceived
        self.session = session
    }

    // MARK: pairing

    private var tokenKey: String? {
        credentialScopeID().map { BackendProfileScopedKeys.talariaDeviceToken($0) }
    }

    func ensurePaired() async -> Bool {  // harness-visible
        guard let tokenKey else { return false }
        if await secureStore.retrieve(key: tokenKey) != nil { return true }
        return await pair(tokenKey: tokenKey)
    }

    private func pair(tokenKey: String) async -> Bool {
        guard let key = await apiKey(), !key.isEmpty else { return false }
        let body: [String: Any] = [
            "type": "pair", "auth": key,
            "install_id": installID(), "device_name": deviceName(),
        ]
        guard let (status, data) = await post(body, bearer: key), status == 200,
              let paired = try? JSONDecoder().decode(TalariaPairResponse.self, from: data)
        else { return false }
        await secureStore.store(key: tokenKey, value: paired.deviceToken)
        await secureStore.store(key: tokenKey + ".device-id", value: paired.deviceID)
        return true
    }

    // MARK: drain

    func drainOnce(wait: Bool) async -> DrainOutcome {
        guard let tokenKey else { return .notConfigured }
        guard await ensurePaired(),
              let token = await secureStore.retrieve(key: tokenKey),
              let deviceID = await secureStore.retrieve(key: tokenKey + ".device-id")
        else { return .notConfigured }

        let body: [String: Any] = [
            "type": "drain", "auth": token, "device_id": deviceID, "wait": wait,
        ]
        guard let (status, data) = await post(body, bearer: token) else { return .failed }
        if status == 401 {
            guard !repairedThisCycle else { return .unauthorized }
            repairedThisCycle = true
            await secureStore.delete(key: tokenKey)
            await secureStore.delete(key: tokenKey + ".device-id")
            guard await ensurePaired() else { return .unauthorized }
            return await drainOnce(wait: wait)
        }
        repairedThisCycle = false
        guard status == 200,
              let drained = try? JSONDecoder().decode(TalariaDrainResponse.self, from: data)
        else { return .failed }

        var didWork = false
        if !drained.items.isEmpty {
            onItemsReceived(drained.items)
            await ack(itemIDs: drained.items.map(\.id), token: token, deviceID: deviceID)
            didWork = true
        }
        for query in drained.queries {
            await answer(query, token: token, deviceID: deviceID)
            didWork = true
        }
        return didWork ? .delivered : .idle
    }

    private func ack(itemIDs: [String], token: String, deviceID: String) async {
        let body: [String: Any] = [
            "type": "ack", "auth": token, "device_id": deviceID, "item_ids": itemIDs,
        ]
        _ = await post(body, bearer: token)
    }

    private func answer(_ query: TalariaPlatformQuery, token: String, deviceID: String) async {
        var body: [String: Any] = [
            "type": "query_result", "auth": token,
            "device_id": deviceID, "query_id": query.id,
        ]
        if let responder {
            switch await responder.answer(kind: query.kind, params: query.params ?? [:]) {
            case .success(let text): body["result"] = ["text": text]
            case .denied: body["error"] = "permission_denied"
            case .unavailable(let reason): body["error"] = reason
            }
        } else {
            body["error"] = "responder_unavailable"
        }
        _ = await post(body, bearer: token)
    }

    // MARK: transport

    private func post(_ body: [String: Any], bearer: String) async -> (Int, Data)? {
        guard let base = gatewayBaseURL(),
              let url = URL(string: base + "/api/platforms/talaria/events") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 40)
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return (http.statusCode, data)
    }
}

/// Task 9 implements the live conformer; the link depends on the seam.
protocol PhoneQueryResponding {
    func answer(kind: String, params: [String: String]) async -> PhoneQueryAnswer
}

enum PhoneQueryAnswer: Equatable {
    case success(text: String)
    case denied
    case unavailable(reason: String)
}
```

(`start()`/`stop()` are added in Task 8 with the loop — do NOT add empty stubs here; the tests in this task exercise pairing and single drains only. If the compiler needs them referenced elsewhere, they don't exist yet anywhere else.)

- [ ] **Step 6: `xcodegen generate`, run the new tests to green, then the whole `TalariaTests` suite — count must MOVE by exactly the new tests.**

- [ ] **Step 7: Commit**

```bash
git add Talaria/Models/TalariaPlatform.swift Talaria/Services/Live/TalariaPlatformLink.swift TalariaTests/TalariaPlatformLinkTests.swift <scoped-keys-file>
git commit -m "feat(#251-2A): platform DTOs + link pairing/drain/ack with 401 self-repair

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 8: Drain loop + backoff + lifecycle

**Files:**
- Modify: `Talaria/Services/Live/TalariaPlatformLink.swift`
- Test: extend `TalariaTests/TalariaPlatformLinkTests.swift`

**Interfaces:**
- Produces: `func start()`, `func stop()`, `private(set) var isRunning: Bool`; internal-for-tests `func nextDelay(afterFailureCount: Int) -> Double` (pure ladder: 1, 2, 4, 8, 16, 30, 30…).

- [ ] **Step 1: Failing tests for the pure ladder + loop wiring**

```swift
    @Test func backoffLadderIsBoundedAndDeterministic() {
        let link = makeLink(secureStore: MemorySecureStore()) { _ in (200, Data()) }
        #expect(link.nextDelay(afterFailureCount: 1) == 1)
        #expect(link.nextDelay(afterFailureCount: 2) == 2)
        #expect(link.nextDelay(afterFailureCount: 3) == 4)
        #expect(link.nextDelay(afterFailureCount: 6) == 30)
        #expect(link.nextDelay(afterFailureCount: 99) == 30)
    }

    @Test func stopCancelsTheLoop() async throws {
        let secure = MemorySecureStore()
        secure.values[BackendProfileScopedKeys.talariaDeviceToken("scope-1")] = "tok"
        secure.values[BackendProfileScopedKeys.talariaDeviceToken("scope-1") + ".device-id"] = "dev"
        let link = makeLink(secureStore: secure) { _ in
            (200, Data(#"{"items":[],"queries":[]}"#.utf8))
        }
        link.start()
        #expect(link.isRunning == true)
        link.stop()
        #expect(link.isRunning == false)
    }
```

- [ ] **Step 2: Verify RED, then implement**

```swift
    private var loopTask: Task<Void, Never>?
    private(set) var isRunning = false

    func nextDelay(afterFailureCount count: Int) -> Double {  // harness-visible
        min(30, pow(2, Double(max(0, count - 1))))
    }

    func start() {
        guard loopTask == nil else { return }
        isRunning = true
        loopTask = Task { [weak self] in
            var failures = 0
            while let self, self.isRunning, !Task.isCancelled {
                let outcome = await self.drainOnce(wait: failures == 0)
                switch outcome {
                case .delivered, .idle:
                    failures = 0
                case .notConfigured, .unauthorized:
                    failures = max(failures, 3)
                case .failed:
                    failures += 1
                }
                if failures > 0 {
                    let delay = self.nextDelay(afterFailureCount: failures)
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }

    func stop() {
        isRunning = false
        loopTask?.cancel()
        loopTask = nil
    }
```

(Healthy loop = `wait: true` long-polls back-to-back — the server's ≤25s hold provides the pacing; degraded loop = `wait: false` + ladder sleeps, per spec §2.1.)

- [ ] **Step 3: Green + full suite count check + commit** (`feat(#251-2A): drain loop — long-poll pacing, bounded backoff, clean stop`).

### Task 9: `PhoneQueryResponder` — catalog with privacy gates

**Files:**
- Create: `Talaria/Services/Live/PhoneQueryResponder.swift`
- Modify (static extractions, pure code motion, only where no static exists yet): `Talaria/Services/Live/DeviceTools/DeviceReadTools.swift` (LocationTool → `static func performLocationRead(relay:name:)`, MotionTool → `static func performMotionRead(rawWindow:relay:name:)`), `Talaria/Services/Live/DeviceTools/DeviceCalendarTools.swift` (CalendarReadTool → `static func performRead(rawWindowDays:relay:name:)`, ReminderReadTool → `static func performRead(rawList:relay:name:)`). Match the exact existing pattern of `WeatherTool.performLookup` / `DeviceHealthTool.performRead`: move the `call(arguments:)` body into the static, have `call` delegate. DO NOT change any behavior, string, or relay interaction while moving.
- Test: `TalariaTests/PhoneQueryResponderTests.swift`

**Interfaces:**
- Consumes: `PhoneQueryResponding` / `PhoneQueryAnswer` (Task 7), belt statics (existing: `DeviceHealthTool.performRead(rawMetric:relay:name:)`, `WeatherTool.performLookup(rawPlace:relay:...)`, `DeviceStatusTool.statusReport()`; extracted: the four above).
- Produces: `final class PhoneQueryResponder: PhoneQueryResponding` with injectable gates: `init(settings: @escaping () -> UserSettings, relayFactory: @escaping () -> ToolEventRelay = { ToolEventRelay() }, reader: PhoneQueryReader = LivePhoneQueryReader())` where `PhoneQueryReader` is a small protocol wrapping the belt statics so tests fake it:

```swift
protocol PhoneQueryReader {
    func location(relay: ToolEventRelay) async throws -> String
    func health(metric: String?, relay: ToolEventRelay) async throws -> String
    func motion(window: String?, relay: ToolEventRelay) async throws -> String
    func weather(relay: ToolEventRelay) async throws -> String
    func calendar(windowDays: String?, relay: ToolEventRelay) async throws -> String
    func reminders(list: String?, relay: ToolEventRelay) async throws -> String
    func deviceStatus() async -> String
}
```

- [ ] **Step 1: Failing tests** — gate behaviors with a fake reader (each returns a canned string, records calls):

```swift
import Testing
@testable import Talaria

final class FakeReader: PhoneQueryReader, @unchecked Sendable {
    var calls: [String] = []
    func location(relay: ToolEventRelay) async throws -> String { calls.append("location"); return "AT: Home" }
    func health(metric: String?, relay: ToolEventRelay) async throws -> String { calls.append("health:\(metric ?? "")"); return "STEPS: 1200" }
    func motion(window: String?, relay: ToolEventRelay) async throws -> String { calls.append("motion"); return "WALKING" }
    func weather(relay: ToolEventRelay) async throws -> String { calls.append("weather"); return "22C CLEAR" }
    func calendar(windowDays: String?, relay: ToolEventRelay) async throws -> String { calls.append("calendar"); return "1 EVENT" }
    func reminders(list: String?, relay: ToolEventRelay) async throws -> String { calls.append("reminders"); return "2 OPEN" }
    func deviceStatus() async -> String { calls.append("status"); return "BATTERY 80%" }
}

@MainActor
struct PhoneQueryResponderTests {
    private func makeResponder(_ settings: UserSettings, reader: FakeReader) -> PhoneQueryResponder {
        PhoneQueryResponder(settings: { settings }, reader: reader)
    }

    private var allOn: UserSettings {
        var s = UserSettings.defaults
        s.sensorStreamingEnabled = true
        s.healthCollectionEnabled = true
        s.locationCollectionEnabled = true
        s.motionCollectionEnabled = true
        return s
    }

    @Test func healthAnswersWhenToggledOn() async {
        let reader = FakeReader()
        let answer = await makeResponder(allOn, reader: reader).answer(kind: "health", params: ["metric": "steps"])
        #expect(answer == .success(text: "STEPS: 1200"))
        #expect(reader.calls == ["health:steps"])
    }

    @Test func masterOffDeniesSensorKindsButNotCalendar() async {
        var s = allOn; s.sensorStreamingEnabled = false
        let reader = FakeReader()
        let responder = makeResponder(s, reader: reader)
        #expect(await responder.answer(kind: "health", params: [:]) == .denied)
        #expect(await responder.answer(kind: "location", params: [:]) == .denied)
        #expect(await responder.answer(kind: "motion", params: [:]) == .denied)
        #expect(await responder.answer(kind: "weather", params: [:]) == .denied)
        #expect(await responder.answer(kind: "calendar", params: [:]) == .success(text: "1 EVENT"))
        #expect(await responder.answer(kind: "deviceStatus", params: [:]) == .success(text: "BATTERY 80%"))
    }

    @Test func perStreamToggleDeniesItsKindOnly() async {
        var s = allOn; s.healthCollectionEnabled = false
        let reader = FakeReader()
        let responder = makeResponder(s, reader: reader)
        #expect(await responder.answer(kind: "health", params: [:]) == .denied)
        #expect(await responder.answer(kind: "location", params: [:]) == .success(text: "AT: Home"))
    }

    @Test func weatherRidesLocationToggle() async {
        var s = allOn; s.locationCollectionEnabled = false
        let responder = makeResponder(s, reader: FakeReader())
        #expect(await responder.answer(kind: "weather", params: [:]) == .denied)
    }

    @Test func unknownKindIsUnavailableNotDenied() async {
        let answer = await makeResponder(allOn, reader: FakeReader()).answer(kind: "contacts", params: [:])
        #expect(answer == .unavailable(reason: "unknown_kind"))
    }

    @Test func readerThrowBecomesUnavailable() async {
        final class ThrowingReader: FakeReader {
            override func location(relay: ToolEventRelay) async throws -> String {
                struct Boom: Error {}
                throw Boom()
            }
        }
        let answer = await makeResponder(allOn, reader: ThrowingReader()).answer(kind: "location", params: [:])
        if case .unavailable = answer {} else { Issue.record("expected unavailable, got \(answer)") }
    }
}
```

(If `UserSettings.defaults` isn't the real factory, use whatever the existing tests use to make one — grep `UserSettings(` in TalariaTests; if `FakeReader` can't be subclassed because the plan's version is `final`, drop `final` on the fake only.)

- [ ] **Step 2: RED, then implement**

```swift
import Foundation

/// #251-2A: answers structured phone queries from the agent using the SAME
/// read machinery the on-device belt uses, behind the SAME privacy gates
/// (spec §2.2). Prose out — the agent is an LLM; the belt's strings are
/// already the honest surface.
final class LivePhoneQueryReader: PhoneQueryReader {
    func location(relay: ToolEventRelay) async throws -> String {
        try await LocationTool.performLocationRead(relay: relay, name: "currentLocation")
    }
    func health(metric: String?, relay: ToolEventRelay) async throws -> String {
        try await DeviceHealthTool.performRead(rawMetric: metric, relay: relay, name: "readHealth")
    }
    func motion(window: String?, relay: ToolEventRelay) async throws -> String {
        try await MotionTool.performMotionRead(rawWindow: window, relay: relay, name: "readMotion")
    }
    func weather(relay: ToolEventRelay) async throws -> String {
        try await WeatherTool.performLookup(rawPlace: nil, relay: relay, name: "currentWeather")
    }
    func calendar(windowDays: String?, relay: ToolEventRelay) async throws -> String {
        try await CalendarReadTool.performRead(rawWindowDays: windowDays, relay: relay, name: "readCalendar")
    }
    func reminders(list: String?, relay: ToolEventRelay) async throws -> String {
        try await ReminderReadTool.performRead(rawList: list, relay: relay, name: "readReminders")
    }
    func deviceStatus() async -> String {
        await MainActor.run { DeviceStatusTool.statusReport() }
    }
}

final class PhoneQueryResponder: PhoneQueryResponding {
    private let settings: () -> UserSettings
    private let relayFactory: () -> ToolEventRelay
    private let reader: PhoneQueryReader

    init(
        settings: @escaping () -> UserSettings,
        relayFactory: @escaping () -> ToolEventRelay = { ToolEventRelay() },
        reader: PhoneQueryReader = LivePhoneQueryReader()
    ) {
        self.settings = settings
        self.relayFactory = relayFactory
        self.reader = reader
    }

    func answer(kind: String, params: [String: String]) async -> PhoneQueryAnswer {
        let current = settings()
        let master = current.sensorStreamingEnabled
        switch kind {
        case "health":
            guard master, current.healthCollectionEnabled else { return .denied }
        case "location":
            guard master, current.locationCollectionEnabled else { return .denied }
        case "motion":
            guard master, current.motionCollectionEnabled else { return .denied }
        case "weather":
            guard master, current.locationCollectionEnabled else { return .denied }
        case "calendar", "reminders", "deviceStatus":
            break  // iOS permissions gate these, matching the belt (spec §2.2)
        default:
            return .unavailable(reason: "unknown_kind")
        }
        do {
            let relay = relayFactory()
            let text: String
            switch kind {
            case "location": text = try await reader.location(relay: relay)
            case "health": text = try await reader.health(metric: params["metric"], relay: relay)
            case "motion": text = try await reader.motion(window: params["window"], relay: relay)
            case "weather": text = try await reader.weather(relay: relay)
            case "calendar": text = try await reader.calendar(windowDays: params["window_days"], relay: relay)
            case "reminders": text = try await reader.reminders(list: params["list"], relay: relay)
            default: text = await reader.deviceStatus()
            }
            return .success(text: text)
        } catch {
            return .unavailable(reason: "read_failed")
        }
    }
}
```

Adjust the four extracted static signatures to whatever the real `call(arguments:)` bodies need (e.g. if MotionTool has no window argument, drop the param — the RULE is pure code motion, the exact signature follows the existing body; update `PhoneQueryReader` + `LivePhoneQueryReader` to match). Mark extractions `// harness-visible` if they widen access.

- [ ] **Step 3: GREEN, full suite count check, commit** (`feat(#251-2A): phone-query responder — catalog behind the belt's own privacy gates`).

### Task 10: Inbox replacement — platform feed in, relay feed out

**Files:**
- Modify: `Talaria/Models/InboxLocalState.swift` (add `platformItems: [InboxItem] = []`, decode-tolerant like `localItems`)
- Create: `Talaria/Services/Live/TalariaPlatformInboxService.swift`
- Delete: `Talaria/Services/Live/LiveInboxService.swift` (and its relay DTO file if separate — grep `RelayInboxItem`)
- Modify: `Talaria/Stores/AppContainer.swift` (~line 493: swap `LiveInboxService(...)` for `TalariaPlatformInboxService(persistence:)`; delete the LiveInboxService init args block)
- Test: `TalariaTests/TalariaPlatformInboxServiceTests.swift`; sweep `grep -rn "LiveInboxService\|RelayInboxItem" TalariaTests/` and delete/replace those tests.

**Interfaces:**
- Consumes: `InboxServiceProtocol` (`fetchInbox(accessToken:) -> [InboxItem]`, `submitAction(itemID:actionID:accessToken:) -> InboxActionResult`), `AppPersistenceStoreProtocol.loadInboxState()/saveInboxState(_:)`, `InboxItem`, `InboxItemType.notification`, `InboxItemStatus`.
- Produces: `TalariaPlatformInboxService` + free function `func talariaInboxItem(from platformItem: TalariaPlatformItem) -> InboxItem` + `static func merge(_ new: [TalariaPlatformItem], into state: inout InboxLocalState)` used by the link's `onItemsReceived`.

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import Talaria

struct TalariaPlatformInboxServiceTests {
    @Test func mapsPlatformItemToNotificationInboxItem() {
        let platformItem = TalariaPlatformItem(
            id: "abc123", kind: "message", text: "Morning briefing: all clear.",
            createdAt: "2026-08-05T21:00:00+00:00", meta: nil
        )
        let item = talariaInboxItem(from: platformItem)
        #expect(item.type == .notification)
        #expect(item.body == "Morning briefing: all clear.")
        #expect(item.isActionable == false)
        #expect(item.payload?["platformID"] == "abc123")
    }

    @Test func mergeDedupesOnPlatformID() {
        var state = InboxLocalState()
        let one = TalariaPlatformItem(id: "a", kind: "message", text: "one", createdAt: "2026-08-05T21:00:00+00:00", meta: nil)
        TalariaPlatformInboxService.merge([one], into: &state)
        TalariaPlatformInboxService.merge([one], into: &state)
        #expect(state.platformItems.count == 1)
    }

    @Test func fetchReturnsPersistedPlatformItemsNewestFirst() async throws {
        let persistence = InMemoryPersistenceStore()  // reuse the existing test double — grep TalariaTests for the type the InboxStore tests use
        var state = InboxLocalState()
        let old = TalariaPlatformItem(id: "a", kind: "message", text: "old", createdAt: "2026-08-04T21:00:00+00:00", meta: nil)
        let new = TalariaPlatformItem(id: "b", kind: "message", text: "new", createdAt: "2026-08-05T21:00:00+00:00", meta: nil)
        TalariaPlatformInboxService.merge([old, new], into: &state)
        persistence.saveInboxState(state)
        let service = TalariaPlatformInboxService(persistence: persistence)
        let items = try await service.fetchInbox(accessToken: nil)
        #expect(items.map { $0.payload?["platformID"] } == ["b", "a"])
    }

    @Test func decodeToleranceOldStateBlobStillLoads() throws {
        let legacyJSON = #"{"readItemIDs":[],"dismissedItemIDs":[],"localItems":[]}"#
        let state = try JSONDecoder().decode(InboxLocalState.self, from: Data(legacyJSON.utf8))
        #expect(state.platformItems.isEmpty)
    }
}
```

(Use the actual in-memory persistence double the existing InboxStore tests use — grep for it; if none exists, add a minimal one in this test file conforming to `AppPersistenceStoreProtocol`'s inbox members only, and route the rest to fatalError-free defaults if the protocol allows.)

- [ ] **Step 2: RED, then implement**

`InboxLocalState.swift` — add the field and decode-tolerance (mirror the existing `localItems` additive-decode comment/pattern):

```swift
    /// #251-2A: agent-initiated platform messages received via the talaria
    /// drain. Persisted app-side because the server marks them delivered on
    /// ack — this cache IS the user-facing history.
    var platformItems: [InboxItem] = []
```

(and add `platformItems` to CodingKeys + the additive `decodeIfPresent` in the existing custom init.)

`TalariaPlatformInboxService.swift`:

```swift
import Foundation

/// #251-2A: the Inbox's feed after the relay retirement (spec §2.3) —
/// reads the local cache the drain loop fills. Platform items are plain
/// notifications in slice A; submitAction never fires for them.
func talariaInboxItem(from platformItem: TalariaPlatformItem) -> InboxItem {
    let timestamp = ISO8601DateFormatter().date(from: platformItem.createdAt) ?? .now
    return InboxItem(
        type: .notification,
        title: "Hermes",
        body: platformItem.text,
        timestamp: timestamp,
        isActionable: false,
        payload: ["platformID": platformItem.id]
    )
}

@MainActor
final class TalariaPlatformInboxService: InboxServiceProtocol {
    private let persistence: any AppPersistenceStoreProtocol

    init(persistence: any AppPersistenceStoreProtocol) {
        self.persistence = persistence
    }

    static func merge(_ new: [TalariaPlatformItem], into state: inout InboxLocalState) {
        let known = Set(state.platformItems.compactMap { $0.payload?["platformID"] })
        for platformItem in new where !known.contains(platformItem.id) {
            state.platformItems.append(talariaInboxItem(from: platformItem))
        }
    }

    func fetchInbox(accessToken: String?) async throws -> [InboxItem] {
        persistence.loadInboxState().platformItems.sorted { $0.timestamp > $1.timestamp }
    }

    func submitAction(itemID: UUID, actionID: String, accessToken: String?) async throws -> InboxActionResult {
        InboxActionResult(itemID: itemID, actionID: actionID, status: .pending, completedAt: .now)
    }
}
```

Then: delete `LiveInboxService.swift` (+ `RelayInboxItem` file if separate), swap the AppContainer construction site (~:493) to `TalariaPlatformInboxService(persistence: <the same persistence instance the container already holds>)`, delete relay-inbox tests, `xcodegen generate`.

- [ ] **Step 3: GREEN + full suite (expect a NET count change: new tests added, relay-inbox tests deleted — record both numbers) + commit** (`feat(#251-2A): inbox rides the platform outbox; relay inbox service deleted`).

### Task 11: Container wiring, lifecycle, Server-screen row

**Files:**
- Modify: `Talaria/Stores/AppContainer.swift` — construct `PhoneQueryResponder` + `TalariaPlatformLink` (closures: `gatewayBaseURL: { profilesStore.activeProfile?.gatewayBaseURL }`, `apiKey: { await self.gatewayAPIKey(for: activeProfile) }`, `installID: { sessionStore.state.installationID }`, `deviceName: { UIDevice.current.name }`, `credentialScopeID: { profilesStore.activeProfile?.credentialScopeID }`, `onItemsReceived:` = merge+persist via `TalariaPlatformInboxService.merge` and nudge `InboxStore.loadInbox(force: true)`); `start()` the link everywhere `sensorUploadService?.start()` runs on scene-activation (grep the call sites — mirror placement), `stop()` where the app backgrounds.
- Modify: `Talaria/Features/Settings/ServerSettingsScreen.swift` — one status row `PLUGIN LINK` with value from the link's pairing state: `PAIRED` when the token slot is non-nil, `NOT PAIRED` otherwise, `—` with no active profile (real data only; a11y id `settings.server.talariaLink`).
- Test: extend `TalariaUITests/AppTemplateUITests.swift` minimally — in the existing Server-screen UI test (find via a11y grep), assert the `settings.server.talariaLink` element exists.

**Steps:** (1) wire container + lifecycle; (2) add the row; (3) `xcodegen generate`; (4) run the FULL unit suite + the touched UI test on the CC sim; (5) commit (`feat(#251-2A): link lifecycle wiring + server-screen pairing row`).

Placement notes: the link is optional exactly like `sensorUploadService` (nil when no profile support); guard `start()` behind an active profile existing. Do not start it in UI-test app launches if sensor upload is similarly gated (mirror whatever launch-argument gate sensor upload uses — grep for it).

### Task 12: Bars, gate, e2e smoke, PR

- [ ] **Step 1: Pre-register bars in the OPEN_ITEMS #251 entry BEFORE the gate run** (a missed bar is a falsification):
  - **2A-A (pair):** fresh app install against the Mac gateway auto-pairs on first foreground — `hermes talaria status` shows the device, token in keychain, zero user steps beyond the existing profile.
  - **2A-B (live query):** with the app open, a real agent turn calling `talaria_phone_query(kind:"location")` answers in ≤5s wall-clock with real device data.
  - **2A-C (durability, exactly-once):** `hermes talaria send` while the app is CLOSED → gateway restart → app open → the item appears in the Inbox exactly once (dedupe on platformID).
  - **2A-D (honest unreachable):** app closed >60s → `check_fn` gates the tool; a forced call returns unreachable prose, no throw, no #232 counter movement.
  - **2A-E (deletion):** `LiveInboxService`/`RelayInboxItem` gone from the tree; suite green without them.
  - **2A-F (privacy):** health toggle OFF on device → `phone.query(kind:"health")` comes back "declined: privacy settings", and flipping it back ON answers.
  - **2A-G (gate):** full `scripts/mac/lane-gate.sh` PASS — units + XCUITest + Release, unit count moved by the net new tests.
- [ ] **Step 2: Run the gate BACKGROUNDED** (`nohup scripts/mac/lane-gate.sh > /tmp/2a-gate.log 2>&1 &`), poll the log; kill + re-gate if any ride-along lands mid-run.
- [ ] **Step 3: E2E smoke with Owen** (phone on OTA or corded): walk 2A-A/B/C/F live; record verdicts in the entry.
- [ ] **Step 4: PR** `claude/t27-251-2a-spine` → main with the gate evidence; merge on green per repo practice; OTA stage after merge (`scripts/mac/ota-stage.sh main`).

---

## Plan self-review (done at write time)

- **Spec coverage:** §1.1 envelope table → Tasks 4/5; §1.2 tool → Task 5; §1.3 outbox → Task 1; §1.4 registration/config → Tasks 5/6; §2.1 link → Tasks 7/8; §2.2 responder+gates → Task 9; §2.3 inbox → Task 10; §2.4 UI row → Task 11; §3 flows + §5 testing/bars → Task 12. Rollout note (§7) rides Task 12's smoke.
- **Known intentional deviations from the spec, recorded in its Addendum:** payload `auth` field (the route cannot pass the header to dispatch); query results as `{"text": prose}` (the belt's strings are already the honest surface; a structured schema would duplicate them for no consumer).
- **Type consistency:** `PhoneQueryResponding`/`PhoneQueryAnswer` defined in Task 7, consumed in Tasks 9/11; `TalariaPlatformItem` defined Task 7, consumed Task 10; store functions defined Task 3, consumed Task 4; `HUB` singleton defined Task 2, consumed Tasks 5. Extraction-signature flexibility in Task 9 is explicitly bounded (pure code motion; reader protocol adjusts to match).
