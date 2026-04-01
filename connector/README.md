# Hermes Mobile Connector

`hermes-mobile` is the host-side process that runs next to a local Hermes install and bridges it to a public Hermes Mobile relay.

## Install

```bash
cd /Users/dylan-mac-mini/Documents/HermesMobile/connector
python -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
```

## Configure Hermes execution

The connector only uses Hermes through the documented CLI surface. Configure it with environment variables:

```bash
export HERMES_COMMAND=/absolute/path/to/hermes
export HERMES_WORKDIR=/path/to/your/hermes/project
export HERMES_PROVIDER=
export HERMES_MODEL=
export HERMES_TOOLSETS=
export HERMES_SOURCE=tool
export HERMES_HISTORY_LIMIT=20
```

Optional connector-local state directory:

```bash
export HERMES_MOBILE_CONNECTOR_HOME=~/.hermes-mobile
```

Relay target:

```bash
export HERMES_MOBILE_RELAY_URL=https://hermes-mobile-relay-dylan.fly.dev/v1
```

## Setup

Create or link the relay account from the Hermes host first:

```bash
hermes-mobile setup
```

If you want to register the host first and leave Hermes config untouched for now:

```bash
hermes-mobile setup --skip-mcp
```

`setup` now does three things in one pass:
- validates that the local Hermes CLI is runnable
- creates or refreshes the relay-side host account
- optionally registers `mcp_servers.hermes_mobile` in `~/.hermes/config.yaml` and runs `hermes mcp test hermes_mobile`

Native MCP is the supported product path. `mcporter` is only useful for debugging or manual inspection.

In the interactive setup wizard, the connector now asks before it edits your Hermes config file:

`Automatically configure iOS tools MCP (Location Services, Health, and sensor context) in your Hermes Agent config file?`

If Hermes chat is already running when setup finishes, the connector will report `Reload required`. Run `/reload-mcp` inside Hermes or start a fresh chat so the new `hermes_mobile` MCP server is loaded into the active session.

If you skip MCP config during setup, you can enable it later with:

```bash
hermes-mobile configure-mcp
```

## Pair a phone

After setup, generate a short-lived phone pairing code and QR:

```bash
hermes-mobile pair-phone
```

Then open Hermes Mobile on the phone and scan the QR code or enter the displayed `ABCD-EFGH` code manually.

## Background service

You can keep the connector alive without an open terminal:

```bash
hermes-mobile service install
hermes-mobile service start
```

Management commands:

```bash
hermes-mobile service status
hermes-mobile service restart
hermes-mobile service stop
hermes-mobile service logs
hermes-mobile service uninstall
```

If you move to a new venv or Python path, rewrite the service artifacts with:

```bash
hermes-mobile service install --force
```

Platform behavior:
- macOS uses a per-user `launchd` LaunchAgent and starts after that user logs in.
- Windows gateway support is WSL2-only. The connector installs a Windows Scheduled Task that launches the WSL-hosted connector after Windows logon.
- Native Windows Hermes execution is not supported.

## Legacy enroll

The legacy host-enrollment path still exists for development and migration:

```bash
hermes-mobile enroll --code 'HC1:...'
```

You can inspect the stored enrollment:

```bash
hermes-mobile status
hermes-mobile service status
hermes-mobile configure-mcp
hermes-mobile validate-mcp
```

## Run

```bash
hermes-mobile run
```

`run` is the foreground development/debugging path. For day-to-day uptime, prefer `hermes-mobile service install` plus `hermes-mobile service start`.

The connector opens one outbound authenticated WebSocket to the relay, heartbeats while idle or during long jobs, executes one Hermes CLI job at a time, and reports results back to the relay.

Location and health data stay off the relay. The phone keeps a local outbox until the relay receives a live ACK from the connector path, and the connector stores delivered sensor context only in its local SQLite database for MCP queries.

HealthKit observer delivery and background location behavior require a physical iPhone for full validation. The simulator is still useful for pairing and foreground sync, but it does not prove device-only background wake behavior.
