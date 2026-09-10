# Review host — ON REQUEST ONLY (recipe, not a runbook step) — #443 / #166c

**Owen's ruling 2026-09-10:** no pre-emptive public host; the on-device tier is the review
story. This file exists so that IF App Review asks to see the "Connect Host" tier, the
answer is a rehearsed hour, not a scramble. **UNREHEARSED as written** — the first time
it is needed, run it end to end on a spare session before replying to App Review, and
correct this file from what actually happened.

## What a reviewer could exercise, and what they could not

- Reachable over a public HTTPS host: hosted chat on the runs plane, model picker,
  sessions shelf, Tasks / Skills / Insights reads.
- Not reachable: anything that needs the talaria plugin's device pairing (push, the
  webhook-driven voice bridge, sensors at query time). Say so in the reply rather than
  half-demonstrating it.

## Recipe (Mac Mini, the dev gateway on `:8642`)

1. **Do not touch the OTA `tailscale serve` on 443** (`tailscale serve --bg 8477` is what
   the phone installs from). Use a second HTTPS port for the funnel:
   ```bash
   tailscale funnel --bg --https=8443 8642
   tailscale funnel status
   ```
   Public URL: `https://owens-mac-mini.tail5663a6.ts.net:8443` (HTTPS, so ATS needs no
   exception — the `100.64.0.0/10` cleartext carve-out is irrelevant here).
2. **Mint a throwaway bearer for the review window.** The gateway authenticates with
   `API_SERVER_KEY` from `~/.hermes/.env`; rotate it to a fresh value for the window
   (edit `.env`, bounce the launchd-supervised gateway with `kill`, verify the LISTENER
   with `lsof -nP -iTCP:8642 -sTCP:LISTEN` — the respawn can race the rebind, see
   CLAUDE.md), and rotate it back afterwards. Never reuse the everyday key.
3. **Verify from outside the tailnet** (cellular, or a friend): `GET /health` answers
   `{"status":"ok"}` on the funnel URL; a bearer-less `POST /v1/runs` is refused.
4. **Reply to App Review** with the URL, the key, and the two-line "how to pair"
   (Settings → Connect Host → URL + key → Test Connection). Include the window
   (date range) during which the host is up.
5. **Teardown, the same day the review ends:**
   ```bash
   tailscale funnel --https=8443 off
   tailscale funnel status
   ```
   Rotate `API_SERVER_KEY` back, bounce the gateway, verify the listener again.

## Risks to name in the reply

- The host is a personal dev machine; uptime is best effort within the stated window.
- The gateway's sessions are shared state — start the reviewer on a fresh profile name
  so their transcripts do not mingle with Owen's.
- Exposing `:8642` publicly relies on the bearer alone; that is why the key is
  throwaway and the window is short.
