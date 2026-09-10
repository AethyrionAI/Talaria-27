# Talaria 1.0 — Launch Runbook

**Tracker #443 · written 2026-09-10 · structure from #166f (hermex's runbook skeleton:
Definition of Ready → Stop Conditions → Steps → Known Risks).** Apple's iOS 27 public
launch is Monday 2026-09-14. That is Apple's date. Talaria submits when the Definition
of Ready is green and Owen presses the button; a week later is still a launch.

Two rules that make this calm: **nothing before "Submit for Review" is irreversible**,
and **an agent never types Owen's Apple ID, never uploads, never submits.** The steps
marked 🧑 are Owen's hands; every other step is done for him and reported back with
evidence.

## Definition of Ready (all must be true before 🧑 Submit)

| # | Ready when | State 2026-09-10 |
|---|---|---|
| R1 | Privacy manifests ×3, encryption flag, ATS scope | ✅ 166a/166b/166d |
| R2 | Distribution cert + App Store profiles, every entitlement validated at export | ✅ 166e (2026-09-06) |
| R3 | Privacy policy, in-app notices, weather attribution published/shipped | ✅ #433 #434 #435 |
| R4 | RC toolchain standard, gate green | ✅ #441 |
| R5 | iPhone-only, no CarPlay scene (Owen's rulings) in the built product, tests pinned | ✅ 443-A/B — PR #447 → `94f5f62a`, gate PASS on 24A434 |
| R6 | Store build exported under Xcode-RC from merged `main`, family + manifest verified inside the ipa | ✅ superseded by the UPLOAD: **build 3338** (main @ `e22c5cb5` — same app code as 3334, plus the script's upload mode) went to App Store Connect 2026-09-10 13:56 via `testflight-stage.sh upload`; the 3334 ipa was never uploaded and sits in `retired/` |
| R7 | Reviewer notes v2 read by Owen; the "model unavailable" sentence grounded (code path + unit test — a sim cannot present the state, #402) | 🔄 443-D grounded 2026-09-10; Owen's read owed |
| R8 | Listing copy decided; 6.9-inch screenshots captured | 🔄 443-E — listing DRAFTED (Owen decides); three simulator frames LANDED in `planning/reports/2026-09-10-launch/screenshots/` (chooser, fresh chat, hostless Settings — from the fixed Release build); the three on-device brain frames are Owen's phone, any evening (`compose-shots.py` pads them to 6.9-inch) |
| R9 | Support contact on the Pages index | ✅ PR #450 merged 2026-09-10 on Owen's read — `https://aethyrionai.github.io/Talaria-27/#support`, support@aethyrion.org (Cloudflare-routed); also the App Review contact email |
| R10 | App Store Connect record exists with App Privacy answered | ✅ 🧑 record "Talaria 27" ("Talaria" was taken); App Privacy, 6.5-inch screenshots, copy, category (Productivity / Utilities), age rating, review notes, contact all ENTERED by Owen 2026-09-10 afternoon (his word: "everything else I believe has been set") |
| R11 | Build uploaded, processed, installed from TestFlight on `whoGoesThere`, ten minutes of real use | 🔄 build **3338 INSTALLED from TestFlight (Internal) ~14:40** — an in-place upgrade over the dev build (same bundle id; pairing + settings persist, and the Keychain rehydrates them even after a delete, #433), so the check runs as a PAIRED user; that still exercises the store-signed entitlements at runtime, which is the point. The ten minutes (chat, Talk, a reminder, Health widget, share a PDF, weather) are this evening |

## Stop conditions (do NOT submit if any is true)

- The gate on `main` HEAD is not green under the RC (a green branch gate is not a green
  `main` gate — the 2026-09-05 integration rule).
- The exported ipa's `DistributionSummary.plist` shows a device family other than iPhone,
  or a CarPlay scene in its Info.plist.
- The TestFlight install on the phone fails to launch, or the on-device brain does not
  answer a chat on the RC build (the first non-dev-signed runtime check of the
  entitlements — PCC, HealthKit, WeatherKit, App Groups).
- The reviewer notes still contain the ⚠️ VERIFY marker.
- The privacy policy URL or support URL 404s.

## Steps, in order

**Agent (this week, no device needed)**
1. ✅ Merged #443's lane (PR #447 → `94f5f62a`); `main`'s tree proven identical to the gated branch tree (same tree hash), so the branch gate IS the `main` gate for this HEAD.
2. ✅ `scripts/mac/testflight-stage.sh` under Xcode-RC → **`~/.talaria-ota/testflight/Talaria27-store-3334.ipa`** (main @ `a76b0440`, build 3334, 1.0.0, minOS 27.0 — includes #444's hostless honesty, #445's three rulings (Private Cloud off on a fresh install, no Developer row in Release, "Message Talaria…") and #447's host-probe honesty for the connected tier); `UIDeviceFamily [1]` and the empty scene-configuration dict verified inside the ipa; both appexes present. Every earlier ipa lives in `retired/` — the one loose ipa in the folder is the one to upload.
3. ~~Verify the model-unavailable path on a simulator~~ — DONE differently (R7): a sim reports the model available and fails at generation (#402), so it cannot show the unavailable copy; the sentence in `reviewer-notes-v2.md` is grounded in `LocalChatBackend.unavailabilityMessage(for:)` and its unit test instead. Owen can see it live by switching Apple Intelligence off for thirty seconds; optional.
4. Capture the five 6.9-inch screenshots on CC-lane-1 with the Mac host supplying chat content; land them in `planning/reports/2026-09-10-launch/screenshots/` (R8).
5. Add a Support section with a contact address to `docs/index.html` (R9) — the address is Owen's to choose.

**🧑 Owen (about an hour total, any evening)**
6. Read and edit: `reviewer-notes-v2.md`, `app-store-listing-draft.md`, the App Privacy answers. Decide the support email, copyright line, territories.
7. App Store Connect → My Apps → **+ New App**: iOS, name `Talaria`, primary language English (U.S.), bundle id `org.aethyrion.talaria27`, SKU (any), full access. (R10)
8. App Privacy → **Data Not Collected** → publish.
9. App Information / Pricing: category Productivity, price Free, availability.
10. Version 1.0.0 page: paste description, subtitle, keywords, promotional text, support + privacy URLs, screenshots; age rating questionnaire (expect 4+); App Review Information → paste the notes; contact phone/email; "sign-in required: No".
11. ✅ **UPLOADED 2026-09-10 13:56 — build 3338** (main @ `e22c5cb5`), by Owen running `scripts/mac/testflight-stage.sh upload` in a Terminal on the Mac: Xcode's `destination=upload` export delivered it under the signed-in Apple ID, no credential typed (`Progress 100%: Upload succeeded.` · `Uploaded Talaria` · `** EXPORT SUCCEEDED **`). One warning, not blocking: *Upload Symbols Failed — no dSYM for WebRTC.framework* (the vendor binary ships none; app symbols uploaded; WebRTC frames in a crash report would be unsymbolicated). Transporter was never needed. Wait for "processing" to finish (minutes to an hour). Select the build on the version page. Export compliance should not prompt (166d); if it does: exempt only.
12. TestFlight → internal testing → add yourself → install on `whoGoesThere` → ten minutes of real use: chat, Talk, a reminder, the Health widget, share a PDF. (R11)
13. **Submit for Review.** Then close the laptop. Review typically answers within 24–48 h; a rejection is a message, not a verdict — it comes back here as a tracker item.

**Agent, after submission**
14. Watch for App Review messages Owen forwards; if the host tier is requested, run `review-host-on-request.md` end to end on a spare session first.
15. On approval, Owen chooses "manually release" (recommended for 1.0) and presses release when he likes; the Pages index gets the App Store link the same day.

## Known-risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Reviewer tests on a phone without Apple Intelligence, or with it off | medium | Notes lead with the requirement; first-launch copy verified (R7); the description states it. |
| Reviewer asks to see the Connect Host tier (guideline 2.1 demo) | low–medium | Notes offer a temporary host on request; recipe rehearsed before the reply. |
| iPhone build on an iPad in compatibility mode looks odd | low | Expected behaviour for iPhone-only apps; the RC fixed the compatibility-mode orientation bugs (178573319 family). |
| HealthKit write-description present while the app never writes | low | Notes explain it; the framework requires the string. |
| Age-rating questionnaire asks about AI/chat content | medium | Answer truthfully (assistant with Apple's on-device guardrails); record the answer in the listing draft. |
| A TestFlight build behaves differently from the dev-signed OTA build (entitlements) | low | R11 is exactly this check; PCC's grant is already validated at export. |
| Name "Talaria" taken on the store | unknown | Fallback name in the listing draft. |

## Withdrawing or fixing

A submitted build can be **removed from review** at any time from the version page. A
rejection arrives with a message thread; reply there or resubmit a new build. Neither
affects anything on the phone or in the repo.
