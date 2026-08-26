# #309 Lane B — Connect Host build spec (Owen's Claude Design → code)

**Written 2026-08-25 night (Fable). The VISUAL authority is Owen's Claude
Design export, committed at `design/connect-host/` (wizard + settings +
the "Today" current-state reference; read the `.dc.html` SOURCE as spec —
the standing memory). This doc records the SEMANTIC translation, the
fact-check verdicts, and the corrections; where it and the .dc.html
disagree on mechanism, THIS doc wins; on look, the design wins.**

## 0. Fact-check verdict

Both deliverable artifacts are vocabulary-clean (zero relay/pairing-code/
encryption claims — those appear only in the "Today" reference panel,
correctly, as the thing being replaced). Copy that names mechanisms is
accurate: `hermes talaria pair-qr` exists (plugin PR #7, tonight),
`hermes gateway run` opens :8642, the key lives in the Keychain, the QR
carries address+key+name. **One falsehood found, fix in translation
(§4.1); a handful of new mechanisms the design implies are enumerated in
§3 so nobody discovers them mid-lane.**

## 1. The design's own reading of the wizard ruling — ADOPT IT

The export's A0 annotation: **"THE WIZARD IS ENTERED, NEVER IMPOSED."**
The wizard's entry point is the Settings **Connect Host** row when no
host exists — there is NO first-launch auto-wizard at all. This is
stricter than the ruled "skippable" and strictly better under #31 (the
no-pairing-wall stance): first launch still lands in chat untouched, and
"first-time setup" means "the first time you tap Connect Host." Adopted.
"Not now" appears on every wizard step and lands in plain chat with no
banner, no nag, no empty host slot (B7).

## 2. Structure → code mapping

- **Wizard (A0–A6, B1–B7):** a single flow presented from Settings —
  step 0 choice (START LOCALLY glowing/recommended vs CONNECT MY HOST) →
  step 1 connect (scan-first; "Enter it manually" disclosure) → step 2
  probe (three named checks) → step 3 done. Progress = four bars; back
  chevron from step 1 on; "Not now" always. House components:
  `HUDScreenBackground` + corner brackets, `ReactorOrb` (.onboarding for
  step 0, the checking animation is the orb + spin rings), `MonoLabel`,
  `GlowButton` (primary), `GhostButton` (secondary rows), forge tint for
  failure states — never danger-red (failures here are warnings).
- **Settings screen (A1–A4, B1–B4):** replaces `ConnectHermesHostScreen`
  AND the relay half of `ServerSettingsScreen`'s profile editor. States:
  empty (not an error; "RUNNING LOCALLY · ON-DEVICE BRAIN" named as the
  current answer) · filled/ready · checking INLINE (fields dim but stay
  visible — no modal) · connected resting card · failed-in-place (only
  the guilty field flagged) · connected-but-quiet (SAVED ≠ REACHABLE) ·
  multi-host list (B3) · disconnect confirm (B4).
- **Multi-host (B3) = the PROFILES system.** "3 HOSTS · OJAMD IN USE" is
  the `BackendProfile` list wearing the new clothes: IN USE = active
  profile; per-host status is measured or "NOT CHECKED" — never guessed;
  "NO KEY" is an honest state. "Add another host" = new profile through
  the same wizard/fields. This screen ABSORBS the per-profile
  Pair/Re-Pair/Forget UI the deletion map already retires.
- **Scanner:** `SetupCodeScannerView` re-pointed at the Lane D payload
  (`{"talaria":1,"gateway":…,"key":…,"name":…}` — pin the plugin repo's
  `tests/fixtures/pair_payload.json` bytes app-side; the cross-repo
  contract). Scanner states: live (camera surface, escape hatch on
  screen) · camera-refused (typed arm promoted, iOS-Settings link
  secondary) · no-camera device (half-sheet, not a full screen).

## 3. Mechanisms the design implies — build these knowingly

