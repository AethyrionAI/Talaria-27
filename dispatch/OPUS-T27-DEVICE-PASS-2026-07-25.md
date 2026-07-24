# OPUS-T27 DEVICE PASS — 2026-07-25

**Build:** off `main` at or after merge `b7e47bd`. **Record the SHA in every finding.**
**Device:** whoGoesThere, iOS 27 b4. **Driver:** Owen. **Support:** Claude, on the Mac.
**Items:** #133 #58 #179 #151 #152 #153 #172 #128 #129 #124 #123 #112 #81 #116 #61 #117 #137

---

## How this document is organised, and why it changed

An earlier version of this pass was written from the code's point of view — it asked Owen to check
"the launch log" without saying where that is, and to "tap the control" when a fresh install had
already wiped the controls out of Control Center. It failed on contact. This version fixes three
things:

1. **Grouped by SETUP STATE, not by item number.** The expensive part of this pass is toggling
   pairing on and off, not the checks. Worked top to bottom, you change state three times total.
2. **Every check names the exact tap path and the exact on-screen label**, taken from source.
3. **Checks that need a log or a database are not Owen's.** They were never a human-eyeball test.
   Those are marked **[CLAUDE CAPTURES]** and are run from the Mac with the phone attached.

**If a check cannot be performed as written, that is a defect in THIS DOCUMENT.** Say so and move
on; do not improvise a substitute check and record its result as a pass.

---

## Preflight

- Build and install off `main` (≥ `b7e47bd`). This image contains Bundle A, Bundle B, #164's fix,
  the #58 control handoff, and the settings work.
- Both profiles paired (OJAMD + Mac Mini) unless a group says otherwise.
- **Claude, before Owen starts:** confirm the relay `:8000`, gateway `:8642`, shim `:8765` and the
  connector are up on both hosts. Check port OWNER, not service name — the OJAMD gateway is a user
  `pythonw` process, not an NSSM service.
- **Console setup for the [CLAUDE CAPTURES] checks:** phone attached by cable, `idevicesyslog`
  running on the Mac, filtered to the app's subsystem. Claude drives this; Owen just taps.

**Record for each check: PASS / FAIL / PARTIAL / UNRUNNABLE.** PARTIAL and UNRUNNABLE are real
outcomes. Do not round a partial up.

---

# GROUP A — both hosts paired, no special setup

Everything here runs back-to-back in one sitting.

## A1 · #58 + #179 — Control Center

**SETUP — MANDATORY, this is why the last attempt failed.** A fresh install removes the controls
from Control Center. Before testing: pull down Control Center → **＋** (top left) → **Add a
control** → search **Talaria** → add both **Open Talaria** and **Talk to Hermes**. Then close
Control Center.

**DO:** force-quit Talaria. Wait ~30s so the widget extension goes cold. Open Control Center, tap
**Open Talaria** twice, a few seconds apart. Then repeat with **Talk to Hermes**.

- **PASS:** Talaria opens on the **Chat** tab. Talk to Hermes opens the **voice overlay**.
- **FAIL:** nothing happens on repeated taps, or it consistently lands somewhere else.
- **EXPECTED, NOT A FAIL:** the *first* tap on a cold extension opens the app to the **default
  screen** instead of the intended destination. That is #179's cold-start swallow combined with
  `openAppWhenRun`. Documented in #58. Tap again — the second tap is the real test.

**[CLAUDE CAPTURES]** the `AppIntents` / `chronod` lines for both taps, to confirm whether the
first-tap swallow still shows the 21 ms no-`PerformAction` signature.

## A2 · #151 — Test Connection

**PATH:** Settings → **Hermes Host**. The button reads **Test Connection** (it changes to
**Testing…** while running).

**DO:** tap it with the host up. Then stop the host (ask Claude) and tap it again.

- **PASS:** a spinner, then a verdict within about 5 seconds — a pass row with host + latency, or a
  fail row naming a reason (unreachable / auth rejected / wrong port).
- **FAIL:** no visible result at all, or it spins past ~5s — especially against a black-holed host.

## A3 · #152 — the pairing surface is named for what it does

**PATH:** Settings → **Hermes Host**. The button now reads **Pairing & Devices** (it used to read
"Pair Device"). Tap it.

- **PASS:** the screen title is **Pairing & Devices**; the add action inside reads **Pair New Device
  (QR)**; the screen leads with current pairing state rather than only offering to add.
- **FAIL:** the old "Pair Device" label anywhere on this path.
- **Do not re-test the QR flow itself** — unchanged by design.

## A4 · #153 — profile actions are findable, and delete confirms

**PATH:** Settings → **Server** (subtitle "Backend Profiles").

**DO:** on a profile card, look for a **visible menu button** — do not long-press first. Open it.
Then choose **Delete** on a NON-active, NON-sensor-destination profile.

