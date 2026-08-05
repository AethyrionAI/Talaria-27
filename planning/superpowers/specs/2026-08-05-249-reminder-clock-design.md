# #249 Reminder clock guards — design (approved 2026-08-05)

**Problem (proven by the discriminator run, OPEN_ITEMS #249):** "remind me at 8"
asked ~10 PM arrives at `createReminder` as bare local `2026-08-05T08:00` — the
model half-day-defaults an evening ask to next-morning 08:00, one hour outside
#233's wee-hour net (hours 0–6). Two of Owen's three cards were additionally due
**in the past** (today 8:00 AM staged at 9:31 PM) and nothing checks a parsed
due against now. The app renders faithfully; the staged hour is still not the
hour the user said.

**Owen's routing (2026-08-05, AskUserQuestion):** ship **both guards** —
the past-due guard (deterministic backstop) and the evening-clock ask.

## Design — two guards, both #233-shaped (bounce once per conversation, latched
re-call stages with a caution row; ordinary tool OUTPUT, never a throw (#197);
an executed call, not a governor refusal (#232's counter must not move))

### Predicates (`DeviceActionParsing`, pure, nonisolated)

- `isPastDue(_ date: Date, now: Date) -> Bool` — `date < now - 300`. The
  5-minute grace absorbs staging latency and "right now" asks; the observed
  defect shapes were hours stale.
- `isNextMorning(_ date: Date, askedAt now: Date) -> Bool` — ask-hour ≥ 17
  AND due on the next calendar day of `now` AND due hour in 7…11. Hours 0–6
  stay #233's wee-hour net; 12+ next-day is not the half-day-default shape.

### Latches (`ToolEventRelay`, conversation-scoped like `earlyMorningAskIssued`)

- `pastDueAskIssued` / `claimPastDueAsk()`
- `eveningClockAskIssued` / `claimEveningClockAsk()`
- Both reset ONLY in `endConversationToolState()` — the ask/answer round-trip
  spans turns, exactly like #233.

### `performCreate` (order matters; new param `now: Date = Date()` so tests
inject the clock — existing call sites unchanged via the default)

1. Parse due (instrument line stays).
2. **Past-due guard** (before wee-hour: a stale wee-hour due is first a stale
   due): bounce text, 233-E-hardened (leads with the negative, NO formatted
   date to mine): *"No reminder was created. The requested due time has
   already passed. Ask the user what future time they meant, then create the
   reminder with the time they confirm."*
3. #233 wee-hour ask (unchanged).
4. **Evening-clock ask:** *"No reminder was created. The request was made in
   the evening and the due time landed the next morning, which may be a
   misread evening time. Ask the user which time of day they meant, then
   create the reminder with the time they confirm."*
5. Stage the card with `caution: dueCaution(for: parsedDue, now: now)`.

### Caution row (`dueCaution(for:now:)`, first match wins)

- past due → `"IN THE PAST — \(displayDate(date))"` (date matters: could be
  yesterday)
- wee-hour → existing `earlyMorningCaution` string (function kept; #233 pin)
- next-morning → `"NEXT MORNING — \(timeOnly(date))"`
- else nil — normal cards render byte-identical to today.

### Out of scope

- Card EDITS are the user's own values — no re-guard (matches #233's trust
  model).
- @Guide text changes — #196/#200 discipline, battery-gated only.
- Widening the wee-hour window — relitigates #233's deliberate 0–6 choice.

## Test-rot hazard the guard surfaces (fix in the same lane)

Existing #233 tests hardcode dues like `2026-08-05T04:00`/`T16:00` — already
past at today's run time; the past-due guard would bounce them. Bounce-path
tests move to direct `performCreate` calls with explicit `now` anchored to the
due's day; `tool.call` wiring tests build dues from tomorrow's date at 16:00
(future at any run time, outside all three windows).

## Bars — pre-registered in OPEN_ITEMS #249 (249-A..E) before the run.
