# Plan — finishing `OPEN_ITEMS.md`

**Written 2026-08-01**, after two Hermes/Kimi audits took the closed count 88 → 136.
This is the sequencing plan for what remains. **Owen set the two decisions that
shape it** (below); everything else is ordering.

**This is a plan, not a queue.** The device queue lives in
`DEVICE-PASS-RUNNING-LIST.md` and is referenced here, never duplicated — a check
that lives in two places drifts.

---

## The two decisions that shape this plan

### 1. The App Store gate goes LAST — Owen, 2026-08-01

**And the reason is better than "it can wait": submission prep is perishable.**
Provisioning profiles, screenshots, review notes, and App Privacy answers all
describe *the app as built*. Every one of them is invalidated by the work in
Phases 1–6. Doing them early means doing them twice.

> I had earlier advised starting #166 immediately "because it has lead time."
> That was wrong as an ordering rule. **The carve-out is narrow and worth naming:**
> the items whose latency is *external* rather than app-shaped — a public
> privacy-policy URL, and creating the App Store Connect account/product records —
> depend on third parties, not on the app, so they can be done at any point without
> being invalidated. Everything else in Phase 7 genuinely belongs at the end.

### 2. #166c is much smaller than it was filed — Owen, 2026-08-01

> *"A reviewer need not join a tailnet. They're testing the local brain.
> Everything else is extra."*

**This is right, and it is defensible on precedent.** Self-hosted-server clients
ship on the App Store routinely without handing reviewers a server — the reviewer
evaluates the app, not the user's infrastructure. Talaria's on-device mode is a
**fully working app with zero setup**, which #166 itself already identified as
"our saving grace, and it's a big one."

**It holds under one condition, verified today:** `MonetizationConfiguration.isEnabled`
is `false` (`MonetizationGate.swift:29`) — the gate ships **dormant**, so there is
**no purchasable feature** at launch. A paid tier the reviewer cannot exercise
*would* be a real 2.1 problem. **So the day "Connected" becomes purchasable, the
reviewer-reachable-host question comes back.** Until then it does not exist.

**Net effect:** #166c drops from "launch requires a public review host" to
"a review-notes framing task." Phase 7 gets meaningfully cheaper.

---

## Phase 0 — Make the board true · **[SOLO, NO PHONE, DO FIRST]**

**Every estimate below depends on a number we do not actually have.** 94 items read
as open. A significant fraction are not work.

**Confirmed stale already (found while writing this plan, in ~5 minutes):**

| # | header says | reality |
|---|---|---|
| **#162** | "156a Tasks lane BUILT on branch `claude/t27-156a-tasks-cron`" | shipped — `Talaria/Features/Tasks/` (5 files), reachable at `ContentView.swift:246` |
| **#163** | "156b Skills lane BUILT on branch" | shipped — `Talaria/Features/Skills/`, `ContentView.swift:250` |
| **#165** | "156d Insights lane BUILT on branch" | shipped — `Talaria/Features/Insights/`, `ContentView.swift:252` |

**Not-actually-work, to be sorted and marked:**

- **📝 notes / decisions-of-record (~9):** #3, #6, #7, #83, #90, #101, #109, #155,
  and #8. These are records, not tasks. Several read as open purely because 📝 has
  no "closed" form.
- **💤 dormant (2):** #4, #55.
- **❌ cut / dropped (3):** #125, #126, and **#161, which says outright
  "NOT VIABLE, recommend closing"** — a close that was recommended and never done.
- **✨ merged features to re-check (5):** #112, #121, #122, #123, #124 — all say
  MERGED in their headers. Verify whether anything is genuinely owed.

**Deliverable:** the real backlog number, and a board where an open item means
open. **Cost: a few hours, no phone.** **Do it first** — sequencing 94 items when
~20 are phantom produces a plan about the wrong project.

> **Why this keeps happening, stated once:** every one of these was true when
> written. The failure is never the writing, it is that the top of an entry reads
> as its summary and nobody scrolls to the correction. Six were found today alone.
> Phase 0 is not cleanup, it is measurement.

---

## Phase 1 — Crashes and lockups · **[HIGHEST USER-FACING SEVERITY]**

Three items where the app becomes unusable. Nothing else on the board competes.

| # | what | state |
|---|---|---|
| **#147** | Tapping an inbox-alert notification **CRASHES the app** | Reopened 2026-07-25 — the 2026-07-21 "fix" was **inert for four days** (`nonisolated` opted the method back out of `@MainActor`). Real fix is on `claude/opus-t27-notifications-e2e-upxqau`. **Closes only on a device cold-launch tap** — the mis-verified case last time |
| **#145** | App **hard-locks** if opened during a gateway outage, and does not recover when the host returns — **phone restart** | The worst failure mode on the board: it survives the condition that caused it |
| **#193** | `confirmationDialog`'s **Cancel button does not render** on iOS 27 | An OS regression we have to work around; blocks every destructive-action escape hatch |

**#147 and #193 have device checks already queued in §F1.** #145 needs a
root-cause lane of its own.

---

## Phase 2 — The device-verification backlog · **[OWEN + PHONE]**

**Runs against `DEVICE-PASS-RUNNING-LIST.md`. Do not restate checks here.**

The single largest category on the board is *"merged, device verification owed."*
It is also the cheapest to clear — most of it is a handful of sittings, not
engineering.

**Order is already set in that document:**

1. **§C5 — the battery-run rescue. A RACE.** Two minutes, and it degrades every
   time a battery runs or the app is reinstalled.
2. **§A2b** — #221's brain-governs-voice A/B (verifies a spend + privacy fix).
3. **§A1b** — A1 re-run with the engine pinned. **Needs a second person to call
   you** — the prerequisite most likely to end a sitting early.