1. **The probe ladder (steps: "Address reachable" → "Key accepted"/
   "Checking the key" → "A Hermes gateway"):** implement as ONE
   authenticated request where possible — `GET /api/model/options` with
   the bearer answers all three (reachable + key valid + Hermes-shaped
   response) AND yields the "MODELS SEEN n" count for the connected
   card; measure latency around it. An unauthenticated `/health` first
   hop MAY separate "nothing answered" from "key refused" cleanly —
   lane's choice, but the three verdicts shown must map to real
   discriminations, never theater. Timeout ~5 s ("The phone waited five
   seconds" is copy — keep the number true).
2. **Commit-on-probe-pass:** "Nothing is saved until the check passes" /
   "Saved only if the host answers and takes the key" — the profile (or
   the edited credentials) persist ONLY on probe success. #406's
   commit-time draft pattern extended one notch: the commit moment is
   the green probe. Failed probes leave stores untouched (B1's "NOTHING
   WAS SAVED. YOU ARE STILL ON-DEVICE.").
3. **Disconnect, one action, both halves (A4/B4):** local forget
   (credentials + plugin device token out of the Keychain) + plugin
   `unpair` POST. **New small mechanism — deferred revoke (B2):** when
   the host is unreachable at disconnect time, the copy promises "OJAMD
   is told when it's next reachable" — queue the unpair (persisted
   intent, retried on reachability) or, if the lane finds that
   disproportionate, change B2's disconnect blurb to the honest simpler
   truth and record the deviation. Copy follows mechanism, never the
   reverse.
4. **"Name this host" (A5):** name from the scanned payload's `name`;
   typed setups fall back to host/IP; editable at the done step and
   later (profile name).
5. **Key never shown post-save:** reveal toggle exists only pre-commit;
   after commit the key renders as "IN KEYCHAIN" forever (re-entry
   replaces it wholesale).
6. **"Check now" on the resting card:** re-runs the probe on demand;
   "LAST ANSWERED" timestamp is measured, not asserted (#350's lesson
   lives here — this screen is now honest by construction).

## 4. Copy corrections (the fact-check's teeth)

1. **🔴 The one falsehood — step 0's local card:** "…run on this phone.
   No account, no host, nothing leaves the device." FALSE as written:
   the hostless tier includes Private Cloud Compute, which sends the
   request (and since #390, attached images) to Apple — exactly the
   tier-honesty class #385 filed and the privacy policy just published.
   **Replacement:** "Chat, photos, and the device tool belt run on this
   phone — or Apple's Private Cloud when you pick that model. No
   account. No host." (Lane may tighten wording; the constraint is: no
   absolute nothing-leaves claim while PCC is electable.)
2. B7's "ANSWERED ON THIS PHONE" chip: reuse #371's provenance-label
   affordance/vocabulary — do not invent a second provenance surface.
3. "Phone context stays off until you allow it" (A6): verify the toggle
   name it points at and match the real setting's language.
4. Illustrative chrome (TALARIA v2.4.0, 9:41, the weather chat) is not
   copy — ignore.

## 5. What Lane B deletes (with the design as cover)

Per the §5 deletion map + the rulings: `ConnectHermesScreen`,
`ConnectHermesHostScreen`, `PhonePairingCode`/`RelaySetupCodePayload`,
`LivePairingService`, `LiveHermesHostService` + `HermesHostStore`'s
relay half (Lane C's row-7 adapt feeds the new probe instead),
`PairingStore` (its `isPaired` readers re-derive from
profile-has-credentials — the sweep's §1 table is the checklist),
`AppSessionState`/`AuthTokens` UI readers, `relayBaseURL` property
(ruled), the Keychain hygiene pass (§4 of the design doc — BOTH
writers' slots), and `AppTemplateUITests` rewritten for the new flow.
#412 closes with the screen that carried it.

## 6. Sequencing

Lane B runs AFTER Lane C (C's adapts change what the new screen probes
and reads). Bars register in #309 at B's lane-open, drawn from this
spec; the eyeball of the finished flow is a runbook card (merge-on-green
stands per the ruling — the look gets Owen's eye post-merge, not a
merge hold, unless he says otherwise when he sees the card).
