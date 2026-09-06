# App Privacy questionnaire — DRAFT answers for Owen (2026-09-06)

Source of truth: the three shipped privacy manifests (`Talaria/Resources`, `TalariaShare`, `TalariaWidgets` — all three declare `NSPrivacyTracking = false`, no tracking domains, **no collected data types**, no required-reason API categories) and the code as reviewed in the 2026-09-04 launch audit and the lanes since (#432 closed the one place response bodies could reach a device log).

## The headline answer

**"Data Not Collected."** Talaria (the developer) collects nothing. There is no Talaria backend, no analytics SDK, no crash-reporting service, no advertising identifier, no account. Apple's questionnaire asks what the DEVELOPER collects or that third-party SDKs in the app collect on the developer's behalf; both are none.

## The two things to state explicitly in the notes (so "Data Not Collected" is not read as a dodge)

1. **The user's own server.** If a user chooses to connect Talaria to a Hermes agent they run themselves, their chat text goes to THAT machine. The developer never receives it. Apple treats data sent to a server the user controls as not "collected" by the developer; say so in the review notes (done in `reviewer-notes-draft.md`).
2. **Apple's own services.** Private Cloud Compute (off by default; user-enabled), WeatherKit, HealthKit, EventKit and Foundation Models are Apple frameworks under Apple's terms; nothing is sent to Talaria's developer.

## Per-category checklist (answer "no" to each; the reason is the evidence)

| Category | Collected? | Why |
|---|---|---|
| Contact info | No | Contacts are read on device to answer a question; never transmitted to the developer. |
| Health & fitness | No | HealthKit reads stay on device (and in the user's own host session only if they connected one). |
| Financial info | No | No purchases in 1.0 (the monetization gate is dormant); if an IAP ships later, StoreKit handles it and Apple, not the developer, holds the record. |
| Location | No | Used for the weather lookup on device; not stored, not transmitted to the developer. |
| Sensitive info | No | — |
| Contacts (list) | No | — |
| User content (messages, photos, audio) | No | Stored on device; sent only to the user's own server if they connect one, or to Apple PCC if they enable it. |
| Browsing / search history | No | — |
| Identifiers | No | No advertising/vendor identifier is read; no account. The installation id is local only. |
| Purchases | No | — |
| Usage data / diagnostics | No | No analytics or crash reporting SDK; os_log stays on the device. |
| Tracking | No | `NSPrivacyTracking = false`, no tracking domains. |

## Privacy policy URL

`https://<the docs/ Pages root>/privacy.html` — republished 2026-09-06 with the deletion/Keychain sentence corrected (#433) and the tap-to-load image sentence (#429).