4. **A2's overnight half** — background the app before bed. Free.
5. **§F1–§F6** — the absorbed backlog, grouped by setup state so one state serves
   many checks. Includes Phase 1's #147 and #193.
6. **§C1–C4** — measurement items, foldable into any sitting.

**Run F3 (fresh install) LAST in any sitting** — it deletes the app.

---

## Phase 3 — "On device means on device"

**Owen's rule, 2026-08-01:** *"on device should signify everything on device.
Local. When hermes is selected, it switches to using hermes' resources."*

#221 applied this to voice after it was found billing OpenAI Realtime while the UI
said on-device. **The rule is bigger than that bug and the remaining items are the
same shape:**

| # | what |
|---|---|
| **#192** | The app **switches itself away** from on-device; the refused manual switch is the residue |
| **#191** | Chat header is not backend-aware — title and model pill keep reporting the Hermes session |
| **#200** + series | Armed path refuses appropriate device actions; the over-serving/latency residue |

**Anything added later that reaches off-device answers to this rule.** Worth a
single pass that audits every modality against it rather than fixing one at a time.

---

## Phase 4 — #180, the honesty umbrella

**#180 is filed as "the app hides its own degradation: four instances, one design
default."** It is a theme, not a bug, and it shapes how the app *feels* more than
any single item under it.

- **#173** — confident replies when the host cannot actually see attachments
- **#197** — a tool failure renders the RAW error, types and a memory address, into
  the transcript
- **#186** — permission accept-lists reject valid grants; the tool belt tells users
  to enable what they already enabled
- **#187** — gateway ignores `min_messages`; empty sessions reach the app

Treat as one design lane. Fixing them individually reproduces the default that
created them.

---

## Phase 5 — Infra, data integrity, and test honesty

**#144 belongs at the top of this phase and arguably higher:** test-harness runs
**enrol as LIVE devices on the Mac relay**, polluting the production DB with device
rows and push registrations. That corrupts the data every other measurement is read
from.

- **#133 / #143** — device-identity churn (one root cause, two symptoms: push
  registration idempotency defeated, Siri notifications ×5)
- **#188** — connector watchdog cannot distinguish relay-down from connector-down
- **#164 / #182 / #219** — three separate UI-test flakes. #164's own bar is *three
  consecutive green runs* and we have one.
- **#183** — "tests that pass without exercising what they name — three instances,
  one shape." **This one outranks the flakes:** a flaky test announces itself; a
  test that passes vacuously does not.

---

## Phase 6 — Feature completion

The long tail, roughly by value. Nothing here is a blocker; several are close to
done.

**Nearly finished / verification-shaped:** #56 (Ask Hermes sub-checks), #58 + #179
(Control Center — one check closes both), #61, #82, #116, #129, #137.

**Real lanes:** #34 (T6 Mac-hosted backend, ACTIVE), #93 (continuity fabric),
#148 (Hermes 0.19 impact), #156 arc (introspection surface — note #161 recommends
closing 156e), #78, #80, #81, #77, #75, #177.

**Decisions rather than code:** #99 (WKContentRuleList), #132 (host-side image
attachments), #170, #47's billing cap, #164's close-or-quarantine.

**Parked by choice:** #130 (Owen: keep as a reminder), #45 + #74 (CarPlay — gated
on an Apple entitlement we do not have), #149, #150 (post-launch).

---

## Phase 7 — App Store · **LAST, by decision**

**Everything here describes the app as built, which is why it goes after the app
is built.**

| # | what | who |
|---|---|---|
| **#166c** | Review-notes framing: on-device mode is the reviewable product; paired features are BYO-server extras. **Re-scoped 2026-08-01 — no public review host needed while monetization is inert** | Claude drafts, Owen approves |
| **#166e** | Portal pre-flight: bundle IDs for app + widgets + share extension, App Group across all three, aps-environment / HealthKit / Siri capabilities, automatic signing mints App Store profiles | Owen |
| **#166f** | Adopt hermex's runbook skeleton — Stop Conditions, Review Notes, Risk Register, Definition of Ready | Claude |
| **#127** | App Store Connect: product id **exactly** `org.aethyrion.talaria27.connected`, plus a sandbox tester | Owen |
| **#8** | TestFlight gate; **#90** DEVELOPMENT_TEAM placeholder cleanup | both |
| **#140** | README + GitHub Pages refresh — currently carries a stale wedge narrative and pre-freemium positioning | Claude |

**⚠️ Two things must be true in the review build:** the monetization gate stays
**inert with no dead purchase UI reachable** (2.3.1), and **#167's MagicDNS landmine
stays defused** — the shipped ATS exception keys a CIDR literal, which ATS never
matches, so plain-IP tailnet traffic works only because bare IPs are not policed.
**Point a host field at a MagicDNS name and it breaks.**

### The narrow carve-out — startable any time

**A public privacy-policy URL** (hermex's runbook calls it a hard stop condition)
and **creating the App Store Connect records**. Their latency is external, so they
are never invalidated by app work. Everything else in this phase waits.

---

## Sequencing summary

```
Phase 0  make the board true          solo, no phone        ← DO FIRST
Phase 1  crashes and lockups          #147 #145 #193
Phase 2  device verification          Owen + phone (§C5 is a race)
Phase 3  "on device means on device"  #192 #191 #200-series
Phase 4  #180 honesty umbrella        one design lane
Phase 5  infra + test honesty         #144 first, then #183
Phase 6  feature completion           the long tail
Phase 7  App Store                    LAST, by decision
```

**Phases 1 and 2 interleave naturally** — most of Phase 1 closes on a device check
that is already in Phase 2's queue.

**Phase 0 is the only one with a hard ordering claim.** Everything after it can be
resequenced by appetite; Phase 0 cannot, because it is what tells us how much of
the rest is real.
