# Security Policy

## Reporting Vulnerabilities

If you discover a security vulnerability in Talaria, please report it responsibly:

1. **Do not** open a public GitHub issue for security vulnerabilities
2. Use GitHub's [private vulnerability reporting](https://github.com/AethyrionAI/Talaria-27/security/advisories/new) for this repository
3. Include a description of the vulnerability, steps to reproduce, and potential impact

We will acknowledge receipt within 48 hours and work with you on a fix.

## Deployment model

Talaria is designed for **private-network self-hosting**. The expected deployment puts the Hermes gateway (Sessions API on `:8642`) on a Tailscale tailnet or equivalent private network, reachable only by your own devices. The gateway is the only service current builds require; the legacy relay tier (`:8000`) is optional and needed only for realtime server voice. None of the services are intended to be exposed to the public internet.

> **Corrected 2026-08-09.** This section previously named a **third service, a
> "models shim" on `:8765`, and told self-hosters to deploy and firewall it.
> That service was retired on 2026-08-04 and current builds never call it.**
> The README and the published docs were corrected the same day; this file was
> missed, so the project's security document described a service that no
> longer exists for five days. If you deployed a shim on a previous release,
> **it is now unused surface and should be stopped** — one fewer listener is
> strictly better.

## Security Architecture

### Sessions API (chat)

The phone talks directly to the Hermes gateway's Sessions API on `:8642` with Bearer authentication (`API_SERVER_KEY`). Chat traffic does not pass through the relay.

### Relay

The relay is a legacy tier whose surface has been narrowing steadily. Pairing, the inbox/directives channel, scheduled runs, and phone queries all migrated to the talaria plugin (same gateway process). **Sensor ingestion was retired outright 2026-08-16, #352** — the app no longer captures or uploads sensor data; phone data answers query-time asks over the talaria plugin. The relay's remaining job is the realtime-voice WebRTC bootstrap; agent-file downloads are partially superseded by the plugin's artifact mirror. On the production host the relay has been stopped and disabled since 2026-08-10 (#346).

> **⚠️ APNs push is UNUSED SURFACE as of 2026-08-09, and that is a security
> fact worth stating plainly.** The app's entire notification surface was
> removed in August 2026 — the shipping build has no `aps-environment`
> entitlement, does not call `registerForRemoteNotifications`, and never
> obtains a push token. **The relay's push machinery is still live**: it
> creates an APNs client at startup and its registration endpoint still
> accepts and stores an `apns_token`.
>
> So the deployment currently exposes **an authenticated endpoint that accepts
> and persists device push tokens which nothing will ever use.** It is not a
> known vulnerability — the endpoint is behind the same bearer auth as the
> rest of the relay, and tokens are stored hashed like other credentials — but
> unused credential-accepting surface is worth removing rather than leaving
> to rot. It is scheduled for removal with the relay itself; until then,
> self-hosters should know it is there and inert.

- **Authentication:** Bearer token auth for iOS clients, connector credential for WebSocket
- **CONNECTOR_SETUP_SECRET:** Optional shared secret that gates new connector registration. When set as an env var on the relay, the connector must provide the same value during `hermes-mobile setup`. Strongly recommended for production deployments.
- **INTERNAL_API_KEY:** Gates internal admin endpoints. Must be changed from the default `"replace-me"` in production — the relay logs a security warning if the default is used outside development.
- **Token lifecycle:** Access tokens (1h default), refresh tokens (30d default), phone pairing codes (10min default) are all configurable via env vars. Tokens are persisted (hashed) in the relay's SQLite database and survive restarts.

### Connector

The connector runs on the same machine as the Hermes Agent:

- **WebSocket auth:** Authenticates to the relay using a credential obtained during setup
- **Sensor data:** Historical only since #352 (2026-08-16) — the app no longer uploads sensor data. Previously ingested rows remain in SQLite at `~/.hermes-mobile/state/sensors.db` on hosts that ran the relay
- **MCP tools:** The `query_sensor_data` tool opens a read-only SQLite connection, preventing write-based SQL injection even if the LLM crafts a malicious query (serves only the historical rows above; disabled on the production host, #346)
- **OpenAI API key:** Stored in `~/.hermes-mobile/secrets.json` (not in state.json), used only for Realtime voice sessions

### iOS App

- **Service URLs:** Configured during onboarding, persisted locally. Not hardcoded.
- **Credentials:** Stored in the iOS Keychain (service name: `org.aethyrion.talaria.session`), mirrored so pairing survives app reinstalls
- **Health data:** Read-only HealthKit access, queried at request time by the agent over the talaria plugin. The old always-on upload pipeline was deleted 2026-08-16 (#352); nothing streams in the background
- **Camera/mic:** Requested just-in-time, not at launch. Camera frames for voice mode are sent directly to OpenAI via WebRTC, not through the relay — **and only when your selected brain permits it.** Since August 2026 the brain selection governs voice, not just chat: the router consults it *before* pairing is even considered, so choosing the on-device brain keeps realtime voice — and therefore any camera frame reaching OpenAI — from starting at all. Selecting an on-device brain is a privacy control, not only a routing preference.

### Known Limitations

- **Scoped ATS exception:** The app permits insecure HTTP only to the Tailscale CGNAT range (`100.64.0.0/10`, via an `NSExceptionDomains` entry) because the default deployment uses plain HTTP to Tailscale IP addresses, which App Transport Security would otherwise block. TLS enforcement remains active for every other connection the app makes. Traffic to your host is still encrypted in transit by Tailscale (WireGuard), but iOS-level TLS is not enforced on that path. If you serve the backends over HTTPS (e.g. `tailscale serve` with MagicDNS), you can remove even this scoped exception from `project.yml` locally. (Verified 2026-07-22: with no exception, or with only `NSAllowsLocalNetworking`, ATS blocks tailnet IP traffic outright — the exception is load-bearing, and the CIDR scoping was confirmed with an outside-range negative control.)
- **MCP tool token in URL:** The voice mode MCP tool token is passed as a query parameter (`?token=...`). This is a constraint of the MCP Streamable HTTP protocol. The token is short-lived (valid only during the active voice session), server-to-server (OpenAI → relay, never in a browser), and invalidated when the session ends.
- **Sensor data retention (historical):** Hosts that previously ran the connector may retain up to 90 days of health and location data in SQLite at `~/.hermes-mobile/state/sensors.db`. No new data is collected since the upload pipeline was removed (2026-08-16, #352). Users should be aware of this historical data when granting access to the machine.

## Supported Versions

Security updates are applied to the latest version on the `main` branch. There are no backported security patches for older commits.
