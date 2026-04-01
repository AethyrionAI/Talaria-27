# Hermes Mobile Relay

FastAPI relay for Hermes Mobile. This service owns device registration, pairing, app session bootstrap, host enrollment, message persistence, connector queueing, push registration, inbox APIs, and Hermes-facing internal inbox hooks.

## Run locally

1. Create a virtual environment and install dependencies.
2. Copy `.env.example` to `.env` and adjust values if needed.
3. Start Postgres and the relay:

```bash
docker compose up --build
```

Or run the API directly:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
uvicorn app.main:app --reload
```

## Deploy to Fly.io

Fly's docs recommend installing `flyctl`, logging in with `fly auth login`, and running `fly launch` or `fly deploy` from the app source directory. Because this repo is a monorepo and Fly deploys from the current working directory, deploy from [`/Users/dylan-mac-mini/Documents/HermesMobile/relay`](/Users/dylan-mac-mini/Documents/HermesMobile/relay), where [`fly.toml`](/Users/dylan-mac-mini/Documents/HermesMobile/relay/fly.toml) and [`Dockerfile`](/Users/dylan-mac-mini/Documents/HermesMobile/relay/Dockerfile) live.

The Fly deployment details for this relay are documented in [`relay/docs/fly-io.md`](/Users/dylan-mac-mini/Documents/HermesMobile/relay/docs/fly-io.md).

## API surface

- `GET /v1/health`
- `GET /v1/version`
- `POST /v1/connector/setup`
- `POST /v1/connector/phone-pairing-codes`
- `POST /v1/phone-pairing/redeem`
- `POST /v1/device/register`
- `POST /v1/pairing/redeem`
- `POST /v1/hosts/enrollment-codes`
- `GET /v1/hosts/current`
- `POST /v1/hosts/current/revoke`
- `POST /v1/hosts/redeem`
- `GET /v1/hosts/ws` (WebSocket)
- `GET /v1/session`
- `POST /v1/auth/refresh`
- `POST /v1/auth/revoke`
- `POST /v1/push/register`
- `GET /v1/conversations/current`
- `POST /v1/messages`
- `GET /v1/inbox`
- `POST /v1/inbox/{id}/action`
- `POST /internal/inbox/create`
- `GET /internal/inbox/{id}/actions`

## Hermes execution modes

The relay now supports three Hermes execution modes:

- `HERMES_ADAPTER=mock`
  - local/demo behavior with deterministic mock replies
- `HERMES_ADAPTER=cli`
  - the relay shells out to Hermes locally, useful for same-machine development and smoke tests
- `HERMES_ADAPTER=connector`
  - production-oriented mode where the public relay queues jobs and a user-owned host connector invokes Hermes locally on that machine

For local CLI mode, set:

```bash
HERMES_ADAPTER=cli
HERMES_COMMAND=/absolute/path/to/hermes
HERMES_WORKDIR=/path/to/your/hermes/project
HERMES_PROVIDER=
HERMES_MODEL=
HERMES_TOOLSETS=
HERMES_SOURCE=tool
```

The relay now uses Hermes quiet mode for programmatic calls, parses the returned `session_id`, and stores that ID on the relay conversation. The first turn still uses relay-side history replay into `hermes chat -Q -q ...`; follow-up turns resume the same Hermes session when possible, and fall back to transcript replay if the local Hermes session is missing.

For connector mode, set:

```bash
HERMES_ADAPTER=connector
PUBLIC_BASE_URL=https://your.public.relay.example/v1
PHONE_PAIRING_CODE_TTL_SECONDS=600
PHONE_PAIRING_MAX_ATTEMPTS_PER_CODE=5
PHONE_PAIRING_MAX_ATTEMPTS_PER_IP=5
PHONE_PAIRING_RATE_LIMIT_WINDOW_SECONDS=300
HOST_ENROLLMENT_CODE_TTL_SECONDS=900
CONNECTOR_SYNC_WAIT_SECONDS=25
CONNECTOR_JOB_LEASE_SECONDS=180
CONNECTOR_HEARTBEAT_TIMEOUT_SECONDS=30
CONNECTOR_IDLE_POLL_INTERVAL_SECONDS=1.0
```

In connector mode the relay never shells out to Hermes directly. Instead, it persists chat jobs and waits for a connected `hermes-mobile-connector` host process to claim and execute them.

Sensor delivery in connector mode is relay-stateless. The phone uploads location and health samples only when paired and authenticated, the relay forwards them to the live connector WebSocket, and the request is treated as delivered only after the connector ACKs local storage. If the host is offline or busy, the relay returns `202` with `deliveryState=retry` and the phone keeps the payload in its local outbox.

## Connector-first setup

On the machine where Hermes lives:

```bash
cd /Users/dylan-mac-mini/Documents/HermesMobile/connector
python -m venv .venv
source .venv/bin/activate
pip install -e .[dev]

export HERMES_COMMAND=/absolute/path/to/hermes
export HERMES_WORKDIR=/path/to/your/hermes/project
export HERMES_MOBILE_RELAY_URL=https://hermes-mobile-relay-dylan.fly.dev/v1

hermes-mobile setup
hermes-mobile pair-phone
hermes-mobile service install
hermes-mobile service start
```

`pair-phone` prints the short-lived manual code plus an ASCII QR. Hermes Mobile release onboarding now expects that connector-generated phone pairing code instead of the old HM1/HC1 two-step flow.

`setup` also auto-registers `mcp_servers.hermes_mobile` in the local Hermes config and validates it with `hermes mcp test hermes_mobile`. If Hermes chat is already open, the connector reports `Reload required`, and the user should run `/reload-mcp` or start a fresh chat before expecting location and health tools to appear in the current session.

`hermes-mobile run` is still available for foreground debugging, but the managed service is the recommended path for a persistent host.

The connector keeps one outbound authenticated WebSocket connection to the relay, executes one Hermes job at a time, resumes Hermes sessions when possible, and sends replies back to the relay for delivery to the iOS app.

Background health delivery and Always-authorized background location still require physical-device validation on iPhone. Simulator testing covers onboarding, foreground sync, and the app-side outbox, but not HealthKit background wakes.
