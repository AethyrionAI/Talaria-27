# FABLE T27-126 — Daily briefing (app half)

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-126-*`
**Dispatch date:** 2026-07-17 · **Tracks:** OPEN_ITEMS #126 (new) · **Size:** one PR, medium
**Baseline:** 755/62 · **Toolchain:** Xcode-beta3.

## The feature (connected-tier centerpiece)

Every morning, Hermes (host-side cron — cron sessions already run and are
visible on the wire; see the #25 probe's `cron_*` sessions) synthesizes health
trends + calendar/reminders + open threads into a briefing, delivered to the
phone. **This lane builds the APP half only.** The host half (the cron job +
prompt) is Owen's config on the Hermes host — the dispatch defines the
CONTRACT so both halves meet.

## The contract (the spec's core deliverable — implement exactly)

The briefing arrives as an inbox item via the existing connector→relay→push
path, `kind: "notification"` (MUST be within the app enum:
alert/approval/notification/reminder/suggestion — house rule), with a payload
body the app can render richly:
- `title` ("Morning briefing — Thu Jul 17")
- `body` — markdown. May include `chart` fences (#100's parser renders them —
  dormant Path A wakes up here, scoped to briefings, exactly as designed).
- optional `speakable` — a short plain-text version for read-aloud.
Unknown/missing fields → render what exists (tolerant, #58 lesson). The PR
body must include a copy-pasteable JSON example of the payload for Owen's
cron prompt.

## The build

1. Briefing detail view: tapping the inbox row opens a full-screen markdown
   render through the EXISTING `MarkdownContentView` pipeline (charts render
   free). Do not fork a renderer.
2. Read-aloud affordance on the detail view: speak `speakable` (fallback: the
   body stripped of fences) through the EXISTING `SpeechOutputService` chat
   instance — **audio-session house law applies: it manages the session only
   via its `managesAudioSession` gate; touch nothing about #106's ownership.**
3. Widget: a small/medium `TalariaWidgets` entry showing the latest briefing's
   title + first line, deep-linking to the detail view (hermes:// route —
   scheme exists, #77). Data via the app group store the widgets already use
   (`SharedWidgetDataStore` — extend, don't parallel).
4. Recognition: briefing items identified by a `category: "briefing"` field in
   the payload (absent → it's a normal notification; nothing breaks).

## Decisions embedded (Owen — answer in PR review, defaults stand otherwise)

- Delivery time is host-side cron config, not app code. Default assumption:
  one briefing/day; the widget shows the LATEST regardless.
- Notification tap → detail view directly (default) vs inbox list first.

## Tests

Payload decode tolerance matrix; briefing-recognition predicate; widget
snapshot data mapping. Speech/render paths ride existing suites.

## Constraints & acceptance

- No new services on the voice/audio side; no connector/relay changes (the
  path exists); regen on file add; suite ≥ 755/62.
- Device check (PR body): Owen sends a hand-crafted briefing payload through
  the connector tool → push arrives → inbox row → detail renders markdown +
  an inline chart → read-aloud speaks → widget shows it. THEN he wires the
  real cron using the JSON example.
