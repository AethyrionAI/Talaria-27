# App Review reply — Guideline 2.1 "Information Needed" (submission 9eaf52da, 2026-09-11)

**What this is.** Apple's boilerplate first-submission questionnaire ("This app has been
submitted by a developer account that has a limited App Review history"). Nothing in it
references anything a reviewer saw in Talaria. It asks for six pieces of information in
the notes plus a screen recording, then the same build is re-reviewed. No code change.

**How to answer (Owen's hands, ~20 minutes plus one recording):**
1. Record the screen on the phone (shot list below), AirDrop/Taildrop it to the Mac, upload
   it somewhere Apple can fetch (an unlisted YouTube link or a Google Drive share link both
   work; Apple asks for a link, not an attachment).
2. App Store Connect → the submission page → **Reply to App Review**: paste the reply below
   with the link filled in.
3. Also paste the same six answers into **App Review Information → Notes** (they ask for
   both, and the notes persist for future submissions).
4. **Resubmit to App Review** — same build 3338; nothing else changes.

---

## The reply (paste into "Reply to App Review")

Thank you for the review. The requested information follows; it is also added to the App Review Information notes for future submissions.

1. SCREEN RECORDING
[LINK] — recorded on an iPhone running iOS 27, from app launch through the typical flow: choosing "Start Locally" on the first screen, asking a question in chat, a spoken conversation in Talk, creating a reminder (showing the confirmation card before anything is written), the Health widget, and sharing a PDF into the app. The app has no account registration, no login, no account deletion (there are no accounts), no user-generated public content, and no paid content, so none of those flows exist to record.

2. PURPOSE AND AUDIENCE
Talaria is a private personal assistant that runs entirely on the iPhone using Apple's on-device Foundation Model (Apple Intelligence). It answers questions about the user's own calendar, reminders, contacts, health data, motion, weather and shared photos or documents, and can create reminders, alarms and calendar events after the user confirms each one on a card. The problem it solves is having an assistant that never sends personal data to a third-party server: there is no Talaria backend, no account, and no analytics. The audience is iPhone users who want an assistant with that privacy posture, and, optionally, technically inclined users who run their own Hermes agent on a computer they control and want to reach it from the phone.

3. HOW TO ACCESS THE MAIN FEATURES
No credentials or sample files are required. Install, open, and choose "Start Locally" on the first screen. Then: type any question in chat (for example "what's on my calendar today" or "how many steps have I taken"); tap the Talk button to speak instead; ask it to "remind me to call the dentist at 4pm" and confirm the card; add the Talaria widgets from the Home Screen; share a PDF or photo from any app into Talaria via the share sheet and ask about it. Each device permission (calendar, reminders, contacts, health, location, microphone, speech, motion, photos) is requested in context the first time that feature is used, and declining any of them leaves the rest of the app working. Requirement: an iPhone that supports Apple Intelligence with Apple Intelligence enabled, on iOS 27. The optional "Connect My Host" path requires a server the user runs themselves and is not needed to review any feature; if you would like to see it, we can provide a temporary host for the review window on request.

4. EXTERNAL SERVICES, TOOLS AND PLATFORMS
Apple frameworks only: Foundation Models (on-device, and Private Cloud Compute only if the user turns that tier on; it is off on a fresh install), Speech, HealthKit, EventKit, Contacts, Core Motion, Core Location, WeatherKit (weather data, attributed in the app), WidgetKit, App Intents. One third-party library is compiled in: the open-source WebRTC framework (stasel/WebRTC, BSD license), used only for the optional realtime voice link to a user's own self-hosted server; it contacts no service of ours. No analytics, crash-reporting, advertising, authentication, or payment SDKs are included. The app never contacts a server operated by the developer.

5. REGIONAL DIFFERENCES
None in the app's own features. Availability of Apple Intelligence by language and region applies, as it does to every app that uses the on-device model; the App Store description states the requirement.

6. REGULATED INDUSTRY / PROTECTED THIRD-PARTY MATERIAL
Not applicable. The app is not in a regulated industry and includes no protected third-party material. Bundled open-source fonts (Chakra Petch, Space Grotesk, JetBrains Mono) are under the SIL Open Font License and are credited in Settings → About → Licenses, along with the WebRTC notice.

---

## Screen-recording shot list (one take, 3–4 minutes, no narration needed)

Settings → Control Center → Screen Recording, or the Control Center button. Portrait.
Delete the app first? No — a paired install is fine, but the first screen the reviewer
asked to see is the launch flow, so do this on a **clean profile** if it's cheap:
Settings → Server → disconnect the host beforehand so the app is in the hostless state
the reviewer will have. (Re-pair afterwards.)

1. Home Screen → tap the Talaria icon (they asked for "launching the app").
2. If the chooser appears, tap **Start Locally**. If it lands straight in chat, that's fine too.
3. Chat: type "what's on my calendar today" → send → wait for the answer.
4. Chat: type "remind me to test Talaria at 4pm" → send → the confirmation card → tap confirm.
5. Tap **Talk** → say one sentence ("what's the weather like right now") → wait for the spoken reply → end Talk.
6. Swipe to the Home Screen → long-press → add a Talaria widget (the Health one) → back to the app.
7. Open Files or Photos → share a PDF or photo → choose Talaria → back in the app, ask "what is this".
8. Open Settings (gear) → scroll the grid once → close.
9. Stop recording.

Upload the video (Photos → share → save to Files, then Google Drive / an unlisted YouTube
upload from the phone) and paste the link into [LINK] above. Apple accepts any URL a
reviewer can open without signing in.
