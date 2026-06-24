# Talaria Models Shim

A minimal, Tailscale-bound HTTP service that gives the Talaria iOS app Hermes's
**model list** and **set-default** operations *without* running the privileged
dashboard web plane (port 9119). It calls the same plain functions the dashboard
wraps, so the data is 1:1 with `/api/model/options` / `/api/model/set`.

## Why
- The Hermes **gateway** (`:8642`) exposes no real model list — only the
  `hermes-agent` pseudo-model on `/v1/models`.
- The host-accurate list lives behind the **dashboard** (`:9119`), which is a
  privileged management plane (indirect agent/terminal access).
- This shim exposes **only** model list + set-default, bound to the tailnet,
  token-authed — a much smaller surface than running the dashboard live.

## Routes
| Method | Path | Notes |
|---|---|---|
| GET | `/healthz` | Liveness, no auth. |
| GET | `/models?refresh=0\|1` | `build_models_payload(...)` + `compiled_at`/`ttl_seconds`. `refresh=1` busts the 1h per-provider disk cache (the "Refresh Models" button). |
| POST | `/models/default` | Body `{provider, model, confirm_expensive?}`. Sets the persistent main default (new-session scope). Returns `{ok, scope, provider, model, ...}` or `{ok:false, confirm_required:true, confirm_message}` for an expensive-model guard. |

Current-session hot-swap is **not** here — that stays on the gateway's `/model`
slash command. This shim only handles the list and the persistent default.

## Auth
Bearer token at `~/.hermes/talaria_shim_token` (auto-created `0600` on first run).
Send `Authorization: Bearer <token>`. The app stores this token in its config.

## Bind
`TALARIA_SHIM_HOST` (default `100.79.222.100`, the mini's tailnet IP) :
`TALARIA_SHIM_PORT` (default `8765`). Tailnet-only — not LAN, not public.

## Service management (launchd)
```sh
# install / start
cp com.aethyrion.talaria.modelsshim.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.aethyrion.talaria.modelsshim.plist

# status
launchctl print gui/$(id -u)/com.aethyrion.talaria.modelsshim | grep -E "state|pid"

# stop / uninstall
launchctl bootout gui/$(id -u)/com.aethyrion.talaria.modelsshim
rm ~/Library/LaunchAgents/com.aethyrion.talaria.modelsshim.plist

# logs
tail -f ~/.hermes/logs/talaria-shim.{out,err}.log
```

## Files
- `shim.py` — the service (stdlib `http.server`, no extra deps; imports `hermes_cli`).
- `com.aethyrion.talaria.modelsshim.plist` — LaunchAgent.
- `model_options.sample.json` — captured real `/api/model/options` payload, for
  building/rendering the MODELS screen against real data.

## Runs under
`~/.hermes/hermes-agent/venv/bin/python` (needs `hermes_cli` importable).
