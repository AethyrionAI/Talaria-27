# #224 sitting brief — eight rulings, one page

**Written 2026-08-10 per Owen's ruling ("own sitting; Claude preps the brief").
The design of record is `design/APPROVAL_MODES_PROPOSAL-2026-08-07.md` — this
is its ballot, not its replacement. Answer with numbers: "approved" = all
eight as recommended; otherwise name the ones you flip.**

## The constraints, baked in so the sitting is rulings, not research

- **The app can DISPLAY and HONOR the host's approval mode, never SET it** —
  `approvals.mode` is dashboard-plane config (`:9119`); no `/api/config`
  exists on `:8642` (re-verified 2026-08-09, 37-route table).
- **Answering HOST approvals is DONE and out of scope here** — #304 shipped it
  (device-proven 08-09: four-choice card, deny, Stop-resolves-as-deny). This
  sitting governs **OUR on-device confirm gate only.**
- **Your hosts today:** OJAMD `approvals.mode: off`, `cron_mode: deny` (cron
  side-effects deny silently — worth knowing, not deciding).
- **Since the proposal was written:** #297's capability A/B **missed its bar
  (7/20 vs ≥18/20)** — one more entry in the #200-series record that the
  on-device model mis-assesses intent. It sharpens Q5's recommendation.

## The eight, as cards

| # | Question | Rec | The deciding fact | What flips it |
|---|---|---|---|---|
| 1 | Build at all, or shelve with the design attached? | **Phase 0 now, hold 1–3** | Phase 0 is a Manual-card improvement that stands alone and is the precondition for everything else — free even if modes never ship | You wanting fewer prompts *today* → open Phase 1 too |
| 2 | Global or per-profile? | **Global (`UserSettings`)** | The gate governs THIS PHONE's writes — identical across hosts, and it must exist with no host at all | A real per-host trust difference you feel in use |
| 3 | Does "Off" ship? | **Yes, with the floor** | #233's AM/PM catch happened ON a card — an unfloored Off would have silently created the wrong-time reminder | No floor ⇒ the answer flips to NO outright |
| 4 | Floor behaviour — refuse, or card? | **Refuse** | Mirrors Hermes's hardline blocklist (no prompt, explanatory error, nothing runs); carding would make Off secretly identical to Smart | Wanting "Off but ask on the scary ones" — then it's Smart, name it so |
| 5 | Smart = deterministic rules, or not at all? | **Rules or nothing — never the model** | The #200-series record, now plus #297's 7/20 miss. The ~3B model does not go on the safety path | Nothing should flip this one |
| 6 | Home: Privacy screen, between Location and App Lock? | **Yes** | There is no chat-settings surface today; creating one for a single control is worse | You wanting it beside the composer anyway |
| 7 | Transcript receipt for auto-approved actions, or os_log only? | **Defer** | Whether silent creates feel unaccountable is only knowable after a week of living with 1–2 | Decided by use, not by this sitting |
| 8 | Run the 30-sec `/approvals smart` slash probe? | **Not now** | The code says no, your host runs `off`, and #304 already delivered the half that mattered | Idle curiosity — it stays cheap if you ever want it |

## What happens after the ballot

"Approved" ⇒ Phase 0 gets a dispatch (OPUS-tier: card improvement + the mode
scaffold behind it, bars pre-registered in #224). Any flip ⇒ recorded in the
entry as a dated ruling first, same as the 08-09 pass. Phases 1–3 stay
un-dispatched until you ask for fewer prompts in so many words.
