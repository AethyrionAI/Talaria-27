# OPUS-T27-200B-DESTALL-BATTERY — treat the reminder list-stall as measured cells

**Executor:** local Claude Code. **Drafted 2026-07-28 evening from the FILED #200 table
(action battery n=20, build `4d419a9`), routed by Owen ("keep going for the next diag
lane") after PR #165 merged (`6f5d8cf`).** Branch `claude/t27-200b-destall-battery`.

## Why

The #200 measurement is unambiguous: **remind 0/20 creates**, with 15/20 trials
interrogating the OPTIONAL `list` (± due) field ("which list should this go in?") and
5/20 substituting `readReminders`; the single-field alarm tool runs 19/20. The
confirmation gate blocked nothing — the disease is pre-tool-selection field anxiety.
Per the #196 remfix precedent, treatments enter as MEASURED CELLS: nothing ships to
production until a battery verdict says which text moves 0/20 and at what collateral
cost.

## The cells (action battery gains a cell dimension)

1. `armed` — production control, byte-identical belt.
2. `armed-guidefix` — `ReminderCreateTool` COPY (same name "createReminder", same call
   semantics) with de-stalled `@Guide` texts: `list` → "Reminders list name. Empty is
   correct when the user didn't name one — the default list is used; never ask which
   list." `due` → same de-stall clause for date detail. (`@Guide` is a macro, so this
   is a copy STRUCT — the description-var seam can't reach it.)
3. `armed-toolfix` — description-only seam (the remfix mechanism, `var description`):
   production text + "Create it immediately with the details given; missing fields
   default — never ask a clarifying question first."
4. `armed-bothfix` — both. Separately and combined, per the #196 battery-2 lesson: an
   interaction effect can't hide behind two individually-clean cells.

## Protocol

- Prompt set gains a GRAB CANARY: `remind` / `alarm` / `calendar` (unchanged) plus
  `haiku` = "Write a haiku about sledding" — the de-stall texts push toward immediate
  creation, so the #196 grab disease is the collateral risk to measure, now under
  auto-ACCEPT (a grab CREATES a real marked reminder and the reap deletes it; the
  confirm capture makes grabs countable).
- 4 cells × 4 prompts × n=10 = 160 trials (~35–50 min). n=10 per the #196 power lesson:
  movement from 0/20 upward is unmissable at n=10; a composition verdict between
  winning cells can re-run at n=20 if two cells land close.
- Auto-accept armed, permissions granted, reap before DONE — the #200 instrument
  as-shipped (crash-hardened, sealed records, confirm capture).
- Classification columns unchanged + a `grab` column for the haiku cell (createReminder
  fired on a words-only prompt = grab, accepted-and-reaped).

## Pins and rules

- Tool-description strings pinned by test (remfix pattern). `@Guide` texts are not
  runtime-readable — comment-pinned in the copy struct, device-verified by the battery
  itself.
- The copy struct must reuse `DeviceActionParsing` / the same confirmation staging so
  the ONLY delta is text (structural-identity discipline).
- House rules: file-scoped commits, merge commits only, OPEN_ITEMS notes separate,
  suite green with stated count, evidence scope + build ID in the PR, classification
  from RAW TEXT with rates, ERROR trials excluded and listed.
- **Nothing promotes in this lane without the battery verdict.** The winning text (if
  any) promotes in a follow-up commit exactly like #163 promoted armed-routed — with
  its own pins.
- Deploy via `ota-stage.sh claude/t27-200b-destall-battery Debug`; capture via the
  results page export.

## Out of scope

Calendar contact-fixation de-fix (next lane after this verdict), the multi-turn
offer→denial absorbing-state instrument (justified, queued), #197 raw-error rendering,
#199 fabrication (gets its denominators from these same runs for free).
