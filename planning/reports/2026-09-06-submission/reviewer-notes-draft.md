# App Review notes — DRAFT for Owen's read (2026-09-06)

**Never submitted by an agent; this file is the draft Owen pastes into App Store Connect → App Review Information → Notes after reading it.**

## What Talaria is, in one paragraph (the reviewer's first read)

Talaria is a private assistant that runs entirely on the iPhone. The default brain is Apple's on-device model (Apple Intelligence / Foundation Models); nothing you type leaves the phone unless you choose to connect Talaria to your own server. Reviewers can exercise every feature of the app with **no server and no account**: chat, voice (Talk), reminders, alarms, calendar, contacts, health and motion questions, weather, photos, the share extension and the widgets all run against the on-device brain.

## How to review without a host (the intended default tier)

1. Install and open the app. Complete onboarding; do NOT enter a host — the "Connect Host" step is optional and can be skipped.
2. Ask anything in chat: "what's on my calendar today", "remind me to test at 4:30pm" (the app shows a confirmation card before writing), "how many steps today", "what's the weather in Cupertino".
3. Tap the microphone / Talk to hold a spoken conversation (on-device speech).
4. Share a PDF or a photo from another app into Talaria (the share extension) and ask about it.
5. Add the widgets from the home screen (Health tiles, quick ask).

Every device permission is asked in context and explained; declining any of them leaves the rest of the app working.

## The optional "Connect Host" tier (why some screens mention a server)

Talaria can also talk to a self-hosted Hermes agent that the user runs on their own machine (the same way a mail or SSH client talks to the user's own server). There is no Talaria-operated backend and no public server: the app never contacts one of ours. Screens under Settings → Connect Host let a user pair their own server; with nothing paired those screens simply say so. There is nothing for review to reach on that tier, and nothing in the app requires it.

## Permissions the app declares, and what each is for

- **Microphone / Speech Recognition** — Talk mode and dictation (on-device).
- **Calendars / Reminders / Alarms** — read to answer questions; every write is confirmed by the user on a card first.
- **Contacts** — look up a contact the user names.
- **Health (read only)** — steps, sleep, heart rate, calories for questions and the Health widget; the write description exists only because the system requires it — the app never writes health data.
- **Location (when in use)** — weather at the current location and place-aware answers.
- **Motion** — "what am I doing right now" style questions.
- **Camera / Photos** — attach a picture or document to a question (analysed on device or, only if the user turns it on, on Apple's Private Cloud Compute).
- **Face ID** — the optional App Lock.

## Third-party content

Weather comes from Apple Weather (WeatherKit) and is attributed under every reply that used it. Third-party notices (WebRTC, the OFL fonts) are in Settings → About → Licenses. Markdown images in replies are never fetched until the user taps them.

## Test account

None needed — the app has no accounts.
