# Zero-Setup Migration — Execution Plan (OPEN_ITEMS #223)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking. **Owen routes each lane; do not start a lane
> he has not routed.** Written 2026-08-02 by the #223 investigation session; every source
> claim below was verified live that day (see the #223 entry's investigation block).

**Goal:** Collapse Talaria's host-side footprint so "upgrade and connect to Hermes" means
*setting up Hermes and pasting one key* — nothing else — because the current
relay/shim/connector slew sets a power-user bar Owen does not want as the App Store
conversation approaches.

**Architecture:** Push moves off the relay onto a **resident in-process watcher** — a
`gateway:startup` hook (two files + a vendored-deps dir in `~/.hermes/hooks/`, survives
`hermes update`, no subprocess ever spawned, no window flicker) that polls the session
store at relay parity (3–5 s) and sends APNs pings directly. The app stops posting relay
watches behind a pilot flag, then the relay's push role retires. Sensors and pairing
collapse ride later, separately-planned lanes gated on decisions recorded here.

**Tech Stack:** Python 3.11 (the hermes venv: `httpx` + vendored pure-Python
`h2`/`hpack`/`hyperframe` for HTTP/2, `pyjwt` + `cryptography` for ES256 — all verified
present/vendorable 2026-08-02); Swift/SwiftUI app-side; pytest for host-side units.

## Global Constraints (from CLAUDE.md — every task inherits these)

- **Never patch Hermes core** (`~/.hermes/hermes-agent`): `hermes update` wipes core
  edits. Everything host-side lands in HERMES_HOME artifacts (hooks/, scripts/, config)
  or in THIS repo.
- **The hook runs inside the gateway's event loop**: strictly async only — `httpx`
  AsyncClient + `asyncio.sleep`; file IO via `asyncio.to_thread`. Never block.
- **Bars in writing before any measured run**, in the OPEN_ITEMS #223 entry (not here —
  this plan carries bar TEMPLATES to copy in at run time). A missed bar is a
  falsification, not a redefinition.
- **`xcodegen generate` after adding/removing Swift files**; `DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`
  in every shell; **`scripts/mac/lane-gate.sh` before any PR** (Debug suite + Release build).
