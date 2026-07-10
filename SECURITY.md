# Security Policy

## Reporting Vulnerabilities

If you discover a security vulnerability in Talaria, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities
2. Use GitHub's [private vulnerability reporting](https://github.com/AethyrionAI/Talaria-27/security/advisories/new) for this repository
3. Include a description of the vulnerability, steps to reproduce, and potential impact

We will acknowledge receipt within 48 hours and work with you on a fix.

## Deployment model

Talaria is designed for **private-network self-hosting**. The expected deployment puts all three host services (Sessions API `:8642`, relay `:8000`, models shim `:8765`) on a Tailscale tailnet or equivalent private network, reachable only by your own devices. None of the services are intended to be exposed to the public internet.

## Security Architecture

### Sessions API (chat)

The phone talks directly to the Hermes gateway's Sessions API on `:8642` with Bearer authentication (`API_SERVER_KEY`). Chat traffic does not pass through the relay.

### Relay

The relay handles sensor ingestion and the voice bootstrap:

- **Authentication:** Bearer token auth for iOS clients, connector credential for WebSocket
- **CONNECTOR_SETUP_SECRET:** Optional shared secret that gates new connector registration. When set as an env var on the relay, the connector must provide the same value during `hermes-mobile setup`. Strongly recommended for production deployments.
- **INTERNAL_API_KEY:** Gates internal admin endpoints. Must be changed from the default `"replace-me"` in production — the relay logs a security warning if the default is used outside development.
- **Token lifecycle:** Access tokens (1h default), refresh tokens (30d default), phone pairing codes (10min default) are all configurable via env vars. Tokens are persisted (hashed) in the relay's SQLite database and survive restarts.

### Connector

The connector runs on the same machine as the Hermes Agent:

- **WebSocket auth:** Authenticates to the relay using a credential obtained during setup
- **Sensor data:** Stored locally in SQLite at `~/.hermes-mobile/state/sensors.db`
- **MCP tools:** The `query_sensor_data` tool opens a read-only SQLite connection, preventing write-based SQL injection even if the LLM crafts a malicious query
- **OpenAI API key:** Stored in `~/.hermes-mobile/secrets.json` (not in state.json), used only for Realtime voice sessions

### iOS App

- **Service URLs:** Configured during onboarding, persisted locally. Not hardcoded.
- **Credentials:** Stored in the iOS Keychain (service name: `org.aethyrion.talaria.session`), mirrored so pairing survives app reinstalls
- **Health data:** Read-only HealthKit access, uploaded to the relay only when the connector is connected and acknowledges receipt
- **Camera/mic:** Requested just-in-time, not at launch. Camera frames for voice mode are sent directly to OpenAI via WebRTC, not through the relay.

### Known Limitations

- **Global ATS exception:** The app ships with `NSAllowsArbitraryLoads` enabled because the default deployment uses plain HTTP to Tailscale IP addresses, which App Transport Security would otherwise block. Traffic to your host is still encrypted in transit by Tailscale (WireGuard), but iOS-level TLS is not enforced. If you serve the backends over HTTPS (e.g. `tailscale serve` with MagicDNS), remove this exception from `project.yml` / `Info.plist` locally.
- **MCP tool token in URL:** The voice mode MCP tool token is passed as a query parameter (`?token=...`). This is a constraint of the MCP Streamable HTTP protocol. The token is short-lived (valid only during the active voice session), server-to-server (OpenAI → relay, never in a browser), and invalidated when the session ends.
- **Sensor data retention:** Health and location data is retained for 90 days locally on the connector host. Users should be aware of this when granting access to the machine.

## Supported Versions

Security updates are applied to the latest version on the `main` branch. There are no backported security patches for older commits.
