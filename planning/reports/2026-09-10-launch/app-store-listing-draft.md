# App Store listing — DRAFT for Owen's decisions (2026-09-10, #443, bar 443-E)

Everything here is a proposal. Character limits are Apple's; counts are given so a cut
is a choice, not a surprise. Fields Owen must fill from his own account are marked
**[OWEN]**. Nothing is entered into App Store Connect by an agent.

## Identity

| Field | Proposal | Notes |
|---|---|---|
| Name (≤30) | **Talaria** | Availability is checked at record creation — if taken, `Talaria — Private Assistant` (28). |
| Subtitle (≤30) | **Private assistant, on-device** | 29 chars. Alternative: `Your assistant, on your phone`. |
| Bundle ID | `org.aethyrion.talaria27` | Fixed by the profiles already minted. |
| SKU **[OWEN]** | `talaria-ios-1` | Any unique string; never shown. |
| Primary language | English (U.S.) | |
| Primary category | Productivity | |
| Secondary category | Utilities | Optional. |
| Price | Free | No IAP in 1.0 (the monetization gate is dormant). |
| Availability **[OWEN]** | All territories | Apple Intelligence's language/region limits gate real usefulness; the description says so. |
| Copyright **[OWEN]** | `2026 <legal name or Aethyrion>` | |
| Version | 1.0.0 | `MARKETING_VERSION` in `project.yml`. |
| Support URL | `https://aethyrionai.github.io/Talaria-27/#support` | The Support section (PR #450) — email, issue tracker, privacy, plugin. |
| Support email | `support@aethyrion.org` | Owen, 2026-09-10: routed through Cloudflare to a personal address. Also the App Review contact email in App Store Connect. |
| Marketing URL | same as support | Optional. |
| Privacy policy URL | `https://aethyrionai.github.io/Talaria-27/privacy.html` | Published, corrected 2026-09-06 (#433). |

## Promotional text (≤170; editable without a new build)

> A private assistant that runs on your iPhone with Apple's on-device model. Ask about
> your day, your health, the weather — nothing leaves the phone unless you say so.

(169 chars.)

## Description (≤4000)

> Talaria is a private assistant that lives on your iPhone. It uses Apple's on-device
> model — the same one behind Apple Intelligence — so what you ask stays on your phone.
> There is no account, no server of ours, and nothing to set up.
>
> ASK ABOUT YOUR DAY
> What's on the calendar, what's due, who to call. Talaria reads your calendar,
> reminders, and contacts to answer, and shows you a card to confirm before it writes
> anything.
>
> TALK, DON'T TYPE
> Hold a spoken conversation with Talk. Speech is recognised on the device.
>
> KNOW YOUR NUMBERS
> Steps, sleep, heart rate, calories — asked in plain language, answered from Health.
> The Health widget keeps the basics on your Home Screen.
>
> WEATHER, PLACES, PHOTOS
> Weather from Apple Weather for wherever you are. Share a photo or a PDF from another
> app and ask about it.
>
> YOUR DATA STAYS YOURS
> Talaria collects nothing. No analytics, no tracking, no cloud of ours. The brain is
> on-device; Apple's Private Cloud Compute is off until you turn it on. An optional App
> Lock uses Face ID.
>
> FOR PEOPLE WHO RUN THEIR OWN SERVER
> If you self-host a Hermes agent, Talaria can connect to it — over your own network,
> to your own machine — and use it as a second brain with your tools, tasks, and
> skills. Entirely optional; the app is complete without it.
>
> REQUIREMENTS
> An iPhone that supports Apple Intelligence, with Apple Intelligence turned on, running
> iOS 27. Apple Intelligence language and region availability applies.

(≈1,750 chars.) The "Hermes" paragraph is the only place the host tier appears; it is
worded as a feature for self-hosters, never as a requirement — consistent with the
reviewer notes and the naming ruling (Hermes = the host, Talaria = the app).

## Keywords (≤100 chars, comma-separated, no spaces after commas)

`assistant,private,on-device,ai,voice,reminders,calendar,health,weather,widgets,self-hosted`

(93 chars.) Do not repeat words already in the name or subtitle.

## What's New (1.0)

> Initial release.

## Age rating **[OWEN answers the live questionnaire]**

Expected: **4+**. Talaria has no user-generated public content, no web browser, no
gambling, no contests, no medical advice claims (health numbers are read back, not
interpreted clinically), no unrestricted web access. If the current questionnaire asks
about AI-generated content or chat features, answer truthfully that the app is an
assistant producing model-generated text with Apple's on-device safety guardrails; note
the answer here afterwards so the next submission is consistent.

## Screenshots (bar 443-E — agent captures; Owen picks)

iPhone-only build ⇒ one required set: **6.9-inch (1320 × 2868 portrait)**; Apple scales
it for smaller displays. Optional: 6.5-inch. The `docs/img` set (780 × 1646, July) is
the wrong size and predates the naming sweep — not reused. Proposed five frames, in
order: (1) onboarding with the on-device brain selected, (2) a chat answer about the
day with a confirmation card, (3) Talk mid-conversation, (4) a health/weather answer
with the Apple Weather attribution visible, (5) Settings → Connect Host with nothing
paired, to show the tier is optional.

**Who captures what (decided 2026-09-10, after the sim facts landed):** the simulator
cannot generate on either FM tier (#402, re-measured on the RC runtime), so frames that
show the on-device brain answering — (2), (3), (4) — are only honest from the phone.
Owen takes those three on `whoGoesThere` in an evening (Settings → screenshot; the
app's Deep Field theme, a real calendar question, Talk mid-sentence, a weather or
steps answer with the Apple Weather line visible). The agent captures (1) and (5) on
the `CC-shots-17ProMax` simulator (created 2026-09-10 for exactly this; 6.9-inch,
1320 × 2868 native) and composes all five onto 6.9-inch canvases — a phone screenshot
from a smaller display is placed on the canvas at native scale with the app's
background colour filling the margin, which Apple accepts (the image must show the app
as it runs; framing and margins are fine, mock-ups of features that do not exist are
not). Output lands in `planning/reports/2026-09-10-launch/screenshots/` as
`01`…`05.png` plus the raw captures.

## App Privacy

Unchanged from `../2026-09-06-submission/app-privacy-answers-draft.md`: **"Data Not
Collected."** The three manifests still declare no collected types (re-read 2026-09-10).

## Export compliance

`ITSAppUsesNonExemptEncryption = false` is in the Info.plist (166d), so App Store Connect
should not ask per upload. If it does, the answer is "uses only exempt encryption
(HTTPS / standard system APIs)".
