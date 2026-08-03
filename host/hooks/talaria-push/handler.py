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