- **PASS:** the menu button is visible without long-pressing; the same actions are still available
  by long-press; **Delete asks for confirmation** and names what is removed and that other profiles
  are untouched.
- **FAIL:** actions reachable only by long-press, or delete fires immediately with no confirm.
- **Expected:** deleting the ACTIVE profile or the SENSOR DESTINATION is refused with a reason.
  That is a house rule, not a bug.
- **Note:** **Forget Pairing** and **Delete** are different actions. Forget severs the credential;
  Delete removes the profile. Both should confirm.

## A5 · #172 — deliver picker return path

**PATH:** Tasks → open or create a task → the **DELIVER** field → tap **Custom…**

- **PASS:** a **USE LIST** control appears and returns you to the menu; anything typed survives the
  round trip as a marked **(custom)** row.
- **FAIL:** no way back to the list, or the typed value is lost crossing back.
- **THE CHECK MOST LIKELY TO BE SKIPPED — do it:** with **no host connected**, `USE LIST` must
  **NOT** appear. Offering a return to a list that cannot open is a second dead end. (Run this one
  in Group B, when you are already disconnected.)

## A6 · #128 + #129 — voice preview mid-session

**PATH:** start an **active voice session**, then Settings → **Voice & Talk** → audition several
voices → apply one.

- **PASS:** no crash; the session keeps running; the mic is still live afterward. Outside a session,
  previews play at full fidelity.
- **FAIL:** a crash (the original was an uncaught `AVAEGraphNode CreateRecordingTap` exception), or
  a session that dies silently.
- **ACCEPTED, NOT A FAIL (Owen, 2026-07-23):** on **native**-engine sessions, previewing mid-reply
  drops that reply's un-spoken audio tail — the transcript stays intact — and the next chunk cuts
  the preview short. On **realtime** (the primary case) previews play over the session cleanly.

## A7 · #124 — Face ID app lock

**PATH:** Settings → **Privacy** → the **App Lock** section. Turn it on.

Seven checks. Any unchecked box is a fail worth its own item.

- [ ] Background the app → reopen → the biometric prompt appears **over** content
- [ ] Fail or cancel twice → a retry button → the system passcode sheet unlocks it
- [ ] **The app switcher shows the obscured splash, NOT chat content** ← unit tests cannot see this
- [ ] Grace period: background <1 min → no prompt; >1 min → prompt
- [ ] Siri **"Ask Talaria27"** works while locked; tapping its result lands on the lock
- [ ] **Background with the Settings sheet open → reopen → the cover is ABOVE the sheet** ← ditto
- [ ] A push arriving while locked shows its banner, and the UI stays locked

## A8 · #123 — share extension

**DO, from other apps:**

- [ ] Safari → Share → Talaria → URL lands in the composer
- [ ] Photos → Share → Talaria → image chip
- [ ] Files → Share a PDF → file chip
- [ ] Two shares in quick succession → both land, **in order**
- [ ] **A ~25 MB video → a polite refusal IN THE SHARE SHEET** — not a crash, not silence ← the one
      that matters most
- [ ] Share while Talaria is force-quit → it lands on the next launch
- [ ] `hermes://ask` still works (separate seed slot; must not collide with shares)

## A9 · #112 — Comic Book adaptive theme

**PATH:** Settings → **Appearance & HUD** → theme picker → select **Comic Book**.

**DO:** leave Settings open and foregrounded, then toggle system Light/Dark (Control Center
brightness long-press, or ask Siri).

- **PASS:** it re-skins between **Villain Variant** (dark) and **Sunday Funnies** (light)
  **without a relaunch**.
- **YOUR VERDICT, NOT AUTO-FAILS — two known seams:** picker cards preview the presented-surface
  variant while a fixed theme forces the scheme; and a cold light-mode launch flashes the villain
  half for one frame before the mirror lands. Say whether either bothers you.
- Also spot-check the 13 new icons in the picker.

## A10 · #81 — lock-screen reply

**DO:** send a message that will take a while, lock the phone, wait for the completion push.
Long-press it → **Reply** → type → send.

- **PASS (your half):** the reply visibly lands in the right session, and the **next** completion
  push also offers Reply.
- **PASS (honest failures — silence in any of these is a FAIL):** expired relay watch TTL → a clear
  notice; wrong/expired API key → "Reply not sent"; replying while another run streams → a busy
  notice.

**[CLAUDE CAPTURES]** the #114 profile-aware half: the headless reply must post to the push's
**session birth profile**, not whichever profile is active at reply time. Verified against the
relay DB, not the screen.

## A11 · #116 — shim token auto-fill

**DO:** Settings → **Server** → forget the Mac pairing → re-pair via QR.

