# Local development

This is the fastest way to run the relay during development. For the *persistent*
Mac Mini deployment (launchd services, production env, T6 Phase 1), use
`relay/docs/DEPLOY_MAC.md` instead — this page is for a hand-run relay that dies
with the terminal.

## Start the relay

```bash
cd relay
python -m venv .venv
source .venv/bin/activate
pip install -e .[dev]
cp .env.example .env
uvicorn app.main:app --reload
```

Or use Docker Compose from the same directory if you want a containerized local stack.

## Choose the right base URL

### Simulator on the same Mac

Use:

```bash
http://127.0.0.1:8000/v1
```

### Physical iPhone on the same network

Use your Mac’s LAN IP:

```bash
http://192.168.x.x:8000/v1
```

> [!IMPORTANT]
> `127.0.0.1` and `localhost` do not work on a physical iPhone. They point back to the phone itself.

## Connector local setup

```bash
cd connector
python -m venv .venv
source .venv/bin/activate
pip install -e .[dev]

export HERMES_COMMAND=/absolute/path/to/hermes
export HERMES_MOBILE_RELAY_URL=http://127.0.0.1:8000/v1   # simulator
# or your Mac's LAN IP for a real phone

hermes-mobile setup
hermes-mobile pair-phone
```

## Useful env vars

- `PUBLIC_BASE_URL`
- `DATABASE_URL`
- `INTERNAL_API_KEY`
- `HERMES_ADAPTER`
- `CONNECTOR_SETUP_SECRET` (optional)

For realistic end-to-end local testing, prefer:

```bash
HERMES_ADAPTER=connector
```
