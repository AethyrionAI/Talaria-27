# Hermes iOS Connector

`hermes-mobile` is the host-side bridge between the Hermes iPhone app and a local Hermes runtime. It owns the durable connection to the relay, executes Hermes work on the host machine, exposes phone context through MCP, and keeps the host available when no terminal window is open.

<insert image> Connector CLI setup wizard after validating the Hermes command and prompting for the relay source.

## What the connector does

- connects to the relay over one authenticated WebSocket
- runs Hermes jobs on the host through the CLI or configured API runtime
- registers the local `hermes_mobile` MCP server in `~/.hermes/config.yaml`
- stores sensor data in `~/.hermes-mobile/state/sensors.db`
- manages OpenAI Realtime talk configuration for the host
- installs a background service on macOS and WSL2

## Prerequisites

- Python 3.11+
- a working Hermes installation (`hermes --version` should succeed)
- access to the relay you want to pair against
- for physical-phone testing against a local relay: the phone and Mac on the same network

## Install

```bash
cd connector
python -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
```

## Recommended setup flow

### 1. Define the Hermes runtime context

```bash
export HERMES_COMMAND=/absolute/path/to/hermes
export HERMES_WORKDIR=/path/to/your/hermes/project
export HERMES_PROVIDER=
export HERMES_MODEL=
export HERMES_TOOLSETS=
export HERMES_SOURCE=tool
export HERMES_HISTORY_LIMIT=20
```

Optional:

```bash
export HERMES_HOME=~/.hermes
export HERMES_MOBILE_CONNECTOR_HOME=~/.hermes-mobile
```

### 2. Run the setup wizard

```bash
hermes-mobile setup
```

The wizard supports three paths:

- **Deploy a new relay on Fly.io**
- **Use an existing relay URL**
- **Use a local-network relay for same-network testing**

You can also bypass the prompt:

```bash
hermes-mobile setup --relay-url https://your-relay.example.com/v1
```

If the relay requires bootstrap protection:

```bash
export CONNECTOR_SETUP_SECRET=replace-me
```

> [!IMPORTANT]
> A physical iPhone cannot reach `127.0.0.1` on your Mac. For same-network testing, use your Mac's LAN IP such as `http://192.168.1.10:8000/v1`.

### 3. Pair the phone

```bash
hermes-mobile pair-phone
```

This prints:

- an ASCII QR code
- a short-lived manual code like `ABCD-EFGH`

Open Hermes iOS, point it at the same relay URL, then scan the QR code or enter the code manually.

<insert image> Connector `pair-phone` output showing the QR code and manual pairing code.

## What setup can configure for you

During setup the connector can optionally:

- register `mcp_servers.hermes_mobile` in `~/.hermes/config.yaml`
- validate the MCP entry with `hermes mcp test hermes_mobile`
- configure OpenAI Realtime talk mode with a connector-owned API key
- install and start the background service

If you want to skip MCP registration:

```bash
hermes-mobile setup --skip-mcp
```

Later:

```bash
hermes-mobile configure-mcp
hermes-mobile validate-mcp
```

If Hermes chat is already open when MCP registration finishes, the connector may report `Reload required`. Run `/reload-mcp` in Hermes or start a fresh chat.

## Recommended: install the `hermes-ios` skill

The MCP server gives Hermes access to the tools, but the bundled `hermes-ios` skill teaches the agent when and how to use them well for location, health, activity, and sensor-aware responses.

From the repo root:

```bash
mkdir -p ~/.hermes/skills
cp -R skills/hermes-ios ~/.hermes/skills/
```

Then reload Hermes:

```text
/reload-mcp
```

Or start a fresh Hermes session.

> [!IMPORTANT]
> Copy the skill directory into `~/.hermes/skills`. Do not rely on a symlink-based install unless you have already confirmed your Hermes setup follows symlinked skills correctly.

If you are updating an older copy of the skill, replace it explicitly:

```bash
rm -rf ~/.hermes/skills/hermes-ios
cp -R skills/hermes-ios ~/.hermes/skills/
```

## Background service

Keep the connector alive without an open terminal:

```bash
hermes-mobile service install
hermes-mobile service start
```

Useful commands:

```bash
hermes-mobile service status
hermes-mobile service restart
hermes-mobile service stop
hermes-mobile service logs
hermes-mobile service uninstall
```

If your Python path or venv changes:

```bash
hermes-mobile service install --force
```

Platform notes:

- macOS uses a per-user `launchd` LaunchAgent
- Windows support is WSL2-only through a Scheduled Task
- native Windows Hermes execution is not supported

## Realtime talk configuration

Realtime talk is connector-owned, not app-owned.

Configure it during setup or later:

```bash
hermes-mobile configure-realtime
```

Helpful commands:

```bash
hermes-mobile configure-realtime --clear
hermes-mobile status
```

`status` reports whether talk is configured, the selected model, and the last validation result without printing secrets.

Talk mode counts as configured when both of these resolve:

- **Enabled flag** — `realtime_talk.enabled` in the connector state
  (written by `configure-realtime`), or set by hand in the secrets store
  (`~/.hermes-mobile/secrets.json`) as `"realtime_talk_enabled": true`,
  `"realtime_talk": {"enabled": true}`, or `"realtime_talk.enabled": true`.
  A value in the secrets store takes precedence over the state file.
- **OpenAI API key** — looked up in order: `openai_api_key` in
  `~/.hermes-mobile/secrets.json`, the `OPENAI_API_KEY` environment
  variable, then `OPENAI_API_KEY` in the Hermes settings
  (`$HERMES_HOME/.env`).

Unknown keys in hand-edited state/secrets files are ignored rather than
treated as fatal.

## Troubleshooting

### Relay setup

- If you already have a relay, set `HERMES_MOBILE_RELAY_URL` and rerun `hermes-mobile setup`.
- If the Fly wizard fails, follow the manual steps in [../relay/docs/fly-io.md](../relay/docs/fly-io.md).
- If you are using a local relay, confirm the phone can reach the Mac's LAN IP.

### Hermes execution

- `hermes --version` should work before setup.
- If jobs fail, run:

```bash
hermes-mobile status
hermes-mobile service logs
```

### MCP registration

- If `configure-mcp` says `Reload required`, reload the active Hermes chat session.
- If `validate-mcp` fails, inspect `~/.hermes/config.yaml` and the connector logs.

## Connector data and schema

The connector keeps sensor and host-side context in SQLite. See [SENSOR_SCHEMA.md](SENSOR_SCHEMA.md) for:

- table definitions
- health metric coverage
- daily rollups
- MCP query tools
- example SQL use cases

## Advanced / legacy

The legacy host-enrollment flow still exists for development and migration:

```bash
hermes-mobile enroll --code 'HC1:...'
```

For almost all new users, `hermes-mobile setup` + `hermes-mobile pair-phone` is the right path.