- **PASS:** the shim token fills in **by itself** within a few seconds — **zero manual paste** — and
  the probe's verdict matches reality.
- **FAIL:** any manual paste still required, or a probe reporting success against a dead shim.

**Claude:** restart relay + connector on the Mini before this. The OJAMD half rides the
`ojamd-deploy` rebase — Owen's manual gate, ask first.

## A12 · #133 — push registration idempotency · **[CLAUDE CAPTURES]**

**This is not a phone check.** It reads a log Owen cannot see on the device — the earlier attempt
failed for exactly this reason.

**Owen's part, ~20 seconds:** force-quit → cold launch → let it settle → background it once.
Claude reads the rest from Console.

- **PASS:** at most ONE registration line per profile (2 max), and exactly one background app-state
  report per backgrounding.
- **FAIL:** 3+ registration lines, or a doubled background report.
- **NOT a fail:** zero registrations on a healthy launch (#146). Also **NOT** this item: ×4 push
  delivery — that is #143, relay-side, different repo.

---

# GROUP B — disconnect both hosts

Do all of these in one disconnected window.

## B1 · #61 — degenerate conversation cards

**#61 CANNOT BE TESTED WHILE PAIRED.** The connected drawer is server-fed and never touches the
code that changed. Three prior sessions were spent on the wrong screen.

**DO:** with both hosts disconnected (standalone / on-device model), ask something that draws a
short opening line — a haiku request is the known case.

- **PASS:** the conversation's **title** and its **preview** are visibly different content.
- **FAIL:** the title is still a verbatim prefix of the preview — e.g. title "I can't create a
  haiku" over preview "I can't create a haiku directly, but here's a simple one:".

**[CLAUDE CAPTURES]** which guard tripped — the log names it, and should now name the new
exact-prefix branch.

## B2 · #172 negative case

While still disconnected, re-open the DELIVER field's **Custom…** path.

- **PASS:** **USE LIST does NOT appear** (no host ⇒ no platform list to return to).
- **FAIL:** it appears and leads nowhere.

---

# GROUP C — connector stopped (Claude stages this)

## C1 · #117 — health-drain deferral under outage

**Tell Claude when you reach this point** and the connector on the Mini gets stopped.

**PATH:** Settings → **About & Diagnostics** → the sensor diagnostics panel.

- **PASS:** drains **defer** with honest notes ("retries exhausted" / "upload failed"), and the
  backlog is held for the next trigger.
- **FAIL:** continuous POST traffic with no backoff — the original no-backoff loop returning.

**Precondition:** sensor health collection must be ON for this to mean anything. Turn it on for
this check and Group D, then restore whatever posture you want at the end — and tell Claude what
you restored to.

**Claude:** restart the connector afterward and verify it re-attaches. Leaving it down silently is
the #113 failure mode.

---

# GROUP D — migration reset

## D1 · #137 — fresh-install migration, without erasing the device

**PATH:** Settings → **Developer** → **Sensor opt-in migration** → **Clear migration stamp**.
Then relaunch the app.

- **PASS:** with the device paired and no stored settings blob, the migration does **NOT** enable
  health or location, and **no permission wall returns**.
- **FAIL:** either sensor switches itself on, or the wall comes back.
- **SANITY CHECK FIRST:** the reset must clear **both** the UserDefaults value and the Keychain
  mirror. If the relaunch behaves as though nothing was cleared, that is a defect in the **reset**,
  not a #137 pass — file it separately.

Note the streaming/motion posture before and after.

---

# Optional — #130 TTS fidelity A/B

Only if there is appetite left. Probe branch `probe/t27-130-halfduplex` (PR #128, OPEN,
DO-NOT-MERGE) needs its own build. Your ear decides between half-duplex `.default` (crisper TTS,
barge-in degrades to tap-or-gap) and the status-quo `.voiceChat`. **Reinstall the main build
afterward.**

---

# Out of scope — do not spend device time here

Waiting on code, not on Owen: **#180** (needs a design decision), **#178's audio deprecations**,
**#176** (spec'd, unbuilt), **#183 Phase 1** (spec'd, unbuilt), **#145** (cause now named — no
chat-plane timeouts, fix unbuilt), **#143** (relay repo), **#127** (App Store Connect ops),
**#21**, **#170a**, **#93** (needs the on-device model gate).

**#147 is CLOSED** — the crash was fixed 2026-07-21 by PR #129 (`20b46fc`); PR #126 was exonerated.
Do not re-test it.

**#125 was CUT** (PR #142). There is no Health Trends screen. Do not look for one.

Stale Wave 4.5/5 checklists (#67, #68, #72, #73, #77, #80) carry unrun steps from early July.
**Audit against merged-PR state before spending device time** — several are likely covered by later
verified work.
