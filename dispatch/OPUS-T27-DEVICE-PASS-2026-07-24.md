# OPUS-T27 — Device pass, 2026-07-24

**Items:** OPEN_ITEMS #133, #179, #128, #129, #124, #123, #112, #81, #117, #116, #61, #172, #137 (the last three are Bundle A, PR #143)
**Repo:** AethyrionAI/Talaria-27 · **Base:** main (`0dab455` at spec time) · **Branch:** none — this is
a verification pass, not a code lane. Findings land as OPEN_ITEMS commits only.
**Driver:** Owen on whoGoesThere (iPhone, iOS 27 b4). **Verifier:** Claude Code Opus, local, full access.
**Staleness check:** re-run at start — `gh pr list --repo AethyrionAI/Talaria-27 --state all --limit 20`,
`git log --oneline -15 origin/main`. OPEN_ITEMS numbers ≠ GitHub numbers.

## Mission

Thirteen items are carrying owed device verification. All the code is merged; nothing here is
blocked on a build. The bar for this pass, borrowed from #171 which worked well: **verify every
claim against live state — relay DB rows, gateway responses, device logs — rather than accepting
what the screen says.** Screen state is a hypothesis, not evidence.

Run the lanes in the order below. It is ordered by cost, not by importance: the two-minute checks
come first so a short session still closes something.

Record each check as PASS / FAIL / PARTIAL / UNRUNNABLE. **PARTIAL and UNRUNNABLE are legitimate
outcomes and must be recorded as such** — do not round a partial up to a pass. #137's history in
this tracker is the cautionary tale.

---

## Preflight

1. `export DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer` in every shell.
   Wrong-toolchain smell: `cannot find in scope` for iOS-27 APIs → check `DEVELOPER_DIR` first,
   never edit app code to satisfy a stale SDK.
2. Both hosts up and on Hermes 0.19 (Owen confirmed 2026-07-23): Mac Mini `100.79.222.100`,
   OJAMD `100.110.102.59`. Verify listeners before starting — relay `:8000`, gateway `:8642`,
   shim `:8765`, connector attached. Check port OWNER, not service name (`Get-NetTCPConnection
   -State Listen -LocalPort 8642 → OwningProcess`); the gateway on OJAMD is a user `pythonw`
   process, NOT an NSSM service.
