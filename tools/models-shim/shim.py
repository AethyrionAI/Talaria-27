#!/usr/bin/env python3
"""Talaria Models Shim.

A minimal, Tailscale-bound HTTP service that exposes Hermes's model list and
set-default operations to the Talaria iOS app WITHOUT running the privileged
dashboard web plane. It calls the same plain functions the dashboard wraps:
  - GET  /models?refresh=0|1   -> hermes_cli.inventory.build_models_payload(...)
  - POST /models/default {...} -> hermes_cli.web_server._apply_model_assignment_sync(...)

Auth: Bearer token from ~/.hermes/talaria_shim_token (auto-created, 0600).
Bind: TALARIA_SHIM_HOST (default tailnet IP) : TALARIA_SHIM_PORT (default 8765).
"""
import os, json, time, secrets, threading, datetime, traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

from hermes_cli.inventory import build_models_payload, load_picker_context
from hermes_cli.web_server import _apply_model_assignment_sync, _profile_scope
try:
    from fastapi import HTTPException
except Exception:
    HTTPException = None
try:
    from hermes_cli.model_cost_guard import expensive_model_warning
except Exception:
    expensive_model_warning = None

HOST = os.environ.get("TALARIA_SHIM_HOST", "100.79.222.100")
PORT = int(os.environ.get("TALARIA_SHIM_PORT", "8765"))
TTL  = int(os.environ.get("TALARIA_SHIM_TTL", "3600"))
TOKEN_FILE = os.path.expanduser("~/.hermes/talaria_shim_token")

def _load_token():
    if os.path.exists(TOKEN_FILE):
        t = open(TOKEN_FILE).read().strip()
        if t:
            return t
    t = secrets.token_urlsafe(32)
    fd = os.open(TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.write(fd, t.encode()); os.close(fd)
    return t

TOKEN = _load_token()
_lock = threading.Lock()
_cache = {"payload": None, "compiled_at": 0.0}

def _build(refresh):
    return build_models_payload(
        load_picker_context(),
        include_unconfigured=True, picker_hints=True, canonical_order=True,
        pricing=True, capabilities=True, refresh=bool(refresh),
    )

def _get_models(refresh):
    with _lock:
        now = time.time()
        fresh = _cache["payload"] is not None and (now - _cache["compiled_at"]) < TTL
        if refresh or not fresh:
            _cache["payload"] = _build(refresh)
            _cache["compiled_at"] = now
        out = dict(_cache["payload"])
        out["compiled_at"] = datetime.datetime.fromtimestamp(
            _cache["compiled_at"], datetime.timezone.utc).isoformat()
        out["ttl_seconds"] = TTL
        out["refreshed"] = bool(refresh)
        return out

def _set_default(provider, model, confirm_expensive):
    if expensive_model_warning and not confirm_expensive:
        try:
            w = expensive_model_warning(model, provider=provider, base_url="")
        except Exception:
            w = None
        if w is not None:
            return {"ok": False, "confirm_required": True,
                    "confirm_message": getattr(w, "message", str(w)),
                    "provider": provider, "model": model}
    with _profile_scope(None):
        result = _apply_model_assignment_sync("main", provider, model, "", "", "")
    # The persistent default just changed in config.yaml. Invalidate the cached
    # GET payload so the NEXT /models (even refresh=0) rebuilds and reflects the new
    # current. The rebuild is cheap when refresh=0 — it re-reads config for the
    # model/provider pointer but reuses each provider's on-disk model-list cache, so
    # clients don't need the slow refresh=1 just to see their own set-default land.
    with _lock:
        _cache["payload"] = None
        _cache["compiled_at"] = 0.0
    return result

class H(BaseHTTPRequestHandler):
    server_version = "TalariaModelsShim/1.0"
    def _authed(self):
        return self.headers.get("Authorization", "") == f"Bearer {TOKEN}"
    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        u = urlparse(self.path)
        if u.path == "/healthz":
            return self._send(200, {"ok": True, "service": "talaria-models-shim"})
        if not self._authed():
            return self._send(401, {"ok": False, "error": "unauthorized"})
        if u.path == "/models":
            q = parse_qs(u.query)
            refresh = q.get("refresh", ["0"])[0].lower() in ("1", "true", "yes")
            try:
                return self._send(200, _get_models(refresh))
            except Exception as e:
                traceback.print_exc()
                return self._send(500, {"ok": False, "error": str(e)})
        return self._send(404, {"ok": False, "error": "not found"})
    def do_POST(self):
        u = urlparse(self.path)
        if not self._authed():
            return self._send(401, {"ok": False, "error": "unauthorized"})
        if u.path == "/models/default":
            try:
                n = int(self.headers.get("Content-Length", "0") or "0")
                body = json.loads(self.rfile.read(n) or b"{}")
            except Exception:
                return self._send(400, {"ok": False, "error": "bad json"})
            provider = (body.get("provider") or "").strip()
            model = (body.get("model") or "").strip()
            if not provider or not model:
                return self._send(400, {"ok": False, "error": "provider and model required"})
            try:
                return self._send(200, _set_default(provider, model, bool(body.get("confirm_expensive"))))
            except Exception as e:
                if HTTPException and isinstance(e, HTTPException):
                    return self._send(e.status_code, {"ok": False, "error": e.detail})
                traceback.print_exc()
                return self._send(500, {"ok": False, "error": str(e)})
        return self._send(404, {"ok": False, "error": "not found"})
    def log_message(self, fmt, *args):
        return

def main():
    last_err = None
    for _ in range(30):
        try:
            httpd = ThreadingHTTPServer((HOST, PORT), H)
            break
        except OSError as e:
            last_err = e; time.sleep(2)
    else:
        print(f"TALARIA_SHIM_BIND_FAILED {last_err}", flush=True)
        raise SystemExit(1)
    print(f"TALARIA_SHIM_READY host={HOST} port={PORT}", flush=True)
    httpd.serve_forever()

if __name__ == "__main__":
    main()
