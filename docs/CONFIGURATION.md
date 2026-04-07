# Configuration and Deployment

This repo is designed to be public-safe and self-hosted-first.

Tracked configuration files should contain generic defaults. Real deployment values should be injected through local env, local config files, or deployment secrets.

## Relay Environment Variables

Core:

- `PUBLIC_BASE_URL`
- `DATABASE_URL`
- `INTERNAL_API_KEY`
- `RELAY_ENVIRONMENT`

Connector mode:

- `HERMES_ADAPTER=connector`
- `CONNECTOR_SYNC_WAIT_SECONDS`
- `CONNECTOR_JOB_LEASE_SECONDS`
- `CONNECTOR_HEARTBEAT_TIMEOUT_SECONDS`
- `CONNECTOR_IDLE_POLL_INTERVAL_SECONDS`
- `CONNECTOR_SETUP_SECRET` (optional)

Pairing/rate limits:

- `PHONE_PAIRING_CODE_TTL_SECONDS`
- `PHONE_PAIRING_MAX_ATTEMPTS_PER_CODE`
- `PHONE_PAIRING_MAX_ATTEMPTS_PER_IP`
- `PHONE_PAIRING_RATE_LIMIT_WINDOW_SECONDS`
- `HOST_ENROLLMENT_CODE_TTL_SECONDS`

## Connector Environment Variables

Required for real use:

- `HERMES_MOBILE_RELAY_URL`
- `HERMES_COMMAND`

Common runtime context:

- `HERMES_WORKDIR`
- `HERMES_PROVIDER`
- `HERMES_MODEL`
- `HERMES_TOOLSETS`
- `HERMES_SOURCE`
- `HERMES_HISTORY_LIMIT`
- `HERMES_HOME`

Optional connector-local state:

- `HERMES_MOBILE_CONNECTOR_HOME`

Optional bootstrap protection:

- `CONNECTOR_SETUP_SECRET`

If the relay is configured with `CONNECTOR_SETUP_SECRET`, the connector must provide the same value before `hermes-mobile setup`.

## iOS App Build/Runtime Config

The app reads these values from `Info.plist`:

- `APP_HOSTED_RELAY_ENABLED`
- `APP_HOSTED_RELAY_URL`
- `APP_SUPPORT_URL`
- `APP_TERMS_URL`
- `APP_PRIVACY_URL`

Public-safe tracked defaults should leave hosted relay disabled.

The app supports custom relay URLs at runtime through user settings and onboarding. A hosted relay is optional and feature-flagged by the plist values above.

## Private Override Strategy

For personal or private deployments, keep these values out of tracked source:

- hosted relay URL
- Fly app name
- `CONNECTOR_SETUP_SECRET`
- Apple signing team / bundle IDs if they differ from public-safe defaults

Recommended approach:

- relay: local `.env`, deployment secrets, or untracked `fly.toml` override
- connector: shell env / service env
- iOS app: local plist/build-setting override for hosted relay values

## Optional: APNs (Push Notifications)

Push notifications allow the relay to wake the app in the background for proactive messages and data refresh. **This is fully optional** — without it, the app refreshes when you open it. No functionality is lost, just proactivity.

### Setup (per developer)

1. Go to [Apple Developer Portal → Keys](https://developer.apple.com/account/resources/authkeys/list)
2. Create a new key with "Apple Push Notifications service (APNs)" enabled
3. Download the `.p8` file and note the Key ID and your Team ID
4. Configure the relay with these environment variables:
   ```
   APNS_KEY_PATH=/path/to/AuthKey_XXXXXXXXXX.p8
   APNS_KEY_ID=XXXXXXXXXX
   APNS_TEAM_ID=YYYYYYYYYY
   APNS_BUNDLE_ID=io.hermesmobile.HermesMobile  # or your custom bundle ID
   APNS_ENVIRONMENT=development  # or "production" for TestFlight/App Store
   ```
5. The iOS app automatically registers its device token with the relay on launch — no app-side configuration needed.

**Note:** The relay's APNs sending implementation is not yet built. The token registration pipeline is complete (iOS → relay stores token). Server-side push delivery is a future task.

### Without APNs

If you don't configure APNs, the app still works normally:
- Sensor data syncs when the app is in the foreground or on background location updates
- Conversations refresh when you open the app
- Voice mode, health, location, and all other features work without push

## Optional: CarPlay

CarPlay provides hands-free voice conversations with Hermes while driving. **This requires an entitlement from Apple** and is the only feature that cannot be self-configured without Apple's approval.

### Setup (per developer)

1. Go to [https://developer.apple.com/contact/carplay/](https://developer.apple.com/contact/carplay/)
2. Request the **Voice-Based Conversational** category entitlement
3. Describe your app: "AI assistant companion app with voice-based conversational interface"
4. Wait for Apple's approval (typically 1-2 weeks)
5. Once approved, the entitlement is tied to your App ID in the Developer Portal
6. Add the capability in your local Xcode signing setup or local entitlement override — keep that entitlement change out of tracked source if you're maintaining the public-safe defaults
7. Rebuild; the code already includes the CarPlay scene delegate and voice control template

### Without CarPlay

If you don't have the CarPlay entitlement:
- The `CarPlaySceneDelegate` is never called by the system — it's inert
- No build errors, no runtime errors, no configuration needed
- Voice mode works normally on the phone
- All other features are unaffected

### Build Flags

Both APNs and CarPlay are additive features with graceful degradation. No build flags or conditional compilation are needed — the code paths are simply never activated if the infrastructure isn't configured.

## Signing and Local Overrides

The tracked `project.pbxproj` has `DEVELOPMENT_TEAM = ""` and generic bundle IDs. When you open the project in Xcode:

1. Select your development team in Signing & Capabilities
2. Xcode updates the pbxproj with your team ID — **do not commit this change**
3. Your local signing config stays as an unstaged modification

If you use XcodeGen, you can add a local `.xcconfig` file (gitignored) to override signing:

```
// Local.xcconfig (not tracked)
DEVELOPMENT_TEAM = YOUR_TEAM_ID
CODE_SIGN_IDENTITY = Apple Development
```

Then reference it in project.yml or pass it via `xcodegen generate --config Local.xcconfig`.

## Personal Setup Checklist

If you are already running a private deployment, verify:

1. Your relay has the correct `PUBLIC_BASE_URL`.
2. Your connector service environment includes `HERMES_MOBILE_RELAY_URL`.
3. If `CONNECTOR_SETUP_SECRET` is enabled on the relay, it is also present in the connector environment before running `hermes-mobile setup`.
4. If you want the app to expose your hosted relay as an option, set `APP_HOSTED_RELAY_ENABLED=true` and `APP_HOSTED_RELAY_URL` locally in your app config.
5. (Optional) APNs: Generate a `.p8` key and configure the relay environment variables.
6. (Optional) CarPlay: Request the voice-based conversational entitlement from Apple.