3. Note on OJAMD (from #113 forensics, 2026-07-23): relay and shim were found **Stopped** with
   `StartType=Automatic`. Confirm they are running before blaming the app for anything.
4. Build and install a fresh device build off current `main`. Record the SHA in every finding —
   "device-verified" without a SHA is worthless six days later. **The build MUST be at or after
   merge `fdc6ebb` (PR #143)** or Lane 10 has nothing to test.
5. `export GH_PAGER=cat` before any `gh` command.

---

## LANE 1 — #133 push registration idempotency (~2 min)

Merged PR #123. The DB row-count leg closed 2026-07-23 on both relays; the **launch-log leg is
what remains**, and it is the only part that exercises the app-side fix.

**Setup:** both profiles paired (OJAMD + Mac Mini). Force-quit the app.

**Run:** cold launch → let it settle → background it once.

**PASS:** at most ONE registration line per profile in the launch log (2 max, not 5); exactly one
background app-state report per backgrounding; sensor pipeline unaffected.

**FAIL:** 3+ registration lines, or a doubled background report.

**Do not misread:** a healthy launch may legitimately show ZERO registrations (see #146). Zero is
not a fail. Also expect a background launch followed by a foreground activation to produce two
lifecycle entries — that is correct, not fan-out (recorded under #133, 2026-07-17).

**Cross-ref:** #143's ×5 notifications are relay-side (duplicate device rows sharing one APNs
token) and are NOT what this lane tests. Do not let a ×5 observation here get filed as a #133 fail.

---

## LANE 2 — #179 Control Center cold-tap (~1 min)

**Setup:** force-quit Talaria; leave it long enough for `TalariaWidgets` to go cold.

**Run:** open Control Center, tap the SAME control twice, a few seconds apart. Capture with
`idevicesyslog` — this lane is a log finding, not a UI finding.

**PASS (shape established):** the first tap produces the 21 ms `Starting → Successfully ran`
sequence with NO `PerformAction` and NO `perform()`, and the extension launches only afterward;
the second tap runs the full `InitializeAction → ResolveParameters → LocateActionPerformer →
PerformAction → perform()` sequence. That confirms cold-extension behaviour → design around it.

**FAIL (shape not established):** both taps behave identically → the app influences it, and it
needs a real fix.

**Expectation management:** the control will NOT actually work either way. #58's nil-`OpenURLIntent`
defect is unfixed and is a separate lane. Do not chase it here.

---

## LANE 3 — #128 + #129 voice preview mid-session (one sitting)

Both merged (`d8b9ad7`, PR #127). One physical test closes two items.

**Run:** start an ACTIVE voice session → Settings → audition several voices → apply one.

**#128 PASS:** no crash. Original failure was `AVAEGraphNode CreateRecordingTap: nullptr == Tap()`,
uncaught NSException, hard kill.

**#129 PASS:** session keeps running, mic still live afterward; outside a session, previews play at
full fidelity.

**ACCEPTED BEHAVIOR — not a fail (Owen, 2026-07-23):** on native-engine sessions, previewing
mid-reply drops that reply's un-spoken audio tail (transcript stays intact) and the next chunk cuts
the preview short. Realtime engine — the primary case — previews play over the session. **Owen has
accepted this; the third dedicated preview instance is CANCELLED, not deferred.** Record the
acceptance in #129 and drop the open question.

**Watch for, but file separately:** #138 self-barge-in and #139 engine-label mismatch are live in
this same surface. If they show, file against those items, not against #128/#129.

---

## LANE 4 — #124 Face ID app lock (merged PR #119, never run)

Seven boolean checks. Any unchecked box is a fail worth its own item.

- [ ] Toggle on → background → reopen → Face ID prompt appears OVER content
- [ ] Fail twice / cancel → retry button → system passcode sheet unlocks
- [ ] App switcher shows the obscured splash snapshot, NOT chat content
- [ ] Grace 1 min: background <1 min → no prompt; >1 min → prompt
- [ ] Siri "Ask Talaria27" works while locked; tapping its result lands on the lock
- [ ] Background with Settings sheet open → reopen → cover is ABOVE the sheet
- [ ] Push arrives while locked → banner shows, UI stays locked

The app-switcher-snapshot and cover-above-sheet checks are the two most likely to fail; they are
the ones a unit suite cannot see.

---

## LANE 5 — #123 Share extension (merged PR #118, never run)

Sim smoke already passed a hand-planted envelope on cold launch, so the app-group container path
works. This lane is about the real share sheet.

- [ ] Safari URL → composer text
- [ ] Photos photo → image chip
- [ ] Files PDF → file chip
- [ ] Two rapid shares → both land, IN ORDER
- [ ] 25 MB video → polite refusal IN THE SHEET (not a crash, not silence)
- [ ] Share while app force-quit → lands on next launch
- [ ] `hermes://ask` still works — separate seed slot, must not collide with shares

**Known v1 simplification, not a defect:** drain file IO runs on the main actor, bounded by the
20 MB cap. Only file it if a real hitch shows on device.

---

## LANE 6 — #112 Comic Book adaptive theme (merged PR #84, owed since 07-13)

First adaptive theme in the app; the live-switch is the whole point.

**PASS:** Settings open and foregrounded → toggle system appearance → Villain Variant ↔ Sunday
Funnies re-skin WITHOUT relaunch.

**Two documented seams needing Owen's verdict — these are questions, not automatic fails:**
(a) picker cards preview the presented-surface variant while a fixed theme forces the scheme;
(b) cold light-mode launch flashes the villain half for one frame before the mirror lands.

Also spot-check the 13 new icons in the picker. **iPad note:** the `CFBundleIcons~ipad` fix rides
Shelley's next install — not testable here.

---

## LANE 7 — #81 Lock-screen reply (merged PR #55; relay half live on OJAMD)

Never run. The evening it was due went to the #83 letterbox chase.

**Run:** let a run finish while the phone is locked → long-press the push → Reply → type → send.

**PASS:** headless post lands in the right session; the NEXT completion push also carries Reply.

**Profile-aware check (#114):** the headless reply must post to the push's SESSION BIRTH profile,
not whatever profile is active at reply time. Verify against the relay DB, not the screen.

**Honest-failure checks — silence in any of these is a fail:**
- relay watch TTL expired → clear notice
- wrong/expired API key → "Reply not sent"
- reply while another run streams → busy notice

**Refuted claim, do not chase:** "Approve/Deny slash commands" from the original discovery do not
exist and nothing here pretends they do.

---

## LANE 8 — #117 health-drain deferral under connector outage (merged PR #103)

Requires a staged outage. Stop the connector on the Mini (`start-connector.bat` is the restart;
the connector is a plain bat-launched process, NOT NSSM).

**PASS:** with the connector down, the sensor diagnostics panel shows drains DEFERRING — honest
notes ("retries exhausted" / "upload failed") — and the backlog is held for the next trigger.

**FAIL:** continuous POST traffic with no backoff. That is the original no-backoff loop back, and
it is the app-side shape of the #113 dead-connector incident.

**Precondition:** sensor health collection must be ON for this lane to mean anything. See Lane 10 —
Owen currently has sensor streaming OFF (state note, #137, 2026-07-23). Turn it on for this lane
and Lane 10, then restore whatever posture Owen wants at the end and RECORD what you restored to.

**Restore the connector when done and verify it re-attaches** (WS attach visible via
`Get-NetTCPConnection`). Leaving it down silently is exactly the #113 failure mode.

---

## LANE 9 — #116 shim plane DoD — UNBLOCKED 2026-07-23

**The hold is lifted.** This item was ON HOLD pending Hermes 0.19; Owen confirmed 2026-07-23 that
0.19 is live on BOTH the Mac Mini and OJAMD. Update the item header accordingly.

**Deploy first (still owed, ahead of the pass):** restart relay + connector on the Mini's live
checkout. OJAMD's half rides the `ojamd-deploy` rebase onto `t27/main` — that is Owen's manual
security gate, so ask before touching it; do not attempt a standing SSH from the Mac.

**DoD pass:** forget the Mac pairing → re-pair via QR → the shim token auto-fills within seconds →
the probe reports honestly.

**PASS:** zero manual token paste, and the probe's verdict matches reality (a failing shim must
read as failing, not as silence — "make the probe honest" is half this item's scope).

**FAIL:** any manual paste still required, or a probe that reports success against a dead shim.

**Context worth carrying:** the models shim is being phased out (#161). This DoD is about removing
a bad onboarding step that exists today, not about investing in the shim's future.

---

## LANE 10 — Bundle A verification: #61, #172, #137 (one build, three checks)

All three shipped in PR #143 (merge `fdc6ebb`). Each was unit-verified; each has a stated blind
spot that only a device closes.

### 10a — #61 on-device card, STANDALONE ONLY

**This cannot be verified against a paired host.** The connected-mode drawer is server-fed —
`SessionsHermesClient.listSessions` maps `row.title`/`row.preview` straight from the Hermes API.
#61 renders only via `conversation.title` / `generatedPreview`, i.e. `ChatScreen`'s header and
`LocalChatBackend.sessionInfo`. Three prior sessions were spent on the wrong screen. **Disconnect
both hosts first.**

Run a standalone chat whose reply opens with a short sentence the title is likely to echo. The
known device case: title `"I can't create a haiku"` (22 chars) against preview
`"I can't create a haiku directly, but here's a simple one:"` (~57).

- **PASS:** title and preview are visibly different content — the exact-prefix guard discarded the
  degenerate card and the fallback produced something distinguishable.
- **FAIL:** title is still a verbatim prefix of the preview.
- The log names which guard tripped. Capture it either way; that logging is how this was diagnosed
  and it should confirm the new exact-prefix branch by name.

### 10b — #172 deliver picker return path (one tap)

Not unit-testable — same view-wiring blind spot as #168a.

Task editor → DELIVER field → **Custom…** → confirm a **USE LIST** control appears and returns you
to the menu, with any typed value preserved as a marked `(custom)` row.

- **PASS:** the return control is present and works; the typed value survives the round trip.
- **FAIL:** no way back, or the value is lost crossing back.
- **Also confirm the negative:** with no host connected (`platforms == nil`), **USE LIST must NOT
  appear.** Offering a return to a list that cannot open is the second dead end #168a was careful
  to avoid, and it is the check most likely to be skipped.

### 10c — #137 fresh-install, now WITHOUT erasing the device

The setup changed at review. The stamp is monotonic in release, so disconnect no longer produces a
re-migratable device — but a DEBUG reset now exists (added in PR #143, #134's harness precedent).

1. Settings → Developer → **Sensor opt-in migration** → **Clear migration stamp**
2. Relaunch the app

- **PASS:** with the device paired and no stored settings blob, the migration does **NOT** enable
  health or location, and does not resurrect the permission wall.
- **FAIL:** either sensor comes on by itself, or the wall returns.
- **Sanity check first:** the reset clears BOTH `UserDefaults` and the Keychain mirror. If a
  relaunch behaves as though nothing was cleared, the stamp read as still-migrated — that is a
  defect in the reset, not a #137 pass. File it separately.
- Note streaming/motion posture before and after, and restore whatever you want at the end.

---

## Optional — #130 TTS fidelity A/B (separate build)

Only if the session has room. Probe branch `probe/t27-130-halfduplex` (PR #128, OPEN, DO-NOT-MERGE).
Build and install it, A/B against main by ear: TTS crispness, whether the `vpio render err: -1` flood
stops, and how much barge-in degrades to tap-or-gap. Owen's verdict decides #130 between (a)
half-duplex `.default` and (b) status-quo `.voiceChat`. **Reinstall the main build afterward** and
say so in the write-up.

---

> **LANE 10 REMOVED 2026-07-24.** #125 Health Trends was CUT (PR #142) — the screen no longer
> exists, so there is nothing to verify. #181 closed moot with it. Do not look for either.

## Explicitly OUT of scope — do not spend device time here

Waiting on code, not on Owen: **#58** (root-caused — `OpenURLIntent` resolves nil in the widget
extension), **#61** (root-caused — `degenerateCardReason` threshold gap), **#137** (trap case FAILED
2026-07-23; fix approved, not built), **#172** (deliver picker one-way door, deliberately unfixed),
**#147/#145** (container-persisted launch wedge, unfixed), **#143** (relay-side duplicate device
rows), **#127** (App Store Connect product setup — ops, not testing), **#21** (blocked on an unrun
binary-write SSE probe), **#170a** (OJAMD stopped writing `model_snapshot` — see #148, unreachable).

**#126 Daily briefing is DROPPED** (Owen, 2026-07-23) — superseded by the #162 Tasks/cron surface.
Do not run its six-step checklist. Close the item; see the OPEN_ITEMS write-up below.

There is also a stale tail of Wave 4.5/5 checklists (#67, #68, #72, #73, #77, #80) carrying unrun
device steps from early July. Several are probably covered by later verified work. **Audit them
against merged-PR state before spending device time** — a dead-dispatch incident has already
happened once in this project from re-sending work that was already done.

---

## Write-up rules

- OPEN_ITEMS.md edits go in their OWN surgical, file-scoped commit — never mixed with anything else.
  Fable has violated this repeatedly; do not repeat it.
- OPEN_ITEMS.md stays MONOLITHIC. Do not split it.
- Before appending a new item, verify the max number:
  `grep -oE '^## [0-9]+' OPEN_ITEMS.md | grep -oE '[0-9]+' | sort -n | tail -1`
- Record the build SHA and the host (Mac vs OJAMD profile) in every finding.
- New defects get their own numbered item with a repro, not a sentence buried in the tested item.
- If a lane is UNRUNNABLE, say why in one line and what would make it runnable. That is more useful
  than a silent omission — see #137, where an unrunnable pass was mistaken for an owed one for days.
