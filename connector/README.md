# Hermes Mobile Connector

`hermes-mobile-connector` is the host-side process that runs next to a local Hermes install and bridges it to a public Hermes Mobile relay.

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
export HERMES_MOBILE_CONNECTOR_HOME=~/.hermes-mobile-connector
```

Relay target:

```bash
export HERMES_MOBILE_RELAY_URL=https://hermes-mobile-relay-dylan.fly.dev/v1
```

## Setup

Create or link the relay account from the Hermes host first:

```bash
hermes-mobile-connector setup \
  --owner-display-name "Taylor" \
  --host-display-name "Home Mac mini"
```

## Pair a phone

After setup, generate a short-lived phone pairing code and QR:

```bash
hermes-mobile-connector pair-phone
```

Then open Hermes Mobile on the phone and scan the QR code or enter the displayed `ABCD-EFGH` code manually.

## Legacy enroll

The legacy host-enrollment path still exists for development and migration:

```bash
hermes-mobile-connector enroll --code 'HC1:...'
```

You can inspect the stored enrollment:

```bash
hermes-mobile-connector status
```

## Run

```bash
hermes-mobile-connector run
```

The connector opens one outbound authenticated WebSocket to the relay, heartbeats while idle or during long jobs, executes one Hermes CLI job at a time, and reports results back to the relay.