- OPEN_ITEMS numbers ≠ GitHub numbers — always say which.
- **Real data only** in UI; degradation is visible and stamped (#180), never silent.
- Payload compatibility is a hard rule: the hook's push payload matches the relay's
  (#38) — `session_id` at the payload root — so the app's existing tap-routing
  (`AppContainer.handleNotificationTap(sessionID:)`) works unchanged.
- OJAMD facts: HERMES_HOME = `C:\Users\Owen\AppData\Local\hermes`; `.env` with
  `API_SERVER_KEY` + the relay's `APNS_*` credentials; Owen pastes PowerShell
  (`curl.exe`/`Invoke-RestMethod`, never bare `curl`).

## Lane map

| Lane | What | Blocker / gate | Status |
|---|---|---|---|
| 0 | Preconditions (Mac gateway restart; token in hand) | none | before Lane 1 smoke |
| 1 | Host: `talaria-push` hook (watcher + APNs sender) | none | detailed below |
| 2 | App: pilot flag + manual token enrollment | Lane 1 deployed on one host | detailed below |
| 3 | Measured pilot (bars → #223 first) | Lanes 1+2 | bar templates below |
| 4 | Productionize (real OFF switch, bootstrap enrollment, relay push retirement) | Lane 3 bars green + Owen accepts | scoped below, own plan at routing |
| 5 | Shim retirement (#223 Phase 1) | none — independent | own plan at routing; note: `:8642` has **only** `/api/model/options` + `POST /api/sessions/{id}/model` (no `/api/model/set` — CLAUDE.md route table) |
| 6 | Upstream contribution (api_server hook emission + managed-files mount) | Owen's go; upstream acceptance | own plan; falls back cleanly (watcher stays poll-based; relay keeps sensors) |
| 7 | Sensors → deposit model | Lane 6 file API, or Owen accepts the daily bootstrap-turn bridge | own plan at routing |
| 8 | Pairing collapse (gateway-only onboarding) | Lanes 4+7 | own plan at routing |
| — | **App Store tier decision (record in #223 when taken):** third-party hosts must NOT hold the developer `.p8` → push for non-Owen users = a tiny vendor-run sender, or a BGTask-only free tier. Decide before submission, not before Lane 1. | — | parked |

---

## Lane 0: Preconditions

- [ ] **P1:** Mac gateway restarted onto 0.19.1 (it is import-torn since the 08-02
  update; chat 500s). Owen or a permitted session runs:
  `cd ~/.hermes && nohup ~/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run --replace > /tmp/gateway-restart.log 2>&1 &`
  Verify: `curl -s http://127.0.0.1:8642/health` reports `"version": "0.19.1"`.
- [ ] **P2:** Device push token in hand: Talaria → Diagnostics → Push Token row
  (tap-copies; #38 scaffolding). Sandbox environment (`aps-environment: development`).
- [ ] **P3 (explicitly OUT of this plan):** the OJAMD sensor-staleness outage
  (stale since 2026-07-26) is its own item — do not fold it in here.

---

## Lane 1: the `talaria-push` hook (host side, repo-first)

**Files:**
- Create: `host/hooks/talaria-push/HOOK.yaml`
- Create: `host/hooks/talaria-push/handler.py`
- Create: `host/hooks/talaria-push/watcher_core.py` (pure logic — all unit tests land here)
- Create: `host/hooks/talaria-push/config.example.json`
- Create: `host/hooks/talaria-push/tests/test_watcher_core.py`
- Create: `host/hooks/talaria-push/vendor/` (vendored `h2`, `hpack`, `hyperframe` — pure Python)
- Create: `scripts/mac/deploy-talaria-push-hook.sh`

**Interfaces:**
- Consumes: Hermes hook contract (verified 2026-08-02): `HOOK.yaml` needs `name` +
  non-empty `events`; `handler.py` needs top-level `handle(event_type, context)` (sync
  or async); loader imports handler.py as module `hermes_hook_talaria-push`; sibling
  imports need `sys.path` insertion. `gateway:startup` fires once per gateway boot,
  unconditionally.
- Produces: `watcher_core.extract_completion(messages) -> tuple[int, str] | None`;
  `watcher_core.WatcherState.completions_to_ping(session_id, messages) -> list[int]`;
  `watcher_core.build_apns_request(token, session_id, *, topic, environment, title, body)
  -> tuple[str, dict, dict]` (url, headers, json payload). Lane 3's measurement reads the
  hook's log lines (format pinned in Task 1.5).

### Task 1.1: `watcher_core.extract_completion` — the relay predicate, ported verbatim

- [ ] **Step 1: Write the failing tests**

```python
# host/hooks/talaria-push/tests/test_watcher_core.py
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from watcher_core import extract_completion


def _u(mid, text="hi"):
    return {"id": mid, "role": "user", "content": text}


def _a(mid, text="reply"):
    return {"id": mid, "role": "assistant", "content": text}


def test_completion_is_assistant_after_last_user():
    assert extract_completion([_u(1), _a(2)]) == (2, "reply")


def test_no_user_message_means_none():
    assert extract_completion([_a(1)]) is None


def test_pending_run_means_none():
    # user spoke last — run not finished
    assert extract_completion([_u(1), _a(2), _u(3)]) is None


def test_empty_assistant_does_not_complete():
    # tool-call shells have empty content (seen live 2026-08-02)
    assert extract_completion([_u(1), _a(2, ""), _a(3, "real")]) == (3, "real")


def test_structured_content_parts_extracted():
    msgs = [_u(1), {"id": 2, "role": "assistant",
                    "content": [{"type": "text", "text": "part"}]}]
    assert extract_completion(msgs) == (2, "part")
```

- [ ] **Step 2: Run to verify failure**

Run: `~/.hermes/hermes-agent/venv/bin/python -m pytest host/hooks/talaria-push/tests -v`
Expected: FAIL — `ModuleNotFoundError: watcher_core` (if pytest itself is missing from
the venv, run `python3 -m pytest` with any Python ≥3.11; the module under test is
dependency-free on purpose).

- [ ] **Step 3: Implement**

```python
# host/hooks/talaria-push/watcher_core.py
"""Pure logic for the talaria-push hook. No IO, no deps — fully unit-tested.

The completion predicate is the relay's `extract_completed_reply`
(relay/app/gateway.py:44) ported verbatim, extended to return the concluding
assistant message's id so the watcher can watermark it.
"""
from __future__ import annotations

from typing import Any


def _message_text(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):  # structured parts
        chunks = []
        for part in content:
            if isinstance(part, dict) and isinstance(part.get("text"), str):
                chunks.append(part["text"])
        return "".join(chunks)
    return ""


def extract_completion(messages: list[dict[str, Any]]) -> tuple[int, str] | None:
    """(assistant_message_id, text) concluding the last user turn, else None."""
    last_user_index = None
    for index, message in enumerate(messages):
        if str(message.get("role", "")).lower() == "user":
            last_user_index = index
    if last_user_index is None:
        return None
    for message in messages[last_user_index + 1:]:
        if str(message.get("role", "")).lower() != "assistant":
            continue
        text = _message_text(message.get("content")).strip()
        if text:
            try:
                return int(message.get("id")), text
            except (TypeError, ValueError):
                return None
    return None
```

- [ ] **Step 4: Run tests → PASS**
- [ ] **Step 5: Commit** — `feat(#223): talaria-push watcher predicate (relay parity)`

### Task 1.2: `WatcherState` — watermarks, silent priming, ping-once

- [ ] **Step 1: Write the failing tests** (append to the same test file)

```python
from watcher_core import WatcherState


def test_first_sight_primes_silently():
    st = WatcherState()
    # A session first seen ALREADY completed must not ping (gateway restart case).
    assert st.completions_to_ping("s1", [_u(1), _a(2)]) == []


def test_new_completion_after_priming_pings_once():
    st = WatcherState()
    st.completions_to_ping("s1", [_u(1), _a(2)])          # prime
    st.completions_to_ping("s1", [_u(1), _a(2), _u(3)])   # run pending
    assert st.completions_to_ping("s1", [_u(1), _a(2), _u(3), _a(4)]) == [4]
    # same transcript again: no re-ping
    assert st.completions_to_ping("s1", [_u(1), _a(2), _u(3), _a(4)]) == []


def test_sessions_are_independent():
    st = WatcherState()
    st.completions_to_ping("s1", [_u(1), _a(2)])
    assert st.completions_to_ping("s2", [_u(1), _a(2)]) == []  # s2 primes separately
```

- [ ] **Step 2: Run → FAIL** (`ImportError: WatcherState`)
- [ ] **Step 3: Implement** (append to `watcher_core.py`)

```python
class WatcherState:
    """Per-session watermarks. Priming is silent: the first observation of a
    session records its current completion (if any) WITHOUT pinging, so a
    gateway restart can never replay old completions as fresh pushes."""

    def __init__(self) -> None:
        self._watermark: dict[str, int] = {}

    def completions_to_ping(self, session_id: str,
                            messages: list[dict]) -> list[int]:
        completion = extract_completion(messages)
        seen = session_id in self._watermark
        current = self._watermark.get(session_id, 0)
        if completion is None:
            if not seen:
                self._watermark[session_id] = 0
            return []
        msg_id, _text = completion
        if not seen:
            self._watermark[session_id] = msg_id
            return []
        if msg_id > current:
            self._watermark[session_id] = msg_id
            return [msg_id]
        return []
```

- [ ] **Step 4: Run → PASS**  ·  **Step 5: Commit** — `feat(#223): watcher watermarks — silent priming, ping-once`

### Task 1.3: APNs request builder (pure) + vendored HTTP/2 deps

- [ ] **Step 1: Failing tests**

```python
from watcher_core import build_apns_request


def test_apns_request_shape():
    url, headers, payload = build_apns_request(
        "abc123", "api_555", topic="org.aethyrion.talaria27",
        environment="sandbox", title="Hermes", body="Reply ready")
    assert url == "https://api.sandbox.push.apple.com/3/device/abc123"
    assert headers["apns-topic"] == "org.aethyrion.talaria27"
    assert headers["apns-push-type"] == "alert"
    assert payload["session_id"] == "api_555"          # #38 payload contract
    assert payload["aps"]["alert"]["body"] == "Reply ready"


def test_production_host():
    url, _, _ = build_apns_request("t", "s", topic="x", environment="production",
                                   title="a", body="b")
    assert url.startswith("https://api.push.apple.com/")
```

- [ ] **Step 2: Run → FAIL**  ·  **Step 3: Implement**

```python
_APNS_HOSTS = {"sandbox": "https://api.sandbox.push.apple.com",
               "production": "https://api.push.apple.com"}


def build_apns_request(token: str, session_id: str, *, topic: str,
                       environment: str, title: str, body: str):
    host = _APNS_HOSTS[environment]
    url = f"{host}/3/device/{token}"
    headers = {"apns-topic": topic, "apns-push-type": "alert",
               "apns-priority": "10"}
    payload = {"aps": {"alert": {"title": title, "body": body},
                       "sound": "default"},
               "session_id": session_id}
    return url, headers, payload
```

- [ ] **Step 4: Run → PASS**
- [ ] **Step 5: Vendor the HTTP/2 extras** (pure Python; the hermes venv has `httpx` but
  not the `http2` extra — verified 2026-08-02):

```bash
python3 -m pip download h2 hpack hyperframe --no-deps -d /tmp/t223-wheels
mkdir -p host/hooks/talaria-push/vendor
for whl in /tmp/t223-wheels/*.whl; do unzip -o "$whl" -d host/hooks/talaria-push/vendor; done
~/.hermes/hermes-agent/venv/bin/python - <<'EOF'
import sys; sys.path.insert(0, "host/hooks/talaria-push/vendor")
import h2, httpx
print("http2 client OK:", httpx.AsyncClient(http2=True) is not None)
EOF
```

Expected: `http2 client OK: True`.
- [ ] **Step 6: Commit** — `feat(#223): APNs request builder + vendored h2 stack`

### Task 1.4: JWT provider with reuse window

APNs provider tokens must be reused 20–60 min (Apple rejects >1 h, throttles <20 min).

- [ ] **Step 1: Failing tests**

```python
from watcher_core import ApnsTokenPolicy


def test_token_reused_inside_window():
    calls = []
    pol = ApnsTokenPolicy(mint=lambda: calls.append(1) or f"tok{len(calls)}",
                          now=lambda: 1000.0)
    assert pol.token() == "tok1"
    pol._now = lambda: 1000.0 + 40 * 60          # 40 min later
    assert pol.token() == "tok1"                  # reused
    pol._now = lambda: 1000.0 + 51 * 60          # past 50-min refresh
    assert pol.token() == "tok2"
```

- [ ] **Step 2: Run → FAIL**  ·  **Step 3: Implement**

```python
class ApnsTokenPolicy:
    """Cache a minted provider JWT for 50 minutes (Apple: reuse 20-60 min)."""
    REFRESH_S = 50 * 60

    def __init__(self, mint, now):
        self._mint, self._now = mint, now
        self._token, self._minted_at = None, 0.0

    def token(self) -> str:
        if self._token is None or self._now() - self._minted_at >= self.REFRESH_S:
            self._token = self._mint()
            self._minted_at = self._now()
        return self._token
```

- [ ] **Step 4: Run → PASS**  ·  **Step 5: Commit** — `feat(#223): APNs provider-token reuse policy`

### Task 1.5: `handler.py` — assembly (supervisor + loop + IO)

No unit tests (IO shell over tested core); the live smoke in Task 1.6 is its test.
Log format is a Lane 3 interface — keep the exact strings.

- [ ] **Step 1: Write `HOOK.yaml`**

```yaml
name: talaria-push
description: "Resident watcher: APNs ping when an api_server session run completes (Talaria OPEN_ITEMS #223 push v1). OFF = remove device files from HERMES_HOME/talaria/push/devices/."
events:
  - gateway:startup
```

- [ ] **Step 2: Write `config.example.json`** (deploy copies to `config.json`, per host)

```json
{
  "gateway_base": "http://127.0.0.1:8642",
  "api_key_env_file": "~/.hermes/.env",
  "apns": {
    "key_file": "~/.hermes/talaria-push-apns.p8",
    "key_id": "REPLACE_KEY_ID",
    "team_id": "DNL25ZFSD2",
    "topic": "org.aethyrion.talaria27",
    "environment": "sandbox"
  },
  "poll_seconds": 4,
  "idle_seconds": 30,
  "sessions_limit": 15
}
```

- [ ] **Step 3: Write `handler.py`**

```python
"""talaria-push: resident in-process watcher (OPEN_ITEMS #223 push v1).

Installed as a gateway:startup hook. handle() parks ONE asyncio task on the
gateway's event loop and returns immediately (the same pattern gateway/run.py
uses for its loop heartbeat). Strictly async — never block the loop.
Errors here are caught by the supervisor; the hook must never take the
gateway down.
"""
from __future__ import annotations

import asyncio
import json
import logging
import sys
import time
from pathlib import Path

_HOOK_DIR = Path(__file__).resolve().parent
for _p in (str(_HOOK_DIR), str(_HOOK_DIR / "vendor")):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import watcher_core  # noqa: E402

log = logging.getLogger("talaria-push")
_started = False


def _load_config() -> dict:
    return json.loads((_HOOK_DIR / "config.json").read_text(encoding="utf-8"))


def _read_api_key(env_file: str) -> str:
    for line in Path(env_file).expanduser().read_text(encoding="utf-8").splitlines():
        if line.startswith("API_SERVER_KEY="):
            return line.split("=", 1)[1].strip()
    raise RuntimeError(f"API_SERVER_KEY not found in {env_file}")


def _device_files_dir() -> Path:
    from hermes_cli.config import get_hermes_home
    return Path(get_hermes_home()) / "talaria" / "push" / "devices"


def _mint_jwt(cfg: dict) -> str:
    import jwt  # pyjwt + cryptography: both in the hermes venv (verified 2026-08-02)
    key = Path(cfg["key_file"]).expanduser().read_text(encoding="utf-8")
    return jwt.encode({"iss": cfg["team_id"], "iat": int(time.time())},
                      key, algorithm="ES256", headers={"kid": cfg["key_id"]})


async def _watch_loop() -> None:
    import httpx
    cfg = _load_config()
    api_key = _read_api_key(cfg["api_key_env_file"])
    apns_cfg = cfg["apns"]
    token_policy = watcher_core.ApnsTokenPolicy(
        mint=lambda: _mint_jwt(apns_cfg), now=time.monotonic)
    state = watcher_core.WatcherState()
    headers = {"Authorization": f"Bearer {api_key}"}
    last_active: dict[str, object] = {}

    async with httpx.AsyncClient(timeout=10) as gw, \
               httpx.AsyncClient(http2=True, timeout=10) as apns:
        log.info("talaria-push: watcher up (poll=%ss)", cfg["poll_seconds"])
        while True:
            devices = await asyncio.to_thread(
                lambda: sorted(_device_files_dir().glob("*.json"))
                if _device_files_dir().is_dir() else [])
            if not devices:
                await asyncio.sleep(cfg["idle_seconds"])   # OFF = near-zero cost
                continue

            resp = await gw.get(f"{cfg['gateway_base']}/api/sessions",
                                params={"limit": cfg["sessions_limit"]},
                                headers=headers)
            resp.raise_for_status()
            for row in resp.json().get("data", []):
                sid = row.get("id")
                if not isinstance(sid, str):
                    continue
                marker = row.get("last_active") or row.get("updated_at") \
                    or row.get("message_count")
                if last_active.get(sid) == marker and sid in last_active:
                    continue
                last_active[sid] = marker
                m = await gw.get(
                    f"{cfg['gateway_base']}/api/sessions/{sid}/messages",
                    headers=headers)
                m.raise_for_status()
                messages = [x for x in m.json().get("data", [])
                            if isinstance(x, dict)]
                for msg_id in state.completions_to_ping(sid, messages):
                    for dev in devices:
                        d = json.loads(await asyncio.to_thread(
                            dev.read_text, "utf-8"))
                        url, hdrs, payload = watcher_core.build_apns_request(
                            d["token"], sid, topic=apns_cfg["topic"],
                            environment=apns_cfg["environment"],
                            title="Hermes", body="Reply ready")
                        hdrs["authorization"] = f"bearer {token_policy.token()}"
                        r = await apns.post(url, headers=hdrs, json=payload)
                        # PINNED LOG LINES — Lane 3 reads these:
                        log.info("talaria-push: ping session=%s msg=%s device=%s status=%s",
                                 sid, msg_id, dev.stem, r.status_code)
                        if r.status_code == 410:
                            log.info("talaria-push: token gone (410) — removing %s",
                                     dev.name)
                            await asyncio.to_thread(dev.unlink)
            await asyncio.sleep(cfg["poll_seconds"])


async def _supervisor() -> None:
    backoff = 5.0
    while True:
        try:
            await _watch_loop()
        except asyncio.CancelledError:
            raise
        except Exception:
            log.exception("talaria-push: watcher crashed — restarting in %.0fs",
                          backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 300.0)
        else:
            backoff = 5.0


async def handle(event_type: str, context: dict) -> None:
    global _started
    if event_type != "gateway:startup" or _started:
        return
    _started = True
    asyncio.get_running_loop().create_task(_supervisor())
    log.info("talaria-push: supervisor task started")
```

- [ ] **Step 4: Commit** — `feat(#223): talaria-push handler — supervisor + resident watcher`

### Task 1.6: Mac deploy + live smoke

- [ ] **Step 1: Write `scripts/mac/deploy-talaria-push-hook.sh`**

```bash
#!/bin/bash
# Deploy the talaria-push hook to the local HERMES_HOME. Idempotent.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../../host/hooks/talaria-push" && pwd)"
DST="$HOME/.hermes/hooks/talaria-push"
mkdir -p "$DST"
rsync -a --delete --exclude tests --exclude config.json "$SRC/" "$DST/"
[ -f "$DST/config.json" ] || cp "$SRC/config.example.json" "$DST/config.json"
echo "deployed to $DST — edit $DST/config.json (APNs key id/path), then restart the gateway"
```

- [ ] **Step 2: Deploy + configure** — run the script; fill `config.json` `apns` block
  (the `.p8` + Key ID Owen already uses for #38 relay push; copy the key file to the
  path in config, `chmod 600`).
- [ ] **Step 3: Restart the Mac gateway** (Lane 0 P1 command). Verify in
  `~/.hermes/logs/gateway.log`: `1 hook(s) loaded` and
  `talaria-push: supervisor task started`, then `watcher up`.
- [ ] **Step 4: Verify the payload-field assumption** (pinned verification — the
  watcher assumes `/api/sessions` rows and `/messages` rows carry `id`, `role`,
  `content`): with no device files present, `curl` both endpoints with the Bearer key
  and confirm those fields. Expected: present (message rows with integer `id` were
  observed live 2026-08-02). If `last_active` is absent from session rows the
  change-marker silently falls back to `message_count` — confirm at least one of the
  two exists; if neither does, STOP and re-plan the skip logic (do not ship a watcher
  that re-fetches every transcript every 4 s).
- [ ] **Step 5: Smoke: enroll + run** — write
  `~/.hermes/talaria/push/devices/whoGoesThere.json`:
  `{"token": "<from Diagnostics>", "enrolled_at": "<now>"}` — then start a chat run
  against the Mac gateway from the phone, background the app, watch for the
  `talaria-push: ping … status=200` log line and the banner on the device.
- [ ] **Step 6: Idle check** — remove the device file; confirm the log goes quiet
  (idle sleeps, no session polls) — this is the OFF-switch host half working.
- [ ] **Step 7: Commit deploy script** — `feat(#223): mac deploy script for talaria-push`

### Task 1.7: OJAMD deploy (Owen pastes; or one bootstrap turn)

- [ ] **Step 1:** Get the hook onto OJAMD — either Owen pastes (from a repo zip staged
  at the OTA server or a file share), or the proven bootstrap-turn pattern (the
  2026-08-02 probe wrote 1.9 KB byte-identically; the hook is bigger — if the turn
  path is used, verify EVERY file by SHA-256 read-back, and vendor/ almost certainly
  wants the zip route). Target: `C:\Users\Owen\AppData\Local\hermes\hooks\talaria-push\`.
- [ ] **Step 2:** `config.json` on OJAMD: `api_key_env_file` → `C:\Users\Owen\.hermes\.env`;
  `apns.key_file` → the relay's existing `.p8` path (values from the relay `.env`,
  #38); environment `sandbox` until #8 flips production.
- [ ] **Step 3:** Owen restarts the OJAMD gateway (his `pythonw` process — the
  `C:\Users\Owen\.hermes\scripts\` launcher; NOT a service). Verify the same two log
  lines; repeat the 1.6 smoke against OJAMD.

---

## Lane 2: app side — pilot flag + enrollment (small by design)

**Files:**
- Modify: `Talaria/Stores/ChatStore.swift` (the `postPushWatch`/`cancelPushWatch` call
  sites — grep `postPushWatch`; the #38 seams are `onRunDetached`/`onRunResolved` +
  the background-scenePhase post)
- Modify: `Talaria/Services/Support/UserSettings.swift` (or wherever `verboseLogging`
  lives — follow that exact pattern)
- Modify: the Developer settings screen (same screen as the `verboseLogging` toggle)
- Test: the suite file covering ChatStore watch behavior (grep `pushWatch` in
  `TalariaTests/`)

**Interfaces:**
- Consumes: Lane 1's payload contract — `session_id` at payload root — which the
  existing `UNUserNotificationCenterDelegate` → `handleNotificationTap(sessionID:)`
  path already handles. **No notification-handling changes in this lane.**
- Produces: `UserSettings.hookPushPilotEnabled: Bool` (default `false`).

### Task 2.1: the flag + the gate

- [ ] **Step 1: Failing test** — in the ChatStore watch test suite, following its
  existing seam pattern:

```swift
@Test func hookPushPilotSuppressesRelayWatch() async throws {
    let (store, relaySpy) = makeStoreWithRelaySpy()   // existing test factory pattern
    store.settings.hookPushPilotEnabled = true
    await store.onRunDetached(sessionID: "api_1")
    #expect(relaySpy.postedWatches.isEmpty)           // no relay watch posted
    store.settings.hookPushPilotEnabled = false
    await store.onRunDetached(sessionID: "api_2")
    #expect(relaySpy.postedWatches.count == 1)        // legacy path intact
}
```

(Adapt factory/spy names to the file's existing ones — do not invent a parallel seam.)
- [ ] **Step 2: Run → FAIL** (`hookPushPilotEnabled` undefined)
- [ ] **Step 3: Implement** — add `hookPushPilotEnabled` to `UserSettings` (persisted,
  default false, exact pattern of `verboseLogging`); guard EVERY `postPushWatch` call
  site (and matching `cancelPushWatch` bookkeeping) with
  `guard !settings.hookPushPilotEnabled else { return }`; add the toggle row to the
  Developer screen labeled **"Hook push pilot (skip relay watches)"**.
- [ ] **Step 4: Run the suite → PASS.** No new files → no `xcodegen` needed; if any
  file WAS added, run `xcodegen generate`.
- [ ] **Step 5:** `scripts/mac/lane-gate.sh` (backgrounded, poll the log; Debug suite +
  Release build must BOTH post success markers — confirm the test count MOVED).
- [ ] **Step 6: Commit** — `feat(#223): hookPushPilot flag — suppress relay watches on the pilot path`

### Task 2.2: enrollment is manual for the pilot (document, don't build)

- [ ] **Step 1:** No app code. Pilot enrollment = the Task 1.6 Step 5 file, written by
  hand (Mac) / one agent turn (OJAMD). Bootstrap-turn auto-enrollment + the real
  Settings OFF switch are **Lane 4** — do not build them into the pilot.
- [ ] **Step 2:** Record in the #223 entry: pilot enrolled device(s), date, host(s).

---

## Lane 3: the measured pilot — bar templates (copy into #223 BEFORE the run)

Run only after Lanes 1+2 are deployed on at least one host. **Copy these bars into the
OPEN_ITEMS #223 entry, dated, before the first measured run** — the entry, not this
file, is the pre-registration vehicle (standing convention since #215).

- **B1 delivery:** 10 detached runs (phone backgrounded mid-run) → **≥9 produce exactly
  one banner within 15 s of run completion**; 0 duplicates (the pilot flag suppresses
  the relay sender, so any duplicate is a bug, not overlap).
- **B2 latency:** watcher log `ping` timestamp − final assistant message timestamp:
  **p50 ≤ 6 s, p95 ≤ 12 s** across those runs (4 s poll + APNs transit).
- **B3 OFF (host half):** with zero device files, 10 min of watcher log shows **zero
  session polls** (idle lines only). **OFF (app half):** flag OFF → relay path
  behaves exactly as before the lane (existing suite green is the evidence).
- **B4 survival:** one gateway restart AND one `hermes-update-safe.ps1` run → the hook
  reloads (both log lines reappear) and vendor/ imports still resolve. This is the
  "HERMES_HOME artifacts survive update" claim, proven rather than assumed.
- **B5 gateway health:** no gateway-loop stalls attributable to the watcher (no new
  `loop_heartbeat` gaps in the gateway log during the run window).

Misses are falsifications: file them in #223 and stop — do not tune-and-rerun inside
the same entry note.

---

## Lane 4+ (scoped here, own plans at routing time)

- **Lane 4 — productionize:** the REQUIRED app-level notifications OFF switch (#223
  Owen-control: OFF = no enrollment + a removal turn + relay watches stay off), Settings
  placement + onboarding surfacing decisions, bootstrap-turn enrollment with SHA-256
  read-back, relay push-role retirement (config off, code stays until Lane 8 deletes),
  production APNs (#8 ties in). Gate: Lane 3 bars green + Owen accepts the trades.
- **Lane 5 — shim retirement:** picker onto `GET /api/model/options` + session pin
  `POST /api/sessions/{id}/model` (the ONLY model routes on `:8642` — per the
  CLAUDE.md route table; there is no `/api/model/set` on the chat plane). Kills #9's
  dual-write. Independent of the push lanes; can run any time Owen routes it.
- **Lane 6 — upstream contribution:** api_server `agent:end` emission (makes the
  watcher event-driven) + a managed-files mount under `API_SERVER_KEY` (the sensors
  deposit channel). Both fall back cleanly if upstream declines.
- **Lane 7 — sensors deposit model:** app-side daily aggregate builder + the
  `talaria-sensors` skill shape (probe-proven 2026-08-02), deposit channel per Lane 6
  or the ~1-turn/day bootstrap bridge (Owen's call), relay/connector sensor retirement,
  #113/#188 dissolve.
- **Lane 8 — pairing collapse:** `relayBaseURL` optional (the `shimBaseURL` pattern),
  gateway-only onboarding (URL + key / QR), capability-detect + #180 degradation for
  mixed-shape profiles, #15/#94 ladders scoped to relay-bearing profiles only.
- **App Store gate (decision, not code):** non-Owen hosts must never hold the
  developer `.p8` → choose vendor-run sender vs BGTask-only free tier before
  submission. Record the decision in #223.

## Self-review notes (per the writing-plans skill)

- Spec coverage: push v1 end-to-end (Lanes 0–3) fully tasked; later phases scoped with
  explicit triggers rather than placeholder tasks — deliberate, per the skill's
  scope-check (each later lane is a separate plan producing working software).
- Known unknowns are pinned as verification steps with expected outcomes (Task 1.6
  Step 4: session-row change marker; pytest availability fallback in Task 1.1).
- Type consistency: `extract_completion` / `WatcherState.completions_to_ping` /
  `build_apns_request` / `ApnsTokenPolicy` names match across tasks and the handler.
