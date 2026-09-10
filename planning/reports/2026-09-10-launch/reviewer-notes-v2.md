# App Review notes — v2 DRAFT for Owen's read (2026-09-10, #443)

**Supersedes `../2026-09-06-submission/reviewer-notes-draft.md`.** Never submitted by an
agent: Owen pastes this into App Store Connect → App Review Information → Notes after
reading it. Changes from v1: leads with the Apple Intelligence requirement (Owen's ruling
that the on-device tier is the review story), states iPhone-only, drops the iPad and
CarPlay implications, and marks the one sentence that still needs a measurement.

---

**Requirements (please read first).** Talaria requires an iPhone that supports Apple
Intelligence, running iOS 27, with Apple Intelligence turned on in Settings → Apple
Intelligence & Siri. The default assistant is Apple's on-device Foundation Model; there
is no other backend. On a device where the model is unavailable, the first message you
send is answered by the app itself with the exact reason and the setting to enable
(for example: "On-device intelligence is turned off. Enable Apple Intelligence in
Settings → Apple Intelligence & Siri, then try again.") — it does not fail silently.

<!-- 443-D evidence (not for pasting): the three reasons Apple's API can report
(deviceNotEligible / appleIntelligenceNotEnabled / modelNotReady) each map to a distinct
sentence in LocalChatBackend.unavailabilityMessage(for:), surfaced as a system message
by connect(), send() and streamTurn(); the unit test
LocalChatBackendTests.unavailabilityMessagesAreDistinctAndActionable pins all three.
This CANNOT be shown on a simulator: the sim reports the model as available and fails
at generation instead (#402), so the evidence is the code path and its test, not a
sim screenshot. A device with Apple Intelligence switched off would show it live. -->

**Language and region.** Apple Intelligence availability by language and region applies;
the app follows the device setting.

**What Talaria is.** A private assistant that runs entirely on the iPhone. Nothing you
type leaves the phone unless you deliberately connect the app to a server you run
yourself. Every feature can be exercised with **no server and no account**: chat, voice
(Talk), reminders, alarms, calendar, contacts, health and motion questions, weather,
photos and documents, the share extension, and the widgets all run against the on-device
model. This build is iPhone-only.

**How to review (the intended default).**
1. Install and open the app. In onboarding, skip "Connect Host" — it is optional.
2. Ask in chat: "what's on my calendar today", "remind me to test at 4:30pm" (a
   confirmation card appears before anything is written), "how many steps today",
   "what's the weather in Cupertino".
3. Tap Talk to hold a spoken conversation (on-device speech).
4. Share a PDF or a photo from another app into Talaria and ask about it.
5. Add the widgets from the Home Screen.

Every permission is requested in context and explained; declining any of them leaves the
rest of the app working.

**The optional "Connect Host" tier.** Talaria can also talk to a self-hosted Hermes agent
the user runs on their own computer, the way a mail client talks to the user's own mail
server. There is no Talaria-operated server, and the app never contacts one of ours. With
nothing paired, the screens under Settings → Connect Host simply say so. Nothing in the
app requires this tier, and there is nothing for review to reach on it. If you would like
to see it, we can provide a temporary host for the review window on request.

**Permissions the app declares, and what each is for.**
- Microphone / Speech Recognition — Talk mode and dictation, on device.
- Calendars / Reminders / Alarms — read to answer questions; every write is confirmed by
  the user on a card first.
- Contacts — look up a contact the user names.
- Health (read only) — steps, sleep, heart rate, calories for questions and the Health
  widget. The write description exists because the framework requires it; the app never
  writes health data.
- Location (when in use) — weather at the current location and place-aware answers.
- Motion — "what am I doing right now" questions.
- Camera / Photos — attach a picture or document to a question; analysed on device, or on
  Apple's Private Cloud Compute only if the user selects that tier in Settings → Models
  (the default brain is on-device; Private Cloud Compute is Apple's own service and is
  never used unless chosen).
- Face ID — the optional App Lock.

**Third-party content.** Weather comes from Apple Weather (WeatherKit) and is attributed
under every reply that used it. Third-party notices, including the OFL fonts, are in
Settings → About → Licenses. Images inside replies are never fetched until the user taps
them.

**Accounts and purchases.** None. There is no sign-in, no account creation, and no
in-app purchase in this version.

**Test account.** Not needed.
