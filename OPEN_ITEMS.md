# Talaria — Open Items / Follow-ups

**Compiled:** 2026-06-23 · **From:** the models-shim / Phase-B wiring session.
**Landed this session (on `main`, merge `98a9a89`):** T1 (Settings→Models dual-write
picker), T2 (regex + copy fixes), shim cache-bust. See the merge commit for detail.

Status legend: 🔧 in progress · ⛔ blocked · 💤 dormant · 🐛 bug · 📝 note / decision ·
**❌ cut / won't-do (terminal)** · ✅ done.

> ## SPLIT 2026-08-06 (#261) — closed history lives in `OPEN_ITEMS-ARCHIVE.md`
>
> This file is the LIVE BOARD: open / watch / decision items plus the standing
> conventions. Every ✅-closed item was moved — VERBATIM, never summarized,
> never renumbered — to `OPEN_ITEMS-ARCHIVE.md` in this directory. Item numbers
> are ONE monotonic sequence across BOTH files; a number is never reused or
> changed, and a reopened item moves its block back here rather than being
> rewritten there. References like "#21" in the items below may point into the
> archive — if a number is missing from this file, look there.
>
> **Counting now spans both files.** The full item set is:
> ```
> cat OPEN_ITEMS.md OPEN_ITEMS-ARCHIVE.md | grep -oE '^## [0-9]+[A-Z]?\.' | sort -u | wc -l
> ```
> The HOW-TO-COUNT rules below still govern both files — run them over the
> concatenation for whole-project figures, or over one file for its own board.

> ## HOW TO COUNT THIS FILE — added 2026-08-01 (Phase 0), made mechanical 2026-08-02
>
> > **CANONICAL HEADER FORM — `## N.` or `## NL.` for letter-suffixed lanes
> > (`## 216A.`). There is exactly one form; `## #N` no longer exists.** Canonicalised
> > 2026-08-02 after the external audit's recount returned **200 against a claimed 229**,
> > purely because two forms were in use. `#N` was retired rather than kept because a
> > header reading `#223` looks like a **GitHub** reference, and that collision has
> > misfired twice (see #128). Prose still says "#223" — only headings are constrained.
> >
> > **The count is now one line, and it counts UNIQUE ITEMS, not headings:**
> > ```
> > grep -oE '^## [0-9]+[A-Z]?\.' OPEN_ITEMS.md | sort -u | wc -l
> > ```
> > **Unique matters:** items **198** and **199** each have two headings (the numbering
> > convention changed mid-project; both are ✅ and each points at the other). Counting
> > headings instead of items reports **232** and inflates ✅ to **136**. The true
> > figures are **230 items / 134 ✅** — the old 136 was this exact double-count.
>
> **"Open" is NOT "not ✅", and counting it that way overstates the backlog.**
> Subtracting ✅ from the item count leaves **96**, but that figure sweeps in three
> terminal states that are not work:
>
> - **📝 (9)** — mixed, and the only marker that needs reading rather than counting.
>   **#3, #6, #7, #83 are pure records** (a standing rule, a cosmetic thing left
>   as-is per Owen, an informational seam, a resolved investigation) — terminal.
>   **#8, #90, #101, #109, #155 are real future work** wearing a 📝.
> - **❌ (3)** — #125 and #126 are completed cuts, terminal. **#161 says "NOT
>   VIABLE, recommend closing" and the close was never actioned — Owen's call.**
> - **💤 (2)** — #4, #55. Parked, not done. Count as open-but-not-scheduled.
>
> **The honest figure as of 2026-08-02 (post device pass, recomputed on UNIQUE items):
> 233 items · 141 ✅ · 6 terminal-not-✅ (4 record 📝 + 2 completed ❌) · 86 genuinely
> open**, of which 2 are dormant and 1 awaits Owen.
>
> *Movement on 2026-08-02, and it is worth reading as two opposite forces:* the day's
> lanes and the evening device pass closed **seven** items (134 → 141 ✅ — #144, #145,
> #151, #146, and the F1 verdicts), while the pass itself **filed three new ones**
> (#225 the 64-call spiral, #226 the push-watch no-op, #227 the single-flight umbrella).
> **Net: 90 → 86 open.** A device pass that closes seven and opens three is the system
> working — the new items are defects that were always there and are now NAMED, which
> is strictly better than a smaller board with the same bugs in it.
>
> *Earlier the same day: "229 · 136 ✅ · ~87" (08-01) → "230 · 134 · 90" after
> canonicalisation, where **✅ fell by 2 because #198/#199 were double-counted**.
> Marker tallies (📝 9, ❌ 3, 💤 2) verified against unique items, not headings.*
>
> **Do not read a header and stop.** Every header-only judgement made during this
> phase was wrong. #162/#163/#165 read "BUILT on branch" and the code is on `main`
> — but all three carry an **"Owed — device checklist"** line further down, so they
> are *shipped with verification owed*, **not** closable. #210 and #208 read as
> concluded ("FIXED", "hypothesis falsified") and both carry explicit **"Still
> owed" / "OWED"**. The five ✨ merged features all carry queued device debt.
> **Six items looked closable from their headers; zero were.**

> **Work audit — 2026-08-02 (Hermes, independent session): PRs #218–#238, `70c8536..d869af1`.**
> Method was **re-execution, not re-reading** — fresh clone, its own `lane-gate.sh` run
> (**PASS**, 1497 + 8, Release green), the §E1 probe recompiled and re-run on the sim
> (**reproduced byte-for-byte**), the board recount, the range totals, and live HTTP
> probes of the gateway. Verdict: *"the strongest two-day stretch the project has
> produced"*; no reverts owed. **Three things came back that we did not know:**
> **(1)** #145's header was **stale** — it survived the two PRs that edited its own body
> (fixed, and the standing consequence is written into that entry). **(2)** Four of #223's
> routes 404 — **right observation, wrong cause on both sides.** The audit blamed a
> mid-version process (*"0.19.0 code under a 0.19.1 install"*), which was real (PID 28104
> from Jul 29) and which I had recorded the same way. Owen force-restarted the gateway and a
> **68-second-old 0.19.1 process returned identical 404s**: those routes are
> **dashboard-app-only (`:9119`)** and were never on the plane the phone speaks. **Running
> the audit's own recommended experiment is what falsified both of us** — and the #223
> investigation session reached the same verdict independently from OJAMD. See #223's
> retraction. **(3)** The `ChatStore` poll loop's
> comment was wrong by ~11× *after* #145 Part A changed its arithmetic — corrected in
> source; the loop itself stays filed, not fixed. Addendum nits (TestRunGuard's
> deliberate no-live-opt-in, the gate's MAX-over-all-numbers, the 20s false-failure
> trade) are annotated where they live. Counting-form fragility (`## N.` vs `## #N`,
> duplicate-number headers) is confirmed real and remains **Owen's call** — it is the
> "retire the old-style headers?" decision — **RESOLVED the same day, see the canonical-form
> box at the top of this file** — with a measured cost that made the call easy: the auditor's
> first recount returned 200 against a claimed 229 purely from the two forms.

> **Accuracy audit — 2026-07-13.** All 112 items were re-checked against `origin/main` (tip `cca1345`), merged-PR/closed-issue state, and on-disk code. Corrections are flagged inline as `> **Audit 2026-07-13:**` blockquotes. Summary: 65 items accurate as-was; 13 status-flips (3 shown ✅ but actually open — #17/#18/#31; 7 shown open but actually done — #37/#47/#48/#49/#55/#76/#94; 3 header-vs-body contradictions — #25/#79/#102); 34 'merged-unverified' items whose 'built in cloud / not compiled / needs merge' wording was stale (PRs since merged — device-verify is the only work left). Full write-up: `design/OPEN_ITEMS_AUDIT_2026-07-13.md`.
>
> **Eve session 2026-07-13.** Device+sim pass: #18/#50/#53/#63/#64/#65/#71 device-verified → ✅; #66 FAILED → 🐛; #61 fail root-caused + fixed (branch); PCC send-crash (#72) + churn (#111) closed by a `pccGrantConfirmed` stopgap (branch); iPad Hermes-switch diagnosed (provisioning + nudge branch); #93 fidelity gate still owed (sim skips it). New cloud dispatches: #104, #110. Build ✅ at cf5609f (iOS 27 sim), suite 582/582.

---

## INDEX — the live board at a glance (regenerated 2026-08-09 by the #261 archive sweep; the items below are the truth, this is only a map)

- **#56** 🔧 Wave 2 Issue E (GitHub #6) — "Ask Hermes" App Intent — MERGED (PR #11), core device-verified 2026-07-11 …
- **#392** 🔴 **A DECLINED CALENDAR EVENT IS REPORTED AS THE CALENDAR REFUSING IT** — *"your calendar didn't accept the request"* when the user declined the card. The calendar never saw it; `performCreate` returned *"The user declined"* and the model reported EventKit refused. **MEASURED 2/30 on device 2026-08-21, CALENDAR-ONLY (remind/alarm 0/20)** — which is the finding, not a detail: a fix aimed at declines in general would target the wrong surface. #180's family, #340's shape. Spawned from #199A's re-run rather than keeping that entry open under a changed meaning; bars 392-A..D pre-registered, and 392-A demands n>=30/arm after #372(c) proved tonight what a low base rate costs
- **#396** 🔉 VOICE IS TOO SENSITIVE on both engines (Owen, 2026-08-22) — four faults characterised separately per engine; **396-B (host knobs re-configured) + the ruled COARSE PICKER shipped** (app PR #361, plugin `e669549`, both hosts on 0.8.0), local half deliberately unbound behind the fault-2 author measurement. **⟵ 2026-09-02: 396-Q instrument MERGED (PR #416, squash `9dca3bad`) — the app now logs the preset it mints with (`#396 tuning preset=… engine=realtime values=host`), always-on, so the next archive attributes rate to preset; the app sends a NAME only, values stay host-side.** Still open: the LOCAL half, 396-D's live before/after quote, and #413's preset attribution once a tuned archive lands
- **#127** 🔧 Monetization scaffold — MERGED DORMANT + gate walk DEVICE VERIFIED 2026-07-17 (fail-open live-confirmed on …
- **#129** 🔧 Voice preview mid-session — MERGED (PR #127, merge `175261b`, 2026-07-20); device pass owed. Known accepted …
- **#138** 🐛 Realtime engine self-barge-in — assistant TTS captured as user speech (OJAMD voice host); slow turn … — **2026-09-01 ESCALATION SYNTHESIS appended (the cluster's one-page home): the phantom is ONSET-bound (5 of 7 speakerphone first utterances dirty, all 0.25–0.58 s after `audio.started`), this entry's "item.created root cause" is falsified on its own archive (it was #419-B's transcript-done reset, now fixed in `02cad7bf`), 138-K retired by measurement (the server clears on its own), hypotheses ranked, cards V1–V5 for Owen's election — V1 (the volume arm) first**  ⟶ **2026-09-02: card V3 (138-M, the SEGMENT INSTRUMENT) SHIPPED — three always-on `#138 segment` lines (`speech_stopped` segment ms + offset, `committed` offset, `transcript` chars + script class, never the text), RED-first and mutation-proven, H3's prediction pre-registered; V1/V2 Record now quotes them (PR #418, `60dd9641`). Still nothing measured — V1 remains the next move**  ⟶ **2026-09-02: card V5 (138-O, THE ONSET GATE) BUILT AND MERGED — the local uplink track is disabled for a named 800 ms from every `audio.started` and restored by a cancellable session-scoped timer, re-armed ONLY by a new playback; barge-in at +2 s untouched and the pre-existing pins byte-unedited; three always-on `#138 onset gate` lines, RED-first and mutation-proven (PR #420, `363f3265`). ⚠️ "V1 remains the next move" just above is SUPERSEDED — Owen's election folded V1 into **138-O-E**, now the single owed device card (speakerphone, `normal`, 3 starts at ~2 bars AND 3 at max, 0/3 onset phantoms per arm). Still nothing measured: the gate is a mechanism and only the phone can score it**
- **#140** 🔧 README + GitHub Pages refresh — ~~stale wedge narrative + pre-freemium positioning~~ re-scoped 2026-08-25 (as-filed premise discharged) → **✅ PUBLISHED the same day on Owen's go (PR #373, `47632a01`, verified live): relay claims retired, the vision story public, beta6 line, honest screens meta. Remaining: the P-4 screenshot batch + device rows R15/R16 (runbook-carded)**
- **#162** 🛠 156a Tasks lane — **SHIPPED, on `main`** (`Talaria/Features/Tasks/`, reachable at `ContentView.swift:246`) …
- **#163** 🧩 156b Skills lane — **SHIPPED, on `main`** (`Talaria/Features/Skills/`, reachable at …
- **#166** 🍎 App Store review-risk register — hermex's actual submission runbook mapped onto Talaria
- **#180** 🎨 UMBRELLA — the app hides its own degradation: one design default + a register ("four instances" is the as-filed count). Lane 180-L SHIPPED 2026-08-09 — bars 180-A..F. **⚖️ 08-25: the design question is RULED — Connect Host's state vocabulary adopted as THE standard; members migrate as lanes touch them (309-C6 is migration #1); umbrella stays open as the register** ⟵ **✅ 180-CONVENTION LANE MERGED 2026-09-01 (PR #406, `d8c8b7f2`): THREE of the four members the 08-25 close-out left outstanding are migrated — the `lastErrorMessage` gate (all three host-fed screens now render through one shared mapper onto the Connect Host ladder; structural pin watched RED on the untouched tree, mutation-isolated), the #241-inherited prose-failure instance (the STRUCTURAL half — a completed run the host itself flagged now carries a degraded marker instead of a clean reply's confidence; the pure-prose half stays open and is named as such), and #139's residual copy (the unapproved `VOICE · CONNECTING` no longer claims a connect in three states where nothing is connecting). **180-C-D HELD, untouched:** the health-permission card still waits on Owen's `PermissionStatus` ruling — and it is now the ONLY member of the 08-25 list not migrated. Gate PASS post-rebase FIRST RUN — 2827 Swift Testing / 15 XCUITest / Release clean
- **#224** 🎨 Mirror Hermes's three-mode approval model — ours is always-on Manual, theirs is Manual / Smart / Off, and … **✅ BALLOT APPROVED 2026-08-10, all eight cards as recommended — Phase 0 dispatch owed (bars pre-register in the entry); Phases 1–3 hold** … ~~**→ BARS 224-0A..0G PRE-REGISTERED 2026-08-11; Phase 0 READY TO DISPATCH.**~~ **⟵ corrected 2026-08-24: Phase 0 RAN the same day it was ready — ALL SEVEN BARS MET 2026-08-11, MERGED as `5313499b`; the entry's own ✅ result block records it while this line still said dispatch-ready. What remains is Phases 1–3, HOLDING on ruling 1 (Owen's call, not a lane).** ~~*"ours is always-on Manual"*~~ **⟵ FALSIFIED 2026-08-26: PHASES 1+2 ARE BUILT. Owen elected them ("Smart is a part of hermes… Orchestrate that as a lane"), the hold is discharged, and the app now ships the full Manual · Smart · Off mirror — Privacy → `// Agent Actions`, global on `UserSettings`, `.manual` still the default, Off with the floor that REFUSES. Bars 224-1A..1E / 224-2A..2B/2D MET; what remains on this item is the two DEVICE bars (224-1F, 224-2C — runbook cards, pre-registered and UNRUN) and Phase 3's transcript receipts, still DEFERRED per ruling 7.**
- **#303** 🐛 `VoiceEngineRouter` has no UPGRADE path — a cold Control Center voice launch pins NATIVE even when the brain permits realtime (`init` reads the brain 35 ms before the sticky-default restores it; `startSession`'s re-check guards only the downgrade direction). **MASKED on the host it was found on — cost UNMEASURED**; needs a realtime-configured host. Observed in passing by #254's device run, **not investigated**
- **#302** 🐛 A voice session STARTS ~650 ms before App Lock evaluates its cover — a Control Center "Talk to Hermes" launch begins on a LOCKED app. Whether the mic is ever LIVE behind the cover is **UNDETERMINED** and is the whole question; it **composes with #272** ~~which leaves the locked interval unbounded~~ (#272 FIXED 2026-08-09, PR #289 — the interval is now held by the Cancel-then-UNLOCK state instead). ~~Observed in passing, **not investigated**~~ **→ 🚨 ANSWERED ON DEVICE 2026-08-10 (§V1, build 2484): THE MIC IS LIVE BEHIND THE LOCK — 302-B RED, mic hot 34.9 s while `cover=locked`, going hot 3.87 s BEFORE the user cancelled; a second unplanned reproduction in the same corpus went hot 820 ms before App Lock even evaluated. 302-A "passed" by a 470 ms Face ID footrace, NOT a gate — there is no gate. Violates the 302-C contract Owen ruled the same morning. ~~FIX OWED, not built~~ → ✅ FIX BUILT 2026-08-20 (Thursday PM lane): `AppLockGate` is one consultable state, both voice doors defer until unlock, bars 302-D…G MET and each proven RED by mutation. ~~DEVICE VERIFICATION STILL OWED~~ → ✅ DEVICE-CONFIRMED 2026-08-20 ON BOTH ARMS: mic COLD behind the cover, and the parked start RESUMES on unlock (a real deferral, not a refusal). Only #124's seven App-Lock regression checks remain. Twin filing #323 carries the non-voice half** — **🔴 RE-OPENED IN EFFECT 2026-08-26 by #415's log forensics: the mic was LIVE BEHIND THE COVER AGAIN on build 3108, 27.4 s and 13.4 s, 2/2. The gate is not broken; it is sampled ONCE at start, and a Control Center tap on a WARM process clears it 1.2 s BEFORE App Lock arms. Every bar 302-D…G places the lock BEFORE the start, so none of them can see this ordering — which is the ordering this item's own title names. The 2026-08-20 device pass also ran the NATIVE engine, the only one carrying the `#302-A` instrument; all three #415 launches were REALTIME, which has no capture hot/cold line at all. See #415's 📏 FORENSICS block**
- **#308** 📝 PUBLISH the talaria plugin repo — the unblock for #269-B, and the update path it needs
- **#312** 🔬 Continuity fabric DEVICE PASS — ~~Group 7 has genuinely never run once~~ **→ IT RAN 2026-08-11 (Owen, `whoGoesThere`, build `6b9e7e2`): (c′) PASS — model switched mid-conversation, SAME hop reused, no priming notice, reply correctly attributed (`kimi-k3` → `deepseek-v4-flash`); (d) PASS — `[CONTEXT TRANSPLANTED INTO A FRESH SESSION — 36,939 TOKENS]` and the host read the prior exchange back; (e) PASS — airplane mode parks QUEUED with no Retry and fires exactly once on reconnect, *"almost instantly, like it was waiting on me"*; **(a) RED → filed as #329** (cold launch calls a live turn failed, offers Retry, tapping duplicates); (b) NOT RUN (needs a host-side gateway stop/restart); **(f) RED → filed as #330** (the whole SESSION block is absent on the transplanted thread — clipping ruled out by discriminator)**
- **#415** 🔴 the MIC STAYED ON after a Control Center voice launch (2/2, cleared by force-quit; privacy-surface real) — Owen's 3108 pass. **Log collect HAPPENED and the mechanism is NAMED: #302's ordering surviving #302's fix (App Lock arms ~1.2 s AFTER a warm CC tap clears the gate); the #303 engine-pin and #198 teardown-miss candidates are FALSIFIED.** ✅ **FIX BUILT 2026-08-26 night — 415-A/B/C MET (RED-first witness 8 tests/21 issues, three isolating mutations): a mid-flight cover now stops capture and PARKS the session, resuming once on unlock via a cover watch on the gate's new `waitUntilLocked()`, and `LiveVoiceSessionService` finally carries the `#302-A` capture instrument. 🔴 OPEN ON 415-D ONLY — Owen's device run holding the cover open.** The naming half is ✅ DONE (415-N, 2026-08-26): both CC controls read "Ask Talaria" / "Talk to Talaria"; host-meaning "Hermes" strings deliberately untouched. **The SHORTCUTS half is ✅ DONE too (415-S, 2026-08-26, Owen's "shortcuts only"): `AskHermesIntent.title` + the `TalariaAppShortcuts` `shortTitle` both read "Ask Talaria", the type name and the registration identity deliberately unmoved (measured: App Shortcuts key off `mangledTypeName`, never the title, so nothing re-registers and nothing orphans). CarPlay stays declined-with-a-trigger and is now GUARDED by a test. ~~🚩 One un-enumerated third site flagged for Owen: `parameterSummary`'s `formatString` still reads "Ask Hermes ${question}".~~** **⟵ ✅ 415-SWEEP DONE 2026-08-27 (Owen's STANDING RULING — "if it says Hermes outward on the phone, replace it with Talaria; exception being the in app connection"): the flagged `parameterSummary` is renamed AND the rule was applied WHOLESALE in one pass — 74 replacements across 37 files, every user-visible "Hermes" in the app/widget/intents targets classified app-meaning vs host-meaning and the whole inventory enumerated in the close-out (three lists + 7 borderline calls with reasoning). Newly swept surfaces no prior lane had inventoried: the **13 `Info.plist` permission usage descriptions** iOS renders in its own system alerts, the two **local-brain system prompts** ("You are Hermes" → Talaria — what the assistant answers when asked its own name), and **README/docs**, where the dispatch's premise was WRONG (#77 was a URL-scheme lane, not a naming lane) and six real app-meaning misses were found. ~100 host-meaning strings deliberately KEPT and newly pinned; fences (hermes:// scheme, CarPlay, control + widget `kind`s, type names) shown structurally. **The MIC FIX (415-A…D) is still what keeps this item red — naming is now fully done.**
- **#419** 🐛 the assistant-playback elapsed counter reads 0 EVERY TIME (all recorded readings, two archives) — a real barge-in would truncate the assistant item at `audio_end_ms: 0`, wiping the heard portion from server history; zeroing path evidence-pointed at a mid-playback assistant item event, mechanism undetermined until 419-A's one-line instrument exists — **✅ 419-A BUILT 2026-08-31 (`97e52d41`): item-arrival line captures the destroyed elapsed + same-vs-new discrimination; next session names the path** — **✅ 419-B FIXED 2026-09-01 (PR #410, squash `02cad7bf`): the zeroing path was `finalizeAssistantText` (transcript-done runs ahead of playout), named from source + three archives, not the item path 419-A1 watched; one conditional, RED-first + mutation-isolated, gate 2832/244 · 15/0 · Release**
- **#421** 🔴 **"OJAMD's gateway is down" is FALSE** — measured UP and healthy from the Mac (200 on both the CGNAT literal and the MagicDNS name; `/health/detailed` returns a running server's auth error). The PHONE cannot dial it: host-fed screens show `unsupported URL` = **-1002, a MALFORMED-URL error**, not a down host. Two fatal mechanisms in our code — no scheme validation anywhere, and MagicDNS names having no ATS exception (CIDR-keyed to `100.64.0.0/10`). **✅ SETTLED 2026-08-31: the field reads `/ojamd:8642`** — a relative path (scheme=nil, host=nil), rejected with exactly -1002. Mechanism 1 confirmed by measurement. **⚠️ Prepending `http://` is a TRAP — a MagicDNS host is then ATS-blocked; the working value is `http://100.110.102.59:8642`.** Corrects handoffs §23/§24
- **#422** 🧠 **MEMORY–AGENT INTEGRATION — REOPENED 09-02 for DESIGN** (was parked post-launch 08-31): four rulings — retrieval + explicit notes only (nothing inferred) · Memory screen with source + per-reply provenance chip · local and host stores NEVER merged · design now, pre/post-launch decided after the Fable design doc. **DESIGN DOC LANDED 09-02** (`planning/2026-09-02-422-local-memory-design.md`; shape + numbers + bars 422-A..GATE in the entry) — Owen rules schedule next
- **#332** 🎲 **THE FIRST DEVICE SUITE RUN** — the full unit suite had never run on hardware; it ran on the phone AND Shelley's iPad on 2026-08-11 and failed on both, differently (2 issues / 5 issues, same commit green on sim). Three causes: **(a)** #224's 0F bar reads Swift SOURCE at runtime, so it works only in a sim sandbox and **reds every device run**; **(b)** a Spotlight test assumes an empty index that a real phone does not have; **(c)** three attachment-downscale assertions go vacuous on the iPad — probably 2× vs 3× fixtures, **not yet proven**, and 332-c's first bar is to tell a fixture bug from a real regression. Bars per finding. **(a) and (b) FIXED 2026-08-12** (`t27-332ab-device-suite-test-fixes`; sim-verified, negative controls witnessed, one device-only half each pending the next central device pass); **(c) untouched and open**
- **#350** 🐛 **THE DRAWER AND THE SETTINGS STRIP ASSERT "LINKED · ONLINE" AGAINST A HOST THAT IS NOT THERE** — pointed at a closed port (`http://ojamd:12399`, verified refused from the Mac) and **cold-launched**, the drawer footer read `HERMES HOST / LINKED · ONLINE` with a green pip and the settings grid's status strip read `LINKED · OJAMD · DEEPSEEK-V4-FLASH`. Held for 20+ s of dwell; no probe, no decay, no re-verify. **MEASURED 2026-08-16 on `whoGoesThere` via iPhone Mirroring, incidentally, while setting up Group 4's standalone block.** The same screen's **Test Connection button is honest** — it actively probes and returns `ONLINE · 23 MS` on the real port, so the app HAS a truthful signal and these two surfaces do not consult it. **#180's honest-degradation family, and #342's "derived state survives, asserted state rots" in a UI surface rather than a doc.** ~~Bars pre-register before any fix~~ **⟵ INDEX LINE STALE UNTIL 2026-08-25 (the entry's own header knew): ✅ BUILT + MERGED 2026-08-18 (PR #318, `3d2e2992`) — both surfaces measured-only, honest CHECKING pre-probe, test-pinned; re-verified at HEAD 2026-08-25 (#382/#329/#264 untouched it). Only 350-D's 30-second device visual remains (runbook card §01)**
- **#279** 🐛 `retryMessage` removes the failed row without adopting — a retry can duplicate the user turn — **FIXED AND MERGED 2026-08-09 as `12ed25b`; bars 279-A..E MET (pre-fix user-row count 2 → 1), `GATE: PASS`. Stays open ONLY for 279-F (device, Owen).** …
- **#270** 🪟 #251 SLICE 2C — desktop face v0: the `plugin.js` pane that answers "is it actually installed?" …
- **#269** 🗣️ #251 SLICE 2B — the conversational installer: the AGENT installs its own plugin, the user never sees a terminal … **⟵ 2026-09-01: the APP HALF is BUILT + MERGED (PR #400 `582a8b49`, bars F/G/H/I/J met, consent = Owen's ruled Candidate B verbatim). Open: exactly the live-host half (B-A/B/D/E + B-C's N≥10), gated on a 🔐 per-experiment go**
- **#263** 🐛 Plugin transport: discovery-pass module reloads SPLIT the hub singleton; the enqueue wake misses the … — **(b) FIXED + 263-G MET; (a) AS FILED FALSIFIED — open ONLY as the (a) WATCH** (the header predates both) … **⟵ 2026-09-01: the PID chore (seven releases overdue) is MERGED in the plugin repo — PR #8, squash `d69a5e2`, plugin 0.8.0 → 0.9.0, bars 263-P-A/B met (RED-first, suite 256 → 257). ⛔ DEPLOYED NOWHERE: both hosts stay at 0.8.0 (`b4e8dfa`) until Owen's per-host go (263-P-C)**
- **#254** 👁 Control Center buttons BIND (confirmed 2034); ghost session = connect-window ownership race — **WATCH (downgraded 2026-08-05, header corrected twice, 2026-08-09); premise MEASURED (254-F), fix landed under 254-A/B/C; **254-D OWED, 254-E UNRUNNABLE AS WRITTEN (device 2026-08-09; native `LIVE` arm passed in its place)** — STAYS OPEN**
- **#220** 🔍 ENGINE-AMBIGUITY AUDIT of past voice verdicts. **#128's mystery SOLVED from source 2026-08-01 (and this …
- **#398** 🚨 the device is on a runtime we cannot reproduce — **premise MOVED 2026-08-24 (#401): the beta 6 Xcode EXISTS now (27A5252f, iOS-beta-7 SDK/runtime 24A5422a/24A5423a)**; **⟵ same day PM: FLEET ALIGNED — Owen upgraded the phone to beta 7**, first alignment since beta 5; 398-A..C unchanged and 398-B now lands on the runtime where Apple fixed FM excessive tool calling; **⟵ ✅ RAN 2026-08-26 — 398-A + 398-C MET (device runtime timeline measured; gate names its runtime), 398-B DEVICE-OWED (card written). Header provenance corrected: the build string is `logd.0.log`'s, stamped 08-17 not 08-22, so the skew was SEVEN DAYS — and the device ran `24A5390f`/`24A5408d`, both of which we hold, for most of the measurement era. STAYS OPEN on 398-B**
- **#198B** 🐛 A synchronous `AVAudioSession` call runs on the MAIN THREAD, at `fault` severity — **un-parked and ✅ BUILT + MERGED 2026-08-25 (PR #371, squash `02c45440`)** — awaited off-main transitions + guards + the #397 generation close; 198B-B/C/D met, both prescribed mutations isolating, gate 2547(+4)/14/Release; **only 198B-A remains** (zero fault lines on device — the runbook card targets build 3022) ⟵ **2026-09-01 the bar was re-cut twice: 198B-BAR (PR #408) replaced the `:978` line-number grep that read PASS while measuring nothing, and 198B-M (2026-09-02, PR #416, squash `9dca3bad`) replaced its verbose `.debug` record-leg-only positive control with an ALWAYS-ON `.notice` at `AudioSessionOffMain`'s choke point (`setActive(<bool>) off-main (#198B) reason=<leg>`) — four attributable legs, `log collect`-visible, so the hand-launched route can score this card too. 198B-A itself STAYS OWED on device; the build floor moved to the 198B-M build**
- **#198A** ⚠️ THE REAL-INTERRUPTION TEST: no false negative, but only ONE engine was verified and we cannot say which
- **#340** 🔴 the due date is OMITTED by the model — both prose fixes falsified 08-15; **ROUTE (a) APP-SIDE RULED by Owen 2026-08-18 ~22:15 post-refresher** *(this line read "route decision pending Owen's refresher" until 2026-08-21 — the ruling landed in the entry and never reached the board, #317)*. 🟡 **BUILT 2026-08-21 AM: `parseBareClock`/`resolveBareClock` ship in BOTH the tool path and — a defect nobody had noticed — the CARD-EDIT path, where typing a plain `18:00` into the Due field was rejected outright. The GUIDE change is held behind cell `armed-bareclock` (Owen, 2026-08-21) because 340-G's guide arm bought its omission win at a flagged cost in tool calls, so the TOOL path stays inert until 340-H5 runs; the card-edit fix is not inert. Four-bucket scorer re-denominated on TRIALS, not calls — `no-call` was structurally invisible before. Wiring mutation: deleting the `performCreate` line reds 2 tests and leaves all 11 parsing tests GREEN.** 🛑 **340-H5 RAN 2026-08-21 AND IS MISSED — the guide is NOT promoted** (union rose 75%→85%). **But the bar was badly formed and is retired:** a `no-call` trial is neither omitted nor wrong-value, so it LOWERS the union — the control's 5 no-calls depressed its number and the treatment was penalised for calling more reliably. Over CALLS the union FELL; two denominators, opposite verdicts, which is 340-F1's ambiguity committed one level up by the same lane that fixed it. **✅ Route (a) VERIFIED on device though:** 3 bare clocks sent, all `16:30` at 17:08, all resolved to TOMORROW correctly, and `already-past` is 0/37 across both arms where 340-G had every value stale. 🔴 **Still broken: the model sent a time 3/20 — omission is 85% and the founding defect is UNSOLVED.** Bars **340-H5′-A..D** reformulated (`correct`/trials primary, `wrong-value` guard, both denominators reported, n≥40 — tonight was ~2x underpowered). ~~340-E still owed~~ **⟵ ✅ 340-H5′-A/B PASSED 2026-08-27** (n=40/arm: union omitted+wrong-value 87.5% → 47.5%, p = 2.54e-04; populated-future 0% → 45%, p = 6.38e-07; `wrong-value` 0/40 both arms, `no-call` fell) · **⚖️ 340-E RULED NO 2026-08-31** (guard stays prose-only — DISCHARGED) · **✅ THE GUIDE IS PROMOTED 2026-09-01 (#340-PROMOTE):** production's `due` @Guide is the bareclock text, pinned on the PRODUCTION type by `PromotedDueGuideTests` reading it back out of `Arguments.generationSchema` (RED-first, revert-mutation RED), and `ReminderCreateToolBareclock` + the `armed-bareclock` cell are retired (cell count pin 33 → 32, moved deliberately). 🔴 **STILL OPEN and this entry does NOT close: the residual omission.** 18/40 correct is a win over 0/40, not a fix — ~55% of trials still carry no due date, 340-E is ruled out as a catcher, and the next measurement is named in the result block (PR #404, `a7a5d676`)
- **#368** 🔧 Phase 3 slice 3E — the runs-transport CUTOVER — MERGED 2026-08-19 (`33108d05`); runs is the DEFAULT plane; 3E-H's last two device steps owed Friday

> **2026-08-18 night — archive sweep 4:** the six-slice board audit closed
> **73 items** in one sitting (ballot: `planning/2026-08-18-close-ballot.md`)
> and filed #368–#381. Bullets above were pruned to the survivors and the
> post-#344 items finally got index lines. The items below remain the truth;
> this is only a map.


> **FREE-WINS SWEEP, 2026-08-09 (Owen: *"if those are done and haven't been
> closed, those are indeed free wins. Lets get those closed."*).** Eight items
> **closed in place**: **#80** (superseded by #251 2A), **#81** (removed by
> #238), **#130** (Owen closed it 2026-07-31 — the header lagged nine days),
> **#149** (already satisfied; used this session), **#161** (a "recommend
> closing" that sat unactioned since 2026-08-01), **#187** (absent from the
> handler, upstream), **#242** (delivered as #251 2A), **#256** (shipped
> 2026-08-05). They stay in this file until the archive pass moves them
> verbatim — closed items migrate at cleanup passes, not instantly.
>
> **Three deliberately NOT closed, and the reason matters:** **#250** and
> **#252** are shipped but each owes one residual (250-D's island watch; the
> Voice-card accent, bar 252R-A pre-registered but NOT STARTED), and **#254**
> is a WATCH with a newly
> identified mechanism. **An item does not close while a residual is
> outstanding, even when the headline work shipped** — that is the same rule
> that keeps #257 and #297 live on a failed bar.
>
> **Why eight items could be closed in one sitting with no code:** the board
> over-reports open work. Six of these were queued as *fresh lanes* by the
> 2026-08-09 sweep on the strength of their headers alone. The documented
> failure mode in this file is headers that look CLOSED while work remains;
> **this is the reverse, and it wastes lanes just as efficiently.**
>
> **SECOND PASS, 2026-08-11 (Owen: *"update the free wins"*) — five more, and
> every one of them was stale by ≤2 days rather than by weeks.** **#300** and
> **#319** both still read `NOT STARTED` in their headers AND their index lines
> while their own bodies carried `✅ FIXED 2026-08-10 … GATE: PASS` (merged
> together as PR #297); **#315** read *"Awaiting review/merge"* after PR #302
> merged it; **#296**'s C1 re-land read *"IN FLIGHT … NOT yet verified"* after
> PR #298 merged it with all six bars MET; **#306** wore a 🔧 two days after
> its own O8 block declared it fully closed. **All five are corrected in place
> and none needed code.** #184/#185 index lines also caught up with the
> 2026-08-10 code read that promised it.
>
> **The pattern to notice: a lane's LAST commit updates its entry BODY and
> stops.** The header and the index line are written by the lane that OPENS the
> work and nothing re-reads them at close, so the freshest, most-verified
> entries in the file are exactly the ones whose top line lies.
>
> **SWEPT THE SAME DAY — all five moved verbatim to `OPEN_ITEMS-ARCHIVE.md`
> (archive sweep 3), INDEX lines dropped with them. Live 128 → 123, archive
> 202 → 207, total unchanged at 330; the two files verified disjoint and no
> item renumbered.** Correction to this box's own first draft, which claimed a
> thirteen-item archive backlog: **the eight items above were already swept**
> by `5dd928a` (*"archive sweep 2 — move 20 closed items verbatim"*) on
> 2026-08-10, and the sentence promising they would *"stay in this file until
> the archive pass"* had itself gone stale. The backlog was five, and it is
> now zero. **Checking the archive for the numbers took one command; the
> paragraph asserting they were still here was written from this file alone.**

---

## 396. 🔉 VOICE IS TOO SENSITIVE — it picks up more than it should, on BOTH engines — **OWEN, 2026-08-22 ~03:1x, from the first working realtime session: *"Its very sensitive, and picked up a lot. I wonder if we can do anything about that as a fine tuning measure for both local and realtime."* FILED per #268 the minute it was raised. **OWEN CHARACTERISED IT THE SAME NIGHT: room/TV noise transcribed word-for-word (threshold), and mutual cut-offs (end-of-turn eagerness) — two DIFFERENT mechanisms, and the threshold one needs `server_vad`, a type #383 hardcoded out of reach. Self-barge-in untested and the negative is contaminated. Owen wants the knobs USER-adjustable. **LOCAL PIPELINE READ 2026-08-22 AM (396-C): the two engines do NOT share a fixable cause — on local, fault 1 has NO knob at all (`SpeechDetector` gates on speech-PRESENCE, and a TV is speech; the obvious `.low` fix is backwards AND the wrong mechanism), and fault 2's author is undecided between our 1.35 s watchdog and Apple's finalizer — a log line that ALREADY SHIPS decides it. No knob moved.** NOT STARTED as a build.** **⟵ HEADER CORRECTED 2026-08-23 (stale-header sweep): 396-B BUILT + deployed to BOTH hosts 2026-08-22 and the local pipeline is characterised; the TUNING lane is what remains unstarted.**

**Raised as a thought, not a request** — filed anyway because a perception noted
once at 3am is exactly what a tracker is for, and because #383 shipped the very
knobs this would turn.

### 🔴 MEASURE FIRST — "too sensitive" names a feeling, not a mechanism

At least four different faults produce the same complaint, and they take
opposite fixes:

1. **Room noise opens a turn** — the activation threshold is too low.
2. **It cuts the user off mid-sentence** — end-of-turn is decided too eagerly;
   the user is still talking.
3. **It hears ITSELF and interrupts its own reply** — self-barge-in, which is
   **#138's territory**, not a threshold at all.
4. **Transcription picks up background speech** the user did not address to it.

**Turning a threshold down when the real fault is (3) makes it worse.** A
tuning lane that starts by adjusting knobs will chase its tail, so the first
deliverable is a characterisation: which of these is actually happening, from a
recorded session rather than from memory of one.

### The knobs that exist, realtime side

**They are HARDCODED as of #383, and that is a regression this entry should
fix regardless of the tuning outcome.** `talaria/voice.py` writes:

```python
"turn_detection": {"type": "semantic_vad", "eagerness": "medium",
                   "create_response": True, "interrupt_response": True}
```

The retired connector carried the same values as **configuration**
(`RealtimeTalkConfig.turn_detection_type / create_response / interrupt_response`,
plus `voice` and `preferred_models`). The re-home ported the behaviour and
dropped the configurability — nobody asked for that, it was simply not part of
the port. **Restoring it is the cheap half of this item and is worth doing even
if the defaults turn out to be right.**

What the provider offers, for the record:
- **`semantic_vad`** takes an `eagerness` (this ships `medium`) — lower waits
  longer before declaring the turn over, which is the knob for fault (2).
- **`server_vad`** instead takes `threshold`, `prefix_padding_ms` and
  `silence_duration_ms` — `threshold` is the knob for fault (1), and this
  session type is not currently reachable at all because the type is fixed.
- **`interrupt_response: True`** is what lets incoming audio cut the assistant
  off. If the fault is (3), this is the line, not the threshold.

### The local side is UNREAD — ✅ **READ 2026-08-22 AM; see the dated block below**

`NativeVoicePipelineService`'s endpointing has not been looked at. **Do not
assume the two engines share a cause** — they share a symptom, and #383 just
finished demonstrating how expensive that assumption is (three mechanisms died
on #394 before the right one). Characterise each separately.

### 🎯 Bars — pre-registered, before any knob moves

- **396-A (characterise before tuning).** Name which of the four faults is
  occurring, per engine, from a recorded session. A lane that opens by changing
  a value has skipped this.
- **396-B (the realtime knobs become configuration again).** Whatever the
  tuning answer, `turn_detection` stops being a literal in `voice.py`. Ported
  behaviour that quietly lost its configurability is a regression to repair on
  its own merits.
- **396-C (both engines, measured separately).** One symptom is not evidence of
  one cause.
- **396-D (no silent default change).** If a default moves, the entry records
  the before/after values and the session that justified it — sensitivity is
  subjective, and an unrecorded tweak cannot be argued with later.


> **📋 2026-08-22 ~03:2x — OWEN CHARACTERISED IT, unprompted, in one message.
> 396-A is largely answered for the realtime engine before the lane opened.**
>
> Verbatim: *"room noise, tv noise were picked up, ever word. I cut it off and
> it cut me off. I didn't see self interrupting yet, but I started pausing
> everything to test — just to get through it. I bet if I turned the volume up
> though."*
>
> Against this entry's four faults:
>
> | fault | verdict |
> |---|---|
> | **1. room noise opens a turn** | **CONFIRMED** — TV audio, and *"every word"* transcribed |
> | **2. end-of-turn too eager** | **CONFIRMED, and mutual** — *"I cut it off and it cut me off"* |
> | **3. self-barge-in (#138)** | ~~NOT OBSERVED — and the negative is CONTAMINATED.~~ **✅ CONFIRMED 2026-08-22 PM, un-suppressed, on the first OJAMD session** — *"it interrupted itself to begin with, but then carried on a full conversation afterwards."* **The contamination call was right**: treating the earlier absence as evidence would have closed a live fault. Recorded at **#138**, whose item this is — and it is START-OF-SESSION ONLY now, where July's was every reply, which points at AEC convergence rather than any threshold. |
> | **4. background speech transcribed** | **CONFIRMED** — same evidence as 1 |
>
> ### 🔴 The lead this points at, and it is not an eagerness tweak
>
> **`semantic_vad` has no activation threshold.** It takes an `eagerness` — how
> quickly it decides the user has *finished* — which addresses fault 2 and does
> nothing for fault 1. The threshold knob (`threshold`, `prefix_padding_ms`,
> `silence_duration_ms`) belongs to **`server_vad`**, a turn-detection type this
> build cannot reach at all, because #383 hardcoded `type: "semantic_vad"`.
>
> So the two confirmed faults likely need **different mechanisms**, and one of
> them needs a session type that is currently unreachable. **A lane that opens
> by lowering `eagerness` will fix the interruptions and leave the TV in the
> transcript.**
>
> ### 🧭 OWEN'S DIRECTION: make them USER-adjustable, not just host-configurable
>
> *"If they're configurable, we may want to think about making them user side
> adjustable for different situations, etc."*
>
> **This widens 396-B.** That bar restored host-side configuration; Owen is
> asking for a user-facing control, and his reason is the right one — the
> correct sensitivity is not a property of the install, it is a property of the
> ROOM. A quiet office and a room with a TV want different answers, and the
> person who knows which is which is holding the phone.
>
> Scope is his call and NOT decided here. The obvious shapes: a coarse picker
> (Quiet / Normal / Noisy) mapping to a small set of vetted values, versus
> exposing raw knobs. **The coarse form is the one worth arguing for** — a raw
> `threshold` slider is a control almost nobody can turn correctly, and this
> entry's own four-faults table is the evidence that even naming the symptom is
> hard. **396-D still binds: no default moves without recording before/after.**
>
> ~~**Still unread: the local pipeline.** Owen reports the symptom on both, but
> only the realtime side has been characterised.~~ **READ 2026-08-22 AM — next
> block. It did not go where this one assumed.**


> **🔬 2026-08-22 AM — THE LOCAL PIPELINE, READ. 396-C's warning was right: the
> two engines do NOT share a fixable cause, and the naive fix is BACKWARDS on
> this one.** Source read only — no device, no knob moved.
>
> Three values are hardcoded in `NativeVoicePipelineService.swift`, and they
> map onto the four faults very differently from the realtime side:
>
> | # | local site | what it actually governs |
> |---|---|---|
> | 1 | `SpeechDetector(detectionOptions: .init(sensitivityLevel: .medium))` — `:1102` | **NOT the activation threshold.** See below. |
> | 2 | `endpointSilence = 1.35` — `:39` | the **fallback** endpointer only |
> | 3 | `SpeechTranscriber(preset: .progressiveTranscription)` — `:1015` | volatile-vs-final REPORTING, a UX contract, not a sensitivity |
>
> ### 🔴 `SpeechDetector` cannot fix fault 1, and turning it "down" makes it worse
>
> Read from Apple's own documentation rather than inferred from the name —
> which matters, because the obvious move (*"it's too sensitive, so lower the
> sensitivity"*) is wrong twice over:
>
> - **The direction is inverted.** `.low` is the *more **forgiving*** model;
>   `.high` is *more **aggressive***. Aggressive means it DROPS more audio. So
>   the pickup-reducing direction is `.high`, not `.low`.
> - **The mechanism is the wrong one anyway.** `SpeechDetector` "asks *is there
>   speech?*… saving power otherwise used by attempting to transcribe what is
>   likely to be silence." It is a **power optimization that gates on
>   speech-presence** — and **television dialogue IS speech.** No value of this
>   enum rejects a talking TV. It would help against a fan, traffic or
>   keyboard; it cannot help against the thing Owen actually reported.
>
> **So on the local engine, fault 1 has NO knob.** Not a hardcoded one — none.
> A VAD answers *is someone speaking*, and the question this fault needs
> answered is *is it **you***, which no Speech API on this SDK exposes. The
> honest options are all product decisions, not tuning: push-to-talk, a
> near-field/level gate we'd have to build, or accepting it.
>
> ### Fault 2 is OURS or APPLE'S, and one already-shipped log line decides which
>
> `endpointSilence = 1.35` is documented at its own definition as a **fallback**
> that fires *"only when the VAD/finalization path misbehaves"* — primary
> endpointing is the transcriber's own finals. So a local cut-off has two
> possible authors, and they take opposite fixes:
>
> - **ours** → the 1.35 s watchdog fired early; raising it is a real fix;
> - **Apple's** → `SpeechTranscriber` finalized; **we have no knob at all**, and
>   the only lever is the preset, which is a UX contract (dropping volatile
>   results would take the live text away).
>
> **The discriminator already ships, at `.notice`, on every device build:**
> `fallback endpointer fired (no final from transcriber)` (`:462`). Correlating
> that line against the timestamps of a cut-off answers 396-A for the local
> engine with **no new instrument and no code change** — which makes it the
> cheapest measurement on this entry and the one that should happen first.
>
> ### Fault 3, both engines: AEC is already on, and local barge-in has no switch
>
> Both engines set `AVAudioSession` mode **`.voiceChat`** (`:995`,
> `LiveVoiceSessionService:696/743`) — the system voice-processing chain, i.e.
> echo cancellation is already engaged. That is consistent with Owen not
> observing self-barge-in, and it *weakens* — does not kill — the
> louder-volume hypothesis, since AEC degrades as the speaker approaches
> clipping.
>
> Worth recording for whoever takes fault 3: realtime has
> `interrupt_response: True`, a flag that can be turned off. **Local has no
> equivalent** — `commitUserUtterance` cancels an in-flight `turnTask`
> unconditionally whenever a final lands (`:679`). Making local barge-in
> optional is a code change, not a configuration one.
>
> ### What this does to the item's shape
>
> **396-B was written as "restore the realtime knobs to configuration". It
> cannot be symmetrical**, because the local engine's knobs do not address the
> confirmed faults:
>
> | fault | realtime | local |
> |---|---|---|
> | 1 room noise | real knob (`server_vad.threshold`), behind an unbuilt session type | **no knob exists** |
> | 2 end-of-turn | `eagerness` — hardcoded literal, easy | ours (1.35 s) *or* Apple's — **unmeasured; one log line decides** |
> | 3 self-barge-in | `interrupt_response` flag | structural, no flag |
>
> **Consequence for Owen's user-adjustable direction:** a Quiet/Normal/Noisy
> picker can be made to mean something real on realtime and would be **partly
> cosmetic on local**, where only the end-of-turn half has anything to bind to.
> A control that silently does less on one engine than the other is worse than
> one that says so. That is a scope input, not a scope decision.

> **✅ 2026-08-22 15:23 — 396-B BUILT AND DEPLOYED TO THE MAC** on Owen's
> per-experiment go (*"config-ify + make `server_vad` reachable"*). Plugin
> commit `fb2e364`; 24 tests in `tests/test_voice.py`, 194 repo-wide.
>
> **No default moved, and that is asserted rather than promised.**
> `resolve_turn_detection()` under an empty environment returns a dict
> **byte-identical** to the literal #383 shipped, with a test saying so — if
> that test ever has to change, 396-D's before/after requirement has been
> triggered.
>
> | fault | before | now |
> |---|---|---|
> | 1 room noise | unreachable — type fixed to `semantic_vad`, which has no threshold | `server_vad` selectable, with `threshold` / `prefix_padding_ms` / `silence_duration_ms` |
> | 2 end-of-turn | literal `eagerness: "medium"` | `TALARIA_VOICE_EAGERNESS` |
> | 3 self-barge-in | literal `interrupt_response: True` | `TALARIA_VOICE_INTERRUPT_RESPONSE` |
>
> Three implementation choices worth keeping: keys are **type-scoped** (a
> `threshold` sent to `semantic_vad` is a provider error, which on the
> bootstrap path is a user with no voice session, so tuned-but-unselected
> values are ignored rather than smuggled); bad values **fall back loudly
> rather than raising**, for the same reason; and resolution happens **once,
> outside the model-fallback loop**, so two models can never receive two
> configurations. `talk_readiness` now reports the effective block as
> `turnDetection` — 396-D's spirit, since a value nobody can read is one
> nobody can notice has moved.
>
> ### 🟡 DEPLOY STATE — measured and inferred, kept apart
>
> Mac gateway bounced 15:33:30, **new listener PID 395, health 200 in ~5 s**,
> plugin reconnected (`✓ talaria connected`, 15:33:34). No headless episode —
> the #264 verify-immediately rule applied and passed on the first check.
>
> ~~**What that proves and what it does not.** … it is an **inference, not a
> wire probe** … **The wire proof arrives free in the device phase**.~~
> **✅ SUPERSEDED 2026-08-22 PM — BOTH HOSTS ARE NOW WIRE-PROVEN, and the
> phone was not needed for it.** The OJAMD session found a better instrument
> than waiting: `EnvelopeService.dispatch` resolves the handler **before** any
> auth check, so a deliberately BOGUS device token discriminates old code from
> new — old ⇒ `unknown_event_type`, new ⇒ `device_auth_mismatch` — with a
> nonsense verb as the control proving the discriminator can still say no.
> Run against both live listeners:
>
> ```
> talk_readiness         -> device_auth_mismatch     talk_session_end -> device_auth_mismatch
> definitely_not_a_verb  -> unknown_event_type   ← control
> ```
>
> **What this cost, stated because it is the reusable part:** the inference was
> sound and I stopped at it, having concluded no credential existed. The
> credential was never the question — `API_SERVER_KEY` was in hand the whole
> time, and dispatch's ordering made auth irrelevant to the measurement.
> **"I cannot measure this" deserved one more minute of reading than it got.**

### 📏 396-D's BEFORE RECORD — both hosts, measured 2026-08-22, identical

`voice.readiness()` is pure and takes an optional `hermes_home`, so it can be
evaluated out-of-process against the real config with nothing live touched:

```json
{ "ready": true, "hostOnline": true, "configured": true, "blockedReason": null,
  "selectedModel": "gpt-realtime-1.5", "voice": "ballad",
  "turnDetection": { "type": "semantic_vad", "create_response": true,
                     "interrupt_response": true, "eagerness": "medium" } }
```

**Byte-identical on the Mac and OJAMD**, and byte-identical to the literal #383
shipped. Three things settled at once: `turnDetection` really is carried in the
readiness payload; **no default moved**, measured on the hosts rather than
trusted from a unit test; and `configured: true` on both means the OpenAI key
is present on OJAMD, so the phone should not meet the "not configured" refusal.

**This is the row any future tuning is diffed against (396-D).** A lane that
moves a value without quoting these four fields has not met the bar.

> **Both hosts are at parity: `talaria-plugin` @ `fb2e364`.** OJAMD deployed
> 2026-08-22 15:54 (pull) / 16:09:32 (listener PID 47276), Discord back at
> 16:10:06, ~86 s of downtime, Hermes **0.20.5**.

**Cross-references:** **#383** (the re-home that hardcoded these), **#138**
(realtime self-barge-in — fault 3 is that item, not this one), **#18** (the
native pipeline), **#1** (voice transcripts).

> **⚖️ SCOPE RULED 2026-08-23 (Owen, decision pass): the COARSE PICKER.**
> Quiet / Normal / Noisy mapping to a small set of vetted `server_vad` values
> on realtime; raw knobs are not exposed. The asymmetry ships HONESTLY: on
> the local engine the control states plainly that (at most) end-of-turn
> responds — a control that silently does less on one engine than the other
> was the named hazard, and saying so is the ruled mitigation. Fault 2's
> author question (our 1.35 s watchdog vs Apple's finalizer; one shipped log
> line decides) is still the device row and still gates how the local half
> binds. Bars pre-register here before the lane writes code.

> **🎯 BARS 396-P-A…F — pre-registered 2026-08-23 late, before code (the
> coarse-picker lane; design mapped the same evening).** The shape: a
> `VoiceSensitivity` enum (`quiet`/`normal`/`noisy`, raw values persisted,
> default `.normal`), a three-segment row on `VoiceSettingsScreen` (the
> `GridDensity`/`AppLockGracePeriod` house pattern), the pick riding the
> `talk_session_create` payload as a `tuning` field (the `voiceVerb(extra:)`
> seam, `talk_session_end`'s precedent), and VETTED preset dicts resolved
> HOST-SIDE in the plugin (the app never composes `turn_detection`).
> **LOCAL BINDS NOTHING this lane** — the ruling's honest asymmetry: the
> picker's caption states that on the local engine (at most) end-of-turn
> responds and room-noise has no knob; both local values stay compile-time
> constants until the fault-2 author is measured (the device row).
> - **396-P-A (persistence).** The pick survives an encode→decode roundtrip
>   (raw values pinned; absent key → `.normal`). Encode is synthesized
>   (#400) — one CodingKeys case + one decode line is the whole persistence.
> - **396-P-B (the wire, RED-first).** `talkSessionCreate` carries
>   `"tuning": <raw>` — always, `.normal` included, so host logs show the
>   choice. Written RED against today's no-extra call; the protocol, the
>   `UnavailableVoiceTransport` stub, and the test fake widen in lockstep.
> - **396-P-C (host: sanitize + the default preserved).** Only the three
>   names are accepted; absent, junk, or non-string → the env-resolved
>   default, and `"normal"` ≡ absent BYTE-IDENTICALLY — extending 396-D's
>   no-default-moved contract, pinned by extending its existing test.
> - **396-P-D (host: presets are type-valid and vetted).** `quiet`/`noisy`
>   emit `server_vad`-scoped keys only (the type-scoped invariant), values
>   pinned by test and quoted in the result block per 396-D's
>   before/after requirement.
> - **396-P-E (capability honesty).** Readiness gains `"tunings":
>   ["quiet","normal","noisy"]`; the app decodes it into
>   `TalkReadinessInfo` (optional — nil means the host predates tuning, and
>   the picker's footnote SAYS so instead of implying effect; an old host
>   ignores the unknown payload field, so the session still mints — the
>   #383 hazard-5 honesty shape, no new failure mode).
> - **396-P-F.** Gates both repos (app lane-gate; plugin pytest). The
>   plugin DEPLOY rides Owen's per-experiment go (Mac first, then OJAMD,
>   per #383's precedent) — building and pushing the branch does not.

> **✅ 2026-08-23 ~22:10 — PLUGIN HALF BUILT AND DEPLOYED TO THE MAC on
> Owen's go ("You can deploy the plugin updates on the mac when you're
> ready. Permission to bounce the gateway granted").** Plugin main
> fast-forwarded `fb2e364` → **`e669549`** (196→201 pytest in the work
> clone; presets quiet `{server_vad, 0.4, 300, 500}` / noisy
> `{server_vad, 0.75, 400, 900}`, response flags from the same env
> resolution as the default; envelope plumbing mutation-checked). Live
> checkout pulled 22:10:23 (reflog), gateway bounced, **listener PID 21918
> up 22:10:42 — 19 s after the pull, so the process imported the new code
> (reflog-vs-start-time pin)**; bind won the #264 race first try; clean
> load (the register() hygiene arm prints only on failure and printed
> nothing — and per the 08-22 adjacency lesson, nothing else in the log is
> being attributed to the plugin). Dispatch proven alive both ways:
> bogus-auth `talk_readiness` → `device_auth_mismatch`, nonsense verb →
> `unknown_event_type`. **Honest limit:** the readiness `tunings` field is
> device-auth-gated, so its first LIVE observation (and the footnote
> disappearing) rides Owen's next Voice-settings visit. **OJAMD: not
> deployed** — rides a later `hermes plugins update` + bounce on its own
> go; until then OJAMD mints with its default and the app's footnote says
> so, which is the designed degrade.

> **📊 2026-08-23 ~22:50 — THE FIRST LIVE TUNED SESSION, Owen's own
> report, MAC PROFILE (so the preset was genuinely bound):** on **noisy**,
> *"it picked me and the tv up, but.. the tv is rather loud. At least it
> got me."* Reading: the preset did its job (reliable capture, no early
> turn-ends) and its structural ceiling is confirmed — `server_vad`'s
> threshold is an AMPLITUDE gate, and a loud TV clears any threshold that
> still hears the user; loudness cannot discriminate speakers (the same
> "a TV is speech" mechanism as the local engine's fault 1, one level up).
> The candidate discriminators are OS Voice Isolation mic mode
> (user-togglable in Control Center during a session — worth one try) or
> product shapes (push-to-talk). This also discharges "Owen's device look
> at the picker." The formal 396-D four-field quote still rides the
> runbook's 396-D card. **Side catch, #138-adjacent:** the live
> `~/.hermes/.env` measures ZERO `TALARIA_VOICE_*` lines (2026-08-23) —
> 138-E's arm-1 was reverted but the revert was never recorded; recorded
> here so #138-L's precondition reads CLEAN.**

> **✅ 2026-08-23 late — APP HALF MERGED (PR #361, squash `4ad8e3c1`).
> GATE: PASS 2482 / 14 / Release (count moved +4 — the wire, roundtrip,
> readiness, and copy-pin tests exactly).** 396-P-A RED-first (stubbed
> non-persisting decode), 396-P-B RED-first AND mutation-proven (the
> `extra` dropped → RED on the missing `tuning` key), 396-P-E both
> directions. The picker sits between the read-only model block and
> Read-Aloud; the honest-asymmetry copy is pinned by test. **THE TUNING
> LANE'S REALTIME HALF IS DONE end-to-end on the Mac profile** (app merged
> + host deployed); still owed on this entry: Owen's device look at the
> picker (next OTA carries it), the OJAMD deploy on its own go, 396-D's
> live before/after quote when a tuned session first runs, and the LOCAL
> half — which stays deliberately unbuilt behind the fault-2 author
> measurement (§3 device row 12), per the ruling.


> **📤 2026-08-26 evening — THE OJAMD BRIEF IS TRANSMITTED (Owen: "ojamd
> brief has been sent").** The brief on the share is the fresh
> `HANDOFF-OJAMD-2026-08-26-PLUGIN-DEPLOY-B4E8DFA.md` (targets 0.8.0,
> four commits — the superseded 08-24/b87cd6c version was NOT sent). The
> deploy is now in the OJAMD session's hands; a share watch is armed for
> its report file, and the Mac's same-day 0.8.0 deploy (pull + Restart
> Gateway; sidebar-confirmed; #224's picker unlocked live) is the
> precedent it follows. Post-deploy phone flips to score: the Voice
> tuning footnote (this entry's OJAMD arm) and the approvals picker
> (#224's OJAMD arm).

> **✅ THE OJAMD DEPLOY LANDED — same evening (report on the share,
> `HANDOFF-OJAMD-2026-08-26-REPORT.md`; a model report — measured and
> inferred kept apart).** `fb2e364 → b4e8dfa` clean ff-only (exactly the
> four commits), `plugins list` **0.8.0**, `pair-qr` listed / `pair`
> absent, listener pinned by START TIME (19:14:14 > the 19:09:46 pull),
> health 200 on 0.20.5, downtime **~3m14s** (~90s of it = harness
> permission blocks, §6 of the report). Probes: both
> `device_auth_mismatch`, control `unknown_event_type` — #396 AND #224
> code live-proven on OJAMD. **The floor silence was negative-controlled**
> (the checker fires on a fake 0.20.2 — tested, not assumed). The
> no-default-moves pin held ON HOST (`normal` ≡ no-arg, byte-identical).
> `qrcode` ABSENT on both interpreters as the brief anticipated —
> `pair-qr` will report actionably; nothing installed, nothing rendered.
> **Still Owen's: the two phone flips** (Voice footnote gone; #224 picker
> unlocked — both ready to check NOW), 241-E, the desktop relaunch
> (#346), each its own go. Procedure findings filed: the survivor-check
> self-match (CLAUDE.md corrected), the parent-kill-takes-child note,
> bluebubbles config-off with a 7-week fossil state row, and the phone's
> pre-existing `/v1/models` 401s → **#414**.

> **⟵ 2026-09-01 POINTER (hygiene sweep, #413 cross-reference):** of the
> two flips this block lists as "Still Owen's," **#413** (filed same day,
> 2026-08-26, from Owen's device pass) shows him selecting between the
> Noisy and Normal VOICE-TUNING presets and getting a real, measured,
> preset-independent effect (3/3 self-capture on BOTH) — evidence the
> tuning picker itself is live and bound, i.e. the "Voice footnote gone"
> flip. #413's text never names the host/profile, so this does not by
> itself pin the OJAMD arm specifically. The **#224 approvals-picker**
> flip is untouched by #413's evidence and remains open.

> **📎 2026-09-01 — WHAT THE ESCALATION READ OF THE VOICE CLUSTER LEAVES ON
> THIS ENTRY (synthesis under #138).**
> - **The local fault-2 discriminator has never fired in any archive.** All
>   ten archives on the Mac were searched for `fallback endpointer fired`:
>   zero hits. The only native-engine session in them (`talaria-cards`,
>   08-31 20:05:12–20:05:23, 11 s, four rows) shows no cut-off at all, so
>   its silence is not a measurement of fault 2. The LOCAL half stays
>   parked exactly where the ruling left it; the archives cannot advance it.
> - **396-Q (gap, filed):** the app never logs the tuning it mints with —
>   `talkSessionCreate(tuning:)` is silent — so #413's 08-26 sessions
>   cannot be attributed to Noisy vs Normal from the device log. One
>   ungated `.notice` at mint (`#396 tuning=<raw> engine=realtime`) closes
>   it; cheap enough to ride #138's V3 instrument lane.
> - **Fault 3 is decomposed, and the picker cannot reach it:** it is #138's
>   ONSET residual (every dirty first utterance lands ≤0.6 s after
>   `audio.started`); the threshold path is dead (138-E), `interrupt_response:
>   false` remains the blunt option, and the precise candidate is #138's
>   proposed onset gate (V5), which is a code change, not tuning.

> **📋 2026-09-01 night — 396-Q INSTRUMENT LANE OPENED (from the voice-cluster escalation, same night).** The escalation could not attribute #413's per-session phantom rate to a preset because **the app never logs the tuning it mints a realtime session with** — the picker's choice reaches the plugin as a request field and vanishes from the phone's own record. Bars pre-registered before code:
> - **396-Q-A:** at realtime session configuration the app emits ONE always-on `.notice` naming the preset requested (quiet/normal/noisy or the raw values) and the engine — pinned by a pure formatter test in the `VoiceInstrumentLogLineTests` pattern, RED-first, mutation-proven. [offline]
> - **396-Q-B:** the runbook's voice cards gain "quote the preset line" in their Record lists, so the next archive attributes rate to preset for free. [offline]
> - **396-Q-GATE:** lane-gate PASS. [Mac]

> **✅ RESULT 2026-09-02 (the 2026-09-01 night lane, run into the small hours)
> — 396-Q-A/B/GATE ALL MET.** Shipped with 198B-M in one PR; the gate line
> below covers both.
>
> **396-Q-A — the marker, verbatim:**
>
> ```
> #396 tuning preset=noisy engine=realtime values=host hostAccepts=[quiet,normal,noisy]
> ```
>
> Formatter `LiveVoiceSessionService.sessionTuningLogDetail(preset:engine:hostTunings:)`
> — `nonisolated static`, pure — at
> `Talaria/Services/Live/LiveVoiceSessionService.swift:1381-1393`, beside the
> #418/#419 pair. Emitted ONCE per realtime mint at
> **`LiveVoiceSessionService.swift:309`**, `.notice`, `privacy: .public`,
> un-gated.
>
> **`values=host` is the honest half, and the brief was right to insist on
> it.** The app composes no `turn_detection` block — 396-P's ruled design
> resolves the vetted `server_vad` numbers HOST-side and the app sends only a
> NAME (`talkSessionCreate(tuning:)`). So the line names where the values live
> instead of printing a threshold the phone never sent. A line quoting
> `threshold=0.75` from the app would be this project's own
> marker-its-component-cannot-emit scar, inverted into a number it cannot
> vouch for.
>
> **`hostAccepts` closes the second attribution hole.** The pick only binds if
> the host's plugin advertises `tunings` (396-P-E); a host that predates it
> ignores the field entirely, and a session logged `preset=noisy` on such a
> host ran on the host default. `hostAccepts=unknown (host predates tuning)`
> says so on the line, so a future archive cannot read an unbound pick as a
> bound one. That is the same honesty the picker's own footnote carries — and
> it is the reason the formatter takes three arguments rather than the two the
> bar's example named.
>
> **One implementation detail worth pinning in prose:** the provider is read
> ONCE into a local and that same value feeds both the log and the wire
> (`:308-310`), so the line can never describe a different pick than the one
> that shipped. Reading `voiceTuningProvider()` twice would have been the
> obvious spelling and a latent lie.
>
> **RED-first:** three pins written against a stub returning `"#396 tuning"` —
> part of the **13-issue** RED recorded in #198B's block above
> (`Expectation failed: line.contains("preset=noisy")`,
> `…("engine=realtime")`, `…("values=host")`,
> `…("hostAccepts=[quiet,normal,noisy]")`). GREEN after: **14/14**.
>
> **MUTATION (the bar's own: drop `preset`).**
> `"#396 tuning engine=\(engine) values=host hostAccepts=\(accepts)"` ⇒
> **2 issues, both 396-Q's** — `line.contains("preset=noisy")` at `:206` and
> `line.contains("preset=normal")` at `:220`. The three 198B-M pins stayed
> GREEN, so this mutation ISOLATES too. Restored.
>
> **396-Q-B — the Record line, for the orchestrator to add to the runbook's
> voice cards** (they are republished, not in this repo — so the exact text
> lives here):
>
> > **Record:** quote the **`#396 tuning preset=`** line for the session —
> > the whole line, e.g.
> > `#396 tuning preset=noisy engine=realtime values=host hostAccepts=[quiet,normal,noisy]`.
> > One is emitted per realtime session start; it is `.notice` and un-gated,
> > so `sudo log collect --device-udid <UDID>` sees it as well as a corded
> > read. Predicate:
> > `subsystem BEGINSWITH "org.aethyrion.talaria" AND eventMessage CONTAINS "#396 tuning preset="`.
> > **If `hostAccepts=unknown` the host's plugin predates tuning and the pick
> > did NOT bind** — that session is not attributable to a preset and must not
> > be scored as one. If the line is absent, the build predates 396-Q or the
> > session was NATIVE, not realtime (the native engine binds no preset and
> > emits none).
>
> **GATE (both lanes — 198B-M and 396-Q shipped together):**
> `TALARIA_SIM_NAME=CC-lane-3 scripts/mac/lane-gate.sh` — **GATE: PASS on
> 24A5423a**, **2840** Swift Testing tests / **15** XCUITest / Release build
> clean, no Swift compile errors in Release. No new Swift files, so no
> `xcodegen generate` was owed.
>
> **THREE runs, and the count moved between them for two different reasons
> — both stated, because a bare "+6" would be ambiguous here.**
>
> | run | tree | verdict | Swift Testing |
> |---|---|---|---|
> | 1 | pre-rebase | **FAIL (4 checks)** — real, see below | 2838 / 2 issues |
> | 2 | pre-rebase, pin repaired | PASS | **2838** = baseline **2832 + 6 exact** |
> | 3 | rebased onto `aec772ab` | PASS | **2840** — main itself gained 2 while this lane ran |
>
> So the lane's own contribution is **+6 exact** (the three 198B-M pins and
> the three 396-Q pins), measured on run 2 against the stated 2832 baseline;
> run 3's 2840 is that same +6 on a baseline that had moved to 2834 under
> four commits that merged mid-lane. Re-gated after the rebase because those
> commits touched COMPILED inputs (`LocalChatBackend+IntentRouting.swift`,
> `DeviceToolBeltTests.swift`, the privacy-manifest tests) — a docs-only
> move would not have owed it.
>
> **Run 1's failure was real, not a flake** — the #399 structural-pin
> regression written up in #198B's block above; 2 issues, both
> `deactivationIsSpelledOnlyInsideTheInjectableSeam`. The known #219
> XCUITest flake did **not** appear in any of the three runs.
>
> **The rebase was checked for #424's hazard** (an invariants checker that
> passed nine times over a tracker missing an entry): entry headers were
> counted and set-diffed before and after — 63 on `origin/main`, 63 after,
> **empty difference**, no entry dropped. `python3 scripts/oi-invariants.py`
> run unpiped, exit 0, before and after.
>
> **XCUITest count verified by hand rather than taken from the script:** 30
> `Test Case '-[` lines = 15 started + 15 passed, **0 failed**, over 14
> distinct names — `TalariaUITestsLaunchTests.testLaunch` legitimately runs
> twice (it is parameterised per launch configuration), which is why 15
> executions and 14 names are both correct and neither is a miscount.
>
> **What is still open on #396** is unchanged by this lane: the LOCAL half
> (parked behind the fault-2 author measurement), 396-D's live before/after
> quote, and #413's per-session preset attribution — which is now
> *possible* for the first time, on the next tuned archive, and that was the
> whole point.
>
> **MERGED 2026-09-02 — PR #416, squash `9dca3bad`** (one PR with 198B-M;
> lane branch left in place per the merge instruction).

## 392. 🔴 A DECLINED CALENDAR EVENT IS REPORTED AS THE CALENDAR REFUSING IT — *"your calendar didn't accept the request"* when the user declined the card — **MEASURED 2/30 ON DEVICE 2026-08-21 (#199A's re-run), CALENDAR-ONLY. Spawned rather than kept inside #199A, whose own claim is refuted. NOT STARTED; bars below.** **⟵ HEADER CORRECTED 2026-08-23 (stale-header sweep): the INSTRUMENT is built + merged 2026-08-23 (PR #353) with NO treatment elected, per Owen's route; the n≥30 device run is what remains.**

**The measurement** (`planning/reports/2026-08-21-199a-decline.json`, decline
battery, 30 action declines, every one reached):

> *"It looks like the event wasn't created — **your calendar didn't accept the
> request**. Let me know if you'd like to try again or adjust something."*

> *"It seems the event **couldn't be added** — let me know if you'd like to try
> again or adjust anything."*

**Both are false in the same way.** The calendar never saw the request. The
user declined the confirmation card, and `performCreate` returned the plain
sentence *"The user declined — no calendar event was created."* The model was
told who declined, and reported that EventKit refused.

**🔴 CALENDAR-ONLY, and that is the finding rather than a detail.** `remind`
and `alarm` produced **20 declines with zero misattributions**; both instances
are among the **10 calendar declines**. A fix aimed at "declines" in general
would be aimed at the wrong surface. Candidate causes, none elected: the
calendar tool's richer argument set, its description, or simply that "a
calendar rejected an event" is a more plausible-sounding story than "an alarm
rejected an alarm."

**Why this is its own entry.** #199A was filed for a decline blamed on a
CONTACT; that shape is now refuted at 0/30. This is the same family — a decline
blamed on something that is not the user — with a different scapegoat, and
keeping #199A open under a changed meaning is how an entry stops describing
what it is named for. It is also #180's family (a claim about state the app did
not observe) and shares #340's shape (a confident sentence about an artifact
that does not exist).

### 🎯 BARS 392-A..D — pre-registered before any code

- **392-A (the control must reproduce).** ≥1 misattribution in 10 calendar
  declines on an unmodified build, in the SAME run as any treatment. At 2/10
  the base rate is low enough that a treatment arm could score 0 by luck, so
  **n ≥ 30 calendar declines per arm** — a lesson taken directly from #372(c),
  which ran tonight at a 3% base rate and could conclude nothing.
- **392-B (the fix must not silence the honest sentence).** Production already
  returns *"The user declined — no calendar event was created."* A treatment
  that suppresses the model's follow-up entirely trades a false attribution for
  no answer, which is the trade #385's 385-B was written to refuse.
- **392-C (remind/alarm must not regress).** They are at 0/20 today. Any
  calendar-aimed change is measured against them as an untouched control, in
  the same run.
- **392-D (scored from TEXT, and the reason is recorded).** Auto-decline means
  no artifact can exist, so text is all there is and there is nothing for it to
  lie against — #202C's justification, which #199A used for the same reason.

> **✅ ROUTED 2026-08-22 PM (Owen): INSTRUMENT AND MEASURE, ELECT NOTHING.**
> Verbatim: *"I think this is really instrument and measure more. It's been
> weird, and we thought we had it before. Better to be sure after all this time
> invested."*
>
> **The route is right for a reason worth stating:** 392-A already demands
> n ≥ 30 calendar declines per arm, and the entry's own 2/10 is too thin to
> score any treatment against. Electing a cause now would spend a device run
> learning what is already recorded. Measuring first buys a real denominator.

> **✅ 2026-08-23 — THE INSTRUMENT IS BUILT. No treatment elected, by design.**
>
> **The runnable half already existed** — `InstrumentRegistry`'s `decline` spec
> (auto-decline, `declineBatteryCells = [.armed]`, no treatment arm) over the
> default prompt set, which already carries **calendar / remind / alarm**, so
> 392-C's untouched controls ride along for free. What was missing was scoring.
>
> **`DeclineAttributionScorer`** (Swift, 9 tests) classifies a reply as
> `attributedToUser` / `attributedToTool` / `actorUnnamed` / `unscorable`, and
> is pinned against the **verbatim strings the device emitted**. Three
> judgement calls are recorded rather than left implicit:
>
> 1. **User attribution WINS over a tool phrase.** *"You declined, so the event
>    wasn't created"* contains `wasn't created` — a fact stated after naming
>    the right actor. Scoring it as the defect pads the rate with correct
>    answers, which manufactures a problem rather than missing one.
> 2. **`"couldn't be added"` counts as tool attribution.** It names no actor,
>    but **the second real device instance was exactly that shape** — a scorer
>    hunting only for the word "calendar" would catch one of two known
>    instances and halve the rate it exists to measure.
> 3. **Unscorable replies are excluded from the denominator**, not counted
>    clean — otherwise a run where the model wanders off-topic reads as an
>    improvement (#215's sibling lesson: an instrument with no error bucket
>    reports its own failures as behaviour).
>
> **Why the scorer is written BEFORE the run**, and this is the part Owen's
> route actually buys: a classifier authored after seeing replies can be
> nudged, sentence by sentence, into agreeing with whatever came out. Fixed in
> advance, it can disagree with us.
>
> ### The two-implementation problem, and the check that closes it
>
> Scoring happens on the Mac over an exported run record, so the executable is
> **`scripts/mac/score-decline-attribution.py`**. That is a second
> implementation of one classifier — the shape that made two date decoders
> drift until they disagreed about a boundary case.
>
> **`score-decline-attribution-test.py` PARSES the Swift file and asserts the
> three phrase lists match, element for element.** Cheaper and harder to fool
> than a shared fixture, which can go stale against both sides. **Verified to
> fail** (#218's rule): inserting one phrase into the Swift list turns it RED
> and names which side moved. 7 behaviour checks + parity over 48 phrases,
> ~1 s, no build.
>
> ### 🔴 What was deliberately NOT done
>
> - **No `battery:` line change.** That shape is depended on byte-identically
>   by four instruments across eight call sites and by `score-eras.py`; #297
>   hit the same wall and inlined its own loop rather than touch it. Same
>   precedent, same reason — which is why scoring reads the export instead.
> - **No treatment cell.** Owen's route. The next step is a RUN, not a fix.
>
> **OWED: the device run** — `--instrument decline`, n ≥ 30 calendar declines,
> auto-decline so nothing is written and nothing needs reaping.

**Cross-references:** **#199A** (the refuted parent, and the run that found
this), **#180** (honest degradation), **#340** (a confident sentence about a
non-existent artifact), **#343** (the governor fix that made the denominator
real), **#372(c)** (tonight's lesson on base rates and power).

> **✅ REPRODUCED / ⚠️ UNDERPOWERED — the device run happened 2026-08-27 evening
> (21:04–21:12 CDT).** Device `whoGoesThere`, Debug build **3125**, iOS
> **`Version 27.0 (Build 24A5424a)`**, `endedCleanly: true`, 120 trials
> (30 per prompt × 4), `thermal: serious` start and end. Artifact
> `~/.talaria-instrument-runs/20260828T020435Z-decline`; scored with
> `scripts/mac/score-decline-attribution.py` (reads the run record — no
> logarchive needed).
>
> | surface | trials | scorable | **tool** | user | unnamed | rate |
> |---|---|---|---|---|---|---|
> | **calendar** | 30 | **18** | **2** | 14 | 2 | **11.1%** |
> | alarm | 30 | 21 | 0 | 21 | 0 | 0.0% |
> | remind | 30 | 20 | 0 | 20 | 0 | 0.0% |
> | haiku | 30 | 1 | 0 | 1 | 0 | 0.0% |
>
> **✅ THE REPRODUCTION BAR IS MET, on both of its halves.** ≥1 misattribution
> among the calendar declines (**2**), and **remind/alarm stayed exactly 0** —
> the calendar-only contrast, which IS the finding, holds on beta 7. The defect
> is real and is not an artifact of the original 2/10 observation.
>
> **⚠️ THE POWER BAR IS NOT MET, and this is recorded as a MISS rather than
> rounded away.** The card asked for **30 calendar declines**. Thirty calendar
> *trials* produced only **18 scorable** ones, and the scorer still emits its own
> `392-A needs n >= 30 CALENDAR declines per arm` warning on this very run. So
> the clause *"a future treatment has its denominator"* is **NOT yet true**.
> - **The conversion rate is the number to plan with: 18 scorable / 30 trials =
>   60%.** Reaching 30 scorable calendar declines needs **~50 trials**, so a
>   future run should pass `--trials 50` at minimum.
> - This is exactly #372(c)'s lesson arriving on schedule — thin scorable n is
>   the failure mode this instrument was built to stop being surprised by.
>
> **Consistency note, kept separate ON PURPOSE:** the same evening's pre-OTA
> subset ran `decline --trials 10` and scored calendar **1/4 scorable
> misattributed**, alarm 0/3, remind 0/8 — same direction, same surface. The two
> runs are **NOT pooled** into a combined rate: different trial counts, different
> thermal states (`fair` vs `serious`), and pooling to manufacture power is the
> move that would make the underpowered verdict above disappear without any new
> data.
>
> **Also not pooled:** #372's device run reports `declineAttributedToTool` of
> 2/54 (control) and 3/59 (`.required`) on the SAME evening. That is the
> card-clause surface, not this one — a different instrument with a different
> denominator. Recorded here only so a future reader does not discover it and
> assume it corroborates.
>
> **OWED:** a `--trials 50` re-run to earn the treatment denominator. No
> treatment exists by Owen's ruling, so there is no urgency — but the next run of
> this instrument should be the bigger one, not another 30.

> **🟡 2026-09-01 03:09Z — THE `--trials 50` RE-RUN. THE DEFECT IS EMPHATICALLY
> REPRODUCED AND THE CALENDAR-ONLY ASYMMETRY IS NOW SIGNIFICANT — BUT 392-A's
> n≥30 IS STILL MISSED ON THE CALENDAR ARM, AND THAT IS RECORDED AS A MISS, NOT
> ROUNDED UP.** Build **3147**, device `24A5430a`, `endedCleanly: true`,
> 200 trials (50 × 4 surfaces), artifact
> `~/.talaria-instrument-runs/20260901T030906Z-decline/`.
>
> | surface | n | scorable | → tool | → user | unnamed | misattribution |
> |---|---|---|---|---|---|---|
> | **calendar** | 50 | **25** | **5** | 12 | 8 | **20.0%** |
> | remind | 50 | **32** | 0 | 32 | 0 | **0%** |
> | alarm | 50 | 26 | 0 | 26 | 0 | **0%** |
> | haiku | 50 | **1** | 0 | 1 | 0 | 0% |
>
> **✅ The reproduction bar is MET, decisively:** 5 misattributions against a
> bar of ≥1. Specimen, verbatim from the artifact:
> *"Looks like **the calendar didn't create the event**. Would you like me to
> try again?"* — the calendar never saw it.
>
> **🔬 WHO DECLINED, and why the answer does not weaken the finding (corrected
> 2026-09-01 — Owen: *"I didn't decline anything, I was hands off"*, and he is
> right; the first write-up of this block said "the user declined the card",
> which was simply wrong about a run that is unattended by design).** The
> decline came from the instrument: §05 runs are `confirmationMode:
> .autoDecline`, and `InstrumentConductor` sets
> `confirmationCenter.autoDeclineForBattery` for the run.
>
> **The substitution is sound where it matters.** That flag short-circuits the
> CARD UI but resolves to **`return .declined`**
> (`ToolConfirmationCenter.swift:235-239`) — *the same `Decision.declined` a
> real tap produces* — so the action tool hands the model the identical
> "user declined" result either way. #392's defect is about what the MODEL does
> with that result, not about the card, so a synthetic decline exercises
> exactly the path under test.
>
> **What it does NOT exercise, stated so nobody over-claims:** the card's own
> rendering and the human tap. A defect living in the UI rather than in the
> model's reading of the tool result would be invisible to this instrument.
>
> **✅ The calendar-only contrast is now STATISTICALLY SOLID**, which is what
> the extra power actually bought: calendar 5/25 vs **remind 0/32**
> (p = 0.0127), vs alarm 0/26 (p = 0.0226), vs the two pooled 0/58
> (**p = 0.0018**). And **remind's arm now clears n≥30 on its own** (32), so its
> zero is properly powered rather than merely small. The asymmetry IS the
> finding, and it is no longer resting on 2 events.
>
> **🛑 392-A REMAINS MISSED.** The bar is n≥30 **scorable** per arm; the
> calendar arm returned **25** at 50 trials (50% conversion — 60% last run, so
> the earlier estimate was optimistic). Alarm is 26. **A missed bar is a
> falsification, not a redefinition** — the honest statement is that the
> asymmetry reached significance *anyway*, so further trials would refine the
> RATE rather than decide the FINDING. **~60 trials would clear it** at the
> observed conversion.
>
> **⚠️ Three caveats, stated rather than buried:**
> - **The rate is 20% here vs 11.1% (2/18) on 08-27.** Do NOT read that as
>   worsening — the intervals overlap heavily and n is small on both.
> - **`haiku` returned 1 scorable of 50** (49 unscorable). That surface is
>   effectively not measuring anything and should be explained before it is
>   quoted; it is not evidence of good behaviour there.
> - **No per-trial thermal is stamped in this artifact**, so unlike the 08-27
>   run this one carries no thermal reading — recorded as absent rather than
>   assumed nominal (#215's discipline).
>
> **Device runtime: `Version 27.0 (Build 24A5430a)`** — a NEW build, and #398-A's
> timeline gains a fifth row (`24A5424a` was the 08-27 measurement). Read free
> off the artifact's own `osVersion`, exactly as #398-A prescribes.

> **📋 2026-09-04 — PLAN WRITTEN (the difficulty sweep): `planning/superpowers/plans/2026-09-04-392-calendar-decline-wording.md`.** The 09-01 run made the calendar-only asymmetry significant (5/25 vs 0/58 pooled, p = 0.0018); the route was measure-only and nothing has been elected. The plan elects ONE treatment for Owen's word — the decline tool result names the ACTOR (*"The user cancelled the confirmation card — no event was created and the calendar was never changed."*) as a DEBUG cell on the calendar surface only — and measures it against the control at 60 trials/cell (≈ n ≥ 30 scorable at the measured ~50% conversion), promotion only on a met bar and Owen's read of the sentence. Bars 392-T-A..C in the plan. Index: `planning/2026-09-04-difficulty-sweep.md`.

## 56. 🔧 Wave 2 Issue E (GitHub #6) — "Ask Hermes" App Intent — MERGED (PR #11), core device-verified 2026-07-11; sub-checks remain

**Device sub-checks 2026-07-20 (Session S launch sweep, seed b3):**
(1) **Long-run hand-off: MOSTLY PASS.** 25s budget hand-off graceful, snippet correct
(screenshot on file: “Hermes is still working on it. Open Talaria to watch it finish” +
WORKING card). Wrinkle — the Ask lands in the CURRENT cached conversation (by design, via
ChatStore.sendMessage), which during the sweep meant appending to a Spotlight-tested thread.
**Owen leans: Siri asks should open a NEW chat.** Design decision → dispatchable micro-lane
(new session per Siri ask) once confirmed.
(2) **Siri Stop: PARTIAL FAIL.** Siri-side cancel clean, but the Talaria-side run KEPT
GENERATING to completion (+ notification). Discriminator owed: Stop BEFORE the 25s hand-off
(designed cancelStreaming path — if that doesn’t cancel, real defect) vs Stop AFTER hand-off
(intent already returned; arguably uncancellable by design — then the defect is wording, not
behavior).
(3) **Tailnet-unreachable: FAIL.** Off tailnet AND wifi, the intent still presented as a
working run (hand-off instead of the designed real-error-text surface) — unreachable is
indistinguishable from slow in the current flow. Both (2) and (3) produced FIVE notifications
each → #143.

> **Audit 2026-07-13:** PR #11 (GitHub #6) merged this to main 2026-07-06; header's 'BUILT IN CLOUD, not compiled' is stale — a 2026-07-11 device pass (commits f35edb9, b05fef9) CORE VERIFIED both Siri actions. 🔧 remains correct only because >25s long-run hand-off, Siri Stop, and tailnet-unreachable error surface are still unchecked, not because the build is missing.

**Device pass 2026-07-11: CORE VERIFIED — phrase mystery solved, no code defect.** The intent works: both actions present and functional in Shortcuts, and "Hey Siri, ask Talaria twenty-seven" produced the "What should I ask Hermes?" prompt. Root cause of every voice miss: `.applicationName` resolves to `CFBundleDisplayName: Talaria27` (project.yml), so the registered phrase is "Ask Talaria27" — NOT "Ask Hermes" (→ Siri contacts) or "Ask Talaria" (→ Siri mythology facts). Apple requires the applicationName token in every phrase, so the utterance is permanently bound to the display name; making plain "Ask Talaria" work means renaming the app — a deliberate product decision, not a patch. Remaining sub-checks before full flip: >25s long-run hand-off, Siri Stop, tailnet-unreachable error surface.

**Shipped (`3ef4695`, branch `claude/issues-5-8-batches-cue3vb`, 2026-07-06).**
`Intents/AskHermesIntent.swift`: background Siri/Shortcuts query (`openAppWhenRun = false`)
through `ChatStore.sendMessage` — the exchange lands in the cached conversation and widgets
update; answer returned as spoken dialog (2-sentence/280-char summary) + HUD-styled snippet +
`ReturnsValue<String>` for Shortcuts chaining. 25 s budget: on expiry the run is NOT cancelled —
Siri says "still working", the reply lands in-app (pendingRun/reconcile). Failures throw the
REAL error text into Siri UI. Siri Stop → `cancelStreaming()`. Registered in the single
`TalariaAppShortcuts` provider ("Ask Talaria" — free-form Strings can't ride phrases, Siri
prompts for the question). Tests: `AskHermesIntentTests`.

**Tier B parked:** `AskHermesLongRunSupport.swift` holds the iOS 27 beta
`LongRunningIntent`/`CancellableIntent` adoption ENTIRELY behind `#if TALARIA_IOS27_INTENTS`
(defined nowhere). Mac session: verify every "iOS 27 beta API" comment against the beta SDK,
then add the flag to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` to enable.

**Mac-session checklist:** `xcodegen generate` (new files; re-verify `aps-environment` — #44/#48)
→ CLI build → run tests → device: Siri short answer, >25 s run hand-off, stop button,
`hermes://chat` deep link, exchange visible in app, tailnet-unreachable error.

**Questions for Owen:** (1) "Ask Talaria" prompting for the question (vs. one-breath phrase —
impossible for String params) OK? (2) Snippet is always Deep-Field-styled (system process can't
read live theme) OK? (3) ~~Known edge: process death mid-run loses the cache write~~ —
**resolved 2026-07-06 (Owen approved):** ChatStore now persists the optimistic turn BEFORE
streaming starts, and cold load finalizes stranded `.sending` user turns to `.failed` (retry
affordance; same terminal as polling exhaustion) + scrubs cached streaming placeholders. The
reply of a completed-but-killed run still needs a session refresh to appear (pendingRun/session
id don't survive process death — persisting the API session id is a session-lifecycle decision,
deliberately not taken here). Tests: `ChatStorePersistenceTests`. (4) Shortcuts chaining value
is "" on still-working paths.

Logged 2026-07-06.

> **Update 2026-08-06 late night (overnight) — the tailnet-unreachable half LANE-OPENED
> (batch-1 triage routing); diagnosis lands harder than the sweep's wording:
> unreachable can NEVER error inside the Siri window.** The intent's reply
> budget is 25s (`AskHermesIntent.swift:105-113`); the SSE send under it
> carries the **300s** streaming transport budget
> (`SessionsHermesClient.makeRequest` → `requestTimeout(forAccept:)`), so a
> black-hole host produces no error for five minutes and the "Hermes is
> still working on it" hand-off is the ONLY reachable branch — exactly the
> device sweep's FAIL, now with its arithmetic. Second collapse: failures
> that DO surface speak raw `localizedDescription` (measured: synthesized
> `URLError`s even degrade to "(NSURLErrorDomain error -1001.)"). **Design
> (reviewed + accepted): a ≤4s connect-level preflight** (`GET /v1/models`;
> any HTTP status = reachable) with one shared failure classifier — sound
> because connect-time and generation-time are independent, so a
> slow-but-alive turn cannot be mislabeled. Rejected with named failure
> modes: classification-only (300s ≫ 25s — the error never arrives),
> NWPathMonitor (path is `.satisfied` in the exact swept configuration),
> shrinking the SSE budget (#145's own trade forbids it — pinned by a bar).
> Siri-Stop stays out of scope (its own half, later). Two residuals
> recorded, not built: a `queueTurnOffline` seam so the honest dialog can
> also QUEUE the question (#90's outbox path never fires today), and the
> Tier-2 idea that fits the launch pivot — route the unreachable Siri ask
> to the on-device brain (#192's router already does this for in-app turns).
>
> **BARS (56-U series) — written before any production code:** 56-U-A
> transport-budget characterization pin (guards the rejected shortcut);
> 56-U-B today's strings name no actionable cause (characterization);
> 56-U-C every URLError variant maps to a distinct, actionable spoken
> detail (`.noAnswer` names tailnet/asleep); 56-U-D unreachable verdict
> lands strictly inside the reply budget in ONE round trip; 56-U-E no
> false positives (any HTTP status = reachable, nil dialog; the
> still-working string stays byte-identical for slow-but-alive); 56-U-F
> all waits share one deadline ≤25s (iOS reaps ~30s); 56-U-G preflight
> SKIPPED when no key is set — a hostless default user's local turn must
> never hear "host down"; 56-U-H device (Owen): off-tailnet ask answers
> ~5s naming the cause, one notification; slow-but-alive still says
> "still working". Compile-RED witnessed (new API); characterization bars
> behaviorally witnessed. Branch `claude/t27-56-unreachable-honesty`
> @ `2c48091`. Side-finding for the board: xcodegen version drift churns
> `Talaria.xcscheme` on every regen (1.3→1.7, app-name rename) — reverted
> as out of scope, needs its own small look.

---

## 127. 🔧 Monetization scaffold — MERGED DORMANT + gate walk DEVICE VERIFIED 2026-07-17 (fail-open live-confirmed on BOTH hosts: gate forced on, existing OJAMD + Mac pairings kept working, profile switch + chat clean); ASC product + sandbox purchase owed pre-flip

> **MERGED 2026-07-18 (PR #114, `62d169b`), fully dormant** — `MonetizationConfiguration.isEnabled
> = false`, one-line flip at launch. Loop-verified against every trap in the dispatch: gate wraps
> the paywall at the PRESENTATION site (ContentView swaps `ConnectedPaywallView` for
> `ConnectHermesHostScreen` on `.showPaywall`; the pairing screen itself untouched); the pure
> `ConnectGate.verdict` matrix pins fail-OPEN for existing pairings and cached-entitled unknowns,
> fail-closed only for new connects with no entitlement evidence; both product-kind scan paths
> behind `MonetizationConfiguration.productKind` (subscription nil-expiry errs toward the payer);
> price only via StoreKit `displayPrice`; DEBUG override in Developer settings. **20 new tests
> (MonetizationGateTests); suite 800/67 — new baseline.** Tree-identity validated. → **Owed
> (Owen, pre-flip):** App Store Connect product `org.aethyrion.talaria27.connected` + sandbox
> tester (steps in the PR body); device sandbox purchase + restore round-trip; DEBUG-override
> gate walk. Benign loop note: a sim-side stale `hermes.sessionUsageIndex` value exercised the
> #25 tolerant decode (logged + recovered) — the tolerance working, nothing owed.

Free = standalone (on-device model, voice, OCR, widgets, trends, share, lock). Paid "Connected"
= the connect-your-own-host feature set (pairing, profiles, uplink, inbox, realtime).
EntitlementService (StoreKit 2, both product-type paths behind a constant), gate wraps CONNECT
ENTRY POINTS only — existing pairings fail OPEN on transient entitlement failure; new connects
fail closed. Paywall sheet (displayPrice, restore, dismissible), DEBUG override, and the whole
gate lands DORMANT behind `monetizationEnabled=false` until launch.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-127-monetization-scaffold.md` — **READY TO
> SEND.** StoreKit greenfield verified. App Store Connect product setup = Owen, steps in the PR.

**Update (2026-07-17): scaffold BUILT on `claude/fable-t27-127-monetization-spgkzl` —
cloud-written, NOT compiled.** What landed:

- **Pure core** (`Services/Support/MonetizationGate.swift`): `MonetizationConfiguration`
  (`isEnabled = false` **DORMANT** — the flip-at-launch line; product id
  `org.aethyrion.talaria27.connected`; `productKind` constant selecting
  non-consumable vs annual-sub, BOTH paths implemented everywhere it's consulted),
  `ConnectGate.verdict` (the pinned matrix: dormant → allow; existing pairing →
  ALWAYS allow; new connect: entitled → allow, not-entitled → paywall even over a
  stale cache, unknown → cached-paid fails open / else closed), `EntitlementScan`
  (per-kind transaction classification + definitive-only cache updates),
  `PaywallPresentation` (displayPrice-or-"—", always dismissible, unlock-only
  auto-close), DEBUG override combinators + `MonetizationDebugSettings`
  (UserDefaults, compiles out of Release).
- **Service trio**: `Services/Protocols/EntitlementServiceProtocol.swift`,
  `Services/Live/EntitlementService.swift` (StoreKit 2 —
  `Transaction.currentEntitlements` launch scan + `Transaction.updates` listener,
  started from `makeDefault()` even while dormant for transaction hygiene; purchase +
  `AppStore.sync()` restore; last-known cache in UserDefaults),
  `Services/Mocks/MockEntitlementService.swift` (scriptable).
- **Gate wiring**: `AppContainer.connectGateVerdict(for:)` is the one seam. Entry
  points: the `.connectHost` pairing-flow branch in `MainTabView.routeDestination`
  (covers all four `navigate(.connectHost)` call sites; the paired-host MANAGEMENT
  screen stays ungated — a live pairing is never severed), Server `Add Profile` +
  pair-unpaired-profile (re-pair of a paired profile = existing → passes), Uplink
  first-key save (`keySaveAttempt` static, rotation ungated).
- **Paywall**: `Features/Paywall/ConnectedPaywallView.swift` (+`ConnectedPaywallSheet`
  wrapper) — theme-tokened, Connected feature list, `Product.displayPrice` only,
  purchase/restore/"Not now", pending (Ask to Buy) surfaced, always dismissible.
- **DEBUG driver**: Developer screen "// Monetization" section — Connect Gate toggle
  (activates the dormant gate for that build; can never deactivate a launched gate) +
  entitlement override picker (SYSTEM keeps real StoreKit so sandbox round-trips work
  with the gate live) + honest STOREKIT status row.
- **Tests**: `TalariaTests/MonetizationGateTests.swift` — dormancy pinned (the test
  fails loudly on flip day, delete it in the launch commit), full gate matrix, both
  product-kind scan paths, cache rule, override combinators, paywall rules, key-save
  classification, mock unlock semantics.

**Next Mac session checklist:**
- [ ] Merge, `xcodegen generate` (6 new source + 1 new test file; re-verify
      `aps-environment` + weatherkit + widget-HealthKit survive regen per #44/#48 —
      no project.yml changes were made, in-app purchase needs no entitlement key)
- [ ] CLI build + full suite — green ≥ 755/62 (post-#113 baseline 780/65)
- [ ] Compile-risk shortlist: `product.purchase()` may warn deprecated on the iOS 27
      SDK in favor of `purchase(confirmIn:)` (warning-only expected); switch-expression
      assignments in `DeveloperSettingsScreen.entitlementStatusLabel`; `@Observable`
      conformance to the `EntitlementServiceProtocol` existential
- [ ] Device: Developer → Connect Gate ON + override LOCKED → paywall at Server "Add
      Profile", Server "Pair" (unpaired profile), Uplink first-key save, and the
      pairing flow via Uplink "Pair Device" / Chat / System Settings; override
      UNLOCKED → all pass; gate OFF → dormant (production behavior)
- [ ] Device fail-open check: gate ON + LOCKED with an EXISTING pairing — chat,
      sensors, re-pair, key rotation all keep working; only NEW connects gated
- [ ] Sandbox (after Owen's App Store Connect setup): override SYSTEM, purchase +
      restore round-trip; price renders from displayPrice (never hardcoded)
- [ ] Owen (App Store Connect): create the in-app purchase with product id EXACTLY
      `org.aethyrion.talaria27.connected` (non-consumable to start — flip
      `MonetizationConfiguration.productKind` if pricing lands on the annual sub),
      create a sandbox tester account; steps also in the PR body
- [ ] Launch day: flip `MonetizationConfiguration.isEnabled = true`, delete the
      `scaffoldShipsDormant` test in the same commit

Logged 2026-07-17.

---

## 129. 🔧 Voice preview mid-session — MERGED (PR #127, merge `175261b`, 2026-07-20); device pass owed. Known accepted behavior: native-engine sessions share the assistant TTS instance, so mid-reply preview drops that reply's un-spoken audio tail (transcript intact) and the next chunk cuts the preview short; realtime engine (primary case) previews play over the session. Third dedicated preview instance (~4 lines) CANCELLED — Owen accepted the behaviour 2026-07-23.

> **⚠️ ENGINE-AMBIGUOUS — flagged 2026-08-01 by the #220 audit.** This item's device
> verdict was recorded while NOTHING logged which voice engine was active, and the engine
> varied run-to-run with OJAMD's health. Specifically: its 'known accepted behavior — **native-engine** sessions share the assistant TTS instance' is an explicit native claim **never verified on the native engine**.
> **See #220 before trusting or re-running this.**

> **Device debt queued 2026-08-01 (Hermes audit Part 1C):** the owed device check for
> this item now lives in `dispatch/DEVICE-PASS-RUNNING-LIST.md` **§F6**, written as a
> runnable check. **One queue** — do not restate it here; a check that lives in two
> places drifts, and a check that lives only in a closed-looking item is not recorded.

> **NAMING COLLISION — read carefully (2026-07-25).** GitHub **PR #129** is the
> merge of the #147 `@MainActor` delegate fix (`20b46fc`) and has nothing to do
> with this item. OPEN_ITEMS **#129** is this voice-preview item, merged as GitHub
> **PR #127** (`175261b`). Tracker numbers and GitHub numbers are independent
> sequences, and the 2026-07-25 results docs cite both senses of "#129".

**2026-07-23 — OWEN ACCEPTED the native-engine behaviour. The third dedicated preview instance is
CANCELLED, not deferred.** Asked directly whether the mid-reply tail-drop on native-engine sessions
(un-spoken audio tail lost, transcript intact, next chunk cuts the preview) was acceptable or
warranted a third TTS instance, Owen: “acceptable.” The open question in the PR is closed; treat the
current behaviour as documented and intended. **The device pass itself is still owed** — no crash,
session survives, mic live after — queued as Lane 3 of `dispatch/OPUS-T27-DEVICE-PASS-2026-07-24.md`
alongside #128's re-verify, which is the same physical test.

**Session V sweep 2026-07-20: PARTIAL — DoD still owed.** Pre-session audition →
composer-origin start passes (selection path sound). The actual DoD (MID-SESSION audition +
apply, session keeps running, mic live after) was only attempted via the settings-origin flow
that hit the #139 hang. Third-preview-instance verdict deferred to the circle-back — and note
#138: on the OJAMD realtime engine the session self-barges on its own TTS, so evaluate the
verdict on a session whose echo behavior is understood.

> **Dispatch spec 2026-07-17:** `dispatch/FABLE-T27-129-preview-instance.md` — **READY TO SEND** (micro; option (a) selection function, audio law restated).

`VoiceSettingsScreen:187` `speechOutput.previewVoice()` uses the chat instance
(`managesAudioSession = true`); during an active voice session each preview flips the shared
session to `.playback` and back under the running capture engine — the interruption/route burst
that lit #128's race, and even crash-free it degrades the live session. The `isBlocked` gate
protects `speak()` but not `previewVoice()`. Decide + fix (small): (a) while a session is
active, route previews through `nativeSpeechOutput` (gate off, no session management — preview
plays over the live session; probably the right UX), or (b) apply `isBlocked` to preview and
show 'end the session to preview voices'. Either is a micro-PR; (a) preferred pending Owen's
call.

Logged 2026-07-17.

**Update 2026-07-20 — BUILT, option (a) (PR #127, `claude/t27-129-preview-instance`):** pure
`SpeechOutputService.previewInstance(sessionActive:chat:native:)` selects which instance
auditions; AppContainer creates `nativeSpeechOutput` unconditionally (mock voice path included
— wiring hoisted byte-identical, audio law #106 held: no session-management changes, no session
calls, `didActivateAudioSession` untouched) and exposes it `private(set)` with a session-safe
closure default for bare containers; the settings preview button routes through the selector
and its `.disabled(isSessionActive)` stopgap is REMOVED (mid-session audition is the
acceptance). TDD identity tests in the existing `SpeechOutputTests` (no new files → no regen);
suite 931/0 + UI bundles green; adversarial review clean. **Record correction:** at base the
mid-session preview was double-blocked since Wave 1 (disabled button + `previewVoice()` →
gated `speak()`) — the #128 trigger attribution only works if `isSessionActive` flapped out of
connecting/connected during the burst, so #128's re-verify stands on its own; selection keys
on the same predicate, so flap-window behavior is unchanged from base. **Question for Owen
(in PR):** native-engine sessions share the pipeline's assistant TTS instance — preview
mid-reply drops the reply's un-spoken audio tail (transcript intact) and the next delta cuts
the preview; realtime engine (primary case) previews truly play over the session. Accept, or
add a third dedicated preview instance? → Device pass (Owen): mid-session audition + apply, no
crash, session keeps running, mic live after; outside a session, full-fidelity previews.

> **Update 2026-08-06 late night (reconciliation audit):** the **"Dispatch
> spec 2026-07-17: `dispatch/FABLE-T27-129-preview-instance.md` — READY TO
> SEND"** line above is stale. That dispatch was **CANCELLED** per this
> entry's own header: *"Third dedicated preview instance (~4 lines)
> CANCELLED — Owen accepted the behaviour 2026-07-23."* Nothing is pending
> send on this item.

---

## 138. 🐛 Realtime engine self-barge-in — assistant TTS captured as user speech (OJAMD voice host); slow turn processing noted

**Scope broadened 2026-07-20 (Owen): NOT realtime-only.** The same self-barge-in occurred on
the native/TTS engine against the Mac Mini profile — i.e. the #130 self-transcription
behavior, live on main (the probe branch that gates it is unmerged). Implication: the fix
should cover BOTH ingest points — the #130 half-duplex gate for the native pipeline, and its
equivalent (or proper AEC reference routing, pending the source read) at the realtime
transcription ingest. The #130 A/B verdict now carries double weight.

**Evidence update 2026-07-20 (eve, via the #139 zombie-session conversation):** the realtime
downlink is unmistakably SERVER audio (quality/speed far beyond local) — weakens the naive
app-TTS hypothesis but does NOT settle the reference question: if the app extracts the remote
track’s PCM and renders it through its own engine/player instead of WebRTC’s internal playout,
the AEC still has no far-end reference and self-echo follows exactly as observed. Discriminator
(1) re-scoped to a SOURCE READ: who renders the remote audio track in the realtime path? —
cloud-doable, no device needed. Self-barge-in persisted through the entire otherwise-excellent
conversation; per-turn speed once connected was good (earlier slowness re-attributed, see #139).

**Observed 2026-07-20 (Owen, whoGoesThere, OJAMD profile — the voice-configured host).** With
the realtime engine active, the moment the assistant starts speaking the session takes its own
audio as the user's response and treats it as barge-in — self-echo into recognition, every
reply. Also observed: long per-turn processing gaps (host-side K3 inference speed —
informational, not an app defect, but it widens the window in which self-echo fires).

**Mechanism hypothesis (source-informed, unverified):** the echo path only exists if assistant
audio is NOT the echo canceller's far-end reference. If the realtime path speaks via the app's
own TTS (SpeechOutputService synthesizing streamed text) rather than a WebRTC downlink track,
WebRTC's AEC has no reference for it → mic re-captures it → server VAD fires speech_started →
spurious barge-in. Same family as #130's native-engine self-transcription, which the half-duplex
gate (discard recognition while isSpeaking + hangover) already solves on the probe branch — the
realtime engine may need the identical software gate at its transcription ingest, or proper
reference routing.

**Discriminators owed (circle-back):** (1) does the realtime session's assistant voice sound
like the app's TTS voices or like server-generated audio? (2) does the #130 gate concept apply
cleanly at the realtime ingest? (3) Mac-host comparison once its voice config is brought up.

Logged 2026-07-20 (Session V launch sweep).

> **🔴 2026-08-22 — CONFIRMED ON THE RE-HOMED PATH, AND THE SHAPE HAS CHANGED
> IN A WAY THAT POINTS AT THE MECHANISM.** Owen, first realtime session against
> OJAMD after #383's deploy: *"it interrupted itself to begin with, but then
> carried on a full conversation afterwards."*
>
> **This is the decontaminated observation #396 said was owed.** On 2026-08-22
> ~03:1x he reported NOT seeing self-interruption — but he was *"pausing
> everything to test"*, suppressing the very condition. #396 recorded that
> negative as contaminated rather than as evidence. Un-suppressed, it fired on
> the first utterance of the first session.
>
> ### The change from July is the finding, not the recurrence
>
> | | 2026-07-20 | 2026-08-22 |
> |---|---|---|
> | frequency | **every reply**, "persisted through the entire conversation" | **once, at session start**, then a full clean conversation |
>
> **Hypothesis this suggests, and it is not a threshold: AEC CONVERGENCE.**
> Both engines now set `AVAudioSession` mode `.voiceChat` (the system
> voice-processing chain). An echo canceller has to ADAPT to the acoustic path
> before it suppresses anything, so the first assistant utterance can leak into
> the mic before convergence and be transcribed as user speech — which, with
> `interrupt_response: true`, cuts the assistant off mid-greeting. Once
> converged, it stops. That is exactly "interrupted itself to begin with, then
> carried on."
>
> It also explains the July→August change: with no AEC the leak recurs every
> reply; with AEC it survives only in the pre-convergence window.
>
> **The route makes it plausible rather than exotic** — the session header
> reads `ROUTE · IPHONE MICROPHONE → SPEAKER`. Speakerphone is the worst
> acoustic case and the one AEC has most work to do on.
>
> ### 🔎 A candidate artifact in the transcript, flagged NOT claimed
>
> The screenshot's transcript carries a user turn reading **`Kanada`** between
> two near-identical assistant greetings. That is consistent with assistant
> audio being captured and transcribed as a user turn — which would make it the
> mechanism caught in the act. **But it is not proven**: Owen may simply have
> spoken. His own words ("it interrupted itself") are the finding; this row is
> a candidate.
> **Discriminator, and it needs no new instrument:** the device log's assistant
> audio timeline against the input transcription timestamps — a user turn whose
> transcription window lies *inside* an assistant utterance is self-capture.
>
> ### 🎯 What this rules OUT, which is the expensive part to get wrong
>
> **A turn-detection threshold cannot fix this.** The leaked signal is the
> assistant at full speaker volume — loud, speech-shaped, and trivially over
> any activation threshold. Raising `threshold` (now reachable via #396-B)
> would degrade real user speech long before it rejected this.
>
> The candidates that fit the mechanism instead:
> 1. **Gate turn detection for the first assistant utterance** (or a short
>    fixed window), letting AEC converge before the mic can open a turn — the
>    realtime analogue of #130's half-duplex gate.
> 2. **`interrupt_response: false`** — now a host-side setting rather than a
>    literal (#396-B), so this arm is cheap to try. Cost: real barge-in stops
>    working, which is a genuine feature loss and probably too blunt.
> 3. **Verify the far-end reference** — #138's original discriminator (3)
>    remains unanswered: who renders the remote track? If the app plays it
>    outside WebRTC's playout, AEC has no reference and (1) is a patch over a
>    routing bug.
>
> **Sharp prediction worth testing before building anything:** if convergence
> is the mechanism, the self-interrupt lands on the FIRST assistant utterance
> of a session and essentially never later. A few session starts settle it, and
> a negative kills the hypothesis cheaply.

> **✅ 2026-08-22 — DISCRIMINATOR (3) ANSWERED FROM SOURCE, and it REFUTES this
> entry's own original mechanism.** Owed since 2026-07-20, marked
> *"cloud-doable, no device needed"*, and it took one read.
>
> **WebRTC renders the remote track. The app never touches it.**
> `LiveVoiceSessionService` contains **no** `SpeechOutputService`,
> `AVAudioPlayer` or `AVAudioEngine` reference of any kind; its
> `peerConnection(_:didAdd stream:)` delegate is **empty**; and the only track
> it constructs is the LOCAL mic track (`"hermes-mobile-audio"`, `:933`). The
> remote stream is played by WebRTC's own audio device module — **which is
> exactly the echo canceller's far-end reference.**
>
> So the hypothesis this entry was built on — *"if the realtime path speaks via
> the app's own TTS … WebRTC's AEC has no reference for it"* — **is false.**
> The July note already suspected as much from the audio QUALITY ("unmistakably
> SERVER audio"); this settles it from the code rather than from an ear. AEC is
> present and correctly referenced, which is why the fault is now a narrow
> start-of-session window instead of every reply.
>
> ### 🔴 AND THE SAME READ FOUND A SHARPER MECHANISM: WE MAY BE CAUSING IT
>
> The app forces the output route to the speaker **three times** around connect:
>
> 1. inside `configureAudioSession()` — which **already passes
>    `.defaultToSpeaker` in the category options** (`:743`);
> 2. again immediately after `setRemoteDescription` returns, commented *"WebRTC's
>    RTCPeerConnectionFactory reconfigures the audio session internally"*;
> 3. **and again 500 ms later**, as an explicit *"safety net"* (`:980`).
>
> **A route change forces the echo canceller to re-adapt — and call (3) lands
> squarely in the window when the first assistant utterance plays.**
>
> This fits the observation strictly better than generic convergence does.
> Generic adaptation predicts occasional later leaks too, after any route
> settling. **A one-shot perturbation at +500 ms predicts exactly one failure,
> at the start, and a clean conversation after** — which is what Owen reported,
> word for word.
>
> **And `forceSpeakerIfNeeded` (`:764`) does not check whether the route is
> ALREADY the speaker.** It only skips when an external output (headphones,
> Bluetooth, CarPlay) is present. On the ordinary speakerphone path it calls
> `overrideOutputAudioPort(.speaker)` on a session that is already on the
> speaker — semantically a no-op, but still a route reconfiguration handed to
> CoreAudio, twice, during the most timing-sensitive second of the session.
>
> ### 🎯 BARS 138-A…D — pre-registered before any code
>
> Deliberately not built yet. This is a timing hypothesis, #138's history is a
> plausible mechanism that turned out false, and #396-A's rule (characterise
> before tuning) applies with equal force here.
>
> - **138-A (reproduce on demand first).** The self-interrupt lands on the
>   FIRST assistant utterance and essentially never later, across ≥3 session
>   starts on the speakerphone route. **A negative kills the route-perturbation
>   hypothesis outright** and sends this back to measurement — that is the
>   outcome this bar exists to allow.
> - **138-B (the treatment is a SKIP, not a delay).** `forceSpeakerIfNeeded`
>   returns early when the current route is already `.builtInSpeaker`. Moving
>   the 500 ms timer later, or removing it outright, are both worse: the first
>   only relocates the perturbation, and the second drops a safety net that was
>   added for a reason nobody has refuted.
> - **138-C (the safety net's PURPOSE survives).** The override exists because
>   WebRTC reconfigures the session under us. A build that stops correcting a
>   genuinely wrong route has traded a rare self-interrupt for quiet audio on
>   the earpiece — strictly worse. Prove the correction still fires when the
>   route IS wrong.
> - **138-D (measured on the speakerphone route, and said so).** Headphones
>   short-circuit `forceSpeakerIfNeeded` entirely, so a headset trial cannot
>   test this and must not be scored as one. Owen's observation was
>   `ROUTE · IPHONE MICROPHONE → SPEAKER`; the bar inherits it.

> **✅ 2026-08-22 — 138-A MET, 4/4, AND THE PREDICTION HELD EXACTLY.** Owen ran
> three fresh session starts on the speakerphone route, giving **only a
> greeting** each time. In every one, Hermes began speaking, then interrupted
> itself. With the earlier OJAMD session that is **4 of 4 — always the FIRST
> assistant utterance, never later.**
>
> | # | assistant's opener | phantom "user" turn | assistant's recovery |
> |---|---|---|---|
> | 1 | *"Hi Owen, good to hear from you. What's on your mind today?"* | **嗨** | *"Hi there, what's on your mind today?"* |
> | 2 | *"Hello there. How can I help today?"* | **Echt?** | *"I'm here. What's on your mind today?"* |
> | 3 | *"Hello there. I'm here and ready to help… How's your day going?"* | **OK.** | *"Hi there. I'm here and ready to help…"* |
> | 0 | *"Hello there. What's on your mind today?"* | **Kanada** | *"Hi there, Owen. What's on your mind today?"* |
>
> ### 🔴 The CONTENT of those turns is the strongest evidence, not the timing
>
> `嗨` (Chinese "hi"), `Echt?` (German "really?"), `OK.`, `Kanada`. Owen spoke
> none of them — **he gave a greeting and nothing else.** Short, mostly
> non-English tokens are the classic signature of **echo residue reaching a
> speech recogniser**: the ASR receives an attenuated, distorted copy of the
> assistant's own speech and emits a brief out-of-language fragment. A person
> saying "hi" does not produce `嗨` on one turn and `Echt?` on the next.
>
> **This retires the "candidate artifact" caveat filed earlier today.** The
> `Kanada` row was flagged as *consistent with* self-capture but not proven,
> because Owen might simply have spoken. Three more instances, in three
> languages, on three consecutive session starts, from a user who only said
> hello, settle it. **The hedge was right to make and right to drop — on
> evidence, not on it having become inconvenient.**
>
> Also note the assistant's recovery each time is a *re-greeting*: it answers
> the phantom turn as if the user had just arrived. So the user-visible cost is
> not only a stutter — the first exchange of every session is spent twice.
>
> ### ⚖️ What 138-A does and does NOT establish
>
> **Established:** self-capture is real, reproducible on demand, confined to
> the first assistant utterance, and it is the assistant's own audio.
> **NOT established:** that the +500 ms route override is the cause. 138-A was
> written so a negative would kill that hypothesis; a positive is consistent
> with it *and* with plain AEC convergence, which the same 4 sessions cannot
> separate. The discriminating test is the fix itself — **138-B removes the
> route perturbation while leaving convergence untouched, so if the
> self-interrupt survives, convergence was the mechanism and the next lane is a
> start-of-session turn-detection gate, not a routing fix.** Recorded now so
> that outcome reads as information rather than as failure.

> **✅ 2026-08-22 — 138-B/C BUILT, mutation-verified.**
> `LiveVoiceSessionService.shouldOverrideOutputToSpeaker(currentOutputPortTypes:)`
> — pure, per the `NativeVoicePipelineService` convention — now declines for
> two reasons rather than one: an external output is connected (pre-existing),
> **or the route is already `.builtInSpeaker` (new)**. Both call sites use it,
> which is what silences the 500 ms safety net on the ordinary path.
>
> **138-C is the bar that shaped the fix.** `.builtInReceiver` still returns
> true, so a route WebRTC genuinely moved is still corrected — the override
> keeps its purpose instead of being deleted. Five tests in
> `TalariaTests/SpeakerRouteOverrideTests.swift`; removing the one new line
> turns `alreadyOnTheBuiltInSpeakerDoesNotOverrideAgain` RED and leaves the
> other four green, so each arm is pinned separately rather than by one
> assertion doing all the work.
>
> **What a unit test cannot say, stated rather than implied:** these pin the
> DECISION, not the acoustics. Whether the skip actually removes the
> self-interrupt is 138-A's re-run on a device — and per the note above, a
> surviving self-interrupt is the informative outcome, not a failed lane.

> **🟡 2026-08-22 — BUILD 2955 TESTED. SPLIT RESULT, AND IT FALSIFIES TWO OF MY
> OWN CLAIMS.** Two sessions on the OJAMD profile.
>
> **Self-CAPTURE persists.** The phantom turns are still there and still carry
> the same signature: `再考`, `是。`, `Hogy?` — Chinese, Chinese, Hungarian, none
> of them spoken. So **the route perturbation was not the cause**, and 138-B is
> refuted as a fix for this. Per the pre-registered reading, that is
> information: it points at AEC residue rather than at anything we do to the
> route.
>
> ~~**Self-INTERRUPTION appears resolved** — every assistant utterance in both
> transcripts is a complete sentence…~~ **❌ WRONG, corrected by Owen within the
> minute: *"it interrupted itself both times on the test. What's partial about
> it?"* Nothing is. 138-B is refuted OUTRIGHT — both symptoms survive it.**
>
> ### 🔴 THE INSTRUMENT WAS THE ERROR, AND IT IS A REUSABLE ONE
>
> I read "complete sentences in the transcript" as "not cut off". **That
> inference is structurally invalid.** Realtime generates TEXT ahead of audio
> playout, so a response whose AUDIO is cancelled mid-sentence still delivers
> its full text over the data channel — **the transcript shows a complete
> utterance for an interruption the user plainly heard.**
>
> **So the live transcript can never score barge-in, and no #138 or #396 bar
> may be scored from it.** It was the only instrument I had, which is the
> actual defect:
>
> **`handleServerVADInterruption` — the one function that answers this — logged
> NOTHING.** It fires on `input_audio_buffer.speech_started`, cancels the
> assistant's audio, and returned silently. **Fourth instance this week of *the
> failure path is the path with no instrument*** (after #394's silent poll loop,
> the envelope's 200-with-an-error-body, and #383's unlogged realtime fallback).
> Worse than the others: here the *misleading* instrument was in the UI, in
> front of both of us, and it read as evidence.
>
> **Now instrumented, both arms**, because the distinction IS the measurement:
> `#138 BARGE-IN: assistant audio cancelled Xs into playback` versus
> `#138 speech_started while assistant idle — phantom turn, no interruption`.
> The elapsed time separates "cut off at 0.2 s" from "cut off at 3 s", which
> bears directly on whether the residue arrives with the utterance or trails it.
> **Every future session now scores itself from the device log instead of from
> Owen's ear or from a transcript that cannot know.**
>
> ### 🔴 FALSIFICATION 1 — "first utterance only" was an ARTIFACT OF THE USER TALKING
>
> 138-A recorded the fault as confined to the first assistant utterance, from
> four sessions in which Owen said only a greeting and then let it run. **In
> this run he spoke once and stayed quiet, and a phantom turn followed EVERY
> assistant utterance** — three in one session.
>
> So the earlier "never later" was almost certainly **his real speech masking
> it**: while he was talking, the assistant's turns were followed by genuine
> user audio, and the echo had no empty window to land in. **The AEC-convergence
> story built on top of that observation is unsupported** — the fault is not
> confined to a start-of-session window at all, and never was.
>
> This is #215's lesson in a new costume: a rate measured under one usage
> pattern was read as a property of the system.
>
> ### 🔴 FALSIFICATION 2 — I said a THRESHOLD CANNOT FIX THIS. That was wrong.
>
> Written into this entry earlier today: *"the leaked signal is the assistant at
> full speaker volume — loud, speech-shaped, and trivially over any activation
> threshold."* **The evidence contradicts it, and the evidence was already in
> hand when I wrote it.**
>
> If the residue were the assistant at full volume, ASR would transcribe it
> **accurately** — we would see Hermes's actual words appearing as user turns.
> Instead every single instance is a short, garbled, usually non-English token
> (`嗨`, `Echt?`, `Kanada`, `再考`, `是。`, `Hogy?`). **That is the fingerprint of a
> heavily ATTENUATED signal** — AEC is working, and what survives is weak enough
> to defeat the recogniser but not weak enough to fall under the activation
> threshold.
>
> **Which makes `server_vad`'s `threshold` a live candidate after all**, and
> makes #396-B's reachability work directly load-bearing rather than
> preparatory. The discriminating question is whether a threshold exists that
> rejects the residue while still accepting Owen at a normal speaking distance —
> which is measurable, not arguable.
>
> ### 🎯 NEXT — 138-E, the threshold arm (host-side config, no app build)
>
> `TALARIA_VOICE_TURN_DETECTION=server_vad` plus a raised
> `TALARIA_VOICE_VAD_THRESHOLD` in the host's `.env`, gateway bounced. **Needs
> Owen's live-install go** (config, not code — but it is a live install).
> **396-D binds:** the BEFORE row is already recorded on both hosts, so the
> after-values and the session that justified them go in the same block.
>
> **The rival candidate, kept alive on purpose:** a half-duplex gate at the
> realtime ingest — #130's fix, which this entry named in July as the likely
> shape. Cost: it kills real barge-in. The threshold arm is cheaper and
> reversible, so it goes first; if no threshold separates residue from user,
> the gate is the answer and its cost is the price.

> **🔬 2026-08-22 18:00 — THE FIRST INSTRUMENTED ARCHIVE, and it refutes MORE
> of my own hypotheses than it confirms.** Build 2957,
> `talaria-138-two-voices.logarchive`, one 40-second session.
>
> Owen's report first, because it reframed the fault before the log did:
> *"there's two responses. It's interrupting itself… with… itself. Two
> different voices too. One male, one female."*
>
> ### What the log SHOWS
>
> ```
> 18:00:07  voice session starting on engine realtime (voiceHostPaired=true)
> 18:00:09  #138 speech_started while assistant idle — phantom turn, no interruption (state=listening)
> 18:00:15  (same)   18:00:21  (same)   18:00:27  (same)   18:00:46  (same)
>           no-op cancel race swallowed: Cancellation failed: no active response found
> ```
>
> **Five phantom detections in forty seconds. ZERO barge-in events.**
>
> ### ❌ REFUTED: two engines running at once
>
> The two voices made a second engine the obvious reading — one realtime
> (`ballad`), one on-device TTS — and `VoiceEngineRouter`'s fallback does start
> the native engine **without ending the realtime session** (`:318-329`, no
> `realtime.endSession()`), which would produce exactly that. **But there is no
> `falling back to local voice` line in this session.** The native engine never
> started. It is one engine.
>
> *(The missing `endSession` on that fallback path is a REAL latent defect and
> is filed on its own merits below — it just is not this. Reaching a true bug
> while chasing a different one is how #388's diagnosis went wrong too.)*
>
> ### ❌ REFUTED: our barge-in path is involved
>
> **Zero `#138 BARGE-IN` lines.** `handleServerVADInterruption` never cancelled
> anything, because its guard requires the app to believe the assistant is
> speaking and the app never did. So what Owen hears as self-interruption is
> **not our cancel path** — it is responses overlapping.
>
> ### ✅ THE MECHANISM THAT FITS: `create_response: true`
>
> Every detection — phantom or real — spawns a response. Five phantom
> detections spawn up to five extra responses, which play over each other.
> *"Two of y'all responding"* is **one engine answering itself**, not two
> engines. The `Cancellation failed: no active response found` line is the same
> story from the other side: a cancel arriving for a response the server had
> already finished.
>
> ### ⚖️ THE ONE THING THE ARCHIVE CANNOT SETTLE — and it is the fork
>
> Every phantom logged `state=listening`, which is **ambiguous**:
> **(a)** the assistant genuinely was idle, or **(b)** the app never learned it
> started — `output_audio_buffer.started` may not arrive at all. The app's ONLY
> model of assistant speech is those events, and they had no logging.
>
> **The two readings take opposite fixes.** (a) makes an app-side gate viable.
> (b) makes an app-side gate **impossible** — you cannot gate on a state you
> cannot observe — and forces the fix server-side onto the threshold.
>
> Now instrumented: `#138 audio.started`, `#138 audio.stopped after Nms`,
> `#138 audio.cleared after Nms`, and `#138 response.created (state=…)`. The
> response-created pattern is also the direct evidence for or against
> overlapping responses.
>
> ### 🔴 THE TALLY, recorded because it is the lesson
>
> **Four hypotheses on this item in one day; four wrong.**
>
> | # | claim | killed by |
> |---|---|---|
> | 1 | AEC convergence window | phantom turns after EVERY utterance once the user went quiet |
> | 2 | "a threshold cannot fix this" | the residue transcribes as garbled non-English — i.e. attenuated, not loud |
> | 3 | "self-interruption appears resolved" | Owen: *"it interrupted itself both times"* — the transcript cannot show barge-in |
> | 4 | two engines live at once | no fallback line in the log |
>
> **Every one died the moment a real instrument existed, and not one died to
> argument.** Three of the four were stated confidently to Owen before any
> instrument could see the thing. The rule this earns: on this item, **no
> mechanism claim without a log line that would have to change if it were
> false** — which is the same discipline #215 and #300 arrived at from their
> own directions.

> **✅ 2026-08-22 19:56 — THE FORK IS RESOLVED AND THE LOOP IS PROVEN.** Build
> 2958, `talaria-138-fork.logarchive`. The ordering is the finding:
>
> ```
> 19:56:21.402  speech_started while assistant idle (state=listening)
> 19:56:22.813  response.created (state=listening)
> 19:56:23.536  audio.started — assistant playback begins
> 19:56:25.730  audio.stopped after 0ms
> 19:56:29.921  speech_started while assistant idle (state=listening)   ← and round again
> ```
>
> **Seven cycles, always the same order: `speech_started` → `response.created`
> → `audio.started`.** The phantom detection is what CREATES each response.
> This is not two engines and not two sessions — **it is one session in a
> feedback loop**: the assistant speaks, the mic hears it, the server's VAD
> calls that a user turn, `create_response: true` answers it, and that answer
> feeds the next lap. *"Two of y'all responding"* is the loop overlapping with
> itself.
>
> ### ✅ Fork answer: `audio.started` DOES arrive — the app CAN see playback
>
> So reading (b) is dead: the app is not structurally blind, and an app-side
> gate is not impossible. **But reading (a) was not right either**, and the
> reason is a defect neither branch anticipated.
>
> ### 🔴 ROOT CAUSE of the blind guard — `LiveVoiceSessionService.swift:825`
>
> ```swift
> case "conversation.item.created", "conversation.item.added":
>     if …role == "assistant"… {
>         resetAssistantAudioPlaybackTracking()   // ← clears startedAt
>     }
> ```
>
> A NEW assistant item arrives **while the PREVIOUS response's audio is still
> playing**, and this zeroes `assistantAudioPlaybackStartedAtUptime`. From that
> moment the app believes nothing is playing, so
> `handleServerVADInterruption`'s guard declines and every subsequent echo logs
> *"assistant idle"* — **which is exactly what we saw, including at 19:56:33.285,
> 1.47 s INTO a playback that had started at 31.813.** It also explains the
> otherwise-nonsensical `audio.stopped after 0ms`: tracking had been reset
> mid-playback, so the accumulator read zero.
>
> **Playback state is being driven by the CONVERSATION lifecycle when only the
> AUDIO BUFFER lifecycle knows the answer.** `output_audio_buffer.started` /
> `.stopped` / `.cleared` are the authority; item-created is not.
>
> ### ⚠️ BUT FIXING THE GUARD ALONE WOULD MAKE IT WORSE, and this is the part
> worth pausing on
>
> `speech_started` comes **from the server** — its VAD ran on audio **we
> uplinked**, and by the time the app sees the event the response already
> exists. So an app-side gate on the EVENT cannot prevent the response. And a
> guard that worked perfectly would convert *"two voices overlapping"* into
> *"the assistant is cut off constantly"* — trading one symptom for the
> original complaint.
>
> **The echo has to stop reaching the uplink, or stop being scored as speech.**
> That leaves three, and only the middle one is cheap and reversible:
>
> | | effect | cost |
> |---|---|---|
> | mute the local track while the assistant plays (+hangover) — #130's shape | kills the loop at source | **kills real barge-in** |
> | **`server_vad` + raised `threshold` (138-E)** | fewer detections; residue is attenuated, so a threshold plausibly separates it | may also reject a quiet user — measurable |
> | `create_response: false` | breaks the loop | the assistant stops answering by itself; not a product we want |
>
> ### 🎯 BARS 138-J/K — pre-registered before any code
>
> - **138-J (playback state follows the AUDIO BUFFER, not the item lifecycle).**
>   A new assistant `conversation.item.added` must not clear
>   `assistantAudioPlaybackStartedAtUptime` while playback is active. Written
>   RED against today's code. **This is worth fixing on its own merits even
>   though it does not stop the loop** — the guard is load-bearing for real
>   barge-in too, and it has been silently inoperative.
> - **138-K (the guard fix ships WITH a detection fix, never alone).** A build
>   that repairs the guard and nothing else turns overlapping responses into
>   constant interruption. 138-J does not ship to a device by itself.

> **🧪 2026-08-22 20:09 — 138-E ARM 1 IS LIVE ON THE MAC.** Owen's go: *"go for
> 138-E on the mac"*. Host config only; no app build. Listener **34110**, health
> 200 in ~5 s, `✓ talaria connected` 20:09:57, wire-proven with the
> nonsense-verb control.
>
> **396-D, both halves in one place:**
>
> | | BEFORE (shipped) | AFTER (arm 1) |
> |---|---|---|
> | `type` | `semantic_vad` | **`server_vad`** |
> | activation | *none exists* | **`threshold: 0.8`** |
> | end-of-turn | `eagerness: medium` | `silence_duration_ms: 500` (provider default) |
> | `prefix_padding_ms` | n/a | `300` (provider default) |
> | `create_response` / `interrupt_response` | `true` / `true` | unchanged |
>
> **Only the threshold was chosen; everything else is a provider default.** One
> deliberate variable, so a result is attributable.
>
> **⚠️ THE CONFOUND, NAMED BEFORE THE RUN so it cannot be discovered
> conveniently afterwards:** `threshold` exists only on `server_vad`, so
> reaching it necessarily changes the turn-detection TYPE as well. That means
> **two things moved**, and `semantic_vad`'s smarter end-of-turn is gone with
> it. So: fewer phantom turns is attributable to the threshold, but **any
> change in how it judges the END of Owen's sentences may be the type change,
> not the threshold.** If turn-taking feels worse while phantoms drop, that is
> the confound talking and the next arm is `server_vad` at the DEFAULT 0.5 —
> which isolates type from threshold.
>
> **Why 0.8:** the residue transcribes as short garbled non-English tokens
> (`嗨`, `Echt?`, `Hogy?`), i.e. it is attenuated rather than loud, so it should
> sit well below a normal speaking voice at phone distance. **0.8 is a guess
> with a reason, not a measurement.** If it also rejects Owen, the answer is a
> lower value (0.65), not abandoning the approach — and that is a one-line
> change plus a bounce.
>
> **Reversal is four lines and a bounce.** `~/.hermes/.env` carries the block
> with its own removal note; the pre-change file is backed up at
> `~/.hermes/.env.bak-138e-200922`.
>
> **Bars for the run:** phantom `speech_started` events per minute of assistant
> speech, from the device log — **scored from `#138` log lines, never from the
> transcript** (which cannot see barge-in) and never from the model's
> self-report. BEFORE is the 2958 archive: **7 cycles in ~90 s.**

> **❌ 2026-08-22 20:13 — ARM 1 FAILED. `server_vad` @ 0.8 does NOT stop the
> loop.** Verified on the right host (`active profile → 'Mac Mini'`, gateway
> online), session minted after the 20:09:57 bounce.
>
> ```
> 20:13:44.685  speech_started, assistant not playing     ← Owen's greeting
> 20:13:45.989  audio.started
> 20:13:46.510  speech_started  +  audio.cleared          ← 0.52 s INTO playback = echo
> 20:13:47.832  audio.started                              ← and round again
> ```
>
> Owen's transcript is the clean illustration: Hermes says *"Good afternoon.
> How can I assist you today?"*, a USER turn appears reading **"Good
> afternoon."**, and Hermes answers it.
>
> **The session was short (~9 s), so this is not a rate** — but it does not
> need to be. One unambiguous echo 0.52 s into playback at a threshold of 0.8
> falsifies "the residue is attenuated enough for a threshold to reject it".
> Pushing to 0.9 risks rejecting Owen and is a guess on top of a failed guess.
>
> ### 🔬 MY OWN INSTRUMENT WAS LYING, and I introduced it
>
> The line read *"speech_started while assistant idle — **phantom turn**, no
> interruption"*. **That branch is also exactly what a legitimate user turn
> looks like** — and the 20:13 archive opens with one: Owen's own greeting,
> labelled "phantom" by my line. Echo is distinguished by **arriving DURING
> playback**, not by this branch. Reworded to report what it saw and nothing
> more. Baking a conclusion into a log line is how the next reader inherits my
> error as data.
>
> ### 🎯 138-L — THE CONTROL THAT SPLITS THE PROBLEM IN HALF (do this FIRST)
>
> **One session with headphones connected.** Nothing acoustic survives
> headphones, so:
>
> | result | meaning | where the work is |
> |---|---|---|
> | loop **stops** | genuinely acoustic — speaker → mic | route/volume tradeoff, or half-duplex. Threshold tuning is dead. |
> | loop **persists** | **NOT acoustic at all** — the assistant's audio is reaching the uplink inside the app | a software loopback; every hypothesis on this entry so far is aimed at the wrong layer |
>
> **This should have been the first experiment of the day.** Five mechanisms
> have been proposed and falsified (AEC convergence, threshold-can't-help, the
> transcript reading, two engines, threshold-can-help), and **every single one
> assumed acoustic echo without ever testing that assumption.** The one control
> that interrogates the shared premise costs a pair of headphones and one
> session. `forceSpeakerIfNeeded` also deliberately drives the speaker at
> maximum volume into the same device's microphone, which makes the acoustic
> branch entirely plausible — but plausible is what the last five were.

> **📎 2026-08-23 (Opus-week audit) — a pinning gap on 138-B, filed for the
> next lane that touches these files:** `SpeakerRouteOverrideTests` pins the
> pure `shouldOverrideOutputToSpeaker` decision only; unwiring either of its
> two call sites (`LiveVoiceSessionService:751`, `:797`) while keeping the
> function leaves the suite green — the #340 wiring shape. Low severity (a
> full revert reverts both, and the entry's own mutation claim is scoped
> honestly to "the one new line"), but a wiring-sensitive assertion is owed
> whenever this file is next open. **→ ✅ TAKEN the same evening (PR #359):
> a structural call-site pin (`theSpeakerDecisionIsWiredAtBothCallSites`,
> exactly-3 spellings) landed in `SpeakerRouteOverrideTests`, RED-proven by
> unwiring a site.**

> **⟵ 2026-09-01 POINTER (hygiene sweep):** 138-L ("do this FIRST" — one
> session with headphones, to split acoustic from software) is absorbed by
> **#413**'s 2026-08-30 AirPods session rather than run separately: its
> log-scored transcript shows zero phantom bubbles and zero
> `speech_started` inside any playback window — the 138-L table's "loop
> stops ⇒ genuinely acoustic" row. Same reading as 138-L intended, on a
> different entry. Still N=1 against the 4/4 speakerphone baseline
> (#413's own words: "each further incidental AirPods session tightens it,
> none needs to be scheduled") — so this is a lean, not a closed control,
> and 138-L itself is not re-run.

> **🔬 2026-09-01 — ESCALATION SYNTHESIS OF THE VOICE CLUSTER (#138 · #413 ·
> #418 · #419 · #396), scored from every archive on the Mac plus the system
> rows nobody had read. This block is the cluster's one-page home; the
> other four entries carry only what is theirs and point here.** Runtime
> per #398-A: the 08-22 archives ran on `24A5418b`, the 08-26 and 08-30
> archives on `24A5424a` (device timeline, resolved by date).
>
> ### A correction first — this entry's "ROOT CAUSE of the blind guard" is falsified on its own archive
>
> The 19:56 block blamed `conversation.item.created` (`:825`) for zeroing the
> playback tracker mid-utterance. In that very archive `audio.started` is at
> **31.813**, the "idle" `speech_started` at **33.285**, and the NEXT
> `response.created` at **36.454** — an assistant item follows its own
> `response.created`, so **no item arrived in the window**, and the item
> handler never writes `voiceState`, so it cannot print `state=listening`.
> The only code that nils the stamp AND sets `.listening` is
> `finalizeAssistantText` (`:1196`), which runs on
> `response.output_audio_transcript.done` — an event this entry itself
> established arrives ahead of playout. Named with the three log lines and
> fixed under **#419-B** (bars there). 138-J's stated cause is therefore
> retired (its invariant is harmless and 419-A1 still watches it); **138-K
> is retired by measurement**: `audio.cleared` lands in the SAME millisecond
> as an "idle" `speech_started` in three archives (`138e` 20:13:46.510,
> `whoGoesThere-415` 17:58:40.699, `138-fork` 19:56:33.285) — the server
> interrupts on its own under `interrupt_response: true`, so repairing the
> guard changes truncation accuracy and the log line, not audibility.
>
> ### The unread archive — `whoGoesThere-415` (08-26) holds #413's sessions
>
> #413 was filed from Owen's words with no log reading. The archive
> collected that night carries **four** realtime starts (all
> `MicrophoneBuiltIn → Speaker`, confirmed from `corespeechd`'s
> `CurrentRoute` rows at 17:58:32.8 / 36.5 and `New Record Route:
> MicrophoneBuiltIn · New Playback Route: Speaker` at 22:17:24.16).
> Scored per utterance, offset = first `speech_started` after
> `audio.started`:
>
> | archive (build) | start | utt | offset | guard read |
> |---|---|---|---|---|
> | 138-fork (24A5418b) | 08-22 19:56 | u1 | clean 2.19 s | |
> | | | u2 | **+1.47 s** | idle (`state=listening`) |
> | | 08-22 19:57 | u1 | **+0.25 s** | BARGE-IN |
> | | | u2 | +2.44 s | BARGE-IN — user-attributable, unresolved |
> | | | u3 | clean 14.2 s | |
> | 138e (24A5418b, `server_vad` 0.8) | 08-22 20:13 | u1 | **+0.52 s** | idle |
> | | | u2 | clean 2.5 s | |
> | 415 (24A5424a) | 08-26 17:58 | u1 | **+0.58 s** | idle |
> | | | u2 | clean 2.55 s | |
> | | | u3 | +0.40 s | BARGE-IN — attribution unknown |
> | | | u4 | +0.84 s | BARGE-IN — attribution unknown |
> | | 08-26 18:01 | u1 | **+0.36 s** | BARGE-IN |
> | | | u2 | clean to end (1.9 s) | |
> | | 08-26 22:17 | u1 | **+0.27 s** | BARGE-IN |
> | | | u2 | clean 2.96 s | |
> | | | u3 | clean to end (10.7 s) | |
> | | 08-26 22:18 | u1 | **clean 1.84 s** | |
> | 413-airpods (24A5424a, AirPods) | 08-30 23:19 | u1–u3 | clean 2.16 / 12.15 / 3.77 s | |
>
> **Read:** on speakerphone, **5 of 7 first utterances are dirty, and every
> dirty one lands 0.25–0.58 s after `audio.started`** — the onset of the
> assistant's audio, never its body. Two clean first utterances (19:56,
> 22:18) mean "first utterance only" is a strong tendency, not a law; the
> +1.47 s phantom on a SECOND utterance (after a 4.2 s silence gap, Owen
> silent by his own report) means it is not first-only either. The
> `state=` field also separates two populations: offsets ≤0.36 s were
> caught by the guard (`BARGE-IN`), offsets ≥0.52 s were not — that seam is
> where transcript-done lands for a short greeting, i.e. #419-B's bug, not
> two mechanisms.
>
> **Also settled from the system rows, before anyone proposes it:** the first
> playout does NOT restart the audio unit or move the route. One `Starting
> AURemoteIO` per session (17:58:36.583, at HOT), and **zero**
> `com.apple.coreaudio`/`avfaudio` rows in 22:17:30–33 around the 22:17:31.178
> first `audio.started` (same-day archive, rows retained). n=2 sessions.
>
> ### What is PROVEN · FALSIFIED · BELIEVED
>
> | status | claim | instrument |
> |---|---|---|
> | **PROVEN** | self-capture is real, reproducible, and it is the assistant's own audio | 138-A 4/4 + the phantom texts; `speech_started` inside playback windows across 6 sessions |
> | **PROVEN** | the phantom is ONSET-bound: ≤0.6 s after `audio.started` on every dirty first utterance | the table above |
> | **PROVEN** | it is one session in a loop, not two engines | no `falling back` line; `speech_started → response.created → audio.started` ×7 |
> | **PROVEN** | the server interrupts by itself; our guard does not decide audibility | same-ms `audio.cleared` after an "idle" `speech_started`, ×3 archives |
> | **PROVEN** | the playback counter is zeroed by transcript-done, not by item arrival | #419-B's three lines; falsified-on-own-archive above |
> | **FALSIFIED** | AEC convergence as the SOLE mechanism (first-only) | 19:56 u2 at +1.47 s; 22:18 clean first utterance |
> | **FALSIFIED** | the +500 ms speaker override | 138-B built, 2955 tested, phantoms persisted |
> | **FALSIFIED** | a `server_vad` threshold can reject it | 138-E @0.8: faithful "Good afternoon." at +0.52 s |
> | **FALSIFIED** | two engines / our cancel path / the transcript as a barge-in instrument | 08-22 blocks above |
> | **FALSIFIED** | an audio-unit restart or route move at first playout | coreaudio rows, n=2 |
> | **BELIEVED (n=1)** | the path is ACOUSTIC (speaker → mic), not a software loopback | AirPods 0/3 clean vs 5/7 speakerphone — Fisher one-sided p≈0.375 at n=1; 0.167 / 0.083 / **0.045** at 2 / 3 / 4 clean AirPods sessions |
> | **BELIEVED** | the residual is level-dependent (speaker at max volume, `forceSpeakerIfNeeded`'s stated purpose) | UNTESTED — card V1 below |
>
> **One family or several?** #138 and #413 are ONE fault (onset residual on
> the speakerphone route; #413 is 138-A's observation re-filed with a
> device pass). #419 is an app-state bug independent of acoustics. #418 is a
> DIFFERENT input-quality fault (the AirPods telephony link — measured under
> #418) that shares only the recognizer's failure mode with the phantom text.
>
> **What the CJK signature says about the bytes the server received:** short
> (`prefix_padding_ms` 300 + a few hundred ms of onset), speech-shaped,
> low-SNR fragments — not silence (a silent commit transcribes empty, and the
> app DROPS empty transcripts, so silent phantoms would show in the log and
> never as a bubble), and not a clean software copy (a clean copy would
> transcribe faithfully every time; exactly one of ~9 phantom texts did, and
> it was the +0.52 s one, where an onset residual is strongest).
> Random-language tokens on sub-second low-SNR audio with `language` unset
> are the known hallucination mode of this recognizer family, and the SAME
> mode fired on Owen's real speech over the AirPods link (#418) — two
> different degradations, one fingerprint.
>
> ### Ranked hypotheses, each with its cheapest discriminator
>
> 1. **H1 — onset residual through a WORKING canceller, level-dependent.** The
>    mic hears the assistant only for the first few hundred ms of each
>    utterance, before the canceller/AGC settles on the new far-end signal;
>    at max speaker volume the residual clears server VAD. Fits every row.
>    **Discriminator: the VOLUME arm (card V1)** — speakerphone at ~2 bars
>    vs max, ≥3 starts each, score onset `speech_started` ≤1.0 s after
>    `audio.started`. Low ≤1/3 dirty AND max ≥2/3 ⇒ H1. Both ≥2/3 ⇒ not a
>    speaker-level effect (mic-side AGC or software next). Attended, ~5 min,
>    no build.
> 2. **H2 — AEC initial convergence.** Subsumed by H1 for the session's first
>    utterance; falsified as the sole mechanism (the archive table above). No separate test owed.
> 3. **H3 — the server's `prefix_padding_ms` shapes the fragment** (not a
>    cause; decides what the transcriber sees). **Discriminator: 138-M** —
>    log `input_audio_buffer.speech_stopped` segment length and the offset
>    from `audio.started` (card V3). Phantoms should read 300–700 ms
>    segments; a phantom ≥1.5 s would say the whole utterance leaks and H1
>    is wrong about "onset".
> 4. **H4 — software loopback.** Disfavoured by AirPods n=1 and by source (no
>    PCM handling on the realtime path; WebRTC owns both directions).
>    **Discriminator: the next incidental AirPods session, free** (card V2).
> 5. **H5–H8** (route override, IO restart, threshold, two engines) —
>    falsified, table above; do not re-test.
>
> ### Cards for Owen's election (runbook shape)
>
> - **V1 · 138-N — the VOLUME arm.** *Precondition:* realtime engine, Normal
>   preset, speakerphone (`#418 route at session start:
>   in=[MicrophoneBuiltIn …] out=[Speaker …]`), same room, no TV. *Steps:*
>   3 starts at ~2 bars — say only "hello", stay silent 10 s, end; then 3
>   starts at max volume, same script. *Claude scores from the log:* per
>   session, first `audio.started` → any `speech_started`/`BARGE-IN` within
>   1.0 s; also the `audio.stopped after Nms` values (419-B's device
>   confirmation rides free). *PASS (H1):* low ≤1/3, max ≥2/3. *FAIL:* both
>   arms ≥2/3 — level-independent, next arm is the mic side.
>   **⟵ RECORD, added 2026-09-02 when 138-M shipped (`grep '#138 segment'`):
>   quote EVERY `#138 segment` line of the run verbatim — `speech_stopped`
>   (`segmentMs=` + `offsetFromPlaybackMs=`), `committed`, and `transcript`
>   (`chars=` + `script=`). They are what scores H3's 300–700 ms prediction
>   against each arm, and V1's low-volume arm is the first chance to see
>   whether the segment LENGTH moves with level or only its frequency does.
>   `offsetFromPlaybackMs=none` means no `audio.started` had fired yet —
>   never read it as `0`.**
> - **V2 · 413/138-L extension — every incidental AirPods session, free.**
>   *Scores:* zero `speech_started` inside any playback window; the two
>   `#418 route` lines (prediction from the 08-30 system rows: the START
>   line reads `MicrophoneBuiltIn → Speaker`, and a `route after change`
>   line flips to `BluetoothHFP "Owen's AirPods Pro"` within ~1 s of HOT —
>   a start line already on BluetoothHFP means a different timeline);
>   `sampleRate=` answers #418 candidate 1's number. Four clean sessions
>   take the acoustic reading to p≈0.045.
>   **⟵ RECORD, added 2026-09-02 when 138-M shipped (`grep '#138 segment'`):
>   quote every `#138 segment` line here too. On AirPods this card's whole
>   claim is an ABSENCE (no phantom), and an absence bar with no positive
>   control passes on an empty log — the `transcript`/`committed` lines are
>   that control, because Owen's REAL turns emit them. A clean AirPods
>   session should therefore show `#138 segment` lines whose
>   `offsetFromPlaybackMs` is large or `none`, not zero of them; zero means
>   the session did not exercise the path and the reading is INVALID rather
>   than clean. The `script=` field also carries #418's own question: Owen's
>   English over the AirPods link reading `cjk`/`other` is the recognizer
>   degradation, not a phantom.**
> - **V3 · 138-M — the segment instrument (build; headless; no device to
>   ship).** Ungated `.notice` on `speech_stopped` (segment ms + offset
>   from `audio.started`), on `committed`, and on
>   `input_audio_transcription.completed` carrying transcript LENGTH and
>   script class (Latin/CJK/other) — never the text. Pure formatter,
>   RED-first, the 418/419 shape. Makes the CJK signature log-scorable.
> - **V4 · 418-B — pin the transcription `language` host-side** (plugin,
>   Owen's per-experiment go; see #418). Cheapest change with two payoffs:
>   #418's real speech, and phantom bubbles becoming faithful English
>   fragments (or empty → dropped) instead of `嗨`. 396-D binds
>   (before/after recorded).
> - **V5 · 138-O — the ONSET GATE (candidate FIX, proposed not built).**
>   Because every unambiguous phantom lands ≤0.6 s after `audio.started`,
>   disable the local `RTCAudioTrack` from `audio.started` for a named
>   ~700 ms and re-enable — an onset gate, not #130's half-duplex. Keeps
>   real barge-in after 0.7 s; cost is that a barge-in inside the first
>   0.7 s waits 0.7 s. Bars to pre-register when elected: (a) constant is
>   named and logged (`#138 onset gate: uplink muted Nms`), (b) barge-in at
>   +2 s still cuts the assistant (unit + device), (c) ≥3 speakerphone
>   starts with 0/3 onset phantoms, (d) V1 run first so the gate is not a
>   patch over a volume tradeoff nobody measured.
>
> **The single most valuable next measurement is V1** — five minutes, no
> build, splits the surviving hypothesis on its one untested prediction,
> and its log doubles as 419-B's device confirmation.

---

> **📋 2026-09-01 night — 138-M (card V3, the SEGMENT INSTRUMENT) OPENED AS A BUILD LANE — Owen's mandate: everything buildable comes off the board; V3 is the one voice card that needs no device to ship.** Sequenced AFTER the 396-Q/198B-M instrument lane merges (same files). Bars pre-registered before code:
> - **138-M-A (three always-on `.notice` lines, pure formatters, the 418/419 shape):** on `input_audio_buffer.speech_stopped` — segment length ms and offset from the last `audio.started` (or `none`); on `input_audio_buffer.committed` — the same offset; on `conversation.item.input_audio_transcription.completed` — transcript LENGTH (chars) and SCRIPT CLASS (latin / cjk / other / empty) — **never the text**. Each formatter pinned by `VoiceInstrumentLogLineTests`, RED-first, one mutation per formatter re-reddening exactly its pin. [offline]
> - **138-M-B (H3's prediction is written before the first read):** phantoms should read 300–700 ms segments at onset offsets ≤0.6 s with script=cjk/other; a phantom segment ≥1.5 s falsifies "onset" (H1 is wrong about the mechanism's shape). Recorded here so the first archive is scored against a prediction, not a story. [offline]
> - **138-M-GATE:** lane-gate PASS; the V1/V2 runbook cards gain "quote the `#138 segment` lines" in Record. [Mac]

> **✅ 2026-09-02 — 138-M RESULT (card V3, the SEGMENT INSTRUMENT): three
> always-on `#138 segment` lines are in, RED-first and mutation-proven. PR
> #418, squash `60dd9641`. All three bars MET.** Built headless on
> `CC-lane-3`, sim runtime iOS 27.0 `24A5423a` (#398-A: the phone is
> `24A5424a` — this is an instrument, not a rate, so the skew does not
> qualify the result).
>
> ### 138-M-A — MET. The three shapes, verbatim and equality-pinned
>
> ```
> #138 segment speech_stopped segmentMs=500 offsetFromPlaybackMs=520
> #138 segment committed offsetFromPlaybackMs=340 itemId=item_9
> #138 segment transcript chars=4 script=cjk itemId=item_9
> ```
>
> Each is a `nonisolated static` pure formatter on `LiveVoiceSessionService`
> (`:1466`, `:1485`, `:1512`), emitted `.notice` / `privacy: .public` /
> un-gated at `:897`, `:899`, `:1023`. **The whole shape is pinned by
> equality**, not just its fields — the runbook's Record step and every
> archive grep are written against it, and a reordered or extra field would
> break a reader who never runs the suite.
>
> **Two readings the shapes refuse to fake, both pinned:**
> `offsetFromPlaybackMs=none` is never `=0` (zero would say the segment landed
> exactly at playback onset — the single most incriminating value this
> instrument can print, so a session that has played no audio cannot render it
> by accident), and `segmentMs=unknown` is never `=0` (manufacturing a
> zero-length segment would fabricate the very reading H3 is being tested on).
>
> **The transcript's TEXT is never logged, and that is pinned rather than
> trusted:** the privacy test passes `嗨。再考` and asserts the line contains
> neither the string nor any one of its characters. A device archive is
> collected wholesale and shared; an instrument that leaked what Owen said
> would be a privacy defect shipped in the name of a measurement. A CJK string
> is used deliberately — none of its characters can appear incidentally in the
> line's own field names, so a leak of even one character is unambiguous.
>
> **RED first, against stubs returning the bare prefix:**
> `✘ Test run with 20 tests in 1 suite failed after 0.012 seconds with 19 issues.`
> — all 19 in the six new tests, the 14 incumbent pins green throughout.
> **GREEN:** `✔ Test run with 20 tests in 1 suite passed after 0.007 seconds.`
> The count MOVED, 14 → 20, which is the check `test-without-building` can
> otherwise fake.
>
> **One mutation per formatter, each reddening exactly its own pins:**
>
> | mutation | issues | tests reddened | untouched |
> |---|---|---|---|
> | drop `segmentMs=` from `speechStoppedSegmentLogDetail` | 3 | the 2 that assert a segment length (`segmentMs=500`, `segmentMs=unknown`) + the equality pin | 18 |
> | drop `offsetFromPlaybackMs=` from `bufferCommittedSegmentLogDetail` | 2 | 1 (`committedCarriesOffsetAndItem`) | 19 |
> | drop `script=` from `transcriptSegmentLogDetail` | 11 | 2 (the privacy pin's class arm + all four class arms) | 18 |
>
> "Nothing else" is bounded, not assumed: `grep -rl SegmentLogDetail` over the
> whole tree returns exactly the service and its pin file, so no other suite
> can see these formatters.
>
> ### The diff outside the formatters is four lines and two stamps
>
> Three `.notice` calls, plus the minimal `input_audio_buffer.speech_stopped`
> decode — **an event that drove no app state before and drives none now** (it
> fell to `default: break`). No behaviour change; `git diff` on the service is
> 100% insertions.
>
> **The offset reads a NEW stamp, and the reason is the point of the
> instrument.** `lastAudioStartedAtUptime` (`:936`) is deliberately separate
> from `assistantAudioPlaybackStartedAtUptime`, which the audio-buffer
> lifecycle nils at `stopped`/`cleared` — and this entry's own 09-01 synthesis
> established that **the server interrupts by itself**, landing `audio.cleared`
> in the same millisecond as an "idle" `speech_started` in three archives. A
> phantom's `speech_stopped` or `committed` therefore arrives just AFTER the
> tracker was nil'd, and reading the old stamp would have printed `none` on
> exactly the cases #138 exists to measure. Both stamps clear with the session.
>
> ### ⚠️ Read the offset correctly — it is the segment's END, not its onset
>
> The ≤0.6 s figures in the 09-01 table are measured from `speech_started`.
> `#138 segment speech_stopped`'s `offsetFromPlaybackMs` is stamped at
> `speech_stopped`, i.e. after the segment finished, so
> **onset ≈ `offsetFromPlaybackMs` − `segmentMs`** and that is the number to
> compare against the table. `committed` is later still. Scoring the raw
> `speech_stopped` offset against "≤0.6 s" would read every real phantom as
> falsifying the onset hypothesis it confirms — the same shape as this entry's
> own falsified "phantom turn" wording, and worth stating before anyone reads
> the first archive.
>
> ### 138-M-B — MET. H3's prediction, written BEFORE the first read
>
> **H3 (`prefix_padding_ms` shapes the fragment the transcriber sees).**
> Scoring a phantom = a `speech_started` inside a playback window, per the
> 09-01 table's method.
>
> | H3 predicts | falsified by |
> |---|---|
> | `segmentMs` in **300–700** ms | a phantom at **≥1500 ms** — the whole utterance leaks, and H1 is wrong about "onset" as the mechanism's shape |
> | derived onset (`offset − segmentMs`) **≤600** ms | onsets spread across the body of the utterance with no clustering at playback start |
> | `script=` **cjk or other** on phantom items | `script=latin` with a faithful English fragment, which would say the residue is a clean copy and re-open the software-loopback branch (H4) |
> | `chars` small (single-digit to low teens) | a long faithful transcript — same reading as above |
>
> **The 300 ms floor is not free** — it is `prefix_padding_ms`'s own value, so
> a segment measuring *below* 300 ms would say the server is not padding the
> way we believe, which is a finding about the config rather than about the
> echo. And the prediction is deliberately falsifiable in the direction that
> costs the most: **a ≥1.5 s phantom segment retires H1's shape**, which is
> currently the only surviving mechanism on this entry.
>
> **Real user turns are the positive control** and cost nothing: they emit the
> same three lines with a large or `none` offset. A session with ZERO
> `#138 segment` lines did not exercise the path, and its reading is INVALID
> rather than clean — the absence-bar trap #198B-A was built to close.
>
> ### 138-M-GATE — MET
>
> `GATE: PASS` on `CC-lane-3`, first run, no re-runs: **2846 Swift Testing
> tests / 244 suites** (baseline 2840 → +6, exactly the new pins),
> **15 XCUITest** (30 `Test Case '-[` lines, 15 passed, 0 failed — #219's
> `testConnectedRelaunchSkipsTheConnectEntry` did not fire), Release build
> green. `xcodegen generate` produced no diff (no files added). Entry set
> **430 → 430** across both tracker files, checked before and after the
> rebase; `scripts/oi-invariants.py` PASS, unpiped, exit 0.
>
> The V1 and V2 cards above gained their Record line (`grep '#138 segment'`),
> which is the rest of this bar.
>
> ### 🔴 The gate was RED on `main` before this lane touched anything
>
> The first gate invocation failed in **preflight**, on a clean rebase:
>
> ```
>   FAIL  failure-advice classifier SELF-TEST FAILED — the gate's advice cannot be trusted
>           FAIL  hint finds NOTHING in OPEN_ITEMS.md: runner dies mid-bundle
>           FAIL  hint finds NOTHING in OPEN_ITEMS.md: runner dies mid-bundle
>         CLASSIFIER: FAIL (2 of 24 checks)
> ```
>
> **Sweep 14 archived #219 the night before, and the gate greps that phrase in
> `OPEN_ITEMS.md`.** Every gate run on `main` had been failing before reaching
> a single test — the verdict is scored in preflight, so the suite result never
> mattered. Fixed in the same PR: both hints repointed to
> `OPEN_ITEMS-ARCHIVE.md` (#313's shape), CLAUDE.md's "in the live board"
> wording corrected, a dated append-only pointer filed under archived #219 per
> #317(a), and the sweep-reds-the-gate hazard written into CLAUDE.md where the
> next sweep will meet it.
>
> **And the documented repair used to SILENCE the check rather than satisfy
> it.** `lane-gate-classify-test.sh` both extracted and resolved hints against
> `OPEN_ITEMS.md` alone — so repointing a swept hint at the archive, which is
> exactly what #313 prescribed, moved it out of the checker's sight.
> `CondenserFidelityTests` had been unverified on that account since
> 2026-08-18; this lane is the first time anything executed it (38 hits). The
> self-test now resolves each hint against the file it NAMES, and was proven
> fail-safe by injecting a pointer matching neither file (`FAIL (1 of 26)`,
> reverted). Ladder: `FAIL (2 of 24)` → widened only `FAIL (1 of 25)` →
> widened + repointed `PASS (25 checks)`.
>
> ### What 138-M does NOT do
>
> It measures nothing on its own. **V1 (138-N, the volume arm) is still the
> single most valuable next measurement** — five minutes, no build — and V3
> exists to make its log say more than "a phantom happened". Nothing here
> touches audibility, the onset gate (V5 · 138-O) stays proposed-not-built, and
> no hypothesis on this entry changes status until an archive is scored.

> **📱 2026-09-02 07:29 — FIELD OBSERVATION (Owen, screenshot; office, "super quiet", nobody else in; OJAMD profile, KIMI-K3, uncorded — remoted into the Mac, so no same-day `log collect` unless a cord appears).** One real utterance ("Hello.") → **two phantoms in a 13 s session**: `"Alude."` (garbage, Latin-scripted) after *"Hello there. How can I help you today?"*, then **`"Hi there."` — a FAITHFUL copy of the reply's first two words** after *"Hi there. I'm here and ready to help…"*. Each phantom earned a new reply; the loop ran three turns. **What it adds to the 09-01 synthesis:** (1) a QUIET room removes ambient noise as a candidate — the captured audio is the assistant's own; (2) one faithful + one garbage phantom in the same session is the onset-residual signature (faithful when the residual is strong, garbage when weak), not a software copy (which would be faithful every time); (3) the faithful fragment is the reply's OPENING words — onset, not body. **Unknowns that decide which card this scores:** speakerphone vs AirPods (V2's discriminator — a phantom on AirPods puts H4 back on the table), the build (3147 Debug has none of the new instruments; 3201/3204 would have logged `#138 segment` lines and a non-zero `audio.stopped after Nms`), and the speaker volume (V1's variable). Recorded as N+1 pending those three answers; the screen-scored V1 (phantom bubbles per start, low vs max volume) is runnable today without a log.

> **📱 07:29 observation — the three unknowns answered (Owen, 09-02 morning): SPEAKERPHONE · build 3204-era (instruments present in the log if ever collected) · speaker at LOW volume, ~2 bars.** That third answer strains H1's level-dependence prediction before V1 has even run: V1 predicted the LOW arm at ≤1/3 dirty, and this session is 1/1 dirty with TWO phantoms — one of them faithful. One session is not the arm (V1 wants 3 low + 3 max), but if the low arm keeps reading dirty, "level-dependent" falls and the mic side (AGC) or the canceller's onset behaviour is next — the onset GATE (138-O) would still address the symptom either way, since the mechanism is still onset-bound. The log carrying the `#138 segment` lines and the 419-B confirmation exists on the phone but is uncollectable until a Mac + cable meets it (logd evicts app rows in hours).

> **📏 07:29 SESSION SCORED FROM THE LOG (2026-09-02 08:19 — the first UNCORDED collect: on-device sysdiagnose → Taildrop → Mac; 99 app rows, every 3204 instrument present; archive preserved at `~/.talaria-instrument-runs/20260902-0729-sysdiagnose/`).** Route `MicrophoneBuiltIn → Speaker`, 48 kHz; preset **normal** (`values=host hostAccepts=[quiet,normal,noisy]`); speaker at ~2 bars (Owen). Timeline: real "Hello." 43.645→44.450 (segment 1328 ms, 6 chars latin) · reply 1 `audio.started` 44.988 · **BARGE-IN +0.60 s** (`audio.cleared after 601ms`) · phantom 1 `speech_stopped` at +4490 ms, **segmentMs=1336**, transcript 6 chars latin (`"Alude."`) · reply 2 `audio.started` 49.854 · **BARGE-IN +0.58 s** (`audio.cleared after 577ms`) · phantom 2 `speech_stopped` at +1526 ms, **segmentMs=1464**, 9 chars latin (`"Hi there."`) · reply 3 starts 51.755 · session ended 53.27. No `audio.stopped after Nms` line exists because every playback was CUT by a phantom — **419-B's device confirmation is NOT readable from this session** (honest gap; it needs a playback that ends naturally).
> **What it settles and what it opens:**
> - **V1 low arm, first start: DIRTY (2 phantoms)** at +0.58/+0.60 s — both at the LATE edge of the 0.25–0.60 s onset band, which is what a weaker residual taking longer to trip VAD looks like. One start is not the arm, but it already argues against "level-dependent" in the OCCURRENCE sense; level may govern TIMING instead.
> - **H3's segment prediction (300–700 ms) is MISSED in the long direction: 1336 and 1464 ms** — under the 1500 ms "onset is wrong" falsifier, but not by much. Phantom 2's onset by the lane's own arithmetic (offset − segment) is **+62 ms server-time**, i.e. detected onset ≈ +360 ms after prefix padding, VAD trip at +576 ms — internally consistent. Phantom 1's arithmetic puts its END 4.5 s after playback with a 1.3 s segment — which does NOT sit with its +0.60 s trip unless the server kept hearing speech ~1 s past the cancel and then waited a long silence window. **Candidate mechanism, NEW: the barge-in cancel does not silence the speaker instantly — audio already received keeps playing out of the WebRTC playout buffer for up to ~1 s, and the mic keeps hearing it.** That would explain both the >1 s segments and why phantom 2 is a FAITHFUL "Hi there." (≈1 s of the reply captured cleanly) while the 09-01 table's shorter phantoms were garbage. **Free discriminator — Owen's ear:** after a phantom cuts the assistant, does the voice stop dead or trail off for about a second? (Asked 09-02.)
> - Both phantoms transcribed LATIN this time (no CJK) — the language-pin decision (418-B) is unaffected either way.
> - Also seen, not scored: the route bounced Speaker → Receiver → Speaker at 40.8–41.3 s with four `realtime-carplay-reassert` activations in the first 4 s, before capture went HOT. Recorded for the next reader.
> **Consequence for 138-O (the onset gate):** if the post-cancel drain is real, a 700 ms uplink mute at each `audio.started` still prevents the FIRST trip (the whole loop starts there), but the gate's bars must add: after a genuine barge-in the mute must not re-arm on the residual of the cancelled reply.

> **🎯 09-02 08:3x — TWO FACTS SETTLE THE 07:29 ANOMALY, AND THE GATE IS READY TO ELECT.**
> 1. **Owen's ear (the free discriminator): "It stopped dead, instantly."** The post-cancel playout-drain candidate above is **FALSIFIED** — the speaker is silent at the cut, so the acoustic residual is ONSET-ONLY (≤0.6 s), exactly as the 09-01 table said.
> 2. **`preset=normal` is SEMANTIC VAD, from source:** `voice.py:178` — `if tuning is None or tuning == "normal": return None` (the env-resolved default), and both hosts' env default was measured 08-22 as `semantic_vad, create true, interrupt true, eagerness medium`. Only `quiet`/`noisy` are `server_vad`. **So the 1336/1464 ms segments are semantic VAD's OPINION of the speech span, not acoustic residual** — and its eagerness explains the timing that did not add up: the nonsense fragment `"Alude."` made it wait ~2.85 s for more speech; the complete-sounding `"Hi there."` ended the turn at once. **Consequences:** H3's 300–700 ms prediction is UNSCORABLE on `normal`; the 138-M segment instrument is diagnostic only under `server_vad` (V1/V2 should run on QUIET when segment timing matters); and semantic eagerness is why one phantom loops instantly and another stalls.
> **Recommendation put to Owen (09-02): ELECT 138-O now.** The condition the Desk Board attached ("after V1 reads level-dependent") is answered by V1's first start — dirty at LOW volume, trips at +0.58/+0.60 s — level governs timing, not occurrence. Every phantom in five archives trips 0.36–0.60 s after `audio.started` on speakerphone; the speaker is dead at the cut; the residual is onset-only. Gate window: **800 ms** from each `audio.started` (the observed trips reach 0.60 s; 700 ms is at the edge), constant named and logged, re-armed ONLY by a new `audio.started` (never by a cancel), real barge-in after the window unchanged (unit + device), device bar 0/3 onset phantoms at LOW volume (the harder arm) and 0/3 at max, V1's remaining starts folded in.

> **⚖️ ELECTED 2026-09-02 (Owen, AskUserQuestion): BUILD 138-O NOW, merge on green.** Bars pre-registered before code (the investigator's (a)–(d) plus this morning's two):
> - **138-O-A (the window is a named, logged constant):** the local uplink (`RTCAudioTrack.isEnabled = false`) is muted from each `audio.started` for **800 ms** and re-enabled by a timer; the constant lives in one place, and one always-on `.notice` per arming names it — `#138 onset gate: uplink muted 800ms` — plus one on release (`#138 onset gate: uplink restored`). Pure formatter pinned in `VoiceInstrumentLogLineTests`, RED-first. [offline]
> - **138-O-B (re-armed only by a NEW playback, never by a cancel):** a barge-in/cancel, `audio.cleared`, `finalizeAssistantText`, or a route change does not re-arm the gate; only the next `audio.started` does. Unit-pinned with a scripted event sequence; mutation (re-arm on cancel) must red exactly that pin. [offline]
> - **138-O-C (real barge-in after the window is untouched):** a `speech_started` at +2 s into playback still cancels the assistant exactly as today — the four pre-existing barge-in pins in `AppStoresTests` stay GREEN untouched, plus one new pin that a speech_started INSIDE the window is ignored and one AT +2 s is honoured. [offline]
> - **138-O-D (no capture-state lie):** while the gate holds, the app's capture-chain state and the #302/#415 markers are unchanged (the mic is not "off" — the TRACK is muted); `capture chain HOT/COLD` lines are not emitted by the gate. Structural pin. [offline]
> - **138-O-E (device, rides the next OTA — REPLACES V1 as the runbook card):** speakerphone, `normal` preset, say only "hello", silent 10 s, end — **3 starts at ~2 bars AND 3 starts at max: 0/3 onset phantoms in each arm**, scored from the log (`#138 onset gate` lines present at every `audio.started`; zero `BARGE-IN` inside 0.8 s; the first `audio.stopped after Nms` that is non-zero also closes 419-B). A phantom AFTER the window is a new finding, not this bar's fail. [device — Owen]
> - **138-O-GATE:** `lane-gate.sh` PASS, count moved; the entry-set check across the rebase. [Mac]
> Scope fences: no change to the host, the preset, the canceller, or `forceSpeakerIfNeeded`; the gate is app-side only and its window is the one tunable.

> **✅ 2026-09-02 — 138-O RESULT (card V5, THE ONSET GATE): the local uplink
> track is disabled for a named 800 ms from every `audio.started` and restored
> by a cancellable, session-scoped timer that only a NEW playback re-arms.
> RED-first, three mutations, PR #420, squash `363f3265`. Bars
> 138-O-A/B/C/D and 138-O-GATE MET; 138-O-E is OWED on device.** Built headless
> on `CC-lane-3`, sim runtime iOS 27.0 `24A5423a` (#398-A: the phone is
> `24A5424a` — and here the skew is the POINT rather than a caveat. This lane
> ships a MECHANISM, not a rate; whether it removes the phantom is not
> simulator-answerable at all, and 138-O-E is the bar that measures it.)
>
> ### 138-O-A — MET. One constant, and three always-on lines
>
> `LiveVoiceSessionService.onsetGateWindowMilliseconds = 800` —
> `Talaria/Services/Live/LiveVoiceSessionService.swift:1431`. The fix's one
> tunable and its only home. The two lines the bar named, verbatim:
>
> ```
> #138 onset gate: uplink muted 800ms
> #138 onset gate: uplink restored
> ```
>
> Both were observed emitting live in the green gate's own suite log (6 armings,
> 4 releases — the two unmatched armings are the pins that end while the window
> is still open, which is the reading `cancelOnsetGate` deliberately leaves
> honest).
>
> **A THIRD line ships that the bar did not name, and 138-O-E is the reason:**
>
> ```
> #138 onset gate: speech_started suppressed 312ms into the 800ms window
> ```
>
> 138-O-E is an ABSENCE bar — zero `#138 BARGE-IN` inside 0.8 s — and an
> absence with no positive control passes on an empty log. That is the trap
> #198B-A was built to close, and the one the V1/V2 cards had to bolt onto
> #138-M in a later edit. Without this line a clean device run cannot separate
> *the gate held* from *the server never sent a `speech_started`*, and those two
> readings take opposite next moves. Additive to the bar, never in place of it.
>
> All three are `nonisolated static` pure formatters (`:1518`, `:1525`,
> `:1533`), emitted `.notice` / `privacy: .public` / **un-gated** — no
> `#if DEBUG`, no `verboseLogging` (#218), and 138-O-D's structural pin asserts
> that against the source rather than trusting it. **The window is READ from the
> constant, not restated:** a pin passes `windowMs: 1234` and requires
> `uplink muted 1234ms`, so a build with a different window cannot print 800.
>
> **Why 800 and not the card's proposed ~700.** The measured trips reach 0.60 s
> (09-02 08:19: +0.58 and +0.60 s), so 700 ms sits on the edge of the band the
> fix has to clear; 800 buys 200 ms of margin over the worst reading we hold.
> The stated cost is unchanged and bounded: a real barge-in inside the first
> 0.8 s of a reply waits 0.8 s.
>
> ### 138-O-B — MET. Re-armed only by a NEW playback
>
> `armOnsetGate()` has exactly ONE call site, `output_audio_buffer.started`
> (`:984`). The pin drives the whole scripted sequence:
>
> | t | event | required |
> |---|---|---|
> | 0 | `output_audio_buffer.started` | uplink disabled, gate holding |
> | +0.3 s | `input_audio_buffer.speech_started` | no cancel sent, state stays `.speaking` |
> | +0.5 s | `output_audio_buffer.cleared` + `output_audio_transcript.done` | window NOT extended |
> | by +1.1 s | — | uplink restored, gate not holding |
> | then | `cleared` + `transcript.done` + `handleAudioRouteChange` | still not holding |
> | then | `output_audio_buffer.started` | re-armed |
> | +2.0 s | `speech_started` | full cancel / clear / truncate, exactly as before |
>
> The release budget is anchored to the ARMING instant, not to "however long the
> previous step took" — a re-arm at +0.5 s moves the release to +1.3 s and has
> to be caught however slow the host is.
>
> ### 138-O-C — MET, and the pre-existing barge-in pins are BYTE-untouched
>
> `git diff --numstat` on both test files reads `233 0` and `56 0`: **pure
> insertions, zero deletions.** Nothing was rewritten to accommodate the gate,
> which is the half of this bar a passing suite alone cannot show. The pins are
> `liveVoiceSessionServiceInterruptsAssistantPlaybackOnSpeechStart` and
> `liveVoiceSessionServiceDoesNotInterruptWhenAssistantIsNotSpeaking` in
> `AppStoresTests`, plus #419-B's `bargeInAfterTranscriptDoneStillTruncates` and
> `audioLessResponseStillFinalizesToListening` in
> `AssistantPlaybackTrackingTests` — that third suite was pulled into every run
> of this lane precisely because two of its pins drive `speech_started` 80 ms
> into playback, i.e. inside the window this fix opens.
>
> **And the reason they still pass is the invariant, not an accommodation.** The
> gate suppresses only what it actually MUTED: `onsetGateIsHolding` means "we
> disabled an uplink", never "800 ms have not elapsed". A service that never
> stood up a peer connection has no uplink, so the gate never arms and
> `speech_started` behaves exactly as before. That is also the production rule —
> a gate that suppressed barge-in on a window it had not enforced would be
> claiming a mute that never happened, and would break real barge-in in any
> state where the mute did not take.
>
> **One further app-side change the bar implies and this entry states outright:**
> a suppressed `speech_started` no longer flips `voiceState` to `.listening`. It
> used to, unconditionally. Inside the window the assistant IS still speaking,
> and a state saying otherwise would be #419's defect in a new place — the UI
> reading "Listening" over live playback.
>
> ### 138-O-D — MET. No capture-state lie
>
> The mic is not off and the audio session is untouched; one TRACK is disabled.
> `capture chain HOT`/`COLD` (#302-A/#415) mean *microphone buffers are / are
> not leaving the device*, and a COLD line at every playback onset would read to
> an operator as the capture chain collapsing eight times a session.
>
> Pinned structurally, because the failure it guards is a line ADDED later by
> someone who thinks the gate should announce itself in the same vocabulary: the
> gate's own MARK section is read out of the source and asserted to contain none
> of `capture chain`, `AudioSessionOffMain`, `configureAudioSession`,
> `forceSpeakerIfNeeded`, `peerConnection`, `#if DEBUG`, `verboseLogging` — and
> the file's two capture-chain emissions are counted and required to stay at
> exactly one each. The behavioural half asserts `connectionState`,
> `voiceState`, `isMuted` and `audioRouteSummary` are unmoved across an arm and
> a release.
>
> ### RED first, and the count MOVED
>
> Against inert stubs (a no-op gate; formatters returning a bare `#138 onset
> gate`): **`✘ Test run with 162 tests in 2 suites failed after 12.180 seconds
> with 16 issues`** — all 16 in the eight new pins, every incumbent green
> throughout. One new pin deliberately passed in RED and had to:
> `aSpeechStartedAfterTheOnsetWindowStillCancelsTheAssistant` is the control
> that says barge-in worked before the gate existed.
> **GREEN: `✔ Test run with 167 tests in 3 suites passed after 13.500 seconds`.**
>
> ### Three mutations, each reddening what the bar said it would
>
> | mutation | issues | tests reddened | untouched |
> |---|---|---|---|
> | (i) re-arm on `output_audio_buffer.cleared` | 4 | **1** — `theOnsetGateIsReArmedOnlyByANewPlaybackNeverByACancel` | 166 |
> | (ii) window constant `800` → `0` | 7 | 4 — the inside-window pin (3 issues) **plus the three constant-readers** | 163 |
> | (iii) drop `\(windowMs)ms` from the arming formatter | 3 | 2 — both arming-line pins in `VoiceInstrumentLogLineTests` | 165 |
>
> Mutation (i) is the bar's own test and it reds **exactly** its pin. Mutation
> (ii) reds more than the bar named, and that is correct rather than sloppy:
> three pins exist specifically to notice a changed window, so a silent 800→0 is
> the one edit this fix cannot afford to ship unremarked.
>
> ### 138-O-GATE — MET, on the second roll
>
> `GATE: PASS` on `CC-lane-3`, runtime iOS 27.0 `24A5423a`: **2856 Swift Testing
> tests / 244 suites** (baseline 2846 → **+10, exactly the new pins — the count
> MOVED**), **15 XCUITest** (30 `Test Case '-[` lines, 15 passed, 0 failed),
> Release build green. `xcodegen generate` produced no diff (no files added).
> Entry set **430 → 430** across both tracker files, checked before and after
> the rebase (which was a no-op — `origin/main` was already `c0786a7d`).
>
> **Roll 1 was RED and it was #219's flake, not this diff:** the suite was
> identical — 2856 Swift Testing passed, Release green — and the single failure
> was `TalariaUITests.testConnectedRelaunchSkipsTheConnectEntry`, 14 passed /
> 1 failed / **15 ran**, with the assertion text *"a successful connect should
> land straight in chat (#137)"* at `AppTemplateUITests.swift:540`. That is
> #219's 2026-09-01 mechanism verbatim (per-test-instance un-hittable, runner
> alive, all 15 run), and it is that entry's declared reopen trigger. One
> identical-bytes re-roll, per the standing rule; the second was green and no
> third was taken. **Evidence preserved for #219 rather than discarded** — see
> the pointer filed under its archived entry.
>
> ### What the gate does NOT do
>
> It does not touch the host, the preset, the canceller or
> `forceSpeakerIfNeeded` — the scope fence holds. It measures nothing: whether
> the phantom is gone is **138-O-E's** question and the simulator cannot answer
> it. A phantom AFTER the window is a new finding, not this fix failing. One
> adjacent line changed for correctness and is named here so it is not found
> later as a surprise: `toggleMute()` now reads `!isMuted && !onsetGateIsHolding`,
> because an un-mute inside the window would otherwise defeat the gate for the
> rest of it; the release re-applies `!isMuted`, so the user's pick lands at
> worst 800 ms later.

> **🎉 2026-09-02 ~10:00 — FIRST FIELD RESULT ON THE GATE BUILD (Owen, build 3211, speakerphone): "It works. When it talks on speakerphone, it doesn't interrupt itself!"** Recorded as the FELT verdict — the first session on any build in this entry's history where the assistant finished its own sentences on speakerphone. **138-O-E is still OWED on the log** (the card's PASS needs the `#138 onset gate: speech_started suppressed Nms` positive control present — proof the server DID send the onset trip and the gate ate it — plus 0/3 at low AND max); a sysdiagnose taken after the session captures it. Volume for this session and whether a reply ran uncut (the 419-B confirmation) pending Owen's word.

> **10:0x — the field session's two unknowns (Owen): speaker at MAX (or near), and at least one reply ran UNCUT.** So the felt PASS is the LOUD arm (where the residual is strongest); the low arm is this morning's 1/1 dirty pre-gate session and still needs its three post-gate starts. The uncut reply means the archive should carry the first non-zero `audio.stopped after Nms` — **419-B's device confirmation rides in the same sysdiagnose.** Awaiting the Taildrop.

> **✅ 138-O-E — MAX ARM MET ON THE LOG (2026-09-02 19:59, home, corded `log collect`, build 3211, speakerphone, preset `normal`; archive `~/Desktop/talaria-138o-gate.logarchive`, copy under `~/.talaria-instrument-runs/20260902-138o-gate-collect/`).** One session, four user turns (6/29/62/28 chars, all latin), four assistant playbacks. At EVERY `audio.started` the gate armed and released — `uplink muted 800ms` / `uplink restored` pairs at 811 · 803 · 818 · 806 ms — **zero `BARGE-IN`, zero `audio.cleared`, zero phantom bubbles**, every `speech_started` in state=listening (Owen's real turns). Against the pre-gate speakerphone base rate at this volume (5 of 7 first utterances dirty, 08-26 archives): **0/4 vs 5/7, Fisher one-sided p≈0.045.** The felt verdict ("it doesn't interrupt itself") is now the measured one for the LOUD arm.
> **The card's positive-control clause was WRONG and is corrected here:** `#138 onset gate: speech_started suppressed Nms` fires only when the server's trip RACES the mute — with a source-side track mute that engages at `audio.started`, the server receives silence for the window and never sends a `speech_started`, so a perfect gate produces ZERO suppressed lines by construction. Absence is not INVALID; it is the gate working. The honest positive controls are (a) the muted/restored pair at every playback (present ×4), and (b) the pre-gate base rate on the same route. The suppressed line stays as a race witness. Runbook card re-cut accordingly.
> **Still owed on 138-O-E: the LOW arm** — three starts at ~2 bars (this morning's pre-gate low session was 1/1 dirty at +0.58/+0.60 s, so the gate's window is exactly where those trips lived). Then #138 closes as FIXED-with-a-gate.
> **Rides free: 419-B's device confirmation — MET.** `audio.stopped after 2280ms` · `3558ms` · `7180ms` — the counter is non-zero on device for the first time in this entry's history. Filed as a dated block under live #419 (which is now CLOSEABLE).

## 140. 🔧 README + GitHub Pages refresh — stale wedge narrative + pre-freemium positioning (pre-launch)

> **🔬 PREMISE RE-CHECKED 2026-08-25 (Owen's applicability rider on the
> election ballot) — the AS-FILED complaint is DISCHARGED, and a NEW,
> NARROWER staleness window is live.** The wedge narrative and pre-freemium
> positioning were fixed across 07-20 / the 08-04 redesign / the 08-09
> ruling / the 08-18 #355 sweep; no pricing claims exist anywhere. What IS
> stale at HEAD: **docs/ was last touched 08-18/19, so it missed #383 and
> #390.** The elected lane (Owen picked #140 on the 08-25 ballot) is:
> 1. docs/index.html + setup.html + screens.html: every "relay carries
>    realtime voice" / "relay's last surfaces = voice + agent-file
>    downloads" claim is FALSE since #383 (08-22) and #375 — re-cut to the
>    plugin-bootstrap reality README:81 already states; relay framing
>    "optional/legacy" → retired/not-called.
> 2. docs/setup.html:178: `Xcode-beta5.app` → beta6 (README moved 08-24).
> 3. docs/screens.html:7 meta description still claims "real captures …
>    running on hardware" — the 08-04 commit's own message says the page
>    stopped claiming that; the meta tag was missed.
> 4. README + docs gain the #390 VISION story (absent from both public
>    surfaces; privacy-relevant — on-device images never leave the phone,
>    PCC disclosure already live in privacy.html).
> **Deliberately NOT in this lane:** the screenshot batch (rides P-4,
> unchanged) and device rows R15/R16 (already runbook-carded). **⛔
> OUTWARD-FACING: docs/ is the live Pages root — the draft lands on a
> branch and MERGES ONLY on Owen's read of the exact text** (the
> no-external-submissions rule; his ballot pick elected the draft, not the
> publish).
>
> **📬 DRAFT COMPLETE 2026-08-25 — PR #373 OPEN, HELD for Owen's read.**
> 17 edits across 4 files (relay claims retired per #383/#375, the #390
> vision story added with the per-tier privacy split matching the amended
> policy, beta6 line, the screens meta leftover). The edit-by-edit list
> with honesty rationale is in the session's draft doc; the PR body
> carries the summary. **Merging PUBLISHES — nothing lands until his go.**
>
> **✅ PUBLISHED 2026-08-25 — Owen's go ("Looks good", answering the
> say-the-word-and-it-goes-live framing after the summary presented the
> two substantive new claims verbatim). MERGED PR #373, squash
> `47632a01`; all four surfaces verified LIVE on Pages post-merge.**
> The re-scoped lane is DONE. **What keeps this entry open:** the
> screenshot batch (rides P-4, now also pre-vision-UI stale) and device
> rows R15 (#140-D ATS mechanism) / R16 (56-U-H Siri hostless), both
> runbook-carded — nothing else.

> **⚖️ OWEN'S RULINGS 2026-08-09 (interactive decision pass) — the copy
> questions, decided:**
> - **"No cloud": QUALIFY THE COPY *AND* ADD THE INDICATOR.** The public line
>   becomes "no Talaria-operated cloud; realtime voice uses your host's
>   provider" (or equivalent), and the app shows a visible indicator when a
>   voice session runs on the realtime engine. This answers archived #221's
>   open product question in the same stroke — the app half is FILED as
>   **#320** (one decision, two surfaces, both corrected).
> - **140-D RUNS on device** (queued as device row §R15) — the ATS mechanism
>   text stays as-is until the run settles the four-document contradiction;
>   until then the disputed parenthetical is not re-published as verified.
> - **Siri-in-the-hostless-column: RUN 56-U-H** (queued as device row §R16)
>   rather than hedging the copy.

**Accuracy half DONE 2026-07-20 (`3367626`).** README status table corrected: voice row now
truthful (working, echo/connect hardening in progress — wedge claim removed); APNs row
current (BYO .p8 on the relay, T6-armed); sensor row states the #137 opt-in default.
**Record corrections from the pass:** README:77’s generic `Xcode-beta.app` path is CORRECT
for the public audience (Apple’s default install name; Xcode-beta3 is a local rename) — the
item overclaimed; and CLAUDE.md already references Xcode-beta3 throughout, no edit needed.
**Remaining (rides P-4):** docs/index.html positioning for the freemium free tier +
screenshot refresh, batched with the App Store screenshot pass so shots are produced once.

> **✏️ COPY HALF DONE 2026-08-04 (queue item 6, `claude/t27-140-docs-refresh` — Owen
> reviews via the PR).** The positioning copy was deliberately DECOUPLED from the
> P-4 screenshot batch: the launch pivot (local brain first, Hermes as the upgrade
> tier) plus Lane 5 (shim retired) plus #238 (notifications removed) had left both
> public surfaces actively wrong about what the app IS, and that could not wait on
> shots. Swept: README intro inverted to on-device-first; status table (model
> picking now gateway-native; the two notification rows honestly replaced with the
> removed-by-design row; inbox row de-pushed); architecture diagram and network
> notes down to two services with the shim named as retired; setup §5 is now
> "nothing to run"; relay env table marks APNs keys legacy. Pages site: title +
> meta + tagline + hero-sub repositioned, ON-DEVICE BRAIN feature card added, shim
> claims corrected in the diagram/service card/feature card/setup step, relay APNs
> mention dropped. **Still remaining, still batched with P-4: the screenshot
> refresh** (docs/img/ predates the theming + local-brain UI) — shots produced
> once, with the App Store pass.
>
> **Owen's read of the refreshed site, 2026-08-04 afternoon (post-merge,
> follow-up fix `93f4223` shrank both setup lists to six steps per his note):**
> *"better. I'm thinking a redesign is in the future, but I'll only ask for a
> handoff to Claude Design for that."* **A future Pages redesign is HIS to
> initiate via Claude Design; nothing queued here.**
>
> **✏️ REDESIGN SHIPPED 2026-08-04 night (PR #266, merge `a375bea`) — Owen
> initiated it exactly as forecast:** he brought a Claude Design handoff zip
> (three `.dc.html` pages) and approved launch after review. The export format
> needs a React host its files never load (blank on Pages), so the pages were
> BAKED to static HTML — index/screens/setup, two vanilla-JS widgets (channel
> demo, carousel). Content corrected against the codebase during the bake:
> **27→30 theme channels** (Cosmic Bowling / Sticker-Bomb Toybox / Comic
> Villain added with real `ThemePaletteCore` values), the "real captures from
> hardware" claim removed (docs/img are stylized renders — 9:41, STARK-WKSTN),
> an unsupported "end-to-end encrypted" pairing claim dropped, and
> `API_SERVER_KEY`'s `.env` location stated per-OS (README's line was wrong on
> Windows — fixed in the same PR). Verified live post-deploy: Pages build
> green on `a375bea`, screens.html 200, thirty-channels marker present.
> **Still remaining, still batched with P-4: the screenshot refresh** — the
> 13 renders predate the theming + local-brain UI and are now labeled
> honestly, but real captures replace them when the App Store pass runs.

**Logged 2026-07-20 (Owen).** Public-facing repo surfaces contradict current reality:
- **README:26** still claims voice is "currently wedged by an iOS 27 beta seed regression…
  revisit on the next seed" — that rule was DISPROVEN 2026-07-16 (root cause was app-side
  AVAudioSession deactivation churn, fixed PR #106; voice confirmed working on device).
- **README:77** points the toolchain at `Xcode-beta.app`; the standard is **Xcode-beta3**
  (same staleness CLAUDE.md was flagged for). README:125 "Xcode 27 beta" wording rides along.
- **docs/index.html (Pages):** no wedge text, but positioning predates the freemium decision
  — "built for self-hosters" framing and hero copy describe only the Connected tier; the
  free standalone on-device tier is absent. Screenshots (docs/img/) predate recent UI work
  (Midnight Marquee, sensor opt-in redesign) — refresh alongside the App Store screenshot
  pass (LAUNCH_PASS P-4) so the shots are produced once.

Scope: accuracy fixes are a micro-commit doable now; the positioning/screenshot refresh is a
launch-adjacent pass, naturally batched with P-4. Feature-status table (README:26 region)
deserves a full sweep — other rows likely stale too.

---

## 162. 🛠 156a Tasks lane — **SHIPPED, on `main`** (`Talaria/Features/Tasks/`, reachable at `ContentView.swift:246`); **device checklist still owed** — header corrected 2026-08-01

Dispatch `dispatch/FABLE-T27-156A-tasks-cron.md` executed 2026-07-22 on the Mac Mini
(Xcode-beta4 toolchain, upstream re-verified against the local hermes-agent 0.19.0
checkout at `d8bf3df255`). All six deliverables, one PR, zero new services (#161 held —
every request rides the `:8642` gateway with the chat path's `API_SERVER_KEY`).

**What shipped:** `CronJob` tolerant models + client-derived status (D2),
`CronJobService` over the eight `/api/jobs` endpoints with verbatim server-rejection
text (D1), `CronJobsStore` with the upsert/delete mutation seam (D3), TasksScreen /
TaskDetailScreen with the four explicit content states and non-destructive refresh
failure (D3), the structured schedule picker emitting the four verified
`parse_schedule` forms with Advanced as the free-text escape (D4 ⭐), the one
create/edit sheet on a diffing draft (D5), and 76 tests in 4 suites (D6). Entry point:
SCHEDULED TASKS row in the sessions drawer; routes `.tasks` / `.taskDetail(id)`.

**Upstream facts verified beyond the dispatch (all from source, 0.19.0):**
- `schedule.kind` vocabulary is exactly `once|interval|cron`; recurring = interval/cron.
- Every mutation answers `{"job": {...}}`; DELETE answers `{"ok": true}`; errors are
  `{"error": "<msg>"}` (400 validation, 404, 500 parse errors incl. the croniter
  message, 501 cron-module-absent). Job ids are 12 hex chars.
- `GET /api/jobs` hides disabled jobs by default — the client passes
  `include_disabled=true`, or off/needsAttention states would never render.
- `state` also takes `"completed"` (repeat-exhausted: `enabled=false`,
  `state="completed"`) and `"error"` (croniter-missing: enabled, `last_error` set, no
  `next_run_at` — deliberately "not silently disabled" upstream). Derivation order
  refined accordingly: completed → OFF (finished, not broken); the croniter shape is
  exactly needsAttention. This is a deliberate refinement of the dispatch's two-branch
  spec, from verified semantics.
- PATCH `repeat` must travel as the record's `{times, completed}` dict — upstream update
  is `{**job, **updates}` with no repeat normalization, and the scheduler reads
  `repeat.get("times")`; a bare int would corrupt the stored record. `completed` is
  preserved from the record being edited.
- No endpoint exposes the host timezone → daily/weekly/advanced inputs carry a
  whose-clock caveat in the sheet. The absolute one-shot sidesteps #51021 entirely by
  emitting the DEVICE's UTC offset (`fromisoformat` keeps explicit offsets as-is).
- Deliver options ride `GET /health/detailed` `platforms` keys (+ built-in
  origin/local); fetch failure degrades the picker to free text; a value outside the
  list is preserved as a marked "(custom)" row.
- `list_jobs` attaches `latest_execution` (executions SQLite row) — its
  `claimed|running` states are the client's only live RUNNING signal; surfaced as the
  status badge and in detail.

**Verification:** app target CLI build green; full suite on the pinned sim
(47F68496): Swift Testing `1007 tests in 88 suites passed` (baseline 931/84 + this
lane's 76/4), XCUITests 8/8. One flake note: `testDisconnectReturnsToStandaloneChat`
failed once on the first bundle run ("Enter Code Manually" still in hierarchy after
disconnect) and passed clean on rerun — the bundle-warm tap-timing class the test's own
comments document, in a flow this lane does not touch. Not chased here.

**Owed — device checklist (next session with the phone):**
- [ ] Drawer → SCHEDULED TASKS → list renders real OJAMD jobs (or the honest empty state)
- [ ] Create via each preset (interval / daily / weekly / once-relative / once-absolute)
      and confirm the server's `schedule_display` matches the preset's intent
- [ ] Advanced mode: submit a bad string → sheet stays open with the server's message
      verbatim; submit a valid cron → server display shown after save
- [ ] Run Now / Pause / Resume / Delete round-trips; list+detail stay in lockstep with
      no refetch flicker
- [ ] Edit an existing job: untouched fields absent from the PATCH (proxy: legacy
      deliver value survives an unrelated edit)
- [ ] needsAttention badge on a genuinely dead recurring job (repro: disable one
      host-side with `enabled: false` via PATCH)
- [ ] Timezone caveat renders next to daily/weekly time input; once-absolute fires at
      the device-local instant picked

Logged 2026-07-22.


> **🔬 DEVICE PASS 2026-08-15 — 6 of 7 checks resolved, and the `needsAttention`
> bar turns out to have NO KNOWN REPRO. Scored on the phone, paired to OJAMD.**
>
> | # | check | verdict |
> |---|---|---|
> | 1 | list renders real jobs | ✅ **PASS** — three real OJAMD jobs, correct next-runs, live AS OF stamp |
> | 2 | five presets → `schedule_display` | ✅ PASS *(Owen, prior run)* |
> | 3 | bad string → server message verbatim | ✅ **PASS** — `HOST REJECTED THIS TASK` is only the header; the server's own text renders beneath it (`TaskEditSheet.swift:126-140`), and Owen confirmed the second line |
> | 4 | Run Now / Pause / Resume / Delete | ✅ **PASS** — delete confirms first; list and detail stayed in lockstep |
> | 5 | edit does not clobber untouched fields | ✅ **PASS** — renamed a job, `deliver` still `local` |
> | 6 | needsAttention badge | ⚠️ **NO KNOWN REPRO — see below** |
> | 7 | timezone caveat + absolute firing | ◐ **HALF** — caveat renders and reads correctly; once-absolute firing NOT yet run |
>
> **⚠️ 6 IS NOT A PRODUCT FAILURE — THE PRE-REGISTERED REPRO CANNOT PRODUCE THE
> STATE IT TESTS, AND NEITHER CAN ITS SUCCESSOR.** `derivedStatus`
> (`CronJob.swift:129-133`) requires THREE conditions: `isRecurring` **and**
> `nextRunAtRaw == nil` **and** (`!isEnabled` or `hasLastError`).
>
> - **Repro (a), the one this checklist pre-registered — `enabled: false` via
>   PATCH — is FALSIFIED.** Executed against OJAMD job `890a5b798d16`: the host
>   kept computing `next_run_at: 2026-08-16T14:00:00`, so `nextRunAtRaw` was not
>   nil, the branch correctly did not fire, and the row rendered **OFF**. That is
>   the right answer — a job someone deliberately switched off is off, not broken,
>   and the derivation comments order `paused`/`completed` ahead of this branch for
>   exactly that reason. Job re-enabled the same minute; `last_status=ok`.
> - **Repro (b), an impossible recurring cron (`0 0 30 2 *`, Feb 30) — REJECTED BY
>   THE HOST**: `{"error": "failed to find next date"}`. **So the server refuses to
>   create a recurring job it cannot schedule**, which means it guarantees a
>   non-null `next_run_at` at creation and the needsAttention precondition cannot
>   be manufactured through `/api/jobs` at all.
>
> **DISPOSITION: verified-by-test, device-bar UNFALSIFIABLE.** Both branches are
> already covered by `CronJobStatusTests` (recurring+disabled+no-next-run,
> recurring+errored+no-next-run, plus the negatives), whose docstring claims EVERY
> needsAttention branch. The UI is defensive against a server state we have no way
> to produce on demand. **Do not spend another sitting hunting this on a device**
> — if it is ever wanted live, the route is a server-side state that nulls
> `next_run_at` on an existing job, not anything reachable from the app or the
> jobs API.
>
> **Two host-side observations, NOT ours (Hermes upstream):** a malformed
> `schedule` payload returns **HTTP 500 with a raw Python error leaked to the
> client** (`'dict' object has no attribute 'strip'`), and `schedule` is accepted
> as a **string** on write while being returned as a **dict** on read.
>
> **And one of mine, recorded because it is the same defect class this project
> keeps filing:** the first probe printed `would badge: True` when every parsed
> field was `None` — a NO-DATA condition rendered as a positive verdict, by the
> same hand that added an explicit no-data guard to
> `scripts/mac/score-due-omission.py` earlier the same day.
> **🛑 2026-08-31 — UNDRIVABLE THROUGH iPHONE MIRRORING; NOT a product
> verdict.** Build 3147, Mac profile. The path is all there — Sessions drawer →
> TASKS → NEW TASK → Schedule → **Once → "At a time"** (the absolute-clock
> option) exists and is reachable, and Name/Prompt accepted input. **The
> time-value control itself could not be driven:** clicks, typed digits, arrow
> keys, scrolling and click-drag all failed to move the underlying value, which
> stayed pinned to a stale default snapshot.
>
> Two save attempts were rejected by the host with:
> ```
> HOST REJECTED THIS TASK — Requested one-shot time
> 2026-08-31T21:20:24-05:00 is more than 120s in the past
> ```
> **That rejection is most likely CORRECT and is NOT filed as a defect.** The
> picker held `21:20:24` while the session ran ~33 minutes of real time, so by
> the save attempts that value genuinely was in the past. The honest reading is
> a stale picker overtaken by the clock, not a timezone bug — and saying so
> matters, because the tempting inference ("the host rejected a FUTURE time")
> would have manufactured a phantom in #249's family.
>
> **What IS established: a date/time picker joins Control Center on the list of
> things iPhone Mirroring cannot drive.** #162 needs a human with a touchscreen,
> or a seam. **Whether a HUMAN can set that field normally is UNTESTED** — if
> Owen also finds it unresponsive, that is a real defect and this note becomes
> its first evidence. Until then the card is human-only, not broken.

## 163. 🧩 156b Skills lane — **SHIPPED, on `main`** (`Talaria/Features/Skills/`, reachable at `ContentView.swift:250`); **device checklist still owed** — header corrected 2026-08-01

Dispatch `dispatch/FABLE-T27-156B-skills-browser.md` executed 2026-07-22 on the Mac Mini
(Xcode-beta4 toolchain). All six deliverables, one PR, zero new infrastructure (#161
held — one existing gateway endpoint, `GET /v1/skills` on `:8642`, same
`API_SERVER_KEY` auth plane as chat and Tasks).

**What shipped:** `Skill` tolerant model + `SkillsPresentation` grouping/search math
(D2 — Uncategorized last, case-insensitive ordering, client-side sort), `SkillsService`
over the one skill route (D1), `SkillsStore` with the Tasks-posture load/error state,
SkillsScreen with the five explicit content states — including the search-no-matches
state echoing the query, the one state Tasks lacks (D3) — expand-in-place rows instead
of a detail screen (no detail endpoint exists), drawer SKILLS row + `.skills` route
(D4), and `TaskSkillsPicker` closing the 156a debt at `TaskScheduleDraft` (D5): a
multi-select sheet fed from the same store, preserve-unknown-values ("(custom)" rows
stay selected; a hand-typed legacy value survives any unrelated edit), free-text
degrade when the fetch fails, and the comma-separated wire format unchanged. 44 tests
in 4 suites (D6).

**Scope holds from the dispatch (do not relitigate):** no enable/disable toggle (the
handler filters to enabled skills; no flag in the payload — read-only IS the honest
surface), no skill detail screen, and the composer autocomplete keeps its relay
`/v1/commands` catalog — the two planes can disagree and that is expected; no
reconciliation was built.

**Verification:** full suite on the pinned sim (47F68496): Swift Testing
`1051 tests in 92 suites passed` (baseline 1007/88 + this lane's 44/4). XCUITests 7/8
on the bundle run — the one failure is exactly the #162-documented
`testDisconnectReturnsToStandaloneChat` bundle-warm flake (untouched flow); passed
clean on a solo rerun. `aps-environment: development` verified after regen.

**Owed — device checklist (next session with the phone):**
- [ ] Drawer → SKILLS renders the real host list (~98 on the Mac host) grouped by
      category, Uncategorized last
- [ ] Search filters live across name/description/category; a garbage query shows the
      "No skills match" state echoing the query
- [ ] Expand a row with a long multi-line description — full text, newlines intact;
      collapse restores the 2-line preview
- [ ] Pull-to-refresh; then airplane-mode refresh keeps rows on screen with the
      REFRESH FAILED strip (never a replacement)
- [ ] Cron editor: SKILLS field shows the picker fed from the host list; a hand-typed
      value renders "(custom)" and survives an unrelated edit round-trip; with the
      gateway unreachable the field stays free text
- [ ] EDIT AS TEXT escape works and round-trips back through the picker

Logged 2026-07-22.

> **✅ DEVICE PASS 2026-08-15 — ALL SIX CHECKS PASS.** Phone paired to OJAMD.
> List renders the real host skills grouped by category with Uncategorized last;
> search filters across name, description and category (garbage returns nothing);
> long descriptions expand and collapse cleanly; **airplane-mode refresh keeps the
> last fetch on screen with a failure strip explaining the host took too long — the
> data is added to, never replaced**, which is the defect this bar exists for; the
> cron SKILLS picker and EDIT AS TEXT both round-trip.
>
> **⚠️ TWO PASSES ARE SOFTER THAN THE REST AND ARE RECORDED AS SUCH, not upgraded.**
> (i) The empty-state bar asks the screen to ECHO the query back, and the run
> recorded only "garbage returns nothing" — an empty list and an echoing empty state
> look identical from a glance. (ii) The picker bar's load-bearing clause is that a
> HAND-TYPED value renders `(custom)` and SURVIVES an unrelated edit round-trip;
> Owen's note was *"these are all familiar, must be a retest"*, which reads as
> recognition rather than exercise. Both are cheap to confirm on the next sitting
> and neither is disputed — they are simply not evidenced to the bar's own wording.

> **✅ 2026-08-31 — CHECK A MET ON DEVICE.** Build **3147**, Mac profile
> (gateway up), driven through iPhone Mirroring. The Skills list loaded (**135
> skills**), a garbage query `zzzqqqxyz` was typed into its search field, and
> the empty state read **verbatim**:
> ```
> No skills match "zzzqqqxyz"
> ```
> **The query is echoed back exactly** — which is the whole bar (an empty state
> that ECHOES rather than rendering a blank void). Check A is met.
>
> **Check B (the cron editor's hand-typed SKILLS value surviving a round-trip)
> is NOT run** and is deliberately left open — see the caveat below.
>
> **⚠️ TWO PRECONDITIONS THIS CARD NEVER STATED, both of which cost a run:**
> **(1) Skills is HOST-FED.** On a profile whose gateway is unreachable the
> screen renders "Skills Unreachable / unsupported URL" and there is no search
> field to type into at all. The card reads as a pure-UI check and is not one.
> **(2) It is not in Settings.** Skills lives on the four-up rail at the bottom
> of the SESSIONS DRAWER (`TASKS · SKILLS · INSIGHTS · ARCHIVE`,
> `SessionsDrawer.swift:888`), not under any settings screen — a run that
> searched Settings for it found `NO MATCHES` for *skills*, *cron* and *task*
> and concluded, wrongly, that the screen might not exist.
>
> **🔬 UNRESOLVED OBSERVATION, recorded rather than filed as a bug.** Typing
> `my-custom-skill` into the task editor's SKILLS field consistently rendered
> **`amy-custom-skill`** — a spurious leading `a` — and once appeared to
> re-corrupt with no input between two captures. It could not be separated
> from iPhone Mirroring's own input unreliability (batched `type` provably
> drops characters here; even per-key sends needed ~0.3 s spacing to land
> `zzzqqqxyz` intact). **The cheap discriminator: type into that field with a
> physical keyboard, off mirroring.** Until then this is an instrument artifact
> candidate, not a defect claim.

## 166. 🍎 App Store review-risk register — hermex's actual submission runbook mapped onto Talaria

> **⚖️ OWEN'S RULINGS 2026-08-09 (interactive decision pass) — the submission
> cluster, decided as a set:**
> - **Privacy policy lives at `docs/privacy.html` on the existing Pages site.**
>   Claude drafts from the app's real data flows; Owen reads and publishes
>   (the standing no-external-submissions gate covers the publish moment).
>   This was 166a's hard stop; it is now unblocked.
> - **iPad STAYS in v1.0.** The 2026-07-20 decision is re-confirmed; P-4 keeps
>   both screenshot sets (6.9" + 13") and #109 stays on the pre-launch path.
> - **Purpose strings: OPTION A — describe the use, no app name.** Satisfies
>   bar 166-D by construction; the display-name question stays open but no
>   longer blocks the strings.
> - **The launch-blocking string subset moves NOW**, its own small change;
>   #255's sweep picks up the remainder whenever it runs.
> - **IAP: CREATE the product early (unblocks #127's sandbox round-trip);
>   SUBMIT only at the flip** (early submission is the 2.3.1 risk).
> - **#8 FOLDS IN as step 166g** — all four of #8's clauses are falsified;
>   TestFlight is a runbook step, not an item. #8 archives at the next sweep.

> **✅ 2026-08-10 — THE PRIVACY POLICY IS DRAFTED, CONFIRMED, AND STAGED
> (interactive pending review).** All four OWEN items in
> `planning/privacy-policy-DRAFT-2026-08-10.html` were answered: **(1)** the
> data-practice claims are CONFIRMED by Owen (no iCloud/CloudKit sync; zero
> analytics/ad/crash SDKs; local-only notifications) and were verified
> against the tree the same day — `cloudKitDatabase: .none` is the only
> CloudKit reference, no APNs registration survives #238, and the sole SPM
> dependency is stasel/WebRTC (realtime voice engine, not analytics);
> **(2)** developer of record: **James Jones** (personal legal name, chosen
> over "Aethyrion"); **(3)** contact: `j.owen.jones@live.com`; **(4)** the
> effective date is a marked SET-AT-PUSH field. The publishable file is
> STAGED at `docs/privacy.html`, **deliberately uncommitted** — the
> COMMIT+PUSH is the publish moment and stays Owen's per the standing
> no-external-submissions gate. Two forward gates recorded in the file
> itself: the permissions table re-syncs against the final Info.plist when
> the 166-D strings lane lands, and the realtime-voice sentence ties to
> #320's indicator.
>
> **✅ PUBLISHED 2026-08-10 (Owen's explicit go, same evening): effective
> date 2026-08-10, live at
> `https://aethyrionai.github.io/Talaria-27/privacy.html`** (Pages serves
> `main` `/docs`; the URL 404'd before this push, so nothing was
> overwritten). A `Privacy` link was added to the site footer so the page is
> not an orphan. **166a's public privacy-policy-URL hard stop is
> SATISFIED.**
>
> **⚠️ AND A FALSE CLAIM IN THIS BLOCK IS CORRECTED IN THE SAME COMMIT.**
> This note originally ended *"the manifests half of 166a is unchanged"* —
> **false.** The manifests landed 2026-07-22 (`6d1515e`), ship in the built
> bundle, and were recorded RESOLVED in the archive that day. The claim was
> borrowed from this entry's own stale 166a paragraph without checking the
> tree — the exact failure mode CLAUDE.md's ATS line warns about, repeated
> inside the correction culture that exists to prevent it. Owen caught it by
> recognising the work sounded familiar. The 166a paragraph now carries its
> own correction block; **what actually remains of 166a is the App Privacy
> questionnaire answers only.**

Source: hermex's `TESTFLIGHT.md` (741-line maintainer runbook from a shipped App Store app) + their `docs/agents/feature-gap-index.md`, read from a fresh shallow clone 2026-07-22, every claim below verified against their tree or ours, not summarized from memory.

### Their #1 risk does NOT apply to us — verified
hermex's highest-flagged review risk is their share extension's dynamic `UIApplication`/`openURL:` auto-launch workaround (responder-chain hacks to open the containing app). **Talaria's share extension has zero dynamic-launch code** — recursive grep of `TalariaShare/` for `openURL`/`UIApplication.shared`/responder finds nothing. Our App-Group-staging flow is already the "review-safer alternative" their runbook describes. Do not add auto-launch later without reading their Step 6.

### What WILL hit us, in severity order

> **⚠️ CORRECTION 2026-08-10 — 166a's MANIFEST HALF IS DONE, AND THIS
> PARAGRAPH HAS BEEN STALE SINCE 2026-07-22.** The paragraph below says
> *"Talaria has **none** for any target"*; `PrivacyInfo.xcprivacy` landed for
> all three bundle targets that same day in commit `6d1515e` and **ships in
> the built product today** — verified by `find` inside the built `.app`:
> `<app>/PrivacyInfo.xcprivacy`, `PlugIns/TalariaWidgets.appex/…`,
> `PlugIns/TalariaShare.appex/…`, plus WebRTC's own. The outcome was recorded
> correctly at the time in `OPEN_ITEMS-ARCHIVE.md` (#166a — privacy
> manifests: RESOLVED), so this register's copy simply never caught up.
> **The "highest-probability rejection" framing no longer describes reality
> and must not be quoted as live risk.** What remains of 166a is the
> Owen-side half only: the App Privacy questionnaire answers and the public
> privacy-policy URL (published 2026-08-10, see the ruling block above).
> **Caught by Owen's instinct that the privacy work "sounded familiar" —
> and the same session had already repeated the stale claim once** (the
> 2026-08-10 policy note originally read "the manifests half of 166a is
> unchanged", corrected in the same commit as this block). Two independent
> readers took this paragraph at face value; that is what a stale register
> line costs.

**166a — Privacy manifests are missing entirely (highest-probability rejection).** hermex ships `PrivacyInfo.xcprivacy` for both app and share-extension targets (theirs: UserDefaults/CA92.1 required-reason, zero collected data types, tracking=false). Talaria has **none** for any target (app, TalariaWidgets, TalariaShare — verified by find). We indisputably touch required-reason APIs (the sensor outbox rewrites UserDefaults on every tick, #104), so uploads will draw ITMS-91053 rejections. Good news verified: the WebRTC xcframework ships its own per-slice manifests, so the SDK side is covered — only our targets need files. **Speccable, small: three manifest files + project.yml wiring.** HealthKit/location App-Privacy posture: data goes only to the user's own host, never to any developer-accessible endpoint — hermex's "zero collected data types" declaration is the same posture we can defend, but the App Privacy questionnaire answers and a public privacy-policy URL (their hard stop condition) are Owen-side work.

**166b — The global ATS exception may be unnecessary, and hermex is the evidence (testable).** They shipped with NO `NSAllowsArbitraryLoads`. Their only "exception" is `100.64.0.0/10` as an `NSExceptionDomains` KEY — a CIDR literal, which is not a valid domain entry and is almost certainly cosmetic. Yet their HTTP-to-Tailscale traffic works for App Store users, which implies ATS is lenient with bare IP-literal URLs in practice. **Test on a dev build: strip our global exception, hit `http://100.79.222.100:8642` and `:8000`.** If traffic flows, delete `NSAllowsArbitraryLoads` from project.yml — removing the single scariest line a reviewer greps for AND closing the SECURITY.md caveat. If it fails, keep + justify in review notes. Either way the answer becomes recorded fact instead of assumption.

**166c — A Tailscale-only host is structurally unreviewable.** Their stop conditions require a live reviewer-reachable server URL + password in App Store Connect, "server awake" through the review window. A reviewer cannot join a tailnet. **Our saving grace, and it's a big one: on-device mode means the reviewer gets a fully working app with zero setup** — hermex had no equivalent. But paired features (hosted chat, Tasks, Skills, Insights, sensors, voice) must be demonstrable, so launch requires a temporarily public HTTPS review host (`tailscale funnel`/`serve`, or a real domain) for the review window. This is a deployment task + review-notes task, not app code.

**166d — `ITSAppUsesNonExemptEncryption` unset.** Theirs: `false` in Info.plist. Ours: absent from project.yml (verified). Everything we use is exempt-standard (HTTPS, DTLS-SRTP via WebRTC). One-line project.yml addition; avoids the per-upload compliance interrogation.

**166e — Portal capability pre-flight.** Their Step 4 checklist, translated: bundle IDs for app + widgets + share extension registered; App Group enabled across all three; push (aps-environment), HealthKit, Siri/App Intents capabilities on the App ID; CarPlay deliberately NOT requested (parked); automatic signing can mint App Store profiles for all targets. Mechanical, Owner-side, but their runbook exists because archive failures here cost them a cycle.

**166f — Adopt their runbook skeleton.** Stop Conditions / Review Notes template / Known Risk Register / Definition of Ready is a genuinely good structure. Their review-notes template ports almost verbatim (self-hosted server framing, "no in-app account creation or purchase flow" — true for us with the gate inert, and the review build must keep it inert with no dead purchase UI reachable, 2.3.1). Fold into the existing launch-pass doc rather than a new file.

### Recommended sequencing
166a + 166d are one small speccable lane (manifests + one key). 166b is a 30-minute experiment that should happen BEFORE that lane so the ATS decision lands in the same project.yml commit. 166c/166e/166f are Owen-side prep. None block current development; all block submission.

Logged 2026-07-22.

> **🔄 STATUS REFRESH 2026-08-31 (Owen: "refresh 166"). This entry was last
> touched 2026-08-10 and its own sequencing note had gone FALSE — which matters
> because that note is what a future reader would route from.**
>
> | sub-item | state as of 2026-08-31 |
> |---|---|
> | **166a** privacy manifests missing | 🔴 **OPEN — and the entry calls it the highest-probability rejection.** No `PrivacyInfo.xcprivacy` for app or share-extension targets. **⟵ FALSE — see the 2026-09-01 block:** the manifests shipped 2026-07-22 (`6d1515ec`); what was true is that they were INCOMPLETE, closed 2026-09-01. |
> | **166b** the global ATS exception | ✅ **DONE — and it is the reason this refresh was needed.** `NSAllowsArbitraryLoads` was removed by PR #138 (`d3c962d`, 2026-07-22) and replaced with the CIDR-keyed `NSExceptionDomains` entry, adopted only after the four-arm experiment. Shipping in `project.yml` since. |
> | **166c** Tailscale-only host is unreviewable | 🔴 OPEN — Owen-side, and structural: a reviewer needs a reachable URL. |
> | **166d** `ITSAppUsesNonExemptEncryption` unset | 🔴 OPEN — one Info.plist key. **⟵ FALSE — see the 2026-09-01 block:** shipped 2026-07-22 (`d3c962dc`, `project.yml:398`); DONE, nothing to build. |
> | **166e** portal capability pre-flight | 🔴 OPEN — Owen-side. |
> | **166f** adopt the runbook skeleton | 🔴 OPEN — structural/organisational. |
>
> **🛑 THE SEQUENCING NOTE BELOW IS SUPERSEDED.** It reads *"166b is a
> 30-minute experiment that should happen BEFORE that lane so the ATS decision
> lands in the same project.yml commit."* **166b already happened, 2026-07-22,
> and its decision already landed in `project.yml`.** Anyone following that
> sentence today would go re-run a settled experiment. **Corrected sequencing:
> 166a + 166d are the one small speccable lane and nothing gates them.**
>
> **Two things this refresh adds that 08-10 could not know:**
> 1. **166b's answer has a live consequence worth carrying into submission
>    copy** — the exception is CIDR-keyed to `100.64.0.0/10`, so cleartext HTTP
>    to a MagicDNS name or a non-Tailscale VPN subnet (PiVPN, self-hosted
>    WireGuard) is ATS-blocked app-wide. That is a **supported-topology
>    statement**, not just a plist detail (#421's corollary; Owen ruled
>    2026-08-31 that no validator narrows it further).
> 2. **166c is sharper than when it was written.** The launch pivot made the
>    local brain the default and the host an optional upgrade tier, so a
>    reviewer can exercise the app fully with **no host at all** — which may
>    dissolve 166c rather than require a reviewer-reachable server. **Worth
>    testing before building anything for it**, and the standalone/unpaired
>    runbook group (§02) is where that evidence already accumulates.
>
> **Unchanged and still true: none of these block development; all of them
> block submission.**

> **🔴 2026-09-01 — THE 08-31 REFRESH TABLE ABOVE IS FALSIFIED ON TWO ROWS,
> and the build list inherited both.** Measured tonight, at the moment the
> "166a+166d lane" was about to be dispatched:
> - **166a's manifest half shipped 2026-07-22** — `6d1515ec` ("privacy: add
>   PrivacyInfo.xcprivacy for all three bundle targets"), all three files
>   present and wired as Resources in the generated project (three
>   `PBXBuildFile … in Resources` rows). The 2026-08-10 correction block
>   above already said this; the 08-31 refresh re-asserted the entry's
>   ORIGINAL "missing entirely — verified by find" paragraph without
>   re-running the find. A corrected claim was re-falsified by quoting the
>   entry's own oldest text — the newest-dated-block rule fails when the
>   newest block itself regressed; the artifact (the tree) is the tiebreak.
> - **166d shipped the same minute** — `d3c962dc` declares
>   `ITSAppUsesNonExemptEncryption: false` (`project.yml:398`), commit
>   subject names #166d. The refresh's "🔴 OPEN — one Info.plist key" and
>   the build list's "absent from project.yml (verified)" were both false.
>   **166d is DONE; nothing to build.**
>
> **The lane is NOT dissolved — it INVERTS: the manifests exist and are
> INCOMPLETE.** The 07-22 content declares only UserDefaults
> (CA92.1 + 1C8F.1); the app has since grown three UNDECLARED
> required-reason API uses (measured tonight by grep over non-test sources):
>
> | category | site | manifest(s) owed |
> |---|---|---|
> | FileTimestamp | `ShareInboxCore.swift:226,305` (`.contentModificationDateKey`) | TalariaShare AND app — the file compiles into BOTH targets |
> | SystemBootTime | `LiveVoiceSessionService.swift:1281,1346,1373` (`ProcessInfo.systemUptime`) | app |
> | DiskSpace | `DeviceReadTools.swift:60-65` (`volumeAvailableCapacity*`) | app |
>
> That is exactly the ITMS-91053 exposure 166a names — arrived by DRIFT
> (the app grew API use after the manifests were written), not by omission.
> **166a's remaining scope: completeness, plus the tripwire that stops the
> next drift.**
>
> **📋 2026-09-01 — 166a-COMPLETENESS LANE OPENED (overnight; Owen elected
> "166a+166d", re-scoped by the above). Bars pre-registered before code:**
> - **166a-G (manifests match measured use, per target):** each target's
>   manifest declares a required-reason category IFF that target's compiled
>   sources use an API in that category's family. The three gaps close with
>   the measured reasons — FileTimestamp **C617.1** (in-container/app-group
>   timestamps), SystemBootTime **35F9.1** (elapsed time between in-app
>   events), DiskSpace **85F4.1** (displayed to the user by the storage
>   read tool) — and nothing is declared "to be safe." [offline]
> - **166a-H (the drift tripwire, RED-first for real):** a structural test
>   derives per-target required-reason API use from the sources (curated
>   pattern list per category) and asserts each target's manifest covers
>   it. It must be RED on tonight's main — the three gaps above are the
>   watched RED — before any manifest edit, and a deliberate mutation
>   (remove one declared category) must re-redden it. [offline]
> - **166a-I (built-product check):** the built app bundle carries the
>   manifests at their expected paths and the built Info.plist carries
>   `ITSAppUsesNonExemptEncryption` = false — read from the BUILD PRODUCT,
>   not the source (the #218 lesson applied to plists). [Mac]
> - **166-GATE:** `lane-gate.sh` PASS (units + XCUITest + Release), count
>   moved. [Mac]

> **✅ 2026-09-01 — 166a-COMPLETENESS LANE LANDED. All four bars MET.**
> PR **#401**, squashed as **`562267f6`**. **166 STAYS OPEN** — 166c/166e/166f
> are Owen-side; 166a's remaining half is the App Privacy questionnaire.
>
> **166a-H (the drift tripwire) — MET, and the RED was the WATCHED one.**
> `TalariaTests/PrivacyManifestCompletenessTests.swift` re-derives per-target
> required-reason API use from the SOURCES — per-target source sets **parsed
> out of `project.yml`** (the same list XcodeGen compiles from), not restated
> — then asserts each target's manifest covers what its sources touch. On the
> untouched tree it named **exactly the three predicted categories**, as four
> (target, category) pairs, each with its call site:
> ```
> Talaria: UNDECLARED NSPrivacyAccessedAPICategoryDiskSpace
>     used by: Talaria/Services/Live/DeviceTools/DeviceReadTools.swift
> Talaria: UNDECLARED NSPrivacyAccessedAPICategoryFileTimestamp
>     used by: TalariaShare/ShareInboxCore.swift
> Talaria: UNDECLARED NSPrivacyAccessedAPICategorySystemBootTime
>     used by: Talaria/Services/Live/LiveVoiceSessionService.swift
> TalariaShare: UNDECLARED NSPrivacyAccessedAPICategoryFileTimestamp
>     used by: TalariaShare/ShareInboxCore.swift
> ```
> **TalariaWidgets produced no failure — "expected unchanged" was DECIDED by
> the instrument rather than assumed from the brief**, which is the whole
> point of writing the tripwire before the fix.
> **MUTATION (the arm that proves the instrument, not the fix):**
> SystemBootTime deleted from the app manifest ⇒ RED again naming that
> category and ONLY that category (`Test run with 1 test in 1 suite failed`,
> `used by: …/LiveVoiceSessionService.swift`); reverted ⇒ GREEN restored,
> 6 tests / 2 suites, diff byte-identical to pre-mutation.
>
> **166a-G (declare IFF used) — MET.** The three gaps closed with the measured
> reasons and nothing else was added: FileTimestamp **C617.1**
> (`ShareInboxCore.swift:226,305`, app-group container timestamps — owed by
> the app target AND TalariaShare because that file compiles into both),
> SystemBootTime **35F9.1** (`LiveVoiceSessionService.swift:1281,1346,1373`),
> DiskSpace **85F4.1** (`DeviceReadTools.swift:60-65`, displayed by the storage
> read tool). `plutil -lint` OK on all three files. The IFF's REVERSE arm is
> enforced too (`manifestsDeclareNothingUnused`).
>
> **⚠️ AND THAT REVERSE ARM SURFACED A FOURTH FINDING THE GAP TABLE DID NOT
> HAVE.** `TalariaShare`'s manifest has declared **UserDefaults** since
> 2026-07-22, but the extension is **purely file-based** — it stages into the
> app-group CONTAINER (`FileManager.containerURL`) and the string
> `UserDefaults` appears **nowhere** in `TalariaShare/` (nor does
> `@AppStorage`). It is an over-declaration inherited from the manifest's
> original authoring. **Left in place** — this lane's scope was closing gaps,
> and its instruction was to keep existing UserDefaults declarations — but
> recorded as a **named exemption in the test** rather than tolerated
> silently, so no NEW over-declaration can hide behind it. A strict reading
> of 166a-G would delete it; that is **a decision, not a build**, and it is
> now on the record instead of in nobody's head.
>
> **166a-I (built product, not source) — MET.** #218's lesson applied to
> plists: `Bundle.main` in an app-hosted unit test IS the built host app, so
> `builtAppBundleCarriesThePrivacyManifest` and
> `builtInfoPlistDeclaresExemptEncryption` read the shipping bundle.
> Both `.appex` bundles verified by `plutil` against the built Debug product:
> `<app>/PrivacyInfo.xcprivacy` (4 categories),
> `PlugIns/TalariaShare.appex/PrivacyInfo.xcprivacy` (UserDefaults +
> FileTimestamp/C617.1), `PlugIns/TalariaWidgets.appex/PrivacyInfo.xcprivacy`
> (UserDefaults only) — all three `NSPrivacyTracking false`, empty tracking
> domains, zero collected data types; built Info.plist
> `ITSAppUsesNonExemptEncryption` = `false`.
>
> **166-GATE — MET.** `GATE: PASS on 24A5423a` — Swift Testing **2789**,
> XCUITest **15/15**, Release build clean, `project.pbxproj` no uncommitted
> drift. Count MOVED (the 6 new tests are named individually in the RED and
> GREEN runs, which is stronger than a delta).
>
> **🎲 One gate run FAILED first, and the flake protocol is what settled it —
> plus it harvested the #219 tripwire's FIRST natural red.** The pre-rebase
> gate came back `GATE: FAIL (3)` on
> `TalariaUITests.testConnectedRelaunchSkipsTheConnectEntry`
> (`AppTemplateUITests.swift:540`), Swift Testing and Release green. A
> structural alibi was available (this diff is two plists and a test file) and
> was deliberately NOT used: identical bytes were re-run on a quiet box
> (load average had been 37) and passed — `GATE: PASS`, 15/15. **The
> `.xcresult` from the failing run carries the XFLAKE activities #219 armed
> for exactly this, and they say something new:**
> ```
> XFLAKE pre  hittable=false frame=(24.0, 509.0, 372.0, 56.0)
>             window=(0.0, 0.0, 420.0, 912.0) scroll=(0.0, 127.0, 420.0, 785.0)
> XFLAKE post wizardUp=true composerIn5s=false wizardUpAfter=true
> ```
> **The element was NOT HITTABLE at a perfectly valid on-screen frame** — so
> the tap never landed, and the wizard was still up afterwards. That is a
> hit-test/settling failure, not the 15 s `waitForComposer` budget expiring
> on a slow box, which is what the prior occurrences assumed. Artifact
> preserved for the #219 lane. Filed there as well.

> **⚖️ RULED 2026-09-01 night (Owen, AskUserQuestion): DELETE TalariaShare's UserDefaults declaration.** The extension is file-based and uses none; "declare IFF used" is the tripwire's own rule, so the named exemption comes out with it. Small lane opened the same night (bars: the tripwire's exemption is removed FIRST and watched RED against the still-present declaration, then the declaration is removed and the test goes GREEN; gate PASS). The app and widget manifests are untouched.

> **✅ 2026-09-02 — THE RULING IS EXECUTED. `TalariaShare` no longer declares
> UserDefaults, and the tripwire's exemption list is EMPTY.** PR **#413**,
> squashed as **`d2bbd8e3`**. **166 STAYS OPEN** — 166c/166e/166f are
> Owen-side and 166a's remaining half is the App Privacy questionnaire; this
> closes only the over-declaration the completeness lane recorded and
> deliberately left standing.
>
> **The bar WAS the order, and the order held.** The exemption came out of
> `PrivacyManifestCompletenessTests.swift` FIRST, with the declaration still
> in the manifest, and the suite went RED on exactly the sentence the reverse
> arm exists to print:
> ```
> ✘ Test manifestsDeclareNothingUnused() recorded an issue at
>   PrivacyManifestCompletenessTests.swift:377:9: Expectation failed: failures.isEmpty
> ↳ A manifest declares a required-reason category nothing uses. #166a-G rules out
>   declaring "to be safe" — either delete the declaration or record it in
>   knownUnusedDeclarations with a reason:
>
>   TalariaShare: declares NSPrivacyAccessedAPICategoryUserDefaults but no compiled source uses it
> ✘ Test run with 4 tests in 1 suite failed after 0.787 seconds with 1 issue.
> ```
> `xcodebuild` exit **65**. The suite's other three tests PASSED in the same
> run, so the red is attributable to the one arm rather than to a broken
> `project.yml` parse — which is what the suite's "a check that did not run
> says so" `#require`s are for.
>
> **THE PREMISE, MEASURED RATHER THAN INHERITED.** Before the edit,
> `grep -rn 'UserDefaults\|AppStorage' TalariaShare/` returned exactly ONE
> line: line 15 of the manifest — the declaration itself, matching its own
> string. After the edit the grep is **empty (exit 1)**. `TalariaShare/` is
> `ShareInboxCore.swift`, `ShareViewController.swift`, `Info.plist`,
> `TalariaShare.entitlements` and the manifest; the extension stages into the
> app-group CONTAINER and nothing in it reads defaults.
>
> **GREEN, then the MUTATION — which re-created the exact pre-fix bytes.**
> Declaration deleted ⇒ `✔ Test run with 4 tests in 1 suite passed`, exit 0,
> `plutil -lint` OK. Re-adding the `NSPrivacyAccessedAPICategoryUserDefaults`
> dict (CA92.1 + 1C8F.1) restored the file **byte-identical to HEAD**
> (`git diff --quiet` clean on that path) and reddened the same test with the
> same sentence — `✘ Test run with 4 tests in 1 suite failed after 0.409
> seconds with 1 issue`, exit 65. Removing it again ⇒ green, exit 0, diff
> byte-identical to pre-mutation. **Four runs, one file, verdict following the
> declaration each time.**
>
> **⚠️ THE TEST COUNT DID NOT MOVE, AND THAT IS THE CORRECT RESULT — recorded
> here so it cannot later read as a stale-bundle tell.** This lane adds no
> test; it deletes an exemption from one that already existed. The suite is 4
> tests before and after and the whole run is 2827 both sides. **What moved is
> the VERDICT**, fail ⇒ pass ⇒ fail ⇒ pass over the same 4 tests — and a stale
> `.xctest` cannot flip a verdict on unchanged inputs. The "confirm the count
> MOVED" heuristic guards a lane that ADDED tests; where nothing is added, the
> RED/GREEN transition is the proof the bundle rebuilt.
>
> **166-GATE — MET.** The MERGED tree's gate is the post-rebase one and it
> passed **FIRST RUN**: `GATE: PASS on 24A5423a` — Swift Testing **2834 in
> 244 suites**, XCUITest **15** (counted independently off the
> `Test Case '-[…]'` ledger: 15 started / 15 passed / 0 failed), Release build
> clean, `project.pbxproj` no uncommitted drift, and
> `PrivacyManifestCompletenessTests` green inside the full run.
> `xcodegen generate` produced **no project diff** — correct, since no file was
> added or removed. **The 2827 ⇒ 2834 delta is NOT this lane's**: main gained
> seven tests (the #334-N and #419-B work) between the pre-rebase gate and the
> rebase. This lane's own contribution to the count is zero, by design.
> **A PRE-REBASE gate run had failed first, and the flake protocol was
> followed rather than shortcut.** `GATE: FAIL (4)` on
> `TalariaUITests.testConnectedRelaunchSkipsTheConnectEntry`
> (`AppTemplateUITests.swift:540`), with Swift Testing 2827 green and Release
> green in the same run — the #219 flake again, one lane after that tripwire
> harvested its first natural red. The box was carrying **load average 10–18
> with three concurrent `xcodebuild`s** from other lanes; the winning runs came
> at load ~4. A structural alibi ("this diff is one plist entry and a comment")
> was available and was NOT used as the argument — identical bytes were re-run
> and passed, twice over (the re-run, then the independent post-rebase run).
> Note the classifier says "ASSERTION TEXT PRESENT — treat this as a REAL
> failure. Do NOT re-roll it," and it is right to say so by default: the
> re-roll here is licensed by #219's named-flake standing, and the passing runs
> are the evidence rather than the reasoning.
>
> **The app and widget manifests are BYTE-UNTOUCHED.** `git diff --name-only`
> is exactly two paths: `TalariaShare/PrivacyInfo.xcprivacy` and
> `TalariaTests/PrivacyManifestCompletenessTests.swift`.
>
> **What the share extension now declares** — `NSPrivacyTracking false`, empty
> `NSPrivacyTrackingDomains`, zero `NSPrivacyCollectedDataTypes`, and a single
> accessed-API entry: `NSPrivacyAccessedAPICategoryFileTimestamp` / **C617.1**,
> the app-group container timestamps `ShareInboxCore.swift` reads.
> **⟵ This SUPERSEDES the 166a-I parenthetical in the lane-landed block above**
> (`PlugIns/TalariaShare.appex/PrivacyInfo.xcprivacy` "(UserDefaults +
> FileTimestamp/C617.1)"): that was a true measurement of the product built
> that afternoon, and it is no longer the shape that ships.
>
> **The exemption MECHANISM survives, empty.** `knownUnusedDeclarations` is
> now `[]` rather than deleted, because the reverse arm's own failure message
> offers it as one of two remedies ("either delete the declaration or record
> it … with a reason"). An empty named set keeps that remedy honest: the next
> tolerated over-declaration has to be written down with a justification
> instead of quietly not-failing.

## 180. 🎨 UMBRELLA — the app hides its own degradation: one design default, and a register that is no longer four instances long

> ## 🎯 BARS — LANE 180-L, PRE-REGISTERED 2026-08-09 BEFORE ANY CODE
>
> **Written first, per the convention** (bars live in the OPEN_ITEMS entry, not
> only in a dispatch doc — CLAUDE.md, "Where the BARS live"). Lane 180-L is the
> residue of this umbrella that nobody else owns: **three pure display-derivation
> seams plus one convention line.** Derivation:
> `dispatch/OPUS-T27-180-honesty-umbrella.md` §6.1/§7.2.
>
> **EXCLUDED BY NAME, and this lane must not touch them:** #296 (its own
> dispatch), #280 (its own dispatch), #173 (a decision, §8.1), and the health
> permission card (needs a `PermissionStatus` decision and a number first).
>
> **DEVICE: NONE. Every bar below is unit-testable.** That is itself a finding —
> see the #139-residual correction further down this entry.
>
> **180-A — no session row prints the same string as its title and its
> subtitle.** For every `HermesSessionInfo` the drawer can receive,
> `ChatScreen.sessionSummary` returns `title != subtitle`.
> *Evidence:* rows in `TalariaTests/LocalSessionHistoryTests.swift`, beside
> `sessionSummaryMapsOriginAndUnresumableState`.
> *RED, two rows, two causes:* (i) **#177's shape** — `title` and `preview` the
> same non-empty string (what Hermes sends): the title branch takes `title`, the
> subtitle ladder takes `preview`, and the assertion fails on two identical
> strings. (ii) **#280's shape** — `title: nil`, `preview` non-empty: the title
> branch substitutes the preview and the subtitle repeats it. **Neither row can
> be satisfied by editing a string constant.**
>
> **180-B — a row with a genuinely distinct title keeps BOTH lines.** Distinct
> `title` + distinct `preview` → title is the title, subtitle is the preview; and
> the three ladder rungs #190 owns (`unresumableReason`, the message count,
> `"No messages"`) are unchanged.
> **GREEN TODAY BY CONSTRUCTION — this is a PIN, not a proof, and it is recorded
> as one.** Its job is to fail if L1 over-reaches and "fixes" 180-A by deleting
> the subtitle.
>
> **180-C — the overlay does not name an engine before one has been selected.**
> The extracted `sessionHeaderLabel` derivation, given the initial state (no
> snapshot applied, so no engine known), returns a label containing **neither**
> "VOICE LINK" nor "LOCAL VOICE".
> *Evidence:* rows in `TalariaTests/NativeVoicePipelineTests.swift`.
> *RED:* the derivation reads `talkStore.voiceEngine == .native`, `voiceEngine`
> defaults to `.realtime` (`TalkStore.swift:35`), and `.idle` falls to
> `VoiceOverlayScreen.swift:162` → **"VOICE LINK · CONNECTING"**. The assertion
> fails on the literal "VOICE LINK". **It cannot pass without the unknown state
> existing**, so re-wording cannot satisfy it.
> *Second RED, the one that proves the mechanism:* a `TalkSessionSnapshot`
> constructed with no `engine:` argument must not report `.realtime`. Today
> `VoiceState.swift:180`'s default makes it `.realtime` — the optimistic-default
> form, caught directly.
>
> **180-D — a session that HAS selected an engine still names it.** A snapshot
> carrying `.native` → "LOCAL VOICE"; carrying `.realtime` → "VOICE SESSION" /
> "VOICE LINK" per `VoiceOverlayScreen.swift:158-166`; and the
> `LOCAL VOICE · ON-DEVICE PIPELINE` badge still appears on native.
> **GREEN TODAY BY CONSTRUCTION — a PIN, stated as one.** #18's rule is that
> local voice is never silently substituted for the Realtime experience; an
> unknown state must not erase the distinction it exists to draw.
>
> **180-E — the number in the size refusal explains the refusal.** The stated
> limit and the sizes the extension shows answer to the **same arithmetic as the
> guard** (`ShareInboxCore.swift`'s `maxEnvelopeBytes`):
> (i) `byteLabel(maxEnvelopeBytes)` states the cap without rounding it **UP** —
> today it renders 20,971,520 as "21 MB", a limit **28,480 bytes larger than the
> one enforced**;
> (ii) the largest byte count the guard ACCEPTS renders `≤` the stated limit;
> (iii) a refused byte count the user's own file browser shows as larger than the
> limit — the worked case is **20,999,999 bytes** — renders **strictly greater**
> than the stated limit.
> *RED:* today the limit renders "21 MB" and the 20,999,999-byte file the guard
> REFUSES also renders "21 MB", so the refusal reads *"21 MB is too large —
> limit 21 MB."* (iii) fails on two equal strings and (i) fails on the
> rounding. **The defect is arithmetic, so no copy change can satisfy it.**
> *Evidence:* `TalariaTests/ShareInboxCoreTests.swift`. The refusal's arithmetic
> moves next to the guard it explains, so it is reachable from the app target's
> tests at all — the share extension's own sources are not.
> **Residual, stated rather than hidden:** any rounded label keeps a boundary
> band (cap+1 … cap+~499,999) that still renders as the limit. This bar removes
> the **systematic** overstatement, not rounding itself. Do not read it as
> byte-exact honesty.
>
> **180-F — the convention is written down and names the four forms.**
> `HostFedListPresentation.swift`'s doc comment carries the review rule as
> **rule 5**, names the monotonic-latch / collapsing-`else` /
> optimistic-default / substitution-fallback forms, states the
> **narrow-never-substitute** corollary, and cites
> `LocalIntelligenceService.swift:452-458` as the in-repo precedent.
> *Evidence:* the file. **Not paperwork:** this umbrella's own recorded lesson is
> that the convention is the deliverable, and the codebase has the counter-example
> — `fallbackCard` solved "never print one line twice" on 2026-07-11, in one
> file's doc comment, and the server-fed drawer row reproduced the same render
> for a month because nobody generalized it.
>
> **Two decisions inside this lane are OWEN'S and are flagged, not guessed:**
> the share-refusal direction (base-10 cap vs base-2 label — the lane takes the
> base-10 cap, §8.4's option (a), reversible in one constant) and the HUD copy
> for the unknown voice state (**"VOICE · CONNECTING"** — it must not read as a
> third engine; approval owed before the PR is opened).
>
> **NO BARS are proposed for #173 or the health card** — a bar written before
> Owen picks an approach pre-empts the decision. **No umbrella-wide "no surface
> may claim…" bar** — unfalsifiable as written, and this entry's own instance
> list is the standing evidence that a stated principle without a code seam holds
> nothing.

> **⚠️ CORRECTION 2026-08-09 (lane 180-L, close-out rule) — the "four instances"
> in this entry's title and the list at the bottom are the AS-FILED count from
> 2026-07-23, not the current one.** Since filing, **#296** was filed into this
> family by name, **#139's residual** was routed here by the 2026-08-07 tidy pass
> and never numbered, and the 2026-08-09 sweep identified **two more**: the
> share-sheet size label (a note inside #123, corrected there) and the health
> permission card (inside *archived* #181 — still unnumbered, §8.3/§8.6 of the
> dispatch, and explicitly NOT lane 180-L's). The register that replaces the
> four-item list is `dispatch/OPUS-T27-180-honesty-umbrella.md` §2, which states
> each member's mechanism, its home, and whether it is live.

> **➕ INSTANCE ADDED 2026-08-09 — inherited from #241, which closed as
> RECLASSIFIED rather than fixed (Owen's ruling).**
>
> **A host-fed prose failure is indistinguishable from a real answer.** The
> gateway's `_handle_session_chat` returns an unconditional HTTP 200 with the
> agent's text — and that is *defensible upstream*, because the gateway runs an
> agent rather than proxying a model call: the turn really did complete. But the
> consequence lands on us. When the agent could not reach any model and says so
> in prose, **Talaria renders that with exactly the confidence of a real
> reply** — no failure strip, no degraded marker, nothing.
>
> **This is the umbrella's rule with the sign unchanged:** a seam rendering state
> the app does not own, modelled as two-valued (answer / no-answer) when the
> truth is three (answer / prose-failure / no-answer), with UNKNOWN landing on
> the affirmative side. Sibling of **#132**, which is the same defect for
> attachments the host cannot see — and #132 already shows the local plane
> disclosing blindness in-band while the remote plane does not.
>
> **Answer this BEFORE writing bars:** is there a machine-readable
> discriminator? The reply carries a `runtime` block (`provider` / `model` /
> `route_source` / `model_lock`). **If it is null or degraded when no model was
> reached, this is a small lane. If the only signal is the prose itself, it is a
> much harder one** — and it should be scoped that way from the start rather
> than discovered mid-flight. The register's existing entries were all
> structural; this is the first that may have no structural tell at all.
>
> Full derivation, the sentinel mechanism, and the dissolved park: **#241**.


> **INSTANCE 4 CLOSED 2026-08-02 — Owen rejudged the disconnection-indicator question
> mid-outage on a #237–#242 build (device pass §F5):** *"Now that I see the attempt to
> send, yes, I think that's enough."* The reactive convention (failure strips, "as of"
> stamps, server-card badge, and the send path's working→timeout→retry presentation)
> is the accepted answer; no proactive app-wide disconnected signal. PR #237's walk
> surfaces plus the #145 fixes are what made this judgeable.

> **Update 2026-08-02 — Phase 4 lane opened (`claude/t27-180-honest-degradation`). The entry
> had DRIFTED: instance 3 was substantially fixed by the #156b/#160 lanes without this entry
> being annotated.** All three list screens carry `refreshFailedStrip` OUTSIDE the `hasLoaded`
> gate when rows exist, and all three stores stamp `lastRefreshedAt` rendered "as of HH:mm" —
> so "lastErrorMessage is set on every later failure and never displayed" is no longer true.
> The cited gates (`SkillsScreen:71`, `TasksScreen:80`, `InsightsScreen:84`) survived only in
> the **empty-list branch**, where the one residual defect lived: a failure after a successful
> EMPTY load rendered as "the host has no X" instead of "the host did not answer."
>
> **Mechanism work shipped this lane — the shared answer, not four patches:**
> 1. **`Talaria/Core/HostFedListPresentation.swift` — THE CONVENTION, written down.** Four
>    rules on the type's doc comment (rows survive failure; failure always visible; data
>    stamped; stores profile-scoped). Its `emptyBranchState` decision replaced the three
>    hand-rolled — identically wrong — gates; all three screens switched onto it.
> 2. **Instance 2 generalized and fixed: the host-fed stores never reset on profile switch.**
>    `SkillsStore`/`CronJobsStore`/`InsightsStore` resolve their base URL per-fetch, but their
>    cached rows, `hasLoaded`, and `lastRefreshedAt` survived `handleActiveProfileChanged` —
>    the reset block there re-homed inbox/host/command-catalog and every gateway surface
>    added after Lane M missed it, which is this umbrella's thesis in one hunk. Now: each
>    store gains `reset()` plus a `loadGeneration` guard so a fetch already in flight against
>    the OLD host is discarded rather than landing in the reset store; all three wired in
>    `handleActiveProfileChanged`. The cron editor's skills picker inherits honesty through
>    `hasLoaded` (its #168b free-text degrade + retry already handle the reset state).
> 3. **Tests, REDs witnessed per the pattern-1 lesson:** the wiring test failed 6/6
>    assertions before the container calls were added (the defect was the WIRING, so that is
>    what the test measures); the in-flight-discard test failed 3/3 with the generation guard
>    deliberately disabled; and TWO presentation rows failed against the original gate
>    semantics before the fix was applied — the failure-after-empty-load case and the
>    refresh-in-flight-after-failure case, both the same suppressed-error class. The five
>    unchanged rows passed under BOTH semantics, pinning that the screen swap alters exactly
>    the two defective cells and nothing else.
>
> **Known accepted edge:** a profile switch while a list screen is simultaneously visible
> (iPad split-view) leaves the reset store empty until pull-to-refresh — `.task` fires on
> appear, and switches happen in Settings, so the screen re-fetches on navigation in every
> ordinary flow.
>
> ~~**Still open under the umbrella — decisions, not mechanisms, all queued for Owen:**
> #173's detection approach (capability surfacing vs never-claim-unverifiable), instance 4's
> app-wide disconnection indicator (chat has one; lists now have strips + stamps — is a
> global signal still wanted?), #197's automatic retry, #187's `min_messages` param.~~
>
> **⚠️ CORRECTED 2026-08-09 (lane 180-L, close-out rule) — that list was stale in
> THREE of its four entries, and in one place the entry contradicted itself.**
> - **Instance 4 is SETTLED**, by Owen's own rejudgement recorded higher in this
>   same entry (*"Now that I see the attempt to send, yes, I think that's
>   enough."*). It should never have stayed in a still-open list.
> - **#197 is CLOSED** (2026-08-04, `OPEN_ITEMS-ARCHIVE.md`). Its automatic-retry
>   question went with it.
> - **#187 is not an umbrella member at all** — the app asks for a filter, does
>   not get it, and compensates *visibly* (it filters client-side and routes the
>   header stat and the ⌘1…⌘9 ordinals through the filtered list), so no surface
>   claims a count the shelf does not show. Owen decided it 2026-08-02
>   (*"Keep, annotated"*) and **it has since CLOSED entirely** (2026-08-09). It was
>   a host-contract item, not an honesty item.
>
> **The list reduces to ONE: #173's detection approach** (§8.1 recommends the
> never-claim floor and demoting the capability half to a watch). Everything else
> live under this umbrella now has its own home: #296 and #280 have dispatches,
> the drawer row / voice header / share label are lane 180-L above, and the health
> permission card needs a number before it can be worked.
>
> **UPDATE 2026-08-09 — #296 is a NAMED INSTANCE of this umbrella and it is now
> FIXED.** It belongs on the register above, not merely in the "has a dispatch"
> footnote: it is this umbrella's thesis compressed into one glyph. A tool call
> the USER killed rendered with the same accent ✓ as one that succeeded, because
> the rail was two-valued and everything not-running drew "done" — and on a turn
> stopped before any prose that checkmark was the *entire message*. Same default
> as #173 and the three refresh-failure sites: **the app had the information, and
> the surface asserted the successful reading of it.** The fix gives the call a
> third state (interrupted) and puts the mark in the warning slot rather than the
> danger slot, because the usual cause is something the user asked for. One
> honest-degradation residual is knowingly accepted rather than hidden — a
> server-transcript reload restores the ✓ — and it is written into #296 as a
> decision, not left to be discovered.

**Raised 2026-07-23 after four independent findings in a single session converged on one shape.**
Each was filed or observed separately; together they look like a default rather than a run of
unrelated bugs.

1. **#173 — confident replies over dropped attachments.** The model never received the images;
   the app presented three fluent answers with no signal that anything was missing.
2. **Stale skills offered as live.** With both hosts disconnected (standalone), the cron editor's
   SKILLS picker still lists skills fetched from a host the app is no longer talking to. Cause:
   `SkillsStore.hasLoaded` latches true on first success and is never reset, and
   `TaskEditSheet.swift:187` gates the picker on it. Correct for the browser (#163 Check 4
   verified keep-rows-on-failure); wrong for a picker whose value is written into a job that runs
   somewhere else.
3. **Refresh failures are invisible after the first success.** All three list screens gate the
   error identically — `else if let message = store.lastErrorMessage, !store.hasLoaded`
   (`SkillsScreen:71`, `TasksScreen:80`, `InsightsScreen:84`). Since `hasLoaded` never returns to
   false, `lastErrorMessage` is set on every later failure and never displayed. `SkillsStore`,
   `CronJobsStore` and `InsightsStore` all carry the identical latch.
4. **No disconnection indicator at all.** Cut off from both hosts, Owen reported "none show i'm
   disconnected from everything." Nothing on the surfaces he was using said so.

**Adjacent, already filed:** #145 (behaviour under a degraded or absent host) and #139 (silent
realtime->local fallback presenting a label lie).

> **Cross-reference update 2026-08-07 (tracker tidy pass) — both adjacents
> named above are now CLOSED and live in `OPEN_ITEMS-ARCHIVE.md`; one of
> them left a residual that belongs to THIS umbrella.** #145 closed
> 2026-08-06; **#139 closed 2026-08-07** (139-F MET on device, both brains,
> full-minute waits after dismissal — *"Mic goes off after about 1s"*, no
> audio, no Live Activity, no late mic). So the specific label lie those
> pointers reach for is fixed, and a future lane should not re-derive it.
>
> **The residual #139 explicitly did NOT settle is umbrella-shaped:** the
> reachable states where realtime is never attempted (`canStartSession`
> false + the overlay skipping readiness) would still produce a label lie —
> the app naming an engine it is not running. ~~#139 flagged it unasserted
> because settling it needs a tethered run that quotes the
> `voice session starting on engine …` line (`VoiceEngineRouter`), and
> Owen's passing run was inferred-not-quoted from an office.~~ It is recorded
> here so it does not travel into the archive unattached: **it is the same
> "the app hides its own degradation" default this umbrella exists for, and
> it costs nothing extra on the next tethered voice sitting.**
>
> > **⚠️ CORRECTED 2026-08-09 — "it needs a tethered run" was FALSE, and
> > that assumption is why this sat unsettled for two days. ✅ SETTLED by
> > lane 180-L, bar 180-C, with a unit test and NO device.**
> >
> > The mechanism is not a runtime routing question at all. It is a **struct
> > default**: `TalkSessionSnapshot.engine` defaulted to `.realtime`
> > (`VoiceState.swift`), `TalkStore.voiceEngine` defaulted to `.realtime`
> > and `reset()` returned it there, and
> > `NativeVoicePipelineService.swift:71` is the ONLY producer that has ever
> > stamped `engine:` — so the realtime path rode the default and
> > `VoiceOverlayScreen.sessionHeaderLabel` rendered "VOICE LINK ·
> > CONNECTING" for `.idle/.checking/.ready/.connecting`, i.e. in every
> > state where nothing had chosen an engine.
> >
> > **The RED was watched, three levels deep, on the unmodified tree:**
> > `Expectation failed: !label.contains("VOICE LINK")`,
> > `Expectation failed: snapshot.engine != .realtime`, and
> > `Expectation failed: store.voiceEngine != .realtime`. No log line was
> > quoted and none was needed.
> >
> > **The fix:** the snapshot's engine is now `VoiceEngine?` with nil meaning
> > *no engine selected*; `VoiceEngineRouter.forward(_:engine:)` stamps the
> > engine that actually produced a snapshot (a fact it already had and was
> > failing to write) while the router's `snapshot` accessor deliberately
> > does NOT stamp `activeEngine`, because before anything runs that is only
> > the init guess; and the header derivation was extracted as a
> > `nonisolated static func` with three branches, the unknown one reading
> > **"VOICE · CONNECTING"** — neutral, and deliberately not a third engine
> > name (#18). ~~**That copy is Owen's to approve.**~~
> > **⟵ SUPERSEDED 2026-09-01 (bar 180-C-C). The approval never came, and the
> > 2026-08-25 ruling made it unnecessary rather than overdue: the convention
> > IS the standard now, and its rule 1 decides this string without a separate
> > sitting.** The word was wrong on its own terms — `CONNECTING` was printed
> > for `.idle`, `.checking` and `.ready` as well as `.connecting`, i.e. in
> > three states where nothing is connecting. The unknown-engine branch now
> > prints the connection state's own measured name
> > (`TalkConnectionState.displayLabel`), so `VOICE · IDLE` / `VOICE ·
> > CHECKING` / `VOICE · READY` / `VOICE · CONNECTING`. No new word entered
> > the vocabulary, and a SELECTED engine's wording is byte-unchanged (#18's
> > contrast is pinned in the same suite).
> >
> > **The finding worth keeping: a bar that assumed a device was needed cost
> > more than the fix did.** #139 filed this as needing a quoted log line; it
> > needed a unit test. Check the mechanism before pricing the verification.

**Why this wants one lane rather than six patches.** Each individual fix is small and each
existing behaviour is locally reasonable — keep-rows-on-failure IS right for a browser, and a
latch that only rises IS the simple implementation. What is missing is a shared answer to: *what
does a surface show when the thing behind it is unavailable, and how does the user find out?*
Patching these one at a time will reproduce the pattern in the next surface built.

**Suggested scope for a design pass — not yet decided:**
- one connection-state signal the app surfaces consistently
- a convention for stale-vs-live data in any list fed from a host
- per surface, decide whether stale data is shown, shown-and-marked, or withheld
- make `lastErrorMessage` reachable after first load (the latch is fine; the gate is not)

Logged 2026-07-23.

> **⚖️ RULED 2026-08-25 night (Owen, AskUserQuestion): ADOPT CONNECT HOST
> AS THE STANDARD — "if 180 is still relevant," a condition VERIFIED
> before filing** (live members at HEAD: the #241-inherited prose-failure
> instance, the health-permission card, the `lastErrorMessage` gate,
> #139's residual copy, #296). **The ruling:** the Connect Host design's
> state vocabulary (Owen's export, `design/connect-host/` — measured
> status, SAVED ≠ REACHABLE, named failures per check, honest empty
> states, no claim the code can't verify) IS the umbrella's long-sought
> "one design default." #309 Lane B's close-out writes it up as the
> standing convention; remaining members MIGRATE as lanes touch their
> surfaces — each migration a named step in this register, never a silent
> drift. **Migration #1 is already in flight tonight:** Lane C's 309-C6
> re-cuts the inbox error surface to the convention. The umbrella stays
> OPEN as the register until the members drain; what closed is the
> DESIGN question it was filed to force.

> **📜 THE CONVENTION, WRITTEN UP — 2026-08-25 night (#309 Lane B's close-out,
> discharging Owen's ruling above). It lives in ONE place in the code:
> `Talaria/Features/Settings/ConnectHostCopy.swift`'s header**, next to the
> strings it governs, because a convention filed only in a tracker is one the
> next lane has to be told about.
>
> **Six rules. Every one of them is a thing the app used to do and stopped.**
>
> 1. **MEASURED, OR NAMED AS UNMEASURED.** Every status is something the app
>    watched happen (`REACHABLE · 18MS`, `LAST ANSWERED 7:32 AM`) or is
>    labelled `NOT CHECKED`. There is no third option. *Why it is a rule:*
>    #350 — a surface that renders "unknown" as good news trains the reader to
>    ignore it, and one that renders it as bad news sends them to fix nothing.
> 2. **SAVED ≠ REACHABLE.** Holding credentials and being answerable are two
>    facts with two labels; a host that stops answering is `NOT ANSWERING`,
>    still saved, and every action's copy stays truthful offline. *Why:* the
>    #412 family — a capability gate reporting through a failure surface.
> 3. **EMPTY IS NOT AN ERROR.** "No host" names the current answer
>    (`RUNNING LOCALLY · ON-DEVICE BRAIN`) instead of rendering a failure for a
>    state the user chose. *Why:* #31/#384 — the hostless install is the
>    DEFAULT user, and the app kept describing them as broken.
> 4. **FAILURES ARE NAMED PER CHECK.** A ladder of real discriminations, so a
>    card can point at the rung that broke — never a bare "failed", and never
>    an HTTP code quoted at a human.
> 5. **THE GUILTY FIELD, AND ONLY IT.** A failure re-offers one input and
>    leaves the others alone, carrying the measurement that exonerates them.
> 6. **NO CLAIM THE CODE CANNOT VERIFY.** Storage claims, not encryption
>    claims; tier claims that survive the tier's own escape hatches. *Why:*
>    #385/#390's tier honesty, and the `END-TO-END ENCRYPTED` footnote this
>    lane deleted.
>
> **Migrations so far, as named steps in this register:**
> **#1** — Lane C's 309-C6, the inbox error surface (rule 2).
> **#2** — Lane B's own sweep: the DIRECT/RELAY link qualifiers on three cards
> (rule 6 — the branch printing "RELAY" had become unreachable, and an
> unreachable branch that can still be read as a claim is exactly what rule 6
> forbids), the Talk footer's `RELAY-BOOTSTRAPPED`, the chat banner's two
> strings, and the Developer screen's relay-origin endpoint row (rule 1: it
> now prints the ACTIVE PROFILE's gateway host, or "—").
> ~~**Still outstanding**, unchanged by this lane: the #241-inherited
> prose-failure instance, the health-permission card, the `lastErrorMessage`
> gate, and #139's residual copy.~~
> **⟵ THREE OF THE FOUR ARE MIGRATED 2026-09-01 (the 180-CONVENTION lane, RESULT
> block below).** What remains of that list is **the health-permission card**,
> which is HELD on Owen's `PermissionStatus` ruling and was deliberately not
> touched — and **the pure-prose half of the #241 instance**, which has no
> structural tell and is stated as still open rather than folded into the
> migration.

> **📋 2026-09-01 — 180-CONVENTION LANE OPENED (Owen's election, subagent + merge-on-green authority).** The 08-25 close-out left four members outstanding; three are buildable now and one is HELD. Verified at HEAD: `SkillsScreen.swift:76,103`, `TasksScreen.swift:85,109`, `InsightsScreen.swift:89,118` still read raw `store.lastErrorMessage`, and `ConnectHostCopy` is referenced only by Connect Host files. Bars pre-registered before code:
> - **180-C-A (the three host-fed screens join the convention):** Skills/Tasks/Insights render host failures through the Connect Host honest-degradation vocabulary (the same closed set or its shared successor — the lane reads the 08-25 ruling for the convention's definition), never a raw `lastErrorMessage` string. Structural pin: no direct render of `lastErrorMessage` on those screens outside the mapper. RED-first; a mutation that bypasses the mapper re-reddens it. [offline]
> - **180-C-B (the #241-inherited prose-failure instance carries the degraded marker):** per this entry's own description of that instance; the lane names the site in its result. [offline]
> - **180-C-C (#139's residual copy corrected):** per this entry's own description. [offline]
> - **180-C-D (HELD, explicitly out of scope):** the health-permission card waits on Owen's `PermissionStatus` ruling — untouched by this lane, and the result says so. [—]
> - **180-C-GATE:** `lane-gate.sh` PASS, count moved. Every string added is closed-vocabulary and pinned. [Mac]

> **📋 RESULT 2026-09-01 — 180-CONVENTION LANE. THREE MEMBERS MIGRATED, ONE
> HELD. PR #406, squash `d8c8b7f2`. Gate PASS post-rebase, FIRST RUN: 2827
> Swift Testing in 243 suites / 15 XCUITest / Release clean.**
>
> **180-C-A — MET.** The three host-fed screens no longer render a raw
> `store.lastErrorMessage`. One new seam,
> `Talaria/Core/HostFailurePresentation.swift`, answers a single question —
> *given a failure the app observed, which rung of the Connect Host ladder is
> it?* — and returns that rung's name **from `ConnectHostCopy` itself**, so
> there is exactly one spelling of each state in the tree. The vocabulary was
> NOT forked, and that is a test rather than a comment
> (`everyFailureNameComesFromTheConnectHostVocabulary` reads both files and
> fails if they diverge).
>   - **The classification was already sitting in the code, unused.** All three
>     services (`SkillsService`, `InsightsService`, `CronJobService`) declare
>     the same five typed cases and the stores collapsed every one of them to
>     `error.errorDescription` on the way to the screen. `notConfigured →
>     RUNNING LOCALLY` · `unreachable`/`timeout` → `NO ANSWER` ·
>     `unauthorized → KEY TURNED DOWN` · `invalidResponse → NOT HERMES`, plus
>     `.notPlaced` for anything this build cannot place (cron's `notFound` /
>     `serverRejected`, foreign errors) — **the DEFAULT branch, per rule 5,
>     never the `else`**.
>   - **Rule 3 landed as behaviour, not copy.** A hostless install used to read
>     "Skills Unreachable" with a Retry button; it now reads `RUNNING LOCALLY ·
>     ON-DEVICE BRAIN · NOTHING TO CONNECT TO`, with no Retry, because there is
>     nothing to retry against and a button that cannot work is a claim too.
>   - **RED, on the untouched tree, naming all six sites the brief predicted:**
>     `Expectation failed: offenders.isEmpty` →
>     `SkillsScreen.swift:76`, `:103` · `TasksScreen.swift:85`, `:109` ·
>     `InsightsScreen.swift:89`, `:118`; and its companion
>     `Expectation failed: text.contains("HostFailurePresentation")` on all
>     three (a check on the mapper's PRESENCE, so deleting the error surface
>     cannot satisfy the first pin — the gate's founding sin in miniature).
>   - **MUTATION:** re-introducing one raw render on `TasksScreen` alone
>     re-reddens the structural pin and nothing else; restored.
>
> **180-C-B — MET on the structural half, and the other half is NAMED rather
> than quietly claimed.** Site: **`Talaria/Services/Live/SessionsHermesClient+RunsTransport.swift`**
> — `runsFinalMessage` and its two callers (the `run.completed` frame at the
> stream seam, and the recovery poll's `completed` arm). The host's own `error`
> field rides both terminal payloads and the app already parsed it
> (`hostErrorDetail`, the union-safe reader #296-C1 wrote when the host was
> caught sending a JSON boolean) — but ONLY the `failed` arm read it. A run
> the host flagged and answered in prose anyway rendered `.delivered`, with
> exactly the confidence of a clean reply. `decodeTerminalHostError` +
> `Message.hostReportedFailure` + `MessageBubble.hostFlaggedStrip` close that:
> the marker reports **one observation** (the host raised a flag on this turn)
> and the host's own words beneath it, and never a cause — the flag can be a
> bare boolean, and a manufactured reason would be worse than the missing
> marker it replaces.
>   - **Answered #241's own pre-registered question, and the answer corrects
>     that entry** (dated block filed there): the `runtime` block it hoped for
>     does not exist on the runs plane at all (#382), so the discriminator is
>     the terminal `error` field instead.
>   - **KNOWINGLY ACCEPTED, stated rather than left to be found:** (i) a prose
>     failure the host never flagged is still indistinguishable from an answer
>     — #241's "materially harder" branch, still live in this register; (ii)
>     the SYNC runs path (`syncTurnViaRuns` — Siri, widgets) returns a String
>     and has no marker channel, so a flagged completion reaches those callers
>     unmarked. Neither is fixed and neither is hidden.
>
> **180-C-C — MET.** #139's residual copy was an UNAPPROVED string
> (`VOICE · CONNECTING`, "Owen's to approve", never approved) that was also
> wrong on its own terms: the unknown-engine branch borrowed the realtime
> STATUS word, so it printed CONNECTING for `.idle`, `.checking` and `.ready`
> as well as `.connecting`. The 2026-08-25 ruling settles it without a
> sitting — rule 1, *measured or named as unmeasured* — and the branch now
> prints the connection state's own measured name. `VOICE · IDLE` /
> `VOICE · CHECKING` / `VOICE · READY` / `VOICE · CONNECTING` / `VOICE ·
> 01:05`. **No new word entered the vocabulary** (it reuses
> `TalkConnectionState.displayLabel`), and a SELECTED engine's wording is
> byte-unchanged — pinned in the same suite, because a correction that erased
> #18's contrast would be the umbrella's own rule with the sign flipped.
>
> **180-C-D — HELD, and untouched.** The health-permission card needs Owen's
> `PermissionStatus` ruling. Nothing in this lane reads, renders or renames it;
> writing a bar for it before the ruling would pre-empt the decision, which is
> what the 180-L bars said in 2026-08-09 and is still true.
>
> **180-C-GATE — MET, and the runs that did not pass are reported rather than
> buried.** `TALARIA_SIM_NAME=CC-lane-2 scripts/mac/lane-gate.sh`. **The
> authoritative run is the POST-REBASE one and it passed FIRST TRY: `GATE: PASS`
> on 24A5423a — 2827 Swift Testing in 243 suites / 15 XCUITest, every one green
> / Release build clean.** (`origin/main` had moved under this lane and the move
> carried COMPILED inputs — another lane's `DeviceActionTools`,
> `LocalChatBackend+Battery` and two test files — so a re-gate was owed and run;
> a tracker-markdown-only rebase would not have needed one. 2827 = 2811 on their
> tree + this lane's 16.)
>
> Before the rebase, three runs on BYTE-IDENTICAL sources produced **2825 Swift
> Testing in 242 suites** (baseline 2809; +16 is exactly this lane's new tests,
> so the count MOVED) and `GATE: PASS` on the third.
>   - **Swift Testing was GREEN on all four runs.** Every red was one
>     XCUITest, and a DIFFERENT one each time: run 1 `testConnectedRelaunchSkipsTheConnectEntry`
>     (#219's known flake — the pre-declared re-roll), run 2
>     `testSettingsDeckNavigation` (*"swipe must advance the deck"*, #182's
>     synthesized-gesture family), runs 3 and 4 none.
>   - **The identical-bytes matrix is the control, and it was run BEFORE the
>     explanation was written** (the standing trap: a true structural argument
>     is not an alibi). Across runs 1–3 **every one of the 15 XCUITests passed at
>     least twice and no test failed twice** — including run 2's, which had
>     passed on the same bytes in run 1. Neither red is reproducible and neither
>     is this diff's.
>   - **The environment is named because it is measurable, and the confirmation
>     is the cleanest part of this record:** a concurrent lane drove this Mac to
>     a 1-minute load average of **138** during run 3's build (72–107 during run
>     2). Run 4 started at load **3.9** with that lane finished — and passed
>     first try, all 15. CLAUDE.md already records host load as the cause of this
>     exact failure shape; this is the documented mechanism happening, and then
>     being removed, rather than a guess offered in its place.
>   - **#423 CONFIRMED in passing:** the two RED runs printed `XCUITest tests
>     run — 2` while 15 ran; the GREEN run printed 15. The under-report is a
>     red-run artifact, exactly as that entry says — counts above are from
>     `Test Case '-[` lines in `suite.log`, not the gate's own line.
>
> **What this lane FALSIFIED upstream, corrected in the same commit:** the
> 08-25 close-out's four-item "still outstanding" list (now one item plus a
> named residual), the 180-L block's "That copy is Owen's to approve", and
> #241's open technical question. `ConnectHostCopy`'s header gains a dated note
> that its constants now reach beyond the Connect Host surfaces, because a copy
> file whose stated scope is narrower than its real one is the next reader's
> trap.

## 224. 🎨 Mirror Hermes's three-mode approval model — ~~ours is always-on Manual, theirs is Manual / Smart / Off, and it is a gateway config key~~ — **✅ OURS IS MANUAL / SMART / OFF TOO: PHASES 1+2 BUILT 2026-08-26** (Privacy → `// Agent Actions`; GLOBAL on `UserSettings`; `.manual` still the default on every install and every old blob; Smart is deterministic caution rules with no model anywhere near the path; Off ships WITH the floor, which REFUSES rather than cards). **Remaining on this item: the two DEVICE bars — 224-1F and 224-2C, runbook cards, pre-registered and UNRUN — and Phase 3's transcript receipts, still DEFERRED per ruling 7.** The HOST-side picker is a DIFFERENT actor and already shipped (#224-APP, 2026-08-25); the two never negotiate.

> **⚖️ OWEN'S RULING 2026-08-09 (interactive decision pass, recorded same day):**
> **OWN SITTING; CLAUDE PREPS THE BRIEF.** The eight questions get a
> one-page brief with the answered constraint baked in — approval-mode
> SELECTION is dashboard-only (no `/api/config` on `:8642`, re-verified
> 2026-08-09), so the app can DISPLAY and honor the mode, never SET it.
> The sitting is eight rulings, not research. Brief owed before scheduling.

**Filed 2026-08-02 from Owen's screenshot + direction ("Probably need to mirror the hermes
side, just a thought").** Source-confirmed the same evening, so this is not filed on a
screenshot alone.

> **📍 READ THIS BEFORE THE SHELVING NOTE BELOW (head pointer added 2026-08-09,
> #304 lane, dispatch §4 C8).** The 2026-08-04 shelving ("structurally blocked
> AND operationally unneeded") is true of **reading/writing the host's
> `approvals.mode`** — re-verified 2026-08-09, no `/api/config` in
> `_http_route_table()` — and says **nothing about ANSWERING** the host's
> approval requests. That half was routed out of this item by the 2026-08-06
> update at the foot: it rides **#304** (Phase 3 slice 3B,
> `POST /v1/runs/{run_id}/approval`), filed and executing 2026-08-09. A reader
> who stops at the shelving note concludes the wrong thing — the dead §F7d turn
> HAS a fix lane; only mode SELECTION stays parked.

**What Hermes has.** `hermes_cli/web_server.py:933` declares the config key
**`approvals.mode`**, `"Dangerous command approval mode"`, options
**`["manual", "smart", "off"]`** — matching the screenshot's *Manual* ("ask before actions
that require approval") / *Smart* ("automatically assess actions and ask when needed") /
*Off* ("run without approval prompts"). It is a first-class **config key with a schema**,
not a hidden flag. (My 2026-08-02 §F7 note called this "YOLO on/off" from `cli.py`'s
`enable_session_yolo` — that is the session-scoped mechanism, **not the whole model**.
Corrected here and in the device list.)

> **⛔ CORRECTED 2026-08-02, hours after filing — the transport claim below was wrong, and
> the replacement is BETTER.** This entry said `approvals.mode` was "readable via
> `GET /api/config` + `/api/config/schema`, writable via `PUT /api/config`, all on `:8642`
> under the chat-plane key." **`/api/config` is DASHBOARD-only (`:9119`) and 404s on
> `:8642`** — verified live against a fresh 0.19.1 gateway. Same root cause as #223's
> retraction: dashboard routes read as chat-plane routes. So **half (2), "mirror the
> CONTROL," cannot be built as described** — it would mean a second port and a second auth
> scheme, against the zero-setup goal.
>
> **But `_http_route_table()` turned up something the config key never offered:
> `POST /v1/runs/{run_id}/approval` IS on `:8642`**, beside `POST /v1/runs`,
> `GET /v1/runs/{id}`, `GET /v1/runs/{id}/events`, and `POST /v1/runs/{id}/stop`. That is a
> purpose-built **answer** channel on the plane the phone already authenticates to —
> strictly more useful than reading a mode, because it lets the phone *resolve* a pending
> approval rather than merely observe the policy. **Revised shape for half (2):** not
> "surface the host's setting," but "answer the host's approval requests."
>
> **The probe that decides it, and it is cheap:** Talaria drives
> `POST /api/sessions/{id}/chat/stream`; the approval endpoint hangs off `/v1/runs`. So the
> open question is whether a Sessions-API run is reachable as a run id — i.e. whether
> `run.started`'s id (already in our SSE taxonomy) is a `/v1/runs` id. If it is, the phone
> can answer approvals today with no new infrastructure. If it isn't, the two planes are
> disjoint and §F7d's stall is structural. **Run this before any #224 design work.**
> *(Related, from the #223 investigation session: hooks do NOT fire for Sessions-API runs —
> evidence that the Sessions plane is thinner than the runs plane, so do not assume.)*

**What we have.** One always-on **Manual** gate: `ToolConfirmationCenter` (#29) suspends
every side-effecting on-device tool on an editable card. There is no user-facing mode at
all — `autoAcceptForBattery` is harness-only. So the local brain can never be told "stop
asking," and can never be told "use judgement."

> **⛔ THAT PARAGRAPH DESCRIBES 2026-08-02 AND IS FALSE FROM 2026-08-26.** Phases
> 1+2 shipped the user-facing mode (Privacy → `// Agent Actions`, three rows,
> global on `UserSettings.approvalMode`, `.manual` still the default). The brain
> CAN now be told "stop asking" (Never ask — with the floor) and "use judgement"
> (Ask when unusual — deterministic rules, never the model). `autoAcceptForBattery`
> is unchanged and still harness-only, and still short-circuits ahead of the mode
> read, so no battery number is affected. Result block at the foot of this entry.

**Two distinct things this could mean, and they are separable — Owen has endorsed the
direction, not a design:**
1. **Mirror the MODEL for our own gate.** Talaria's confirm gate grows the same three
   modes for on-device tools. *Manual* = today. *Off* = never prompt (needs a written
   blast-radius rule: our tools write calendars, reminders, contacts — "dangerous" is a
   different set than Hermes's shell commands). *Smart* is the hard one — it implies a
   classifier, and **the #200-series is a long record of this model mis-assessing which
   action a turn needs**, so "automatically assess" cannot be handed to the same model
   that produced the grabs without a measured bar. Suggest Manual/Off first, Smart only
   behind a battery.
2. **Mirror the CONTROL of the host's mode.** Surface `approvals.mode` in Settings so
   the phone can see and set what the host will do — the same read/write the dashboard
   does. Cheap, no classifier, and it makes §F7d's "the host is waiting on an approval
   nobody can answer" state *visible and fixable from the phone*.

**Why (2) is likely the higher-value half.** §F7's source check found Talaria handles
**no approval event at all** — no SSE case, no producer for `InboxItemType.approval`
outside `DemoData`. So today, a host in *manual* mode plus a phone that cannot answer =
a dead turn. Being able to READ the mode at least lets the app say *why*. Answering
host-side approvals in-app is a third, bigger piece — file it only if §F7d shows the
stall is real.

**Ordering:** §F7d (device list) measures the actual failure first. Then (2) as a small
lane. Then (1) as a design question, Smart last if ever. Rides #223's gateway-API
direction — one more thing the gateway already carries.

**🔬 THE DECIDING PROBE RAN — 2026-08-04 ~8:15 AM, v0.20.0, prompted by Owen's
worry ("we'll have to integrate with the gateway more to make that work").
VERDICT: THE PLANES ARE DISJOINT.** A fresh Sessions-API streamed turn's
`run.started` id (`run_597cd29e…`) was looked up on `/v1/runs/{id}` WHILE THE
RUN WAS LIVE → `404 run_not_found` (and again post-completion; an 8-hour-old
id from the #241 probes also 404s). So `POST /v1/runs/{id}/approval` cannot
answer a chat run's approval on today's API — consistent with the earlier
finding that hooks don't fire for Sessions-API runs (the Sessions plane is
thinner than the runs plane). **Disposition:** half (2) — anything touching
the HOST's approval machinery — is PARKED: building it means new gateway
surface (dashboard-plane config, or upstream work joining the two planes),
which is exactly the added coupling Owen flagged and the brief's
stop+approval-only control plane discourages. Revisit only if §F7d ever shows
a real chat turn stalled on an unanswerable approval — then it's a Lane-6-class
upstream conversation, not an app patch. **Half (1) — Manual/Off (Smart
gated behind a battery, #200-series caution) for OUR OWN on-device confirm
gate — needs zero gateway anything and stays fully buildable app-side.**

**⏸ SHELVED 2026-08-04 morning on Owen's operational report: his host runs
smart/auto mode and "i've never seen it ask for an approval" — the approval
base rate in his real usage is ~zero (his side-effecting work rides OUR
on-device tools and their confirm cards; host-side work is reads). So half
(2) is structurally blocked AND operationally unneeded, and half (1) is a
comfort feature with no expressed discomfort — the #233 AM/PM catch happened
ON a confirm card, so the cards are currently load-bearing. Reopen triggers:
a real chat turn observed stalled on an unanswerable approval (→ upstream
conversation), or Owen asking for the cards to stop prompting (→ the small
Manual/Off app lane).**

> **📝 2026-08-05 (from #251's approvals probe): OJAMD's gateway config is
> now `approvals.mode: off` (agent self-read of config.yaml). NOT a
> contradiction of the shelving premise — Owen had smart on when he made
> the 08-04 report, and turned approvals off himself afterward ("since I
> wasn't sure it was set up properly," corrected 2026-08-05). So the
> operational observation stands under BOTH configs: smart never surfaced
> a prompt in his real usage, and off can't. The probe verified
> the Sessions-API approval WIRE exists and is advertised
> (`/v1/capabilities`: `approval_events`, `run_approval_response`;
> `approval.request` SSE emitter + `POST /v1/runs/{id}/approval` handler
> with once/session/always/deny — code-read at api_server.py:6464/6772),
> and that terminal commands (echo AND a deletion-shaped `del`) execute
> ungated under mode=off. Also learned: `approvals.cron_mode: deny` — cron
> runs deny side effects silently under current config. Item stays SHELVED;
> the #251 venture's interactive half is now the natural reopen path.**

> **Update 2026-08-06 late night (Phase 3 scoping):** the §F7d failure has a MECHANISM now,
> not just a symptom — a Sessions-plane turn under host `manual` is
> **blocked-and-queued** for an unreachable `/approve` (`_bind_api_server_session`
> hardwires `platform="api_server"` → `_is_gateway_approval_context()` true →
> the gateway branch finds no notify callback and queues,
> `tools/approval.py:243-261`, `:3154-3171`), and the agent is handed "⚠️ … Asking
> the user for approval," which it narrates. **The user sees the agent say it is
> asking, and then nothing** — neither a hang nor a silent auto-approve. The runs
> plane has the full wire (`register_gateway_notify` fires in exactly one place,
> `_handle_runs`, `api_server.py:6524`), proven e2e 2026-08-05. **Half (2) stays
> parked** (the mode itself is dashboard-only config, `:9119`); the fix for the
> dead turn is answering approvals, not reading the mode, and it rides **Phase 3
> slice 3B** (`design/PHASE3-RUNS-MIGRATION-PLAN-2026-08-07.md` §2.2). Note that
> the app-side proposal `design/APPROVAL_MODES_PROPOSAL-2026-08-07.md` deliberately
> excludes all of this — it governs OUR gate; this governs the HOST's.

> **2026-08-09 corrections to the update above (#304 lane, dispatch §4 C4/C1):**
> **(C4)** the update is true and INCOMPLETE the same way the plan's N6 bullet
> was — a dropped-stream approval is visible "as a state but not as a question,"
> **and the ANSWER channel is stream-independent**: `resolve_gateway_approval`
> works off `_gateway_queues[session_key]`, and `_run_approval_sessions[run_id]`
> is popped only in the run's own `finally`, so a client that lost the stream
> can still POST a deny and it lands. The honest degraded state includes a
> working Deny (bar 304-D(i)), not just an explanation. **(C1)** every
> `api_server.py:NNNN` cited in this entry was read at pre-`3dcbe9001` heads and
> is stale (e.g. `_handle_run_approval` `:6772`→`:6929`,
> `register_gateway_notify`'s sole site `:6524`→`:6681`); the runs region
> drifted ≈ +150 lines while the version string stayed `0.20.0`. Cite the head
> you read; re-resolve before quoting (drift table: dispatch
> `FABLE-T27-283-3B-approvals.md` §4 C1).

> **✅ OWEN'S BALLOT 2026-08-10 — "APPROVED", ALL EIGHT AS RECOMMENDED.**
> The sitting ran interactively in the consolidated pending review
> (2026-08-10, post-wave-2) against
> `planning/224-APPROVALS-SITTING-BRIEF-2026-08-10.md`; no card flipped. The
> rulings of record: **(1)** Phase 0 builds now, Phases 1–3 hold un-dispatched
> until Owen asks for fewer prompts in so many words; **(2)** the gate is
> GLOBAL (`UserSettings`), not per-profile; **(3)** "Off" ships WITH the
> floor; **(4)** the floor REFUSES (explanatory error, no card — carding
> would make Off secretly identical to Smart); **(5)** Smart is
> deterministic rules or nothing — the on-device model never goes on the
> safety path (the #200-series record plus #297's 7/20 miss); **(6)** the
> control's home is the Privacy screen, between Location and App Lock;
> **(7)** transcript receipts for auto-approved actions DEFERRED — decided
> by use after living with Phases 1–2; **(8)** the `/approvals smart` slash
> probe is NOT run now. **Next action: Phase 0 dispatch (OPUS-tier: Manual
> card improvement + the mode scaffold behind it), bars pre-registered in
> this entry before any code.** Design of record remains
> `design/APPROVAL_MODES_PROPOSAL-2026-08-07.md`.

**BARS — PHASE 0 ONLY, pre-registered 2026-08-11 BEFORE any code, per the
ballot's own next-action line. Phases 1–3 stay un-dispatched; their sketch
bars in `design/APPROVAL_MODES_PROPOSAL-2026-08-07.md` §6 are NOT
pre-registered here and must not be treated as such. Anchors resolved at
`506a319`.**

- **224-0A — `scheduleAlarm` gains caution rows.** An early-morning alarm
  (before 07:00 local) and a past-due one (beyond the 5-minute grace) each
  stage a caution row. The caution wording carries **no formatted date or
  time** the model could mine into a fabricated success claim — the #233-E /
  #249-F rule, pinned by assertion, not by review.
- **224-0B — `createCalendarEvent` gains the same two rules** (past-due and
  early-morning starts), same wording constraint.
- **224-0C — RED witnessed first.** Neither tool passes `caution:` at HEAD, so
  0A's and 0B's tests must FAIL before the change and pass after. A green-only
  run does not score this bar (the #313 / "tests written after a defect" rule).
- **224-0D — boundary coverage.** Unit tests per tool at 06:59 / 07:00 and at
  both sides of the 5-minute past-due grace. Swift Testing count MOVES; the
  before/after numbers are recorded in this entry.
- **224-0E — the mode scaffold exists and is unreachable.** An `ApprovalMode`
  type ships with `.manual` implemented and `.smart` / `.off` present as cases
  every switch must handle (#306's C1 precedent — name the door on day one).
  It reads from **`UserSettings`, GLOBAL, not per-profile** (ruling 2).
  **No user-facing control ships in Phase 0** (ruling 1) and `.manual` is the
  only reachable value — asserted, so a later lane cannot expose a mode by
  accident.
- **224-0F — the model-free pin, placed now rather than at Phase 2.** No
  `LanguageModelSession` is constructed anywhere on the approval path
  (ruling 5). Asserted at scaffold time so Phase 2 inherits the pin instead of
  adding it.
- **224-0G — `GATE: PASS`** (units + XCUITest + **Release**), unit count moved,
  logs path recorded here.

> **KILL CLAUSE, written before the run:** if extending the caution layer
> cannot be done without editing either tool's SUCCESS-claim text, **stop and
> report** rather than proceeding — that text is #233's defended surface and a
> change to it is a different decision than the one Owen balloted.

**✅ PHASE 0 RAN — 2026-08-11, branch `t27-224-phase0-caution` off `fb8d28c`.
ALL SEVEN BARS MET. The kill clause never came close to firing: neither tool's
success-claim text was touched, and neither tool's success path was entered at
all — the whole change is one `caution:` argument per tool plus the pure
function behind it. Phases 1–3 stay UN-DISPATCHED (ruling 1).**

Result in one line: `createCalendarEvent` and `scheduleAlarm` now stage caution
rows, and an `ApprovalMode` type ships with `.manual` as its only reachable
value. **No user-facing control ships.**

- **224-0A — MET.** `AlarmTool.caution(for:now:calendar:)` stages
  `EARLY MORNING — CHECK AM/PM` for a fixed-time alarm in hours 0–6 and
  `ALREADY PASSED TODAY — RINGS TOMORROW` for one whose occurrence today is
  stale beyond #249's five-minute grace; `AlarmTool.call` passes it. The alarm
  grammar resolves to a clock time, never a date, so both rules read the
  request against `now` rather than a parsed due, reusing `isEarlyMorning` and
  `isPastDue` verbatim rather than restating their thresholds. A countdown
  trips neither (always future, no clock hour to misread). Tests:
  `weeHourAlarmStagesACautionRow`, `alarmCautionEarlyMorningBoundary`,
  `alarmCautionPastDueGraceBoundary`, `countdownAlarmNeverCautions`,
  `weeHourAlarmOutranksAlreadyPassedToday`,
  `afternoonAlarmStagesWithNoCautionWhenStillAhead`.
- **224-0B — MET.** `CalendarEventTool.startCaution(for:now:)` stages
  `STARTS IN THE PAST` and `EARLY MORNING START — CHECK AM/PM`;
  `performCreate` passes it and gained an injectable `now` (default `Date()`;
  production never passes it) for the same reason the reminder engine has one.
  Tests: `weeHourEventStartStagesACautionRow`, `pastEventStartStagesACautionRow`,
  `ordinaryEventStartStagesWithNoCaution`, `eventStartCautionEarlyMorningBoundary`,
  `eventStartCautionPastDueGraceBoundary`, `pastWeeHourEventStartReadsAsPastFirst`.
- **The wording constraint (0A + 0B) — MET, pinned by assertion.**
  `phase0CautionRowsCarryNothingMineable` asserts every row this lane adds is
  **DIGIT-FREE**, which is strictly stronger than "no formatted date": every
  formatted date and time carries digits, so a digit check cannot be satisfied
  by one. **Scope, stated rather than left to be discovered: the REMINDER
  card's rows still carry `displayDate`/`timeOnly`** — they predate the
  #233-E/#249-F rule, they are #233/#249's shipped and device-validated
  surface, and rewriting them was not balloted. The card is therefore
  deliberately inconsistent between tools, and that is a decision, not an
  oversight.
- **224-0C — MET; RED WITNESSED FIRST, and here is how.** The wiring tests were
  written against API that already existed at HEAD (`performCreate` /
  `AlarmTool.call` / `ToolConfirmationCenter.pending`), so they COMPILE at HEAD
  and FAIL there rather than failing to build — a build error is not a RED. The
  four production edits were removed with
  `git stash push -- Talaria/Models/UserSettings.swift
  Talaria/Services/Live/DeviceTools/DeviceActionTools.swift
  Talaria/Services/Live/DeviceTools/ToolConfirmationCenter.swift
  Talaria/Stores/AppContainer.swift`, the targeted run was executed, and the
  stash was popped after. Verbatim (`/tmp/224p0-red.log`, 2026-08-11 13:5x):
  ```
  ✘ Test weeHourEventStartStagesACautionRow() recorded an issue at Phase0ActionCautionTests.swift:88:9: Expectation failed: center.pending?.caution == "EARLY MORNING START — CHECK AM/PM"
  ✘ Test pastEventStartStagesACautionRow() recorded an issue at Phase0ActionCautionTests.swift:107:9: Expectation failed: center.pending?.caution == "STARTS IN THE PAST"
  ✔ Test ordinaryEventStartStagesWithNoCaution() passed after 0.007 seconds.
  ✘ Test weeHourAlarmStagesACautionRow() recorded an issue at Phase0ActionCautionTests.swift:150:9: Expectation failed: center.pending?.caution == "EARLY MORNING — CHECK AM/PM"
  ✘ Test run with 9 tests in 2 suites failed after 0.950 seconds with 4 issues.
  ```
  Every one of the three read `center.pending?.caution → nil` — the precondition
  the bar names, observed rather than asserted. **`ordinaryEventStartStagesWithNoCaution`
  passing in the same run is the control**: it says the three failed because the
  caution was absent, not because the harness never staged a card. (The fourth
  issue was the 224-0F source scan; see below.)
- **224-0D — MET.** Boundary coverage per tool, on an injected clock.
  `isEarlyMorning` is hours 0…6: **06:59 trips, 07:00 does not**, tested for
  both tools. `isPastDue` is `date < now - 300`: **-299 s and exactly -300 s are
  inside the grace, -301 s is not**, tested for both (the alarm's at
  08:04:59 / 08:05:00 / 08:05:01 against an 8 AM request). Counts:
  **BEFORE 2056 tests in 156 suites** (`/tmp/gate-224p0-baseline/suite.log`,
  the same 2056/156 #324's beta5 audit recorded on `main`, which
  cross-validates the baseline) → **AFTER 2078 tests in 158 suites**
  (`/tmp/gate-224p0/suite.log`). +22 tests, +2 suites.
- **224-0E — MET.** `ApprovalMode` in
  `Talaria/Services/Support/ApprovalModeCore.swift`: `.manual` implemented,
  `.smart` and `.off` present so every switch is exhaustive from day one
  (#306's C1). The policy table is `disposition(hasCaution:)`, one pure
  function carrying the balloted §3.4 rows including ruling 4's `.off` +
  caution ⇒ REFUSE. Persisted as **GLOBAL `UserSettings.approvalMode`**
  (ruling 2), read by the gate through `ToolConfirmationCenter.modeProvider`,
  armed in `AppContainer` from `settingsStore.settings.approvalMode` — so the
  key is real, not vestigial. **`.manual` is the only reachable value, and it
  is unreachable at the DATA layer, not merely un-rendered:**
  `ApprovalMode.selectable == [.manual]` and the settings decoder clamps
  through `ApprovalMode.resolved(_:)`, so a blob that literally says
  `"approvalMode":"off"` decodes to `.manual`
  (`approvalModeIsAGlobalUserSettingsKeyDefaultingToManual`). A later lane that
  widens `selectable` turns `approvalModeExposesOnlyManual` RED — exposing a
  mode has to be a deliberate edit to the line that says so.
  `anUnreachableModeStillStagesTheCardRatherThanActing` proves the second
  half: even if a future lane arms `.smart`/`.off` without building their
  paths, the gate stages the card anyway (default-CLOSED — an unhandled mode
  costs a prompt, never an unapproved write).
  - **⛔ THE PREDICTION IN THIS BULLET FIRED, 2026-08-26.** Phases 1+2 widened
    `selectable` and all four named tests went RED exactly as designed — see
    the RED-witness block in the Phases 1+2 result at the foot of this entry.
    Three were rewritten as the deliberate acknowledgement the design demanded
    (`approvalModeExposesOnlyManual` → `approvalModeExposesAllThreeAfterPhases12`,
    `approvalModeClampsUnreachableValuesToManual` →
    `approvalModeResolvesEverySelectableModeToItself`,
    `anUnreachableModeStillStagesTheCardRatherThanActing` →
    `noModeSilentlyCreatesAFlaggedAction`), and
    `theGateStagesACardUnderTheOnlyReachableMode` was renamed to
    `theGateStagesACardUnderManual`. **The property survives:** `selectable`
    is still a literal list rather than `allCases`, so the next case added
    still does not ship itself, and the clamp still guards the next
    NARROWING. Cite the new names from here on.
- **224-0F — MET, in two halves, because one is not enough.**
  (i) `approvalPathDecisionsAreSynchronousAndModelFree` — **the pin is the
  absence of `async` on that test body**, not an expectation inside it. Every
  approval decision is a pure synchronous function; a `LanguageModelSession`
  turn is necessarily `await`ed, so putting the model on this path means making
  one of them `async`, which stops the file compiling. (ii) the type system
  cannot see `requestConfirmation`, which is legitimately `async`, so
  `approvalPathSourcesNeverReferenceALanguageModelSession` reads the three
  approval-path sources and fails if the symbol appears outside a comment. It
  carries a **positive control** — it asserts the scan still FINDS the
  constructions in `LocalChatBackend+IntentRouting.swift` — because a scan that
  has never fired is indistinguishable from one that cannot fire.
  - **⚠️ QUALIFIED 2026-08-12 (#332-a): half (ii) is a SIMULATOR-ONLY bar, and
    "MET" above should be read as "met on the simulator".** Reading the repo's
    Swift sources at runtime works only where the test process shares the Mac's
    filesystem. On a device the sources do not exist, and this test red-ed the
    first device suite run this project ever did — on BOTH devices,
    `NSCocoaErrorDomain 260` — and would have red-ed every one after it. The
    lane that landed it recorded *"the source-scan approach works from the
    simulator sandbox (it read all four files)"* without noticing that was a
    property of the SANDBOX, not of the test.
  - **The fix keeps the bar and narrows its claim** (#332-a, same date): the
    body is unchanged — positive control included — and the test now carries
    `.enabled(if: repoSourcesAreReadableAtRuntime, …)`, a compile-time
    `#if targetEnvironment(simulator)` discriminator, so off-simulator it
    **skips with a reason naming #332-a** instead of failing. **Consequence for
    reading this entry:** ruling 5's *source-scan* half is scored on every gate
    run and on NO device run. Half (i) — the synchronous, non-`async` pin — is
    unaffected and is scored everywhere, which is why 0F was written in two
    halves in the first place.
- **224-0G — MET.** Verbatim, `/tmp/gate-224p0.log`:
  ```
    PASS  Test run reported TEST SUCCEEDED
    PASS  Swift Testing tests run — 2078
    PASS  XCUITest tests run — 14
    PASS  Release build succeeded
    PASS  no Swift compile errors in Release
  GATE: PASS — logs in /tmp/gate-224p0
  ```
  Sim `CC-224-iPhone-Air` (`658E3991-…`), calendar + reminders TCC granted
  immediately before the run. Two notes on the run, neither a pass being
  claimed for something unproven: the preflight printed
  `WARN project.pbxproj is modified` — that is the uncommitted `xcodegen`
  regen for the two new files, which THIS commit lands; and the gate's four
  reported SKIPS are the pre-existing set (two `CondenserFidelityTests`, two
  #282), unchanged by this lane and none of them ours.

**Three things the bars did not anticipate, all worth the next lane's time:**

1. **The wee-hour rule fires on the CANONICAL morning alarm.** `isEarlyMorning`
   is hours 0–6, so `"6:30am wake up"` — an ordinary alarm, not a defect —
   carries `EARLY MORNING — CHECK AM/PM` on every card. Under Manual that is one
   amber line on a card the user is already tapping, which is the cost the bar
   bought. **Under Phase 2's Smart it would mean every pre-7 AM alarm CARDS
   instead of auto-approving** — conservative in the safe direction, but not
   "ask only about the unusual". Phase 2 must decide that deliberately; the
   threshold is #233's and moving it is a written decision, not a detail to
   discover in use. Not changed here: the bar said "before 07:00 local" and a
   missed bar is a falsification, not a redefinition — so is a quietly
   improved one.
2. **The `/alarm` SLASH COMMAND is a second door and it got nothing.**
   `ChatScreen.swift`'s `.alert("Schedule on this iPhone?", …)` (#193) is a
   separate consent surface from `ToolConfirmationCenter`, with no caution row
   and no mode. The bars named the `scheduleAlarm` TOOL and that is what was
   built — correctly — but if a mode ever ships, "Never ask" would be untrue of
   one path into AlarmKit until this door is answered for.
3. **🔴 THE PROJECT'S POLL-THEN-DECLINE TEST IDIOM CAN HANG THE SUITE, and it
   did — this is a live hazard in `DeviceActionToolsTests`, not a story about
   this lane.** The shape is
   `while center.pending == nil && attempts < 2_000 { await Task.yield() }`
   followed by `center.decline()` and `await task.value`. It is a RACE, not a
   flake: when the budget expires before the tool's Task has reached
   `requestConfirmation`, the test declines an EMPTY gate — a no-op that still
   logs `confirmation declined`, so the log looks normal — the tool stages a
   moment later, and it then suspends on a continuation nobody will ever
   answer, so `await task.value` never returns. **Measured on the first RED
   attempt (`/tmp/224p0-red-attempt1.log`): the card arrived 3.4 SECONDS after
   the yield budget ran out** (declined 13:42:11.028999, staged
   13:42:11.029432 — that second staging is the orphan), with three lanes
   building on this Mac. The run had to be killed. **A yield count is not a
   clock**; 2,000 of them are microseconds or minutes depending on who holds
   the main actor. This lane's tests use `awaitStagedCard`, which waits on a
   `ContinuousClock` deadline and, if no card arrived, records an issue and
   deliberately does NOT decline or await — leaking a suspended Task is bad,
   hanging the suite is worse. **The five older loops in
   `DeviceActionToolsTests.swift` were left alone** (out of scope, and green
   today because a full run reaches them warm), but they are the same shape and
   one of them will eventually eat a gate run on a loaded host. Filing that
   conversion is the next reader's call.

**Upstream corrections made in this commit** (close-out rule): four in
`design/APPROVAL_MODES_PROPOSAL-2026-08-07.md` — §2's gate table (both "**no
caution**" cells now false), §2's "the caution layer exists **on one tool**"
(all three now), §2's "modes exist today only as DEBUG battery flags" (a
production persisted mode exists and is deliberately not user-visible), and
§3.5's "hard precondition" (discharged). §6's Phase 0 sketch also gained a
**do-not-cite** warning: its `224-0C` is the boundary bar, whereas the
REGISTERED `224-0C` is the RED-first bar and the boundary bar is `224-0D`,
so a reader citing a letter from that page means a different bar from the one
scored here.


> **⚖️ 2026-08-24 night (Owen, interactive decision pass): RE-PROBE BEFORE
> ANY PHASE — "Re-probe 224 since so much has changed. Lets make sure
> there's not an easier exposed way to do this now, and then reassess."**
> The Phase 1–3 hold stands; the new first step is a read-only probe of
> the CURRENT host surface (0.20.5+, vs the 0.19.1-era scoping): does the
> gateway now expose approval-mode selection anywhere the phone can reach —
> `/v1/capabilities`, the route table, a config surface, or run-level
> fields — that the 2026-08-09 verification (no `/api/config`; selection
> dashboard-only) predates? Probe result reassesses the ballot; probes are
> free, no go needed.


> **🔍 RE-PROBE RAN 2026-08-24 night, same hour as the ruling — read-only,
> Mac gateway 0.20.5 + upstream source at `503d863f`. THE EASIER WAY
> HALF-EXISTS, and the missing half is small:**
> 1. **Upstream now owns persistent mode selection: `/approvals
>    [manual|smart|off]`** — a gateway slash command
>    (`gateway/slash_commands.py` `_handle_approvals_command` →
>    `hermes_cli/approval_mode.py`, persisting `approvals.mode` through the
>    canonical config chokepoint; admin-gated per source, unconfigured
>    policies unrestricted). A session-scoped `/yolo` bypass toggle exists
>    beside it. This is exactly what the 2026-08-09 verification found
>    dashboard-only — it moved.
> 2. **But the runs plane does NOT enter the slash pipeline** — wire-proven
>    tonight: a `/approvals` turn POSTed to `/v1/runs` went to the MODEL
>    (3+ minutes of agentic chewing; a slash intercept returns its canned
>    "Approval mode: …" string instantly). Probe run stopped cleanly via
>    `/stop`. The phone cannot reach the command as a turn today.
> 3. `/v1/capabilities` grew an `admin_config_rw` flag — hardcoded FALSE
>    (a deliberate this-plane-has-no-config-RW declaration, not a toggle).
>    No door there.
> **Reassessment shape for Owen (his "then reassess"):** the balloted
> Phases 1–3 app machinery may now be oversized. A one-verb addition to OUR
> plugin (`set_approval_mode` → `run_approval_mode_command`, the same
> admin-gated chokepoint) would give the phone a sanctioned 3-mode picker
> riding upstream's own semantics — the app side shrinks to a picker row +
> a state read. Alternatives: keep holding, or the original phases. The
> plugin-verb route is recommended; deploy would ride a per-experiment go
> like any plugin change.


> **⚖️ ROUTE ELECTED 2026-08-24 late (Owen, on the probe: "For approvals,
> thats great. Halfway easier, and just some verbs away. Sounds good to
> me."): THE PLUGIN VERB.** Two design calls made and surfaced (no
> objection): paired-device auth stands in for the slash gate's admin check
> (the threat model is an unlocked phone in the wrong hands, which is App
> Lock's own model), and `/yolo` is NOT exposed — the phone gets the three
> persistent modes only. Owen also cleared updating the UNSENT OJAMD brief
> in place ("I haven't sent ojamd's deploy yet... feel free"), so one desk
> visit deploys presets + floor + this verb.

> **🎯 BARS 224-V-A..F — pre-registered 2026-08-24 late, BEFORE any code
> (the plugin half; the app picker's bars pre-register when its lane
> opens):**
> - **224-V-A:** a new `approval_mode` verb on the envelope dispatch,
>   device-auth-gated exactly like the talk family (bogus auth ⇒
>   `device_auth_mismatch`); with no `mode` field it READS — returns the
>   current effective mode without mutating anything.
> - **224-V-B:** with `mode` ∈ {manual, smart, off} it persists through
>   upstream's own `run_approval_mode_command` chokepoint (canonical
>   `set_config_value`, managed-scope safety preserved), verified by
>   read-back in an isolated HERMES_HOME; the response carries
>   `{ok, mode, changed, message}` mapped from `ApprovalModeResult`.
> - **224-V-C:** an invalid mode passes through upstream's rejection —
>   `ok: false`, the usage message, mode unchanged (we duplicate NO
>   validation; upstream's table is the table).
> - **224-V-D:** structural negative pin — the dispatch map carries NO yolo
>   verb, RED-provable by adding one.
> - **224-V-E:** an unavailable `hermes_cli` import degrades to a NAMED
>   error code (`approval_mode_unavailable`), never the generic
>   `storage_error`.
> - **224-V-F:** plugin version 0.6.0 → 0.7.0; pytest count moves by
>   exactly the additions; RED witnessed before code; a wiring mutation
>   (delete the dispatch row) isolates. Deploy rides the per-experiment go
>   — the OJAMD brief is retargeted in place (unsent, Owen's clearance
>   above); the Mac's own deploy needs its own go.


> **✅ RESULT 2026-08-24 late — 224-V-A..F ALL MET (the plugin half).
> Plugin main `b87cd6c`, version 0.6.0 → 0.7.0; DEPLOYED NOWHERE — the
> unsent OJAMD brief was RETARGETED in place on Owen's clearance
> (`HANDOFF-OJAMD-2026-08-24-PLUGIN-DEPLOY-B87CD6C.md` on the Workhorse
> share; one desk visit now deploys presets + floor + this verb, expected
> range fb2e364 → exactly three commits, plugins-list flip 0.5.0 → 0.7.0).**
> RED-first honest: 6/6 verb tests failed `unknown_event_type` before code
> (the two no-yolo pins were green negative controls). Suite **208 → 216**
> (+8 exactly); `hermes plugins doctor --ci` clean. Two mutations, both
> isolating: deleting the dispatch row reds the six verb tests and nothing
> else; ADDING a yolo verb reds both 224-V-D arms. The isolated-home probe
> before the tests pinned upstream's default (`smart` on an empty home) and
> — worth knowing — the live Mac host runs `approvals.mode: 'off'`.
> **What remains on the #224 board:** the APP half (picker row + state
> read, capability-gated with #396's host-predates pattern — bars
> pre-register when that lane opens), the verb's deploy (rides the brief /
> a Mac go), and Owen's Phases-1–3 reassessment once the picker exists.


> **🎯 BARS 224-APP-A..F — pre-registered 2026-08-24 late, BEFORE code (the
> app half). Recon: `voiceVerb` is already a generic envelope sender with
> the `unknown_event_type → .unsupported` classifier built in; the picker
> home is `ServerSettingsScreen` after the plugin-link panel (its refresh is
> already keyed on the active profile); #396's segmented-row + pinned-copy +
> predates-footnote pattern is the model.**
> - **224-APP-A:** the link grows `approvalMode(setting: String?)` riding
>   the existing verb sender — wire shape `{type: "approval_mode"[, mode]}`
>   pinned by a TalariaPlatformLinkTests wire test (the #396 tuning-test
>   pattern); decode of `{ok, mode, changed, message}` lives with the
>   caller, not the transport.
> - **224-APP-B:** host state is THREE-VALUED (`unknown` / `unsupported` /
>   `mode(String)`) with UNKNOWN as the default branch (#180 rule 5) — the
>   picker renders disabled/"—" until the read answers; mapping is
>   `.ok → mode`, `.unsupported → unsupported`, `.unreachable → unknown`.
> - **224-APP-C:** ⛔ the on-device `ApprovalMode` enum is NOT touched — the
>   host mode is a DISTINCT type (raw wire string); every Phase-0 pin
>   (`approvalModeExposesOnlyManual`, not-per-profile, clamping) stays green
>   untouched. Touching `ApprovalModeCore.swift` is the wrong lane.
>   *(⛔ 2026-08-26: that test name is now `approvalModeExposesAllThreeAfterPhases12`
>   — Phases 1+2 renamed it, deliberately, and DID touch `ApprovalModeCore.swift`,
>   which was the right lane for it. The bar as written was correct for the
>   224-APP lane and is unaffected: the HOST mode is still a distinct type
>   and the two never negotiate.)*
> - **224-APP-D:** the host-predates footnote (unsupported state) ships
>   pinned copy naming the remedy ("after the host updates" shape, #396's
>   pinned form); set-path failures surface honestly (unreachable ≠
>   unsupported ≠ refused).
> - **224-APP-E:** a set round-trips: segment tap → verb with mode → state
>   updates from the RESPONSE's mode (never optimistically); `ok: false`
>   (managed config, upstream refusal) leaves the picker on the host's
>   reported mode and surfaces the message.
> - **224-APP-F:** GATE: PASS, count moved exactly; the device look rides
>   the runbook's next-build card; both hosts answer `unsupported` until the
>   plugin deploys, so the predates path is the FIRST-BUILT path, not an
>   afterthought.


> **✅ RESULT 2026-08-25 (small hours) — 224-APP-A..F ALL MET; the app half
> is BUILT.** `HostApprovalModeState` (three-valued, response-driven,
> UNKNOWN the default branch), `approvalMode(setting:)` on the envelope
> transport (wire-pinned: the read omits the mode key, the set carries it —
> mutation witnessed with the corrected `()` selector after the
> zero-tests-match trap fired once and was caught), and the APPROVALS panel
> on ServerSettingsScreen after the plugin-link row — disabled until the
> host answers, landing always on the REPORTED mode, host-predates footnote
> pinned. The on-device `ApprovalMode` enum untouched (its Phase-0 pins ran
> green in the gate). GATE: PASS **2526/207** + 14 XCUITest + Release
> (+11/+2 over the trio's 2515, exact). **Expected state until the plugin
> deploys: BOTH hosts show the predates footnote — that is the picker being
> honest, not broken. After deploy, the Mac should report `off` (its live
> config, measured) — a built-in first verification.**
> **What remains on #224:** the deploys (brief staged / Mac go) · the device
> look (runbook) · then Owen's Phases-1–3 reassessment with a working
> switch in hand.


> **📱 2026-08-26 evening (Owen's runbook pass, ~18:14 local; BUILD 3087, confirmed in-chat moments after the paste) — THE PICKER CHECK "FAILED", AND THE LIKELY CAUSE IS A
> DEPLOY LAG THE NIGHT BATCH ALREADY MEASURED, not an app defect.** Owen:
> Settings → Server shows "hermes host predates approval modes — the
> picker unlocks after the host updates" on BOTH hosts, "Mac is the most
> up to date and has the most recent plugin. I assume this fails."
> **The assumption to check first: Lane D measured (2026-08-25 night)
> that the Mac's LIVE plugin checkout sits at `e669549` — TWO commits
> behind origin/main, and one of the two missing commits is `b87cd6c`,
> the #224 approval_mode support itself.** So the gate may be telling
> the truth: the DEPLOYED plugin genuinely predates approval modes on
> both hosts, and "most recent plugin" described the repo, not the
> install. **Discriminating fix, ~2 min (Mac):** `git -C
> ~/.hermes/plugins/talaria pull` then the desktop app's Restart Gateway
> button (the affordance A1 traced) → re-open the picker. Unlocks ⇒ the
> gate was honest and this row flips PASS; still locked on a current
> plugin ⇒ a REAL app-side gate defect, re-file with teeth. OJAMD rides
> the standing brief either way. NOT closed — awaiting the post-deploy
> re-check.

> **📱 ~30 min later, same evening — THE DISCRIMINATOR ANSWERED: THE GATE
> WAS HONEST.** Owen pulled the Mac's plugin checkout and hit Restart
> Gateway (sidebar confirms **v0.8.0**), and: "now Talaria is showing
> Manual Smart Off for Approvals with the mac selected." **The picker
> unlocked the moment the host actually carried the verb** — same app,
> same build 3087, zero app changes between FAIL and PASS. The runbook
> row's Mac arm flips PASS, and the card's premise is fully exercised:
> Owen has now seen BOTH honest worlds (the truthful lock against a
> predates-host, and the live picker against a current one). This also
> live-proves `b87cd6c`'s verb end-to-end on a real gateway for the first
> time. **The OJAMD arm flips the same way after its own deploy** — the
> superseded 08-24 brief is replaced on the share by
> `HANDOFF-OJAMD-2026-08-26-PLUGIN-DEPLOY-B4E8DFA.md` (targets 0.8.0,
> four commits; its step 7 now scores this exact picker flip).

> **📱 SAME EVENING — THE OJAMD ARM FLIPPED TOO (Owen, live: "Switching
> to ojamd, I now have the three options!!").** Both hosts now show
> Manual · Smart · Off on build 3087 — the picker is proven end-to-end
> against BOTH gateways, and the honest-lock state was witnessed on both
> before their deploys. The runbook row is fully green. **What this
> unblocks: this entry's post-deploy phases** — the picker was the app
> half; whatever the entry's remaining phases elect next now has two
> live hosts to build against. (The Voice-footnote and lighter-picker
> glances went unreported in the same message — presumed fine, not
> scored; they can ride any future OJAMD-profile minute.)

> **⚖️ ELECTED 2026-08-26, minutes later (Owen, verbatim: "Smart is a
> part of hermes, makes sense that we should have that too. Orchestrate
> that as a lane please").** This DISCHARGES ruling (1)'s hold — not by
> its trigger phrase but by a direct election, which outranks it. **Scope,
> derived from the design of record and stated so it can be trimmed:**
> Phase 2 (Smart) structurally requires Phase 1 (the mode setting, the
> Privacy-screen control, and Off-with-the-floor — ruling 3 of his own
> 08-10 "approved all eight" ballot says Off ships WITH the floor), so
> the lane is **PHASES 1+2 TOGETHER — the complete Manual · Smart · Off
> mirror** under the eight standing rulings (global UserSettings gate ·
> Privacy screen home · Off's floor REFUSES · Smart is deterministic
> rules or nothing, no model on the safety path · receipts stay deferred
> per ruling 7 · the host's `approvals.mode` is explicitly out of scope
> per the design's own "not a phase"). The doc's §6 sketch bars
> (224-1A..F, 224-2A..D) formalize into THIS entry at lane-open with
> anchors re-resolved at HEAD (the 08-07 sketches predate Phase 0's
> scaffold and the caution system). Device bars (224-1F, 224-2C) become
> runbook cards. Merge-on-green applies.
> *(📱 First device sighting, 2026-08-26 night, build 3101: "oh neat. I
> see the settings in privacy" — the Agent Actions control renders on
> the phone. The behavioral halves await the 224-1F / 224-2C cards.)*

**🎯 BARS 224-1A..1F / 224-2A..2D — FORMALIZED 2026-08-26 at lane-open,
BEFORE any code, from the design of record's §6 sketch. Anchors re-resolved
at HEAD `627ec37e`.**

> **WHAT MOVED SINCE THE 08-07 SKETCH — read this before citing a §6 line.**
> The sketch predates Phase 0 (2026-08-11), #323-D (App Lock), #409 (the
> do-not-claim clause) and the 224-APP host picker (2026-08-25). Nine anchors
> resolve differently now:
> 1. **`locationSection` does not exist.** §3.3 says "between Location and App
>    Lock"; `PrivacySettingsScreen.body` at HEAD composes `permissionsSection ·
>    sensorStreamingSection · appLockSection · spotlightSection ·
>    revokeSection · manageSection`, and Location is a ROW inside
>    `sensorStreamingSection` (#137). The ruled position resolves to **between
>    `sensorStreamingSection` and `appLockSection`** — the same reading order
>    ruling 6 names, a different symbol.
> 2. **The policy table already exists.** `ApprovalMode.disposition(hasCaution:)`
>    (`Talaria/Services/Support/ApprovalModeCore.swift`) is §3.4's table as a
>    pure function, and `ApprovalDisposition` already names `.card` /
>    `.autoApprove` / `.refuse`. Phases 1+2 do not invent the policy; they give
>    two of its three arms an implementation and widen `selectable`.
> 3. **The caution layer is on ALL THREE tools** (Phase 0, 224-0A/0B), so
>    §3.4's "once caution exists" caveats and §3.5's hard precondition are
>    discharged — already noted in the doc, restated here because the bars
>    depend on it.
> 4. **`UserSettings.approvalMode` already ships, clamped.** 224-1A is no
>    longer "add a key"; it is "widen the clamp without moving the default",
>    and the Phase-0 pins that assert the clamp erases `off`/`smart`
>    (`approvalModeExposesOnlyManual`, `approvalModeClampsUnreachableValuesToManual`,
>    the `"approvalMode":"off"` arm of
>    `approvalModeIsAGlobalUserSettingsKeyDefaultingToManual`) are **designed
>    to go RED here** — they say so in their own doc comments. Editing them is
>    the deliberate act the Phase-0 lane demanded; deleting them is not.
> 5. **224-2B's pin already exists as 224-0F**, in two halves (the non-`async`
>    body + the sim-only source scan, narrowed by #332-a). 224-2B EXTENDS it —
>    it does not duplicate it.
> 6. **The gate grew `lockStateProvider` (#323-D).** The lock OUTRANKS the mode
>    and short-circuits ahead of the provider. Phases 1+2 must keep every
>    disposition inside the unlocked branch, and `AppLockGateTests`'
>    `lockedApprovalNeverConsultsTheMode` is what catches a lane that does not.
> 7. **`ToolConfirmationCenter.Decision` has two cases** (`approved`,
>    `declined`). The floor cannot ride `declined` — a refusal is not a decline
>    and the tools' text says "The user declined", which would be a lie.
> 8. **#409 exists now.** Its ruling — a refusal string the MODEL reads carries
>    an explicit do-not-claim clause — postdates this design and applies
>    directly: the Off floor's refusal is a tool RESULT, so the model reads it.
> 9. **There is now a SECOND approvals picker in the app** —
>    `ServerSettingsScreen`'s host APPROVALS panel (224-APP, 2026-08-25), which
>    governs the HOST's `approvals.mode`. The Privacy control governs THIS
>    PHONE's gate and nothing else; its copy must not be confusable with it.

**PHASE 1 — Manual / Off, with the floor.**

- **224-1A — the default survives the widening.** `.manual` on a fresh install
  AND on a pre-existing settings blob with no key. Now that `selectable` is all
  three, a blob naming `smart` or `off` must ROUND-TRIP rather than clamp
  (that is the behaviour change), while junk still degrades to `.manual`
  instead of failing the whole settings decode and resetting every preference.
- **224-1B — the floor, RED first.** In `.off`, a clean staged action creates
  with **no card**; a caution-tripping one creates **nothing** and returns an
  explanatory refusal. The refusal is a tool RESULT the model reads, so per
  #409 it carries an explicit do-not-claim clause, and per #233-E/#249-F every
  refusal this build can produce is **DIGIT-FREE** — asserted, not reviewed.
  RED witnessed before the change (the gate stages a card at HEAD for every
  mode, by construction).
- **224-1C — reads and permissions are untouched.** Two halves, because one is
  not enough. (i) **Structural, everywhere-scorable:** no read tool holds a
  `ToolConfirmationCenter` — `DeviceToolBelt.makeReadTools` cannot even accept
  one — pinned by reflection over the real read belt. (ii) **Resumption
  identity:** an auto-approve returns the SAME `.approved(values)` shape a
  user's approve returns, with the staged field values, so every downstream
  check — EventKit/AlarmKit authorization included — runs exactly as it does
  under `.manual`. A mode cannot bypass an OS permission because it never
  reaches one.
- **224-1D — the Privacy control.** Three rows in a new `// Agent Actions`
  section between `sensorStreamingSection` and `appLockSection` (ruling 6, as
  re-resolved above). (i) renders in EVERY theme including Paper Tape;
  (ii) **Off reads as `Design.Brand.forgeText`, never `dangerText`** — asserted
  on the colour the row resolves, not by review; (iii) VoiceOver labels state
  the CONSEQUENCE, not the mode name alone; (iv) the copy is honest about its
  blast radius — it claims the three agent-staged writes and explicitly does
  NOT claim the `/alarm` slash command, which is a second door with its own
  alert (`ChatScreen.swift`, #193/#16) and is the USER typing, not the agent
  acting. All four pinned by copy/colour tests, and the copy is production
  (#218 — no `#if DEBUG` strings).
- **224-1E — `GATE: PASS`** (units + XCUITest + **Release**), Swift Testing
  count MOVED, before/after recorded here.
- **224-1F — DEVICE (Owen, runbook card). PRE-REGISTERED AND UNRUN.** Scored
  only by a device sitting; nothing in this lane may claim it.

**PHASE 2 — Smart.**

- **224-2A — the one-line difference holds in test, RED first.** In `.smart`,
  clean actions auto-approve and caution-tripping ones **CARD** — not refuse.
  The discriminator is the same staged action run twice: `.smart` ⇒ card,
  `.off` ⇒ refusal. **(ii) The wee-hour threshold is NOT moved** — Phase 0's
  finding 1 asked Phase 2 to decide deliberately and in writing, and the
  decision is: a pre-07:00 alarm CARDS under Smart. The threshold is #233's,
  it was balloted, and moving it is a different decision than the one Owen
  elected. Pinned by a test naming `"6:30am"` explicitly, so the behaviour is
  a written choice rather than a discovery in use.
- **224-2B — the model-free pin EXTENDS 224-0F, and mutation-proves it.**
  Ruling 5: no `LanguageModelSession` is constructed on the approval path. The
  synchronous non-`async` half must still cover the widened decision path, the
  source scan's file list must still name every file this lane edits on that
  path, and a mutation (construct a session there) must red it.
- **224-2C — DEVICE (Owen, runbook card). PRE-REGISTERED AND UNRUN.**
- **224-2D — `GATE: PASS`, count moved.** Phases 1+2 ship in ONE PR, so ONE
  gate run scores both 224-1E and 224-2D. Stated here rather than discovered
  later: that is a deliberate merge, not a skipped bar.

> **KILL CLAUSE, written before the run:** if giving `.autoApprove` or
> `.refuse` a real path cannot be done without editing any tool's SUCCESS-claim
> text, or without weakening #323-D's lock-outranks-mode short-circuit,
> **stop and report** rather than proceeding. Both are defended surfaces
> balloted by other decisions.

> **OUT OF SCOPE, named so it is not discovered as a gap:** transcript receipts
> for auto-approved actions (ruling 7 — DEFERRED, Phase 3, build nothing of
> it; auto-approvals log to `os_log` per §3.7) · the host's `approvals.mode`,
> `approval.request`, and `POST /v1/runs/{id}/approval` (the design's own "not
> a phase") · the `/alarm` slash command's alert (224-1D(iv) makes the copy
> honest about it instead) · MCP (`design/MCP_CLIENT_DESIGN.md` routes through
> this same gate and stays Manual in its first version regardless).


**✅ PHASES 1+2 RAN — 2026-08-26, branch `t27-224-phases12-modes` off
`627ec37e`. 224-1A..1E and 224-2A..2B/2D MET; 224-1F and 224-2C are DEVICE
bars, pre-registered and UNRUN — nothing in this lane scores them.**

Result in one line: **the confirm gate has three modes now** — *Ask every time*
(default, unchanged behaviour), *Ask when unusual* (clean staged actions go
through, caution-tripping ones CARD), *Never ask* (clean ones go through,
caution-tripping ones are REFUSED by the floor) — chosen on the Privacy
screen, global on `UserSettings`, with no model anywhere on the path.

**THE PRIVACY ROW COPY, VERBATIM** (`ApprovalMode` + `PrivacySettingsScreen`,
production strings, pinned by test):

- Section header: `// Agent Actions`
- **Ask every time** — *"Every reminder, event, and alarm waits for your approval."*
- **Ask when unusual** — *"Goes ahead unless the action trips a caution — an early-morning hour, or a time that has already passed. Those still ask."*
- **Never ask** — *"Goes ahead without asking. An action that trips a caution is refused instead of created."*
- Section caption — *"Covers the reminders, calendar events, and alarms your agent stages on this phone. Reading your data always follows the permissions above, and an alarm you type yourself with /alarm always asks."*
- VoiceOver, per row (224-1D(iii) — the CONSEQUENCE, not the name):
  - *"Ask every time. Every reminder, event, and alarm waits for your approval."*
  - *"Ask when unusual. Actions go ahead without asking unless they trip a caution, and those still ask you first."*
  - *"Never ask. Actions go ahead without asking, and any that trip a caution are refused instead of created."*

**THE OFF-FLOOR REFUSAL, VERBATIM** (`ApprovalFloor`, one builder, three
callers). Template, with a real instance beneath it:

> `"<No X was created/scheduled.> Action confirmations are set to Never ask, and this request was flagged: <REASON>. This action was refused and did not run — do not tell the user it happened. Tell the user what was flagged and ask them to confirm what they meant, then try again with what they confirm."`
>
> *"No reminder was created. Action confirmations are set to Never ask, and this request was flagged: EARLY MORNING. This action was refused and did not run — do not tell the user it happened. Tell the user what was flagged and ask them to confirm what they meant, then try again with what they confirm."*
>
> Fail-safe form, for a flagged action whose tool supplied no text (reachable
> only from a direct `requestConfirmation` call; refusing rather than carding,
> because a card there would make Off secretly Manual for whichever tool
> forgot): *"Nothing was created. Action confirmations are set to Never ask,
> and this request was flagged as unusual. This action was refused and did not
> run — do not tell the user it happened. Tell the user what was flagged and
> ask them to confirm what they meant, then try again with what they confirm."*

**🔴 THIS STRING REACHES THE MODEL, so #409's do-not-claim precedent applies
and is HONOURED.** The floor's refusal is a tool RESULT — the model reads it
and speaks next — which is exactly the channel the 336-A forensics measured
answering a refusal with *"I've set the alarm for 6:30 AM"* **6/6**. The
sentence *"This action was refused and did not run — do not tell the user it
happened"* is `ApprovalFloor.doNotClaimClause`, one constant across all three
tools, pinned in test on its own literal rather than by referencing the
constant. **And it is DIGIT-FREE**, per #233-E/#249-F: the two Phase-0 caution
rows are digit-free already, so the calendar and alarm tools pass their row
straight through; the REMINDER's rows carry `displayDate`/`timeOnly`, so it
passes `dueCautionReason` — a digit-free twin derived from its own row rather
than restated — and the card keeps its dates untouched.
**Not user-facing:** nothing renders this string; it is model-facing only
(ruling 7 keeps receipts deferred, so an auto-approval and a refusal both log
to `os_log` and render no row).

**THE SMART RULE SET SHIPPED, enumerated.** Smart is `caution == nil ⇒
auto-approve, caution != nil ⇒ card`, and the caution layer is the ONE seam —
the same rows the card shows, not a parallel risk model. So the deterministic
rules that make an action "unusual" are exactly these five, all pre-existing
and unchanged by this lane:

| Tool | Rule | Row |
|---|---|---|
| `createReminder` | `isPastDue` (5-min grace, #249) | `IN THE PAST — <date>` |
| `createReminder` | `isEarlyMorning` (hours 0–6, #233) | `EARLY MORNING — <time>` |
| `createReminder` | `isNextMorning` (asked ≥17:00, lands 07:00–11:59 next day, #249) | `NEXT MORNING — <time>` |
| `createCalendarEvent` | `isPastDue` on the start (#224-0B) | `STARTS IN THE PAST` |
| `createCalendarEvent` | `isEarlyMorning` on the start (#224-0B) | `EARLY MORNING START — CHECK AM/PM` |
| `scheduleAlarm` | `isEarlyMorning` on the fixed time (#224-0A) | `EARLY MORNING — CHECK AM/PM` |
| `scheduleAlarm` | `isPastDue` on today's occurrence (#224-0A) | `ALREADY PASSED TODAY — RINGS TOMORROW` |

Countdowns trip nothing (always future, no clock hour to misread). **Zero
model calls, zero added latency, zero new failure mode** — ruling 5 holds by
construction, and 224-2B pins it.

**Bar by bar:**

- **224-1A — MET.** `.manual` on a fresh install (`UserSettings().approvalMode`)
  and on a blob that predates the key. The behaviour CHANGE is that a blob
  naming `off`/`smart` now round-trips instead of clamping — encode→decode
  included, because a decoder alone is half of a persisted pick. Junk still
  degrades to `.manual` without losing the rest of the blob. Tests:
  `defaultIsManualOnAFreshInstallAndOnABlobThatPredatesTheKey`,
  `aChosenModeRoundTripsNowThatAllThreeAreSelectable`,
  `junkStillDegradesToManualWithoutLosingTheRestOfTheBlob`,
  `allThreeModesAreSelectableInRenderOrder`.
- **224-1B — MET, RED witnessed first (see the RED block below).** Gate seam:
  `.off` + clean ⇒ `.approved(staged values)` with `pending == nil` throughout;
  `.off` + flagged ⇒ `.refused(text)`, no card, and `declineCount` does NOT
  move (a refusal is not a decline). Through the real tools:
  `offRefusesAWeeHourCalendarEventAndCreatesNothing`,
  `smartCardsTheWeeHourAlarmThatOffRefuses`,
  `offRefusesAWeeHourReminderWithADigitFreeReason` — the last calls
  `performCreate` TWICE on one relay, because #233's pre-gate bounce claims the
  first wee-hour due per conversation and the gate is only reachable after it
  (production behaviour, not a contrivance).
  `everyFloorRefusalCarriesTheClauseAndNothingMineable` sweeps all nine
  producible refusals for the clause, digit-freedom, the negative lead, and the
  setting's name.
- **224-1C — MET, in two halves.** (i) **Structural, scored everywhere:**
  `noReadToolHoldsTheConfirmationGate` reflects over the REAL read belt (12
  tools) and finds no `ToolConfirmationCenter` and no `ApprovalMode` — with a
  POSITIVE CONTROL asserting the same reflection DOES find the gate on all
  three action tools, because a reflection that cannot see a stored property
  would report a clean read belt for the wrong reason. (ii) **Resumption
  identity:** `anAutoApprovalIsByteIdenticalToAUserApprove` — an auto-approval
  hands the tool the same `.approved(values)` dictionary a user's tap hands it,
  so the tool resumes at exactly the point it resumes under `.manual`, which is
  UPSTREAM of every EventKit/AlarmKit authorization check. **No mode can bypass
  an OS permission because no mode ever reaches one.** Plus
  `theGateIsTheOnlyPlaceAModeIsConsulted` (sim-only, #332-a shape): a scan of
  all `Talaria/*.swift` finds `.disposition(hasCaution:` in exactly one file,
  with a positive control on the declaration site.
- **224-1D — MET, all four clauses.** (i) `offReadsAsForgeInEveryThemeAndNeverAsDanger`
  resolves the row tint for **every `ThemeID` × every `AccentSlot`** and
  asserts Off == `forgeText`, ≠ `dangerText`, Manual/Smart == `accentText`, and
  — the part that makes the claim meaningful — that `forgeText != dangerText`
  in each, Paper Tape included by name. **Honest scope: that is colour
  RESOLUTION across themes, not a pixel render.** The render itself is scored
  by a new XCUITest, `testPrivacyAgentActionsControlRendersAndSwitchesMode`,
  which opens Settings → Privacy, finds `settings.privacy.agentActions`,
  scrolls (bounded) to the rows, asserts a fresh install lands on *Ask every
  time*, taps *Never ask*, and asserts the selection moves. (ii) the role type
  `ApprovalModeAccentRole` has exactly two cases — **danger is not expressible
  on an approval row at all**, which is a compile error rather than a comment.
  (iii) VoiceOver labels pinned verbatim and asserted to be strictly longer
  than the mode name with a consequence in them. (iv) the caption is pinned
  verbatim and asserted to name the three writes, to disclaim reads, and to
  name `/alarm`. **Position:** `theControlSitsBetweenSensorSharingAndAppLock`
  reads `body`'s composition and pins the seven-section order — the only check
  that can see the ruling-6 placement, since a render test proves it exists and
  a copy test proves what it says, but neither notices it drifting to the
  bottom of the screen.
- **224-2A — MET.** `smartCardsTheVeryActionOffRefuses` (gate) and
  `smartCardsTheWeeHourAlarmThatOffRefuses` (real `AlarmTool`) run the
  IDENTICAL flagged action under both modes: Smart stages the card with its
  amber row and Off refuses with no card. The design's one-line difference —
  *Smart asks you about the unusual ones; Off refuses them* — holds in test.
  **(ii) The wee-hour threshold was NOT moved**, and that is a written decision
  rather than an inheritance: `theCanonicalMorningAlarmStillCardsUnderSmart`
  names `"6:30am"` explicitly and asserts the card. The threshold is #233's, it
  was balloted, and 224-0A's registered bar says "before 07:00 local" — a
  missed bar is a falsification and so is a quietly improved one.
- **224-2B — MET, EXTENDING 224-0F rather than duplicating it.**
  `everyPhase12ApprovalDecisionIsSynchronous` exercises every new decision
  surface (the widened `disposition`, `ApprovalFloor.refusal`, `accentRole`,
  `resolved`) from a **deliberately non-`async` body** — a
  `LanguageModelSession` turn is necessarily `await`ed, so putting the model
  there stops the file compiling. 224-0F's source scan was **extended** with
  the two files Phases 1+2 put on the path (`UserSettings.swift`,
  `PrivacySettingsScreen.swift`); its positive control is unchanged.
- **224-2D / 224-1E — MET.** One gate run scores both, deliberately: the two
  phases ship in one PR. See the gate block below.
- **224-1F, 224-2C — NOT RUN.** Device bars. The runbook card texts are
  verbatim below; nothing here may be read as scoring them.

**🔴 RED WITNESSED FIRST, and here is how.** The API had to exist for the tests
to COMPILE (a build error is not a RED — 224-0C's own rule), so the BEHAVIOUR
was reverted while the API stayed: `selectable` back to `[.manual]`, and the
gate's disposition `switch` back to consult-log-and-stage-anyway, which is
byte-for-byte what HEAD did. Verbatim
(`/private/tmp/.../scratchpad/224p12-red2.log`):

```
✘ Test run with 44 tests in 6 suites failed after 180.303 seconds with 37 issues.
```

**Fifteen tests RED**, and the set is the bars: `allThreeModesAreSelectableInRenderOrder`,
`aChosenModeRoundTripsNowThatAllThreeAreSelectable`,
`approvalModeExposesAllThreeAfterPhases12`,
`approvalModeResolvesEverySelectableModeToItself`,
`approvalModeIsAGlobalUserSettingsKeyDefaultingToManual` (224-1A) ·
`offAutoApprovesACleanActionAndNeverStagesACard`,
`smartAutoApprovesACleanActionToo`, `anAutoApprovalIsByteIdenticalToAUserApprove`,
`offRefusesAFlaggedActionInsteadOfCardingOrDeclining`,
`aFlaggedActionWithNoFloorTextIsStillRefused`,
`offRefusesAWeeHourCalendarEventAndCreatesNothing`,
`offRefusesAWeeHourReminderWithADigitFreeReason`,
`noModeSilentlyCreatesAFlaggedAction` (224-1B/1C) ·
`smartCardsTheVeryActionOffRefuses`, `smartCardsTheWeeHourAlarmThatOffRefuses`
(224-2A). The copy, colour, position, read-isolation and model-free bars stayed
GREEN under the revert — **that is the control**: they say the failures came
from the missing behaviour, not from a broken harness.

> **⚠️ AND THE FIRST RED ATTEMPT HUNG THE SUITE — Phase 0's finding 3, again,
> in a test written to catch a mutation.** `noModeSilentlyCreatesAFlaggedAction`
> awaited `task.value` unconditionally on its `.off` arm, which is correct when
> the floor returns immediately and is a **permanent hang** under any build
> where `.off` stages a card instead — i.e. under exactly the mutation the test
> exists to catch. It had to be killed by hand. The fix watches for EITHER a
> staged card or a settled decision on a wall-clock deadline and cleans up
> whichever happened; the re-run completed in 180 s with no hang. **The general
> form is worth the next reader's time: a mutation-testable test that awaits
> the code under test unconditionally is a test that cannot survive its own
> mutation.**

**THE GATE — 224-1E and 224-2D together. Verbatim** (logs in
`/var/folders/…/talaria-gate.0ZPxOK1ZKh`):

```
  PASS  runtime: iOS 27.0 (24A5423a) on "CC-lane-2"
  PASS  Test run reported TEST SUCCEEDED
  PASS  Swift Testing tests run — 2721
  PASS  XCUITest tests run — 15
  PASS  Release build succeeded
  PASS  no Swift compile errors in Release
GATE: PASS on 24A5423a
```

**Counts MOVED, and the delta is exact: +28 Swift Testing (2693 → 2721) and
+1 XCUITest (14 → 15).** The 28 are 27 in the new `ApprovalModesPhase12Tests`
plus `anInstrumentRunPinsTheApprovalModeToManualAndRestoresIt`; the XCUITest is
`testPrivacyAgentActionsControlRendersAndSwitchesMode`. The Phase-0 edits are
renames and rewrites, so they contribute zero. **No new SKIPs** — the two
sim-only bars run on the simulator, which is where the gate runs.

> **⚠️ THREE GATE RUNS, and honesty about all three rather than reporting the
> green one. Both non-green runs are recorded, per the standing rule.**
> - **Run 1 (`…F7WnjMCJoK`) — FAIL, one real test.** Swift Testing **2721** with
>   a single issue: `HostApprovalModeTests.theHostStateIsADistinctTypeFromTheOnDeviceGate`,
>   the 224-APP pin described in finding 4. A genuine catch, fixed in
>   `26b3781d`. **Killed by hand mid-XCUITest** once the cause was clear.
> - **Run 2 (`…tqkE4tdfwz`) — FAIL, and NOT a product failure: #219's
>   runner-death family.** No Swift Testing count line at all, XCUITest 8, and
>   **no assertion locus anywhere in the log** — six tests listed as failing,
>   none of them ours, none with an issue recorded. Logged against #219 as
>   occurrence 2 with its measured context.
> - **Run 3 (`…0ZPxOK1ZKh`) — PASS, first try, quoted above.** Nothing changed
>   between runs 2 and 3 except shutting `CC-lane-2` down and the host load
>   falling (1-min average **53.7 → 5.6**).

**MUTATIONS — three, each ISOLATING. Every one was built and run; none is a
thought experiment.**

- **M1 — DROP THE FLOOR** (`.refuse` returns `.approved(staged values)`
  instead of `.refused`). **6 tests RED, and every one of them is an
  Off-floor pin:** `offRefusesAFlaggedActionInsteadOfCardingOrDeclining`,
  `aFlaggedActionWithNoFloorTextIsStillRefused`,
  `offRefusesAWeeHourCalendarEventAndCreatesNothing`,
  `offRefusesAWeeHourReminderWithADigitFreeReason`,
  `noModeSilentlyCreatesAFlaggedAction`, plus the Off arm of both
  Smart-vs-Off discriminators. **Every Smart-only, copy, colour, position,
  read-isolation and model-free bar stayed GREEN.**
- **M2 — MAKE SMART REFUSE INSTEAD OF CARD** (`.smart: hasCaution ? .refuse
  : .autoApprove`). **5 tests RED, and every one of them is a Smart
  discriminator:** `smartCardsTheVeryActionOffRefuses`,
  `smartCardsTheWeeHourAlarmThatOffRefuses`,
  `dispositionTableMatchesTheBallotedPolicy`,
  `theCanonicalMorningAlarmStillCardsUnderSmart`,
  `anEveningAskForTomorrowsAlarmAlsoCardsUnderSmart`. **Every Off-floor test
  stayed GREEN** — which is the point: the two modes' pins do not overlap, so
  *"Smart asks, Off refuses"* is measured rather than asserted.
- **M3 — CONSTRUCT A `LanguageModelSession` ON THE APPROVAL PATH** (a real
  one, with `Instructions`, inside `requestConfirmation`). **RED, on 224-0F's
  source scan** (`approvalPathSourcesNeverReferenceALanguageModelSession`) —
  ruling 5's structural guarantee, still firing after this lane widened the
  file list it covers.

**Findings the bars did not anticipate — three, and the first is the largest:**

1. **🟡 AN EVENING-SET MORNING ALARM CARDS UNDER SMART AND IS REFUSED UNDER
   OFF, and this lane did NOT fix it.** Phase 0's finding 1 named the wee-hour
   rule (hours 0–6). It did not name #249's past-due rule, which under Smart
   bites much harder: *"set an alarm for 7am"* asked at 9 PM has already passed
   TODAY, so `AlarmTool.caution` stages `ALREADY PASSED TODAY — RINGS
   TOMORROW`, and *caution ⇒ card*. Setting tomorrow's morning alarm in the
   evening is close to the most common thing anyone does with an alarm, so in
   practice a large share of alarms card under *Ask when unusual* and are
   REFUSED under *Never ask*. **Found by this lane's own test, not by
   inspection** (the clean-contrast case failed). **Left as-is deliberately:**
   the registered bar is *caution ⇒ card*, one seam and no second risk model,
   and carving an exception for one rule mid-lane would be a redefinition of a
   bar rather than a fix. The alarm DOES ring, correctly, tomorrow — so the
   honest question is whether that row should count as a caution under
   Smart/Off at all, and that is a written decision with device evidence
   behind it. Pinned as a NAMED behaviour by
   `anEveningAskForTomorrowsAlarmAlsoCardsUnderSmart`; runbook card 224-2C
   asks Owen to report the friction directly. **The one-line change, if it is
   ever elected:** give the alarm's past-due row a disposition of its own, or
   drop it from the Smart/Off discriminator while keeping it on the Manual
   card.
2. **The copy had to be rewritten because of finding 1.** A first draft read
   *"Approves ordinary ones"*; an evening 7 AM alarm is about as ordinary as an
   alarm gets, so that was a claim the code does not keep. Both rows now name
   the DISCRIMINATOR — *"trips a caution"* — which is literally what the gate
   reads, so the copy cannot drift from the behaviour without the behaviour
   changing. A test bans the word "ordinary" from those two rows and requires
   the phrase, so the reasoning survives the next copy edit.
3. **🔴 AN INSTRUMENT RUN WOULD HAVE INHERITED THE USER'S MODE — fixed here,
   one line plus its restore.** The battery flags short-circuit ahead of the
   mode read, so `.autoAccept` / `.autoDecline` instruments were never at risk.
   But `confirmationMode: .none` instruments (`read-tool`, `router-probe`) arm
   NEITHER — and those are precisely the cells where the #200-series measured
   the model GRABBING an action tool. On a phone set to *Never ask*, such a
   grab would have stopped staging an unanswerable card and started writing a
   real reminder to Owen's real list, unattended: exactly the containment #331
   was ruled to protect. It is also a measurement fact — a rate would have
   silently acquired a fourth hidden axis on top of #215's routing, #343's
   governor and #398-A's runtime. **`InstrumentConductor` now pins the gate to
   `.manual` for the duration of every run and restores the user's provider in
   the same `defer` as the flags**, pinned by
   `anInstrumentRunPinsTheApprovalModeToManualAndRestoresIt` — scored on a
   `.none` spec, the only shape that reaches the hazard. **Consequence worth
   stating: no archive rate is affected, and none needs annotating.**

4. **A FOURTH pin lived in another lane's suite, and only the GATE found it.**
   `HostApprovalModeTests.theHostStateIsADistinctTypeFromTheOnDeviceGate`
   (224-APP-C) asserted `ApprovalMode.selectable == [.manual]` from the HOST
   lane's file, as shorthand for "the host lane did not touch the on-device
   enum." True of that lane; false the moment this one widened `selectable` on
   Owen's election. **Eleven targeted suites were run before the gate and none
   of them was this one** — the pin READ a symbol it did not own, so no
   ownership-based selection could find it. Repointed onto the claim
   224-APP-C actually makes (distinct TYPE, raw wire strings, nothing
   converts, a host reporting `off` does not move this phone's default), which
   is stronger than a literal borrowed from another lane. **Generalisable, and
   cheap: before widening a shared constant, grep for every test that READS
   it, not just the suite that owns it** — the pre-gate checklist's count-pin
   rule, one level out.

**Two behaviours named so they are not discovered as gaps:**

- **The reminder tool's #233/#249 pre-gate BOUNCES still fire under every
  mode**, once per conversation, upstream of the gate. So under *Never ask* a
  first wee-hour reminder still produces an agent question — the agent asking,
  not a card. That is the bounce doing its job, not the mode leaking.
- **The `/alarm` slash command is untouched** and still shows its own alert
  (#16/#193). It is the USER typing a command, not the agent acting, and the
  gate exists to stop the MODEL writing silently — so the modes deliberately do
  not govern it, and the section caption says so in words rather than leaving
  the user to find out by being asked.

**RUNBOOK CARD TEXTS — pre-registered, UNRUN. Verbatim, for the runbook
artifact:**

> **`#224-1F · Agent Actions — Never ask, and its floor`**
>
> **Build:** any build carrying #224 Phases 1+2 (Settings → Privacy shows a
> `// Agent Actions` section with three rows).
> **Setup:** Privacy → `// Agent Actions` → tap **Never ask**. Leave the app,
> come back, reopen the screen — the pick must still be Never ask, and it must
> NOT change when you switch host profiles (it is global by ruling 2).
> 1. **Clean action, no card.** In chat: *"remind me to take out the bins at
>    6pm"* (any time still ahead today). **PASS:** the reminder is created with
>    NO confirmation card, and it is really in the Reminders app.
> 2. **The floor refuses.** In chat: *"set an alarm for 4am"*. **PASS:**
>    nothing is scheduled, no card appears, and the agent tells you it was
>    flagged as early morning and asks what you meant. **FAIL if:** an alarm
>    appears in the Clock app, or a card appears (a card here would mean Never
>    ask is secretly Ask-when-unusual).
> 3. **The claim check (#409).** Read the agent's step-2 reply word by word.
>    **FAIL if it says the alarm was set, scheduled, or created in any form.**
>    The refusal carries an explicit do-not-claim clause and this is the only
>    place its effect on a real model can be seen.
> 4. **Back to safety.** Set the mode to **Ask every time** and repeat step 2 —
>    the card must return, with its amber `EARLY MORNING — CHECK AM/PM` row.
> **Report:** the mode you were on, what appeared (card / artifact / neither),
> and the agent's exact words for step 2.

> **`#224-2C · Agent Actions — Ask when unusual`**
>
> **Setup:** Privacy → `// Agent Actions` → **Ask when unusual**.
> 1. **Ordinary actions go through.** Three in a row, no taps expected:
>    *"remind me to call the dentist at 3pm"*, *"put lunch with Sam on my
>    calendar tomorrow at noon"*, *"set a 20 minute timer"*. **PASS:** all
>    three created with NO card, and each artifact really exists in Reminders /
>    Calendar / Clock.
> 2. **The unusual one still asks.** *"set an alarm for 4am"*. **PASS:** a card
>    appears carrying the amber `EARLY MORNING — CHECK AM/PM` row. Decline it —
>    nothing is scheduled.
> 3. **The known cost, and it is EXPECTED, not a bug.** *"set an alarm for
>    6:30am"*, and then — in the evening — *"set an alarm for 7am"*. **A card
>    is expected for both**: #233's wee-hour rule covers midnight–06:59, and
>    #249's past-due rule fires on any morning time already gone today. This
>    lane decided in writing not to move either threshold. **Report how it
>    FEELS.** If being asked about your ordinary morning alarm is annoying in
>    real use, that is the evidence for a future written decision, and it can
>    only come from you.
> 4. **Contrast against #224-1F.** The same 4 AM ask under *Never ask* is
>    refused, not carded. If both modes behave the same way, one of them is
>    wrong.
> **Report:** counts for step 1 (cards seen / artifacts created out of 3), what
> steps 2 and 3 did, and your read on step 3's friction.

**Upstream corrections made in this commit** (close-out rule): the design of
record gains a dated *"Phases 1+2 landed"* banner plus two in-place
supersessions (§2's *"One always-on Manual gate, no user-facing mode"* and the
Phase-0 note that said the mode was deliberately not user-visible) ·
`dispatch/DEVICE-PASS-RUNNING-LIST.md` §F7's *"There is no user-facing
auto-approve"* is struck and replaced, with the consequence for anyone running
that section spelled out ("no card appeared" now has two causes) · this entry's
own *"What we have … no user-facing mode at all"* paragraph and its index line
· 224-0E's prediction block, which FIRED and now points at the new test names ·
224-APP-C's parenthetical, whose cited test name changed · a stale comment in
`HostApprovalModeTests` · and `ToolConfirmationCenter`'s #323-D note, which
said `.manual` was the only mode settings could produce — that anticipatory
guard is now load-bearing and says so.

## 303. 🐛 `VoiceEngineRouter` has no UPGRADE path — a cold Control Center voice launch pins the NATIVE engine even when the brain permits realtime, because the engine is chosen from a brain value that changes 35 ms later — **FILED 2026-08-09 from #254's device logs. MASKED on the host it was found on, so its user-visible cost is UNMEASURED. NOT STARTED; bars pre-register here before any code. ⟵ PREMISE RE-VERIFIED LIVE AT HEAD 2026-08-25 (Sonnet agent): the asymmetric gate survives exactly as filed (#221 built it this way; #383 only renamed the pairing predicate; a passing regression test PINS the cold-launch pin as current behavior, `RealtimeVoiceIndicatorTests.swift:193`). The runbook's #303-A/B card remains the right instrument and has never run — measurement first, fix election after.**

> **📋 DISPATCH FILED 2026-08-10: `dispatch/FABLE-T27-voice-triage-301-302-303.md` (Lane 2).** 303-A/B ride the OJAMD sitting (realtime-configured host — see the OJAMD handoff §11); no fix before 303-A runs.

**The asymmetry, from source.** `startSession()` carries an explicit
*"last line of defence"* re-check (`VoiceEngineRouter.swift:238`) —
but it fires in **one direction only**:

```swift
if activeEngine == .realtime, !Self.realtimeIsPermitted(for: activeBrain()) {
    // downgrade realtime → native
}
```

There is **no matching upgrade**. If `activeEngine` is already `.native` — the
value `init` assigned from `(realtimeIsPermitted(for: activeBrain()) &&
isRelayPaired())` — nothing re-evaluates it before the session starts, no matter
what the brain says by then.

**Why that matters on a cold launch, measured on build 2330:**
```
14:00:22.780  active voice engine → native (initial; relayPaired=true)
14:00:22.815  activeBrain on-device → hermes  initiator=refresh/sticky-default
14:00:23.098  OpenHermesVoiceIntent.perform fired in the APP process — routing hermes://voice
14:00:23.113  voice session starting on engine native (relayPaired=true)
```
`init` read the brain **35 ms before** the sticky-default restored `hermes`, and
the session started **283 ms after** that restore — still native. No
`refreshReadiness` line appears for that process, so nothing re-routed in
between.

**⚠️ THE COST IS UNMEASURED, AND THE ENTRY MUST NOT PRETEND OTHERWISE.** On the
host this was found on, `talk/readiness` reports `configured:false`, so
`shouldRouteNative` would have selected native **anyway**. Every observable
consequence is therefore identical to correct behaviour here. **This is a
code-path defect visible in the log ordering, not a demonstrated user-visible
one** — it needs a host where realtime IS configured before anyone can say what
it actually costs.

**Two readings, and the entry does not pick between them:**
- **It is a fail-safe, arguably deliberate.** The guarded direction is the
  dangerous one (#221: never let a stale decision ship microphone audio to
  OpenAI when the user chose on-device). Failing toward the local engine is the
  private direction, and the asymmetry may be intentional.
- **It is still wrong for the user who chose Hermes**, who gets the local engine
  on every cold Control Center launch without having asked for it. Note this is
  **not a silent substitution** in the #18 sense — `forward(from:engine:)` stamps
  the real engine, so the overlay header names `native` honestly. The defect is
  functional, not a lie: the setting is obeyed by chat and not by a cold voice
  launch.

**Bars, pre-registered before any code:**
- **303-A — reproduce on a host where realtime IS configured.** Hermes brain,
  paired, realtime available, cold Control Center launch. **PASS = the session
  starts on `realtime`; a start on `native` confirms the defect.** Until this
  runs, everything above is an ordering observation.
- **303-B — the warm path is the CONTRAST and must be run in the same
  sitting.** Open voice from inside the app (which does run `refreshReadiness`)
  under the identical configuration. If warm reaches realtime and cold does not,
  that difference *is* the defect, isolated.
- **303-C — any fix keeps #221's gate un-weakened.** The downgrade direction
  must still fire; an "upgrade" that lets pairing or a healthy probe re-admit
  realtime against a forbidding brain re-introduces the exact defect #221 closed.
  **A fix that makes 303-A pass by loosening the gate is a FAILURE, not a pass.**

**Pre-registered response:** if 303-A shows realtime starting correctly on a
configured host, this closes as **NOT A DEFECT** — the init guess would have
been right whenever it mattered — and the log ordering gets documented so the
next reader does not re-file it.

**Related:** #221 (brain governs voice — the gate this must not weaken), #254
(the run that surfaced it), #180-L (the overlay's engine copy), #18 (no silent
local substitution — cited here to note this is *not* an instance of it).

> **📝 EXECUTION NOTE 2026-08-10 (voice-triage lane, Lane 2 — code read only,
> per the dispatch's stop-gate: NO FIX BUILT before 303-A runs).**
>
> **Source re-verified at HEAD (`d004c82`):** the `:238` one-direction
> re-check is confirmed verbatim — `if activeEngine == .realtime,
> !Self.realtimeIsPermitted(for: activeBrain())` is at exactly line 238, and
> `startSession()` contains no upgrade branch. Three sharpenings from the read:
>
> 1. **The upgrade direction already EXISTS in the router — in
>    `refreshReadiness()`** (`setActive(.realtime)`, line 217, after brain
>    gate → pairing → probe). The defect is precisely that the cold Control
>    Center path reaches `startSession()` with no `refreshReadiness()` in
>    between (the entry's log shows none). So any fix is "make the cold start
>    consult the decision that already exists," not "invent an upgrade."
> 2. **Fix-shape constraint, recorded here because this is where the fix will
>    be built (303-C):** a startSession-entry re-route evaluates BOTH
>    directions from the CURRENT brain; the downgrade branch at `:238` stays
>    first and untouched; the upgrade check must be conjunctive —
>    `realtimeIsPermitted(for: activeBrain()) && isRelayPaired()` — so
>    pairing or a healthy probe can never re-admit realtime against a
>    forbidding brain. That keeps #221's gate provably un-weakened. An
>    upgraded cold start then flows into the existing #247 B1 belt (12 s) +
>    `shouldFallBackToNative`, so an unconfigured/unreachable realtime
>    self-heals to native for that session.
> 3. **A cost asymmetry the fix design must weigh (this is 303-C design
>    space, parked with it):** `startSession()` consults only brain+pairing —
>    no readiness probe — so an attempt-first upgrade would send a cold CC
>    launch on a paired-but-unconfigured host (the Mac Mini shape,
>    `configured:false`) into a doomed realtime bootstrap, up to the 12 s
>    belt, before falling back — where today it starts native in ~23 ms.
>    Probe-first instead adds probe latency to every cold start. Neither is
>    obviously right; 303-A's result decides whether the question is even
>    live.
>
> **#320 cross-reference (not built here):** `forward(from:engine:)` stamps
> the engine that actually PRODUCED each snapshot, and the router's
> `snapshot` property is deliberately unstamped (`:170`) — so an indicator
> built on snapshots tracks the engine that actually starts, which is #320's
> requirement. If this item's fix changes cold-start routing, #320's lane
> must re-verify against the post-fix routing.
>
> **303-A/B remain PARKED on the OJAMD sitting** (realtime-configured host —
> `handoffs/HANDOFF-2026-08-09-OJAMD-SESSION.md` §11 pairs it with R6/#138).
> Until 303-A runs, the fail-safe reading stays live and nothing above is a
> defect confirmation.

> **2026-08-18 ballot:** the realtime key is configured on BOTH hosts now
> (Owen), so 303-A/B are runnable; #320's shipped indicator is the free
> instrument for reading the engine off-screen. Queued with #254-D.

## 302. 🐛 A voice session STARTS ~650 ms before App Lock evaluates its cover — a Control Center voice launch begins on a LOCKED app — **🚨 DETERMINED 2026-08-10 ON DEVICE: THE MICROPHONE IS LIVE BEHIND THE LOCK. 302-A/B FAILED (bar 302-B RED, two independent reproductions; 302-A "passed" by a 470 ms race, not by a gate). The ruled 302-C contract (defer-until-unlock) is VIOLATED. ~~FIX OWED — not built; the fix is a design change and rides Owen's go.~~ → ✅ FIX BUILT 2026-08-20, on the 2026-08-18 ruling. Bars 302-D…G MET, each proven RED by mutation — see the RESULT block below. ~~**PR #329 OPEN**~~ **✅ PR #329 MERGED 2026-08-21 as `2767ca70` (marker corrected 2026-08-23 by the Opus-week audit — it sat stale through the header sweep because the checker's regex could not see this spelling; the regex is widened in the same commit)** (GATE: PASS, 2383/14/Release). DEVICE VERIFICATION OWED.** ~~FILED 2026-08-09 from #254's device logs, OBSERVED IN PASSING. Whether the microphone is ever LIVE behind the lock is UNDETERMINED and is still the whole question.~~ **⟵ HEADER CORRECTED 2026-08-23 (stale-header sweep): the GATE IS BUILT — 302-D…G all met 2026-08-20, each mutation-proven. Device closing bars owed.**

> **🔴 SUPERSESSION 2026-08-26 — THIS DEFECT IS BACK ON DEVICE, AND THE
> BARS CANNOT SEE IT. Filed here, in its own home, by #415's log forensics
> (`whoGoesThere-415.logarchive`, build 3108); the full per-launch timeline
> and the cited rows live in #415's 📏 FORENSICS block.**
>
> **What recurred:** the microphone was hot **27.4 s** and **13.4 s** on two
> consecutive Control Center voice launches, **24.3 s and 10.3 s of that behind
> `cover=locked`**, with a full realtime conversation running under an opaque
> App Lock cover. The user cancelled Face ID on both, exactly the 302-B arm.
>
> **Why the fix did not prevent it, and why no bar caught it.**
> `TalkStore.deferUntilUnlocked` samples `AppLockGate.isLocked` **once**, at the
> instant of start. `AppLockStateMachine` computes `cover == .locked` only on the
> transition INTO `.active`; any other phase is `.obscured`, which 302-D
> deliberately does not lock on. A Control Center tap runs its intent **in the app
> process** during the `background → inactive` window that precedes that
> transition — so on a WARM process the gate is measurably **open for 1.2 s after
> the tap**, the start clears it in 23–25 ms, and the cover arms on top of an
> in-flight start. Mic went hot **272 ms** and **2.4 s AFTER `locked=true`**.
> **Bars 302-D…G all place the lock BEFORE the start** (302-E's evidence shape is
> "gate locked ⇒ start count stays 0"); **none scores "gate open at start, lock
> arms mid-flight."** The fix closed the arm the bars measured and left open the
> ordering **this item's own title names** — *"STARTS ~650 ms before App Lock
> evaluates its cover."*
>
> **And the 2026-08-20 device pass was run on the wrong engine to see it.** The
> `#302-A` capture-chain instrument exists only in `NativeVoicePipelineService`
> (`:1006`/`:1040`/`:1173`). `LiveVoiceSessionService` — realtime, the engine all
> three #415 launches routed — emits **no capture hot/cold line at all**, so on
> realtime the app's own log cannot answer "was the mic hot?". #415's forensics
> had to read CoreAudio `AURemoteIO` rows instead.
>
> **Owed:** a mid-flight re-arm bar (#415's 415-A, which must be proven RED on
> today's `main` before any fix), its App-Lock-OFF negative control (415-B), the
> realtime instrument (415-C), and a device re-run that HOLDS the cover open
> (415-D). Until 415-A exists, "302-D…G MET" describes a gate that is real and a
> race that is not covered.
>
> **✅ 2026-08-26 night, SAME DAY — THE BLIND ORDERING IS NOW COVERED. The
> three unit owings above are BUILT and MET; only the device re-run is left.**
> `TalariaTests/AppLockMidFlightCoverTests.swift` (10 tests) holds 415-A's pin:
> gate OPEN at start, cover arms mid-flight, capture must stop and the session
> must park — **witnessed RED on the unmodified tree first (8 tests, 21
> issues)**, then green, then proven by three isolating mutations. The fix is a
> **cover watch** on `TalkStore` waiting on a new `AppLockGate.waitUntilLocked()`
> — the mirror of the suspension point *this* item's fix already uses, so
> `refreshCover()` is still the gate's only writer and no second observer
> exists. **The park semantics are 302-C's contract extended, not replaced:**
> stop capture with the existing teardown, park on the same
> `isWaitingForUnlock` + `lockedWaitingMessage` state, resume exactly once on
> unlock, never resume an abandoned one (302-F's rule through the new door).
> `parkedWaiterCount` still counts UNLOCK waiters only, deliberately — 302-E
> and 302-G are written against that number and it means what it meant.
> 415-C closed the instrument half: `LiveVoiceSessionService` now carries the
> `#302-A` capture lines, so **the engine that carried all three #415 launches
> can finally answer "was the mic hot?" in the app's own log** — the reason the
> 2026-08-20 device pass here could not see this. **Still owed on THIS item:
> nothing new; its own device verification and #415-D are the same
> measurement, and #415-D's card is written.** Full result block, bar table,
> mutations and the verbatim lines: **#415**.

> **⚖️ 302-C RULED 2026-08-10 (Owen, on the wave-1 close-out): the contract
> is DEFER-UNTIL-UNLOCK, and it is today's felt flow.** His words: *"Today, if
> you press the control center button, it unlocks and launches the app."* So:
> the launch is ACCEPTED, the unlock prompt is part of the flow, and the voice
> session proceeds only after unlock resolves — which means **the capture
> chain must be provably COLD until unlock succeeds.** 302-A/B (the instrument
> shipped in PR #300) now measure COMPLIANCE with a stated contract rather
> than informing a choice: cold in both arms ⇒ the ordering is benign and the
> item closes as NOT A DEFECT with the contract on record; hot in either ⇒ a
> defect against this ruling, and the fix defers session start behind the
> unlock. The cancelled-unlock arm (302-B, fixture updated post-#272) is the
> one that can still surprise.

> **📋 DISPATCH FILED 2026-08-10: `dispatch/FABLE-T27-voice-triage-301-302-303.md` (Lane 1 = this item, runs FIRST).** Note recorded there: bar 302-B's "trivially arranged while #272 is unfixed" fixture is STALE — #272 closed 2026-08-09; the locked interval is now held open via the fixed Cancel-then-UNLOCK-button state.

### 🚨 RESULT 2026-08-10 — RUN ON DEVICE, BAR 302-B **FAILED**. THE MICROPHONE IS LIVE BEHIND APP LOCK, AND 302-A's PASS IS A RACE.

**Owen ran device row §V1 on `whoGoesThere` (iPhone 17 Pro Max, iOS 27.0),
build 2484 (`main` @ `75e5e08`, Release OTA — the production build, chosen
over a Debug install precisely because this bar is a timing question).
Setup as pre-registered: App Lock ON / grace Immediately, brain On-Device,
network up. Evidence: `log collect --device-udid` archive, 439 app-subsystem
lines, mined across BOTH subsystems per §V's warning.** Owen's own words
before any log was read: *"On the lock screen, it can hear me. and respond.
When I unlocked, it had everything we discussed there."* The log agrees, to
the millisecond.

**The engine is `native` in every episode — no trial is VOID.**

**302-B — 🛑 FAILED. Verbatim, arm (b):**
```
19:30:46.426  VoiceEngineRouter    voice session starting on engine native (relayPaired=true)
19:30:46.535  NativeVoiceCapture   audio session activated for capture (#302-A)
19:30:47.010  AppLock              scenePhase background -> active | pre: cover=locked locked=true
19:30:47.038  AppLock              requestUnlock ENTER attempt=1
19:30:47.212  NativeVoiceCapture   capture chain HOT — AVAudioEngine.isRunning=true inputTap=installed (#302-A)
19:30:51.086  AppLock              requestUnlock EXIT attempt=1 result=FAILED_OR_CANCELLED didFail=true
19:31:22.131  AppLock              requestUnlock EXIT attempt=2 result=SUCCESS (episode ends, counter reset)
19:31:36.543  NativeVoiceCapture   capture chain COLD — AVAudioEngine.isRunning was=true now=false
```
**The microphone was HOT for 34.92 s while `cover=locked locked=true`** —
and it went hot **3.87 s BEFORE the user cancelled** the biometric, so the
cancel is not what opened the window; the window was already open.

**302-A — GREEN, and the number says why that is worthless as reassurance:**
```
19:29:23.741  voice session starting on engine native
19:29:23.899  audio session activated for capture (#302-A)     ← already cover=locked
19:29:24.322  requestUnlock ENTER attempt=1
19:29:24.930  requestUnlock EXIT attempt=1 result=SUCCESS       ← Face ID took 608 ms
19:29:25.400  capture chain HOT                                 ← 470 ms LATER
```
**Nothing deferred the capture chain. Face ID simply won a footrace by
470 ms.** The audio engine needed ~1.66 s from session start; the unlock
happened to resolve in ~1.19 s. A slower Face ID, a colder start, a second
attempt — any of these flips 302-A red too. **Recording 302-A as "PASS" without
this sentence would be the most misleading true statement in the tracker.**

**A SECOND, UNPLANNED REPRODUCTION in the same corpus (episode 3, 19:31:40),
and it is worse:**
```
19:31:40.799  capture chain HOT — isRunning=true inputTap=installed
19:31:41.619  AppLock  requestUnlock ENTER attempt=1        ← 820 ms AFTER the mic went hot
19:31:45.791  AppLock  requestUnlock EXIT result=FAILED_OR_CANCELLED
19:32:11.853  AppLock  requestUnlock EXIT attempt=2 result=SUCCESS
```
Here the microphone was live **before App Lock began evaluating at all**, and
stayed live across another cancel and a ~31 s hold. Two independent
reproductions, one run.

**MECHANISM — read, not inferred. App Lock is a UI COVER and nothing else.**
`AppLockWindowPresenter` (`AppLockOverlayView.swift:17-44`) presents an
opaque `UIWindow` above every presentation layer — its own doc comment says
so, and that design was correct for what it was solving (#124's sheets/alerts
hole). **But no non-UI subsystem consults lock state.** *(True as measured on
2026-08-10 and FIXED on 2026-08-20 — `AppLockGate` is now consulted by
`TalkStore`, `ChatStore` and `ToolConfirmationCenter`. The sentence stands as
the finding it was; read it in the past tense.)* A recursive grep of
the voice path finds the string `AppLock` in `NativeVoicePipelineService`
**only inside comments** about correlating log lines (`:997`, `:1166`), and
not at all in `VoiceEngineRouter`. There is no gate to be late — there is no
gate. `scenePhase` goes `.active` while `cover=locked`, and everything keyed
on `.active` proceeds.

**Consequence, stated plainly:** anyone holding the phone can reach Control
Center → "Talk to Hermes" → cancel Face ID → and hold a working conversation
with an assistant that has tool access, with the turns committing to the
transcript. **App Lock's entire purpose is to prevent that.**

**FIX NOT BUILT.** The row's instruction is stop-and-file, and the fix
("defer session start behind the unlock") is a design change to the Control
Center flow Owen described as his felt flow — it needs his go and its own
bars. **Bars pre-register here before any code**, and the fix's bar must
close the RACE, not the arm: a green 302-A that still depends on Face ID
winning is not a fix.

**Scope note:** the locked-interval evidence also shows a full inference turn
and the whole sensor pipeline running behind the cover. That is broader than
this item's microphone question and is filed separately as **#323** rather
than absorbed here.

**Observed** on build 2330 (`main` @ `6b71872`, Release OTA), `whoGoesThere`,
iOS 27.0, while running #254's native arm. App Lock was enabled with grace
`Immediately`; the launch came from Control Center → "Talk to Hermes" on a
force-quit app. Both trials show the same ordering:

```
13:20:52.983  [controls] OpenHermesVoiceIntent.perform fired in the APP process — routing hermes://voice
13:20:53.006  [VoiceEngineRouter] voice session starting on engine native (relayPaired=true)
13:20:53.109  [NativeVoicePipeline] audio deactivated by app — not an interruption (#198)
13:20:53.659  [AppLock] scenePhase background -> active | pre: cover=locked locked=true
13:20:54.165  [AppLock] requestUnlock EXIT attempt=1 result=SUCCESS
```

**The voice session's start is logged ~653 ms BEFORE the lock controller sees
`.active` at all, and ~1.16 s before the unlock succeeds.** The second trial
(PID 15143, 13:32:24.984 vs 13:32:26.203) reproduces the same ordering with the
same sign, so it is not a one-off scheduling artifact.

**What is NOT established, and this is the entire reason the item exists as a
question rather than a finding.** The `audio deactivated by app` line 103 ms
after the start suggests the capture chain does **not** stay up behind the lock
cover — that reading is *consistent* with the logs and is **not proven by
them**. Nothing here distinguishes:
- **(a)** the session starting, immediately deactivating audio, and waiting for
  the unlock — benign, and what the deactivate line hints at; from
- **(b)** a microphone that is briefly live while the app is locked — a real
  privacy defect, and exactly the class of thing App Lock exists to prevent;
  from
- **(c)** an ordering that is benign today only because the unlock happened to
  succeed in ~500 ms. **A CANCELLED unlock is the untested case** — and per
  **#272**, a cancelled unlock currently loops indefinitely, so the "locked"
  interval is unbounded in practice. **#272 and this item compose**, and neither
  entry's evidence was taken with the other in mind.

**Do not read the `#198` deactivate line as an answer.** It is emitted by BOTH
pipelines on every audio-session teardown and appears throughout these logs in
contexts that have nothing to do with the lock; treating it as proof the mic was
never hot would be reading a general-purpose line as a specific guarantee.

**Bars, pre-registered before any code:**
- **302-A — the mic state during the locked interval is MEASURED, not
  inferred.** An instrument that reports whether the capture chain is running
  between `voice session starting` and the unlock resolving. Evidence must
  distinguish (a) from (b) above; a log line that merely repeats "audio
  deactivated" does not.
- **302-B — the CANCELLED-unlock case is run explicitly**, with the locked
  interval held open (trivially arranged while #272 is unfixed). If the mic is
  cold in 302-A but hot here, the defect is real and this is where it shows.
- **302-C — the intended contract is WRITTEN DOWN before any fix.** Should a
  Control Center voice launch on a locked app (i) be refused, (ii) be deferred
  until unlock, or (iii) proceed as it does now? This is a product decision and
  it is **Owen's**, not a lane's — a fix chosen before the contract is stated
  would be guessing at which of three defensible behaviours is wanted.

**Pre-registered response:** if 302-A and 302-B both show the capture chain
cold, this closes as **NOT A DEFECT** with the ordering documented — the
observation was still worth filing, and a closed item with a measurement beats
an unfiled hunch. If either shows it hot, this becomes a privacy defect and
outranks the remaining #254 device bars.

**Related:** #124 (App Lock, whose seven original checks would not catch this —
the same blind spot that hid #272 for 12 days), #272 (unbounded locked interval),
#254 (the run that surfaced it), #118 (background revoke).

> **📝 EXECUTION NOTE 2026-08-10 (voice-triage lane, Lane 1 — instrument
> BUILT; measurement NOT run; nothing built past the measurement, per the
> dispatch's stop-gate).**
>
> **302-A instrument shipped this lane** — three always-on `.notice` lines
> (every interpolation `privacy: .public`; never behind Verbose Logging) in
> `NativeVoicePipelineService.swift`'s `NativeVoiceCaptureController`:
> - `audio session activated for capture (#302-A)` — after
>   `AVAudioSession.setActive(true)` in `start(muted:)`;
> - `capture chain HOT — AVAudioEngine.isRunning=… inputTap=installed
>   (#302-A)` — immediately after `audioEngine.start()`, reading the
>   ENGINE's own `isRunning` back, not a wrapper flag (the wrapper is the
>   thing under suspicion);
> - `capture chain COLD — AVAudioEngine.isRunning was=… now=…
>   inputTap=removed (#302-A)` — in `stop()`, with the state read BEFORE
>   teardown, so `was=false` is usable negative evidence (a start that died
>   in permission checks never went hot).
>
> **Read protocol for the device pass:** the mic was live behind the lock
> iff a HOT line lands before the unlock resolves AND no COLD line falls in
> [HOT, unlock] — intersect with AppLock's existing `.notice` lines
> (`scenePhase … | pre: cover=locked`, `requestUnlock EXIT`), same corpus,
> millisecond timestamps on both sides. That distinguishes (a) from (b)
> directly; (c) is 302-B's arm.
>
> **Scope boundary, explicit:** this instruments the NATIVE capture chain
> only. The realtime engine captures via WebRTC's audio unit
> (`LiveVoiceSessionService` — no `AVAudioEngine`), which is NOT
> instrumented here; both observed trials ran native (per #220, quoted from
> the corpus: `voice session starting on engine native (relayPaired=true)`).
> If 302 recurs on a realtime-configured host, the WebRTC chain needs its
> own instrument.
>
> **302-B fixture RE-ARRANGED (the bar's parenthetical "trivially arranged
> while #272 is unfixed" is STALE as of 2026-08-09 — #272 was FIXED and
> CLOSED that day, PR #289):** the locked interval is now held open
> legitimately — Cancel the biometric sheet, and the fixed behaviour leaves
> the cover down with the in-app UNLOCK button waiting (one auto-prompt per
> lock episode), so the interval stays open until UNLOCK is tapped. Same
> interval, different arrangement; the bar itself is unchanged.
>
> **Parked, and on whom:** the 302-A/302-B measurement rides the next
> device sitting (Control Center cold launch + App Lock is a device
> arrangement; the OJAMD voice sitting covers all three of this dispatch's
> lanes). **302-C — the locked-launch contract (refuse / defer-until-unlock
> / proceed) — is OWEN'S, and comes BEFORE any fix.** The pre-registered
> response stands: both-cold ⇒ closes NOT A DEFECT with the ordering
> documented.

> **2026-08-18 ~22:30 — DESIGN RULED (Owen, pre-build ballot): ONE REAL GATE,
> STARTS-ONLY POLICY.** A single `AppLockState` every subsystem consults —
> voice start (302-C's defer-until-unlock), new inference turns, approval-
> gated actions — one mechanism, one bar per consumer, so the #323 class (a
> subsystem nobody wired) becomes structurally impossible. Covered-state
> policy: NEW user-initiated work defers until unlock; an IN-FLIGHT turn
> finishes and commits normally; host-driven `talaria_phone_query` keeps
> answering (the agent is the owner's; the cover hides everything from the
> holder either way). Thursday PM's lane builds exactly this; bars
> pre-register before code. Twin ruling recorded at #323.

### 🎯 FIX BARS 302-D … 302-G — pre-registered 2026-08-20 (Thursday PM lane), BEFORE any code

**Lane:** the 2026-08-18 ruling, built. `#323` carries the other three
consumers' bars (323-A…E); this block carries the MECHANISM and the VOICE
consumer. One gate, so both entries score the same object.

**What the fix is.** A single `AppLockGate` — one `@MainActor` state, true iff
`AppLockController.cover == .locked` — published by the controller's own
`refreshCover()` and consulted by every subsystem that starts new work. Voice
start awaits it. The state machine is NOT rebuilt: `AppLockStateMachine`
already computes the verdict (`cover(configuration:)`, `AppLockCore.swift:108`);
what has never existed is anything outside the window that can READ it.

**#302's own instruction governs these bars: the fix's bar must close the
RACE, not the arm.** A green 302-A that still depends on Face ID winning a
footrace is not a fix, so every bar below asserts the capture chain is cold
*while locked* — not merely that it eventually starts.

- **302-D — the gate exists as ONE consultable state, and the cover drives
  it.** Drive `AppLockController` through a full episode (cold launch locked →
  auto-prompt cancelled → unlock) and assert `AppLockGate.isLocked` tracks
  `cover == .locked` at every transition. **`.obscured` must NOT lock the
  gate** — the app-switcher snapshot and the Face ID sheet's own inactivity
  both produce it, and gating on them would defer work every time the user
  pulls the notification shade. Mutation: delete the publish line in
  `refreshCover()` ⇒ red.
- **302-E — a voice start while the cover is LOCKED leaves the capture chain
  COLD until unlock, then starts.** Both TalkStore doors scored SEPARATELY
  (`startSession()` and `startSessionDirectly()`) — a fix that defers one door
  and not the other is the #323 class arriving inside its own fix. Evidence
  shape: gate locked ⇒ the fake voice service's start count stays **0** across
  a bounded yield; unlock ⇒ it becomes **1**. Asserting only the second half
  would pass on a build with no gate at all.
- **302-F — an ABANDONED start parked on the lock never opens the
  microphone.** Park a start, `abandonSession()`, then unlock: the start count
  must stay **0** forever. This is #139's defect arriving by the new door — a
  naive implementation parks, resumes, and starts a session nobody is in,
  which is precisely the privacy defect the whole lane exists to close.
- **302-G — App Lock OFF is a NO-OP on the voice path.** Negative control:
  with `isEnabled: false`, both doors start immediately, no wait, no status
  change. **Without this, 302-E and 302-F are both satisfied by a build that
  never starts voice at all** — the failure mode that makes a deferral gate
  indistinguishable from a broken one.

**CarPlay is gated WITH the others, and deliberately carries no bar of its
own.** `CarPlayVoiceManager` is a third door onto `startSessionDirectly()`, so
it inherits 302-E's deferral by construction. Owen's routing, 2026-08-20:
*"I refuse to submit for review to get CarPlay because you have to have a
working product. However, in the simulators, we couldn't get CarPlay to show
in iOS 27… I'm not going to apply for it until it works in the simulator."*
So the surface is **unshippable (no entitlement, #45) and unverifiable (no sim
under 27.0 across two betas, #74)** — a CarPlay-specific bar could not be run,
and an unrunnable bar is furniture. **The deferred question, recorded so it is
not lost:** if the entitlement ever lands, defer-until-unlock means the car's
voice button is dead until the driver picks up the phone, which is the worst
possible moment to hand someone their phone. The exemption is then a one-line
policy change of exactly the same shape as #124's App Intents bypass — decide
it *then*, with a sim that works, not now against a surface nobody can run.

**Pre-registered response.** All four green ⇒ #302's fix is built and the item
moves to device verification (#124's seven App-Lock checks fold in, Saturday's
list item 6). 302-E or 302-F red ⇒ the fix is not built, whatever the other
bars say. **302-G red is the most informative failure available here** — it
means the gate defers work with the lock switched off, which is a worse defect
than the one being fixed.

### ✅ RESULT 2026-08-20 — THE GATE IS BUILT. 302-D…G ALL MET — ~~EACH PROVEN RED BY MUTATION~~ THREE PROVEN RED BY MUTATION; 302-G, the negative control, is GREEN under every mutation, which is its bar. *(Heading corrected 2026-08-23 by the Opus-week audit: the scorecard below always said so; the heading overstated it.)*

**`AppLockGate` (`Talaria/Services/Support/AppLockGate.swift`) is the one
consultable state.** `AppLockController.refreshCover()` is its ONLY writer;
`TalkStore`, `ChatStore` and `ToolConfirmationCenter` are its readers. The
state machine was not rebuilt — `AppLockStateMachine.cover(configuration:)`
has computed the verdict correctly since #124. **What never existed was a
reader outside the cover window**, which is the whole of the root cause both
entries recorded.

**15 tests in `TalariaTests/AppLockGateTests.swift`.**

| bar | verdict | what proved it |
|---|---|---|
| **302-D** gate tracks the cover; `.obscured` does NOT lock | ✅ MET | mutation A1 (delete the publish line) ⇒ 2 tests RED |
| **302-E** both voice doors defer, mic COLD while locked | ✅ MET | mutation A2 (delete both deferrals) ⇒ 2 tests RED, 6 assertions |
| **302-F** an ABANDONED parked start never opens the mic | ✅ MET | mutation B (delete the generation re-check) ⇒ **exactly one** test RED |
| **302-G** App Lock OFF is a no-op on voice | ✅ MET | green under every mutation — which is the bar |

**Bar 302-F is the one that earned its place, and the mutation says why.**
Removing only the post-wait generation re-check left **every other bar
green** — both deferral bars, both negative controls — and turned exactly one
assertion red: the microphone opening after the session was abandoned. That
is `await the gate, then start`, the implementation any reasonable person
writes first. It satisfies 302-E perfectly and re-creates #139's defect
through a door #139 never had.

**#302's own instruction — "the fix's bar must close the RACE, not the arm" —
is honoured structurally, not by a faster clock.** The device failure was
that nothing deferred the capture chain and Face ID merely won a 470 ms
footrace. There is now no race to win: `voiceService.startSession()` is not
reached at all until the gate releases, and the bars assert the call count is
**0 while locked** rather than merely that it eventually reaches 1. Asserting
only the second half would pass on a build with no gate — mutation A2
confirms it, because the post-unlock assertions were the ones that stayed
green.

#### Five things the filing did not contain, all found by building it

1. **🔴 Parking only in `sendMessage` opens a DATA-LOSS window in the compose
   outbox.** `drainComposeOutboxIfPossible` does `composeOutbox.remove` +
   `persistComposeOutbox()` **before** it calls `sendMessage`, and the turn's
   next durable home is the optimistic row `sendMessage` persists. Park in
   `sendMessage` alone and a queued turn spends the entire locked interval —
   which the user makes arbitrarily long simply by leaving the phone locked —
   removed from the outbox and not yet in the transcript. A force-quit or an
   iOS reap in that window loses it outright, where before this lane it
   survived as a `.sending` row. **Fixed by parking at the top of the drain,
   ahead of the removal.** A gate that trades a privacy defect for a
   data-loss defect is not a fix.
2. **`.obscured` must NOT lock the gate, and the distinction is the whole
   difference between a fix and an availability defect.** The app-switcher
   snapshot, a pulled notification shade, an incoming call and the Face ID
   sheet's own inactivity blip all produce `.obscured`. Gating on it would
   defer the user's work every time they glanced at Control Center. Pinned
   explicitly rather than left to the reader.
3. **The tap-driven send paths are UNREACHABLE while covered, which relocates
   the gate's real job.** The cover is a `UIWindow` at `.alert + 1`, so no tap
   reaches the composer, retry or regenerate. What actually dispatches behind
   the cover is the *untapped* work: the compose-outbox drain off
   `handleAppDidBecomeActive`, and — until this lane — the voice pipeline,
   which is exactly how #323's §V1 inference turn got there. The gate is
   defending against unattended paths, not against a phantom user.
4. **`isStartingSession` composes with #254's background revoke for free — but
   only because the flag is claimed BEFORE the wait.** A start parked on the
   lock is still visible to the background observer, so backgrounding a parked
   start revokes it and the parked caller returns `false` on resume. Had the
   flag been set after the wait (the natural reading order), a parked start
   would have been invisible to the one observer #254 built to catch it.

5. **🔴 The honest parked status was NOT DURABLE, and only the FULL-SUITE run
   found it.** `deferUntilUnlocked` set `statusMessage = "Waiting for unlock…"`
   once — but `applySnapshot` overwrites that field wholesale, and the engines
   keep publishing snapshots throughout a locked interval. So the honest
   message survived exactly until the next voice event, after which the user
   would be shown the engine's stale status instead. **Bar 302-E caught it by
   FAILING under full-suite scheduling while passing in isolation** (the event
   task's initial snapshot landed after the park in one ordering and before it
   in the other). The tempting reading is "flaky test, re-roll it" — and this
   project has a standing rule against exactly that. **The flake was the
   defect.** Fixed with a durable `isWaitingForUnlock` flag that
   `applySnapshot` honours, which also makes the bar order-independent for the
   right reason: not by weakening the assertion, but by fixing what it was
   flakily measuring. *(Worth noting against #236, which is a real flake with
   no such cause found yet: an isolation-passes/suite-fails signature is
   **evidence of a scheduling dependency**, not evidence of harness noise.)*

**Also examined and deliberately NOT gated: `HostApprovalStore` (#304).** No
timer, no expiry auto-answer — every path into `post(_:)` originates in
`requestChoice`/`confirmPendingChoice`, both tap-driven, and the cover
prevents the tap. Recorded so the next reader does not re-derive it as a gap.

> **📱 DEVICE 2026-08-20 (build 2894, branch `302-323-app-lock-gate` @ `8c999498`,
> Release OTA on `whoGoesThere`) — THE MICROPHONE HALF IS CONFIRMED FIXED.**
> Owen ran the exact arm that went RED in July: force-quit → Control Center →
> "Talk to Hermes" → **cancel Face ID** → sit ~30 s → try to speak. His words:
> *"The mic stayed dead. I tried talking and it didn't talk back this time."*
>
> **That is 302-B's finding inverted, on the same hardware, through the same
> door, under the same setup.** July's corpus had the capture chain HOT 3.87 s
> before the cancel and staying hot 34.9 s while `cover=locked locked=true`.
> This run has nothing behind the cover.
>
> **✅ THE OTHER HALF IS NOW CONFIRMED TOO — 2026-08-20, same evening.** Owen,
> on the re-run: *"a voice start resumes on unlock after 30+ seconds."* So the
> behaviour is **(a) a real DEFERRAL, not (b) a permanent refusal** — the
> distinction the first report could not settle, and the one that separates
> 302-C's ruled contract from a new defect wearing its symptoms. **302-E is
> device-confirmed on both arms: cold while locked, and it starts on unlock.**
> The 30+ s figure is the parked interval — the session survived being held
> that long and still resumed, which is the arm that matters, since #272's
> fixed Cancel-then-UNLOCK state is what holds a locked interval open
> indefinitely.
>
> *(One reading not excluded by the sentence alone: that the resume itself took
> 30+ s AFTER the unlock, which would be a latency defect rather than a
> deferral one. The natural reading is the parked interval, and it matches the
> test asked for — recorded so a later reader knows which was meant and that
> the alternative was considered rather than missed.)*
>
> **What this closes.** #302's fix is now verified end to end on device: the
> microphone is cold behind the cover (the July defect, inverted) AND the
> session defers rather than dies. Nothing about the fix is unmeasured. What
> remains for this item is #124's seven App-Lock checks, which are a broader
> regression sweep rather than a question about this fix.

> **⚠️ HALF THE CONTRACT IS STILL UNVERIFIED, and the two halves are
> indistinguishable from the report so far.** *(SUPERSEDED by the block above
> — kept because it is the record of what was and was not known at the time.
> Read it in the past tense.)* 302-C's ruled contract is
> **DEFER**-until-unlock, not refuse. "The mic stayed dead" is produced
> equally by:
> - **(a) a correct deferral** — parked, then started when the cover came
>   down; and
> - **(b) a permanent refusal** — the start was dropped and never resumed,
>   which would be a NEW defect against the same ruling that named the fix.
>
> The unit bars prove (a) against a fake service (302-E: park, unlock, start
> count goes 0 → 1), but a fake service is not `VoiceEngineRouter` plus two
> real engines, and the resume crosses a `@MainActor` boundary that the
> fixture does not model. **Asking Owen to re-run and watch what happens AFTER
> the unlock — and recording this as OPEN rather than reading his report
> generously.** A device pass that answers one of two questions has answered
> one of two questions.
>
> **Also owed from the same sitting:** whether `"Waiting for unlock…"` is what
> shows and whether it STAYS (the durability fix the first gate run forced —
> see the RESULT block's finding 5), and the log confirmation that no
> `capture chain HOT` line falls between `cover=locked` and the unlock. The
> felt observation is strong evidence; the corpus is the proof, and #302 has
> been a millisecond-ordering question from the day it was filed.

> **📱 DEVICE 2026-08-20 — 323-A's MECHANISM FIRED ON A REAL PHONE.** Caught
> incidentally in #72's PCC pass, which is the best kind of confirmation
> (nobody was looking for it). The launch log carries, twice:
> ```
> compose outbox drain deferred — App Lock is covering the app (#323-A)
> scenePhase background -> active | pre: cover=locked locked=true …
> autoAuth FIRED (no tap) after attempt=0 this episode
> requestUnlock EXIT attempt=1 result=SUCCESS (episode ends, counter reset)
> ```
> **The drain deferred behind the cover and the episode resolved normally** —
> the untapped path that #323's §V1 finding was actually about, gated on
> device rather than only in a fixture. It also exercises the data-loss fix
> from this lane's finding 1: the deferral happened at the DRAIN, ahead of the
> outbox removal, which is where it had to be.
>
> Still not covered by this observation: the voice DEFERRAL half (#302's open
> question — does a parked voice start actually resume on unlock).

**STILL OWED — device verification.** These bars are unit-level. The device
question 302-A/302-B answered in the negative must be re-asked on the fix:
Control Center → "Talk to Hermes" on a locked app, cancel Face ID, and read
the same corpus for `capture chain HOT` inside the locked interval. **#124's
seven App-Lock device checks fold into this pass** (Saturday's list, item 6).

## 308. 📝 PUBLISH the talaria plugin repo — the unblock for #269-B, and the update path it needs — **NAMED 2026-08-09 by Owen ("The plugin could eventually be made public, especially if we tie some sort of git pull for the plugin or something"). Filed the day it was named per #268. NO DESIGN, NO LANE — Owen routes.** **⟵ HEADER CORRECTED 2026-08-23: partly RULED already. Owen ruled 2026-08-18 (under #363, pointed here per the close-out rule) — **no deploy token**, and the repo goes public **AT the #269-B publication moment**. So the routing is decided; what is still owed is the **pre-publish scrub** (secrets / host paths / tailnet IPs / #255 naming / attribution) and the **compatibility-signal** question. The scrub is desk work available now; PUBLISHING is outward-facing and needs Owen's explicit per-submission go.**

**What it unblocks, precisely.** #269-B (the conversational installer's install
half) is blocked on **two** things and publishing fixes only the first:
1. **`AethyrionAI/talaria-plugin` is private**, and `hermes plugins install` is
   git-only and non-interactive (`plugins_cmd.py:485-492`) — **no user's Hermes
   can clone it.** Publishing closes this.
2. **There is no reload.** `discover_and_load` early-returns on a process-global
   singleton, and the agent runs *in-process*, so the install's last step is
   killing the process the agent lives in. **Publishing does not touch this, and
   it is the harder half.** Do not read "made public" as "#269-B unblocked".

**On the git-pull idea — the pull is the easy part.** ✅ **Verified 2026-08-09:
the plugin already survives `hermes update`** — it lives at `~/.hermes/plugins`,
*outside* `~/.hermes/hermes-agent`, which is the tree `curl install.sh | bash`
replaces. **So deletion is not the fragility. DRIFT is.** Upstream moves ~1,341
commits/week (measured); a preserved plugin against a newer agent does not get
deleted, it silently stops matching the API it was written for. **A bare pull
delivers fresh bytes with no signal about whether they still fit** — and it
inherits the reload problem above, so you would also get fresh bytes served by a
stale process. **The missing piece is a compatibility signal, not a fetch.**

**⚠️ A SCRUB IS OWED BEFORE ANY PUBLISH, and it is not optional.** Going public
changes the bar on content that is currently private-by-default:
- **Secrets and host specifics** — tokens, keys, `O:\Hermes\`, `C:\Users\Owen\`,
  tailnet IPs (`100.110.102.59`, `100.79.222.100`), `HERMES_HOME` paths.
- **#261's standing rule** — no attack mechanics, crafted strings, or
  copy-pasteable probes in anything that goes to GitHub. That rule exists
  because it was violated once already.
- **Naming (#255)** — a public repo carrying `hermes-mobile` is a different bar
  than a private one, and #255's inventory found that name is **WIRE**, not
  cosmetic: it is the MCP tool namespace a live agent config depends on.
- **Attribution** — Talaria is forked from `dylan-buck/Hermes-iOS`, and
  `THIRD_PARTY_LICENSES.md`'s attribution is flagged never-touch. Confirm what
  lineage the plugin carries before it is published under a new name.

**This is Owen's decision, not a lane.** Publishing a repo is outward-facing and
irreversible in practice (it can be un-published, but not un-seen). **Bars
pre-register here if it is ever routed.**

**Open questions worth answering before deciding:**
1. Does the plugin need to be public at all, or would a documented
   `git clone`-from-a-release-tarball path serve the same users?
2. If public, does it become a thing we **support** — issues, PRs from
   strangers, a compatibility matrix against a 1,341-commit/week upstream?
   Upstream's own posture is instructive: 857 authors/30d but a **16.6% merge
   rate** and ~20k open PRs.
3. What is the compatibility signal — a version floor the plugin asserts at
   load, a probe, or a tested-against tag?

> **2026-08-18 upstream pointer (the ruling landed under #363 the same day;
> corrected here per the close-out rule):** Owen ruled — no deploy token
> ("i'll pass. Making the repo public when we're done at least"); the repo
> goes public AT the #269-B publication moment, which also retires the
> plugin-update credential papercut. Still owed before the trigger: the
> pre-publish scrub (secrets / host paths / tailnet IPs / #255 naming /
> attribution) and the compatibility-signal question.

> **✅ 2026-08-23 — THE PRE-PUBLISH SCRUB RAN** (read-only over the Mac's live
> checkout `~/.hermes/plugins/talaria`, working tree AND full git history):
> `planning/reports/2026-08-23-308-prepublish-scrub.md`. Verdicts: **zero
> secrets anywhere** (tree or history — no 64-hex, no `sk-`, no committed
> `.env`; the test key is a labeled runtime-built dummy), zero tailnet IPs or
> `*.ts.net` names, no attack mechanics, and the #255 naming is 2 occurrences,
> BOTH cosmetic docstrings — publishable as-is. **1 BLOCKS-PUBLISH: the
> personal email is the commit identity on 43/44 commits**, history-resident,
> so publishing requires either a `git filter-repo` mailmap rewrite (breaks
> every SHA, including README install-by-SHA pins) or a FRESH-HISTORY publish
> — the report recommends fresh-history, which also clears the minor
> history-resident findings in one move. 5 NEEDS-OWEN-DECISION: publish
> mechanics, license choice (**no LICENSE file exists**, and `talaria/voice.py`
> self-describes as a port of the retired connector's voice bootstrap —
> dylan-buck lineage, MIT — so heritage needs a note), `whoGoesThere` as a
> test-fixture name, two OJAMD provenance comments + first-name mentions, and
> the compatibility signal. **The compatibility-signal question is ANSWERED as
> "nothing exists today"** — no version floor, fail-soft `register()`, CI
> against floating HEAD — with four candidate homes for a floor laid out in
> the report.

> **⚖️ RULED 2026-08-23 (Owen, decision pass — all four scrub decisions):**
> 1. **Publish mechanism: FRESH-HISTORY.** At the #269-B moment the scrubbed
>    tree is squashed onto a new public history; this repo keeps the private
>    history. Clears the email finding and every minor history finding in one
>    move; deployed `--ref` pins get re-issued once. The mailmap rewrite is
>    declined.
> 2. **License: MIT + upstream-heritage note.** MIT matching the app repo,
>    plus a one-line acknowledgment that `voice.py` ports the retired
>    connector bootstrap's behavior (dylan-buck lineage, MIT).
> 3. **Depersonalize: MINIMAL.** Rename the `whoGoesThere` fixture and reword
>    the two `OJAMD` comments in the pre-publish commit; the "Owen ruled…"
>    provenance comments and "Owen's iPhone" fixtures stay — load-bearing
>    provenance, low-risk once the email is gone.
> 4. **Compatibility floor: the FULL STACK.** `manifest_version: 1` + a loud
>    logged floor check in `register()` (fail-soft preserved) + a README
>    tested-against line + CI pinned to a tag/SHA. This closes the open #308
>    compatibility question as a ruling; the build is a plugin lane and its
>    deploy rides the per-experiment go like any other.
>
> Same day: the live checkout's git identity was set to the noreply address
> (`git config user.email`, repo metadata only — nothing the gateway loads),
> so post-scrub commits stop re-introducing the BLOCKS-PUBLISH finding.
> **What #308 still waits on:** the #269-B publication moment itself, which
> remains outward-facing and needs Owen's explicit per-submission go.

> **🎯 BARS 308-FLOOR-A..E — pre-registered 2026-08-23 (late night), BEFORE
> any code, for ruling 4's compat-floor plugin lane.** Facts pinned from the
> live 0.20.5 checkout before writing these: `hermes_cli.__version__` is the
> in-process version read (`hermes_cli/__init__.py:17`, `"0.20.5"` — register()
> runs inside the gateway process, so this reads the code actually serving);
> and the installer's validator (`plugins_cmd.py` `_SUPPORTED_MANIFEST_VERSION
> = 1`) accepts a declared `manifest_version: 1` and refuses only GREATER —so
> declaring it is safe today and buys the "run the update command" refusal
> from any future installer whose schema moved.
> - **308-FLOOR-A (manifest):** `plugin.yaml` declares `manifest_version: 1`;
>   a test parses the manifest and asserts the key is the int 1.
> - **308-FLOOR-B (below-floor arm, RED-first):** with the version read
>   returning a below-floor value, the load-time check emits a loud named
>   line (stable grep token `[talaria] COMPATIBILITY FLOOR`) AND registration
>   still proceeds — fail-soft preserved, per the module's own "register must
>   never break gateway load" contract.
> - **308-FLOOR-C (negative controls):** at-floor and above-floor emit NO
>   floor warning; an unparseable or unreadable version emits a skip line and
>   never raises.
> - **308-FLOOR-D (lockstep pin, #399-shape):** CI's hermes-agent clone is
>   pinned to a full 40-char SHA (not floating HEAD), and a structural test
>   reads `.github/workflows/ci.yml` + `README.md` and asserts the SAME SHA
>   appears in both — the README "tested against" claim cannot drift from
>   what CI actually tests. The test fails loudly if either file is
>   unreadable.
> - **308-FLOOR-E (mutations):** deleting the register()-side check call
>   turns the integration test RED; reverting the CI pin to HEAD (or editing
>   README's SHA) turns 308-FLOOR-D RED. Both run and recorded.
> Floor constant: **(0, 20, 3)** — the oldest host version the plugin is
> LIVE-verified on (OJAMD measured 0.20.3 with the plugin serving, 2026-08-18,
> #347/#349's wire probes); earlier lines are unmeasured with the plugin, so
> the floor claims only what was measured. Pin SHA:
> `503d863fcd2cbfc0be5a6d6c536fae2e98aa4204` — the Mac checkout's HEAD, which
> is what local pytest (the hermes venv's `-e` install) and the live gateway
> both run. **Deploy of the resulting plugin commit rides the per-experiment
> go like any other — building this lane deploys nothing.**

> **✅ RESULT 2026-08-23 (late night) — 308-FLOOR-A..E ALL MET. Plugin commit
> `dbf32c9` on plugin main (version 0.5.0 → 0.6.0); DEPLOYED NOWHERE — both
> hosts' live checkouts stay at `e669549` until a per-experiment go.**
> RED-first honest: all 7 new tests failed before any code (manifest key
> absent, `talaria/compat.py` nonexistent, README line missing, CI unpinned).
> Both 308-FLOOR-E mutations isolate cleanly — deleting the register()-side
> call reds ONLY `test_register_consults_the_compat_floor` (6 others green);
> reverting the CI pin to a floating ref reds ONLY the lockstep test. Suite
> **201 → 208** (the count moved by exactly the additions); `hermes plugins
> doctor . --ci` passes on the tree (`manifest: talaria 0.6.0`; the
> `pre_tool_call`/`provides_hooks` WARN is pre-existing, not this lane's).
> One expected casualty updated: `test_plugin_version_reads_the_yaml`'s
> literal moved 0.5.0 → 0.6.0 with the bump. **Consequence for the pending
> OJAMD deploy: the go should take `dbf32c9`, not `e669549` — it contains
> #396's presets AND the floor, so one desk visit discharges both.** The
> Mac's next deploy go advances it the same way. **With this, every ruled
> #308 build is done; the item waits ONLY on the #269-B publication moment
> (fresh-history publish + pre-publish edits, Owen's explicit go).**

## 312. 🔬 Continuity fabric DEVICE PASS — Group 7 has genuinely never run once — **FILED 2026-08-09 (successor A of #93's split; Owen ruled the split). The oldest owed verification on the board, on mechanisms four later lanes (#97, #114, #240, #283) now depend on.**

The checklist is `dispatch/DEVICE-PASS-RUNNING-LIST.md` **Group 7**: items
(a) kill/relaunch resumes the SAME hop with no priming notice; (b) gateway
stop → app relaunch → gateway restart shows the transplant notice + priming
tokens; **(c′) as rewritten 2026-08-09** (model pick mid-conversation → SAME
hop reused, NO priming notice, reply attributed to the new model — a priming
notice is a REGRESSION; the original (c) tested the removed
`switchModel`-ends-the-hop mechanism); (d) local-brain turns then Hermes →
the transplant carries the local exchange; (e) airplane mode parks `.queued`,
reconnect auto-sends (**airplane mode specifically** — a dead host over
Tailscale surfaces `.timedOut` → honest `.failed`, by design); (f) session
totals show the PRIMING row + cost. **Batch with Group 6** (both need
host-side gateway stop/restart); ~25–30 min corded.

> **2026-08-18 — the Group 7 RESULT block this entry never carried (it lived
> only in the board INDEX line; written in per the close-out rule):** RAN
> 2026-08-11 (Owen, whoGoesThere, build `6b9e7e2`): (c′) PASS — model switch
> mid-conversation, same hop reused, correctly attributed; (d) PASS —
> transplant notice + the host read the prior exchange back; (e) PASS —
> airplane-mode queue fired exactly once on reconnect; (a) RED → #329;
> (f) RED → #330; **(b) NOT RUN — needs a host-side gateway stop/restart,
> the one row left for a device sitting (batch with Z8).**
>
> **⟵ 2026-08-25, #330's fix lane: item (f)'s MECHANISM IS FIXED but (f) is
> STILL RED on this board**, and the distinction is the point. #330's fix
> (the `TurnReceiptSidecar` + the primer re-map) is unit-green and
> Release-clean, but (f) is a DEVICE observation and only a device sitting
> can retire it. It flips when 330-G does — same sitting, same card, one
> look: transplant a thread, reopen it from the drawer, open the status card
> and see the SESSION block with its Priming row and Est. cost. **Do not
> mark (f) PASS off a green suite** — that would be recording a prediction
> as a measurement, which is the thing this row exists to prevent.

> **🔴 2026-08-31 — 312(b)'s FAIL CLAUSE CONTRADICTS A DOCUMENTED-LEGITIMATE
> STATE.** The card fails the run on "no priming tokens". But the Priming row
> renders `"—"` **by design** when the token count is unknown
> (`StatusCardView.swift:96-103`), which is this project's own real-data-only
> convention — so a correct app can trip the card's FAIL. #330-G already
> carries the right rule for the same surface, and the two should agree.
> **Correction:** score the transplant NOTICE and the session block's
> survival; treat `—` in Priming as PASS-compatible, and fail only on a
> contradictory NUMBER. Turning verbose ON (for `/usage`) makes the whole
> card cheap and unambiguous. Found by the runbook staleness audit.

## 332. 🎲 THE FIRST DEVICE SUITE RUN — three failures the simulator has been hiding, on two devices at once — **FILED 2026-08-11. The full unit suite had NEVER run on hardware; every green in this project's history came from a simulator. It ran on both `whoGoesThere` and Shelley's iPad in the same sitting and failed on both, differently. ~~NOT STARTED~~ → **332-a and 332-b FIXED 2026-08-12 on `t27-332ab-device-suite-test-fixes`** — both are sim-verified with witnessed negative controls, and each has ONE half left that only hardware can score, deferred to the next central device pass (this lane touched no device, by instruction). **332-c STAYS OPEN and is untouched** — its first bar is a measurement nobody has taken yet, and the entry must not be edited to assume the benign answer. Bars per finding below.**

**The run.** `-only-testing:TalariaTests` on each device, `main` @ `7699c43`.
- **`whoGoesThere`** — 2123 tests / 161 suites, **2 issues**, 69.5 s.
- **iPad Air M3** — 2066 tests / 157 suites, **5 issues**, 68.9 s (fewer tests: four
  EventKit/AlarmKit suites skipped by Owen's absolute no-writes rule for that device;
  verified afterwards — those four suites report 0 runs there and the log shows zero
  EventKit activity).

The same commit is green on the simulator. **Three separate causes, none of which a
simulator can express.**

---

### 332-a — a bar that CANNOT be scored on a device, and fails rather than skipping
**Both devices.** `approvalPathSourcesNeverReferenceALanguageModelSession()`
(`Phase0ActionCautionTests.swift:352`) →
`NSCocoaErrorDomain Code=260 "The file 'LocalChatBackend+IntentRout…' couldn't be opened
because there is no such file"`.

This is **#224's bar 0F**, landed 2026-08-11. It proves no `LanguageModelSession` is
constructed on the approval path by **reading the Swift source files at runtime** — which
works in a simulator, because the sim shares the Mac's filesystem, and **cannot work on a
device**, where the sources do not exist. Its own lane recorded *"the source-scan approach
works from the simulator sandbox (it read all four files)"* without noticing that was a
property of the sandbox rather than of the test.

**Why it matters beyond one red:** the bar is a genuinely good idea — it carries a positive
control asserting the scan still finds the constructions it expects — but as built it
**reds every device suite run forever**, and a permanently red test is one people learn to
skip past. It must either skip explicitly on device with a reason naming this item, or be
re-expressed as something a device can check.

**332-a bars:** (1) the test no longer fails on device — it either passes or skips with a
reason; (2) the sim arm keeps its positive control, so the #224 ruling 5 guarantee is not
weakened; (3) whichever route is taken is stated at #224's entry, because that entry
currently claims 0F is MET without qualification.

> **▶ 332-a FIXED 2026-08-12 (`t27-332ab-device-suite-test-fixes`). Route taken: an
> EXPLICIT SKIP, not a re-expression.** The test keeps its body — every scan, the
> positive control, the loud failure on an unreadable file — and gains a
> `.enabled(if:)` trait whose condition is a file-scope `let` resolved by
> `#if targetEnvironment(simulator)`. The discriminator is **compile-time on
> purpose**: the test bundle is built per destination, so nothing is sniffed at
> runtime and there is no device-only code path to drift.
>
> - **Bar (1) — the MECHANISM is witnessed; the DEVICE RUN is not.** The skip was
>   observed by forcing the discriminator to its off-simulator value and running
>   from the simulator, which is the same shape as 332-b's RED witness rather than
>   an assumption. Verbatim, `witness.log:276`:
>   ```
>   ➜ Test approvalPathSourcesNeverReferenceALanguageModelSession() skipped:
>     "#332-a: this bar proves ruling 5 by READING the repo's Swift sources at
>      runtime, so it can only be scored where the test process shares the Mac's
>      filesystem — a simulator. …"
>   ```
>   Skipped, with a reason naming this item — not failed. The test bundle also
>   **compiles for a real-device destination** (`build-for-testing`,
>   `generic/platform=iOS`), so the `#else` arm is proven to build, not merely
>   written. **What is NOT scored here: an actual device suite run.** No device was
>   touched by this lane, by instruction; bar (1) closes at the next central device
>   pass. The exact command is in that pass's list.
> - **Bar (2) — MET, and re-measured rather than argued.** The simulator arm is
>   byte-unchanged inside the function. Targeted run on `CC-332-iPhone-Air`:
>   `✔ Test approvalPathSourcesNeverReferenceALanguageModelSession() passed after
>   0.034 seconds`, inside `✔ Test run with 26 tests in 3 suites passed`, with **no
>   skips**. The positive control still asserts the scan finds the constructions in
>   `LocalChatBackend+IntentRouting.swift`, so #224's ruling-5 guarantee is scored
>   on every gate run exactly as before.
> - **Bar (3) — MET.** #224's 0F block carries a dated qualification in this same
>   commit.
>
> **One finding this lane nearly shipped a false green on, worth more than the fix.**
> The first targeted run selected `-only-testing:TalariaTests/Phase0ActionCautionTests`
> and reported `✔ Test run with 17 tests in 2 suites passed` — a clean green that
> **never executed the test being fixed**. 0F lives in `ApprovalModeScaffoldTests`,
> a second suite in the same FILE; a file name is not a suite name. The tell was
> grepping the log for the test's own name and finding nothing. Same family as
> `-only-testing:` without the trailing `()` matching zero tests and printing
> TEST SUCCEEDED: **after any targeted run, grep the log for the specific test
> name — a suite-level pass is not evidence that your test ran.**

### 332-b — a test that assumes a clean Spotlight index
**Phone only.** `donationIsGatedByTheToggle()` (`SpotlightIndexingTests.swift:64`) →
`Expectation failed: service.sessionEntities.isEmpty`.

On a real phone the Spotlight index is **not** empty — a device log from this same evening
reads `[SpotlightIndexing] donated 108 session entities`. The test asserts emptiness as a
precondition of the gate check, which holds on a fresh simulator and does not hold on a
device that has been used.

**This is test isolation, not a product defect** — real system state bleeding into an
assertion. But it is exactly the class that makes device suites look flaky and then get
ignored.

**332-b bars:** (1) the test asserts the *gate's behaviour* rather than global index
emptiness, and is green on a device with pre-existing donations; (2) it still fails if the
toggle stops gating — witnessed, not assumed.

> **▶ 332-b FIXED 2026-08-12 (`t27-332ab-device-suite-test-fixes`).** The assertion is
> now a **delta, not an absolute**: snapshot the donated ids, offer one whose id is
> unique per run (`gate-probe-<UUID>`), then require that the offered id is absent
> afterwards AND that the donated set is exactly the one we found. Pre-existing
> donations can neither satisfy nor defeat that — 0 donations and 108 read the same.
>
> - **Bar (1) — the ASSERTION is fixed and sim-green; the DEVICE RUN is pending.**
>   It no longer reads global emptiness, and the id is unique per run, so a phone
>   carrying 108 entities passes by construction rather than by luck. Green in the
>   targeted run and in the gate. **No device was touched by this lane** — bar (1)'s
>   device half closes at the next central device pass.
> - **Bar (2) — MET, WITNESSED.** The `isEnabled?() == true` guard was removed from
>   `SpotlightIndexingService.donateSessions` and the test re-run; it went RED on
>   **both** new expectations, then the guard was restored and it went green.
>   Verbatim:
>   ```
>   ✘ Test donationIsGatedByTheToggle() recorded an issue at
>     SpotlightIndexingTests.swift:91:9: Expectation failed:
>     service.sessionEntities[offeredID] == nil
>   ↳ disabled toggle must block donation entirely — the offered session was recorded anyway
>   ↳   service.sessionEntities[offeredID] → ChatSessionEntity(id: "gate-probe-8E46E269-…")
>   ✘ Test donationIsGatedByTheToggle() recorded an issue at
>     SpotlightIndexingTests.swift:93:9: Expectation failed:
>     Set(service.sessionEntities.keys) == before
>   ↳ a disabled toggle must leave the donated set exactly as it found it
>   ↳   Set(service.sessionEntities.keys) → ["gate-probe-8E46E269-…"]
>   ↳   before → []
>   ✘ Test donationIsGatedByTheToggle() failed after 0.031 seconds with 2 issues.
>   ```
>
> **The obvious fix that was deliberately NOT taken:** clearing the session cache
> (or `UserDefaults`) at the top of the test to manufacture the empty world the old
> assertion wanted. **The test host IS the app** — on a device that would delete the
> owner's real Spotlight donations to make a test convenient. A test that destroys
> user data to establish its own precondition is worse than the red it fixes.
> Related, and the reason the entity id is a UUID rather than `"sess-1"`: a fixed id
> could collide with a real donation and turn the check vacuous.
>
> **The test now PRINTS its own precondition** —
> `#332-b PRE-EXISTING DONATED SESSION ENTITIES ON THIS HOST: N` — because bar (1)
> says "green on a device with pre-existing donations" and a green alone cannot tell
> a dirty index from an empty one. On the simulator that number is 0 and the run is
> still valid (the delta is what is scored); on `whoGoesThere` it should be nonzero,
> and if it is 0 there, bar (1) is NOT met by that run and the device's Spotlight
> toggle needs checking before re-running. That is the `#257 CAPABILITY BLOCK`
> precedent: print the thing the reader would otherwise have to assume.

---

### 332 — THE DEVICE-PASS COMMANDS for 332-a(1) and 332-b(1)

> **✅ 332-a(1) SCORED ON HARDWARE 2026-08-12, same day** — the narrow run on Shelley's
> iPad (`main` @ `a5595a2`, the #333 device sitting, device unlocked by Owen). The test
> **skipped with the full #332-a reason string** (log line quoted: *"➜ Test
> approvalPathSourcesNeverReferenceALanguageModelSession() skipped: '#332-a: this bar
> proves ruling 5 by READING the repo's Swift sources at runtime…'"*), `** TEST
> SUCCEEDED **`, and **zero `Code=260` errors** (the one `NSCocoaErrorDomain` string in
> the log is the skip reason quoting itself — checked before scoring). 332-a is now
> fully met: sim positive control on every gate + device skip witnessed. **332-b(1)
> remains owed** — it needs `whoGoesThere` (the pre-existing-donations condition lives
> there), and the narrow command below still applies for that half.
>
> **✅ 332-b(1) SCORED ON `whoGoesThere` LATER THE SAME EVENING — and the run it rode
> in on is the project's FIRST FULLY GREEN DEVICE SUITE:** `main` @ `d4ebbe2`, full
> `-only-testing:TalariaTests` on the phone — **`✔ Test run with 2181 tests in 169
> suites passed after 83.136 seconds`**, `** TEST SUCCEEDED **`.
> `donationIsGatedByTheToggle() passed` with the fixed test's own freshness line
> reading **`#332-b PRE-EXISTING DONATED SESSION ENTITIES ON THIS HOST: 484`** — the
> gate assertion was exercised against a genuinely non-empty index (N=484 > 0, so the
> bar's "green with pre-existing donations" condition is met by evidence, not by
> vacuity). The device skip line for 332-a appeared in the same log; zero `Code=260`.
> **332-a and 332-b are both CLOSED, both halves each. 332-c stays open** (iPad
> downscale — the one remaining red class, not exercised by this phone run).

Neither device half was scored by the fixing lane, which touched no hardware by
instruction. Both close in one device run. Run from the repo root with
`export DEVELOPER_DIR=/Applications/Xcode-beta5.app/Contents/Developer`:

```bash
# Narrow — the two tests this lane changed. Note the trailing "()" on each
# Swift Testing name: without it -only-testing matches ZERO tests and still
# prints TEST SUCCEEDED.
xcodebuild test -project Talaria.xcodeproj -scheme Talaria \
  -destination 'platform=iOS,name=whoGoesThere' \
  -only-testing:'TalariaTests/ApprovalModeScaffoldTests/approvalPathSourcesNeverReferenceALanguageModelSession()' \
  -only-testing:'TalariaTests/SpotlightIndexingTests/donationIsGatedByTheToggle()' \
  2>&1 | tee /tmp/332-device-narrow.log

# Wide — the full unit suite, i.e. a repeat of the run that filed this item.
# This is also what re-scores 332-c, so prefer it if the iPad is in the sitting.
xcodebuild test -project Talaria.xcodeproj -scheme Talaria \
  -destination 'platform=iOS,name=whoGoesThere' \
  -only-testing:TalariaTests \
  2>&1 | tee /tmp/332-device-suite.log
```

**Scoring — three greps, and a green verdict alone does not settle any of them:**
```bash
# 332-a(1): SKIPPED with a reason naming the item, and NOT failed.
grep -E '➜ Test approvalPathSourcesNeverReferenceALanguageModelSession\(\) skipped' /tmp/332-device-*.log
grep -c 'NSCocoaErrorDomain.*260' /tmp/332-device-*.log      # must be 0

# 332-b(1): passed, AND against a non-empty index.
grep -E '✔ Test donationIsGatedByTheToggle\(\) passed'        /tmp/332-device-*.log
grep -E '#332-b PRE-EXISTING DONATED SESSION ENTITIES'        /tmp/332-device-*.log
```
A missing skip line is as much a miss as a failure line: it would mean the
discriminator did not resolve the way `#if targetEnvironment(simulator)` says it
must. `N = 0` on the second grep means 332-b(1) was not exercised, not that it
passed.

**GATE for the 332-a/332-b fix — PASS**, sim `CC-332-iPhone-Air`
(`A730C5A2-2F06-40D0-AF44-54E83B74FBD8`), calendar + reminders TCC granted
immediately before the run:
```
  PASS  Test run reported TEST SUCCEEDED
  PASS  Swift Testing tests run — 2145
  PASS  XCUITest tests run — 14
  NOTE  2 test(s) SKIPPED — the known-permanent CondenserFidelityTests pair
  PASS  Release build succeeded
  PASS  no Swift compile errors in Release
GATE: PASS
```

> **⚠️ THE TEST COUNT DID NOT MOVE — 2145 before and after — and that is CORRECT
> here, which makes the usual staleness check useless.** This lane rewrote two
> existing tests and added none, so "confirm the count MOVED" cannot distinguish a
> fresh binary from `test-without-building` re-running the old `.xctest`. The
> freshness proof used instead is a **string that exists only in the new code**:
> the suite log contains `#332-b PRE-EXISTING DONATED SESSION ENTITIES ON THIS
> HOST: 1`, which the previous binary could not have printed. **Generalise this:
> when a lane edits tests without changing their number, the count check is
> vacuous and a new string in the log is the substitute.**
>
> And that `1` is not noise — it is the RED-witness's probe entity, persisted into
> the lane simulator's `UserDefaults` while the gate was deliberately broken. So
> the gate run scored the fixed assertion **against a non-empty index**, which is a
> small simulator-side rehearsal of exactly the device condition 332-b(1) names.
> The junk row is left in place on `CC-332-iPhone-Air` deliberately; deleting it
> would only make the next run less like a device.

### 332-c — 🔬 THE INTERESTING ONE: three attachment assertions are SCREEN-SCALE dependent
**iPad only**, three failures in `AttachmentDownscaleTests`, all green on the phone and on
the sim:

```
inlinedPayloadIsAtMostHalfThePreFixSize   :148  dataURL.utf8.count * 3 → 534021
                                                legacyPayload * 2      → 355968
fourImagesNoLongerOverrunTheAggregateBudget :166  legacyTotal > aggregateAttachmentBudget → false
reportsEncodedSizeForTheRecord              :233  after.count < before.count → false
```

Read the first one: the downscaled payload came out at ≈178 KB against a legacy baseline of
≈178 KB. **On the iPad the downscale saved nothing**, and the second failure says the
legacy path did not even overrun the budget the test exists to defend.

**The probable mechanism, NOT yet proven:** the iPad Air is a **2× device** and the iPhone
17 Pro Max is **3×**. A fixture image built from points renders to fewer pixels on the
iPad, so it is already at or under the downscale target and there is nothing to save —
which makes all three assertions vacuous there rather than wrong.

**What points AWAY from a product defect:** `stagedImageIsDownscaledInPixelsNotPoints()`
— #132's fix — **passed on the iPad**, immediately above these failures. The production
path is scale-aware; the suspicion is that the **fixtures** are not.

**Do not treat that reading as established.** The failing assertions are about *sizes*, and
a device that silently stops downscaling attachments would be a real regression with a real
cost. **332-c's first bar is to tell those two apart**, and the entry must not be edited to
assume the benign answer before that measurement exists.

**332-c bars:** (1) **name the cause by measurement** — instrument the fixture's actual
pixel dimensions and the encoder's output on both devices, and say whether the fixture or
the production path differs; (2) if it is the fixture, make it scale-independent so the
assertion is meaningful on every device rather than only on 3×; (3) if it is the production
path, that is a defect and gets its own item; (4) the phone and sim arms stay green.

---

**What this run bought, stated plainly:** three findings, from a suite that has been green
2,123 times on a simulator, in 70 seconds per device. Two are test-infrastructure defects
that would have made future device runs look flaky; one may be a real behavioural
difference between hardware classes. **None of them was reachable from a simulator**, and
the exercise that found them was "run the thing we already have somewhere we had never run
it".

**Cross-references:** **#224** (0F is the bar 332-a breaks), **#132** (the pixels-not-points
fix whose test passes on both, and is the reason 332-c leans toward fixtures), **#326** (the
sibling lesson — a failure that looked device-specific and was really contention),
**#313** (the sibling lesson — a red that was a proxy problem, not the defect it named),
`planning/DEVICE-BACKLOG-TRIAGE-2026-08-11.md` (the plan this run validates).

## 340. 🔴 THE TOOL IS CALLED, THE TIME IS DROPPED, AND THE MODEL CLAIMS THE TIME ANYWAY — a dateless reminder that never fires, reported as *"set for 11"* — **AND #338'S GUARD IS BLIND TO IT BY DESIGN. MEASURED IN PRODUCTION 2026-08-12 9:51 PM, discriminator RESOLVED the same minute. NOT STARTED; bars pre-registered below.** **⟵ HEADER CORRECTED 2026-08-23 (stale-header sweep), AND THE FIRST CORRECTION WAS ITSELF WRONG — REPLACED THE SAME DAY. It read *"the route-(a) FIX is genuinely unbuilt"*. **Route (a) was BUILT + MERGED 2026-08-21** (`DeviceActionParsing.parseBareClock`/`resolveBareClock`, wired into BOTH `performCreate` and the card-edit path; 340-H1..H4 met, wiring suite mutation-proven), and **340-H5 RAN on device the same day** — its bar missed and was retired as unfit, replaced by 340-H5′-A..D. What is actually owed is the **device A/B at n≥40/arm** (340-H5′) plus **340-E**, Owen's call. So this header's NOT STARTED is wrong outright, not "accurate about the fix".** **⟵ 📌 POINTER 2026-09-01 (#340-PROMOTE): that "what is actually owed" clause is now FALSIFIED TWICE OVER, and neither falsification reached this header at the time.** 340-H5′-A/B **RAN AND PASSED 2026-08-27** (n = 40/arm, both bars met, both guards held), and **340-E was RULED NO on 2026-08-31** — the guard stays prose-only, DISCHARGED. So from 08-31 this header described as *owed* two things that were finished, while the promotion the A/B had earned by its own pre-registered wording sat **unexecuted for five days**. This lane executed it. **What is owed NOW is neither of those: it is the residual ~55% omission, re-filed WATCH-shaped in the 340-P result block at the end of this entry.** The "NOT STARTED" at the head of this header has been wrong since 2026-08-21 and is deliberately NOT deleted — the correction chain beneath it is the record of how a header goes stale in the claiming-open direction, which is exactly the failure that hid this promotion.

> **🔴 2026-08-23 — A CORRECTION THAT WAS ITSELF WRONG, AND THE CHECK THAT
> SHOULD HAVE CAUGHT IT EXEMPTED IT FOR SAYING SO.** The 08-23 stale-header
> sweep appended a clause to this header claiming route (a) was *"genuinely
> unbuilt."* It shipped 2026-08-21. The error then propagated: the Sunday
> night build list booked #340 as *"the fix and the scorer are desk work"* and
> Owen elected it on that description. It is **device work** — 340-H5′, n≥40
> per arm — and there was nothing here to build.
>
> **The mechanism is worth more than the mistake.** Of the fourteen headers
> that sweep corrected, **thirteen claimed something WAS built or merged, and
> one — this one — claimed something was NOT.** A presence claim is settled by
> a grep or a git check. **An ABSENCE claim can only be settled by reading the
> whole entry**, and this is the longest entry in the tracker: the `✅ ROUTE
> (a) BUILT` block sits roughly seven hundred lines below the header, past two
> falsified candidates and four sets of pre-registered bars. The sweep read
> enough to be confident and not enough to be right.
>
> **And `check_headers_claiming_not_started`, added by that same sweep, could
> not fire here — because it exempts any header carrying the `HEADER
> CORRECTED` marker.** The exemption is granted by the marker's PRESENCE, not
> by whether what it says is true, so **a wrong correction silences the check
> permanently.** A sweep that writes its own exemption is worse than one with
> no check at all: the entry now reads as reconciled. The invariant is
> narrowed in the same commit — a correction clause may no longer claim
> not-started over a body that records a build — and mutation-verified against
> this very text.
>
> **The rule this earns: an absence claim needs a positive read, not a
> confident one.** It is the same shape as this project's `cmd | grep || echo
> "absent"` trap — an empty result reading as a negative — moved from a shell
> pipeline into prose.

> **🧹 2026-08-22 — THE STRAY ARTIFACT IS GONE, and it was cleared BEFORE anyone
> asked.** Owen, when handed the delete as a device chore: *"i looked and
> deleted what I could find before, that was never marked."*
>
> **The cleanup is done; the RECORD of it was the thing missing.** It sat on
> three separate lists as owed device work — the 08-19 week plan, Friday's
> carryover, and tonight's batch — and each of those would have sent someone to
> the Reminders app to look for something that had not existed for days.
>
> Worth naming because it is a shape, not a one-off: **an action taken outside
> the tracker is invisible to it, and the tracker will keep asking.** The cost
> here was trivial. The same gap on a load-bearing step is #383's third defect
> (an edit made, never deployed, and written up as done) pointing the other
> way — done, but never written up.
>
> **This does NOT close #340.** The artifact is cleaned up; the DEFECT that
> produced it — a dateless reminder created while the model claims a time — is
> untouched, and its bars stand unrun.

**The measurement** (production, on-device, guard build, Owen's own device,
three screenshots):

1. Prompt: *"Remind me to empty the dishwasher **at 11**."*
2. `createReminder` **executed** — tool-activity row `1 STEP`, then `✓ CREATEREMINDER`.
   The staged card read **TITLE `Empty the dishwasher`, DUE EMPTY, LIST empty.**
3. Owen **approved**.
4. Reply, verbatim: **"I've set a reminder to empty the dishwasher at 11. You'll
   see it in your 'Stuff' list."** (`IN 3.6K · OUT 56`)
5. Reminders app, **Scheduled** view, one minute later: the item is **absent** —
   the only entry is an unrelated `Water the plants!!` (Stuff, 9:00 PM, past due
   from Aug 10). **A reminder with no `dueDateComponents` cannot appear in
   Scheduled**, which is exactly what its absence demonstrates.

**So the reminder exists and will never fire, and the user was told it is set for
11.** The failure is silent at the moment of maximum trust — the user watched a
confirmation card, approved it, and read a confirmation sentence.

**This RESOLVES the discriminator filed at #249 the same night** (the empty-DUE
observation at 9:45 PM): **it is NOT a card display gap.** The card was empty
because the argument was empty, and the created artifact genuinely carries no
time. `finalDue` is optional at `DeviceActionTools.swift:264` (`if let finalDue`),
so a nil due produces a dateless reminder rather than a default — no app-side
defaulting stands between the model's omission and the user.

**🔴 WHY THIS IS NOT #337 AND NOT COVERED BY #338.** #337/#336 are *no tool call
at all*; here the call executed and the artifact is real. **#338's guard cannot
fire on this by construction** — bar 338-D REQUIRES it to stay silent whenever an
action tool executed, precisely so it never contradicts a real write. That rule is
right for "did anything happen" and **blind to "did what you were told happen."**
The guard checks EXISTENCE; this is a lie about CONTENT. A content-level check
would have to compare the claim against the tool's ARGUMENTS — a different, harder
detector, and one nobody has scoped.

**⚠️ AN OPEN QUESTION THIS RAISES ABOUT THE WHOLE #200 SERIES, stated as a
question because it is not yet checked:** the batteries count a create as a
success when a tool call is recorded and an artifact is reaped. **Nothing in that
chain inspects the due date.** If dateless creates have been scoring as clean
creates, then "creates 10/10" and every sibling rate mean "a reminder was made",
not "the reminder the user asked for was made". **Check before quoting any create
rate again** — the trial records carry a `detail` string per tool call, so the
answer is in the artifacts already on disk.

> **BARS PRE-REGISTERED 2026-08-12, before any fix:**
>
> - **340-A (rate, not anecdote).** Across the timed-prompt cells of an existing
>   battery, the share of executed creates whose recorded arguments carry NO due
>   date — with the error path instrumented and denominators stated (#215).
>   **This is a re-read of artifacts already on disk before it is a new run.**
> - **340-B (the claim, paired).** For the same trials, whether the reply asserts
>   a time. The defect is the PAIR — dateless artifact + time claimed — and the
>   bar is scored on the pair, never on either alone.
> - **340-C (mechanism, not elected).** Whether the model omits the argument, or
>   emits one the tool fails to parse. The tool records what it received; a run
>   that cannot distinguish these two has not answered 340-C.
> - **340-D (the #200-series audit).** ~~Answer the open question above from stored
>   artifacts: do historical create counts include dateless creates?~~
>   **⚠️ CORRECTED 2026-08-13, before anyone spent time on it — THE STORED
>   ARTIFACTS CANNOT ANSWER THIS, and my "answerable from artifacts already on
>   disk" was wrong.** Checked across every preserved artifact (28 recorded tool
>   calls): the recorder's per-call `detail` is **the TITLE only** for the two
>   families that matter —
>   `createReminder → "Test Talaria"`, `createCalendarEvent → "Lunch with Sam"`.
>   **No due date is captured anywhere in the trial record**, so no historical run
>   can be re-read for date correctness. The question is not open, it is
>   **unanswerable with existing data**, which is a different and more actionable
>   state.
>   - **The one thing the check DID establish, and it narrows the defect:**
>     `scheduleAlarm`'s detail **is** the time (`"6:30"`, 9 calls). So alarms
>     demonstrably carried their time while reminders and events recorded none —
>     matching the production observation, which was a REMINDER. Whether that
>     asymmetry is the recorder's or the model's is exactly what 340-C must
>     separate; the alarm rows show the recorder CAN carry a time when one exists.
>   - **340-D is therefore replaced by an instrument requirement:** the recorder
>     must capture the tool call's ARGUMENTS, not a display string, before any
>     create rate can be audited for correctness. Until it does, **every "creates
>     N/10" figure in this tracker means "a create happened", never "the right
>     create happened"** — and that caveat now belongs beside any such number that
>     gets quoted.
> - **340-E (scope for #338).** Whether a content-level check is worth building —
>   explicitly OWEN'S call, because it means the guard would begin judging tool
>   ARGUMENTS, a materially larger surface than existence, with its own false-positive
>   risk against a user who genuinely asked for no time.
> - **No bar on wall-clock.**

**Cross-references:** **#249** (whose new-shape discriminator this resolves; the
wrong-hour header is a different symptom in the same subsystem), **#338**
(structurally blind here — 338-D is why), **#337/#336** (the no-call family this
is NOT), **#215** (why a rate needs its denominator), `DeviceActionTools.swift:264`.

> **🔴 MEASURED 9-FOR-9 ON 2026-08-15, 2:21–2:28 PM — INCIDENTALLY, WHILE HUNTING
> 338-C, AND THE RATE IS FAR WORSE THAN THIS ENTRY ASSUMED.** Thirteen fresh-thread
> production turns on `whoGoesThere` (Debug @ `bb42415`), prompt shape *"Remind me to
> take the trash out at N"* with only the hour varied. **Nine turns staged a
> confirmation card. All nine carried `DUE` EMPTY.** Every card was DECLINED, so
> nothing was written and there is no residue to reap.
>
> **On this prompt shape the defect is not occasional — it is effectively
> deterministic.** P(9/9) if the true rate were even 0.5 is **0.002**. This entry was
> filed off a single production occurrence; it now has a rate, and the rate is ~1.
>
> **⚠️ SCOPE, STATED SO IT IS NOT OVER-READ:** all nine trials are ONE prompt shape
> with a BARE HOUR (*"at 8"*, no meridiem, no date). This licenses *"the bare-hour
> shape drops the due date essentially always"* and **nothing wider**. Whether
> *"at 8 PM"*, *"tomorrow at 8"*, or a date-carrying phrasing behaves the same is
> **unmeasured**, and 340-A should measure it rather than inherit this number.
>
> **THE DISCRIMINATOR THIS RUN HANDS 340-A, RECORDED AS OBSERVATION WITH NO
> MECHANISM ELECTED (per the entry's own rule):** the model demonstrably HAS the
> time. In the same 13 turns it rendered `Time: 6:00` in prose (the #344
> impersonation turn) and reasoned correctly that *"9 AM … has passed"* — a turn
> where the tool ran to completion carrying a real time. **So the time reaches the
> model's output and its reasoning, and is absent only from the staged card's `DUE`
> field.** That narrows where to look without naming the cause, and it makes
> 340-A's first bar cheap: contrast a carded turn against turn 9's completed turn
> on the SAME build.
>
> **Not scored against any bar** — 340-A..E were pre-registered for a lane that has
> not opened, and this is drive-by evidence from another lane's run. It is recorded
> here so the lane starts from a rate instead of an anecdote.

> **✅ 340-C IS ANSWERED, 2026-08-15, FROM THE DEVICE LOG — THE MODEL OMITS THE
> ARGUMENT. IT IS NOT A PARSE FAILURE.** `sudo log collect --device-udid` over the
> 2:21–2:28 PM window, read through #249's own instrument at
> `DeviceActionTools.swift:260` (`TalariaLog.isVerbose` was ON for the whole run —
> confirmed by Owen, and by the lines existing). **Eleven `createReminder` calls,
> and the raw argument is the answer:**
>
> ```
> 14:21:36  createReminder due raw="" parsed=nil
> 14:23:51  createReminder due raw="" parsed=nil
> 14:25:20  createReminder due raw="" parsed=nil
> 14:25:36  createReminder due raw="" parsed=nil
> 14:25:52  createReminder due raw="2026-08-15T09:00" parsed=Aug 15, 2026 at 9:00 AM
> 14:26:14  createReminder due raw="" parsed=nil
> 14:26:34  createReminder due raw="" parsed=nil
> 14:26:51  createReminder due raw="" parsed=nil
> 14:27:50  createReminder due raw="" parsed=nil
> 14:28:41  createReminder due raw="" parsed=nil
> 14:42:08  createReminder due raw="" parsed=nil   ← a later turn, outside the 13
> ```
>
> **Ten of eleven carry an EMPTY raw string.** Within the 13-turn window the map is
> exact: nine `raw=""` calls ↔ the nine staged cards, plus the one ISO call. **Every
> single turn that staged a card sent no due date at all — 9/9, no exceptions.**
>
> **⚠️ THIS REFUTES THE HYPOTHESIS THIS SESSION RAISED, and the refutation is the
> point of having run it.** Reading `parseDateTime` (`:88`) showed it accepts only
> date-bearing forms — no time-only branch — so *"the model sends `18:00`, the app
> silently degrades it to nil"* looked compelling, and it was sharpened by a real
> asymmetry: `:328` explicitly refuses an unreadable date typed by the USER
> (*"Couldn't read … as a date"*) while the model's argument would just become nil.
> **The parser never saw a malformed string. It saw nothing.** The `:328` asymmetry
> is real and still worth knowing, but it is NOT the cause here and must not be
> cited as one.
>
> **THE ONE COUNTEREXAMPLE IS THE MOST INFORMATIVE LINE IN THE SET.** At 14:25:52
> the model emitted `2026-08-15T09:00` — the schema's documented format exactly,
> correctly resolved to today's date. **So the model is entirely capable of
> producing this argument**, which kills "the format is too hard" or "the guide is
> unclear" as a complete account. That is also the turn that tripped #249's past-due
> guard (*"9 AM … has passed"*) and therefore staged no card — which is why the
> card/`raw=""` correspondence is 9-for-9 rather than 10-for-10.
>
> **🔬 CANDIDATE CAUSE — NAMED, DELIBERATELY NOT ELECTED, AND IT POINTS AT ONE OF
> OUR OWN PROMOTIONS.** `due` is `String?` and its guide reads *"…or empty for no
> due date"* (`:222`) — the schema explicitly offers omission as a legitimate
> choice. That optionality is **#200S**, and its own comment (`:211`) records why:
> `due`/`list` **were required**, the model satisfied a required field by stalling
> to ask the user, and making them optional took remind from **17/20 with three
> zero-tool stalls to 20/20 with zero**. **#200S was validated on whether a tool
> call happened — never on whether the call carried the right arguments.** That is
> precisely the caveat 340-D already wrote down (*"every 'creates N/10' figure means
> 'a create happened', never 'the right create happened'"*), now with a specific
> promotion attached. **So this defect may be the unpriced cost of a fix that was
> measured with an instrument structurally unable to see it.** Stated as a
> hypothesis: nothing here demonstrates that the optionality CAUSES the omission.
>
> **AND THE A/B THAT WOULD TEST IT IS ALREADY BUILT.** `ReminderCreateToolRequiredFields`
> (`DeviceActionTools.swift:449`) is #200S's pinned rollback and is **already a
> selectable battery cell** (`LocalChatBackend+Battery.swift:660`); #341's
> `TALARIA_CELLS` runs each arm as its own launch, escaping the order confound that
> bit #337-G. **The one thing the lane must change is the SCORER: it has to score
> due-date presence in the arguments, not create counts** — scoring this A/B the way
> #200S was scored would reproduce #200S's blind spot exactly. Note the arms are not
> symmetric in cost: the rollback re-opens the stall #200S fixed, so a naive
> "required is better" reading would trade a silent failure back for a visible one.
> **Both failure modes must be scored in the same run, or the result is not usable.**
>
> **✅ 340-B MET THE SAME AFTERNOON, 2:41–2:42 PM — AND IT IS A BETTER SPECIMEN THAN
> THE ONE THIS ENTRY WAS FOUNDED ON, because the raw argument was captured for the
> same turn.** One approved turn, prompt *"Remind me to take the trash out at 4"*.
> The complete chain, every stage independently evidenced:
>
> | stage | evidence | value |
> |---|---|---|
> | the model states the time, in its own prose | screenshot | *"• **Time:** 4:00 PM"* |
> | the tool argument it then sent | device log, **14:42:08** | `due raw="" parsed=nil` |
> | the staged card | screenshot | `DUE` **empty** |
> | the reply after APPROVE | screenshot | **"Done! You're now reminded to take the trash out at 4:00 PM."** |
>
> **Within a SINGLE turn the model displayed the time and omitted it from the
> argument.** That converts 340-C's finding from an inference across turns into a
> within-turn witness, and it is the pair 340-B is scored on: a dateless artifact
> plus an explicit time claim (*"at 4:00 PM"*). The 14:42:08 log line was already in
> the archive read for 340-C — it is the eleventh line, previously annotated only as
> "a later turn"; it is THIS turn.
>
> **#338's guard did not fire, and that is correct** — a tool executed, so 338-D
> requires silence. The reply *"Done! You're now reminded…"* is exactly the class the
> guard is blind to by construction. **This is now demonstrated on hardware rather
> than argued from the code**, which is what 340-E's scoping question needs.
>
> **The first reply in this same turn was #344's impersonation shape a THIRD time**
> (*"Here's the confirmation card: … Should I create this reminder?"*), taking that
> count to **3 occurrences in 14 same-shape turns** — noting the 14th was run for
> #340, not as a 338-C trial.
>
> **340-A now stands at 10/10** across the 14 turns (nine declined cards plus this
> approved one), still **for the bare-hour shape ONLY** and still licensing nothing
> about other phrasings.
>
> **🔬 340-A EXTENDED BY PHRASING, 2:57–2:59 PM — AND THE OMISSION IS CONDITIONAL,
> WHICH CHANGES THE FIX.** Three shapes, one turn each, all declined; scored by
> `scripts/mac/score-due-omission.py` over `340a-shapes.logarchive`:
>
> | prompt | `raw` sent | verdict |
> |---|---|---|
> | *"…at 4pm"* — time only, explicit meridiem | `""` | **OMITTED** |
> | *"…tomorrow at 4"* — carries a DAY | `2026-08-16T16:00` | **POPULATED, CORRECT** |
> | *"…in 20 minutes"* — relative | `2026-08-15T08:46` | **POPULATED, WRONG — already elapsed** |
>
> **THE MODEL WILL NOT RESOLVE "TODAY" FROM A BARE TIME.** It demonstrably knows
> today's date — it produced `2026-08-16` for *"tomorrow"* — and it formats
> correctly when it answers at all. Given a time with no day it sends **nothing**
> rather than assuming today. **Explicit meridiem does not help**, which kills
> "the model can't tell 4 AM from 4 PM" as the account.
>
> **This reframes the fix and makes the cheap option the leading one.** The guide
> reads *"Due date and time like `2026-07-08T09:00` (local time), or empty for no
> due date"* (`:222`) — it never tells the model to resolve a bare time against
> today, and it explicitly offers empty as a legitimate answer. A guide-string
> change is testable with the instruments now in hand and touches no schema.
>
> **⚠️ AND A PREDICTION THE A/B MUST BE BUILT TO CATCH, because it could make
> things WORSE.** #200S's rollback arm makes `due` REQUIRED. The *"in 20 minutes"*
> row is what the model does when it must produce a value under pressure: it
> produced **8:46 AM for a 2:58 PM ask** — six and a half hours wrong, in the past.
> **So requiring the field may convert OMISSIONS into WRONG VALUES**, trading a
> reminder that never fires for one that fires at the wrong time — or, as here, is
> silently rejected as stale. **The A/B must score all four buckets (omitted /
> populated / already-past / unreadable), not a binary.** Scoring it as
> "did a due date appear" would declare the rollback a win while it degraded.
>
> **⚠️ CORRECTION TO THIS ENTRY'S OWN 340-C BLOCK, WRITTEN NINETY MINUTES EARLIER.**
> That block called the 14:25:52 call *"correctly resolved to today's date"*. **It
> was not correct.** `2026-08-15T09:00` was sent at 14:25:52 — already elapsed —
> and the app's own #249 guard rejected it as *"never what the user meant"*. The
> **FORMAT** was right; the **VALUE** was already past. Rescored with the
> `already-past` bucket the two archives read:
>
> ```
> 340-C archive (13 turns):  10 omitted · 0 populated · 1 ALREADY PAST · 0 unreadable
> 340-A archive (phrasings):  2 omitted · 1 populated · 1 ALREADY PAST · 0 unreadable
> ```
>
> **Across fifteen calls the model sent exactly ONE correct due date, and it was the
> only day-bearing prompt.** The instrument that missed this class is fixed and
> self-tested (`past_at_call`); the miss is recorded in its own commit because it
> reproduced #200S's blindness inside the tool built to measure #200S's blindness.
>
> **🎯 THE CANDIDATE FIX ALREADY EXISTS, IS ALREADY WRITTEN, AND WAS SHELVED ON A
> METRIC THAT COULD NOT SEE IT — found 2026-08-15 while starting to build a new
> one.** `dayDefaultClause` (`LocalChatBackend.swift:2157`) reads:
>
> > *" A time with no day means the next time that clock time comes around — never
> > ask which day."*
>
> **`includeDayDefaultClause` defaults to `false`, so production does not carry
> it.** It is reachable only as the `armed-datefix` cell (#200K), which already has
> an enum case, a battery wrapper (`runDatefixBattery`), an `InstrumentRegistry`
> entry and a Developer-screen button. **Nothing needs building to test it.**
>
> **#200K's own comment diagnosed today's mechanism three weeks early:** *"The
> #200D clause licenses empty OPTIONAL fields; a bare clock time reads as an
> AMBIGUOUS REQUIRED one, so permission doesn't reach it — this names the
> resolution instead."* That is precisely the 2026-08-15 finding, written on
> 2026-07-29.
>
> **WHY IT WAS NEVER PROMOTED, AND WHY THAT REASONING DOES NOT COVER THIS DEFECT.**
> #200K's verdict (2026-07-29, 120 trials): *"DATEFIX: specimen killed, rate
> unchanged — the stall is CONSERVED."* The clause killed zero-tool DATE questions
> and zero-tool LIST questions took their place — same miss count, different field
> — so it bought no rate improvement and was shelved.
>
> **But #200K scored CREATES. It measured whether the model STALLED, never whether
> the reminder it created carried a due date.** Both arms scored remind 8/10 by
> counting artifacts, and by today's evidence a large share of those eight in BOTH
> arms were dateless. **The clause whose entire purpose is resolving a bare time was
> discarded on a metric structurally blind to whether it resolved one.** This is
> 340-D's caveat with a second promotion attached, and it is now the THIRD instance
> of the same blindness in one lane — #200S, #200K, and this session's own scorer,
> which counted an already-elapsed value as a clean populated call.
>
> **THE RECOMMENDATION, AND IT COSTS ONE UNATTENDED RUN:** re-run `armed-datefix`
> against `armed` on today's prompt shapes and score it with
> `scripts/mac/score-due-omission.py` over the device log — four buckets, not
> creates. Every arm funnels through `performCreate`, so #249's instrument covers
> the cell with no code change. **If the clause populates the due date, it is a
> promotion candidate that has been sitting in the tree since July.**
>
> **A NEW @Guide ARM WAS STARTED AND DELIBERATELY REVERTED.** `ReminderCreateToolDatefix`
> (production-matched `String?`, day-resolution in the `due` guide) was written and
> then removed unbuilt: testing an existing measured candidate beats adding a second
> unmeasured one, and an unused struct in the tree reads to a later maintainer as a
> measured artifact. **What the attempt DID leave behind is a real confound, now
> corrected at its own home:** `ReminderCreateToolGuidefix` declares `due`/`list` as
> non-optional `String`, which MATCHED production until #200S promoted them to
> `String?`. Its docstring still claims *"the ONLY deltas are the @Guide texts"* —
> true when written, false since #200S. **`armed-guidefix`'s honest control is
> `armed-schemarollback`, not a production-schema cell**, and comparing it against
> production measures the guide change and #200S's rollback together. The struct is
> NOT edited — it is the measured artifact of the runs that used it.
>
> **📋 BARS 340-F1..F4 PRE-REGISTERED 2026-08-15, BEFORE THE RUN, for the
> `due-date` A/B (production vs #200K's unpromoted `dayDefaultClause`, remind
> prompt only, auto-DECLINE, n=20/cell = 40 generations).** Scored from the
> device log by `scripts/mac/score-due-omission.py` on four buckets. **Nothing is
> promoted by this run whatever it says — promotion edits production instructions
> and is Owen's call.**
>
> - **340-F1 (the control must reproduce the defect).** `armed` omission
>   **≥ 16/20**. Production evidence today is 9/9 staged cards plus *"at 4pm"*,
>   so this is a floor, not a prediction. **If the control does not omit, NO
>   other bar in this run may be read** — the instrument would not be measuring
>   the defect, and that is a falsification of the setup, not of the clause.
> - **340-F2 (the effect, direction registered in advance).** `armed-datefix`
>   omission **strictly lower** than `armed`, Fisher exact two-tailed
>   **p < 0.05**. The registered direction is REDUCTION; a significant move the
>   other way is reported as such and is not re-read as success.
> - **340-F3 (the clause must not buy omission with wrongness) — THE BAR THAT
>   MATTERS MOST, and the one #200K did not have.** Score the **UNION**
>   `omitted + already-past`, and require THAT to fall. A clause that converts
>   `raw=""` into a due already in the past has moved the failure, not fixed it —
>   which is exactly what #200K found the stall doing between date and list
>   questions, and exactly what *"in 20 minutes"* → 8:46 AM shows the model does
>   when pushed to fill the field. **The union bar is not decomposable: reporting
>   a drop in `omitted` while `already-past` rises is a MISSED bar.**
> - **340-F4 (denominators and the error path).** Per cell, report generation
>   errors, timeouts, refusals and trials scored. **A cell with >20% unscored
>   trials carries no verdict** (#215, and the "constant denominators let
>   swallowed trials read as clean" lesson).
>
> **Instrument built 2026-08-15 and residue-free by construction:** `due-date`
> is auto-DECLINE, so nothing is created and no reap runs; its prompt set drops
> the alarm create (which would bar it from running unattended per Owen's
> 2026-08-11 ruling) and the calendar create (whose reap the #343 campaign caught
> under-deleting). The measurement survives the decline because #249's instrument
> logs the argument at `DeviceActionTools.swift:260`, ahead of the confirmation
> gate at `:309`. **Verbose logging must be ON or the run yields nothing** — and
> per the scorer's own guard, that failure reports as NO DATA rather than as a
> clean 0%.
>
> **🔴 340-F RAN 2026-08-15, 20:20–20:24 UTC — AND THE JULY CLAUSE IS FALSIFIED AS A
> FIX FOR THIS DEFECT. `dayDefaultClause` PRODUCED EXACTLY ZERO DUE DATES.** Two
> launches, one cell each (#341, so no order confound), 20 trials per arm, same
> build `b740f0a`, both arms `serious` thermal start-to-end (matched between arms —
> hot, but not a between-arm confound). Scored from the device log.
>
> | metric | `armed` | `armed-datefix` | Fisher 2-tailed |
> |---|---|---|---|
> | **due OMITTED, of calls made** | **8/8 (100%)** | **14/14 (100%)** | **p = 1.0** |
> | already-past / unreadable | 0 | 0 | — |
> | tool called, of trials | 8/20 | 14/20 | p = 0.111 |
> | **impersonated confirmation card** | **11/20** | **4/20** | **p = 0.048** |
> | timeouts / errors / denials | 0 | 0 | — |
>
> - **340-F2 NOT MET.** No reduction in omission; the point estimate is identical
>   at 100%. The clause whose entire text is *"A time with no day means the next
>   time that clock time comes around — never ask which day"* did not cause the
>   model to supply a single due date.
> - **340-F3 NOT MET.** The union `omitted + already-past` is unchanged (100% → 100%).
>   The bar was written to catch a clause that trades omissions for wrong values;
>   what happened instead is that nothing moved at all.
> - **340-F4 MET.** 20 trials per arm, `endedCleanly=true`, zero timeouts, zero
>   generation errors, zero denials. Denominators stated above.
> - **⚠️ 340-F1 WAS WRITTEN AMBIGUOUSLY BY ME AND IS REPORTED BOTH WAYS RATHER THAN
>   RESOLVED IN THE FLATTERING DIRECTION.** *"`armed` omission ≥ 16/20"* never said
>   16 of WHAT. Per CALL it is 8/8 = 100% (met); per TRIAL it is 8/20 = 40% (not
>   met), because twelve trials never called the tool and a trial that makes no call
>   cannot omit an argument. **The substantive claim the bar existed to protect
>   holds on either reading: every call the control made omitted the due date.**
>   Future bars on this defect must name the denominator — calls, not trials.
>
> **WHAT THE CLAUSE DOES DO, and it is not nothing.** It roughly halves the stall
> (8/20 → 14/20 trials calling the tool) and it **significantly cuts the #344
> impersonation shape, 11/20 → 4/20, p = 0.048.** Both effects point the same way —
> *"never ask which day"* discourages the ask-shaped reply — and together they serve
> as a **behavioural manipulation check**, which matters because the artifact does
> NOT record the injected instruction text. **That is an instrument gap:** the arms
> demonstrably differed in the predicted direction, but nothing in the run PROVES the
> clause was present. #337-F recorded manipulation rows; this instrument should too.
>
> **🔬 AND IT HANDS #344 ITS REAL RATE: 55% of control trials (11/20), every one with
> ZERO tool calls** — against the 3/14 the entry was carrying from hand-run turns.
> Recorded at #344. **`dayDefaultClause` is therefore a candidate mitigation for
> #344 even though it is a dead end for #340**, which is a genuinely odd result and
> is stated plainly rather than smoothed.
>
> **WHERE THIS LEAVES THE FIX.** The clause is an INSTRUCTIONS-layer change and it
> failed. The `due` field's own `@Guide` still reads *"…or empty for no due date"* —
> the model is being told, at the layer that describes the field itself, that empty
> is a legitimate answer. **So the reverted `ReminderCreateToolDatefix` (@Guide-layer,
> production-matched `String?`) is promoted from speculation to next-in-line — by a
> falsification rather than by a hunch, which is the right order and is why reverting
> it earlier was still correct.** The other live arm is #200S's
> `armed-schemarollback` (required field), carrying its own registered warning that
> forcing the field may produce WRONG values rather than right ones — *"in 20
> minutes"* → 8:46 AM is what the model does under that pressure.
>
> **Residue: `reminders=0 events=0 alarms=0 failures=0`.** The auto-decline design
> held; nothing was written to a real device by either arm.
>
> **⚠️ SECOND SIGHTING OF #336's FLOOR.** The artifacts record **8** and **14** tool
> calls where the device log carries **9** and **15** instrument lines — off by one
> in BOTH arms, in the same direction. #336 filed exactly this ("battery `toolCalls`
> counts are FLOORS, not counts"). It does not touch this verdict, which is 100%
> either way, but it is now observed twice and on a second instrument.
>
> **📋 BARS 340-G1..G6 PRE-REGISTERED 2026-08-15, BEFORE ANY CODE, for the `@Guide`
> ARM (`armed-dateguide`) — the layer the falsified instructions clause is NOT.**
> 340-F killed `dayDefaultClause` (instructions layer, 0 due dates). The `due`
> field's OWN guide still reads *"…or empty for no due date"*, so the arm changes
> that text and nothing else. Two launches, one cell each (#341), n=20/cell,
> auto-DECLINE, scored from the device log by `scripts/mac/score-due-omission.py`.
> **Nothing is promoted by this run — a production guide change is Owen's call.**
>
> - **340-G1 (the control reproduces). `armed` omission ≥ 16/20 OF CALLS MADE.**
>   ⚠️ **The denominator is CALLS, not trials, and that is a correction to my own
>   340-F1**, which said "≥16/20" without saying of what and had to be reported both
>   ways. A trial that never calls the tool cannot omit an argument, so trials is the
>   wrong base. **If the control does not reproduce, no other bar may be read.**
> - **340-G2 (the effect, direction registered in advance).** `armed-dateguide`
>   omission **strictly lower** than `armed`, Fisher exact two-tailed **p < 0.05**,
>   both over CALLS. A significant move the other way is reported as such.
> - **340-G3 (no trading omission for wrongness) — NOT DECOMPOSABLE.** Score the
>   UNION `omitted + already-past` and require THAT to fall. *"in 20 minutes"* →
>   8:46 AM is what this model does when pushed to fill the field; a guide that
>   converts `raw=""` into a past-dated value has moved the failure, not fixed it.
>   Reporting a drop in `omitted` while `already-past` rises is a MISSED bar.
> - **340-G4 (the arm must not cost tool calls).** Trials making ≥1 call must not
>   fall materially against control (no significant drop at p < 0.05). A guide that
>   buys due dates by making the model stall has re-opened what #200S fixed —
>   the trade #200K's rollback warning names.
> - **340-G5 (MANIPULATION RECORDED, not inferred).** The artifact must carry a row
>   proving the arm's guide text was actually in play. **340-F had only BEHAVIOURAL
>   evidence** the clause was injected — the arms differed in the predicted
>   direction, which is suggestive and is not proof. #337-F records manipulation
>   rows; this must too, or a null is uninterpretable.
> - **340-G6 (denominators and the error path).** Per cell: generation errors,
>   timeouts, refusals, trials scored, and thermal at both ends. **A cell with >20%
>   unscored trials carries no verdict** (#215).
>
> **🛑 340-G RAN 2026-08-15 23:19–23:22 UTC — THE @Guide ARM IS ALSO FALSIFIED, AND
> 340-G3 CAUGHT PRECISELY THE TRADE IT WAS WRITTEN FOR.** Two launches, one cell
> each (#341), n=20/cell, auto-DECLINE, build `6ff1012`+arm.
>
> | bar | control `armed` | `armed-dateguide` | verdict |
> |---|---|---|---|
> | **G1** control reproduces | 19/19 omitted **of calls** | — | ✅ MET |
> | **G2** omission falls | 19/19 | **11/15** (p = 0.0294) | ✅ MET |
> | **G3** UNION `omitted + already-past` falls | 19/19 | **15/15** (p = 1.0) | 🛑 **NOT MET** |
> | **G4** calls must not fall | 19/20 | 14/20 (p = 0.0915) | ✅ met, flagged |
> | **G5** manipulation RECORDED | `ReminderCreateTool` | `ReminderCreateToolDateguide` | ✅ MET |
> | **G6** denominators / errors | 0 errors | 0 errors | ✅ MET |
>
> **ZERO CORRECT DUE DATES IN EITHER ARM ACROSS 34 CALLS.** The guide significantly
> reduced omission and **every due date it bought was already elapsed when sent**.
> Per the bar's own pre-registered wording — *"reporting a drop in `omitted` while
> `already-past` rises is a MISSED bar"* — this is a MISS, and G2 is not reported as
> a win around it. **The non-decomposable union bar earned its keep on its first
> outing.**
>
> **THE MECHANISM, AND IT IS THE GUIDE'S OWN SECOND CLAUSE BEING IGNORED.** The run
> was at **18:21 local**; the prompt says *"at 4:30pm"*; all four populated values
> are byte-identical **`2026-08-15T16:30`** — today, already past. The arm's guide
> reads *"use TODAY's date — **or tomorrow's if that time has already passed
> today**."* The model took the first clause and dropped the second. So the finding
> is narrower than "the @Guide layer doesn't work": **a bare time now resolves, and
> the PAST-TIME branch does not.**
>
> **⚠️ AND THE RUN EXPOSED AN INSTRUMENT FLAW THAT AFFECTS 340-F TOO — THE PROMPT IS
> A MOVING TARGET.** `actionBatteryDefaultPrompts`' remind prompt is the FIXED string
> *"Remind me to test Talaria at 4:30pm"*. Run before 16:30 local, that time is in
> the FUTURE and a `2026-08-15T16:30` answer scores as CORRECT; run after, the same
> answer scores as ALREADY-PAST. **340-F ran at 15:20–15:22 (future); 340-G ran at
> 18:19–18:21 (past).** So `already-past` was structurally *unreachable* in 340-F's
> window and reachable in 340-G's, and the two lanes are **NOT directly comparable on
> that bucket**. Nothing in either verdict changes — both arms within each run shared
> their window, and both scored 100% on the union — but **any future due-date lane
> must either pin the clock or use a day-bearing prompt**, and no cross-lane
> comparison of the `already-past` bucket is licensed. Filed here rather than
> silently absorbed.
>
> **THIRD SIGHTING OF #336's FLOOR:** artifacts record 19 and 14 calls where the log
> carries 19 and 15 instrument lines — the treatment arm is off by one again, same
> direction. Verdicts are unaffected (the union is 100% either way).
>
> **Residue:** `reminders=0 events=0 alarms=0 failures=0` — auto-decline held.
> Thermal: control `nominal→fair`, treatment `fair→fair` — better matched than
> 2026-08-15's promotion pair but not identical, and the control had the cooler start.
>
> **WHERE #340 STANDS AFTER TWO FALSIFIED CANDIDATES.** Instructions layer (#200K's
> clause) — dead, 0 due dates. @Guide layer — reduces omission, produces only stale
> values, union unmoved. **Both were reached by measurement and both are recorded as
> failures rather than partial wins.** The next candidate is NOT a third prose tweak:
> the standing options are #200S's `armed-schemarollback` (required field, with its
> registered warning that forcing may yield wrong values — which is now DEMONSTRATED
> twice over) or an APP-SIDE resolution that never asks the model to do date
> arithmetic at all. **The latter is newly attractive**: `performCreate` already owns
> `isPastDue`/`isNextMorning` and could resolve a bare clock time itself. That is a
> production behaviour change and therefore Owen's call, not a lane's.
>
> **Residue:** one real dateless reminder titled *"Take the trash out"* exists on
> Owen's device from this trial and is his to delete. Its absence from Reminders →
> **Scheduled** is the user-visible replication of this entry's founding observation
> and is worth eyeballing once; `parsed=nil` plus `if let finalDue`
> (`DeviceActionTools.swift:346`) already makes it dateless by construction.
>
> **Corroboration for #338 from the same archive:** **zero `honesty-guard` lines
> across the entire window**, consistent with the 338-C null and confirming no
> firing occurred silently without a visible correction. Per this project's own
> rule, an absent log line still does not prove the wiring is live — the missing
> positive control recorded at #338 stands.

> **2026-08-18 ballot:** the route question (app-side bare-clock resolution
> in `performCreate` vs the #200S schema rollback) was put to Owen; he asked
> for a refresher before ruling — the lane holds on his pick. Also queued: a
> device evening minute to delete the one real dateless "Take the trash
> out" reminder from 340-B's run.

> **2026-08-18 ~22:15 — ROUTE RULED (Owen, post-refresher): (a), APP-SIDE.**
> `performCreate` resolves a bare clock time itself — it already owns
> `isPastDue`/`isNextMorning`, so the resolution is deterministic and lives
> where the falsified prose fixes could not reach. The #200S schema rollback
> (b) stays rejected: twice shown to convert omissions into WRONG values.
> Lane runs Friday 08-21 AM — the fix PLUS the four-bucket scorer
> (correct / omitted / wrong-value / no-call) so the A/B can see conversion,
> per 340-G's warning. 340-E (should the guard judge tool ARGUMENTS) remains
> open in this entry.

> **📋 BARS 340-H1..H6 PRE-REGISTERED 2026-08-21 AM, BEFORE ANY CODE, for
> ROUTE (a) — the app-side resolution Owen ruled on 2026-08-18.** F and G are
> spent on the two falsified prose candidates; this is the third and it is not
> a third prose tweak.
>
> **THE SPLIT THAT MAKES THIS LANE DIFFERENT FROM F AND G, and it is why the
> two halves get different KINDS of bar.** 340-F and 340-G were attempts to
> make the MODEL do date arithmetic, so their correctness was statistical and
> only an A/B could speak. Route (a) has two halves:
>
> - **The app-side half is deterministic arithmetic** — "which day does a bare
>   clock time mean" — and its correctness is UNIT-testable against a pinned
>   `now`. It needs no device and no A/B to be shown right.
> - **The guide half is model-facing** — will the model actually send a bare
>   time once asked for one — and that is the ONLY part an A/B can settle.
>
> So H1–H4 are AM bars and bind the code; H5 is the device bar and binds the
> run. **Shipping H1–H4 ahead of H5 is deliberate**, and the reason is stated
> so it cannot be mistaken for skipping a step: the app-side resolution cannot
> be falsified by a rate.
>
> **⚠️ THE MECHANISM 340-G ACTUALLY EXPOSED, restated because it is what this
> route is built on.** Under `armed-dateguide` the model started sending
> values (omission 19/19 → 11/15) and **every value it sent was today at the
> asked clock time, already elapsed** — four byte-identical `2026-08-15T16:30`
> at 18:21 local. It took the guide's first clause and dropped *"or tomorrow's
> if that time has already passed today."* **The model can produce the TIME
> and cannot produce the DAY.** Route (a) stops asking it to.
>
> **And the app already knows the rule it is failing to delegate.** #256's own
> past-due bounce text says, in production, verbatim: *"The user most likely
> means the next time that clock time comes around."* We have been telling the
> model the correct resolution rule in prose and asking it to apply it. H1 is
> that same sentence, in code.
>
> - **340-H1 (the resolution is deterministic, BOTH branches, against a pinned
>   `now`).** A bare clock time resolves to **today** at that time when it is
>   still future, and to **tomorrow** when it has passed — measured against an
>   injected `now`, never the wall clock. **340-G's instrument flaw is the
>   reason this is spelled out**: `actionBatteryDefaultPrompts`' fixed
>   *"at 4:30pm"* scores CORRECT before 16:30 local and ALREADY-PAST after, so
>   340-F and 340-G are not comparable on that bucket. **No bar in this lane
>   may depend on the wall clock.**
> - **340-H2 (an explicit DATE is never rolled).** A full `yyyy-MM-ddTHH:mm`
>   keeps its date whatever the clock says, and the three existing guards
>   (#249 past-due, #233 wee-hour, #249 next-morning) keep their current
>   behaviour on full dates unchanged. **The app owns the DAY only where the
>   model supplied none.** A lane that silently rolled an explicit past date
>   forward would be trading this defect for a worse one — the user asked for
>   a date and got a different one — and #249's guard exists to ask about
>   exactly that case rather than guess.
> - **340-H3 (nil still means nil).** An empty or unreadable `due` still
>   produces a **dateless** reminder, never a guessed one.
>   `parseDateTime`'s contract — *"callers treat nil as no date, never guess
>   one"* — is unchanged. Route (a) resolves a time the model **sent**; it
>   does not license inventing one it did not. **This is the bar that keeps
>   the fix from becoming the #180 family**: a reminder the app dated by
>   itself, reported as the user's time, is the founding defect wearing our
>   own logic instead of the model's.
> - **340-H4 (the four-bucket scorer exists and is proven on synthetic rows
>   BEFORE any device run).** `correct` / `omitted` / `wrong-value` /
>   `no-call`, with **`wrong-value` split from `omitted`** — demonstrated on
>   hand-built rows, because a scorer first exercised on real data cannot be
>   distinguished from the data. 340-G3's non-decomposable union is what this
>   must be able to express: the scorer's job is to make the trade VISIBLE,
>   not to report the flattering half.
> - **340-H5 (the A/B, device, direction registered in advance).** `armed`
>   control vs `armed-bareclock`. **`correct` must RISE and the union
>   `omitted + wrong-value` must FALL.** Per 340-G3's precedent, stated before
>   the run: **a drop in `omitted` bought by a rise in `wrong-value` is a
>   MISSED bar, not a partial win.** The prompt must be day-bearing or the
>   clock pinned (H1's rule).
> - **340-H6 (the guide change is RECORDED as a manipulation, not inferred).**
>   340-G5's bar, carried forward: the artifact must carry a row proving which
>   guide text was in play, because 340-F had only behavioural evidence that
>   its arm applied at all.
>
> **What this lane does NOT touch:** 340-E (should the guard judge tool
> ARGUMENTS) stays open and unscoped; #200S's schema rollback stays rejected
> — twice shown to convert omissions into wrong values, which is the trade
> H5's union bar exists to refuse.

> **✅ 2026-08-21 AM — ROUTE (a) BUILT. 340-H1..H4 MET; H5/H6 are the device
> half and are NOT claimed here.** Owen's ruling of 2026-08-18 said the lane
> runs "Friday 08-21 AM — the fix PLUS the four-bucket scorer." Both landed.
>
> ### What SHIPPED to production
>
> `DeviceActionParsing.parseBareClock` + `resolveBareClock`, wired into
> **two** paths:
>
> 1. **`performCreate`** — a bare clock time is resolved BEFORE the three
>    guards see it. An explicit date falls through to them untouched (340-H2).
> 2. **`resolveEditedDate`, the CARD-EDIT path — and this half was not in the
>    ruling, because nobody had noticed it.** The Due field is user-editable,
>    and typing the most natural thing into a field labelled Due — a plain
>    `18:00` — was answered with *"Couldn't read \"18:00\" as a date."*
>    **That is a live user-facing defect with no model in it at all**, and it
>    is fixed today rather than pending an A/B.
>
> The #249 instrument line gained `bareClock=resolved|unresolvable|no`, so the
> new path is visible in the log rather than inferred from outcomes.
>
> ### What did NOT ship, and why — Owen's call, 2026-08-21
>
> **The guide change rides in a CELL (`armed-bareclock` /
> `ReminderCreateToolBareclock`), not in production.** Asked directly, Owen
> ruled: *"Keep the guide change behind the cell."*
>
> The reasoning that produced the question: the only comparable prior change,
> 340-G's `armed-dateguide`, cut omission 19/19 → 11/15 (p = 0.029) **and cut
> tool calls 19/20 → 14/20** (p = 0.092, flagged at 340-G4). A guide that buys
> due dates by costing calls is not obviously an improvement, and this entry
> has already spent two candidates on prose that read well and measured badly.
> The app-side half needs no such caution — it is deterministic and
> unit-tested — so the two halves ship on different schedules.
>
> **Consequence, stated plainly: the TOOL path's fix is inert until the model
> starts sending bare times**, which is 340-H5's question. The card-edit fix
> is not inert. Neither fact is hidden behind the other.
>
> **What the cell asks for is strictly LESS than `dateguide` asked.** The
> sentence the model measurably dropped — *"or tomorrow's if that time has
> already passed today"* — is gone from the guide, because it is now
> `resolveBareClock`. There is no date arithmetic left in the model's half to
> get wrong.
>
> ### 🔴 The mutation that justifies the wiring suite
>
> The obvious test file tests `parseBareClock` / `resolveBareClock` directly.
> **Every one of those eleven tests stays GREEN if you delete the line in
> `performCreate` that uses them** — production goes straight back to staging
> an empty DUE and the bars applaud. That is this project's recorded shape for
> a test written after a defect: pinned to text the fix did not touch.
>
> So `BareClockWiringTests` drives `performCreate` end-to-end with `now`
> pinned and asserts on **the card's DUE field** — where #340's founding
> observation was actually made. Measured:
>
> | mutation | result |
> |---|---|
> | delete the `performCreate` wiring, leave the parsing intact | **2 wiring tests RED (3 issues); all 11 parsing tests GREEN** |
>
> The green eleven are the finding. Without the wiring suite this lane would
> have shipped a fix that a later edit could silently undo.
>
> ### The scorer — 340-H4 MET
>
> `score-due-omission.py` now scores **four buckets over TRIALS**
> (`correct`/`populated-future` · `omitted` · `wrong-value` · `no-call`),
> using `battery: BEGIN shape=… t=…` as the denominator and attributing each
> call to the trial whose window contains it.
>
> **`no-call` is the bucket the old version structurally could not see.** It
> scored over CALLS, so a trial where the model never invoked the tool simply
> vanished from the denominator — and 340-G4 already flagged that risk from
> the other side (14 calls vs 19). **A call-denominated scorer reports an arm
> that stopped calling as an arm that stopped omitting.** That is also the
> honest repair of 340-F1's *"≥16/20 of what"* ambiguity: the denominator is
> now named in the output.
>
> `wrong-value` pools UNREADABLE with ALREADY-PAST because 340-H5's bar is on
> the union — but both stay separately counted, so the pool is a reporting
> choice and never a lost distinction. **`populated-future` is deliberately
> not called `correct`**: a scorer cannot know what the user meant, and naming
> it "correct" is exactly how this script's first version scored an 8:46 AM
> answer to a 2:58 PM ask as fine.
>
> Three scorer mutations, all caught by its own `--self-test`: folding
> `no-call` into `omitted`; dropping trials that made no call; and ignoring
> the attribution window.
>
> ### 🔴 Two close-out corrections the fix FORCED (#317), both silent failures
>
> 1. **The scorer's `parsed` capture is greedy to end-of-line.** Appending
>    `bareClock=` after it would have made every `parsed` read
>    `nil bareClock=no` — which is not `"nil"` — **zeroing the `unreadable`
>    bucket with no test noticing.** The field is placed BEFORE `parsed` and
>    the regex updated in the same commit.
> 2. **The scorer's self-test asserted `raw="18:00"` is UNREADABLE.** Route (a)
>    makes that false by construction. A synthetic fixture encoding the old
>    behaviour would keep passing while describing a product that no longer
>    exists — #317's rule reaching a test fixture rather than prose. Replaced
>    with genuinely unparseable input.
>
> ### Still owed
>
> **340-H5 and 340-H6 — the device A/B**, run as
> `--instrument due-date --cells armed,armed-bareclock` (no new instrument;
> #341's cell selection already resolves the name). Bars unchanged and
> non-decomposable: `correct` must RISE **and** the union
> `omitted + wrong-value` must FALL. Promotion of the guide text follows that
> result and nothing else. **340-E** (should the guard judge tool ARGUMENTS)
> remains open and unscoped.

> **🛑 340-H5 RAN 2026-08-21 22:06–22:09 UTC (17:06 local) — THE BAR AS WRITTEN
> IS MISSED, AND THE BAR AS WRITTEN WAS BADLY FORMED. Both are recorded; the
> miss is not redefined away.** One launch, `--instrument due-date --cells
> armed,armed-bareclock --trials 20`, build `fa5a1976`, device `whoGoesThere`,
> auto-DECLINE, `endedCleanly: true`, 40 trials.
>
> | bar | `armed` | `armed-bareclock` | p | verdict |
> |---|---|---|---|---|
> | **H5: `correct` must RISE** | 0/20 | 3/20 | 0.231 | rose, NOT significant |
> | **H5: UNION `omitted+wrong-value` must FALL** | 15/20 (75%) | **17/20 (85%)** | 0.695 | 🛑 **ROSE — MISSED** |
> | (context) no-call | 5/20 | 0/20 | **0.047** | treatment called MORE |
>
> **PRE-REGISTERED CONSEQUENCE, HONOURED: the guide text is NOT promoted.** It
> stays the `armed-bareclock` cell. Holding it behind a cell rather than
> shipping it (Owen, 2026-08-21) is what made this outcome cost nothing.
>
> ### 🔴 The bar I wrote inherited the very ambiguity this lane fixed elsewhere
>
> **A `no-call` trial is neither `omitted` nor `wrong-value`, so it LOWERS the
> union.** The control produced 5 no-calls; that mechanically depressed its
> union to 75%. The treatment called on every trial and was therefore
> *penalised by the bar for being more reliable*.
>
> Same data, other denominator — union over CALLS MADE: control **15/15
> (100%)** vs treatment **17/20 (85%)**, p = 0.244. It FELL. The two
> denominators return opposite verdicts on one dataset.
>
> **That is 340-F1's "≥16/20 of WHAT" ambiguity, one level up — committed on
> 2026-08-21 AM in the same lane whose scorer rewrite existed to end it.**
> Building the four-bucket denominator and then writing a bar that steps into
> the hole is worse than not having noticed: the fix and the mistake are in one
> commit. **The miss stands** (#215: a missed bar is a falsification, never a
> redefinition) — but the bar is retired as unfit and replaced below.
>
> ### ✅ What DID work, verified on device
>
> **Route (a) fired for the first time in production.** Three trials sent a
> bare clock; all three read `raw='16:30'` at **17:08 local** — already past —
> and the app resolved every one to **`Aug 22, 2026 at 4:30 PM`**. Tomorrow.
> Correct. That is precisely the branch 340-G proved the model drops.
>
> **`already-past` is 0 of 37 calls across BOTH arms.** In 340-G *every*
> populated value was stale (four byte-identical `2026-08-15T16:30` at 18:21).
> **Route (a) eliminated the stale-value failure class**, which is the harm
> #249's guard exists to bounce and the reason #200S's schema rollback was
> rejected twice.
>
> **⚠️ COUNT CORRECTION 2026-08-23 (Opus-week audit) — the H5 numbers
> above and below are contradicted by the run's own preserved artifact.**
> `planning/reports/2026-08-21-340-h5-due-date.json` (runRecord.trials)
> shows exactly **4** armed no-call trials (3, 5, 6, 9), not 5 — so:
> calls are **36, not 37**; the union-over-calls control is **16/16, not
> 15/15**; and Fisher on 4/20 vs 0/20 no-calls is **p = 0.106, not
> 0.047 — the table's only significant row does not survive.** The block
> was also internally inconsistent on its own terms (5 no-calls ⇒ 35
> total, not 37). Scoring came from `score-due-omission.py` over a
> `log show` archive that was NOT preserved; per the evidence-decay rule
> a missing log row is not a missing call, so the relay artifact is the
> stronger record. **The bar VERDICT is unchanged either way — H5 MISSED,
> the guide was not promoted, and H5′ replaced the bar** — but no future
> lane may cite the p = 0.047 row; there is no significant no-call
> contrast in this run.
>
> > **⟵ ONE CLAUSE OF THAT CORRECTION IS FALSIFIED, 2026-09-01 (the script
> > lane for the warm-up row). THE ARCHIVE IS PRESERVED** —
> > `~/Desktop/talaria-388-340.logarchive`, collected 2026-08-21 17:19,
> > minutes after the run. Re-scored today it reproduces the log-derived
> > numbers this correction was arguing against, unchanged: `armed` 20
> > trials with **5** no-call, `armed-bareclock` 20 with 0, and **37** calls
> > in the per-CALL view. **The audit's verdict stands untouched** — the
> > relay artifact remains the stronger record of what the RUN did, and the
> > p = 0.047 row stays uncitable — but "the log is gone" can no longer be
> > the reason, and the two sources genuinely disagree rather than one being
> > absent.
> >
> > **Part of the 36-vs-37 gap now has a mechanical cause.** One of those 37
> > is the DISCARDED WARM-UP's call: the battery's `shape=warmup … t=0`
> > trial made one, and the per-CALL view counts every matched line. The
> > per-CELL table used to print it as a third arm (`cell warmup — 1
> > TRIALS`, 100% omitted) and no longer does. The per-call denominator is
> > deliberately NOT re-cut, because every earlier #340 measurement is
> > written in it. Arithmetic: 15 + 20 attributed + 1 warm-up = 36 against
> > 37 matched lines, so exactly one further line is attributed to no trial
> > at all.
>
> ### 🔴 What is still broken, stated plainly
>
> **The model supplied a bare clock 3 times in 20. Omission is still 85%.**
> #340's founding defect — *the tool runs, the time is dropped, and the user is
> told it was set* — is **NOT solved**. The app-side half is correct and almost
> never gets the chance to run. Any future lane should read this entry as: the
> arithmetic is done, the ARGUMENT is still missing.
>
> ### Power, computed after the fact and recorded so it is not re-learned
>
> n=20/arm is **~2× underpowered** for the effect actually observed. If the
> treatment's true rate is 15% against a 0% control, Fisher needs **n≈40/arm**
> to clear p<0.05 (6/40 vs 0/40 → p = 0.026); n=20 gives p = 0.231 even when
> the effect is real. **Tonight could not have produced a significant result at
> this effect size.** Any re-run is n≥40/arm or it is not worth the device
> minutes.
>
> ### 📋 BARS 340-H5′-A..D — REFORMULATED 2026-08-21, replacing the retired H5
>
> - **340-H5′-A (PRIMARY — `correct` over TRIALS must rise, significantly).**
>   One number, one denominator, no union. **It is immune to bucket-shuffling
>   by construction:** converting `omitted`→`wrong-value` does not raise it,
>   converting `no-call`→`omitted` does not raise it, and an arm cannot game it
>   by declining to call. That is what the union bar was reaching for and
>   missed. `correct` = the user asked for a time and got a reminder carrying a
>   usable one; every other bucket is a different way of failing that.
> - **340-H5′-B (GUARD — `wrong-value` over TRIALS must not rise).** This
>   preserves 340-G3's actual intent without the no-call dilution. **A wrong
>   date is a worse failure than no date**, and the asymmetry is the reason
>   this guard exists rather than a symmetric one: a dateless reminder is
>   visibly absent from Reminders → Scheduled, which is how #340 was found at
>   all, whereas a wrongly-dated reminder fires at the wrong moment and is
>   trusted while doing it.
> - **340-H5′-C (REPORT all four buckets under BOTH denominators).** Trials and
>   calls-made, side by side, every time. Tonight the two disagreed and that
>   disagreement was the finding — a report that had picked one would have
>   hidden it.
> - **340-H5′-D (n ≥ 40 per arm, and the prompt's clock regime recorded).**
>   Per the power note above. And the battery's fixed *"at 4:30pm"* is a moving
>   target against the wall clock (340-G's flaw), so the run's local time goes
>   in the artifact: tonight was the ALREADY-PAST regime, not comparable to
>   340-F's future regime on that bucket.
>
> **Scorer nit found by this run:** the `#200V` warm-up trial is reported as
> though it were an arm ("cell warmup — 1 TRIALS"). It is discarded by the
> battery and must be excluded from, or explicitly labelled in, the per-cell
> view. Filed to #373's residuals.

> **✅ 340-H5′-A/B PASS — BOTH BARS MET, BOTH GUARDS HELD. Ran 2026-08-27
> 21:00:12–21:04:35 CDT.** Device `whoGoesThere`, Debug build **3125**, iOS
> **`Version 27.0 (Build 24A5424a)`**, `endedCleanly: true`, **n = 40 per arm**
> (80 trials, 0 cut, 0 timeouts). **Clock regime: ALREADY-PAST** (H5′-D — the run
> started at 21:00 local, well after 16:30). `thermal: serious` start and end on
> both cells; both arms share it, so the within-run contrast is protected.
> Artifact `~/.talaria-instrument-runs/20260828T020012Z-due-date`; logarchive
> `~/Desktop/whoGoesThere-batteries2.logarchive` (preserved, per this entry's own
> instruction that H5's correction exists because an archive was NOT kept).
>
> **Manipulation row read FIRST:** `armed` → `ReminderCreateTool`,
> `armed-bareclock` → `ReminderCreateToolBareclock`, 1/1 each. The arms are
> genuinely different tools.
>
> | bucket (denominator = TRIALS) | armed | armed-bareclock | verdict |
> |---|---|---|---|
> | **UNION omitted+wrong-value** *(the scorer's own named primary)* | 35/40 **87.5%** | 19/40 **47.5%** | **FELL, p = 2.54e-04** ✅ |
> | **populated-future** *(the correct bucket)* | 0/40 **0.0%** | 18/40 **45.0%** | **ROSE, p = 6.38e-07** ✅ |
> | wrong-value **(GUARD)** | 0/40 | 0/40 | **did NOT rise** ✅ |
> | no-call **(GUARD)** | 5/40 12.5% | 3/40 7.5% | **did NOT rise** ✅ |
> | already-past | 0/40 | 0/40 | clean in both |
> | **route (a) — app-resolved a bare clock** | **0/40** | **18/40** | **THE MECHANISM FIRES** |
>
> Two-sided Fisher exact on both primaries. **Per this card's own wording —
> *"Then (and only then) the guide text promotes"* — the promotion condition is
> SATISFIED.**
>
> **Why this is the night's strongest result:** the same evening's #339 baseline
> measured shipping code omitting `due` on **28/28 calls (100%)** with route (a)
> firing **0/60**. The bareclock arm populates a correct FUTURE due **45%** of
> the time with **zero** wrong values and **zero** already-past values — in the
> ALREADY-PAST regime, where a lazy fix would have been caught buying its wins
> with stale dates. It does not, and `no-call` FELL rather than rose, so the
> improvement was not traded for a stall (340-H5′-B's guard, and 372-HD2's).
>
> **🔴 THE SCORE ALMOST CAME OUT WRONG, AND THE FIX IS #416-G.** The evening's
> archive spans the whole chained session, and **a cell name is not unique across
> INSTRUMENTS**: #392's decline run also uses a cell called `armed`. Scored
> whole, this A/B read:
> - `cell armed — **160 TRIALS**` (#340's 40 pooled with #392's 120), against
> - `cell armed-bareclock — 40 TRIALS` (clean, because only #340 ran it).
>
> A 4× contaminated arm compared against a clean one — **a confident, precise,
> WRONG A/B, with nothing in the output hinting at it.** `score-due-omission.py`
> gained `--start`/`--end` passthrough in the same commit; the numbers above are
> scoped to `21:00:00–21:04:40`, and **the check that the window is right is that
> both arms return exactly 40, matching the artifact's `trialsPerCell`.**
> Back-to-back runs into one archive is the normal shape of a chained session, so
> this trap was going to fire on somebody eventually.

> **⚖️ 340-E RULED 2026-08-31 (Owen, interactive decision pass): NO — THE GUARD
> STAYS PROSE-ONLY.** #338's guard is about impersonation; validating tool
> ARGUMENTS is a different job and belongs in the tool layer or the prompt, not
> bolted onto a guard built for another purpose. **340-E is DISCHARGED.**
>
> **What this means for the rest of this entry, stated so the scope is not
> quietly widened later:** the false-claim half of #340 — *"set for 11"* on a
> reminder that carries no due date — gets no guard-side catcher. The omission
> itself (85%, both prose fixes falsified) remains this entry's open work, and
> it stays a model/prompt/tool problem. **#340 does NOT close with this.**

> **📋 2026-09-01 — 340-PROMOTE LANE OPENED (Owen's election, subagent + merge-on-green authority).** The board pass found this entry's own promotion condition — *"Then, and only then, the guide text promotes"* — SATISFIED by 340-H5′-A/B on 08-27 and **never executed**: at HEAD the production `ReminderCreateTool.Arguments.due` guide (`DeviceActionTools.swift:357`) is still the OLD text, the winning text lives only inside `struct ReminderCreateToolBareclock` (`:770`, `#if DEBUG`), and `DeviceToolBelt.swift:64` instantiates the plain tool. A header stale in the claiming-open direction hid it for five days. Bars pre-registered before code:
> - **340-P-A (the winner ships):** the production `due` guide equals the 340-H5′ winning bareclock text VERBATIM, pinned by a test on the PRODUCTION type. RED-first: the pin is written and watched RED against the old guide before the swap; a revert-mutation re-reddens it. [offline]
> - **340-P-B (the harness copy leaves):** `ReminderCreateToolBareclock` and the instrument's `armed-bareclock` cell are retired (or the cell re-pointed at production and renamed honestly) — `grep -rn Bareclock Talaria/` returns zero non-comment hits; any cell-enum/count pins updated DELIBERATELY and named in the result. [offline]
> - **340-P-C (#218 discipline):** the promoted string is compiled in Release — Release build green, nothing left behind `#if DEBUG`. [Mac]
> - **340-P-D (scope honesty):** this lane does NOT close #340. The ~55% residual omission is model/prompt behaviour with 340-E ruled NO (08-31); the result block re-files it as WATCH-shaped with the next measurement named. [offline]
> - **340-P-GATE:** `lane-gate.sh` PASS, count reconciled. Header pointer appended in the same commit (the 08-23 header's "what is actually owed" clause is falsified twice over). [Mac]

> **✅ 2026-09-01 — 340-PROMOTE LANDED. THE 08-27 WINNER IS IN PRODUCTION, AND
> #340 DOES NOT CLOSE.** All five pre-registered bars **MET**. PR #404, squash `a7a5d676`.
>
> **340-P-A (the winner ships) — MET, RED-first and mutation-proven.**
> Production's `ReminderCreateTool.Arguments.due` @Guide is now the
> `armed-bareclock` text, byte-for-byte, and it is pinned by
> `TalariaTests/PromotedDueGuideTests.swift` on the **production type**.
>
> **The RED, watched before the swap** (`-only-testing` on the new suite,
> unmodified production guide) — two issues, both attributable:
> ```
> ✘ productionDueGuideIsTheWinningBareclockText() … Expectation failed: due == Self.winningBareclockGuide
>   ↳ due → "Due date and time like "2026-07-08T09:00" (local time), or empty for no due date."
>   ↳ Self.winningBareclockGuide → "Due time. Give just the clock time the user said, like "16:30" or "9am" — …"
> ✘ … Expectation failed: due != Self.supersededDueGuide
>   ↳ production still carries the pre-promotion `due` guide
> ✔ theSchemaCarriesEveryGuideText() passed
> ```
> After the swap: **230 tests / 6 suites GREEN** (`PromotedDueGuideTests`,
> `DeviceToolBeltTests`, `BareClockResolutionTests`, `BareClockWiringTests`,
> `ActionBatteryCellSelectionTests`, `InstrumentRegistryTests`).
> **Revert-mutation:** the pre-promotion guide put back → the SAME two issues
> return, `theSchemaCarriesEveryGuideText()` stays green; restored, green again.
>
> **🔴 THE PIN'S FIRST DRAFT WAS A BAD INSTRUMENT, AND IT WENT RED ANYWAY —
> which is the whole reason it had to be caught by reading the output rather
> than by reading the verdict.** Draft one did
> `encodedSchemaJSON.contains(text)`. The schema JSON escapes the embedded
> quotes in `\"16:30\"`, so a raw Swift literal can NEVER match it: the
> positive assertion went RED **for the escaping, not for the text**, and the
> paired negative assertion — *"the superseded guide is gone"* — passed
> **VACUOUSLY while the superseded guide was sitting in the payload**. A
> confident RED for the wrong reason plus a green that meant nothing, in one
> test, on the first run. The tell was the issue COUNT: one, where a genuinely
> unpromoted production must fail both. The pin now decodes
> `properties.due.description` and compares with `==`, which has neither
> failure mode.
>
> **⚠️ AND THIS ENTRY'S MOST-REPEATED CLAIM IS FALSE.** Six places in this
> entry and in `DeviceActionTools.swift` say some form of *"`@Guide` has no
> runtime accessor, so the text is pinned here by comment and measured by the
> battery itself."* The macro's **argument** has none; its **effect** does —
> `@Generable` lowers every `@Guide(description:)` into
> `Arguments.generationSchema`, which is `Codable`. That is why this promotion
> could be pinned by a TEST rather than by another comment, and why the pin is
> strictly stronger than a source grep: it fails both if the text is reverted
> and if some future refactor stops the text reaching the model at all. The
> comment on `ReminderCreateToolDateguide` carries the correction upstream.
>
> **📌 AND THE LANE-OPENING BLOCK ABOVE HAS A WRONG LINE NUMBER — corrected
> here rather than silently worked around.** It says the winning text lives at
> `DeviceActionTools.swift:770`. **`:770` was the `armed-dateguide` cell's
> guide** — 340-G's arm, the one that bought its win at a flagged cost in tool
> calls. The 340-H5′ winner was at **`:824`**, inside
> `struct ReminderCreateToolBareclock` (`:813`). Following the line number
> instead of the struct name would have promoted the LOSING text under the
> winner's name, and every downstream artifact would have called it bareclock.
> The identification was made from the struct, not the offset.
>
> **340-P-B (the harness copy leaves) — MET.** `grep -rn Bareclock Talaria/`
> returns exactly one hit and it is a comment (the promotion note naming what
> was retired). Deleted, and why each:
> - **`struct ReminderCreateToolBareclock`** (`DeviceActionTools.swift`) — its
>   only delta from production was the `due` guide, which production now has.
> - **`ActionBatteryCell.armedBareclock`** + its 26-line doc comment, and the
>   `.armedBareclock` arm of the belt-swap factory
>   (`LocalChatBackend+Battery.swift`) — a cell that swaps production for
>   production measures nothing. **Not "re-pointed at production under an
>   honest name": `armed` IS that name and it already exists.**
> - **`bareClockBatteryCells`** — and it had **ZERO call sites**, before this
>   lane touched anything. Its own doc said *"The control travels with the
>   treatment. Pinned."* while the Developer-screen button that ran the A/B
>   passed `cells: ["armed", "armed-bareclock"]` as **string literals**. A
>   constant documented as a pin, pinning nothing, for eleven days.
> - **The Developer screen's "Due-date A/B (#340-H5) n=20" button** — it named
>   the retired cell by literal, so keeping it would have shipped #420's
>   inert-control disease into the very screen used to measure. The plain
>   `due-date` instrument button (registry default cells) is untouched.
>
> **Every count/label pin, updated DELIBERATELY rather than discovered red:**
> - `DeviceToolBeltTests.everyCellCarriesItsExportLabel` — the
>   `armedBareclock.rawValue == "armed-bareclock"` assertion **removed** (the
>   text it guarded is now guarded better, on the production type).
> - the same test's `ActionBatteryCell.allCases.count` — **33 → 32**, with the
>   comment's own 31 → 32 → 33 chain extended to record the removal. This pin
>   is documented as catching ADDITIONS; this lane is the first time it moved
>   in the removing direction, and it was edited before the run, not after a
>   red.
> - `ActionBatteryCellSelectionTests.theRefusalTextCarriesTheKnownNames`
>   asserts `knownNames.count == Cell.allCases.count` — **no edit needed and
>   that is a finding, not an omission**: `ActionBatteryCellSelection.knownNames`
>   is *derived* from `CaseIterable`, never retyped, so the resolver's "known:"
>   vocabulary tracked the removal on its own. Verified green, not assumed.
> - **`scripts/mac/score-due-omission.py` NOT touched** (another lane owns it).
>   Its `bareclock` references are the production `bareClock=` log field and
>   its own self-test fixtures — neither names a cell that must exist.
>
> **340-P-C (#218 discipline) — MET.** Release build clean:
> `xcodebuild -configuration Release -destination 'generic/platform=iOS Simulator'
> build CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`. The promoted string
> is in the production `struct`, outside every `#if DEBUG`; nothing this lane
> added is Debug-only. Run standalone under Xcode-beta6 **before** the gate, so
> the #218 check is not merely a by-product of the gate's own Release leg.
>
> **340-P-GATE — MET, on the SECOND roll, and the roll is declared.**
> `GATE: PASS on 24A5423a` — **2811 Swift Testing** (2809 baseline **+2**, this
> lane's two new tests, so the count moved exactly as much as it should) /
> **15 XCUITest, 0 failures** / **Release clean**. Sim `CC-lane-1`, runtime
> iOS 27.0 `24A5423a`.
>
> **Run 1 was a FAIL and it was #219, declared before the re-roll rather than
> after.** One red — `TalariaUITests.testConnectedRelaunchSkipsTheConnectEntry`
> — the un-hittable-button flake, on a run whose Swift Testing leg was 2811/2811
> and whose Release leg passed. Re-run on **byte-identical** bytes: that test
> **passed (42.5 s)**, 15/15, everything else unchanged. Under this lane's
> pre-declared rule (one re-roll on THAT test only; a second red on the SAME
> test stops the lane) the red is discharged.
>
> **⚠️ THE GATE'S OWN CLASSIFIER DISAGREED, and it should be read before anyone
> treats its advice as final.** It printed *"ASSERTION TEXT PRESENT — treat this
> as a REAL failure. Do NOT re-roll it."* That advice is correct in general and
> wrong for this test: #219's flake is an XCUITest assertion failure, so it
> presents with assertion text every time. The classifier fails SAFE by design
> (#300) — it cannot distinguish a known-flaky assertion from a new one, and
> nothing has taught it #219's signature. The override here rests on evidence
> the classifier does not have: #219 is measured **6 reds / 2 passes on
> unmodified `main`** the previous night, and this lane's diff touches no
> connect path. **Anyone overriding this advice owes that second sentence.**
>
> **✅ #423 REPRODUCED EXACTLY, on the failing run.** The gate printed
> **`XCUITest tests run — 2`** while `suite.log`'s own summary read
> *"Executed 15 tests, with 1 failure"* and carried 30 `Test Case '-[` lines
> (15 started + 15 finished). On the PASSING run the same line read
> **`15`**. So the under-report is specific to red runs, exactly as #423
> describes — the count was taken by hand from `suite.log` on both runs rather
> than from the gate's summary line. **Both runs used the PRE-FIX gate:** #423's
> repair (`6a96b85a`, *"the gate's XCUITest count reads the ledger"*) landed on
> `main` while this lane was mid-gate and arrived here on the rebase. So this is
> a LAST SIGHTING of the defect, not a live one — recorded precisely because the
> fix means nobody will see it again.
>
> **Rebase note (and why there is no third gate run).** `origin/main` moved
> during this lane — `9f537b42`, `6a96b85a`, `2cab3d45` — and those three
> commits touch **only** `OPEN_ITEMS*.md` and `scripts/mac/*`: no Swift, no
> `project.yml`, no `project.pbxproj`. The compiled inputs the PASS was measured
> on are byte-identical to what merges, so the gate was **not** re-run after the
> rebase. That is a decision, not an omission: re-rolling twenty minutes to
> re-measure an unchanged binary with a fixed test COUNTER is the cost rule this
> project already wrote down (*the gate is a verification instrument, not a
> search tool*). `xcodegen generate` after the rebase produced no diff.
>
> ---
>
> **🟡 340-P-D — WHAT REMAINS, RE-FILED AS WATCH. #340 IS NOT CLOSED BY THIS.**
>
> The promotion moved a real number and did not solve the founding defect. On
> 08-27's own figures the promoted text produces a correct future due date in
> **18 of 40 trials**; **~55% of trials still carry no due date at all**, and a
> reminder with no due date is exactly the artifact this entry was opened over.
> With **340-E ruled NO (08-31)** there is no guard-side catcher for the false
> *"set for 11"* claim either, so the residual is model/prompt behaviour with
> two prose candidates already falsified (340-F: 0 due dates in 14 calls;
> 340-G: won omission, cost tool calls) and a third now promoted.
>
> **The next measurement, named — and the reason it needs naming is that the
> instrument's meaning changed underneath it.** The `due-date` instrument's
> **`armed` cell now IS the promoted text.** Every pre-2026-09-01 `armed` number
> in this entry is a measurement of the OLD guide; every `armed` number from
> here on measures the new one. They are not comparable, and nothing in the
> artifact says so.
> - **A future run should compare a fresh `armed` against 08-27's
>   `armed-bareclock` column, not against 08-27's `armed` column** — i.e. the
>   pre-registered expectation is **REPLICATION at ~45% populated-future /
>   ~47.5% union / 0% wrong-value**, not improvement. A fresh `armed` landing
>   near 08-27's *control* (0/40) means the promotion did not survive the trip
>   into production, which is a different and worse finding than "no gain".
> - **The clock regime must be recorded with it.** 08-27 ran ALREADY-PAST
>   (21:00 local against a fixed *"at 4:30pm"* prompt). A replication run before
>   16:30 local is measuring the other branch of `resolveBareClock` and is not a
>   like-for-like check on the same bucket — 340-G's own instrument flaw,
>   avoided by stating it rather than by remembering it.
> - **Cheapest vehicle:** `preota-subset.sh` already runs
>   `due-date --trials 20 --cells armed` on the phone, so the replication rides
>   an existing device pass rather than needing a lane. Score with
>   `score-due-omission.py`, four buckets over TRIALS, `--start`/`--end` scoped
>   to the run window (#416-G: cell names are not unique across instruments, and
>   an unscoped score silently pooled #392's `armed` into #340's).
> - **The 55% itself gets no new prose candidate without a mechanism.** This
>   entry has spent three texts; the standing lesson is that a guide which reads
>   well is not evidence. Anything further should start from why the model omits
>   the field when it is optional, not from a fourth rewrite.
>
> **Prose this lane FALSIFIED and corrected upstream, in the same commit**
> (close-out rule, #317): the header clause above; the index line at the top of
> this file; `ReminderCreateToolRequiredFields`'s *"same @Guide texts"* (now a
> TWO-delta struct — schema optionality **and** the pre-#340 guide);
> `ReminderCreateToolGuidefix`'s already-corrected confound note (it grew a
> third leg the same way, on the same day, which is the second time a promotion
> has aged that comment out); `ReminderCreateToolDateguide`'s *"production's
> `due` guide still offers …or empty for no due date"*; the `armedDateguide`
> cell doc, which made the same claim and whose `armed` is no longer a control;
> `dueDateBatteryCells`'s implicit control claim; and the
> *"`@Guide` has no runtime accessor"* line. **None of the measured DEBUG
> structs were edited** — each is the artifact of the runs that used it, and
> editing one would invalidate those numbers; the corrections are comments
> beside them saying what they now measure.

> **📋 2026-09-04 — PLAN WRITTEN (the difficulty sweep, Owen's 09-03 ask): `planning/superpowers/plans/2026-09-04-340-due-date-from-user-words.md`.** Route (a) one step upstream: when the model's `due` argument is EMPTY (the ~55% case on the promoted text), `performCreate` resolves the date from the USER'S OWN WORDS — `NSDataDetector` + the existing `parseBareClock`/`resolveBareClock`, deterministic, no model — through a per-turn `userText` on `ToolEventRelay.beginTurn` (the seam `LocalChatBackend.beginToolTurn()` already calls). A populated argument keeps today's path byte-for-byte; 340-E stays prose-only; the guide text is untouched. Bars 340-U-A..E are in the plan (device: `armed` populated-future ≥ 34/40 with a `source=userText` column ≥ 12/40, `armed-nofallback` as the same-run mutation arm, wrong-value 0). Task 0 measures `NSDataDetector` on the instrument's prompts BEFORE the bars are pinned — the plan's one unmeasured premise. Index: `planning/2026-09-04-difficulty-sweep.md`.

> **📌 2026-09-04 — BARS PRE-REGISTERED (RED-first) — LANE 340-U, "due date from the user's words" (`planning/superpowers/plans/2026-09-04-340-due-date-from-user-words.md`). Owen's five decisions, 09-04 AM ballot, each on the recommended arm: (1) the fallback fires ONLY on an EMPTY model `due` argument — an unparseable value stays pooled into wrong-value as today, so the A/B stays clean; (2) two dates in one message → the EARLIEST future date, candidate count logged; (3) time-only phrases → `NSDataDetector` first, then the existing `parseBareClock`/`resolveBareClock` (next occurrence) over the message's tokens; (4) reminders ONLY — calendar creates always carry a start and alarms a time, calendar is a follow-up lane if the instrument ever shows an omission there; (5) when the words carry no date the card STAYS DATELESS — the honest state; the "default 09:00" arm is rejected by this entry's own history. The guide text is untouched; 340-E stays prose-only (the 08-31 ruling stands); a populated argument keeps today's path byte-for-byte.**
> **Bars (written before any code; a missed bar is a falsification, never a redefinition — with ONE pre-run clause the plan itself carries: 340-U-C's numerator expectation is derived from Task 0's prompt census, and if more than 6 of the 40 prompts carry no date phrase the bar is re-pinned BEFORE the device run, in a dated block here, never after it):**
> - **340-U-A — the parser (unit, deterministic).** `DeviceActionParsing.detectDue(in:now:)` resolves each phrasing in Task 0's measured list to a FUTURE date with the asked clock time; returns `nil` for text with no date; never returns a date ≤ `now`; the bare-clock second pass resolves "at 4pm" / "at 16:30". Isolating mutations: return `nil` unconditionally → every resolving row reds; drop the future guard → the past-date row reds.
> - **340-U-B — the seam.** `ToolEventRelay.beginTurn(userText:)` carries the text and `beginTurn()` clears it; `ReminderCreateTool` reaches it; source-witness pins prove `send` and `streamTurn` pass `message` (not `promptText`). Isolating mutation: stop passing it in `send` → the witness pin reds.
> - **340-U-C — the number (device, the `due-date` instrument, `armed` cell, n = 40).** `populated-future ≥ 34/40` (from 18/40 on the promoted text), `wrong-value = 0/40` (unchanged), `already-past = 0`, and the new `source=userText` column ≥ 12/40 — the fix has to be visibly doing the work, not the model getting lucky. Prediction, written first: the residual omissions are exactly the prompts whose text carries no date phrase (Task 0 lists them).
> - **340-U-D — the mutation arm (same run).** `armed-nofallback` on the same 40 prompts: `populated-future` back in the 08-27 band (≤ 24/40) — the A/B that proves the delta is the fallback and not a model drift between runs. Bar: `armed − armed-nofallback ≥ 10` populated-future, Fisher p < 0.05.
> - **340-U-E — the honesty half is closed by construction.** On the `armed` cell, every reply that names a time for a reminder whose card carries a date is counted `claimTrue`; `claimedTimeCardDateless` (this entry's founding artifact) must be 0 on prompts that carry a date phrase. Scored from the transcript + the instrument line, never from the model's prose alone.
> - **340-GATE.** `lane-gate.sh` PASS on final bytes (Swift Testing count MOVED, XCUITest count unchanged, Release clean).
> **Task 0 precedes every bar's code and has a STOP rule of its own:** it measures `NSDataDetector` on the sim over the instrument's prompts plus the plan's own set, printing (not asserting) `date`/`duration`/past-or-future per phrase and the two things documentation cannot say — whether a bare "at 4" resolves at all, and whether a bare clock resolves to TODAY when already past. If the detector resolves fewer than half of the instrument's date-bearing prompts, the plan's premise is falsified and the consequence (a hand-rolled relative-date grammar, or no lane) goes to Owen before any production line is written. RESULT block to follow here.

> **📏 2026-09-04 — TASK 0 MEASURED (the premise probe + the prompt census, before any production line). Premise HOLDS; one plan assumption FALSIFIED; bar 340-U-C NOT re-pinned.** Full report in the lane's SDD workspace (`task-0-report.md`); the probe ran as a macOS `swift` script (`NSDataDetector` is Foundation, same engine) because the box was at its concurrent-xcodebuild ceiling — parity with iOS is ASSERTED here and is PROVEN by 340-U-A's unit rows when they run on the simulator inside the gate; if a row behaves differently there, the row is wrong, not the phone.
> - **The census falsifies the plan's own premise about the instrument:** there is NO 40-prompt list. `dueDatePromptSet` is ONE element — `actionBatteryDefaultPrompts[0]`, *"Remind me to test Talaria at 4:30pm"* — sent `trials` times per cell (`LocalChatBackend+Battery.swift:1546-1549`, loop at `:1029-1035`). Date-bearing **40/40**, phrase-less **0/40** → the re-pin clause does not fire, and the residual set the prediction leaned on is EMPTY: a missed `≥ 34/40` cannot be excused by phrase-less prompts. Read the bar that way. (A phrase-diverse cell — the plan's eight phrasings × 5 — would generalise the number; it is Owen's device minutes and is NOT a bar of this lane; noted for the RESULT.)
> - **Detector facts documentation cannot give (probed 09:15 CDT):** **(a)** a bare `at 4` NEVER resolves, at any hour 1–12, bare or wrapped — a day word licenses it (`tomorrow at 4` → 16:00), so the bare-clock second pass is load-bearing, not a nicety. **(b)** a bare clock resolves to TODAY even when already past (`at 7:45am` at 09:15 → today 07:45) — the detector never rolls forward; its AM/PM is a fixed waking-hours map (1–8 → PM, 9–12 → AM), not next-occurrence. **(c)** `tomorrow at 4` → 16:00. **(d)** `tonight`/`this evening` → today 19:00, `this afternoon` 15:00, `this morning` 09:00, day-only phrases → noon. `duration`/`timeZone` were 0/nil on every match — build nothing on them.
> - **Premise verdict:** the instrument's date-bearing prompt resolves 1/1 (so 40/40 trials) by the detector alone; the plan's own eight phrasings 6/8 — the two misses are exactly the two the plan predicted (`at 4`, `in 20 minutes`). Far above the STOP line.
> - **The load-bearing consequence — the evening run:** the device run is an EVENING card, and in the evening the detector's raw answer for *"…at 4:30pm"* is TODAY 16:30, already elapsed, on 100% of trials — the very regime 340-G's four byte-identical `16:30` values and 340-H5′ were measured in. A `detectDue` that returned the detector's output unmodified would populate a stale `due` every time and trip `performCreate`'s guard 1 → `already-past 40/40`, `populated-future 0/40`. **340-U-A's "never returns a date ≤ now" already forbids this; the sharpening is WHERE the roll-forward applies: to the detector's CLOCK-ONLY matches (a time with no day word) → next occurrence; an explicit past DATE ("on September 1") → `nil`, stays dateless (honest).** Test rows construct `now`, never wait for the clock.
> - **Second finding → a new RED row under 340-U-A:** a token-wise bare-clock pass MANUFACTURES dates — `"in 20 minutes"` (no detector match) → token `20` → `parseBareClock` accepts 20:00; `"in 3 hours"` → 03:00; `"call table 4"` → 04:00. The second pass runs ONLY over an `at <clock>` frame (the token after "at"/"@"), never over bare integers; `"in 20 minutes"` returns `nil` (a duration is neither detector-resolvable nor a clock, and stays dateless by decision 5). Rows carried into 340-U-A: the ten resolving rows (incl. the instrument's own prompt), the bare hours 1–12, the past-clock roll-forward rows (`at 7:45am` at 09:15; `at 10:30` at 14:00; the instrument's prompt at an evening `now`), the three `nil` rows (`Remind me to test Talaria`, `buy milk`, `next week`), decision 2's two-date row AND its reversed-order twin (document order ≠ chronological order), and the §6 guard row.
> **⟵ CORRECTED 2026-09-04 PM (Task 1's parity check, same lane): fact (b)'s "fixed waking-hours map (1–8 → PM, 9–12 → AM)" is FALSE.** The detector's AM/PM choice for an AMBIGUOUS bare `h:mm` is the next occurrence of that reading in a 12-hour cycle relative to the REAL clock — `at 10:30` read 10:30 at 09:16 and **22:30** at 11:02, same Foundation call, same box. Task 0's twelve `h:30` probes all sat AHEAD of their 09:16 probe time, so the fixed-map reading and the 12-hour-cycle reading fitted that data identically; a single time-of-day probe could not separate the two hypotheses. The rest of (b) stands — the detector still never rolls a past clock forward. Consequence: `NSDataDetector` takes no reference date, so this ambiguity cannot be held still by a test; 340-U-A's ambiguous-clock row pins the parser's CONTRACT (minute, hour ∈ {h, h+12}, strictly future) and the roll-forward row uses an explicit meridiem. The instrument's prompt carries an explicit meridiem, so 340-U-C is unaffected. iOS-vs-macOS parity: every carried-over row scored the same on the simulator — no parity finding.
> **📌 2026-09-04 PM — FOLLOW-UP LANE 340-F RULED (Owen, AskUserQuestion, all on the recommended arm; raised by the lane's final whole-plan review; none blocks 340-U's merge or the device card):** (1) **bare hour in the USER'S words mirrors the detector** — a bare 1–11 in the second pass means the next occurrence on a 12-hour clock (`at 8` said at 10:00 → 20:00 today), the model-argument path keeps its ruled 24-hour `parseBareClock` rule untouched; (2) **candidates are consumed per turn** — a second empty-`due` create in the same turn takes the next unused candidate instead of the same first date (the new `candidates=` artifact field is the watch for how often it happens); (3) **the voice-transcript synthesized send mines only the `User:` lines** — `appendVoiceTranscript` posts `User:`/`Talaria:` lines through `send(message:)`, and with the brain resolving local a tool call on that turn could otherwise mine an assistant line (narrow preconditions, closes the founding wrong-value shape on that path); (4) **a phrase-diversity cell** — the plan's eight phrasings × 5 as its own instrument cell (a unique name per #416-G), a follow-up device card of ~20 min, so the second pass and the ambiguous-clock reading are measured on device rather than sim-proven only. Also carried: a `carriesUserText` banner field in the instrument artifact so a reminder-due rate carries its configuration (the #398-A rule, third axis); 340-U-E is hand-scored from the transcript + the instrument line per plan. **Sequence:** 340-U merge → Debug OTA → the two-cell device card → lane 340-F (bars pre-registered here before code) → OTA → the diversity card.

## 279. 🐛 `retryMessage` removes the failed row without adopting — a retry can duplicate the user turn — **✅ FIXED AND MERGED 2026-08-09 as `12ed25b` (branch `claude/t27-279-retry-adoption`, commits `c4411cc` + `13e4049`). Bars 279-A..E MET, `GATE: PASS`. OPEN ONLY for 279-F, the device bar, which is Owen's.** *(Header corrected 2026-08-10 — it still read "FILED … Bars pre-register here before any code" for a full day after the fix merged, and that is what got this lane dispatched a second time. See the RE-DISPATCH note at the end of this entry.)*

`ChatStore.retryMessage` does `messages.removeAll { $0.id == message.id }`
OUTSIDE the new `truncateTranscript` primitive, so the backend mirror is
never told. The user row of a failed turn IS in the local brain's mirror
(`appendUserMessage` runs before generation), so a retry can duplicate it on
the next merge — the same resurrection family as #78, through a path that
lane deliberately did not touch. Fix shape: route it through the primitive
like `/retry` and `/undo` now are.

> **⚠️ FOUR CORRECTIONS TO THE TEXT ABOVE — 2026-08-09, written from a read of
> the code at `bfbd154`, BEFORE any code of this lane. The paragraph above is
> right about the defect and wrong in four particulars.**
>
> 1. **"The user row of a failed turn IS in the local brain's mirror" is true
>    for ONE of the two failure paths, not both.** `LocalChatBackend.swift`'s
>    availability gate (`:493-497`) yields `.failed` and `return`s *before*
>    `appendUserMessage` runs (`:525`). A refusal-to-run failure — the
>    `.unavailable` model tier — leaves **nothing** in the mirror and cannot
>    resurrect anything. The claim holds only for a **generation** failure
>    (`:646`, inside the streaming loop's `catch`, i.e. after `:525`). The bars
>    below are written for the generation-failure path, which is the one that
>    mirrors.
> 2. **"Fix shape: route it through the primitive" is NOT literally
>    implementable, and doing it literally is a worse bug than the one being
>    fixed.** `truncateTranscript(from:)` removes `index...` — *to the end of
>    the transcript*. `retryMessage` removes ONE row and is reachable on any
>    `.failed` row **anywhere** in the thread (`MessageBubble.swift:211`, and
>    `finalizeStaleSendsFromCache` `ChatStore.swift:502-511` manufactures
>    mid-transcript `.failed` rows on every cold load after a mid-stream
>    death). Literal routing would delete every turn below the retried one.
>    **The correct reading is "reach the mirror", not "truncate to the end"** —
>    i.e. route the single-row removal through the same adoption tail
>    (`adoptLocalTranscript()`, `:1807`). **Bar 279-D exists specifically to
>    fail if anyone implements this sentence literally.**
> 3. **The entry omits a second defect in the same eight lines: the swallowed
>    re-send.** The removal at `:1739` is unconditional; the re-send at `:1757`
>    calls `await sendMessage(...)` and **discards** its `Bool`. `sendMessage`
>    returns `false` from the empty guard (`:575`) or from
>    `hasPendingDuplicateMessage` (`:576`, defined `:2211-2218`) — a
>    byte-identical turn still `.sending` or `.queued` elsewhere in the thread.
>    When that happens the failed row is deleted and **nothing is sent**. That
>    is the precise residual `regenerateReply` was given
>    `restoreTruncatedRows(_:at:)` for (`:1794`, used at `:1858-1864`) and
>    `retryMessage` never got. Bar 279-C covers it.
> 4. **The entry does not scope the Hermes path, and without that scoping
>    279-B reads as a promise the code cannot keep.**
>    `SessionsHermesClient.adoptTruncatedConversation` (`:766-768`) assigns
>    `currentConversation` and nothing else — that mirror is a **fetch cache**,
>    not the gateway's session. On the Hermes path this fix stops the *cache*
>    from re-serving the removed row and does nothing more; the GATEWAY session
>    still holds the turn, and the documented `/retry` caveat
>    (`ChatStore.swift:1823-1829`) applies unchanged. The fix is total only on
>    the local brain.
>
> **PRE-REGISTERED BARS — written 2026-08-09, before the first line of code,
> per CLAUDE.md ("Where the BARS live"). A missed bar is a falsification, not
> a redefinition.**
>
> - **279-A (unit, characterization — written and GREEN against the UNMODIFIED
>   tree, and green again after the fix with the new number).** On a
>   `.localBrain`-shaped mirroring double, drive a turn to `.failed` *after*
>   the user row has been mirrored, then `retryMessage` that row, then let the
>   retried turn finish. Assert the merged transcript's user-row count.
>   **This bar records TODAY'S number first.** If the pre-fix number is not 2,
>   the mechanism above is wrong and **the lane stops and re-diagnoses rather
>   than proceeding.** Evidence: the asserted count, quoted verbatim here, from
>   both sides of the fix. No device.
> - **279-B (unit, fails today — the defect):** same setup as 279-A; after the
>   retried turn settles, exactly **one** user row carrying the retried text
>   survives, and it is the row minted by the retry (its `id` is not the failed
>   row's `id`), and the backend mirror was TOLD (an
>   `adoptTruncatedConversation` call recorded between the removal and the
>   re-send). Evidence: the filtered count, the id inequality, the adopt log.
>   Expected RED before the fix with the count at 2. No device.
> - **279-C (unit, fails today — the swallowed re-send):** arrange a retry
>   whose `sendMessage` returns `false` via `hasPendingDuplicateMessage`
>   (`ChatStore.swift:2211`) — a byte-identical `.queued` or `.sending` user
>   row elsewhere in the thread. Assert the failed row is **still present** and
>   the backend was not asked to send (`client.sentPrompts` unchanged). Today
>   the row is gone and nothing was sent. Evidence: both assertions. No device.
> - **279-D (unit, no over-reach — the mid-transcript case):** a thread whose
>   `.failed` user row sits at index 0 with two later *successful* exchanges
>   below it (a production shape, not a contrived one — `#56`'s
>   `finalizeStaleSendsFromCache` manufactures exactly it). After
>   `retryMessage` on that row, **every row below it survives**, count and
>   contents pinned explicitly. This is the bar that fails if correction 2 is
>   implemented literally. Evidence: the full `messages.map(\.content)` array.
>   No device.
> - **279-E (unit, fixture fidelity — 281-C's lesson applied before it costs a
>   day again):** the double used by 279-A/B must reproduce what
>   `LocalChatBackend` does on a generation failure and not an invented shape:
>   (i) the user row is mirrored with `id == clientMessageID` **and**
>   `clientMessageID` set, matching `LocalChatBackend.swift:1318-1338`; (ii) on
>   a failed turn the reply is **not** mirrored (nothing reaches
>   `appendAssistantMessage`); (iii) the double records every
>   `adoptTruncatedConversation` call, so 279-B can prove the mirror was told
>   rather than that the count merely came out right. **This is a fidelity pin
>   and it is GREEN on both sides of the fix — its "RED" was that the
>   capability did not exist in the double at all, recorded honestly as such,
>   the way 281-C is.** No device.
> - **279-F (device, OWEN — NOT claimed by this lane; queue it):** on the
>   **LOCAL BRAIN**, force a turn to fail *after* it starts generating —
>   **Airplane mode will not do it**, that is the `.unreachable` path, and the
>   `.unavailable` model tier is correction 1's non-mirroring path; use a
>   prompt that trips a generation error, or the Developer forced-trip harness
>   (#134). Tap retry on the failed bubble. **The question must appear exactly
>   once**, carrying the retry-time bubble, and must still be exactly once
>   after leaving the thread and returning. Expected RED until this lands.
>
> **Falsification stated in advance.** If 279-A's pre-fix count is 1, the
> mirror is not the resurrection source and the mechanism above is wrong — the
> lane reports that and stops. If 279-B goes green but 279-F still shows two
> bubbles on device, the duplicate has a second source (the server transcript
> on the Hermes path per correction 4, or the assistant-row hole below) and the
> fix is **incomplete, not wrong**.
>
> **Out of scope, watched:** `unconfirmedLocalMessages` restricts the
> content-claim tier to `sender == .user` (`ChatStore.swift:2751`), so prior
> `.hermes` reply rows have no claim tier at all and may already double on
> server-sourced merges. That is #282's seam, not this one — if 279-A's
> baseline shows it, FILE it for a number, do not absorb it here.
>
> Full pre-code analysis: `dispatch/OPUS-T27-279-retry-adoption.md`.

> **📊 MEASURED — 2026-08-09, branch `claude/t27-279-retry-adoption`. Every
> bar above met except 279-F, which is device-owed and NOT claimed by this
> lane.**
>
> **279-A, the number, quoted from the run that produced it.** Written and run
> GREEN against the UNMODIFIED tree first, asserting `userRows.count == 2`.
> **The pre-fix merged user-row count is 2** — the mechanism above stands, so
> the lane proceeded. Post-fix the same assertion is **1**. Both numbers live
> in the test's own comment (`aRetriedFailedTurnsMergedUserRowCount`).
> (Renamed from the dispatch's proposed
> `aRetriedFailedTurnLeavesTheMirrorHoldingTheOldRow` — a characterization
> bar's name has to stay true on both sides of a fix that moves its number.)
>
> **279-B/C/D watched RED against unmodified production**, verbatim from
> `xcodebuild`:
>
> ```
> 279-B  retried.count == 1 → false
>          retried.count → 2
>        retried.first?.id != failed.id → false
>          retried.first?.id → 5B7F72A1-0F37-44CC-860C-A2C693F47CED
>          failed.id        → 5B7F72A1-0F37-44CC-860C-A2C693F47CED
>        !client.adoptedMessageCounts.isEmpty
>          client.adoptedMessageCounts → []
> 279-C  messages.map(\.content) → ["Same question", "generation failed"]
> 279-D  messages.map(\.content) → ["Failed question", "Second question",
>          "Second answer", "Third question", "Third answer",
>          "Failed question", "Done."]
> ```
>
> 279-D's array is the defect rendered: the removed "Failed question" is back
> at index 0, *above* everything, with the retried copy beneath it.
>
> **279-E green on both sides**, as a fidelity pin should be. Recorded
> honestly: its "RED" was that `MirroringReplyClient` could not fail a turn at
> all — the capability did not exist — not that production was broken in a way
> it could see.
>
> **THE FIX** (`ChatStore.swift`, `retryMessage`): `firstIndex` + `remove(at:)`
> instead of `removeAll(where:)`, then **`adoptLocalTranscript()`** — the same
> tail `truncateTranscript` exits through. **Deliberately NOT
> `truncateTranscript(from:)`**, per correction 2. `sendMessage`'s `Bool` is
> now read, and every early return restores the row via the existing
> `restoreTruncatedRows(_:at:)` (new one-line wrapper `restoreRetriedRow`, so
> the three return paths restore identically).
>
> **Not pinned to text the fix never touched — both halves re-probed
> (2026-08-09).** The suite was re-run twice with one half of the fix reverted
> at a time:
> - adoption call removed, index refactor kept → **279-A and 279-B RED**
>   (`retried.count → 2`, `adoptedMessageCounts → []`), **279-C stayed GREEN**;
> - restore branch removed, adoption kept → **279-C alone RED**
>   (`messages.map(\.content) → ["Same question", "generation failed"]`,
>   `cached.messages.count → 2`), everything else green.
>
>   The two halves are therefore independently pinned; neither bar is riding
>   on the other's change. `ChatStore.swift` was byte-diffed back to the fixed
>   state after each probe.
>
> **CLOSE-OUT (same commit, at each claim's own home):**
> - `ChatStore.swift` `truncateTranscript`'s doc said it was *"**The one way**
>   to remove rows from the rendered transcript"* — **false when written**;
>   `retryMessage` removed rows and never came through it. Corrected: it owns
>   the RANGE case, and the invariant that actually holds is one level down —
>   every removal exits through `adoptLocalTranscript()`.
> - `TalariaTests/ChatStorePersistenceTests.swift` 275-C's doc comment now
>   says it covers source SELECTION only and never saw the removal. Its
>   assertions are byte-unmodified.
>
> **GATE: PASS** (`scripts/mac/lane-gate.sh`, run 3). Swift Testing
> **1859 → 1864** (+5, the bars above — verified by `@Test` count 30 → 35 in
> `ChatStorePersistenceTests`, not by arithmetic alone), XCUITest 12, Release
> build green. **Runs 1 and 2 are recorded rather than hidden**, per the gate
> script's own instruction on a flake: run 1 failed on three *fresh-simulator
> prerequisites* (EventKit TCC not pre-granted — the probe's own doc says to
> grant it with `simctl privacy`; a cold-start WKWebView control arm; and the
> #195/#236 keyboard-focus typing race), all three green on the warmed sim;
> run 2 failed on `testPairedRelaunchSkipsPairingEntry()` with **no assertion
> text**, which the gate itself classifies as a harness flake — it had passed
> in run 1 on identical code, under load average 15.7/31.6/61 with three
> concurrent gates.
>
> **Sim note for the next lane:** this ran on a dedicated `CC-279-iPhone-Air`
> created on the **iOS 27.0** runtime. **The stock `iPhone Air` on this Mac
> exists only on iOS 26.5** and cannot host the 27.0 deployment target, so
> naming it in `TALARIA_SIM_NAME` fails preflight-then-destination; and
> `lane-gate.sh` resolves the name with `head -1`, which picks the 26.5 entry
> because `simctl` lists that runtime first. A freshly created sim also has
> **no TCC grants**, which is what cost run 1.
>
> **STILL OWED: 279-F, device, Owen.** Everything above is simulator-side.

> **🔁 RE-DISPATCHED IN ERROR AND RETIRED UNRUN — 2026-08-10.** This lane was
> dispatched a second time, with a full TDD task list, against a defect that
> had already been fixed and merged the previous day. The second lane stopped
> at verification and wrote nothing but this correction. **No production line
> moved; nothing above is re-measured or superseded.**
>
> **What the code read showed, at `main` = `e3d8616`:**
> - `12ed25b` (*"Merge tracker #279"*, 2026-08-09 05:29) **is an ancestor of
>   HEAD** — a real merge commit, not a squash, so even `--contains` could
>   have seen it.
> - `ChatStore.retryMessage` carries the fix verbatim: `firstIndex` +
>   `remove(at:)` + `adoptLocalTranscript()`, and `restoreRetriedRow` on all
>   **three** early returns, with the #90 outbox removal still FIRST.
> - All five bars are in `ChatStorePersistenceTests.swift`
>   (`theFailingLocalBrainMirrorMatchesTheRealAppendLog`,
>   `aRetriedFailedTurnsMergedUserRowCount`,
>   `aRetryLeavesExactlyOneUserRowForTheRetriedText`,
>   `aSwallowedRetryPutsTheFailedRowBack`,
>   `retryingAMidTranscriptFailedRowKeepsEverythingBelowIt`), and both
>   close-out edits are in place (`truncateTranscript`'s corrected doc, 275-C's
>   pointer).
>
> **The bars are still green at HEAD, and it did not cost a suite run to know
> it.** `12ed25b` is an ancestor of `c011acd` — #299's gated tip, `GATE: PASS`,
> 2056 units — so the five bars ran green *with* `serverIdentityAdoptions` in
> the tree; and `25a713d..HEAD` touches **only** `OPEN_ITEMS.md` and
> `OPEN_ITEMS-ARCHIVE.md`. A green gate you are already downstream of is
> evidence; re-running it would only have re-bought the same fact for twenty
> minutes.
>
> **Where the false premise came from, and it is worth the sting.** The
> re-dispatch inherited *"the ChatStore serial queue shrinks to four:
> #315 → #299 → #282 → #279"* — written in `8bf4046` on 2026-08-10 00:44,
> **nineteen hours after #279 merged**, in the commit message of the lane whose
> entire job was retiring #184/#185 for having already landed. **The same
> failure mode, in the correction for that failure mode.** The tracker was not
> uniformly wrong: #282's entry says *"#279 merged as `12ed25b`"* in three
> places. **What was wrong was the one line anyone actually reads first** — this
> entry's own header, which still opened *"FILED … Bars pre-register here before
> any code"* while the MEASURED block sat two hundred lines below it.
> **A `📊 MEASURED` block does not close an item; the header is the instrument,
> and a stale header outranks a correct body every time.**
>
> **One observation, filed as an observation and deliberately NOT a new item.**
> The corrected `truncateTranscript` doc now asserts *"every removal exits
> through `adoptLocalTranscript()`"*, and read strictly at HEAD that is an
> overstatement: six other sites mutate `conversation.messages` directly
> (`:538`, `:919`, `:973`, `:1033`, `:1087`, `:1217`, `:2305`). Every one of
> them removes a row the backend mirror **never held** — empty `.hermes`
> streaming placeholders, and `.queued` rows that were by definition never
> posted — so none can be resurrected by a merge and none is a #279. The
> sentence is loose; the invariant is sound. Tightening it is free-bucket
> prose, not a lane.

> **🔴 2026-08-31 — 279-F IS UNRUNNABLE BY ITS OWN NAMED METHOD.** The card
> says to trip a generation error with the #134 forced-trip harness. That
> harness cannot produce the state 279-F observes: `debugRunForcedTrip`
> (`ChatStore.swift:4921-4941`) sends **its own** prompt, and
> `LocalChatBackend+Harnesses.swift:130-131` appends the assistant row as
> **`.delivered`** — never `.failed`. Both Retry affordances are gated on
> `status == .failed` (`MessageBubble.swift:207-214`, `:329-336`), so **no
> Retry button can ever appear** and the bar has nothing to press. It is a
> #102/#110 repetition instrument, not a failure injector — the Developer
> screen's own success text says as much.
> **The fix under test is still live** (`ChatStore.retryMessage:2817-2845`
> carries the #279 adoption-tail fix), so the bar's INTENT stands; only its
> method is void. **Candidate replacement (unverified, needs two device
> attempts):** force-quit mid-local-stream, relaunch, and let the cold-load
> scrub settle the interrupted user row `.failed`
> (`ChatStore.swift:915-925`, `:998-1010`). If that does not reproduce twice,
> 279-F needs a purpose-built DEBUG failure injector — do NOT keep spending
> device minutes on the #134 path, which is now proven not to be it.

## 269. 🗣️ #251 SLICE 2B — the conversational installer: the AGENT installs its own plugin and the user never touches a terminal — **FILED 2026-08-06 late night by the roadmap-recovery pass (#268). Owen ROUTED the shape on 2026-08-05 ("I like this. Empowers the user too") but it was never given an entry, a lane, or bars. NOT STARTED.** **⟵ HEADER CORRECTED 2026-08-23 (stale-header sweep): 269-A MERGED 2026-08-16; the remainder of slice 2B is still unbuilt.**

**The correction that produced it (Owen, 2026-08-05 late, quoted in #251):**
*"I didn't even know it had a terminal cli until I had update issues."* Real
users get Hermes as a **desktop app from a GitHub-released installer** — no
`curl | bash`, no terminal, ever. The curl path is OUR server-side reality on
OJAMD and the Mini, not the user's. **Any setup story that says "just run one
command" fails the actual audience on contact.**

**The chosen shape, verbatim from #251:** *"Talaria's upgrade flow = connect
the app to Hermes (the existing API-key handshake), then the APP SENDS THE
SETUP PROMPT and the agent — which has hands on its own host — installs and
enables the talaria plugin itself. Consent ('enable talaria?') surfaces in
chat where the user lives; the app probes to verify."* Vehicle, in Owen's
words: *"a skill more or less, and the intro prompt for the user, and hermes
handles the rest."* **The load-bearing constraint is in the same paragraph:**
*"the first contact must ride the app's prompt, since a skill can't ship
inside a plugin that isn't installed yet."* The agent can lay down BOTH
halves — the agent plugin and the desktop face's `plugin.js` (#270) — which
dissolves every file-system-navigation step. **CLI stays as the power-user
backup path: kept, documented, never the headline.**

The slice name comes from `handoffs/HANDOFF-2026-08-06-T27-EVENING.md`:
*"slices **B (conversational installer)**, C (desktop face), D (OJAMD
rollout)."* It is called "the Phase 2 design star" in #251.

**Open design questions this lane inherits (none answered):**
- What exactly the app's first-contact prompt says, and how consent is worded
  in chat — this is a **capability claim made by the app on the agent's
  behalf**, which puts it in the same family as #257 (the on-device model
  under-selling its own toolbelt). Wording is bars-worthy.
- The verification probe: how the app confirms the install actually took, and
  what it shows when the agent's host refuses or half-completes (a partial
  install is the realistic failure, not a clean one).
- Hosts where the agent has no write access to `~/.hermes/plugins/`, and
  whether the flow degrades honestly (#180's rule) rather than claiming
  success.

**Bars pre-register HERE before any code** — and given this lane is mostly
prose the model must produce, the #200-series discipline applies: measure the
behaviour, do not assume the instruction landed.

> **Update 2026-08-07 (momentum report, validated):** the pattern itself got
> external confirmation — `different-ai/openwork` ships install-via-an-
> existing-AI-agent as a first-class path, so #251's "the agent is the
> installer" shape is convergent, not exotic. One SHARPENING to adopt when
> this opens: the verification step must be MACHINE-VERIFIABLE, never the
> agent's prose. The app already plans to "probe to verify" (#251); make
> that probe deterministic — plugin name, version, protocol version,
> capability list, and an explicit installation state, so a partial or
> stale install is DETECTABLE and the app never renders 👍 off "Done!".
> Rides the existing authenticated plugin surface (pair/status family), not
> a new endpoint invented for it. Source + validation:
> `planning/reports/2026-08-07-open-source-momentum-report.md`, #284 note.

**2026-08-09 — INVESTIGATED AND SPLIT; the lane is PARTIALLY BLOCKED and the
split is the finding** (`dispatch/FABLE-T27-269-conversational-installer.md`;
read-only probes of the live Mac install; Owen deferred the BUILD to the host
sitting — this filing is the orchestrator's T0, code waits):

**Two blockers, both verified, neither fixable inside this lane:**
1. **The plugin repo is PRIVATE** and `hermes plugins install` is git-only,
   non-interactive (`plugins_cmd.py:485-492`) — no user's Hermes can clone it.
   **Filed as #308; Owen routes.** Publishing unblocks only half (see #308).
2. **There is no reload.** `discover_and_load` early-returns on a
   process-global singleton; `force=True` has one unrelated non-test call
   site; the agent runs IN-PROCESS — so an install's last step is restarting
   the process the agent lives in. An agent cannot narrate its own success
   across that boundary. (This same limitation DODGES the #263(a) reload
   trap — an install cannot trigger a discovery pass at all.)

**The split:** **269-A (the honest verification half — UNBLOCKED, app-side
only, no live-install change on path (i))**: the machine-verifiable
install-state probe, the honest state model, PLUGIN LINK stops believing the
keychain, the stale SETUP card retired. **269-B (the conversational install
itself — BLOCKED)** on #308 plus a decided restart story. **The architecture
both halves must respect: the agent narrates WHY, the app verifies WHETHER,
and the app never upgrades the agent's narration into a verdict** — from the
app's side "never installed", "on disk but not enabled", and "enabled but not
restarted" are INDISTINGUISHABLE (all 503); only the agent can tell them
apart.

**Verified seams for 269-A (probed live, read-only):** unauthenticated
`POST /api/platforms/{p}/events` returns **401 when the adapter is registered
vs 503 `platform_unavailable` when absent** — a deterministic, already-shipping
installation-state signal needing zero plugin change. The richer option is a
`describe` verb in the envelope's dispatch table (~six lines, authenticated by
the API key the app already holds) — that catches STALE installs, which
401/503 cannot see, but requires the 🔐 live-install gate to deploy. A
capability probe MUST be an envelope verb — a plugin cannot add a `:8642`
route (platform-adapter contract: two hooks behind the single events route);
the momentum-report sketch of `GET /talaria/capabilities` is corrected by this
(its §4 carries the supersession note).

**Corrections filed 2026-08-09 (dispatch §3, upstream homes):**
- The app's SETUP card teaches RETIRED commands —
  `ConnectHermesHostScreen.swift:110-112` ships `hermes-mobile setup` /
  `pair-phone` / `service install`, the venv CLI family #251 Phase 1 records
  as deleted (replaced by `hermes talaria …`). The tracker says they are
  gone; the app still tells users to run them. 269-A-D owns the fix.
- `hermes plugins enable` prints *"Takes effect on next session."* — FALSE
  for the gateway (process-global singleton; the agent runs in-process). An
  agent that believes its own tooling will report success that has not
  happened — a hard reason 269-A (machine verification) must exist before
  269-B, and an upstream-report candidate (queued with #264's, subject to the
  no-external-submission rule).
- The parent brief's "#113 supervision gap" pointer is stale — #113 closed
  2026-07-25; the surviving half is #188, DECLINED under the no-hardening
  rule. Neither bears on this lane.
- #263(a) does not block this lane (see blocker 2's note).

**BARS — pre-registered 2026-08-09 (filed-and-blocked is a result, not an
omission; a missed bar is a falsification):**
- **269-A-A (probe distinguishes live from absent, real host):** the app's
  probe resolves live vs not-live, each verdict tracing to the observed HTTP
  status (401 vs 503), never a stored token. Negative arm from a
  profile/host without the plugin — no live-install change. [live host, no
  device required]
- **269-A-B (PLUGIN LINK stops believing the keychain):** a phone holding a
  valid device token, pointed at a host with no adapter, renders NOT LIVE —
  not PAIRED. `TalariaLinkState.resolve`'s token-only signal no longer
  decides alone. The #264 "one banner and one truth" repayment. [unit +
  screenshot]
- **269-A-C (the app never claims to know WHY):** not-live copy states what
  was observed and never asserts a cause it cannot distinguish; every string
  maps to the observation licensing it. [offline]
- **269-A-D (the stale SETUP card is gone):** `rg -n 'hermes-mobile'
  Talaria/` returns no user-visible string. [offline] **✅ MET 2026-08-16 —
  executed by the #352 lane (Owen's Q1 "ride along"), merged `f6b8367`: the
  SETUP card teaches `hermes talaria pair`, and a SECOND user-visible
  string this bar's grep caught — the manual-entry error hint in
  `RelaySetupCodePayload.swift` — was fixed with it. Remaining grep hits
  are two WebRTC wire identifiers (not user-visible). The rest of #269-A
  (probe, honest state model, 269-A-A/B/C/E) stays open and unclaimed.**
- **269-A-E (gate):** `lane-gate.sh` PASS, unit count moved. [Mac]

> **269-A LANE OPENED — 2026-08-16 night (Owen's routing: #269-A → #270 →
> 3C-in-new-session; #353 route (b) folds in here). Design approved in
> discussion; spec:
> `planning/superpowers/2026-08-16-269A-plugin-link-honesty-design.md`.
> Bars A-A/B/C/E stand as written (D was MET via #352). Extension and one
> adaptation, pre-registered before code:**
> - **269-A-F (#353(b), NEW):** the About status panel gains a Plugin Link
>   row (same composed observation), and Relay Link/Relay Identity regroup
>   under a `// Legacy Relay` header with DERIVED severity: plugin observed
>   LIVE ⇒ relay-unreachable renders muted `OFFLINE`, never red; plugin NOT
>   live ⇒ red stands (the relay would be the only phone-facing channel).
>   The derivation is a pure function with table tests; device screenshot
>   arm shows no red ERROR row on the current rig (plugin live, relay
>   retired). [offline + device — Owen]
> - **269-A-A ADAPTATION (recorded, not redefined):** the bar's "negative
>   arm from a profile/host without the plugin" was written 2026-08-09 when
>   such a host existed; both hosts now run the adapter (#271). The 503 arm
>   becomes a stubbed-HTTP unit test against the classifier (a real 503
>   response through the URL-loading path), the 401/LIVE arm stays live
>   against OJAMD, and the transport-error arm uses a refused port. Probing
>   a live host read-only needs no gate; no live install is modified.
> - **Deliberately NOT this lane:** the drawer footer + settings grid strip
>   (#350's surfaces — the machinery built here is adoptable there, and
>   #350 pre-registers its own bars); any plugin-repo change (the probe is
>   the verified unauthenticated 401-vs-503 seam, zero new contract — the
>   `describe` envelope stays a gated later idea); PairingStore/voice.

> **✅ 269-A LANE RAN AND MERGED — 2026-08-16 night, same session
> (`a39150e`, merge commit, GitHub PR #309, branch deleted). Bars A-A
> (adapted arms: live 401 from OJAMD verbatim; stubbed 503/418; dead-port
> timeout → HOST UNREACHABLE), A-B (TalariaLinkState DELETED; composer
> takes the raw token so empty-string-is-not-a-token lives once), A-C
> (closed vocabulary), A-E (GATE: PASS — 2233 Swift Testing + 14 XCUITest
> + Release; 2225→2233/+9−1 reconciled), and A-F's offline half (severity
> table all four cells) MET. REMAINING: A-F's device glance — About shows
> Plugin Link LIVE · PAIRED and Relay Link muted OFFLINE, no red row —
> after the next install. 269-B unchanged (blocked on #308 + restart
> story); the rest of #269-A's arc (probe-driven state model is BUILT;
> #350's surfaces can now adopt it) closes 269-A when the glance lands.**

> **✅ 269-A COMPLETE — 2026-08-16 ~10:01 PM, A-F's device glance MET on
> `whoGoesThere` (Owen's screenshots, minutes after the corded install):
> Plugin Link `LIVE · PAIRED` green — a live probe answering, not the
> keychain — `// Legacy Relay` grouping with Relay Link muted `OFFLINE`
> and Relay Identity beneath it, page hero HEALTHY, zero red rows. All
> #269-A bars (A-A..A-F) are MET; #353 closes with this and moves to the
> archive. #269 stays OPEN for 269-B only (blocked on #308 + the restart
> story). Standing note kept alive here: the info grid's `HOST VERSION —`
> stays honest-empty until a `describe` envelope exists — the richer probe
> this entry already records as the gated plugin+app option.**
- **269-B-A/B/C/D/E:** as written in dispatch §5 (clean e2e agent-driven
  install verified by the 269-A probe, not prose; injected partial states
  detected and named; wording measured N≥10 with the error path instrumented;
  honest degradation where the agent has no hands; consent is not the app's
  to give — the app asks before sending, Hermes asks before executing, and on
  an `approvals.mode: off` host the in-app ask still happens). **ALL BLOCKED
  on #308 + the restart story; every one needs the 🔐 live-install gate,
  per-experiment.**

**Task A1 (read-only, free, highest-value unknown):** trace whether a
desktop-app-only user's gateway is managed by the desktop backend
(`web_server.py` `start_gateway`/`restart_gateway`; `main.ts:8167` spawns
`serve --port 0`) — if the desktop app can bounce its own gateway, blocker 2
softens to "ask the user to click restart" and 269-B's viability materially
improves. Owed before any 269-B design. Also flagged, NOT designed against:
`POST /api/gateway/restart` (`web_server.py:4038-4052`) appears to lack a
`_require_token` call — trace the middleware before reporting upstream; do
not use the endpoint either way.

**Shared vocabulary with #270 (settle once, at the host sitting):** proposed
NOT INSTALLED · INSTALLED, NOT LIVE · LIVE — noting the app alone can only
distinguish LIVE from the other two.

> **2026-08-18 header correction:** 269-A is COMPLETE — 2026-08-16 ~22:01,
> PR #309 merge `a39150e`, bars A-A..A-F met, device glance passed (Plugin
> Link LIVE · PAIRED, Legacy Relay muted OFFLINE). The header's "NOT
> STARTED" described the filing day. Open ONLY for 269-B (publication) —
> whose moment now also fires #308's ruling (repo goes public) — plus the
> undecided restart story (Task A1, read-only, is the free next step).

> **⚖️ RULED 2026-08-25 night (Owen, AskUserQuestion): RUN TASK A1
> FIRST.** The restart-story ruling is deliberately DEFERRED until A1's
> read-only trace answers whether the desktop backend can bounce its own
> gateway (which would soften the whole question to "ask the user to
> click restart"). A1 dispatched the same night — read-only over the
> upstream checkout on this Mac, no live install touched; the flagged
> maybe-unauthenticated `POST /api/gateway/restart` gets its middleware
> traced in the same pass, findings INTERNAL pending Owen's per-submission
> go (the standing external-submissions rule). Results file here.

> **📏 TASK A1 COMPLETE — same night (Sonnet read-only trace, upstream
> checkout `beb794123`, clean tree; full report in the session
> transcript). THE ANSWER DISSOLVES BLOCKER 2:**
> - **A desktop-only user already has a first-class gateway restart —
>   shipped, two ways:** the statusbar Gateway popover's Power-icon
>   "Restart Gateway" button (`apps/desktop/src/app/shell/
>   gateway-menu-panel.tsx:203-213`) and the Command Palette entry
>   (`command-palette/index.tsx:922`). Both → `POST /api/gateway/restart`
>   on the desktop's OWN backend, which spawns a detached
>   `hermes gateway restart` (`web_server.py:4789-4846`) that tries the
>   OS service manager first, then kill-and-respawn.
> - **The desktop app does NOT manage the gateway process itself** — its
>   `serve --port 0` children are its own dashboard backends (in-repo
>   comment: "the gateway isn't running under the app"); the restart is
>   control-plane-by-HTTP, matching the CLI exactly.
> - **Upstream treats gateway restart as a DELIBERATE, disruptive
>   action** — the button's own comment says it was visually isolated
>   "so it can't be hit by mistake." Evidence AGAINST any silent
>   auto-restart in 269-B's flow.
> - **Security flag RESOLVED BENIGN (static, internal):** the route has
>   no inline `_require_token`, but the global `auth_middleware`
>   (`web_server.py:935-956`) 401s every non-allowlisted `/api/*` path
>   first — `gateway/restart` is not on `PUBLIC_API_PATHS` and not a
>   registered token route. The per-route helper is redundant
>   belt-and-braces (its own docstring says the middleware is
>   authoritative in gated mode). Nothing to report upstream; the old
>   "do not use the endpoint either way" caution is superseded — it is
>   gated like the rest of the dashboard surface. (Routes belong to the
>   DASHBOARD app :9119, not the :8642 chat plane — two-of-everything
>   held.)
> - **Stale cite corrected:** the entry's `main.ts:8167` now points at
>   cloud-agent discovery; the real spawns are `:10502-10503` and
>   `:10848-10849` at this HEAD. And the desktop Electron source lives
>   IN the hermes-agent repo (`apps/desktop/`) — no asar spelunking
>   needed, ever.
> **THE RESTART RULING IS NOW READY (recommendation put to Owen in-chat
> the same night): the agent/app never restarts the gateway silently —
> 269-B's installer flow ends by pointing the user at the existing
> Restart Gateway affordance (popover Power icon / palette), matching
> upstream's own deliberate-action UX. Awaiting his word.**

> **⚖️ RULED 2026-08-25 night (Owen: "ruled, sounds good"): AS
> RECOMMENDED.** The agent/app NEVER restarts the gateway silently;
> 269-B's conversational-installer flow ends by directing the user to
> the existing Restart Gateway affordance (statusbar Gateway popover's
> Power icon, or the Command Palette entry). No new restart mechanism is
> built, ever — the ruling is a standing constraint, recorded so a
> future lane cannot reach for an auto-restart when the flow feels
> long. **#269's remaining scope is now exactly one thing: the 269-B
> publication moment (which also fires #308's repo-goes-public ruling),
> gated on Owen per the standing external-submissions rule.**

> **⚖️ RULED 2026-09-01 (Owen, AskUserQuestion, overnight election): CONSENT
> WORDING = CANDIDATE B ("verification-forward"), verbatim and now pinned:**
> - Title: **"Set up the plugin over chat?"**
> - Body: **"Talaria sends your agent the install instructions; you approve
>   the steps on the host. Talaria then verifies the install with its own
>   probe — it won't take the agent's word for it."**
> - Confirm / decline: **Send · Not Now.**
> - Restart guidance deliberately moves to the COMPLETION state (per the
>   08-25 no-silent-restart ruling: point at the host's existing Restart
>   Gateway affordance), NOT the ask.
>
> **📋 2026-09-01 — 269-B APP HALF OPENED (overnight; Owen's election).
> Scope split on the record:** both original blockers are dissolved — the
> restart story RULED 08-25, and the private repo stopped gating when
> `hermes plugins install`'s `git@`/`ssh://`/`file://` + `--ref` support
> was measured (08-31) — **but bars 269-B-A/B/D/E and the N≥10 half of B-C
> all need a LIVE HOST and the 🔐 per-experiment go, which cannot be
> granted overnight.** Tonight builds the APP HALF only; B-A..E stand as
> written and wait for an approved window. App-half bars, pre-registered
> before code:
> - **269-B-F (consent-before-send, wired):** the setup prompt cannot reach
>   the transport without the consent affordance's explicit confirm, and
>   the consent copy is Owen's ruled Candidate B VERBATIM, pinned by test
>   so a wording change is a deliberate act. Mutation arm: bypassing the
>   confirm must turn the wiring test RED. [offline]
> - **269-B-G (the verdict comes only from the probe):** after a setup
>   turn, the rendered install state derives exclusively from the 269-A
>   probe; no string in the agent's reply can flip the surface to LIVE.
>   Mutation arm: wiring the verdict to reply text must go RED. [offline]
> - **269-B-H (honest not-live copy + the restart pointer):** the
>   not-live-after-setup state says only what was observed (269-A-C's
>   closed vocabulary EXTENDED, not forked) and points at the host's
>   existing Restart Gateway affordance — never an in-app restart, never a
>   cause claim the app cannot distinguish. [offline]
> - **269-B-I (the first-contact prompt is a pinned constant):** the prose
>   the app sends is a testable constant, parameterized on install source
>   (repo URL + `--ref`), instructing the agent to narrate before acting,
>   to report failure honestly rather than retry silently (#180's rule),
>   and NEVER to restart the gateway itself (08-25 ruling). Pinned by
>   test. [offline]
> - **269-B-J (gate):** `lane-gate.sh` PASS, count moved. [Mac]

> **✅ 269-B APP HALF — BUILT 2026-09-01 overnight. Bars 269-B-F/G/H/I MET,
> RED-first with recorded output and two mutation arms that each isolated
> exactly the pin they name. 🔴 269-B-J is MISSED — `lane-gate.sh` never
> printed `GATE: PASS`, and that is recorded as a falsification, not
> redefined into a pass. B-A/B/D/E and the N ≥ 10 half of B-C are UNTOUCHED
> and stay open, awaiting a live host and the 🔐 per-experiment go. #269
> STAYS OPEN.**
>
> **PR https://github.com/AethyrionAI/Talaria-27/pull/400 — OPEN, NOT MERGED.**
> The standing overnight rule is merge-on-green; the gate was not green, so
> the merge is Owen's call rather than this lane's. Branch
> `claude/t27-269b-app-half` (commits `43ee3282` code + `6c263128` tracker).
> No squash SHA to record yet — the block below is what the merge decision
> should be read against.
>
> **What shipped.** Four new files —
> `Talaria/Models/TalariaPluginSetupPrompt.swift` (`TalariaPluginInstallSource`
> + the first-contact prompt), `Talaria/Stores/PluginSetupStore.swift` (the
> consent gate, three injected seams, the verdict),
> `Talaria/Features/Chat/PluginSetupCard.swift` (consent card, progress row,
> result row), `TalariaTests/PluginSetupConsentTests.swift` (20 tests) — and
> four touched: `TalariaLinkObservation.swift` (the completion vocabulary,
> EXTENDED onto `TalariaLinkDisplayState`, never forked), `ChatScreen.swift`,
> `ServerSettingsScreen.swift`, `AppContainer.swift`.
>
> **Where consent landed, and the pattern it follows.** In CHAT, at the tail
> of the transcript, as a third card in the family `ToolConfirmationCard`
> (#29) and `HostApprovalCard` (#304) already established — titled ask, two
> plain buttons, a notice row that takes the card's place when it settles.
> That is #251's sentence honoured literally: *"consent surfaces in chat where
> the user lives; the app probes to verify."* The ENTRY is on the Server
> screen, gated by `PluginSetupStore.offersSetup(for:)` on a MEASURED
> `.notLive` and nothing else — a live host is not nagged, and an unmeasured
> one gets no offer invented out of an absence of measurement.
>
> - **269-B-F MET (consent before send, wired).** Candidate B pinned verbatim
>   in `PluginSetupStore.Consent`; a separate pin holds that the ASK carries no
>   restart guidance (the 08-25 ruling put that in the completion state on
>   purpose). `confirm()` is the only door — it guards on `.awaitingConsent`
>   and ASSEMBLES the prompt inside itself from the source the ask carried, so
>   no built string exists for another path to send. **Mutation:** drop the
>   phase guard ⇒ `confirmIsTheOnlyDoorAndOnlyFromTheAsk` RED (4 issues) and
>   **nothing else moved**.
> - **269-B-G MET (verdict only from the probe).** `verdict(agentReply:
>   observation:deviceToken:)` composes #269-A's own
>   `TalariaLinkDisplayState.compose` — the same two facts the PLUGIN LINK row
>   reads, so the two surfaces cannot disagree. `agentReply` is accepted **and
>   deliberately unread**: a signature that never took it could not be mutated
>   into reading it, and a pin that cannot go RED under the mutation it names
>   is not a pin. Four success-claiming replies against a 503 still render NOT
>   LIVE; three failure-claiming replies against a 401 still render LIVE.
>   **Mutation:** a naive prose scan ⇒ `noProseCanFlipTheSurfaceToLive` (3),
>   `noProseCanSuppressALiveProbe` (3), `theSettledPhaseCarriesTheProbesVerdict`
>   (1) RED.
> - **269-B-H MET (honest not-live copy + the restart pointer).**
>   `TalariaPluginSetupCompletion` EXTENDS #269-A-C's closed set — all five
>   display states `resolve` onto it, and the one case that is about the PHONE
>   (`promptNotSent`) is pinned unreachable from any observation. The not-live
>   copy names the observation (*"the plugin did not answer"*), says out loud
>   that the cause is not knowable (*"Talaria cannot tell from here whether it
>   is missing, switched off, or waiting on a restart"*), defers WHY to the
>   agent's own message, and points at the host's shipped control (*"use
>   Restart Gateway on the host — the Gateway popover's power button, or the
>   Command Palette entry"*). Pinned: exactly ONE state names that control, no
>   state offers an in-app restart, no state asserts one of the three
>   indistinguishable causes, only `.live` reads as success.
> - **269-B-I MET (the prompt is a pinned constant).** Parameterized on
>   `TalariaPluginInstallSource`, asserted on the actual string for every ruled
>   constraint: narrate first (*"before you do it"*), `hermes plugins install
>   <source> --ref <ref>` + `hermes plugins enable talaria`, **"Do not restart
>   the gateway"** verbatim (08-25) with the Restart Gateway pointer for the
>   USER, **"Do not retry silently … do not report a success you did not
>   observe"** (#180), and *"Talaria probes this host itself … it will not take
>   your word for it."* Also pinned pure: same source ⇒ same bytes.
>
> **Default install source, RESOLVED rather than remembered:**
> `https://github.com/AethyrionAI/talaria-plugin.git`, read read-only from the
> deployed checkout's own git remote (`~/.hermes/plugins/talaria/.git/config`)
> — nothing under `~/.hermes` was modified. Ref defaults to `main`, NOT a
> pinned sha: the app cannot know which sha is good and a frozen one rots into
> a stale install, so the parameter exists for a caller that does know. The
> constant carries a comment tying it to the 269-B publication moment — **the
> repo is still private, and #308 is the ruling that flips it.**
>
> **RED-first, recorded.** The 20 tests ran against compiling STUBS before any
> implementation: **20 tests, 18 failed, 58 issues.** Two passed vacuously
> against the stubs (`theAskCarriesNoRestartGuidance`,
> `decliningSendsNothingAndClaimsNothing`) — recorded rather than papered over.
> GREEN after implementation: `Test run with 20 tests in 1 suite passed` ·
> `** TEST SUCCEEDED **`.
>
> **🔴 269-B-J — THE GATE DID NOT GO GREEN, AND THE CONTROL RAN INSTEAD OF THE
> ARGUMENT.** Swift Testing and the count bar are unambiguous: **2803 tests in
> 239 suites PASSED**, twice, against a base of **2783 in 238** — exactly the
> +20/+1 this lane adds, so the count MOVED and it is not a stale `.xctest`.
> The XCUITest half failed BOTH branch runs on
> `TalariaUITests.testConnectedRelaunchSkipsTheConnectEntry`
> (`AppTemplateUITests.swift:540`), so "it passes on identical bytes" does NOT
> hold and this could not be called a flake on that basis. **A structural alibi
> was available and deliberately not used** (this diff adds a chat card that
> renders only when its store leaves `.idle`, a Server-screen view that renders
> only on `.notLive`, and three closure assignments — the Connect Host wizard
> runs none of it), so the base control ran:
>
> | arm — same box, same simulator | Swift Testing | that test |
> |---|---|---|
> | branch `43ee3282`, full gate, run 1 | 2803/2803 ✅ | **FAILED** |
> | branch `43ee3282`, full gate, run 2 (sim recycled, box quiet) | 2803/2803 ✅ | **FAILED** |
> | **base `4a59b963` = `origin/main`, NO lane changes, full gate** | 2783/2783 ✅ | **FAILED, same line** |
> | branch `43ee3282`, `-only-testing:TalariaUITests` (isolated bundle) | — | **15/15 PASSED**, `** TEST SUCCEEDED **` |
> | branch `43ee3282`, Release build | — | `** BUILD SUCCEEDED **` |
>
> **Unmodified `main` reproduces it, and the branch's own XCUITest bundle
> passes 15/15 in isolation** — the isolation-passes / suite-fails shape #219
> already records, now with a base row under it. And #219's XFLAKE tripwire — armed
> 2026-08-27 precisely so the next natural red would self-document — FIRED and
> named the mechanism in all three runs: `XFLAKE pre hittable=false` at frame
> `(24.0, 509.0, 372.0, 56.0)`, then `post wizardUp=true composerIn5s=false`.
> The two PASSING instances in the same logs read `hittable=true` at the
> **identical frame**. So the button exists, is laid out identically, and is
> simply not hit-testable at tap time — an idle/hit-test race, not layout and
> not this diff. Artifacts: `~/.talaria-instrument-runs/20260901-xflake-269b/`
> (three suite logs, branch ×2 + base ×1; the run-1 `.xcresult` is PARTIAL —
> `xcodebuild` hung ~9 min writing a 318 MB bundle and was killed, so it has no
> `Info.plist` and `xcresulttool` cannot open it. The XFLAKE lines in the logs
> carry the finding regardless).
>
> **So 269-B-J is MISSED as written** — `lane-gate.sh` did not print `GATE:
> PASS`. It is recorded as MISSED rather than redefined, per this project's own
> rule that a missed bar is a falsification. What it is NOT is evidence against
> this lane's code, and the base row is why.
>
> **⚠️ AND THE TALLY IS WORSE THAN #219's RECORDED RATE.** That entry measured
> ~4 fails in 10 full-suite runs; tonight is **3 for 3** across two trees. The
> earlier hours of this session ran two concurrent lane gates on this box.
> Whatever tonight's condition is, it is a property of the machine and it is
> currently near-deterministic — worth knowing before the next lane reads a red
> here as its own.
>
> **Close-out corrections landed in the same PR (THE CLOSE-OUT RULE).** The
> dispatch brief had the agent restarting itself in TWO places — §2's vision
> prose (*"…and restart myself — I'll be back in about twenty seconds"*) and
> §5's 269-B-A (*"installs + enables + restarts"*). Both are falsified by the
> 2026-08-25 ruling and would have taught the next reader to build the one step
> it forbids. Dated supersession notes now sit at both sites; **269-B-A is
> AMENDED, not redefined** — the agent installs + enables and STOPS, the user
> restarts from the host's own affordance, and its evidence and 🔐 gate stand
> unchanged.

> **✅ 269-B-J SUPERSEDED: MET — 2026-09-01 ~02:27, on the pre-declared final
> roll.** The bars above record J MISSED honestly at the moment of filing;
> this block supersedes rather than rewrites. After the #219 hedge attempt
> was falsified (that entry, same night), a stopping rule was declared BEFORE
> the last run: one final gate on the rebased bytes — the same
> identical-bytes re-roll #166a's Gate4 green was accepted on — then
> merge-or-hold. It ran on CC-lane-2, box quiet: **GATE: PASS on 24A5423a —
> 2809 Swift Testing (+20 exactly this lane) · 15/15 XCUITest (counted from
> the `Test Case` ledger directly, because #423) · Release clean**
> (`talaria-gate.qGBfEfdv9p`). Identical compiled bytes to the two red rolls;
> the red is #219's flake, tallied there. **MERGED — PR #400, squash
> `582a8b49`.**
> - Two rebases rode the merge: post-#166a (pbxproj regenerated, ZERO drift,
>   gate re-run = the pass above) and a final tracker-markdown-only
>   conflict resolution against `20ee4e6f` (entry-219 union, chronological
>   order) — **no re-gate after the second, stated deliberately: no compiled
>   input changed.** Invariants PASS at both.
> - **Open on #269 after tonight: exactly the live-host half** — 269-B-A/B/D/E
>   and B-C's N≥10 measurement, all waiting on a 🔐 per-experiment go with the
>   host awake. The app half (F/G/H/I/J) is done.

## 263. 🐛 Plugin transport: discovery-pass module reloads SPLIT the hub singleton (tool gated against a live phone), and the enqueue wake misses the parked drain (every query rides a full 25s poll cycle racing the 25s timeout) — **FILED 2026-08-06 late night from live forensics during the 260-E pass; absorbs 2A-B's owed transport instrumentation**

Two related defects, one module-lifecycle root, both observed live tonight:

**(a) The split hub.** Post-bounce, the gateway ran 8 plugin-discovery
passes; the platform adapter binds `HUB` at an early pass while `tools._hub()`
re-resolves `from .transport import HUB` at call time — after any reload
those are DIFFERENT `TransportHub` instances. Symptom observed: the phone
long-polling every 25s (access log, store `last_seen` advancing) while
`_transport_available` read a hub nobody touched — `talaria_phone_query`
"not available in this session" forever, on a live phone, in fresh sessions.
A second bounce restored coherence (a fresh process starts aligned, like the
17:33 process that served the whole evening pass correctly). NOT caused by
the #260 prose change — nothing in that diff touches imports or hub
lifecycle; the trigger is bounce + later discovery passes.

**(b) The wake-miss.** Even hub-coherent, tonight's queries resolved at
EXACTLY 25.00s — one full long-poll hold — with the phone parked the whole
time: the enqueue-side `wake()` never released the park. With
`_QUERY_TIMEOUT == 25.0 == park hold`, every query races the timeout: the
master-off leg won by 0.4s, the allow leg lost once ("did not answer in
time") and won on retry mid-cycle. This IS the transport-leg number 2A-B
owed: **delivery-to-answer is fast; DELIVERY waits up to a full park cycle.**
May be (a) wearing another face (park's event in one hub, wake in another)
— unresolved; instrument before fixing.

**Fix candidates when the lane opens (bars pre-register HERE):** a
reload-proof hub anchor (process-global registry keyed by plugin name, or
tools binding the hub at registration time from the SAME pass as the
adapter); store-backed liveness as the check_fn source (window widened past
the 60s store-write throttle); timeout margin (query timeout > park hold);
and a wake-path integration test that fails on a full-cycle delivery.

> **Update 2026-08-06 late night — SCOPED against the code + the live logs. (b) PROVEN
> and it is WORSE than filed (universal, not a race). (a) AS FILED
> FALSIFIED — the reload path does not split the hub, and the evening's
> live evidence does not survive the timeline either. Lane splits: ship (b)
> + instrumentation; (a) → WATCH with counters.** Read-only throughout —
> the live checkout stayed clean at `4205d1a`, the gateway was never
> bounced. Study worktree: `~/Documents/Claude/t27-263-plugin/talaria`
> (branch `claude/t27-263-transport-instrumentation`), 60/60 green.
>
> **(b) PROVEN — a cross-loop wake, not a missed one.** The wake is *sent*;
> it just never wakes the loop. Every async plugin tool is bridged off the
> caller's loop: `tools.py:132` registers `is_async=True`, and
> `tools/registry.py:773-775` dispatches through `model_tools._run_async`,
> which **always** runs the coroutine on a different loop in a different
> thread (`model_tools.py:150-156` spins a fresh loop when already inside an
> async context; `:77-89` is the persistent one otherwise). So `park()`
> (`envelope.py:145` → `transport.py:45-66`) sits on the api_server's HTTP
> loop while `enqueue_query()` + `wake()` (`transport.py:76-100`) run on the
> tool loop. `asyncio.Event.set()` resolves its waiter with a plain
> `loop.call_soon()`, which only checks the calling thread in DEBUG mode —
> in production it appends to the target loop's `_ready` queue **without**
> `_write_to_self()`, so the parked loop stays blocked in `select()` until
> its next scheduled event. On a quietly-parked drain the next event is the
> 25s hold itself. The answer leg is the same defect mirrored:
> `resolve_query`'s `future.set_result` (`transport.py:128`,`:130`) fires on
> the HTTP loop against a future created on the tool loop
> (`transport.py:78`), and that tool loop is running *only* `phone_query`
> (`run_until_complete`), so its sole timer is the 25s `_QUERY_TIMEOUT` —
> every answer lands exactly on the timeout boundary and coin-flips against
> it inside one loop iteration.
>
> **Repro (worktree, hold shortened to 5.0s, wake fires at t=0.5s):**
> same-loop wake `0.502s` · cross-loop wake **`5.002s`** (full hold, and the
> query *was* present after the park — coherent hub, dead wake) ·
> cross-loop resolve **`5.002s`**, answered right on the boundary.
>
> **Why the suite could never see it:** `tests/test_transport.py:28-33`
> (`test_park_returns_early_on_wake`) parks and wakes **on the same loop** —
> it is the 0.502s arm. Green forever, blind by construction. Same shape as
> #258: a suite pinning a bar production violates.
>
> **(b) is INDEPENDENT of (a) — the entry's "may be (a) wearing another
> face" is resolved: it is not.** Under a split hub the query is enqueued
> into hub B while the drain reads hub A, so `take_queries` after the
> timeout (`envelope.py:148`) returns empty and `resolve_query`
> (`transport.py:107-109`) returns `False` — the query would never be
> delivered *or* answered. Ours were answered. The hub was coherent.
>
> **The live logs make (b) universal, not intermittent.** Every
> `talaria_phone_query` in `~/.hermes/logs/agent.log` that reached the phone
> on 2026-08-06 completed at **25.00–25.01s** — 16:26:04 (25.01s), 16:32:57
> (25.00s), 18:09:41 (25.01s), 18:14:32 (25.00s), 21:05:56 (25.00s),
> 21:09:51 (25.00s), 21:16:56 (25.00s), 21:17:49 (25.01s) — **8 for 8,
> across two different gateway processes (the 18:59 and 21:03 bounces), both
> denial and allow legs.** The only fast one, 17:39:13 at 0.00s/116 chars,
> is the *unreachable* prose (`tools.py:68-71`), which never waits. So this
> is not "sometimes loses the race" — **it is a deterministic full cycle on
> every single query**, and the 0.4s and retry noted in the filed text are
> the boundary coin-flip, not the variable. The access log corroborates the
> mechanism directly: at 21:05 the drain that started 21:05:07 ran its full
> hold to 21:05:31 carrying the query (545 bytes vs the idle 489), the very
> next drain returned in ~0.5s with 473 bytes (the leftover set flag being
> consumed by `park`'s pre-check, `transport.py:52-54` — the predicted
> side-signature), and the tool completed at 21:05:56.473 with a real
> 237-char answer, 25.00s after enqueue.
>
> **(a) AS FILED FALSIFIED — the loader does not do this.**
> `hermes_cli/plugins.py:1885-1889` replaces **only the parent package
> object** (`sys.modules[module_name] = module`; `exec_module`) — the
> submodules stay cached under their own keys, so `from . import admin,
> tools` (`__init__.py:14`) and `from .platform_adapter import ...`
> (`__init__.py:21`) are cache hits and never re-run. Measured: **8 forced
> `discover_and_load(force=True)` passes against the real `PluginManager`**
> (isolated `HERMES_HOME`, only this plugin) — the parent module id churned
> on every pass while `transport` module id, `transport.HUB`,
> `platform_adapter.HUB` and `tools._hub()` all held at `4464329232`, and an
> adapter built from the **last** pass's `adapter_factory` reported
> `_envelope._hub` identical to `tools._hub()`. No split.
>
> **The split SHAPE is real, though, and reachable by two routes we did NOT
> observe — record both, they are what the counters watch for.** The
> asymmetry the entry describes exists: `tools.py:48-50` re-resolves `HUB`
> at every call (late), while `platform_adapter.py:20` and `:33` freeze it
> at import and at adapter construction (early), and `EnvelopeService` holds
> that reference for life (`envelope.py:57`). Two ways to make them diverge,
> both reproduced in the worktree: **(1) manifest-name divergence** — the
> slug comes from the manifest key (`plugins.py:1874-1876`), so the same
> directory loaded under two names yields two HUBs; one `plugin.yaml` edit
> or one relocation away; **(2) submodule eviction** — CPython drops a
> submodule from `sys.modules` when its `exec_module` raises, so any
> transient import failure inside the package leaves `transport` to be
> re-executed, after which the late side tracks the new hub and every early
> holder keeps the old one. Nothing in hermes-agent deliberately pops
> `hermes_plugins.*` today (grepped).
>
> **And the evening's live evidence for (a) does not survive the timeline
> either.** The symptom string is not ours — it is the deferred-tool bridge
> (`model_tools.py:1250`, `agent/tool_executor.py:793`), reached when the
> name is absent from the turn's definitions, which are gated by
> `tools/registry.py:425`/`:699` → `_check_fn_cached`. That gate logs, and
> the log has exactly **one** evening hit: `20:51:19,564 WARNING
> tools.registry: check_fn _transport_available returned False` — followed
> at `20:51:19,811` by the `talaria_phone_query` turn and at `20:51:32,370`
> by the "not available in this session" error. But the access log shows the
> phone's drains **stopped**: continuous `POST /api/platforms/talaria/events`
> every ~25s through a request starting `20:42:41`, then **nothing until a
> request starting `20:53:00`** — a ~10-minute app-side polling gap. The 60s
> liveness window (`tools.py:15`) expired ~`20:43:41`, eight minutes before
> the warning. **The transport really was dead and the gate reported it
> correctly.** Ruled out by the same timeline: **#264** (the failed bind was
> `20:57:12`, six minutes *later*, in a different process); **the 30s
> False-cache** (`registry.py:216`,`:337` — a 10-minute outage dwarfs a 30s
> TTL, so the cache was reporting truth, not staleness); **a split hub**
> (which would show False *while drains arrive* — here they had stopped, and
> 14 minutes later at `21:05:05` the same check_fn passed and the query was
> delivered and answered on that same process). The filed "forever, in fresh
> sessions" is **not** in the log: one hit, not a persistent condition.
> Recorded as a falsification against the filed claim, not an edit to it —
> (a) stays open as a WATCH because the shape is real, but its priors drop
> hard and nothing should be built for it until a counter fires.
>
> **LANE SPLIT (orchestrator decision, 2026-08-06 late night):** ship the (b) fix +
> the instrumentation; (a) becomes a **WATCH** with counters in place. This
> honors the entry's own "instrument before fixing" and avoids the #218
> shape — a fix for a mechanism no test can exercise.
>
> **BARS PRE-REGISTERED (bars written first, before any code):**
> - **263-A (wake-miss pin, unit):** a test that parks a drain on one event
>   loop and calls `enqueue_query`/`wake` from a *second* loop in a second
>   thread asserts delivery in **< 1s** against a 5s hold. It **FAILS on
>   today's code at ~5.00s** (measured: 5.002s vs 0.502s same-loop) and
>   passes after the fix. The existing same-loop
>   `test_park_returns_early_on_wake` stays, unmodified, as the control.
> - **263-B (answer-leg pin, unit):** a test that creates the query future
>   on the tool loop and calls `resolve_query` from a second loop asserts
>   the awaiting side observes the answer in **< 1s** against a 5s wait.
>   **FAILS today at the timeout boundary** (measured: 5.002s).
> - **263-C (timeout margin, unit):** `_QUERY_TIMEOUT` (`tools.py:14`) is
>   pinned **strictly greater** than the drain hold (`envelope.py:56`) by an
>   asserted margin, so no future edit can silently re-equalise them. Fails
>   on today's `25.0 == 25.0`.
> - **263-D (hub-identity pin, unit):** a test asserts that the hub reached
>   by `tools._hub()` and the hub held by a constructed
>   `TalariaPlatformAdapter`'s `EnvelopeService` are **the same object**
>   after the plugin package has been re-loaded the way
>   `hermes_cli/plugins.py:1885-1889` re-loads it. Passes today (correctly —
>   the reload path does not split); it is a **regression pin against the
>   two real routes above**, and it must be written so that forcing a
>   `transport` re-execution makes it FAIL — **demonstrate that failure
>   once, in the PR body, or the bar is unfalsifiable.**
> - **263-E (instrumentation, the one-grep bar):** with the counters below
>   in place, a single `grep talaria ~/.hermes/logs/agent.log` answers all
>   four of tonight's questions without a rebuild: **which** hub instance
>   the adapter attached, **which** hub the check_fn read, **how many**
>   module-load passes ran, and **how long** each query waited between
>   enqueue and drain. Acceptance: a scripted replay of the wake-miss
>   produces log lines from which the full-cycle delivery is identifiable
>   **by eye in under a minute.**
> - **263-F (no regression):** all 60 existing plugin tests stay green
>   unmodified; the Talaria app is untouched; no relay or connector change
>   (out of scope by the standing rule, and unnecessary — this plugin is
>   neither, and instrumentation is measurement, which that rule explicitly
>   allows).
> - **263-G (live verification — NEEDS OWEN'S EXPLICIT PER-EXPERIMENT GO):**
>   on the live install, with the phone paired and the app foregrounded,
>   three consecutive `talaria_phone_query` calls each resolve in **< 3s**
>   (today: 25.00s, 8/8), and the instrumentation log shows enqueue→drain
>   latency well under one hold. **This bar modifies a loaded plugin file
>   and requires a gateway bounce to take effect, so it is a live-install
>   experiment under the CLAUDE.md rule and must not run on an assumed
>   authorization.** The 2026-08-06 time-boxed clearance has expired. And
>   per #264: after the bounce verify the **LISTENER**
>   (`lsof -nP -iTCP:8642 -sTCP:LISTEN`), never the PID.
>
> **Instrumentation plan (the plugin has NO logger today — only `print`, so
> step zero is a module `logging.getLogger("talaria")`):** ① module-load
> stamp `id(module)`+`id(HUB)` right after `transport.py:153` — two lines
> means split, printed, no inference; ② adapter-attach `id(HUB)` in
> `platform_adapter.__init__` after `:35`; ③ check_fn-read `id(hub)` + the
> liveness inputs (`live`, `len(_parked_counts)`) in `tools.py:53-54`, so a
> *coherent* False (tonight's actual case) is distinguishable from a split
> at a glance; ④ enqueue→drain latency — stamp `time.monotonic()` into the
> query at `transport.py:92-94`, log the delta at `envelope.py:148` (**the
> transport number 2A-B owed**); ⑤ park exit reason `woken` vs `timed_out`
> + elapsed in `park`'s `finally` (`transport.py:61-66`) — under today's
> defect this reads `timed_out` on every delivery, the single most
> diagnostic line in the set; ⑥ `id(asyncio.get_running_loop())` on both
> the enqueue (`transport.py:78`) and park (`transport.py:46`) sides, so the
> cross-loop premise is self-evident instead of re-derived. Optional and
> cheap: surface the counters in `hermes talaria status` (`admin.py:50-62`),
> which turns the forensic into a CLI call.
>
> **Fix plan.** (b): capture the loop at park/enqueue time and schedule
> through it — `loop.call_soon_threadsafe(event.set)` in `wake()`
> (`transport.py:68-73`), and store the owning loop with the future at
> `transport.py:98` so `resolve_query` uses
> `call_soon_threadsafe(future.set_result, answer)` at `:128`/`:130`.
> Low risk, confined to `transport.py`; `call_soon_threadsafe` is correct
> same-loop too, so there is no branch to get wrong. One edge: a
> closed/finished tool loop raises `RuntimeError` — swallow it, the caller
> already gave up (`tools.py:76-85` discards on every exit path). Plus
> **263-C's margin**, which is a mitigation and not the fix — with the
> margin alone every query still costs a full 25s. Ships with a one-line
> comment at `transport.py:68` naming the cross-loop contract, so the next
> caller inherits the invariant rather than the bug. **Disagreement with the
> filed candidates, on the record:** "tools binding the hub at registration
> time from the SAME pass as the adapter" would make things *worse* — it
> converts the one self-healing late resolver into a second early binder,
> and under eviction two early binders split just as readily. A
> process-global anchor is the right shape but is a fix for a mechanism we
> have not observed firing. Store-backed liveness is worth considering on
> its own merits, with the cost the entry already flags: `envelope.py:132`
> throttles store writes to 60s, so widening the window past that makes the
> gate *less* responsive to a phone that just left.

> **Update 2026-08-06 ~22:33 — BUILT + DEPLOYED LIVE under Owen's 263-G go
> ("263-G is approved. if you need to install it and then bounce the
> gateway, thats fine"). Bars 263-A/B/C/D/E/F MET; 263-G's query half
> remains (Owen's phone, Mac profile).** TDD by Opus subagent, orchestrator-
> reviewed: RED measured all four cross-loop legs at the FULL hold
> (5.001s of a 5.0s hold — delivery, wake-all, answer, denial), GREEN at
> ~0.05s each (bounded by the test's own sleep); `_QUERY_TIMEOUT` 25→40s
> against the 25s hold (263-C); 263-D's falsifiability DEMONSTRATED (forced
> `transport` eviction → two hub instances → the pin fails with the right
> diagnosis; output recorded in the test docstring); suite 60→80, the
> pre-existing 60 byte-unmodified (`git diff 4205d1a` shows appends only).
> Plugin main ff'd `4205d1a`→`fd5d7d1`, live checkout ff'd, gateway bounced
> 22:33 — **listener verified per #264 (new PID 58870), and the new
> instrumentation's first live lines prove hub coherence at a glance:**
> `transport module loaded module=4494707664 hub=4494638288` then
> `adapter attach hub=4494638288` — one load line, same hub id, no
> inference. The one-grep bar (263-E) worked on its first boot. Latency
> stamps are stripped in `take_queries` before delivery, with a test
> pinning that they never reach the phone (#251's strict-decoder lesson).
> **Remaining: three consecutive sub-3s `talaria_phone_query` answers from
> Owen's foregrounded phone on the Mac profile (was 25.0s deterministic);
> then this closes and (a) survives only as the WATCH.**

> **Update 2026-08-06 22:49-50 — 263-G MET. The (b) half of this item is
> DONE end to end; the entry stays open ONLY as the (a) WATCH.** Owen ran
> three consecutive steps queries on the Mac profile (screenshot: Mac Mini
> ACTIVE, plugin link paired; build 2107). `agent.log`, verbatim:
> `22:49:47 query delivered … enqueue_to_drain=0.001s` → tool completed
> 0.15s · `22:49:58 … enqueue_to_drain=0.001s` → 0.21s · `22:50:11 …
> enqueue_to_drain=0.016s` → 0.07s. Three for three, tool waits under a
> quarter-second, from a 25.00s deterministic floor. (Orchestrator's
> wrong turn recorded: the instrumentation lines live in `agent.log`, not
> `gateway.log` — an "it was OJAMD" misread stood for ~10 minutes until
> Owen's profile screenshot corrected it.) **WATCH observation, first
> breadcrumb:** a SECOND `transport module loaded` stamp appears at
> 22:49:23 in `agent.log` with DIFFERENT module/hub ids than the 22:33:24
> boot stamp in `gateway.log` — either two processes each writing their
> own log (benign; disambiguate cheaply via `hermes talaria status`
> process-local counters or PID logging) or a genuine same-process
> re-execution (route 2 of the split shape, live). The queries delivered
> fine either way. This is exactly the breadcrumb the counters were built
> to leave; chase it on the next gated-against-live-phone incident, or
> add a PID to the load stamp when the lane next touches transport.py.

> **Update 2026-08-06 late night (Phase 3 scoping) — this item's lesson becomes a standing
> design rule for the runs migration.** Phase 3's steer/approval reach walks
> `gateway.run._gateway_runner_ref()` → `runner.adapters[Platform.API_SERVER]` →
> `._active_run_agents[run_id]`. **That walk resolves LATE, per call — the runner
> and the adapter are never cached at import or at construction.** This is exactly
> the early-binder shape the (a) WATCH exists for: `tools.py`'s late `_hub()` and
> `platform_adapter.py`'s import-frozen `HUB` are the two sides of it, and a cached
> reach would add a third. **Its failure mode there is silent** — `_active_run_agents`
> is a private attribute with no stability contract, so an upstream rename makes a
> steer stop landing with no error surface, and an unfound agent looks identical to
> a steer that did not land. So the plugin handler must return an explicit
> `agent_found:false` and the app must render it, and the steer path should stamp
> `id()` the way #263-E stamped the hub. Detail:
> `design/PHASE3-RUNS-MIGRATION-PLAN-2026-08-07.md` §2.3 + §4.2.

> **State check 2026-08-07 (tracker tidy pass) — still accurate as of
> today, with one caveat about the HEADER.** Nothing since 2026-08-06 has
> touched plugin transport, so the entry's live content is unchanged: **(b)
> is DONE end to end** (built, deployed, 263-G MET — three consecutive
> sub-quarter-second answers off a 25.00s deterministic floor) and **(a)
> survives ONLY as a WATCH**, with exactly one breadcrumb outstanding — the
> second `transport module loaded` stamp at 22:49:23 in `agent.log` carrying
> different module/hub ids from the 22:33:24 boot stamp in `gateway.log`,
> which is either two processes each writing their own log (benign) or a
> genuine same-process re-execution (the split shape, live).
>
> **The header is stale and is deliberately left as filed:** it asserts both
> defects as filed, and (a) AS FILED WAS FALSIFIED — the reload path does
> not split the hub. Read the 2026-08-06 scoping note, not the header. The
> cheap next step whenever transport is touched again is unchanged and is
> the whole content of the WATCH: **stamp the PID on the `transport module
> loaded` line**, which converts the breadcrumb into a one-glance answer.
> Nothing here is device work and nothing here blocks a lane.

> **2026-08-18 note:** the PID-log chore (`transport.py:307` /
> `platform_adapter.py:44`) has now been skipped by FOUR plugin releases
> (0.2.0 → 0.5.0). Fold it into the next plugin touch.

> **⟵ 2026-09-01 POINTER (hygiene sweep):** the count is stale. The live
> plugin checkout (`~/.hermes/plugins/talaria`) is at **0.8.0** (`b4e8dfa`,
> `plugin.yaml`); `git log --oneline -- plugin.yaml` shows three more
> version bumps since the 0.5.0 counted above — 0.6.0 (`dbf32c9`), 0.7.0
> (`b87cd6c`), 0.8.0 (`b4e8dfa`) — so the PID-log chore has now been skipped
> by **SEVEN plugin releases (0.2.0 → 0.8.0)**, not four. Still not folded
> into any of them.

> **📋 2026-09-01 (night) — 263-PID LANE OPENED (Owen's mandate).** The one concrete leftover, now SEVEN releases overdue (hygiene sweep `9f537b42`). ⚠️ The Mac's plugin checkout IS the live install (`~/.hermes/plugins/talaria`) — modifying it is a 🔐 live-install change, so the lane works on a FRESH CLONE of the plugin repo and the live install is not touched. Bars pre-registered before code:
> - **263-P-A (the line carries the PID):** the `transport module loaded` log record includes `pid=<os.getpid()>`, pinned by a pytest that captures the record. RED-first; removing the field re-reddens it. [offline, plugin repo]
> - **263-P-B (the repo stays green):** plugin pytest suite green (216 → 217), `hermes plugins doctor`-equivalent clean if the repo has one, version bumped per the repo's own convention, PR to the PRIVATE plugin repo merged (our repo — not an external submission). [offline]
> - **263-P-C (deploy is NOT this lane):** both hosts stay at 0.8.0 (`b4e8dfa`) until Owen's per-host go; the deploy rides a runbook desk card, and the result block says so plainly. [—]

> **✅ 2026-09-01 (night) — 263-PID RESULT: 263-P-A and 263-P-B MET, 263-P-C
> HELD. The chore that outlived seven releases is merged in the plugin repo
> and DEPLOYED NOWHERE.** Plugin PR
> [#8](https://github.com/AethyrionAI/talaria-plugin/pull/8), squash
> **`d69a5e2`** (`d69a5e28fbda5c6befc002ca9669d6d43ba3f9cb`), version
> **0.8.0 → 0.9.0**. Worked on a fresh clone in a scratch dir; the live
> install was read once (`git remote get-url`) and never written.
>
> **263-P-A MET — RED first, and the RED is the evidence.** The stamp fires
> at interpreter import, long before any test runs, so the pre-existing
> `test_module_load_stamp_names_the_hub_instance` could only grep the SOURCE
> that emits it. The new test CAPTURES the record: it re-executes
> `transport.py` into a throwaway module object — deliberately never
> registered in `sys.modules`, because a probe that installs a second
> `transport` would be manufacturing the very split this item watches for —
> and reads `caplog`. On pre-fix code:
> ```
> E  AssertionError: the module-load stamp must name the process that emitted it —
>    without it two loads and two processes are indistinguishable (#263 WATCH)
> E  assert 'pid=74342' in 'transport module loaded module=4312161624 hub=4410001648'
> INFO talaria:transport.py:306 transport module loaded module=4312161624 hub=4410001648
> 1 failed, 10 passed
> ```
> GREEN after `pid=%s` lands; removing the field again re-reddens it
> (mutation run with `__pycache__` purged and `PYTHONDONTWRITEBYTECODE=1`,
> so the `.pyc` staleness trap could not fake the result). **The record's
> existing text is intact** — `transport module loaded` is still one
> contiguous grep string with `module=`/`hub=` still following, so anything
> grepping the old line still matches.
>
> **263-P-B MET, with one stale number in the bar corrected.** The bar said
> "216 → 217"; the measured baseline on `b4e8dfa` is **256**, so the run is
> **256 → 257** — the `+1` is what the bar meant and the absolute was
> already out of date when it was written. Green under both `pytest tests/
> -q` and `python -m pytest tests/ -q`, `python -m compileall -q .` clean,
> and `hermes plugins doctor . --ci` **OK** at `talaria 0.9.0` (its single
> `WARN` — `pre_tool_call` not listed in `provides_hooks` — reproduces
> identically on `b4e8dfa`, so it is pre-existing, not this diff). Verified
> against the pinned hermes-agent `503d863f` (the README/CI pin) on Python
> 3.12 in a throwaway uv venv; the operator's hermes venv was untouched. CI
> passed both matrix legs (3.11, 3.12). **Version convention read from the
> repo, not assumed:** all eight releases bumped MINOR — including both
> `fix:` releases — and the repo has never cut a patch, so 0.9.0 is the
> convention and a patch bump would have been the departure. The
> `#308` floor tests (`manifest_version: 1`, README ↔ CI hermes-SHA
> lockstep) still pass untouched; the one existing test edited is
> `test_plugin_version_reads_the_yaml`, which IS the version lockstep pin.
>
> **263-P-C HELD — nothing is deployed. BOTH HOSTS STAY AT 0.8.0
> (`b4e8dfa`) until Owen's explicit per-host go**, which rides a runbook
> desk card. Confirmed after the merge: `git -C ~/.hermes/plugins/talaria
> status --short` empty, HEAD still `b4e8dfa36eb4a1460c4ff9449e8ec7c0cbdcca24`.
> The pid line therefore does **not** yet appear in any live `agent.log`;
> the 22:49 breadcrumb stays unresolved until a host runs 0.9.0.
>
> **⚠️ One hazard found and recorded, because the next lane will hit it:**
> `hermes plugins doctor` REGISTERS the plugin, and registration initializes
> the database — so a doctor run in a default environment reaches
> `<HERMES_HOME>/talaria/talaria.db`, the operator's real one. The first
> doctor run here did exactly that: the directory mtime moved while
> `talaria.db`'s own mtime and SHA-256 did not (checked before and after —
> an open, not a write), and every later run set
> `HERMES_HOME=<scratch>`. The `talaria.db.accidental-2026-08-16*` files
> sitting in that directory say this has bitten before. **Run doctor with an
> isolated `HERMES_HOME` — it is not a read-only command.**
>
> **Scope note:** the 2026-08-18 chore named two sites,
> `transport.py:307` *and* `platform_adapter.py:44` (`adapter attach
> hub=%s`). Only the transport stamp is in 263-P-A, so only it moved. The
> adapter-attach line still carries no pid; it is the cheaper half (one
> process's two lines are already correlated by the transport stamp above
> it) and is left for the next plugin touch rather than smuggled in
> untested.

## 254. 👁 Control Center "Ask/Talk to Hermes" buttons BIND — **Half 1 CONFIRMED WORKING on build 2034**; Half 2 (the ghost session) is a **connect-window OWNERSHIP RACE**, not a present-tense defect — **NOT REPRODUCIBLE on 2034, ⬇️ WATCH since 2026-08-05; mechanism named and its premise MEASURED (bar 254-F) 2026-08-09; app-side fix landed same day under bars 254-A/B/C — **254-D still OWED; ~~254-E~~ UNRUNNABLE AS WRITTEN on device 2026-08-09 (its airplane-mode pin collapses the connect window to 23 ms), with the native `LIVE` arm verified in its place and labelled as a substitute, not scored as the bar**

> **⚠️ HEADER CORRECTED TWICE, and this item is NOT closed.** The downgrade to
> WATCH was recorded in the body on 2026-08-05 but the header kept describing a
> live ghost, which is why the 2026-08-09 sweep commissioned a lane against it.
> A first pass that day appended the downgrade to the header but **left the
> leading clause present-tense** ("the voice session SURVIVES dismissing its UI
> and keeps talking at full volume") and left Half 1's CONFIRMED-WORKING status
> buried in a parenthetical. The header above is the second correction: Half 1
> leads as confirmed, Half 2 is named as a race with a measured premise. **The
> item stays open** — a watch with a named mechanism is worth more than a closed
> item with none, and the two device bars are still owed.
>
> **The mechanism, found 2026-08-09 and it explains the non-reproduction.**
> Teardown has exactly two owners: `VoiceOverlayScreen.onDisappear`
> (`VoiceOverlayScreen.swift:91-110`, deliberately unguarded per #139) and the
> #118 background observer (`AppContainer.swift:1148-1161`) — which **still
> carries the `isSessionActive` guard that #139 removed from the other path**
> (`TalkSessionRules.swift:32-34`). `isSessionActive` is **false for the entire
> connect window** (`TalkStore.swift:80-99`), so backgrounding mid-connect
> revokes nothing, the connect lands live in the background under
> `UIBackgroundModes: audio`, and `overrideOutputAudioPort(.speaker)` "for
> maximum volume" (`LiveVoiceSessionService.swift:757-762`) is literally
> Owen's *"full volume."*
>
> **Cold launch from Control Center is the slowest connect** — which is
> exactly why that path found it, and why re-testing a warm app "worked every
> time." **A race is what this looks like.** Do not read the 2034
> non-reproduction as a refutation.
>
> **First task when a lane opens is 254-F**, a one-minute check of the single
> ASSUMED step: does `onDisappear` fire when a `fullScreenCover` is
> backgrounded? It either kills the mechanism outright or promotes this from
> ghost to known race. Bars and the full trace:
> `dispatch/OPUS-T27-voice-130-138-254.md`.

> **🎯 BARS 254-A…F — PRE-REGISTERED 2026-08-09, BEFORE ANY FIX CODE.** Written
> here per the standing convention (bars live in the OPEN_ITEMS entry since
> #215; a dispatch doc is optional). 254-F's statement was pre-registered
> earlier the same day in `dispatch/OPUS-T27-voice-130-138-254.md` §6 and
> referenced from this entry above — it ran FIRST, against a bar already in
> writing, because it is the one bar that could retire the whole lane.
>
> | bar | statement | evidence | engine pin | device? |
> |---|---|---|---|---|
> | **254-A** | `TalkBackgroundRule` returns **true** for a session that is STARTING but not yet active, and still **false** for a genuinely idle store and for CarPlay. The existing `backgroundIgnoresIdleSession` pin is KEPT — an extension, not an inversion. | New red-first cases in `TalariaTests/TalkSessionRulesTests.swift`. | n/a (pure function) | **NO** |
> | **254-B** | Backgrounding while a start is in flight **revokes** it: the voice service records an `endSession`, and a snapshot returning afterwards does not flip the store live. | Store-level test driving `TalkStore` against a delayed-start stub. **RED first — confirmed failing against HEAD.** | n/a | **NO** |
> | **254-C** | Backgrounding with **no** session and **no** start in flight calls nothing — no `endSession`, no `setActive(false)`. Guards the #84 stray-deactivation regression. | Same harness, negative case. | n/a | **NO** |
> | **254-D** | Control Center → "Talk to Hermes" from a cold app, background the phone **before** the header leaves `VOICE LINK · CONNECTING`, wait 60 s: **silence**, mic indicator dark, and the log carries the revoke line. | Device log; must quote the engine line. | **realtime** (paired + relay healthy) | **YES** → `DEVICE-PASS-RUNNING-LIST.md` §F6 |
> | **254-E** | Same as 254-D on the other engine. | Device log; must quote the engine line. | **native** (airplane mode) | **YES** → §F6 |
> | **254-F** | `onDisappear` firing behaviour on background is **recorded**, not assumed. **This bar can retire the whole lane.** | One `.notice` in `VoiceOverlayScreen.onDisappear`, one background event, plus a POSITIVE CONTROL proving the instrument fires at all. | either | **YES/sim**, ~1 min |
>
> **254-D and 254-E are two engines because the ghost's audio differs by
> engine** — realtime speaks through WebRTC's ADM on a forced loudspeaker,
> native through `SpeechOutputService` whose native-pipeline instance has
> `managesAudioSession == false`. A pass on one says nothing about the other
> (#220's rule, applied prospectively).

> **✅ 254-F: MET, 2026-08-09 — and it CONFIRMS the mechanism rather than
> retiring the lane. `onDisappear` does NOT fire when the app backgrounds a
> presented `fullScreenCover`.**
>
> **Configuration, named:** simulator `CC-272-iPhone-Air`
> (`530ACE23-CBC3-4BFD-9CCC-ECB1496D0357`), **iOS 27.0**, Xcode-beta4, Debug,
> unpaired. **Engine pin — quoted from the log, per #220:**
> `voice session starting on engine native (relayPaired=false)`.
> Simulator, not device: 254-D/E remain owed and are the device bars.
>
> **Two trials, both negative, each with the app proven ALIVE and proven
> BACKGROUNDED:**
>
> | | overlay presented | HOME pressed | background proof (in-app) | `onDisappear` line |
> |---|---|---|---|---|
> | trial 1 | 06:32:43 | 06:32:43 | `app-refresh submit failed…` 06:32:48 | **absent** |
> | trial 2 | 06:33:50 | ~06:33:55 | `app-refresh submit failed…` 06:33:57 | **absent** |
>
> The background proof is not SpringBoard's word for it: `BackgroundRefreshScheduler.schedule()`
> is called **only** from `AppEntry.swift:178` under `newPhase == .background`,
> so that log line IS the app observing its own scene going to background.
> `launchctl list` showed the process alive across both trials, so the absence
> is not a dead process.
>
> **POSITIVE CONTROL — the absence means something.** Foregrounded, then the
> overlay dismissed by its own end-call button:
> ```
> 06:33:07.596  [org.aethyrion.talaria:VoiceOverlay] #254 254-F: VoiceOverlayScreen.onDisappear fired (appState=active)
> ```
> The instrument fires on a genuine dismissal and does not fire on
> backgrounding. Without this control the negative would have been the
> `cmd | grep || echo "absent"` shape — empty output reading as a result.
>
> **Consequence: `abandonSession()` does NOT cover the background race, the
> #118 observer is the only backstop, and its guard is the defect.** The §5
> mechanism stands.

> **🔧 CORRECTION to the mechanism paragraph above, found while building the
> fix — it does not weaken the mechanism, it sharpens it.** The line
> *"`isSessionActive` is false for the entire connect window"* is **too
> strong**, and the same sentence is in `dispatch/OPUS-T27-voice-130-138-254.md`
> §2/§5. What is actually true:
>
> - `TalkStore.startSessionDirectly()` sets `connectionState = .connecting` on
>   the **store** (`TalkStore.swift:74`) but **never assigns `isSessionActive`** —
>   that flag is written in exactly two places, `applySnapshot` and `reset()`.
> - `applySnapshot` computes `isSessionActive = connectionState == .connecting
>   || connectionState == .connected` (`TalkStore.swift:238`), and the engines
>   DO publish a `.connecting` snapshot (`LiveVoiceSessionService.swift:257`,
>   `NativeVoicePipelineService.swift:218`, each with
>   `didSet { publishSnapshot() }`), which `VoiceEngineRouter.forward`
>   (`:306-317`) relays to the store.
>
> **So the flag flips true PART-WAY through the connect, not at the end.** The
> uncovered window is everything BEFORE the active engine publishes
> `.connecting` — the brain gate, the pairing check, the #82 mic preflight
> (which can sit on a permission dialog indefinitely) — **plus a second window
> nobody had named: the realtime→native fallback.** A realtime start that lands
> `.failed`/`.idle` publishes a NOT-active state, and `shouldFallBackToNative`
> then opens a LOCAL microphone from that state (`VoiceEngineRouter.swift:~250`
> onward) — with `isSessionActive` false for the whole fallback start. #139's
> own comment already names that door ("a user who dismissed during
> ESTABLISHING LINK got a LOCAL microphone opened by the very belt added to
> bound the hang"); this entry now names it for the BACKGROUND door too.
>
> **Net effect on the lane: none of the fix changes** — the rule still needs the
> third input, and `isStartingSession` spans both windows because it is set
> before the first `await` and cleared only when the start resolves. But a
> future reader should not carry away "the flag is false for the whole
> connect": it is false at the START and it is false again during the FALLBACK,
> which is a different and more interesting claim.

> **✅ 254-A / 254-B / 254-C: MET, 2026-08-09. Fix landed. `GATE: PASS`.**
>
> **RED first, and the RED is verbatim.** The rule's SIGNATURE was extended
> while its BODY was left unchanged, so these are assertion failures rather
> than compile errors — a compile error proves a signature changed, not that a
> behaviour was wrong:
> ```
> TalkSessionRulesTests.swift:66:9: Expectation failed:
>   TalkBackgroundRule.shouldEndSession(isSessionActive: false, isStartingSession: true, routeHasCarAudio: false)
> TalkStoreBackgroundRevokeTests.swift:168:9: Expectation failed: revoked
> TalkStoreBackgroundRevokeTests.swift:169:9: Expectation failed: service.endCallCount >= 1
> TalkStoreBackgroundRevokeTests.swift:175:9: Expectation failed: !store.isSessionActive
> ✘ Test run with 20 tests in 2 suites failed after 0.787 seconds with 4 issues.
> ```
> **The last line is the ghost itself** — the connect that landed after the
> non-revoke flipped the store live, in a unit test. After the one-line body
> change: `✔ Test run with 20 tests in 2 suites passed after 0.179 seconds.`
>
> **The fix, in three parts.** `TalkStore` publishes `isStartingSession`
> (`private(set)`), set before the first `await` in BOTH start doors and
> cleared by `defer` on every exit plus on any explicit `endSession()`;
> `TalkBackgroundRule.shouldEndSession` gains it as a third input,
> `(isSessionActive || isStartingSession) && !routeHasCarAudio`; the background
> observer revokes via the unguarded `abandonSession()` and its notice names
> which arm fired — `#118/#254: app backgrounded with a voice session (LIVE|STARTING) — revoking it`.
>
> **`isSessionActive` was NOT deleted from the rule, deliberately.** Revoking on
> every backgrounding would call `endSession()` with nothing live, reaching
> `setActive(false, .notifyOthersOnDeactivation)` unconditionally — the #84
> shape, where a stray deactivation on the shared session killed the live mic.
> **254-C is that negative case, and it is honestly labelled in the test file as
> a regression guard that is green before AND after** — not as evidence the fix
> works. CarPlay (#19) exempts both arms.
>
> **Unit count MOVED: 1859 → 1867 (+8).** Measured as `@Test` declarations in
> `TalariaTests` at `bfbd154` vs HEAD, and the 1867 cross-validates against the
> gate's own reported Swift Testing count. **A caution for the next lane: the
> 272d gate (a DIFFERENT branch, `6420cb7`) also reported 1867, so "same number
> as last time" is not by itself the stale-`.xctest` symptom** — resolve the
> baseline from THIS lane's base commit, not from the last gate log you happen
> to have. Independent proof the binary was not stale: all eight new tests
> appear by name as `✔ passed` in the gate log, and `TalkStoreBackgroundRevokeTests`
> is among the 143 suites — a stale bundle cannot contain a file that did not
> exist when it was built.
>
> **THREE gate runs, all recorded — two FAILs before the PASS, neither caused by
> this branch:**
>
> | run | verdict | cause |
> |---|---|---|
> | 1 (`/tmp/gate-254`) | **FAIL** | `Simulator device failed to launch org.aethyrion.talaria27` — the unit-test HOST would not launch. **Self-inflicted:** 254-F's evidence run hand-installed a `CODE_SIGNING_ALLOWED=NO` build on that same sim and it crashed mid-session. Cleared by `simctl uninstall` + sim reboot + re-granting the calendar/reminders TCC the reboot dropped. **Lesson for any lane that runs a device/sim probe before its gate: uninstall the probe build first.** |
> | 2 (`/tmp/gate-254-run2`) | **FAIL** | one test: `HTMLArtifactSandboxTests.controlArmWithoutRulesLeaksToTheListener()` — `Expectation failed: landed` after 5.754 s. Isolated on this same branch immediately afterwards: **PASSED in 1.878 s**, whole suite 6/6 green. A local-network beacon race, and this branch touches no WebKit, no networking, no listener. |
> | 3 (`/tmp/gate-254-run3`) | **`GATE: PASS`** | Swift Testing 1867 · XCUITest 12 · Release build PASS · 2 expected skips (CondenserFidelityTests, #93). |
>
> **A finding about the GATE itself, worth more than the flake:** on run 2 the
> gate labelled that failure *"NO assertion text — likely an XCUITest harness
> flake (runner lost/restarted). Re-run ONCE and RECORD both runs in OPEN_ITEMS
> #164."* **Both halves misfire.** The failure DID carry assertion text
> (`Expectation failed: landed`) and it is a **Swift Testing unit test**, not an
> XCUITest; and **#164 is CLOSED** (`OPEN_ITEMS-ARCHIVE.md:4775`, closed
> 2026-08-04) and is about a different test entirely
> (`testDisconnectReturnsToStandaloneChat`). Following the instruction literally
> would have reopened a closed item under the wrong diagnosis. **The flake is
> recorded here instead and needs its own number — Owen's call**, since
> allocating one touches the numbering sequence and the INDEX and is outside
> this lane's scope.

> **↪ RESOLVED 2026-08-10 — this finding got its number (#300) and the fix has
> landed. Two corrections to the reading above, both found by the fix lane:**
>
> **1. The classifier was not merely wrong here — it had NO discriminating
> power at all.** Extracting the pre-fix conditional verbatim and running it
> over both surviving logs returns the identical *"NO assertion text — likely
> an XCUITest harness flake"* verdict for each: `/tmp/gate-254-run2/suite.log`
> (this run's real Swift Testing failure) and `/tmp/gate-279-run2/suite.log`
> (a genuine runner death, same week). The regex `\.swift:[0-9]+: error:`
> recognises only the XCTest diagnostic shape; Swift Testing prints
> `recorded an issue at File.swift:LINE:COL:` with no `error:` token at all, so
> its match count in this very log was **zero**. Every Swift Testing failure in
> the project's history was announced as a UI-test harness flake — this run is
> simply the first time anyone read the advice closely enough to notice.
>
> **2. It was not one dead item number — it was all three.** Alongside #164 the
> same advice printed **#183** and **#93** at the reader, and both of those are
> also in `OPEN_ITEMS-ARCHIVE.md`. The live homes are **#219** (the
> runner-flake family) and **#313** (the CondenserFidelityTests skips). Advice
> text now carries no item number at all; it names a search string, and a
> self-test executes each one against `OPEN_ITEMS.md` so a pointer cannot rot
> unnoticed the way these three did.

> **📱 DEVICE RUN 2026-08-09 — build 2330, corded, airplane mode, Owen
> driving. 254-E is UNRUNNABLE AS WRITTEN. The native `LIVE` arm was verified
> in its place, and that substitution is LABELLED, not folded into the bar.**
>
> **254-E — UNRUNNABLE AS WRITTEN, and the reason is measured, not argued.**
> The bar pins native via airplane mode — but the same airplane mode collapses
> the connect window the STARTING arm requires:
> ```
> 13:20:52.983  OpenHermesVoiceIntent.perform fired in the APP process — routing hermes://voice
> 13:20:53.006  voice session starting on engine native (relayPaired=true)
> ```
> **23 milliseconds.** Owen: *"there is no establishing link, its so fast to
> failover to local that it appears by the time I press talk to hermes, its
> already listening."* There is no interval to background into, so no trial on
> this route can reach `isStartingSession == true && isSessionActive == false`.
> **Per the running list's own standing rule — a check that cannot be performed
> as written is a defect in the DOCUMENT, not a result — 254-E is not scored in
> either direction.**
> - The engine line reads `relayPaired=true`. The bar's own warning held:
>   pairing did not choose the engine, the failed readiness probe did.
> - ~~**This does NOT mean the native STARTING window is unreachable in
>   principle.** … A native pin that keeps the network (the on-device brain,
>   per #221) is the untried candidate route.~~ **🔧 CORRECTED SAME DAY, ~1 h
>   later — I wrote that the network-keeping native pin was UNTRIED and might
>   open the window. It was tried within the hour, accidentally, and it does
>   not.** The 254-D attempt at 13:49 ran with the network **up** (zero
>   `unreachable` / `offline` / `timed out` / `degraded` lines in that archive,
>   in contrast to the airplane runs which are full of them) — and the engine
>   was still `native` with the same collapsed window:
>   `perform 13:49:49.821 → voice session starting 13:49:49.843` = **22 ms**.
>   **So airplane mode was never what closed the window; the native start is
>   simply that fast, network or not.** The realtime→native FALLBACK window
>   (which does need the network) remains a distinct, still-unopened door — but
>   reaching it requires realtime to be *attempted and to fail*, which needs the
>   Hermes brain, not merely a network.
>
> **✅ NATIVE `LIVE` ARM — PASS. Recorded under its own name; this is NOT a
> 254-E pass and must never be cited as one.**
> ```
> 13:32:40.840  scenePhase inactive -> background
> 13:32:41.042  #118/#254: app backgrounded with a voice session (LIVE) — revoking it
> 13:32:42.060  audio deactivated by app — not an interruption (#198)    ×3 pairs, through .722
> 13:32:42.207  #254 254-F: VoiceOverlayScreen.onDisappear fired (appState=background)
> ```
> Revoke **202 ms** after background; audio down ~1 s later. Owen: *"silence,
> mic went dark."* Engine quoted per #220:
> `voice session starting on engine native (relayPaired=true)`.
> **What this establishes:** the native audio path (`SpeechOutputService`, whose
> native-pipeline instance has `managesAudioSession == false`) is genuinely torn
> down by the #118 observer — precisely the half of the two-engine argument a
> 254-D pass could never supply. **What it does NOT establish:** anything at all
> about the STARTING arm on native.
>
> **A false contradiction, headed off before it enters the record.** That
> `onDisappear` line fires at `appState=background`, which reads like a
> refutation of 254-F's simulator finding that it does *not* fire on
> backgrounding. **It is not one.** The revoke handler sets
> `container.router.isVoiceOverlayPresented = false` immediately after
> `abandonSession()`, so this `onDisappear` is downstream of the **revoke**, not
> of the backgrounding — visible in the 1.2 s gap between them. On 254-F's sim
> trials no revoke fired (idle store), so nothing dismissed the cover. The two
> results are consistent, and only because the revoke ran first.
>
> **One earlier trial was VOID and is recorded rather than dropped.** The first
> attempt dismissed the overlay *before* backgrounding, so teardown went through
> `VoiceOverlayScreen.onDisappear (appState=active)` and the background observer
> had nothing left to revoke — **no `#118/#254` line at all, neither arm.** The
> instruction was at fault, not the app; a runner told to "background it" will
> reach for the overlay's own dismiss unless told not to.
>
> **⛔ 254-D — ATTEMPTED 2026-08-09, UNRUNNABLE ON THIS HOST. Not a fail: the
> realtime engine cannot be reached from the Mac Mini profile at all, because
> the host has no OpenAI key.** Owen switched the profile to Mac Mini and the
> brain to Hermes and re-ran. The probe answered:
> ```
> 14:00:19.188  [VoiceEngineRouter] readiness routed voice to the native engine (configured=Optional(false), state=blocked)
> 14:00:22.815  [ChatBackendRouter] activeBrain on-device → hermes initiator=refresh/sticky-default
> ```
> `configured: false` is `talk/readiness` reporting **no OpenAI key host-side**,
> which `shouldRouteNative` correctly treats as "route native." **The app did
> the right thing; the bar simply has no realtime engine to test against on this
> host.** 254-D therefore stays OWED and needs a host where realtime is
> configured — #221's history implies OJAMD was that host, which is the obvious
> next attempt and has NOT been tried.
> - The trial itself hit `(LIVE)` again (revoke at `14:00:24.637`, 179 ms after
>   background) — a **fourth** clean native revoke, now with the Hermes brain
>   selected. Not scored as 254-D.
>
> **A SECOND defect fell out of this attempt and is filed separately as #303:**
> the engine is chosen at `VoiceEngineRouter.init` from a brain value that the
> sticky-default refresh changes 35 ms later, and `startSession`'s re-check
> guards only the `realtime → native` direction. So a cold Control Center launch
> pins **native** even when the brain permits realtime. It is **masked on this
> host** (`configured:false` would have routed native anyway), which is exactly
> why it needs its own number rather than a line in this entry.
>
> **254-D remains OWED** — realtime over a real network has a
> genuine connect window, once a host that HAS realtime is used. **Free capture
> from the same logs, routed out:** the
> voice session start precedes App Lock's cover evaluation by ~650 ms on a cold
> Control Center launch → filed as **#302**.

**Owen (2026-08-05, on OTA build 2024):** *"the ask hermes and talk to
hermes buttons in the control center started working? The chat one takes
me right to the composer and the talk to takes me directly to a voice
session. Interesting! It also stayed alive that method after I closed it
and just started talking to me full volume in the office LOL."*

- **Half 1 (observation, good news):** the #7 `ControlWidget` pair
  (`TalariaWidgets/Controls/HermesControls.swift`) now routes correctly —
  chat → composer, talk → live voice session. First confirmed working
  binding; worth knowing OTA 2024 is where it started.
- **Half 2 (the bug):** closing the voice UI did NOT end the voice
  session — it kept running and speaking at full volume. The session's
  lifetime is evidently not tied to its view's dismissal on the
  intent-launched path. Suspect neighborhood: `StartVoiceSessionIntent`
  sets a flag `DeeplinkRouter` (`Talaria/Core/DeeplinkRouter.swift:48`)
  consumes; whatever tears the session down on the normal in-app path is
  bypassed or never armed when the session starts from the control.
  Needs a diagnosis pass (how "closed" was performed matters — dismiss
  vs app-switch vs swipe-kill); bars pre-register here when a lane opens.

**⬇️ DOWNGRADED TO WATCH 2026-08-05 evening (build 2034): NOT
REPRODUCIBLE.** Owen re-tested both buttons repeatedly: chat → composer
and talk → voice session, consistently, every time; voice audio cut off
correctly BOTH on app swipe-out AND on ending the session. The
full-volume ghost did not recur ("it couldn't reproduce it, but it did
work each time" — plus one workplace embarrassment in the line of
science). Half 1 (buttons bind) is now CONFIRMED WORKING on 2034. Leave
filed; re-open on next sighting with the how-was-it-closed detail.

> **2026-08-18 ballot:** Owen — the OpenAI/realtime key "should be on both
> OJAMD and mac mini now." 254-D's blocker (no realtime-configured host) is
> GONE; the bar is runnable on either host. Queued for a device evening /
> Saturday.

## 220. 🔍 ENGINE-AMBIGUITY AUDIT of past voice verdicts. **#128's mystery SOLVED from source 2026-08-01 (and this entry's own proposed test for it was invalid — see below);** three verdicts still need re-checking.

*(OPEN_ITEMS #220. **Not** a GitHub PR number.)* **FILED 2026-08-01** after #198A
established that nothing logged which voice engine was active.

### The window, and why it is worse than a fixed confound

| date | state |
|---|---|
| **before 2026-07-07** | **one engine existed.** `NativeVoicePipelineService` and `VoiceEngineRouter` both arrive in `0709ba2`. **Every voice verdict before this date is unambiguous.** |
| **2026-07-08 onward** | realtime "deployed + confirmed minting on OJAMD" (#47). A paired device now defaults to `.realtime` via `isRelayPaired() ? .realtime : .native`. |

**But the engine was not FIXED in that window — it VARIED.** `refreshReadiness`
probes realtime and falls back to native whenever the probe fails
(`shouldRouteNative`), and `startSession` falls back again on a failed start. So
the active engine tracked **OJAMD's health, run to run**, and **nothing logged
it.** Proof that native really was sometimes live: #128's crash on 2026-07-17 is
a `CreateRecordingTap` failure inside `NativeVoicePipelineService`, which cannot
happen unless the native engine is capturing.

**A nondeterministic, unlogged confound is worse than a constant one.** A constant
one biases every result the same way and can be corrected after the fact. This one
means two runs of the same test may have measured different engines, and nothing
in the record distinguishes them.

### SAFE — no re-check needed

- **Everything before 2026-07-07.** One engine.
- **#118** (background teardown, device-verified 07-20). The fix lives in
  `AppContainer` and is engine-agnostic — and it was watched firing on the
  realtime path during A1 tonight.
- **#138** (realtime self-barge-in). Names its engine, and is the one item that
  caught this organically: *"Scope broadened 2026-07-20 (Owen): NOT
  realtime-only"* — found by observing the same symptom elsewhere, not by any log.
- **#254** (voice session outlives the foreground) — **added 2026-08-09; it
  POSTDATES this audit** (filed 2026-08-05, four days after #220) and is the
  first voice item that could be engine-named from the start, because the
  `voice session starting on engine …` line (`VoiceEngineRouter.swift:225`)
  already existed when it was filed. Owen's original OTA-2024 report named no
  engine and could not have — **but every bar written for it since does.**
  254-F quotes `engine native (relayPaired=false)`; **254-D (realtime, paired
  + healthy relay) and 254-E (native, airplane mode) are pinned to opposite
  engines by construction and are still OWED.** The FIX is engine-independent
  (`TalkSessionRules` + `TalkStore` + `AppContainer`, no audio code), so the
  unit bars 254-A/B/C carry no engine ambiguity at all — **the ambiguity lives
  entirely in the two device bars, which is why they are two.** This is the
  audit's rule applied PROSPECTIVELY rather than retroactively; #254 is on this
  list because its evidence names its configuration, not because it is
  engine-agnostic.

### THE PAYOFF — ✅ **CONFIRMED 2026-08-01, and the settlement method below was WRONG**

> **RESOLVED the same day it was filed, by source archaeology (see #128).** The
> hypothesis **holds, and is stronger than stated here**: realtime is **WebRTC**
> (`LiveVoiceSessionService.swift:5-6,136-138`) with **zero** matches for
> `installTap`/`AudioNodeTap`/`AVAudioEngine`, against 5 tap sites in
> `NativeVoicePipelineService`. So it is not that the native tap code "never executes"
> — **no tap-install code of any kind is in the process's path** on a paired
> healthy-realtime phone.
>
> **But the settlement method prescribed below does not work, and this correction is
> the more useful half.** It says: re-attempt the repro with the engine pinned to
> native. **That test cannot answer the question**, because PR #127 (2026-07-20)
> removed the mid-session category flip that was the actual trigger — the repro is
> **decoupled from the defect**, so it comes back clean on a pinned native engine
> whether the fix is load-bearing or not.
>
> **That is precisely the failure this very entry names one table down for #130** —
> *"a null result wearing the clothes of evidence."* I wrote that warning and then
> prescribed an instance of it in the section above it, in the same document, on the
> same day. **Pinning the engine was necessary and not sufficient**, and the
> difference was invisible until someone read the trigger's source rather than the
> repro's description. A real test of the invariant has to construct the race
> deliberately — that is §E1, not this.

*(Original text preserved below as filed.)*

#### THE LIKELY PAYOFF — #128's "unreachable repro" probably has its answer

#128 is filed as *"FIXED (2026-07-17); documented repro path unreachable
(2026-07-25)"*, and the standing question (restated by the Hermes audit) is
**"is the fix dead defensive code, or was the repro route never recorded?"**

**There is a third answer, and it fits every fact: the repro was unreachable
because the NATIVE ENGINE WAS NOT IN THE PATH on 07-25.** The crash on 07-17 was
native by construction. By 07-25 a paired device with healthy realtime routes to
`.realtime`, and `NativeVoicePipelineService`'s tap code — where the entire fix
lives (`NativeVoicePipelineService.swift:1081`) — never executes.

**This is now cheap to settle** (device-list §G, no phone): re-attempt the repro
with the engine pinned to native and the new `voice session starting on engine …`
line quoted. If it reproduces pre-fix and not post-fix, the fix is load-bearing
and #128 closes properly instead of on an absence.

### AMBIGUOUS — re-check before trusting

| item | verified | why it is in doubt |
|---|---|---|
| **#82** | device CONFIRMED 07-16 | the fix spans `LiveSpeechService` + `LiveVoiceSessionService` + `NativeVoicePipelineService`. Whichever engine ran that day, **the other engine's half of the fix is unverified.** |
| **#110** | device-verified 07-18 | fix is in `SpeechOutputService`, which has **two** consumers: read-aloud (engine-independent) and native voice sessions. **If it was exercised via read-aloud the verdict is safe; via a voice session it is engine-dependent.** The record does not say which. |
| **#129** | device pass never ran | its stated "known accepted behavior — **native-engine** sessions share the assistant TTS instance" is an explicit native-engine claim **never verified on the native engine.** |
| **#130 / B1** | parked | already parked for exactly this reason. Its gate is in `NativeVoicePipelineService`; a comparison run on realtime would find it does nothing **because it was never in the path** — a null result wearing the clothes of evidence. |
| **#198A / A1** | 2026-08-01 | established realtime. **The local engine has no interruption verification at all.** |

### The rule

**A device verdict about voice must quote the engine line.** As of 2026-08-01
`VoiceEngineRouter` logs the initial selection and names the engine at every
`startSession()`. **A verdict that cannot name its configuration is not a
verdict** — it is a measurement of something, and you do not know what.

## 198B. 🐛 A synchronous `AVAudioSession` call runs on the MAIN THREAD, at `fault` severity

**FILED 2026-08-01**, found in the A1 device log while checking something else.

```
17:55:51.682 [AVAudioSession Hang Risk] AVAudioSession_iOS.mm:978
  This method can lead to UI unresponsiveness if called on the main thread.
  Consider using the asynchronous activate/deactivate API instead.
```

**`fault` is the highest severity iOS emits** — above `error` — and it fired in
the **resumption** path, a fraction of a millisecond before
`audio resumption recommendation: resume`.

`AudioSessionOffMain` exists in this codebase precisely to keep activate/deactivate
off the main actor, so **some call site is bypassing it.** Source work; no device
time needed. Find the synchronous site in the resumption handling and route it
through `AudioSessionOffMain`.

**Why it was invisible until now:** every prior console read filtered
`oslogSeverity: ["default"]` — the documented workaround for `GetConsoleOutput`'s
broken `pattern:` argument. `fault` is not `default`, so **the noise-reduction
filter was also hiding the highest-severity line in the log.** Read `all` at least
once per device session.

> **🔴 2026-08-20 — THE ENTRY POINTS AT THE WRONG PLACE, AND THE SCOPE IS
> TWELVE SITES ACROSS THREE SERVICES. Diagnosed from the tree, not the log;
> NO code changed yet — this needs Owen's routing, because it is not the
> free-bucket one-liner the week plan booked.**
>
> **The resumption handling is CLEAN.** This entry says *"find the synchronous
> site in the resumption handling and route it through `AudioSessionOffMain`."*
> Both resumption paths were read at HEAD and both are already off-main:
> `LiveVoiceSessionService.handleAudioInterruptionEnded` →
> `configureAudioSession()`, which is `AudioSessionOffMain.run { … }` (`:746`);
> and `NativeVoicePipelineService.handleInterruptionEnded` → `restartCapture()`
> → the capture chain's own `start(muted:)`, which lives on **`private actor
> NativeVoiceCaptureController`** (`:912`) and is therefore off the main actor
> already. The notification observers themselves only log and dispatch.
>
> **Where the bypasses actually are** — every one `@MainActor`, none using the
> helper:
>
> | service | sites | what they do |
> |---|---|---|
> | `SpeechOutputService` | `:248 :249 :264` | assistant TTS playback session |
> | `VoiceMemoPlayer` | `:52 :53 :58 :74` | memo playback |
> | `VoiceMemoRecorder` | `:63 :64 :69 :78 :129` | memo recording |
>
> `LiveSpeechService` is **also clean** — its calls sit on `actor
> DictationController`, not on the `@MainActor` class that owns it. Two
> classification traps worth writing down, because a naive grep gets both
> wrong: **a `@MainActor` class can contain a nested `actor`** (LiveSpeech,
> NativeVoicePipeline), and **a call inside `AudioSessionOffMain.run { … }` is
> off-main even though the enclosing class is `@MainActor`** (four
> `LiveVoiceSessionService` sites read as bypasses until the closure is
> noticed). Classify by the ENCLOSING EXECUTION CONTEXT, not the file's type.
>
> **⚠️ AND THE FIX IS NOT MECHANICAL, which is why this stops here.**
> `AudioSessionOffMain` is `async`, and the enclosing functions mostly are NOT
> — `configurePlaybackAudioSession()`, `releaseAudioSessionIfIdle()`,
> `togglePlayback(path:)`, `stop()`, `stopRecording()`, `discard()`,
> `finishRecorder()` are all synchronous. That splits the work:
>
> - **DEACTIVATIONS (~6 sites) are safe to move** — nothing downstream awaits
>   them, so `Task { try? await AudioSessionOffMain.setActive(false, …) }` is
>   the shape already used at `LiveVoiceSessionService:353` and
>   `NativeVoicePipelineService:399`.
> - **ACTIVATIONS are NOT.** The session must be active BEFORE
>   `recorder.record()` / playback starts, so a fire-and-forget `Task` would
>   RACE the thing it is meant to prepare. Those need their callers to become
>   `async`, which ripples into SwiftUI views and delegate callbacks.
>
> **✅ ROUTED 2026-08-20 (Owen): SUNDAY 08-23, AS A FABLE LANE.** His words:
> *"that seems like an intense refactor."* Which it is — twelve sites, and the
> activation half cannot move without making synchronous callers `async`, so
> it ripples into SwiftUI views and delegate callbacks. That is escalation-tier
> work, not free-bucket work, and booking it as one lane avoids shipping the
> safe half alone and leaving the entry half-corrected.
>
> **Why Sunday specifically works for this item:** Saturday is the device day
> and already carries #220/#198A's engine-pinned voice re-checks. A Sunday
> build lands with the device evidence fresh, and the paths this touches (TTS
> output, memo record/playback) are exactly the ones a sim cannot verify. The
> lane should read the two classification traps below BEFORE grepping —
> both produce false bypasses.
>
> **REMOVED from Thursday's free bucket** in the same decision; the week plan
> is corrected to match.

> **Recommendation carried into that lane: do not ship a partial audio change
> without device time.**
> These paths are already the fragile ones (#82's wedge, #128's double-install
> crash, #138's barge-in), the sim cannot exercise real route changes, and
> Saturday already carries #220/#198A voice re-checks that would cover a
> change like this. Options for Owen: **(a)** deactivation half now, activation
> half filed as its own item; **(b)** whole thing as one lane, built before
> Saturday so the device day verifies it; **(c)** leave it — the fault is a
> hang-RISK warning, and no hang has been reported.


> **🔴 2026-08-23 — LANE OPENED, WORKED, AND DELIBERATELY STOPPED BEFORE ANY
> CODE. The 08-20 table above is RIGHT about where the sites are and WRONG
> about what to do with them: this entry's own prescribed fix for the
> deactivation half would ship a RACE. Four hazard classes below; nothing
> changed; bars pre-registered. Stopped under Owen's standing ruling for the
> 08-23 night list — _if a lane turns out bigger or riskier than it looks,
> stop, file what was learned, move to the next_ — which this is the first
> lane to actually exercise.**
>
> **① THE PRESCRIBED `Task { … }` DEACTIVATION SHAPE IS UNSAFE HERE.** The
> block above rules ~6 deactivations "safe to move" because *"nothing
> downstream awaits them."* That is true and **insufficient** — the hazard is
> not a downstream await, it is **a subsequent activation on the same tick.**
> `VoiceMemoPlayer.togglePlayback(path:)` calls `stop()` — which deactivates
> — and then, **in the same synchronous body**, `setCategory` +
> `setActive(true)` (`:47` then `:52-53`). Defer that deactivation into a
> `Task` and it lands *after* the activation it was meant to precede. Worse
> than "later": `AudioSessionOffMain` runs its body on a **detached** task, so
> the teardown and the setup are genuinely **unordered** against each other —
> a data race on one shared global session, not merely a reordering. The same
> shape sits at lower acuity in `finishRecorder()` (`:129`), where a re-record
> is user-speed rather than same-tick. **The fix for the deactivation half is
> therefore NOT the cheap half; it needs the same ordering guarantee the
> activation half does.**
>
> **② MAKING THE CALLERS `async` MAKES PREVIOUSLY-ATOMIC UI ACTIONS
> RE-ENTRANT — #128's class.** `togglePlayback` today is one main-actor
> run-to-completion: a double-tap **cannot** interleave. Introduce an `await`
> inside it and two taps can, so the sequence becomes stop→start→stop→start
> interleaved across two invocations. #128 is exactly this failure — *two
> interleaved capture starts double-installed a tap and crashed a device*
> (`CreateRecordingTap: nullptr == Tap()`). Any async version needs an
> explicit transition guard; the 08-20 estimate budgets for the signature
> ripple and **not** for the guard, and `VoiceMemoRecorder`'s existing
> `guard !isRecording` does not cover it (`isRecording` is set at `:82`,
> after the whole do/catch, and the function already suspends at `:51`).
>
> **③ THREE OF THE TWELVE SITES ARE DELIBERATELY SYNCHRONOUS, AND THE CODE
> SAYS SO.** `SpeechOutputService:236` carries a comment naming *this very
> rider* and refusing it: activation must complete before
> `synthesizer.speak` on the same tick; the release is interlocked with the
> #106 `didActivateAudioSession` gate, so hopping **either** off-main could
> reorder activate/deactivate across a `stop()` → `speak()` boundary; and
> voice sessions never reach these calls anyway (`managesAudioSession ==
> false` on the pipeline's instance, and the shared instance is gated off
> while Talk is active). **So a FOURTH classification trap joins the two
> above: a site can be synchronous ON PURPOSE.** The 08-20 pass classified by
> *is it off-main?* and structurally could not see a recorded decision. These
> three sites are **not** in scope for a mechanical rider; moving them is a
> re-litigation of #84/#106 and needs its own justification.
>
> **④ TWO SCOPE CORRECTIONS, both making the lane SMALLER than stated.**
> `VoiceMemoRecorder.startRecording()` is **already `async`** — it is absent
> from the 08-20 list of synchronous enclosing functions, correctly, but the
> consequence was never drawn: its two activation sites (`:63 :64`) carry
> **zero caller ripple**. And the feared ripple *"into SwiftUI views and
> delegate callbacks"* is four `Button` actions
> (`MessageBubble:782`, `ChatInputBar:502`, `VoiceMemoRecorderSheet:216` and
> `:305`), where `Task { await … }` is idiomatic, plus one delegate callback
> that **already** wraps itself in `Task { @MainActor in }`
> (`VoiceMemoPlayer:82`). The signatures are the easy part. **The guard and
> the ordering are the lane.**
>
> **WHAT THIS LEAVES — the corrected scope, by what each site actually
> needs:**
>
> | sites | where | needs |
> |---|---|---|
> | `:248 :249 :264` | `SpeechOutputService` | **nothing — deliberate, documented** |
> | `:63 :64 :69 :78` | `VoiceMemoRecorder.startRecording()` | already `async`; ordered `await`, no ripple |
> | `:52 :53` | `VoiceMemoPlayer.togglePlayback` | `async` + **re-entrancy guard** |
> | `:58 :74 :129` | player `stop()`, recorder `finishRecorder()` | **ordering guarantee, NOT fire-and-forget** |
>
> **RECOMMENDED DESIGN when this is built:** make the player's and recorder's
> transitions `async` and **await every one of them**, so ordering is
> preserved by construction rather than by argument — never `Task { }` a
> deactivation on a path that can reactivate. Add one `isTransitioning`
> guard per service to restore the atomicity the `await` removes. Leave
> `SpeechOutputService` alone and extend its comment to record that this lane
> considered and declined it.
>
> **BARS — pre-registered 2026-08-23, before any code (#215):**
> - **198B-A (the point of the item).** A device session that records a memo,
>   plays it, and stops it emits **ZERO** `AVAudioSession_iOS.mm:978` lines,
>   read at `oslogSeverity: all`. *Any* such line falsifies. Read `all` —
>   `default` is what hid this for weeks.
> - **198B-B (ordering, unit-testable).** A test drives
>   stop-then-start on one action and asserts the session's observed call
>   order is `deactivate` **then** `activate`. Must be written against a seam
>   that records order, and must be shown RED against the fire-and-forget
>   shape hazard ① describes — a bar that never saw the bug it forbids is not
>   a bar.
> - **198B-C (re-entrancy, unit-testable).** Two toggles issued without
>   awaiting between them produce **exactly one** activation. Shown RED
>   against an unguarded async version.
> - **198B-D (#84 non-regression).** Read-aloud `stop()` during a native voice
>   session still performs **no** deactivation — `shouldReleaseAudioSession`
>   stays the gate and stays covered.
>
> **NOT a reason to build it blind:** the fault is a hang-RISK warning and no
> hang has ever been reported (option (c) above). Against that, these are the
> paths with #82's wedge, #128's device crash, #84's killed mic and #138's
> barge-in, and **a simulator cannot exercise a real route change** — so the
> verification this needs is device time, which is the one thing the lane
> cannot self-serve.
>
> **SPAWNED: #399** — the memo PLAY buttons lack the Talk gate that every
> sibling surface carries. Found while reading these files; graded honestly
> there (it is a defence-in-depth gap, not a demonstrated live bug) and filed
> separately per #268 rather than buried in this entry.

> **⚖️ ROUTED 2026-08-23 (Owen, decision pass): BUILD AT THE NEXT PRE-DEVICE
> WINDOW.** The recommended design above stands (awaited transitions +
> `isTransitioning` guards; `SpeechOutputService` untouched); the lane opens
> when a device sitting is hours away rather than days, so 198B-A closes in
> the same breath the change lands — the entry's own rule that a partial
> audio change never ships without device time. Options (a) build-now and
> (c) leave-it are declined.

> **🔓 UN-PARKED 2026-08-25 (Owen's stacking ruling, in-chat: "Don't hold
> anything for my testing, it should stack"):** the 08-24 deferral that
> held this lane behind the runbook's voice sitting (attribution
> protection) is VOID — work stacks, the runbook adapts. The pre-device
> condition is also met (evening device time is hours away). LANE OPENS
> NOW; 198B-A rides the next staged build's runbook card, annotated with
> the build boundary per the ruling.

> **✅ BUILT + GATED 2026-08-25, the un-park's same day — 198B-B/C/D MET;
> 198B-A rides the next staged build's runbook card (the device half, as
> ruled).** GATE: PASS **2547** Swift Testing (+4 exact: the
> `VoiceMemoTransitionTests` suite) + 14 XCUITest + Release.
> - **The ruled design, built as recommended:** every memo-service session
>   transition rides `AudioSessionOffMain` and is AWAITED at its call site
>   — never `Task { }`'d on a path that can reactivate — so one toggle's
>   stop-then-start is deactivate THEN activate by construction (hazard ①
>   answered). `isTransitioning` guards on `togglePlayback` and
>   `startRecording` restore the tap atomicity the awaits removed (hazard
>   ②/#128); `stop()`/`discard()` are unguarded ON PURPOSE — a dismissal
>   must never be dropped — with idempotent effects (#399's flag).
> - **One design ADDITION beyond the recommendation, forced by hazard ②'s
>   own logic:** `discard()` landing inside `startRecording()`'s await
>   window is real (cancel mid-prompt/mid-activation), and drop-semantics
>   there would leak a live recorder. Closed with the #397 GENERATION
>   pattern: `finishRecorder()` bumps the generation; the start re-checks
>   after every suspension and backs out, releasing exactly what it
>   activated. Tested with a parked activation seam
>   (`discardDuringAStartTransitionEndsTheStartCleanly` — events exactly
>   `[activate, deactivate]`).
> - **Two new seams with structural pins (the #399 shape):**
>   `activateForPlayback`/`activateForRecording` (`setActive(true` spelled
>   exactly once per file, in the seam default — the pin caught its own
>   first red: two COMMENT spellings, reworded) and
>   `requestRecordPermission` (the TCC ladder seamed so unit tests cannot
>   hang on a mic prompt — the gate's founding hang class; the real ladder
>   is the default, `AVAudioApplication.requestRecordPermission` spelled
>   once).
> - **Bars falsified as they prescribe:** 198B-B shown RED against the
>   exact fire-and-forget shape it forbids (only the ordering test red);
>   198B-C shown RED against the unguarded version (2 activations, only
>   the re-entrancy test red). The five #399 pins survive re-signatured
>   (async drives, assertions unchanged). 198B-D: `SpeechOutputService`
>   UNTOUCHED (its comment now records this lane's considered-and-declined
>   pass — hazard ③); its suite green in the gate.
> - Callers: four Button sites + the sheet's dismissal/finish/discard
>   flows wrap in Tasks; the delegate completion awaits `stop()`.
> - **198B-A (device):** a memo record→play→stop session emits ZERO
>   `AVAudioSession_iOS.mm:978` lines at `oslogSeverity: all` — carded in
>   the runbook against the next staged build.
> **MERGED 2026-08-25 — PR #371, squash `02c45440`; lane branch deleted
> both sides. Build 3022 staged from this merge; the runbook's 198B-A card
> targets it. Only 198B-A (device) remains on this item.**


> **🔴 2026-08-31 — 198B-A's BAR IS AN ABSENCE BAR ON A STRING WE DO NOT
> CONTROL, and it fails silently GREEN.** The card greps for
> `AVAudioSession_iOS.mm:978`. That string has **zero emitters in our source**
> — it is an Apple-internal diagnostic keyed to a LINE NUMBER inside Apple's
> own file, and the device has since moved to `24A5424a`. The bar is "zero
> such lines appear", so **if Apple renumbered that line, the grep returns
> nothing and the card reads PASS while measuring nothing at all.** This is
> the #416 family (a green signal covering what it cannot see) and the
> "marker its component cannot emit" scar, combined into one step.
> **Correction, not yet run:** grep the FILE (`AVAudioSession_iOS.mm`) without
> the `:978`, at `fault` severity, and RECORD every line number seen — so the
> bar measures the absence of the fault rather than the absence of one
> spelling of it. Found by the runbook staleness audit; the fix that #198B
> shipped is untouched by this — only its verification is.

> **📋 2026-09-01 (night) — 198B-BAR LANE OPENED (Owen's mandate).** The board pass confirmed the 08-31 audit finding: 198B-A as written greps `AVAudioSession_iOS.mm:978` — an Apple-internal string keyed to a LINE NUMBER, zero emitters in our source, on a device OS build that has since moved — so the card would print PASS while testing nothing. Bars pre-registered before any edit:
> - **198B-B-A (the bar is re-cut to something that can fail):** the device card (in `dispatch/DEVICE-PASS-RUNNING-LIST.md` ~:2503-2511 and the runbook) keys on the bare filename `AVAudioSession_iOS.mm` at `fault` severity within the session window — PASS = zero such lines across the memo play/record/discard transitions, FAIL = any — and the old line-numbered string is struck with a dated note, not deleted. [offline]
> - **198B-B-B (a positive control so an empty log cannot pass):** the card names one line the app's OWN off-main path emits during those transitions (from `AudioSessionOffMain` / the memo services — the lane reads the code and names the exact marker) and requires it to be PRESENT; absence = the run did not exercise the path, verdict INVALID rather than PASS. [offline]
> - **198B-B-C:** the runbook card is rewritten to the same bar; the entry's result block states 198B-A stays OWED on device (unchanged) — this lane fixes the instrument, not the finding. [offline]

> **✅ RESULT 2026-09-01 (night) — 198B-B-A/B/C MET, DOCUMENT-ONLY. 198B-A ITSELF
> STAYS OWED ON DEVICE — this lane fixed the INSTRUMENT, not the finding.**
>
> **Emitter count, re-confirmed:** `grep -rn "AVAudioSession_iOS.mm" --include='*.swift' .`
> returns exactly four hits, all comments/doc-comments naming the historical
> observation — `TalkSessionRules.swift:22`, `VoiceMemoPlayer.swift:60`,
> `VoiceMemoRecorder.swift:62`, `VoiceMemoAttachmentTests.swift:238`. **Zero
> emitters.** The 08-31 audit's finding stands unchanged; this lane did not
> discover anything new here, it re-verified the premise before cutting the fix.
>
> **198B-B-A — the bar is re-cut.** `dispatch/DEVICE-PASS-RUNNING-LIST.md`'s
> §A1b/A2 fault-log row now carries a runnable PASS/FAIL/INVALID card keyed on
> the bare filename `AVAudioSession_iOS.mm` at `messageType == fault`, across
> the full record→play→stop→discard window, with every line number seen
> recorded (so a renumber is visible, not silently absorbed). The old
> line-numbered spelling is struck (`~~…:978~~`) with a dated note, not
> deleted; the raw original finding is kept below it for the record, labeled
> as evidence rather than as the bar.
>
> **198B-B-B — the positive control.** No single existing line covers all
> three transitions cleanly, so the honest answer is a partial one, stated on
> the card: `Self.logger.verbose("Voice memo recording started")` —
> `Talaria/Services/Live/VoiceMemoRecorder.swift:148` (sibling:
> `"Voice memo recording stopped (<N>s)"` at `:170`) — is the marker used,
> required PRESENT or the verdict is INVALID rather than PASS. It carries two
> preconditions now written into the card's Setup: **Developer → Verbose
> Logging must be ON** (`Logger.verbose(_:)` no-ops silently when the flag is
> off — off by default — `TalariaLog.swift:44-48,66-70`), and the read must be
> a **corded live session** — the line is `.debug`-level, which
> `TalariaLog.swift`'s own doc comment (`:76-79`) says `log collect` does not
> persist, so the hand-launched + archive route cannot see it. **The control
> only proves the RECORD leg ran off-main** — `VoiceMemoPlayer` logs nothing
> on a successful play/stop (its only `Logger` calls are the two `.error()`
> failure paths, `:112` and `:119`), and `discard()`/`finishRecorder()` are
> silent on success. Proposed (NOT built this lane — source work, needs its
> own go): one always-on `.notice` inside `AudioSessionOffMain.run`/
> `setActive` (`Talaria/Services/Support/TalkSessionRules.swift:150-171`, the
> single choke point all three transitions already funnel through) —
> `TalariaLog.logger.notice("AudioSessionOffMain: setActive(\(active)) off-main (#198B)")`
> — un-gated and `.notice`-level, so it would survive `log collect` and cover
> record/play/discard from one site instead of three.
>
> **198B-B-C — the runbook card, full text (for the orchestrator to
> republish; the HTML source is not in this repo).**
>
> > **Precondition:** build ≥ #198B's fix (PR #371, `02c45440`, build 3022+).
> > Developer → Verbose Logging: ON. Corded session, read at
> > `oslogSeverity: ["all"]` (never `["default"]`).
> >
> > **Steps:** record a short voice memo → stop → play it back → stop
> > playback → discard. One continuous session.
> >
> > **Claude scores two predicates:** (1) zero lines matching
> > `eventMessage CONTAINS "AVAudioSession_iOS.mm"` at `messageType == fault`
> > across the window — record every line number seen regardless of severity;
> > (2) `subsystem BEGINSWITH "org.aethyrion.talaria"` AND
> > `eventMessage CONTAINS "Voice memo recording started"` present at least
> > once (positive control — confirms the record leg's off-main path actually
> > ran and Verbose Logging was on).
> >
> > **PASS** = predicate (1) zero AND predicate (2) present.
> > **FAIL** = any fault-severity `AVAudioSession_iOS.mm` line, regardless of
> > (2) — reopens #198B.
> > **INVALID (not PASS)** = predicate (2) absent — Verbose Logging was off or
> > the record leg didn't run; redo the pass.
>
> **Gate:** document-only change (dispatch doc + this tracker file); per
> Owen's merge-on-green ruling for docs-only lanes, no app gate is owed.
> `python3 scripts/oi-invariants.py` run unpiped, exit 0 (see this file's own
> commit history for the run).
>
> **198B-A remains OWED on device** — unchanged by this lane. The next corded
> sitting runs the re-cut card above against build 3022+ with Verbose Logging
> ON, and that verdict — not this one — closes #198B.

> **📋 2026-09-01 night — 198B-MARKER LANE OPENED (the positive control the re-cut bar still lacks).** The 198B-BAR lane (PR #408) found the only app-emitted line on the memo path is a verbose-gated `.debug` on the RECORD leg alone, so the bar's INVALID arm cannot see play/discard. Bars pre-registered before code:
> - **198B-M-A:** `AudioSessionOffMain`'s single choke point (`TalkSessionRules.swift` ~:150-171, the `run`/`setActive` path all three memo transitions funnel through) emits ONE always-on `.notice` naming the transition — `AudioSessionOffMain: setActive(<bool>) off-main (#198B)` or equivalent — pinned by a pure formatter test in the `VoiceInstrumentLogLineTests` pattern. RED-first; mutation (drop the field) re-reddens. [offline]
> - **198B-M-B:** the device card's positive control is re-pointed at that line (present ⇒ the path ran; absent ⇒ INVALID); the `.debug` record-leg line is demoted to optional. [offline]
> - **198B-M-GATE:** lane-gate PASS. 198B-A itself stays OWED on device. [Mac]

> **✅ RESULT 2026-09-02 (the 2026-09-01 night lane, run into the small hours)
> — 198B-M-A/B/GATE ALL MET. 198B-A ITSELF STILL STANDS OWED ON DEVICE: this
> lane, like the 198B-BAR lane before it, fixed the INSTRUMENT and not the
> finding.**
>
> **198B-M-A — the marker, verbatim:**
>
> ```
> AudioSessionOffMain: setActive(true) off-main (#198B) reason=memo-record-start
> ```
>
> Formatter `AudioSessionOffMain.setActiveLogDetail(active:reason:)` —
> `nonisolated static`, pure, no I/O — at
> `Talaria/Services/Support/TalkSessionRules.swift:174-176`, in the #418/#419
> shape (`VoiceInstrumentLogLineTests`). Emitted at
> **`TalkSessionRules.swift:208`**, inside `AudioSessionOffMain.run`, at
> `.notice`, `privacy: .public`, **un-gated by Verbose Logging** — the whole
> point, since `Logger.verbose(_:)` writes at `.debug` and `log collect` does
> not persist that (`TalariaLog.swift:76-79`).
>
> **The choke point is TWO entry points, not one, and the 09-01 bar text did
> not know that.** The bar says *"the `run`/`setActive` path all three memo
> transitions funnel through"* — true, but they arrive by different doors:
> the DEACTIVATIONS call `AudioSessionOffMain.setActive(false, …)` while the
> ACTIVATIONS ride `AudioSessionOffMain.run { setCategory; setActive(true) }`,
> because #198B seamed category+activation into one ordered hop. `run`'s
> closure is **opaque** — the direction cannot be read out of it — so `run`
> gained an `activating: Bool?` parameter by which a compound caller declares
> the transition it performs, and `setActive` now delegates through it. One
> emitter, one formatter, both doors. `activating: nil` (the default) emits
> nothing, which is what the route-read hop at
> `LiveVoiceSessionService.swift:699` wants.
>
> **Emitted on ENTRY, not on success — a deliberate choice.** A control that
> vanished when the transition threw would score the single most interesting
> run INVALID instead of surfacing it, and the claim the line makes ("this
> ran off-main") is true of the attempt. Recorded here because it is exactly
> the kind of decision a later reader would otherwise assume was an oversight.
>
> **Call sites, all reasons explicit** (`reason:` has no default on
> `setActive`, so a new call site cannot be silently unnamed):
>
> | reason | site |
> |---|---|
> | `memo-record-start` | `VoiceMemoRecorder.swift:73` |
> | `memo-record-stop` | `VoiceMemoRecorder.swift:64` |
> | `memo-playback-start` | `VoiceMemoPlayer.swift:75` |
> | `memo-playback-stop` | `VoiceMemoPlayer.swift:62` |
> | `realtime-session-start` | `LiveVoiceSessionService.swift:784` |
> | `realtime-session-end` | `LiveVoiceSessionService.swift:398` |
> | `realtime-carplay-reassert` | `LiveVoiceSessionService.swift:734` |
> | `native-pipeline-stop` | `NativeVoicePipelineService.swift:399` |
>
> The four memo reasons are what the device card scores; the other four are
> free coverage the same choke point buys, and the card says to ignore them.
>
> **RED-first, and the RED is recorded rather than asserted.** Six pins were
> written against a stub formatter returning `"AudioSessionOffMain: off-main"`
> and the suite reported **`Test run with 14 tests in 1 suite failed after
> 0.018 seconds with 13 issues`** — every new expectation named, e.g.
> `Expectation failed: line.contains("setActive(true)")`. Real formatter ⇒
> **`Test run with 14 tests in 1 suite passed`**; the suite's count MOVED 8 → 14
> (three pins here, three for #396-Q).
>
> **MUTATION (the bar's own: drop the `active` field).**
> `"AudioSessionOffMain: setActive off-main (#198B) reason=\(reason)"` ⇒
> **2 issues, both 198B-M's** — `line.contains("setActive(true)")` at
> `:146` and `off.contains("setActive(false)")` at `:161`. The three #396-Q
> pins stayed GREEN, so the mutation ISOLATES. Restored.
>
> **198B-M-B — the device card is re-pointed** (`dispatch/DEVICE-PASS-RUNNING-LIST.md`,
> the §A1b/A2 `198B-A` card the 198B-BAR lane re-cut). Predicate 2 is now
> `eventMessage CONTAINS "AudioSessionOffMain: setActive("`, with a table of
> the four memo `reason=` values and an instruction to **record which appeared**
> — all four ⇒ every leg ran off-main; some ⇒ the fault-absence result covers
> only those legs, and the verdict says so instead of generalising. The old
> `"Voice memo recording started"` `.debug` line is **demoted to optional**
> ("its absence is **not** an INVALID"), Verbose Logging drops from *required*
> to *optional*, and the card now accepts the **hand-launched
> `log collect`** route as well as the corded one, which the `.debug` control
> could never support. The Setup build floor moved to the 198B-M build with a
> dated note: a build between 3022 and this one carries the FIX but not the
> CONTROL and can therefore only ever score INVALID.
>
> **🔴 THE GATE CAUGHT A REAL REGRESSION ON THE FIRST RUN, and it is worth
> writing down because it is #399's pin working exactly as designed.**
> Adding a `reason:` argument, this lane reformatted the two memo
> deactivation calls across four lines — which **split the literal
> `VoiceMemoAttachmentTests.deactivationIsSpelledOnlyInsideTheInjectableSeam`
> greps for**, so its per-file count went 1 → 0 and the gate came back
> `GATE: FAIL (4 checks)` / *"Test run with 2838 tests in 244 suites failed
> … with 2 issues"* — `Expectation failed: direct == 1`, once per memo
> service. Nothing about the behaviour changed; a purely cosmetic reformat
> was enough. **Both deactivation calls are now single-line with a comment
> saying why.** And the first repair reintroduced the same fault from the
> other side: the explanatory comment QUOTED the literal, taking the count
> 1 → 2, because the pin reads the whole file and cannot tell code from
> prose. That is the identical trap #198B's own 2026-08-25 block recorded
> ("two COMMENT spellings, reworded") — met again, by the lane that had
> just read the note. **A source-reading pin constrains the formatting and
> the comments of the file it guards, and that constraint is invisible at
> the call site until it fires.**
>
> **198B-M-GATE:** see the shared gate line in #396's result block below —
> one gate covers both lanes (they shipped in one PR).
>
> **What this does NOT do.** It does not close #198B. The fault-absence bar
> still needs a corded or collected device session; all this lane changed is
> that an empty log can no longer pass it, and that play and discard are now
> visible to the check at all.
>
> **MERGED 2026-09-02 — PR #416, squash `9dca3bad`** (one PR with 396-Q;
> lane branch left in place per the merge instruction).

## 198A. ⚠️ THE REAL-INTERRUPTION TEST: no false negative, but only ONE engine was verified and we cannot say which

**Two real phone calls, corded whoGoesThere, PID 14087, 2026-08-01.**

> **CORRECTED within the hour.** This entry first read *"PASSED … both engines"*.
> **Owen asked whether the session was truly the local engine or the OpenAI
> realtime path, and the question broke the claim.** Both services register their
> observers in `init()` — `LiveVoiceSessionService.swift:154`,
> `NativeVoicePipelineService.swift:132` — so **both observers fire on every
> notification regardless of which engine is capturing.** Two log lines proved two
> OBSERVERS classified correctly. They never proved two ENGINES ran.
>
> **The instrument gap is the real finding: nothing logs which voice engine is
> active.** `VoiceEngineRouter` decides and says nothing. The low-level trace does
> not disambiguate either — `aurioc AURemoteIO … enable 3` failing across the
> interruption window proves a real full-duplex capture chain existed and was torn
> away, but **both** paths capture locally; realtime only streams the result on.
>
> **We spent the scarcest resource we have — a second person making real calls —
> and the record cannot say which configuration it exercised.** Same disease as
> everything else this week: the instrument did not record the thing that mattered.
>
> ### ANSWERED, same evening: it was the REALTIME engine. The local one is unverified.
>
> `VoiceEngineRouter` assigns its default **in `init`**
> (`activeEngine = isRelayPaired() ? .realtime : .native`) **without logging**,
> and `setActive` logs only on a **change** (`guard activeEngine != engine`).
> All three of its log calls are `.notice` → `default` severity, and the
> `default`-severity read for this session returned `totalCount: 42` — **all of
> which were inspected, with no `VoiceEngineRouter` line among them.** No engine
> change, no `readiness routed voice to the native engine`, no
> `Realtime start failed`.
>
> The device was paired (`relay accepted push registration`,
> `handleAppDidBecomeActive: paired + token OK`), so `isRelayPaired()` was true
> and the engine stayed at its init value: **`.realtime`.**
>
> **So A1 exercised the OpenAI realtime path through Hermes. The local/native
> engine has NO interruption verification at all.** Owen suspected exactly this
> — *"I'd almost want to investigate whether or not this was TRULY local device"*
> — and he was right for a reason the log actively concealed: **the one line that
> would have said so is emitted only on a change that never happened.**
>
> **A verdict reconstructed from the ABSENCE of a log line is not a verdict.** It
> is a lucky inference, and it only happened because someone asked the awkward
> question after the fact.
>
> **Fixed the same evening** — `VoiceEngineRouter` now logs the initial selection
> in `init` AND names the engine at every `startSession()`. Re-run is device-list
> §A1b, and it must QUOTE the engine line.

**What IS established, and it is worth having:** the 2026-08-01 pass proved no
false POSITIVES and said explicitly that it could not speak to missed
interruptions. **A real call WAS seen** — classified `source == .system` — in both
runs and both orderings. **The false-negative question is answered for the engine
that ran.** What is NOT established is which engine that was, or that the other
one behaves the same. Both share `AudioInterruptionRule`, so the residual risk is
low; **low risk is not verification**, which is the lesson of this entire week.

| run | action | interruption seen |
|---|---|---|
| 1 | ring → **decline** | ✅ `17:53:30.815`, **567ms BEFORE** #118's teardown |
| 2 | **answer**, speak, hang up | ✅ `17:55:47.418`, **167ms AFTER** #118's teardown |

Both runs logged `audio interrupted — system deactivation` from **both
OBSERVERS** (`NativeVoicePipeline` and `LiveVoiceSessionService` — see the
correction above; that is two observers, not two engines), while the app's own
deactivations in the same traces logged `audio deactivated by app — not an
interruption`. **True positive and true negatives in one trace: the filter
discriminates rather than merely permits.**

**The finding that outranks the pass: the ordering is a RACE and it is not
deterministic.** #118's "app backgrounded with a live voice session — ending it"
and the interruption notification arrive in whichever order they arrive — run 1
the interruption won, run 2 the teardown did. `AudioInterruptionRule` classified
correctly either way. **That order-independence was never designed for; it held,
and it is now measured rather than assumed.** Anything that later reorders this
teardown must re-run A1.

**Corroboration from the negative side:** Owen began speaking again *as the call
arrived* and that speech was **not captured**. A missed interruption would have
left the mic live. The absence is the evidence.

**No call audio reached the transcript.** The turn completing a few seconds after
each interruption is the PRE-call utterance being submitted as the session tears
down — confirmed with Owen, expected.

### The residual this found: `shouldResume` is unreachable for phone calls

`resumptionRecommendationNotification` returned **`resume`** in both runs — at
**+1.5s** (run 1) and **+4.3s** (run 2) after the interruption. In both cases
**#118 had already ended the session.** An incoming call always backgrounds the
app, so #118 always fires, so the resume branch **cannot execute on device for a
phone call**.

**Not a bug — but it is dead code wearing the clothes of a safety net**, which is
the more dangerous kind. Options, none taken yet: reach it via a non-backgrounding
interruption (another app grabbing audio), narrow #118 so a *system* interruption
does not tear down, or delete the branch and say plainly that interruptions end
sessions. **Do not simply trust it** — it has now been observed never to run.

## 398. 🚨 THE DEVICE IS ON A RUNTIME WE CANNOT REPRODUCE — `whoGoesThere` runs **24A5418b** while every simulator we own is beta5 (`24A5408d`) or beta4, and **no Xcode beta 6 exists** — **MEASURED 2026-08-22 from the device's own `callservicesd` BuildVersion in `talaria-138-fork.logarchive`. Raised by Owen as a worry ("we based everything on beta 2 stuff and not what it's evolved to"); the measurement made it sharper than the worry. NOT STARTED.** **⟵ PREMISE MOVED 2026-08-24 (#401): Apple SHIPPED the beta 6 Xcode (27A5252f) carrying the iOS-beta-7 SDK/runtime (24A5422a / 24A5423a) — the "no beta 6 Xcode" clause is dead, and the sim now LEAPFROGS the device instead of trailing it. Dated block at the foot; bars 398-A..C unchanged.** **⟵ ✅ RAN 2026-08-26 on the aligned fleet — 398-A and 398-C MET (device runtime timeline MEASURED end-to-end from two independent sources; the gate now names its runtime on the preflight AND verdict lines), 398-B DEVICE-OWED (runbook card written; the sim still cannot generate, #324/#402). **THIS HEADER'S OWN PROVENANCE WAS WRONG TWICE and is corrected in the result block: the build string comes from `Extra/logd.0.log`, NOT `callservicesd` BuildVersion, and it is stamped 2026-08-17, NOT the 08-22 collection date — so the skew was a SEVEN-DAY window.** Owen's founding worry measures FALSE: no battery ever ran on a beta-2/beta-3 device build, and the device ran builds we still hold (`24A5390f`, `24A5408d`) for most of the measurement era. **STAYS OPEN on 398-B.**

**What was measured, not inferred:**

| | build |
|---|---|
| device `whoGoesThere` | **`24A5418b`** (beta 6) |
| newest sim runtime we hold | `24A5408d` (beta 5) |
| Xcode / SDK | `27A5237l` (beta 5) — **and Apple has shipped no beta 6 Xcode** |

**So every gate result is measured on a runtime the user does not run**, and
there is no local twin of the one they do. This was true for an unknown number
of days and **nothing in the tracker or CLAUDE.md knew it** — the toolchain
section still describes beta5 as the frontier.

### 🔴 Why this is worse for the BRAIN than for anything else

For most of the app a runtime skew is a compatibility question. For the
on-device model it is a **measurement** question, because of #324's finding:
**the simulator cannot generate on the on-device model at all** — `contextSize`
0, generation fails in every build × runtime cell. So brain behaviour has only
ever been answerable on a device, and the device has now moved somewhere we
cannot follow.

**This is the SECOND known contamination window on the battery numbers.** #343
established the first: every rate measured between 2026-08-02 and its fix was
governor-strangled. This is a wider one, and unlike #343's it cannot be closed
by fixing an instrument — it can only be closed by re-measuring on the device.

**Dates of the foundations, which is Owen's actual worry:** the #200-series
batteries are **July, beta3/beta4 era**. #324 re-audited the API surface at
beta5 and found zero Talaria-called FM API changed — but API surface is not
behaviour, and behaviour is what a battery measures.

### ⛔ What will NOT solve this, recorded so nobody spends a night on it

- **A device restore IPSW is not a simulator runtime.** Owen downloaded
  `iPhone18,2_27.0_24A5418b_Restore.ipsw` and stopped when the distinction
  surfaced. `simctl runtime add` takes runtime disk images; an IPSW is a device
  image, different architecture (`arm64-apple-ios` vs `-ios-simulator`) and
  different packaging. **There is no path from an IPSW to a sim runtime.**
- **And a beta 6 sim runtime would not help the brain even if one existed**,
  per #324's cannot-generate finding. It would help the rest of the app.

### 🎯 BARS 398-A…C — pre-registered before any work

- **398-A (name the skew everywhere it is load-bearing).** CLAUDE.md's
  toolchain section and every entry quoting a battery rate carry the runtime
  they were measured on. A number without its runtime is now ambiguous.
- **398-B (re-measure the load-bearing rates on 24A5418b, not all of them).**
  The #215 routing contrast and #343's canary are the two that decide product
  shape; the rest are cell contrasts that were never production facts anyway
  (#215's own rule). **Scoped deliberately — "re-run every battery" is a week
  and most of it would answer nothing.**
- **398-C (the gate's blind spot is STATED, not fixed).** The gate runs on
  beta5 sims and will keep doing so; there is no beta 6 runtime to move it to.
  The honest response is a line in the gate's own output naming the runtime it
  measured, so a green gate stops implying "green on the user's device."

**Cross-references:** **#324** (the beta5 audit, and the cannot-generate
finding that makes this a measurement problem), **#343** (the first
contamination window), **#215** (armed-cell rule — a rate measured in a
configuration the system never enters), **#388** (the beta5 surface sweep).

> **2026-08-24 — THE PREMISE MOVED: Apple shipped Xcode 27 beta 6 (#401's
> arrival measurement, Mac Mini, direct — no MCP).** Owen installed it as
> `/Applications/Xcode-beta6.app`: build **27A5252f**, swiftlang
> **6.4.0.33.1**, iOS SDK **24A5422a**, and a new iOS 27.0 sim runtime
> **24A5423a** already on disk (Ready) — the *iOS beta 7* vintage, released
> alongside it. What this changes and does not change:
> - **The "no beta 6 Xcode exists" clause is DEAD.** The table above is
>   historical as of today.
> - **The skew is not closed — it FLIPPED.** The sim (24A5423a) now leapfrogs
>   the device (24A5418b, beta 6): there is *still* no exact local twin of the
>   build the phone runs, and won't be unless/until the phone takes iOS 27
>   beta 7, at which point the fleet aligns for the first time since beta 5.
> - **398-B (re-measure on device) and 398-C (gate names its runtime) are
>   UNCHANGED** — if anything 398-C matters more now that the gate's runtime
>   will silently advance to 24A5423a via `runtime match`.
> - **New dyld corollary (the #324 rule, third arrow):** the beta 6 Xcode's
>   SDK is *beta-7-vintage* (24A5422a), so a beta6-Xcode-built binary that
>   references new-in-this-SDK symbols would strong-link and die at launch on
>   the phone's OLDER 24A5418b. No new-SDK API adoption until the device is on
>   beta 7.
> The regression round itself is **#401**.

> **2026-08-24 PM (hours after the block above): THE FLEET ALIGNED — Owen
> upgraded `whoGoesThere` to iOS 27 beta 7** (*"Phone was just upgraded to
> beta 7 so we're good there"*). First device/sim/SDK alignment since beta 5.
> Consequences:
> - **#401's dyld adoption freeze is LIFTED** — the device is no longer older
>   than the SDK (24A5422a). The exact device build string is still
>   unmeasured (grab it from the next device log pass the way 24A5418b was
>   grabbed); Owen's word settles the ordinal, not the suffix.
> - **398-B's re-measure got MORE urgent, not less:** it now lands on the
>   runtime where Apple fixed FM excessive tool calling (#401 §3), so the old
>   over-serving rates describe a dead runtime twice over (#343's governor
>   window, then this). A re-measured rate must carry its runtime per 398-A.
> - **398-C stands unchanged** — the gate silently advanced to 24A5423a this
>   very day, which is exactly the behavior 398-C wants named in the output.


> **⚖️ ELECTED 2026-08-25 night (Owen, the ten-item ballot — ALL TEN elected, timing "Tonight, stacked"):** 398-A..C executed at last on the aligned fleet. Own lane; sim/Mac-side halves run tonight, device halves become runbook cards. Bars pre-register in this entry at lane-open where missing (house rule); groupings + order in the plan doc's night-batch addendum (`planning/PLAN-2026-08-25-FINISH-TO-RUNBOOK.md`).


> **✅ RESULT 2026-08-26 — 398-A MET, 398-C MET, 398-B DEVICE-OWED. Measurement
> only: zero app/test code changed, so the suite count is unmoved at 2666 by
> construction and that is the control, not a coincidence.** Evidence artifact:
> `planning/reports/2026-08-26-398-device-runtime-timeline.md`.
>
> **🔴 FIRST, THIS ENTRY'S OWN HEADER WAS WRONG TWICE — and both errors are the
> kind the house rules already name.**
> 1. **The build string does not come from `callservicesd`'s `BuildVersion`.** A
>    predicate query against that process on the very archive this entry cites
>    (`talaria-138-fork.logarchive`) returns **nothing**. The string lives in
>    `Extra/logd.0.log`, emitted as `assertion failed: <build>`. This is the
>    standing "confirm which LOGGER emits a line before making it a bar" rule
>    arriving a second time — a verification step keyed on a marker its component
>    cannot emit is a step that always fails.
> 2. **The measurement is not dated 2026-08-22.** That is the archive's
>    COLLECTION date. The `24A5418b` line inside it is stamped **2026-08-17
>    15:55:40**. The skew therefore opened on **Aug 17** and closed on Aug 24 —
>    a **seven-day window**, not the "unknown number of days" recorded here.
>
> **📐 398-A — MET, and the shape of the fix is not what the bar assumed.**
> The bar asked that every entry quoting a battery rate carry its runtime. Two
> facts made a per-entry annotation campaign both unnecessary and forbidden:
> - **Most rates already carry it.** `BatteryRunStore` and `InstrumentConductor`
>   have recorded `ProcessInfo.processInfo.operatingSystemVersionString` since
>   **2026-07-28** (`801e8728`), and on iOS that string renders as
>   `"Version 27.0 (Build 24A5408d)"` — the build is *in the artifact*. Across
>   `planning/reports/`, **53 files carry `24A5408d` and 4 carry `24A5418b`**;
>   no other build appears anywhere.
> - **Annotating the rest would breach two standing rules.** ~1,500 rate-shaped
>   numbers sit across 66 entries, **47 of them in the archive**, where #261 /
>   #317(a) forbid editing the bytes — and #215 already ruled the #200-series
>   rates *"left un-annotated on purpose."* So the deliverable is the
>   **resolution path**, not the annotation: a measured date→build timeline, in
>   CLAUDE.md's measurement-discipline section as a THIRD axis beside #215's
>   routed check and #343's governor-date check.
>
> **📊 THE TIMELINE — measured from two independent sources that agree.**
>
> | device build | window | evidence | twin held? |
> |---|---|---|---|
> | `24A5355q` | 06-08 → 06-13 | logd | no |
> | `24A5370h` | 06-23 → 07-05 | logd | no |
> | `24A5380h` | 07-06 → 07-20 | logd | no |
> | `24A5390f` | 07-20 → 08-11 | logd | **yes (beta4)** |
> | `24A5408d` | 08-11 → 08-15 | logd + 53 artifacts | **yes (beta5)** |
> | `24A5418b` | ≤08-17 → 08-24 | logd + 4 artifacts | **no** |
> | beta 7 | 08-24 → now | Owen's word only | `24A5423a`; **unconfirmed** |
>
> **The control that makes this a measurement:** an archive collected 2026-08-15
> (`340g`) holds the whole history and **no `24A5418b` line**; one collected
> 08-22 (`talaria-138e`) holds the identical history **plus** that line. An
> archive predating a transition cannot see it; one postdating it can.
>
> **⚖️ OWEN'S FOUNDING WORRY MEASURES FALSE.** *"We based everything on beta 2
> stuff"* — **no battery in this project ever ran on a beta-2 or beta-3 device
> build, because the instrument did not exist yet.** The earliest is
> `runShapeBattery`, `b9094ea3`, **2026-07-27** (the action battery followed
> 07-28) — a week after the device moved to `24A5390f`. *(Self-correction, and
> exactly this lane's own subject: the first draft of this block dated it 07-28
> off `BatteryRunStore`'s commit, which is the RECORD's origin, not the
> instrument's. The one-day seam is real — a 07-27 run has a rate and no
> `osVersion` field, so it resolves by date like any pre-artifact run.)* And for most of
> the measurement era the device ran builds **we still hold as sim runtimes**
> (`24A5390f`, then `24A5408d`). The genuine gap is one week on `24A5418b`.
> The worry was reasonable; the answer is better than the worry.
>
> **⚠️ What 398-A could NOT close: the device's CURRENT build string is still
> unmeasured.** The newest logarchive on this Mac is 2026-08-22 and predates the
> beta-7 upgrade, so `24A5423a`-vs-device parity remains **assumed**. It is not
> a separate chore — 398-B's run stamps it into the artifact automatically.
>
> **🛠 398-C — MET.** The gate now reports the runtime it measured, on the
> **preflight AND the verdict line**, because the verdict is the line that gets
> copied into a tracker entry and the preflight scrolls away. Live output this
> run: `PASS  runtime: iOS 27.0 (24A5423a) on "CC-lane-3"`, followed by the
> caveat that a green gate is green on *that* runtime and not the phone's, and
> `GATE: PASS on 24A5423a`.
> **The probe is not the obvious one, and the two obvious ones are both wrong:**
> `simctl list devices` reports only the runtime IDENTIFIER
> (`…SimRuntime.iOS-27-0`), which **three different builds on this Mac share** —
> precise-looking and uninformative; and `device.plist` records
> `runtimePolicy: System`, i.e. the sim **pins nothing** and follows the system
> runtime match, which is exactly how the gate silently advanced to `24A5423a`
> on 08-24. So the gate asks the booted OS itself via
> `simctl getenv <udid> SIMULATOR_RUNTIME_BUILD_VERSION` (`sw_vers` does not
> exist inside an iOS runtime — probed, NSPOSIXErrorDomain code=2). Reported,
> never checked: an unreadable build prints `runtime: UNKNOWN` rather than
> vanishing, following the SKIPPED-report precedent. Classifier self-test green
> (15 checks), including 300-C's scan for tracker numbers in emitted text.
> **Both verdict branches were witnessed live** — this run ended
> `GATE: FAIL (3 check(s)) on 24A5423a`, so the build rides the FAIL line too
> and not only the happy path. The `UNKNOWN` fallback was exercised separately
> against an unreadable device and resolves to the literal `UNKNOWN`, never to
> an empty string (which would have printed a verdict reading `PASS on ` — a
> silent hole exactly where the fix is supposed to speak).
>
> **⚠️ THE GATE RUN WAS RED, AND IT IS NOT THIS LANE'S RED — but it is not
> being waved off either.** Swift Testing **2666 / 219 suites PASSED** (the
> branch-point baseline, unmoved, which is the control a measurement-only lane
> should produce); Release build **clean**; all **14** XCUITest executed, **13
> passed, 1 failed** — `TalariaUITests.testConnectedRelaunchSkipsTheConnectEntry`
> at `AppTemplateUITests.swift:538`, *"a successful connect should land straight
> in chat"*. **This lane's diff contains ZERO Swift files** (docs, a report, and
> `lane-gate.sh`), so it cannot have caused a UI regression — and #309 Lane B,
> whose Connect Host wizard this test covers and which is the commit at this
> branch point, recorded 14/14 green on the same code. The failure is the
> 15-second `waitForComposer` budget after tapping START CHATTING, on a box with
> a second lane running. *(Correction made in-flight: the gate's
> "XCUITest tests run — 2" is its documented MAX-over-`with 0 failures`-lines
> quirk on a run that HAS a failure, not a truncated bundle — an earlier reading
> in this lane called it a mid-bundle runner death and that was wrong.)*
>
> **Isolation re-run: the same test PASSED alone on the same simulator** —
> `** TEST SUCCEEDED **`, **38.470 s**. Note the durations: **38.396 s when it
> failed, 38.470 s when it passed.** The test sits right on its own wait budget
> either way, so the margin — not the load — is the thing worth looking at.
> **This is deliberately NOT filed as "a flake."** An isolation-passes /
> suite-fails split is exactly the shape a real order-dependence takes, and the
> standing lesson is not to dismiss one as noise. What this lane can honestly
> say is bounded: **the red is not from this diff** (zero Swift files in it, and
> the Swift Testing count is the branch-point baseline to the test), it
> reproduces under a loaded box and clears alone, and it belongs to whoever owns
> the Connect Host wizard. **A clean-box full-suite re-run is owed before anyone
> calls `main` green on XCUITest.** No PR was opened from this lane, so nothing
> merged behind this red.
> **⟵ ✅ THE OWED CONTROL RAN — 2026-08-26 morning (orchestrator, quiet
> box, no concurrent lanes): `GATE: PASS on 24A5423a` — 2693 Swift
> Testing / 219 suites + 14/14 XCUITest + Release, first run. `main` IS
> green on XCUITest.** The tally on this test across an unchanged tree is
> now **1 fail in 4 full-suite runs** (Lane B 14/14 · this lane 13/14
> under a loaded box · instruments 14/14 · the quiet-box control 14/14) —
> consistent with the margin-not-load reading above (it failed 0.07 s
> from where it passes). The deeper question (widen the wait budget vs a
> real order-dependence) stays with this filed note for whoever touches
> the wizard's tests next; recurrence data now has its baseline.
>
> **🔴 ⟵ SUPERSEDED THE SAME NIGHT (2026-08-27 ~01:00, from #415's fix
> lane): `main` IS NOT GREEN ON XCUITEST RIGHT NOW, and that is a
> MEASUREMENT, not an inference.** A full gate run on **`origin/main`
> itself** — commit `60a874dd`, detached, no lane changes, 2742 Swift
> Testing and Release clean — ended `GATE: FAIL (3 checks)` on **this exact
> test**, same assertion, same line. The lane that measured it did so as its
> own exculpatory control after the test reddened **3 of 5** of its gate
> runs; a paired isolated-bundle run had already shown base and branch both
> **15/15** with the test at **37.983 s** on base and **37.731 s** on the
> branch (the branch is *faster* on the failing test). **So the recurrence
> tally is no longer "1 fail in 4 on an unchanged tree"** — it is roughly
> **4 in 10 full-suite runs across two trees on one night**, and **0 in
> every isolated bundle run**, which is exactly the shape the note above
> declined to call a flake. Whoever owns the wizard's tests: the choice
> (widen the 15 s `waitForComposer` budget vs find the order-dependence)
> is now a live one, and until it is made, a lane's red gate on this test
> means nothing about that lane. Evidence lives in #415's result block.
>
> **📱 398-B — DEVICE-OWED, and its target build is SUPERSEDED.** The bar reads
> "re-measure on `24A5418b`"; that build is dead — the device left it on 08-24.
> The bar's SUBSTANCE (re-measure the two load-bearing rates on the device)
> stands unchanged and now lands on beta 7. Still device-only: #324's
> cannot-generate finding was re-measured as recently as #402 (generation dead on
> both tiers on sim), so no simulator can answer this.
> **Both rates now have a known prior runtime**, which is what makes the
> re-measure a contrast rather than a fresh guess:
> - **#215 routing contrast** (run `F486F103`, 2026-08-01) → `24A5390f` by date.
>   Also predates the governor, so it is governor-free on #343's axis too.
> - **#343 canary** (2026-08-15) → `24A5408d`, from its own 30-plus artifacts.
>   An earlier reading of this lane placed it inside the unresolved
>   Aug-11-to-Aug-17 window; the artifacts close it.
>
> **📱 DEVICE CARD (for the runbook — the orchestrator owns the file):**
> > **#398-B — re-measure the two load-bearing rates on beta 7.** Developer
> > screen, device only, brain = **on-device**. Roughly 25 min attended.
> > **Run, in this order:**
> > 1. **`motion-scope`** (canary #1) — the retention canary. Read-only, no
> >    confirmations fire.
> > 2. **`routed`** — the #215 contrast: cells `armed` (unrouted control) vs
> >    `routed-production`, all four prompts, grab canary IN. **Auto-ACCEPT and
> >    it writes real reminders/alarms/events** — they are reaped before DONE,
> >    but do not run it on a day the calendar matters.
> > 3. **`motion-scope`** again (canary #2) — start-vs-end drift check.
> > **EXPECT / BARS:** canary #1 and canary #2 each **20/20** on
> > `stepsdirect`/`readHealth`; ANY drop, even one trial, is the finding
> > (retention, not delta). For `routed`, the 2026-08-01 reading to contrast
> > against is unrouted **6/10 grabs + 4/10 disclaimer tics, zero clean
> > composition turns** vs routed **10/10 clean, 0 grabs**; creates were 10/10 in
> > both arms.
> > **FAILS IF:** a cell reports zero trials (instrument state, not behaviour —
> > check the error counter before reading any rate), or the two canaries
> > disagree (within-night drift; the run's rates are then not comparable to
> > anything).
> > **⚠️ READ THE RATES AGAINST THE RIGHT RUNTIME.** Apple fixed FM excessive
> > tool calling in this OS, so the old over-serving numbers describe a dead
> > runtime twice over — governor window, then runtime change.
> > **🎁 THIS RUN ALSO CLOSES 398-A's LAST GAP FOR FREE:** every artifact stamps
> > `osVersion`, so the phone's beta-7 build string — currently unmeasured
> > anywhere — lands in the JSON without a separate step. Read it back with
> > `grep -rhoE '"osVersion" : "[^"]+"' planning/reports/<run>` and record it in
> > this entry; that is the one line 398-A still owes.
> **✅ 398-A's LAST GAP CLOSED 2026-08-27 — the device's CURRENT build string is
> MEASURED: `24A5424a`.** It arrived free, from an instrument artifact's own
> `osVersion` field during #416's device runs — the pre-OTA subset printed the
> transition itself:
> `⚠ RE-BASELINE: osVersion changed 'Version 27.0 (Build 24A5418b)' → 'Version 27.0 (Build 24A5424a)'`.
> **No logarchive, no `log collect`, no device sitting** — exactly the "most
> rates already carry it, read it don't guess it" route this entry established.
>
> **🔴 AND IT FALSIFIES THE ASSUMED PARITY.** The newest sim runtime on this Mac
> is `24A5423a`; the device is `24A5424a`. They are NOT the same build — the
> phone leads by one revision and **we hold no local twin of it**, so the
> "fleet is ALIGNED" clause written on 2026-08-24 (Owen's word, honestly flagged
> as unmeasured at the time) is now measured false. CLAUDE.md's three alignment
> claims are corrected in the same commit per the close-out rule.
>
> **What does NOT change, and the distinction is the point:** the #324 adoption
> freeze stays LIFTED. That hazard bites only when a binary references symbols
> NEWER than the runtime it launches on, and our SDK (`24A5422a`) is the OLDEST
> of the three — older SDK onto a newer device runtime is the safe direction.
> **The conclusion survives while its stated premise does not**, which is the
> shape CLAUDE.md's own "probe live before assuming this holds" was warning about.
>
> **Timeline gains a fourth row:** `24A5390f` 07-20→08-11 · `24A5408d`
> 08-11→08-15 · `24A5418b` 08-17→08-24 · **`24A5424a` 08-24→present**. The
> genuine no-twin gaps are now two: one week on `24A5418b`, and everything from
> 08-24 onward.

> **📏 2026-09-01 — THE TIMELINE GAINS A FIFTH ROW, read free off an artifact's
> own `osVersion` exactly as 398-A prescribes.** #392's `--trials 50` decline
> run records the device at **`Version 27.0 (Build 24A5430a)`** — newer than the
> `24A5424a` measured 2026-08-27, so the phone took another OS update in the
> intervening days.
>
> `24A5390f` 07-20→08-11 · `24A5408d` 08-11→08-15 · `24A5418b` 08-17→08-24 ·
> `24A5424a` 08-24→08-31 · **`24A5430a` from 2026-08-31/09-01**.
>
> **The sim/device gap widens again:** the newest runtime we hold is
> `24A5423a` and our SDK is `24A5422a`, so the device is now **two revisions
> ahead** of any local twin. **The #324 adoption freeze still does NOT bite** —
> it triggers only when the SDK is NEWER than a target runtime, and ours is the
> oldest of the three — but every simulator rate is now measured two revisions
> away from what Owen runs, and any rate quoted from here should carry its
> build.

## 415. 🔴 THE MIC STAYED ON after a Control Center voice launch — 2/2 reproducible, cleared by force-quit — and the control said "Talk to HERMES" (**renamed — see 415-N**) — **FILED 2026-08-26 night per #268, from Owen's third runbook pass (BUILD 3108, verbatim: "Control center > Talk to Hermes (should be Talaria, right?) and the mic stayed on. Tried again, same result. Force quit, tried again, did NOT happen."). Mechanism NOT guessed; the SAME-DAY LOG COLLECT is the discriminating evidence and it decays in hours.** **→ ✅ COLLECT HAPPENED AND THE MECHANISM IS NAMED (2026-08-26, `whoGoesThere-415.logarchive`): this is #302 recurring through an ordering its bars cannot see — `AppLockGate` is sampled ONCE at start, and a Control Center tap on a WARM process clears it ~1.2 s BEFORE App Lock arms, so the cover comes down on top of an in-flight start. Mic hot 27.4 s / 13.4 s, most of it behind `cover=locked`. Engine was REALTIME both times and teardown RAN IN FULL — the #303 and #198 candidates are FALSIFIED. The force-quit run is a DEGENERATE control (cold ⇒ gate already armed ⇒ start parked ⇒ revoked unused). Fix bars 415-A…D proposed below; #302 carries a dated supersession. ~~FIX NOT BUILT.~~** **⟵ ✅ 415-N DONE 2026-08-26: the NAMING half (fact 2) SHIPPED — both Control Center controls read "Ask Talaria" / "Talk to Talaria", host-meaning "Hermes" strings deliberately untouched and now pinned.** **⟵ ✅ THE MIC FIX IS BUILT 2026-08-26 night (same day): 415-A/B/C MET — a session covered mid-flight now STOPS CAPTURE and PARKS, resuming exactly once on unlock, via a cover watch on the gate's new `waitUntilLocked()`; the realtime engine gained the `#302-A` capture instrument. 415-A was witnessed RED on the unmodified tree first (8 tests, 21 issues) and each mutation isolates. 🔴 STILL OPEN ON 415-D ONLY — the device run that HOLDS the cover open; its card is written in the result block, and until Owen runs it this item stays red.**

**The two facts, separately:**
1. **The mic indicator persisted** after Control Center → Talk to Hermes,
   twice in a row; after a force-quit the third attempt was clean. The
   2/2-then-clean shape points at STATE ACCUMULATED in the long-running
   process (an audio session/engine or tap not torn down on the CC-launch
   path), not a per-launch race — but that is a candidate class, not a
   finding. A live mic indicator is capture-session-alive: this is
   privacy-surface real, not cosmetic.
2. **The control's title says "Talk to Hermes"** — should be Talaria
   (Owen's own parenthetical, and now doubly ruled by #77's
   talaria-primary direction). **⚖️ EXTENDED minutes later (Owen,
   verbatim: "The talk and chat ones should be changed from hermes to
   talaria") — BOTH Control Center controls rename. Scope is exactly the
   two control titles (and their intent display names): the app still
   says "Hermes" wherever it means THE HOST, which stays correct.**
   Rename lane dispatched the same hour.

**Candidates for (1), a starting list:** the CC cold-launch path pins the
NATIVE engine (#303's measured asymmetry — this launch shape is exactly
its territory); the native pipeline's `setVoiceProcessingEnabled` input
tap surviving session end; a #198-family audio-session deactivation miss
on the intent-launched path (the memo path got its async discipline in
#198B — the CC voice path may not have). **Name it by measurement:**
the locked-interval log corpus (#302/#323's own card — the FAIL was
scored against it) would show which engine held the session and whether
teardown ran. **⟵ RUN 2026-08-26, and it answered both: the engine was
REALTIME on both stuck launches (so the #303 pin is not this), and
teardown RAN IN FULL (so the #198-family miss is not this either). Both
of those candidates are FALSIFIED; the third — an App-Lock-family miss —
is what landed, in a form this list did not contain. See the 📏 FORENSICS
block below.** **⏰ The events were ~22:1x local on 08-26; logd evicts
app-subsystem rows in HOURS — a `sudo log collect` tonight captures the
2/2 reproductions AND the clean control run; tomorrow it likely cannot.**

**Related:** #303 (the CC-launch engine pin — this may be its first
user-visible cost, which would change its measured-only status), #198A/B
(audio-session teardown discipline), #220 (engine attribution), #138
(voice umbrella), #413 (the night's other voice finding — different
shape, same subsystem), #77 (the naming direction).

---

### 📏 FORENSICS 2026-08-26 — MECHANISM **NAMED** from `whoGoesThere-415.logarchive`. It is **#302's headline ordering surviving #302's fix**; the engine-pin and teardown-miss candidates are both **FALSIFIED**.

**Corpus + method.** `~/Desktop/whoGoesThere-415.logarchive` (3.1 GB, collected
22:26). Read with `/usr/bin/log show … --info --debug`, chunked predicates.
Positive control run FIRST: `subsystem BEGINSWITH "org.aethyrion"` over
20:30–23:00 returns **503 rows** across both app subsystems
(`org.aethyrion.talaria` for the hand-rolled `Logger(...)` call sites,
`org.aethyrion.talaria27` for `TalariaLog.subsystem` = the bundle id), so every
absence below is scored against a live channel. **All three CC launches are in
the corpus** — exactly three `OpenHermesVoiceIntent.perform` rows exist in the
whole window, matching Owen's "twice, force quit, third."

**⛔ WHAT THE ARCHIVE DOES NOT CONTAIN, said before it is leaned on.** There is
**no `mediaserverd`, no `audiomxd`, no `coreaudiod`, no `runningboardd`, no
`SpringBoard`, and no `com.apple.SystemStatus`** anywhere in the window — probed
by name, zero rows each, against a positive control of **2,302
`com.apple.coreaudio` rows in a 2-minute slice from 16 other processes**. So the
mic INDICATOR's own attribution daemon was never captured and the orange dot is
**not directly observed**. What IS observed is the client-side ground truth:
`AURemoteIO` start/stop and `AVAudioSession` activate/deactivate **inside the app
process**. Those bracket the reported symptom exactly, and a system-wide sweep for
`Starting/Stopping AURemoteIO` over 22:10–22:25 finds **only two app-attributed
capture intervals in the entire window** (both below; the only other rows are
`appleh16camerad`, unrelated).

**PER-LAUNCH TIMELINE.** *(`Df` = Default = `.notice`; verbose was ON.)*

**LAUNCH 1 — 22:17:24, PID 10131 (WARM process, up since 22:17:06). MIC HOT 27.4 s, 24.3 s of it behind a LOCKED cover.**
```
22:17:23.058  AppLock       scenePhase inactive -> background | pre: cover=obscured locked=false
22:17:24.208  AppLock       scenePhase background -> inactive | pre: cover=obscured locked=false
22:17:24.221  controls      OpenHermesVoiceIntent.perform fired in the APP process — routing talaria://voice
22:17:24.246  VoiceEngine…  voice session starting on engine realtime (voiceHostPaired=true)   ← GATE CLEARED
22:17:24.301  coreaudio     AVAudioSession_iOS.mm:1017  Activated session 0x63c5e1
22:17:25.418  AppLock       scenePhase inactive -> active | pre: cover=obscured locked=false   ← autoAuth FIRED
22:17:25.469  AppLock       scenePhase active -> inactive | pre: cover=locked  locked=true     ← LOCK ARMS (1.2 s LATE)
22:17:27.850  coreaudio     AURemoteIO.cpp:1673  Starting AURemoteIO(0x13be15e40)              ← MIC HOT, 2.4 s AFTER locked=true
22:17:29.005  AppLock       requestUnlock EXIT attempt=1 result=FAILED_OR_CANCELLED didFail=true
22:17:29.412  LiveVoice…    #138 speech_started … 22:17:31.178 audio.started … BARGE-IN …     ← a full realtime conversation, behind the cover
22:17:52.159  AppLock       requestUnlock EXIT attempt=2 result=SUCCESS
22:17:55.299  coreaudio     AURemoteIO.cpp:1748  Stopping AURemoteIO(0x13be15e40)   (+2 more)
22:17:55.751  coreaudio     Deactivated session 0x63c5e1   (+2 more, through 22:17:56.853)
22:17:56.350  VoiceOverlay  #254 254-F: VoiceOverlayScreen.onDisappear fired (appState=active)
```

**LAUNCH 2 — 22:18:30, PID 10131 (SAME warm process). MIC HOT 13.4 s, 10.3 s behind a LOCKED cover. Identical shape, tighter race.**
```
22:18:30.648  AppLock       scenePhase background -> inactive | pre: cover=obscured locked=false
22:18:30.662  controls      OpenHermesVoiceIntent.perform fired in the APP process — routing talaria://voice
22:18:30.685  VoiceEngine…  voice session starting on engine realtime (voiceHostPaired=true)   ← GATE CLEARED
22:18:30.708  coreaudio     Activated session 0x63c5e1
22:18:31.883  AppLock       scenePhase inactive -> active | pre: cover=obscured locked=false
22:18:31.941  AppLock       scenePhase active -> inactive | pre: cover=locked  locked=true     ← LOCK ARMS
22:18:32.213  coreaudio     Starting AURemoteIO(0x139f90a40)                                   ← MIC HOT **272 ms AFTER** locked=true
22:18:36.034  AppLock       requestUnlock EXIT attempt=1 result=FAILED_OR_CANCELLED didFail=true
22:18:39.259  LiveVoice…    #138 speech_started … 22:18:41.004 audio.started                   ← again, conversing behind the cover
22:18:42.474  AppLock       requestUnlock EXIT attempt=2 result=SUCCESS
22:18:45.628  coreaudio     Stopping AURemoteIO(0x139f90a40)   (+2 more)
22:18:46.063  coreaudio     Deactivated session 0x63c5e1       (+2 more, through 22:18:47.166)
22:18:46.637  VoiceOverlay  #254 254-F: onDisappear fired (appState=active)
```

**LAUNCH 3 — 22:18:57, PID 10161 (COLD, post-force-quit). MIC NEVER OPENS — and the control is DEGENERATE.**
```
22:18:56.923  VoiceEngine…  active voice engine → native (initial; voiceHostPaired=false)      ← process start
22:18:57.165  ChatStore     compose outbox drain deferred — App Lock is covering the app (#323-A)  ← GATE ALREADY LOCKED
22:18:57.190  controls      OpenHermesVoiceIntent.perform fired in the APP process — routing talaria://voice
22:18:57.815  AppLock       scenePhase background -> active | pre: cover=locked locked=true
22:18:57.937  VoiceEngine…  active voice engine → realtime
              ── NO `voice session starting` line. NO `Activated session`. NO AURemoteIO. ──
22:18:59.083  AppLock       requestUnlock EXIT attempt=1 result=FAILED_OR_CANCELLED didFail=true  ← and he never retried
22:19:47.560  AppContainer  #118/#254: app backgrounded with a voice session (STARTING) — revoking it
22:19:47.567  VoiceOverlay  #254 254-F: onDisappear fired (appState=**background**)
```
**The third run is not a clean run of the same experiment.** On a cold process
App Lock is locked *before* the intent lands, so `deferUntilUnlocked` **parked**
the start (that is what the `STARTING` arm of the revoke proves — `isStartingSession`
was true while `voiceService.startSession()` had never been reached). Owen then
failed Face ID once, never retried, and backgrounded 50 s later, so the parked
start was revoked unused. **It shows the gate WORKING, not a fresh process being
safe.** A cold launch where the user *does* unlock is still untested.

**ANSWERS TO THE FOUR QUESTIONS.**

1. **Engine — `realtime` on both stuck launches; launch 3 never started.** Every
   process start logs `active voice engine → native (initial; voiceHostPaired=false)`
   and flips to `realtime` 0.3–0.6 s later once pairing resolves; that flip is
   startup ordering, not a session decision. **#303's asymmetry is NOT what
   happened here** — the two sessions that ran, ran realtime, and the one cold CC
   launch never reached `startSession()`, so #303's pin was not exercised. #415's
   first candidate is **falsified for this corpus**.
2. **Teardown — IT RAN, fully, on both stuck launches. Candidate FALSIFIED.**
   `Stopping AURemoteIO` ×3, `Deactivated session` ×3, and the
   `NativeVoicePipeline`/`LiveVoiceSessionService` `audio deactivated by app —
   not an interruption (#198)` pairs, all present at 22:17:55–56 and
   22:18:45–47. There is **no audio activity at all** between 22:17:56.853 and
   22:18:32.213, or after 22:18:47.166 through 22:23. Nothing leaked past the
   session; the #198-family teardown-miss candidate is dead.
3. **Who held the mic — the app itself, legitimately, for the whole locked
   interval.** The only two app-attributed capture intervals in the window are
   the two above, both in PID 10131, both starting *after* `locked=true`. The
   symptom is not a leak after the session; it is **a session that ran to
   completion underneath the App Lock cover**, invisible, with the indicator lit
   and no voice UI on screen.
4. **What differed on the clean run — the ORDER in which App Lock armed,** not
   the process age as such. Cold ⇒ locked-then-intent ⇒ parked. Warm ⇒
   backgrounded-then-intent ⇒ the intent lands in the `.inactive` window where
   `cover == .obscured` and `isLocked == false`.

**🔴 MECHANISM, NAMED.** `TalkStore.deferUntilUnlocked` (`Talaria/Stores/TalkStore.swift:199`)
**samples `AppLockGate.isLocked` exactly once, at the instant of start, and never
re-checks.** `AppLockStateMachine` only computes `cover == .locked` on the
transition INTO `.active` (`Talaria/Services/Support/AppLockCore.swift:78`,
`:108–111` — any non-`.active` phase yields `.obscured`, and `.obscured` is
**deliberately** not locked, per `AppLockGate`'s own doc and bar 302-D). A
Control Center tap runs `OpenHermesVoiceIntent.perform()` **in the app process**
(`Shared/HermesControlIntents.swift:82`, `supportedModes = .foreground`,
`allowedExecutionTargets = .main`) during the `background → inactive` window that
**precedes** that transition. Measured gap: the gate was open for **1.2 s** after
the intent fired on both stuck launches, and the start cleared it in **23–25 ms**.
The cover then arms on top of an in-flight start, and nothing re-parks or tears
down a session that becomes covered *after* it started. Result: mic hot **0.27 s
and 2.4 s AFTER `locked=true`**, and hot until the user finally authenticates.

**This is #302's own headline sentence** — *"a voice session STARTS ~650 ms before
App Lock evaluates its cover"* — **surviving #302's fix.** Bars 302-D…G every one
place the lock BEFORE the start (302-E's evidence shape is literally "gate locked
⇒ start count stays 0"); **not one scores "gate open at start, lock arms
mid-flight."** The fix closed the arm the bars measured and left the ordering the
title named. → **#302 needs a dated re-open pointer; #415 is its recurrence, not a
new defect.**

**🔍 SECOND FINDING — the instrument is on the wrong engine, and that is probably
why #302's device pass held.** The `#302-A` capture-chain instrument
(`audio session activated for capture` / `capture chain HOT` / `capture chain
COLD`) exists **only** in `NativeVoicePipelineService.swift` (`:1006`, `:1040`,
`:1173`). `LiveVoiceSessionService` — the realtime engine, the one all three #415
launches routed — has **no capture hot/cold line at all**. So on realtime the
app's own log **cannot answer "was the mic hot?"**, which is why this forensics
had to fall back to CoreAudio `Df`-level rows that a later `log collect` may not
retain. #302's 2026-08-20 device verification scored the engine that carries the
instrument.

**🎯 THE FIX LANE'S DISCRIMINATING TEST (bars, to be pre-registered before code).**

- **415-A — the lock arming MID-FLIGHT parks or kills the start.** Unit, and the
  only bar that discriminates this defect from #302's fixed one: with
  `gate.isLocked == false`, drive `startSessionDirectly()`; while the fake voice
  service is suspended inside `startSession()`, flip `gate.setLocked(true)`.
  **Assert the capture chain never comes up** (fake records no start, or records
  a start followed immediately by an abandon) **and** that a later
  `setLocked(false)` resumes it exactly once. Score `startSession()` and
  `startSessionDirectly()` **separately**, per 302-E's rule. Mutation: delete the
  re-check ⇒ RED. **Run it against today's `main` FIRST and confirm it is RED —
  a bar that is green before the fix is measuring the wrong thing.**
- **415-B — the negative control that keeps 415-A honest** (mirror of 302-G):
  App Lock disabled ⇒ arming has no effect, one start, no stop, no wait. Without
  it, 415-A is satisfied by a build that never starts voice.
- **415-C — the realtime engine grows the `#302-A` instrument.** `LiveVoiceSessionService`
  emits capture HOT/COLD `.notice` lines at the same two seams the native pipeline
  does. **415-B and the device bar are not scorable without it**, because the only
  current evidence for realtime capture is a `Df` CoreAudio row from a framework.
- **415-D — device, and it must hold the cover open.** Warm process: background
  the app, tap Control Center → Talk, **cancel Face ID and hold the locked cover
  ≥30 s.** Score from the archive: no `capture chain HOT` / `Starting AURemoteIO`
  may appear while any `cover=locked` is in effect; after unlock it may. Then the
  **untested** cell: cold launch, tap the control, and **unlock** — confirming the
  parked start resumes rather than being the accident that made run 3 look clean.

**Deviations from the brief:** the mic's system-side owner could not be consulted
(daemon absent from the archive, documented above with its positive control), so
question 3 is answered from in-process CoreAudio rather than `mediaserverd`; and
the brief's leading candidate class (long-running-process state accumulation) is
**refined rather than confirmed** — warm-vs-cold IS the discriminator, but the
causal variable is App Lock's arming order, not accumulated state.

---

### 415-N — the NAMING half (fact 2 only). **Bars written first, 2026-08-26, before any edit.**

**What HEAD actually spells, read before the bars were written** (the
dispatch guessed `Chat with Hermes`; that string does not exist). The two
Control Center controls are `AskHermesControl` and `TalkToHermesControl`
(`TalariaWidgets/Controls/HermesControls.swift`), driven by
`OpenHermesChatIntent` / `OpenHermesVoiceIntent`
(`Shared/HermesControlIntents.swift`, compiled into BOTH targets). So the
"chat one" Owen means is titled **"Ask Hermes"**, not "Chat with Hermes".

**415-N-1 — the four user-facing title strings say Talaria.**
`OpenHermesChatIntent.title == "Ask Talaria"` and
`OpenHermesVoiceIntent.title == "Talk to Talaria"`, pinned as COMPILED
values through the app module (`LocalizedStringResource` is `Equatable`).
A test that only reads source text would pass on a commented-out literal;
these two do not.

**415-N-2 — the widget-target strings, structurally.** The `ControlWidget`
structs are widget-target-only and cannot be compiled into the app test
host, so their `Label` / `.displayName` / `.description` literals are
pinned by READING `TalariaWidgets/Controls/HermesControls.swift` (the #399
source-reading pattern, same shape as `RunsTransportSwitchTests`): the
file must spell `"Ask Talaria"` and `"Talk to Talaria"` and must contain
**no** `"Ask Hermes"` / `"Talk to Hermes"` string literal. Fails loudly if
the file cannot be read — a check that cannot run must say so.

**415-N-3 — the control `kind` identifiers do NOT move.** The system keys
placed controls by `kind`; a rename orphans every control Owen has already
placed. `HermesControlKind.askHermes`/`.talkToHermes` keep their
`org.aethyrion.talaria27.control.*` values — already pinned by
`HermesControlsTests.controlKindsAreStable`, which must stay green
UNCHANGED. **A title rename that also moved a kind would pass 415-N-1 and
still be a regression**, which is why this bar is written separately.

**415-N-4 — "Hermes" survives where it means THE HOST, shown
structurally.** A rename lane's real risk is a global search-and-replace,
and a bar that only checks the two new titles cannot see that. So: the
composer placeholder (`"Message Hermes…"`), the Connect Host copy (`"A
Hermes gateway"`, `"Something's there, but it isn't Hermes"`) and the
chat-status copy (`"Hermes host online"`) must all still be present in
`Talaria/` source after the edit. These are host-meaning strings and stay
correct.

**415-N-5 — the gate.** `scripts/mac/lane-gate.sh` green on `CC-lane-2`
under Xcode-beta6: Swift Testing + XCUITest + the Release build, positive
markers from each. Baseline to beat: ~2726 Swift Testing tests (verified
at lane open); the delta must equal the tests this lane adds and nothing
else.

**Explicitly OUT of scope, and each is a deliberate leave, not an
oversight** *(⟵ the first two were later ELECTED and renamed by 415-S,
2026-08-26; they were correctly out of scope for THIS lane and the
enumeration is what let Owen rule on them)* — enumerated before the edit
so the close-out cannot quietly
grow: `AskHermesIntent` (the #6 Siri/Shortcuts intent, title "Ask
Hermes"), `TalariaAppShortcuts`' `shortTitle: "Ask Hermes"`,
`StartVoiceSessionIntent`'s description, and
`CarPlayVoiceManager`'s `titleVariants: ["Talk to Hermes"]` — all
different surfaces from the two Control Center controls Owen named.
**The Siri PHRASES need no change at all**: they are already built from
`\(.applicationName)` (`"Talk to \(.applicationName)"`, `"Ask
\(.applicationName)"`), so Siri has always said Talaria. And the two
control intents are `isDiscoverable = false` — they have no Siri phrases
of their own to rename. Swift TYPE names (`AskHermesControl`,
`OpenHermesChatIntent`, `HermesControlKind`) are not user-facing and stay.

**✅ 2026-08-26 — 415-N DONE. Fact 2 only; fact 1 (the mic) is UNTOUCHED
and stays 🔴 OPEN at the top of this entry.** Every bar met.

**The titles, verbatim, before → after:**

| surface | before | after |
| --- | --- | --- |
| chat control `Label` + `.displayName` | `Ask Hermes` | `Ask Talaria` |
| chat control `.description` | `Open the Hermes chat and ask a question.` | `Open the Talaria chat and ask a question.` |
| `OpenHermesChatIntent.title` | `Ask Hermes` | `Ask Talaria` |
| `OpenHermesChatIntent` description | `Opens Talaria to the Hermes chat.` | `Opens Talaria to the chat.` |
| voice control `Label` + `.displayName` | `Talk to Hermes` | `Talk to Talaria` |
| `OpenHermesVoiceIntent.title` | `Talk to Hermes` | `Talk to Talaria` |
| voice control `.description` | `Open Talaria and start a hands-free voice session.` | *(unchanged — already correct)* |

Six sites moved, one was already right. Files:
`TalariaWidgets/Controls/HermesControls.swift`,
`Shared/HermesControlIntents.swift`. Two stale comments naming the old
titles were corrected in the same commit (`DeeplinkRouter.swift`'s `voice`
case, `AppLockGateTests`' device-repro note) per the close-out rule.

**What was DELIBERATELY left as "Hermes", and why each is right** — the
whole risk in a rename lane is the global search-and-replace, so this list
is the deliverable as much as the rename is:
- **The composer placeholder, Connect Host copy, chat status lines,
  Settings copy, CarPlay's `"Connecting to Hermes..."` / `"Hermes is
  speaking"`** — these mean THE HOST. Talaria is a client for a Hermes
  agent; that word is load-bearing, not legacy branding. Pinned by
  415-N-4 so a future sweep cannot quietly take them.
- **`AskHermesIntent` (#6), title `"Ask Hermes"`, and
  `TalariaAppShortcuts`' `shortTitle: "Ask Hermes"`** — the Siri/Shortcuts
  surface, not a Control Center tile. Owen named the CC controls; renaming
  Shortcuts entries is a separate call and was not made.
  **⟵ SUPERSEDED 2026-08-26: the call WAS subsequently made** (Owen,
  ruling the stragglers: *"shortcuts only"*). Both strings now read
  "Ask Talaria" — see **415-S** below. The TYPE name `AskHermesIntent`
  is the only part of this bullet still standing, and 415-S records why
  it must: it is the registration identity.
- **`CarPlayVoiceManager`'s `titleVariants: ["Talk to Hermes"]`** — the
  CarPlay voice template's idle state, a third surface (the car screen).
  ⚠️ **Flagging it for Owen**: it is the same words on the same action, so
  it plausibly wants the same treatment, but it is outside the ruled scope
  and sits in a family with two host-meaning siblings. One line if elected.
- **Swift type names and the control `kind` identifiers** — not
  user-facing; `kind` in particular MUST NOT move (415-N-3).

**Siri needed nothing, and this is worth recording because it looks like a
gap:** the phrases are built from `\(.applicationName)` —
`"Talk to \(.applicationName)"`, `"Ask \(.applicationName)"` — so Siri has
said *Talaria* since the phrases were written. The two control intents are
`isDiscoverable = false` and have no phrases of their own. No App Shortcuts
implication either way.

**🟡 One honest instrument correction, made mid-lane.** 415-N-2's test was
first written as a COUNT (`"Ask Talaria"` must appear exactly twice — Label
+ displayName). It went red on the GREEN run against a correct rename,
because the explanatory comments I added to the same file also quote the
new titles. The count was my test's detail, not the registered bar (which
says only "must spell … and must contain no old literal"), so it was
replaced with something **stricter**, not looser: all six sites matched
*with their surrounding call* (`Label("Ask Talaria", systemImage:
"text.bubble")`, `.displayName("Ask Talaria")`, …), which no comment prose
can satisfy. RED-first was re-established by measurement rather than
argument — `git show 0ef3fd44:…HermesControls.swift` contains **five of the
six** site strings zero times (the sixth is the voice description, which
was already correct and which no bar claimed would change).

**Test evidence.** `HermesControlsTests` 8 → **11 tests, +3**
(`launchIntentTitlesNameTalaria`, `theWidgetControlsSpellTalaria`,
`hostMeaningHermesStringsSurviveTheRename`). RED-first at HEAD: **7 issues
across the two new title bars**, with the host-meaning guard already green
(as it must be — it is a guard, not a goal). After the rename: **11/11
pass**.

**415-N-5, the gate** — `TALARIA_SIM_NAME=CC-lane-2` under Xcode-beta6,
**GATE: PASS on 24A5423a**, first run, no flake re-runs:
**2729 Swift Testing** + **15 XCUITest** + Release build clean (0 Swift
compile errors), preflight all-PASS including the TCC grant and the
`project.pbxproj` drift check. **The count MOVED 2726 → 2729, exactly +3**
— the three tests this lane adds and nothing else, which is the check that
`test-without-building` staleness would have failed. The 2 skips are the
known-permanent `CondenserFidelityTests` pair (needs Apple Intelligence
hardware); nothing new was skipped. **Runtime caveat the gate now prints
itself (398-C): green on sim runtime 24A5423a, which is not measured to be
the phone's build** — irrelevant to a string rename, recorded because the
gate says so on every run.


> **⚖️ FIX LANE ELECTED 2026-08-26 night (Owen: "go, dismissed the chip,
> orchestrate the lane" — the forensics agent's suggested-task chip was
> redundant with this dispatch and he dismissed it).** Scope per the
> forensics: the mid-flight gate re-evaluation (a session that becomes
> COVERED after starting is parked/stopped — closing #302's blind
> ordering) + the realtime engine gains the #302-A capture instrument.
> Bars 415-A..D formalize at lane-open; 415-A proven RED on today's
> main first, per its own proposal.


> **⚖️ THE TWO STRAGGLERS RULED 2026-08-26 night (Owen: "shortcuts only.
> Notate about the carplay. I don't see any reason to make changes that
> we can't even see right now."):**
> - **Shortcuts surface ELECTED:** `AskHermesIntent.title` + the
>   `TalariaAppShortcuts` `shortTitle` rename to "Ask Talaria" — mini-lane
>   dispatched.
> - **CarPlay DECLINED-FOR-NOW, his reasoning verbatim above:**
>   `CarPlayVoiceManager.swift`'s `titleVariants: ["Talk to Hermes"]`
>   stays — CarPlay is UNVERIFIABLE today (#74: the CarPlay simulator
>   window has been broken across beta 4/5/7 runtimes, three cycles), and
>   a change nobody can see is a change nobody can verify. **This
>   notation is the standing record: when #74's sim pass finally works
>   (or CarPlay becomes otherwise verifiable), the one-line rename rides
>   the first CarPlay-touching lane — it is deferred-with-a-trigger, not
>   forgotten.**

---

### 415-S — the SHORTCUTS half (the elected straggler). **Bars written first, 2026-08-26, before any edit.**

**415-S-1 — the intent title is a COMPILED value and says Talaria.**
`AskHermesIntent.title == "Ask Talaria"`, asserted through the app module
(`LocalizedStringResource` is `Equatable`), exactly as 415-N-1 did for the
two control intents. A source-text check would pass on a commented-out
literal; this one does not.

**415-S-2 — the `TalariaAppShortcuts` `shortTitle`, structurally.**
`AppShortcut` exposes **no readable `shortTitle` property** — the SDK
interface declares initializers only (verified in
`AppIntents.swiftinterface`, iOS SDK 24A5422a), so the compiled value is
unreachable from a test. It is pinned by READING
`Talaria/Intents/StartVoiceSessionIntent.swift` (the #399 / 415-N-2
source-reading pattern): the file must spell `shortTitle: "Ask Talaria"`
**with its surrounding call** — matched that way so no comment prose can
satisfy it — and must contain no `"Ask Hermes"` string literal. Fails
loudly if the file cannot be read.

**415-S-3 — CarPlay is UNTOUCHED, shown structurally.** Owen declined it
with a trigger, so the bar is not "we didn't edit it" (unfalsifiable in a
diff nobody re-reads) but a live guard:
`Talaria/CarPlay/CarPlayVoiceManager.swift` must still contain
`titleVariants: ["Talk to Hermes"]`. If a future sweep takes that line
before #74 makes CarPlay verifiable, this goes red and the deferral is
re-decided deliberately rather than by accident. The sibling host-meaning
CarPlay strings (`"Connecting to Hermes..."`, `"Hermes is speaking"`)
ride the same guard.

**415-S-4 — the four test-pinned host-meaning strings stay green.**
`HermesControlsTests.hostMeaningHermesStringsSurviveTheRename` is
UNCHANGED by this lane and must stay passing: `"Message Hermes…"`,
`"A Hermes gateway"`, `"Something's there, but it isn't Hermes"`,
`"Hermes host online"`. Talaria is a client for a **Hermes** host; that
word is load-bearing everywhere it means the host.

**415-S-5 — the identity does NOT move.** The Swift type
`AskHermesIntent` keeps its name (ruled out of scope) — and per the
measurement below that name IS the registration key, so a type rename is
the Shortcuts-surface equivalent of 415-N-3's control `kind` hazard.

**415-S-6 — the gate.** `scripts/mac/lane-gate.sh` green on `CC-lane-2`
under Xcode-beta6. Baseline to beat, verified at lane open: **2729** Swift
Testing tests; the delta must equal the tests this lane adds and nothing
else.

**Explicitly OUT of scope** (enumerated before the edit, per 415-N's
precedent, so the close-out cannot quietly grow): `CarPlayVoiceManager`'s
`titleVariants` (declined-for-now, guarded by 415-S-3), the TYPE name
`AskHermesIntent` (internal, and load-bearing per 415-S-5), and every
host-meaning "Hermes" string in the app.

**✅ 2026-08-26 — 415-S DONE.** Every bar met. **The strings, verbatim,
before → after:**

| surface | file | before | after |
| --- | --- | --- | --- |
| `AskHermesIntent.title` | `Talaria/Intents/AskHermesIntent.swift:26` | `Ask Hermes` | `Ask Talaria` |
| `TalariaAppShortcuts` `shortTitle` | `Talaria/Intents/StartVoiceSessionIntent.swift:61` | `Ask Hermes` | `Ask Talaria` |

Two sites, both ruled. One adjacent comment naming the old title was
corrected in the same commit (close-out rule).

**🔎 THE RE-REGISTRATION QUESTION, ANSWERED BY MEASUREMENT rather than
recall — and the answer is "nothing to do", for a reason worth keeping.**
App Shortcuts metadata is extracted at **BUILD** time into
`Metadata.appintents/extract.actionsdata` inside the `.app` bundle. Read
out of a real build product:

```
actions.AskHermesIntent.identifier        = "AskHermesIntent"
actions.AskHermesIntent.mangledTypeName   = "7Talaria15AskHermesIntentV"
actions.AskHermesIntent.fullyQualifiedTypeName = "Talaria.AskHermesIntent"
autoShortcuts[].actionIdentifier          = "AskHermesIntent"
autoShortcuts[].shortTitle.key            = "Ask Hermes"   ← pre-rename build
```

Three consequences:
1. **No runtime call is needed.** The titles ship inside the binary's
   extracted metadata and the system re-reads them on install.
   `AppShortcutsProvider.updateAppShortcutParameters()` exists, but it
   refreshes **dynamic parameter option values** (AppEnum/AppEntity) —
   and this shortcut has no `parameterPresentation` at all, with phrases
   built only from `\(.applicationName)`. There is nothing for it to
   update, so calling it would be cargo cult.
2. **Nothing orphans.** Registration keys off the TYPE
   (`identifier` / `mangledTypeName`), never the display title, so
   shortcuts a user has already built and any Siri bindings survive a
   title change untouched. This is the same identity-vs-display split
   415-N-3 pinned for the control `kind` — and it is why 415-S-5 forbids
   renaming the type even though the type name is invisible.
3. **The title is a bare localization KEY**, and this project ships no
   `.xcstrings` / `.strings` catalog (checked), so the key *is* the
   displayed string. No catalog entry is owed.
   ⚠️ Not measured here: whether the Shortcuts app's own cache redraws
   immediately on upgrade-install or only after a relaunch. That is
   device-observable only and this lane is sim-bound; if a stale title
   shows after the next OTA, relaunch before suspecting the code.

**🚩 FLAGGED FOR OWEN — a THIRD "Ask Hermes" on this same surface that
nobody has enumerated, found in the metadata above and deliberately NOT
changed.** `AskHermesIntent.parameterSummary` is
`Summary("Ask Hermes \(\.$question)")`, and the extractor bakes it as
`formatString: "Ask Hermes ${question}"` — the row the Shortcuts **editor**
draws for a configured action, while `title` is what the action
*browser* lists. So after this lane the browser says "Ask Talaria" and a
placed action still reads "Ask Hermes <question>". It was not in Owen's
"shortcuts only" enumeration and not in 415-N's flag list, so renaming it
would be the lane growing itself — but it is one line if elected, and
this note is the standing record. *(Two further Hermes mentions in that
file are host-meaning and correct as they stand: the intent
`description` — "Asks Hermes a question…" — and the parameter's
`requestValueDialog` — "What should I ask Hermes?" — both name the agent
being asked, not the app doing the asking.)*

**Test evidence.** `AskHermesIntentTests` 11 → **14 tests, +3**
(`askIntentTitleNamesTalaria`, `theAppShortcutSpellsTalaria`,
`carPlayIdleTitleIsUntouched`). **RED-first at HEAD, measured before the
edit: 3 issues across 2 failing tests** — the compiled title, the
`shortTitle` presence, and the old-literal absence — with 415-S-3's
CarPlay guard already green, as it must be: it is a guard, not a goal.
After the rename, `AskHermesIntentTests` + `HermesControlsTests` run
together: **25/25 pass in 2 suites**, which also re-proves 415-N's eleven
pins and 415-S-4's four host-meaning strings across the edit.

**415-S-6, the gate** — `TALARIA_SIM_NAME=CC-lane-2` under Xcode-beta6,
**GATE: PASS on 24A5423a**, first run, no flake re-runs: **2732 Swift
Testing** + **15 XCUITest** + Release build clean (0 Swift compile
errors), preflight all-PASS including the TCC grant, the classifier
self-test (15 checks) and the `project.pbxproj` drift check. **The count
MOVED 2729 → 2732, exactly +3** — this lane's three tests and nothing
else, which is the check a stale `.xctest` would have failed. No
`xcodegen` regen was owed: no Swift file was added or removed, and the
pbxproj drift check confirms it. Baseline provenance: 2729 is 415-N's own
measured gate count from earlier the same day, and `origin/main` was still
at that lane's commit when this one branched (the parallel 415 fix lane
had not landed).


> **⚖️ STANDING NAMING RULING 2026-08-27 (Owen, verbatim: "Rename it,
> and standing authority to rename any other finds. If it says Hermes
> outward on the phone, replace it with Talaria. With the exception
> being the in app connection to Hermes."):** the parameterSummary
> rename is elected, AND the rule is standing — the app's outward
> identity is TALARIA on every phone-facing surface; "Hermes" survives
> only where it means THE HOST/CONNECTION (Connect Host, gateway
> errors, host status, the composer's host-channel identity). Fences
> that OUTRANK the standing rule because they are their own rulings:
> the `hermes://` easter-egg scheme (#77), CarPlay's deferred-with-
> trigger rename (this entry), type names / control `kind` ids /
> intent identifiers (orphaning hazards, test-pinned). One SWEEP lane
> dispatched to apply the rule wholesale rather than string-by-string;
> borderline judgments enumerated in its close-out. Also recorded in
> CLAUDE.md's Conventions.

### 415-SWEEP — the STANDING RULING applied WHOLESALE. **Bars written first, 2026-08-27, before any edit.**

The two prior naming lanes were string-by-string (415-N: two control
titles; 415-S: two Shortcuts strings). This one inventories **every**
user-visible "Hermes" across the app + widget + intents targets and rules
on each. The judgment axis is Owen's: **APP-MEANING** (the assistant/app
surface the user talks to — the local brain answers hostless, so these are
Talaria) vs **HOST-MEANING** (names the host, the gateway, the connection,
or where a message goes when a host is attached — these stay Hermes).

**415-SWEEP-1 — the elected string is pinned.**
`AskHermesIntent.parameterSummary` must compile to `Ask Talaria` and must
NOT contain `Ask Hermes`. This is the straggler 415-S flagged for Owen and
the reason the ruling was issued. A test asserts the rendered
`formatString`, not the source text.

**415-SWEEP-2 — the inventory is ENUMERATED, with zero silent decisions.**
The close-out carries three lists — RENAMED (with before → after), KEPT AS
HOST-MEANING, and FENCED — and every borderline call states its reasoning.
A string that changed without appearing in a list, or a judgment asserted
without a reason, fails this bar. Scope of the sweep: string LITERALS the
user can see (UI text, intent titles/descriptions/dialogs, VoiceOver
labels, notification/Live-Activity copy, widget gallery names, **and the
`Info.plist` permission usage descriptions**, which iOS renders in system
prompts and which no prior lane inventoried).

**415-SWEEP-3 — the host-meaning pins stay green.**
`HermesControlsTests.hostMeaningHermesStringsSurviveTheRename` is
UNCHANGED and must keep passing: `"Message Hermes…"`, `"A Hermes
gateway"`, `"Something's there, but it isn't Hermes"`, `"Hermes host
online"`. Talaria is a client for a **Hermes** host; that word is
load-bearing everywhere it means the host. New pins are added for the
host-meaning families this sweep deliberately walked past (the service
error strings, the Connect Host copy, the brain label).

**415-SWEEP-4 — the fences are shown STRUCTURALLY, not asserted.**
Untouched, each proven by a test that reads the file or the compiled
value: the `hermes://` easter-egg scheme (#77's ruling), every
`CarPlayVoiceManager` `titleVariants` entry (415-S-3's guard, still a
guard and not a goal), the control `kind` ids (415-N-3), the widget
`kind` ids (`HermesStatus`/`HermesHealth`/`HermesBriefing` — same
orphaning hazard as a control kind), the Swift type names (415-S-5), and
the `Logger` subsystem/category strings. **A rename that also moved an
identifier would pass 415-SWEEP-1 and still be a regression.**

**415-SWEEP-5 — no user-visible regression from the placeholder rename.**
`Conversation.defaultTitle` is user-visible (the drawer's title before
on-device titling fires) AND load-bearing in logic — `#4.8` title
generation only runs while `title == defaultTitle`. Renaming the constant
alone would strand every conversation created before this build: it would
display the OLD name forever and never auto-title, i.e. the sweep would
manufacture the exact symptom it exists to remove. A tolerant
placeholder check must accept both the new and the legacy value, and a
test must fail if it does not.

**415-SWEEP-6 — the gate.** `scripts/mac/lane-gate.sh` green on
`CC-lane-2` under Xcode-beta6. Baseline to beat, verified at lane open:
**2732** Swift Testing tests (415-S's own measured count); the delta must
equal the tests this lane adds and nothing else.

**Explicitly OUT of scope**, enumerated before the edit so the close-out
cannot quietly grow: the `hermes://` scheme and its comment, all of
CarPlay, every identifier (type names, control/widget `kind`s, intent
identifiers, bundle ids, subsystem strings), log lines, and code comments
except where a rename in this lane FALSIFIES one (those are corrected in
the same commit, per the close-out rule). `README`/`docs/` are verified
for app-meaning misses but are expected to need nothing after #77.

**✅ 2026-08-27 — 415-SWEEP DONE.** The standing ruling applied wholesale in one
pass. **74 string replacements across 37 files**, every one classified before it
was touched. The inventory method, stated so the enumeration below can be
checked rather than trusted: every `"…"` literal containing `Hermes` across
`Talaria/`, `Shared/`, `TalariaWidgets/`, `TalariaShare/` — **212 at lane
open** — plus the `Info.plist` permission descriptions, which no prior naming
lane had inventoried at all.

**★ The elected string, before → after:**

| surface | file | before | after |
| --- | --- | --- | --- |
| `AskHermesIntent.parameterSummary` | `Talaria/Intents/AskHermesIntent.swift:54` | `Summary("Ask Hermes \(\.$question)")` | `Summary("Ask Talaria \(\.$question)")` |

That is the row the Shortcuts EDITOR renders. It is pinned against the
**compiled** summary, not the source line — see the instrument note below.

#### LIST 1 — RENAMED (APP-MEANING). 74 sites.

**Shortcuts / Siri surface** — `AskHermesIntent`'s own doc already recorded the
governing fact ("The Shortcuts/Siri surface names the APP", 415-S), and this
intent reaches the **on-device brain whenever the Sessions-API key is unset**
(`needsReachabilityPreflight`), so the host was never the right subject:
`IntentDescription` "Asks **Hermes** a question…" → Talaria · parameter
`description:` "What to ask **Hermes**." → Talaria · `requestValueDialog`
"What should I ask **Hermes**?" → Talaria · `stillWorkingDialog` "**Hermes** is
still working on it. Open Talaria to watch it finish." → "**Talaria** is still
working on it. Open **the app** to watch it finish." · `.busy` error, same
shape · `AskHermesLongRunSupport` progress "Hermes is thinking" → Talaria ·
`StartVoiceSessionIntent` "…hands-free voice session with **Hermes**." → clause
dropped (see B1).

**Spotlight / App Entities** (`SpotlightEntities`, `SpotlightIndexingService`,
`PrivacySettingsScreen`): `"Hermes Session"` ×3 → `"Talaria Session"` ·
`"Hermes session"` · `"Hermes File"` · `"File from Hermes"` →
`"File from Talaria"` · `"Open Hermes Session"` · `"Open Hermes File"` ·
`"Opens a Hermes chat session in Talaria."` → `"Opens a Talaria chat session."` ·
the Spotlight toggle caption "Makes **Hermes** sessions and agent files
findable…".

**Assistant persona / transcript role labels**: `HermesAvatar` VoiceOver label ·
`MessageBubble` `"Hermes: \(content)"` · `ConversationSearchScreen` match label ·
`ThinkingIndicatorView` "Hermes Is Reasoning" ·
`TranscriptSpeaker.hermes.displayLabel` · `ChatScreen`'s conversation-history
dump role · and the four transcript role labels fed back to the model
(`LocalChatBackend`, `ContextTransplanter`, `ChatStore.voiceTranscriptTurnText`,
`DeviceMediaTools`).

**The two local-brain SYSTEM PROMPTS** (`LocalChatBackend:2573`, `:2583`) —
*"You are **Hermes**, the user's personal assistant, running entirely on their
iPhone…"* / *"…running on Apple's Private Cloud Compute…"* → **Talaria**. Not a
UI string, and arguably the most outward one in the app: it decides what the
assistant answers when the user asks it its own name, on the two tiers that
never touch a host at all.

**Voice HUD status** (`LiveVoiceSessionService`, `NativeVoicePipelineService`,
`MockVoiceSessionService` in lockstep): "Hermes is thinking." ×4 · "Hermes is
speaking." ×3 · "Hermes is working on that…" ×2 · "Hermes has the answer…" ·
"A tool call failed — Hermes will try another way." · "Hermes is waiting on a
host approval…" (see B2). Plus `SpeechOutputService`'s spoken voice preview,
"This is how **Hermes** replies will sound."

**Live Activity / widgets / alarms**: `HermesActivityAttributes.agentName`
default in **both** copies (app + widget target, per the `HermesWidgetData`
lockstep convention) · both `LiveActivityService` call sites ·
`LiveActivityPreviews` ×2 (see B7) · `AlarmService`'s default alarm title
`"Hermes \(kindNoun)"` · `"Hermes Timer"` · and the widget GALLERY names
`.configurationDisplayName("Hermes Health"/"Hermes Status")`, plus
`HermesStatusWidget`'s in-widget wordmark ×2 and its sender attribution.

**Permission copy — the surface no prior lane inventoried.** 13 `Info.plist`
usage descriptions (edited in `project.yml`; `Talaria/Resources/Info.plist` is
xcodegen-generated from it and regenerated in the same commit), their four
in-app twins in `PermissionType`/`PermissionsScreen`, and `DeviceCalendarTools`'
grant-widening instruction. **iOS renders these verbatim in its own system
alerts, above an app the user installed as Talaria** — and the calendar one
actively misdirected, sending the user to Settings → Privacy to find a row
labelled Talaria.

**Misc**: `CaptureScreen`'s coming-soon caption · `DemoData`'s sample
conversation title · **README/docs**, 6 lines (see the premise correction
below) · and `Conversation.defaultTitle` (see 415-SWEEP-5, the half that
mattered).

#### LIST 2 — KEPT, HOST-MEANING. Deliberate, not missed.

~100 literals, in families: every service error string
(`SessionsHermesClient`, `CronJobService`, `InsightsService`, `SkillsService`,
`GatewayHermesHostService`, `HostReachability`, the three `…Store` error
mappers) — "The Hermes host rejected this device's API key.", "Hermes API base
URL is not set.", "The Hermes run failed." · the whole `ConnectHostCopy`
wizard · the chat header's five host-status lines · the composer pair
`"Message Hermes…"` / `"Reply to Hermes"` (B6) ·
`ChatBackendRouter.Brain.hermes.displayLabel` = `"Hermes"` and `monoLabel`
`"HERMES"` · `"Hermes Host"` / `"My Hermes"` / `"Hermes host"` ·
`"Sessions stored on the Hermes host"` · `"Hermes host pairing"` ·
`"Share Sensors with Hermes"` + `"Lets your Hermes agent ask this phone…"`
(B5) · `"Send Transcripts to Hermes"` · `"Connect Hermes Desktop"` ·
`"Update Hermes Agent"` · `"Sending to Hermes"` ·
`"Hermes when reachable, on-device otherwise"` ·
`"The latest briefing from Hermes."` and the platform-inbox row title
`"Hermes"` (both are pushed BY the host plugin) · the pair-QR instructions ·
`"Mock Hermes Host"` · and the three `AskHermesIntent` dialogs that fire only
on host paths — `"I couldn't reach Hermes."` (the #56 reachability preflight),
`"Hermes is unreachable right now. Your question is queued…"`, and
`"Hermes accepted the question and is still working."` (a run committed
server-side).

#### LIST 3 — FENCED. Untouched, each shown structurally by a test.

`hermes` URL scheme + its easter-egg registration (#77's own ruling) · every
`CarPlayVoiceManager` `titleVariants` entry, incl. its host-meaning siblings
(415-S-3's guard — still a guard, not a goal) · control `kind` ids (415-N-3) ·
**widget `kind` ids** `HermesStatus`/`HermesHealth`/`HermesBriefing` (same
orphaning hazard as a control kind — newly pinned this lane) · all Swift type
names incl. `AskHermesIntent` and its `mangledTypeName` (415-S-5) · `Logger`
subsystem/category strings · log lines (`probe: … not a Hermes catalog`, the
`#293b` reconcile line, the `#192` fallback notice) · the `O:\Hermes\…`
demo/host paths · tracker and doc history.

#### Borderline judgments — stated with reasoning, not decided silently

- **B1 — dropped clauses, not mechanical swaps.** A literal rename of
  `StartVoiceSessionIntent` gives "Opens **Talaria** and starts a hands-free
  voice session with **Talaria**." The clause was dropped instead; likewise
  `stillWorkingDialog`/`.busy`, where "Open Talaria" became "Open the app".
  Three places where a pure find-and-replace would have introduced a copy
  defect.
- **B2 — `"Hermes is waiting on a host approval…"` → Talaria.** For keeping:
  the run genuinely is paused on the HOST. What won: this is the voice HUD's
  `statusMessage`, alternating with "Talaria is thinking."/"Talaria is
  speaking." in the same label — a HUD that switches persona mid-sentence is
  incoherent — and the host is still named explicitly in the same sentence
  ("a **host** approval"). Its chat-plane sibling in
  `SessionsHermesClient+RunsTransport` ("The **Hermes host** paused this run…")
  names the host as SUBJECT and correctly stays.
- **B3 — `"Hermes talk is ready."` KEPT.** Same file as the renamed HUD lines,
  opposite verdict: it is the host's `talk_readiness` probe result, and its
  neighbours ("Could not reach the Hermes host.", "This Hermes host doesn't
  support voice yet…") are unambiguously connection status. The split inside
  one file is the point — assistant persona renames, connection status does
  not.
- **B4 — the Spotlight entity family → Talaria**, although the ids behind it
  are Sessions-API (host) ids. These are system-surface labels for the app's
  own content, and `OpenSessionIntent.title` renders in the **Shortcuts
  editor** — the exact surface 415-S ruled names the app. The host provenance
  is an implementation detail the user never sees.
- **B5 — `"Share Sensors with Hermes"` KEPT** despite sitting in Talaria's own
  Privacy screen: the thing being granted is *your host agent's* ability to
  query this phone, and the toggle's own caption says so. Same reasoning kept
  `"Send Transcripts to Hermes"`.
- **B6 — the composer pair KEPT.** `"Message Hermes…"` is named in Owen's
  ruling text itself; `"Reply to Hermes"` is that same field's VoiceOver
  label, so it follows the field rather than being judged separately.
- **B7 — `LiveActivityPreviews` renamed although `#Preview`-only** and
  therefore not user-visible: it mirrors the Live Activity whose `agentName`
  this lane renamed, so leaving it would have falsified it (close-out rule).

#### 🟡 A PREMISE OF THE DISPATCH WAS WRONG, and checking it is what caught six misses

The dispatch said README/docs "already says Talaria where it should post-#77 …
likely none". **#77 was a URL-SCHEME lane, not a naming lane** — `git show
92363b56` edits README line 51 and leaves `ask Hermes` sitting in it. No
README/docs naming pass had ever run. Six app-meaning misses found and fixed:
the Siri phrase (the shipping intent has read "Ask Talaria" since #393, so the
README was advertising a phrase that no longer exists) and five share-extension
lines — the clearest case in the sweep, because `TalariaShare` **never touches
the network**: it queues an app-group envelope the app drains, and works with
no host paired at all. `docs/index.html`'s phone mockup keeps `Message Hermes…`
and its `HERMES` header, both correct: the first is enumerated in Owen's ruling,
the second depicts hosted mode, which `ChatScreen.headerWordmark` renders
exactly that way (#191).

#### 415-SWEEP-5 — the regression this lane had to design around rather than discover

`Conversation.defaultTitle` is user-visible **and** load-bearing: `#4.8` title
generation fires only while `title == defaultTitle`. Renaming the constant alone
would have stranded every conversation created before this build — displaying
"Hermes" forever *and* never becoming eligible for auto-titling again, because
the equality test stopped matching them. **A naming sweep that manufactures a
permanent "Hermes" in the sessions drawer has defeated itself.** Fixed with
`legacyDefaultTitle` + `isPlaceholderTitle(_:)`, and the four equality sites
(three in `ChatStore`, one in `LocalChatBackend.sessionInfo`) migrated to it.

#### 🟡 Two honest instrument corrections, made mid-lane

**(1) There is no `formatString` API.** 415-SWEEP-1 was written promising an
assertion on the "rendered `formatString`". `ParameterSummary` publishes nothing
but an `associatedtype`, and `ParameterSummaryString` exposes no accessor for
the format it was built from — checked in `AppIntents.swiftinterface` BEFORE
writing the test rather than after it failed. The bar was met by a
**depth-capped recursive `Mirror` walk over the compiled summary value**: still
the compiled artifact rather than the source text, which is what the bar was
protecting, but by reflection instead of a public accessor. The failure message
carries the whole reflected string list, so if AppIntents reshapes the type this
goes red with its evidence attached instead of asserting over an empty
collection.

**(2) The test was right where the author was wrong.**
`theHermesSchemeEasterEggIsUntouched` was first written against the literal
`"hermes://"` and went **RED** — that string is nowhere in the tree. The scheme
is registered as a bare `hermes` in `project.yml`'s `CFBundleURLTypes` and
matched by `DeeplinkRouter.registeredSchemes`. Both are now asserted, because
either alone is satisfiable while the feature is broken: a router accepting a
scheme iOS does not route is dead code, and a registration nothing handles is a
launch that lands nowhere.

**RED-first evidence.** Mutating the single elected string back to `Ask Hermes`
produced **3 failures across 2 tests** — both arms of the compiled-value pin
(presence AND absence) plus `oldAppMeaningLiteralsAreGone`. The instrument
discriminates; it is not asserting over an empty set.

---

### 🎯 FIX BARS 415-A … 415-D — pre-registered 2026-08-26 night (fix lane), BEFORE any code. Adapted from the forensics' proposals above; the differences are named where they exist.

**What the fix is, stated before it is built.** `TalkStore` gains a **cover
watch**: a re-evaluation of `AppLockGate` that outlives the single sample
`deferUntilUnlocked` takes at the instant of start. The gate is the seam —
`AppLockController.refreshCover()` is still its only writer, and the watch
reads it through a **mirror of the suspension point the park already uses**
(`waitUntilLocked()` beside `waitUntilUnlocked()`), not through a second
observer, a notification, or a poll. **No new mechanism, no new writer, no
new state machine** — that is the #323-class discipline applied to the fix
for #302's own recurrence.

**The park semantics are #302's, extended — not invented.** A session that
becomes covered mid-flight is treated exactly as a start that arrived one
second later would have been: **capture STOPS immediately** (the existing
teardown, `voiceService.endSession()` + snapshot — the same body
`discardAbandonedStart()` runs), the store **parks** on the same
`isWaitingForUnlock` + `lockedWaitingMessage` state a pre-start lock
produces, and on unlock it **resumes exactly once through the door the
session came from** — or, if the start was abandoned/revoked while parked,
it never resumes at all (302-F's rule, extended to the new door).

Two consequences recorded now rather than discovered later:
- **The stop is the BARE teardown, not `endSession()`.** The full path
  publishes `lastCompletedSession`, which `MainTabView` injects into the
  chat transcript — a transcript write behind the cover, which is
  precisely what **#323** forbids. So a covered session's turns are
  dropped rather than injected. In the ordering the forensics actually
  measured this costs nothing (the cover arms 0.27–2.4 s into a start that
  has no turns yet); in the defensive already-active ordering it trades
  data for the covered-interval rule, deliberately.
- **"Resume" means the store re-enters its start door, so the engine opens
  a NEW session.** The engine's own session was torn down; nothing
  pretends otherwise. Same shape a pre-start park produces.

- **415-A — THE LOCK ARMING MID-FLIGHT PARKS THE SESSION, AND THE CAPTURE
  CHAIN DOES NOT SURVIVE THE COVER.** Unit, and the only bar that
  discriminates this defect from #302's fixed one. **Must be witnessed RED
  on the unmodified tree before any fix lands — a bar that is green before
  the fix is measuring the wrong thing.** Three orderings, scored
  separately:
  - **A-1 STARTING** (the measured ordering): gate UNLOCKED, drive
    `startSessionDirectly()`; while the fake voice service is suspended
    inside `startSession()`, flip `gate.setLocked(true)`. Assert the
    capture chain does not stay up — the fake records the start and then an
    **immediate stop**, `isSessionActive == false` — and that the store is
    **parked** (`isWaitingForUnlock`, `statusMessage ==
    lockedWaitingMessage`). Then `setLocked(false)` ⇒ it resumes
    **exactly once** and stops claiming to wait.
  - **A-2 ACTIVE** (the defensive ordering): a completed start, live
    session, then `setLocked(true)` ⇒ stopped and parked; unlock ⇒ resumed
    exactly once. Scored separately from A-1 because a fix that only
    re-checks after `startSession()` returns closes the measured half and
    leaves this one open.
  - **A-3 ABANDONED WHILE PARKED**: cover arms mid-flight, then
    `abandonSession()`, then unlock ⇒ **no resume, ever**. #139's defect
    arriving through the new door — a naive park-and-resume opens a
    microphone for nobody, which is the whole reason 302-F exists.
  - Both start doors are covered (A-1 through `startSessionDirectly()`,
    A-2 through `startSession()`), per 302-E's two-door rule.
  - **Mutations:** delete the mid-flight re-check ⇒ A-1/A-2/A-3 RED;
    park WITHOUT stopping capture ⇒ the capture-stopped assertions RED
    while the parked-state ones stay green (that is the isolating pair —
    a park that leaves the mic hot is the defect wearing the fix's
    clothes); drop the post-unlock generation re-check ⇒ **A-3 alone** RED.
- **415-B — the negative control that keeps 415-A honest** (mirror of
  302-G). **App Lock OFF is a NO-OP on the mid-flight path:** driven
  through a real `AppLockController` with `isEnabled: false`
  (background → active, the transition that arms the lock when it is on),
  the gate never locks, a started session is **never stopped**, **never
  parks**, and starts **exactly once**; a store with **no gate wired** is
  unchanged too. **Without this, 415-A is satisfied by a build that never
  starts voice, or by one that parks every session forever** — the
  availability defect traded for the privacy one. Its bar is to stay
  **GREEN under every mutation**.
- **415-C — the realtime engine grows the `#302-A` instrument, and the
  park announces itself.** `LiveVoiceSessionService` emits the same three
  always-on `.notice` lines `NativeVoicePipelineService` has — *audio
  session activated for capture*, *capture chain HOT*, *capture chain
  COLD* — at its own equivalent seams, carrying the same `(#302-A)`
  marker, `privacy: .public`, and **never behind Verbose Logging**, so one
  Console predicate reads BOTH engines forever after. `TalkStore` gains a
  `.notice` line for the mid-flight park/resume itself, so 415-D can be
  scored from the app's own log instead of framework CoreAudio rows a
  later `log collect` may not retain (the fallback this forensics was
  forced into). Pinned by a **source read** over both files — the
  `SpeakerRouteOverrideTests` pattern, in the same file it already pins.
  **Mutation:** delete any one instrument line ⇒ RED.
- **415-D — device, and it must HOLD THE COVER OPEN.** Warm process:
  background the app, tap Control Center → **Talk to Talaria**, **cancel
  Face ID and hold the locked cover ≥30 s**. Score from a same-day
  archive: no `capture chain HOT` and no `Starting AURemoteIO` may appear
  while any `cover=locked` is in effect; the park line must appear
  instead; after unlock, capture may go hot. Then the cell run 3 never
  tested: **cold launch, tap the control, and UNLOCK** — the parked start
  must resume rather than being the accident that made the force-quit run
  look clean. Owen's card ships with this lane's result block; the bar is
  **not scorable by this lane** and stays open until he runs it.

**Pre-registered response.** 415-A green with its mutations isolating and
415-B green throughout ⇒ the mid-flight ordering is closed and #302's
supersession is answered. **415-A red ⇒ the fix is not built, whatever the
other bars say.** 415-B red is the most informative failure available
here — it means the app now defers or tears down voice with App Lock
switched OFF, which is worse than the defect being fixed. 415-C is not
scorable by unit assertion (an `os_log` line has no return value); its pin
is structural and says so.

**Instrument discipline for this lane's own counting:** baseline is
**2729 Swift Testing + 15 XCUITest** (415-N's gate, same day) and the
delta must equal the tests this lane adds and nothing else.

### ✅ RESULT 2026-08-26 night — THE MID-FLIGHT ORDERING IS CLOSED. 415-A and 415-B MET, each mutation-isolated; 415-C SHIPPED on both engines and pinned; 415-D is Owen's and stays open.

**415-A was witnessed RED on the unmodified tree first, as its own proposal
demanded: 8 tests, 21 issues** (`-only-testing:TalariaTests/AppLockMidFlightCoverTests`,
CC-lane-3, Xcode-beta6, sim runtime 24A5423a). The distribution was the
predicted one and is recorded because it is the finding's regression pin:
A-1 7 issues, A-2 6, A-3's park half 2, 415-C 4 + 2. **The three green-at-HEAD
tests were green BY CONSTRUCTION and said so in their own doc comments before
the run** — HEAD has no resume to suppress, no watch to leak, and 415-B is a
negative control.

**What shipped.** `TalkStore` gains a **cover watch**: one task per session,
armed **before** the engine call (the window the device evidence lives in —
the mic went hot 272 ms and 2.4 s *after* `locked=true`, inside that await),
cancelled with the session. It waits on **`AppLockGate.waitUntilLocked()`**,
a mirror of `waitUntilUnlocked()` added beside it. Three files:
`Talaria/Services/Support/AppLockGate.swift`, `Talaria/Stores/TalkStore.swift`,
`Talaria/Services/Live/LiveVoiceSessionService.swift`.

**The subscription seam, and why it is not a new one.** The gate already IS
the app-wide App-Lock observation point — `AppLockController.refreshCover()`
is its only writer and `TalkStore`/`ChatStore`/`ToolConfirmationCenter` are
its readers. So the mid-flight re-check rides the same state through the same
kind of suspension point, rather than a second observer, a
`NotificationCenter` name, or a poll. **`parkedWaiterCount` deliberately still
counts UNLOCK waiters only** — 302-E's park and 302-G's `== 0` control are
written against that number, and a cover watch armed on an unlocked app would
silently change both answers. Cover watches are counted separately
(`armedCoverWatchCount`).

**The park semantics, chosen against #302's contract rather than invented.**
302-C ruled the contract *defer-until-unlock*, and `deferUntilUnlocked` is its
implementation: park, publish `isWaitingForUnlock` + `lockedWaitingMessage`,
re-read the generation after the wait, resume or decline. A session covered
mid-flight now gets **the same four steps**, in this order:
1. **STOP first.** Capture ends through the existing teardown —
   `discardAbandonedStart()`'s body — and **not** `endSession()`. That is a
   decision, not an oversight: `endSession()` publishes
   `lastCompletedSession`, which `MainTabView` injects into the chat
   transcript, and a transcript write behind the cover is exactly what **#323**
   forbids (*"the transcript kept it"* IS the reported defect there). A
   covered session's turns are dropped instead. In the measured ordering this
   costs nothing — the cover arms 0.27–2.4 s into a start with no turns yet.
2. **Revoke like #139.** The generation is bumped, so a start still inside
   `voiceService.startSession()` cannot land live when it returns; the door's
   own re-check routes it into `discardAbandonedStart()`. Both orderings —
   STARTING and ACTIVE — therefore end identically.
3. **Park**, on the same two published fields a pre-start park uses, and
   holding `isStartingSession` for the parked interval so **#254**'s
   background revoke still sees an outstanding start. (The doors' `defer` no
   longer clears a flag the park owns — one line, and it is the only change
   to the pre-existing start path.)
4. **Resume exactly once on unlock, through the door the session came from**
   — or never, if it was abandoned while parked (302-F's rule through the new
   door). The resume runs in a **fresh task**, because the resumed start
   cancels this watch and a start running inside a cancelled task would fail
   its first network call.

| bar | verdict | what proved it |
|---|---|---|
| **415-A-1** cover arms mid-START ⇒ stopped, parked, resumed once | ✅ MET | RED at HEAD (7 issues); M2 ⇒ RED |
| **415-A-2** cover arms over a LIVE session ⇒ same | ✅ MET | RED at HEAD (6 issues); M2 ⇒ RED |
| **415-A-3** abandoned while parked ⇒ never resumes | ✅ MET | park half RED at HEAD (2 issues); M3 ⇒ its sibling arm RED |
| **415-A** hygiene: the watch dies with its session | ✅ MET | `armedCoverWatchCount` 1 → 0; green at HEAD by construction |
| **415-B** App Lock OFF / no gate wired ⇒ no-op | ✅ MET | green under every mutation — which is its bar |
| **415-C** both engines carry the `#302-A` instrument | ✅ MET | RED at HEAD (4+2 issues); M4 ⇒ RED |
| **415-D** device, cover held open ≥30 s | ⬜ OPEN | Owen's; card below |

**The three isolating mutations, each run as its own build:**
- **M2 — park WITHOUT stopping capture** (delete the teardown call): **5
  issues, every one a capture assertion** (`!voice.isCapturing`,
  `endCallCount >= 1`); the parked-state assertions and the resume assertion
  stayed **green**. That is the registered isolating pair, measured: a park
  that leaves the mic hot is this defect wearing the fix's clothes, and the
  bar can tell them apart.
- **M3 — drop the post-unlock generation re-check**: **exactly one test, one
  issue** — `aParkedSessionSupersededWithoutCancellationNeverResumes`.
  🟡 **And finding that arm took a second look, which is worth recording.**
  The obvious dismissal path (`abandonSession()`) revokes through
  `endSession()`, which ALSO cancels the watch — two belts, so the mutation
  would have shown nothing there. `endSessionIfNeeded()` is the honest
  isolator: while parked the session is not active, so it bumps the
  generation and returns without ending anything and without touching the
  watch, leaving the post-unlock re-read as the only thing between it and a
  microphone opened for nobody.
- **M4 — delete the realtime `capture chain HOT` line**: RED, isolated.
  🟡 **Its first run exposed a weak pin and it was tightened before the
  close.** The mutation comment I left behind quoted the phrase, so
  `source.contains("capture chain HOT")` stayed **green** and only the marker
  count went red — 415-N's own lesson from the same week, in a different
  file. Every phrase is now matched **with its opening quote**, so only a
  string literal satisfies it; the clean re-run reds both expectations.
- **M1 — the whole mechanism absent** is the RED witness above, and is
  labelled as such rather than re-run: deleting the cover watch from the
  fixed tree reproduces exactly the state HEAD was in.

**The instrument lines, verbatim** (all `.notice`, all `privacy: .public`,
none behind Verbose Logging — one Console predicate now reads both engines):
```
LiveVoiceSessionService  (NEW, #415)          NativeVoicePipelineService (existing)
  audio session activated for capture (#302-A)        audio session activated for capture (#302-A)
  capture chain HOT — RTCAudioTrack.isEnabled=<b>     capture chain HOT — AVAudioEngine.isRunning=<b>
      peerConnection=<state> (#302-A)                     inputTap=installed (#302-A)
  capture chain COLD — was=<b>                       capture chain COLD — AVAudioEngine.isRunning
      audioTrack=released session=deactivated (#302-A)    was=<b> now=<b> inputTap=removed (#302-A)

TalkStore (NEW, #415 — so 415-D scores from the APP's log, not CoreAudio's)
  voice session parked — App Lock cover armed mid-flight (#415)
  parked voice session NOT resumed — abandoned under the cover (#415)
  parked voice session resuming after unlock (#415)
```
The realtime HOT line reads the **transport's own state** (track enabled,
peer connection state) for the same reason the native one reads
`AVAudioEngine.isRunning` and not a wrapper flag: the wrapper is the thing
under suspicion. Subsystems differ by file and that is pre-existing — the
engines log under `org.aethyrion.talaria`, `TalkStore` under
`TalariaLog.subsystem`; the forensics' own predicate
(`subsystem BEGINSWITH "org.aethyrion"`) catches both.

**THE GATE — `TALARIA_SIM_NAME=CC-lane-3`, Xcode-beta6.** Five runs across
three successive bases as two other 415 lanes landed underneath this one.
**`GATE: PASS on 24A5423a` on the pre-sweep tree** (415-S + the naming
ruling merged): 2742 Swift Testing, **15/15 XCUITest**, Release clean. On the
FINAL tree (the naming sweep merged): **2752 Swift Testing** — 2742 → 2752,
**exactly +10**, the ten tests this lane adds and nothing else, which is the
check `test-without-building` staleness would have failed — **Release build
clean, preflight all-PASS**, and one XCUITest red that **`main` itself
carries tonight** (measured, below). The 2 skips are the known-permanent
`CondenserFidelityTests` pair; nothing new was skipped. **Runtime caveat the
gate prints itself (398-C): green on sim runtime 24A5423a**, which is why
415-D exists.

**🔴 THE XCUITEST RED IS `main`'s, AND THAT IS A MEASUREMENT — THE CONTROL
RAN INSTEAD OF THE ARGUMENT.** Three of this lane's five gate runs ended
`GATE: FAIL (3 checks)` on one test:
`TalariaUITests.testConnectedRelaunchSkipsTheConnectEntry` at
`AppTemplateUITests.swift:538`, *"a successful connect should land straight in
chat (#137)"* — Swift Testing and Release green in every one. **A structural
alibi was available and was deliberately not used** (this diff touches voice
start, the gate's waiter sets and two log lines; the Connect Host wizard runs
none of it), because the standing lesson is that such an argument is exactly
what a real order-dependence hides behind. So two controls ran, in order:

| arm (same box, same simulator) | result | that test |
|---|---|---|
| `origin/main` `dfd8f69b`, `-only-testing:TalariaUITests` | **15/15** | **37.983 s** |
| this branch, `-only-testing:TalariaUITests` | **15/15** | **37.731 s** |
| **`origin/main` `60a874dd`, FULL `lane-gate.sh`, no lane changes** | **`GATE: FAIL (3)` — same test, same line** | — |

**The last row is decisive: unmodified `main` fails this test in a full-suite
gate run on this box tonight**, with 2742 Swift Testing green and Release
clean — the exact red this lane was carrying. And in the isolated arms the
branch is **0.25 s FASTER** than base on the very test that fails, so the
diff does not even move its margin. **Tally across two trees on one night:
~4 fails in 10 full-suite runs, 0 in every isolated bundle run** — the
isolation-passes/suite-fails shape #300's note refused to call a flake, now
with a base measurement behind it. **#300's "`main` IS green on XCUITest"
(2026-08-26 morning) is superseded in its own home, dated, by this
measurement.** *(The gate's "XCUITest tests run — 2" line on a red run is its
documented MAX-over-`with 0 failures`-lines quirk when a run HAS a failure,
not a truncated bundle — corrected once already in #300's entry, and it read
exactly the same way here.)*

**🟡 A second infrastructure note, same night.** Twice, a targeted
`xcodebuild … test` after a source-change rebuild stalled ~6 minutes and
ended *"The test runner hung before establishing connection."* No test-host
process existed at all, so nothing in the diff was implicated; a
`simctl shutdown` + `boot` of the lane's simulator cleared it both times and
the same build then ran green. Recycling the sim before a post-rebuild run is
the cheap prophylactic.

**🟡 One more instrument fact found in passing.**
`-only-testing:TalariaTests/AppLockTests` matches **zero tests** and passes
silently — that file's suites are named `AppLockStateMachineTests`,
`AppLockGracePeriodTests` and `AppLockControllerTests`. A `-only-testing:`
name that matches nothing is a green run that measured nothing, which is the
`test-without-building` trap wearing a different coat.

### 📱 DEVICE CARD — 415-D (for the runbook; the only bar this lane cannot score)

**Setup:** App Lock **ON**, grace **Immediately**. Install the build, launch
it once, then **background it** (home swipe — do NOT force-quit; a cold
process is the degenerate control that made run 3 look clean).

1. **The warm Control Center repro, cover held open.** From the home screen
   open **Control Center → Talk to Talaria**. Watch the lock arm — Face ID
   will prompt: **cancel it, and leave the app sitting under the locked cover
   for at least 30 seconds.** ✅ PASS = **the mic indicator goes cold the
   moment the cover arms** and stays cold for the whole locked interval.
   ❌ FAIL = the orange dot stays lit, or you can talk to it.
2. **Then unlock** (tap UNLOCK, authenticate). ✅ PASS = the voice session
   comes back by itself, exactly once.
3. **The cell run 3 never tested — cold launch + unlock.** Force-quit the
   app, tap the Control Center control again, and this time **authenticate**
   instead of cancelling. ✅ PASS = the parked start resumes and voice
   connects; ❌ FAIL = nothing happens (the parked start was lost).
4. **Log evidence, same day** (`logd` evicts app rows in hours):
   `sudo log collect --device-udid <whoGoesThere UDID>`, then read
   `subsystem BEGINSWITH "org.aethyrion"`. **The bar:** no
   `capture chain HOT` and no `Starting AURemoteIO` may appear while any
   `cover=locked` is in effect, and
   `voice session parked — App Lock cover armed mid-flight (#415)` must
   appear at the arming instant. `parked voice session resuming after
   unlock (#415)` marks step 2.

## 419. 🐛 THE ASSISTANT-PLAYBACK ELAPSED COUNTER READS 0 EVERY TIME — and a real barge-in would send `conversation.item.truncate` with `audio_end_ms: 0`, deleting the ENTIRE heard portion from server-side history — **FILED 2026-08-30 from the #413 archive read. Every recorded reading of this instrument is 0 ms; the zeroing mechanism is deliberately NOT asserted (no log line can currently see it).** **⟵ HEADER CORRECTED 2026-09-01 (hygiene sweep): 419-A1/A2 (the naming instrument) SHIPPED, MERGED 2026-08-31 as `97e52d41` (PR #396) — every assistant `conversation.item.created`/`.added` arrival now logs the event/item relation and, if playback is live, the elapsed ms about to be destroyed. The zeroing MECHANISM is still not asserted; only the instrument that will name it is built.** **⟵ 2026-09-01: MECHANISM NAMED AND FIXED (419-B, PR #410, squash `02cad7bf`) — `finalizeAssistantText` on transcript-done, which runs ahead of playout; 419-A1's item path was never the cause (it cannot set `.listening`, and the fork archive had no arrival in the window). Awaiting only the next voice session's `audio.stopped after Nms` reading ≠ 0 as the device confirmation (rides #138's card V1).**

**The measurement:** `#138 audio.stopped after Nms` printed **0** on all three
stops in tonight's archive — against real playbacks of **2.16 s, 12.15 s and
3.77 s** by wall-clock (`audio.started`→`audio.stopped` timestamps) — and the
2026-08-22 fork archive's stop line also read `after 0ms`. **Every reading
this instrument has ever produced is 0.** It shipped 2026-08-22 (build 2957)
and nobody had read the value until tonight — the #416 family's shape again: a
signal that always says the same thing regardless of what it measures.

**The code read (`LiveVoiceSessionService.swift`):** the tracker itself is
sound — `start` stamps uptime (:884), `stop` BANKS elapsed before nil'ing
(:869, :659, and the stopped/cleared handlers), so a stop-path zero would
still print the banked value. **The only path that zeroes a RUNNING counter is
`resetAssistantAudioPlaybackTracking` (:865), whose in-session caller is the
`conversation.item.created`/`.added` (assistant role) handler.** So the
evidence points at an assistant item event arriving MID-playback — e.g. the
beta/GA event pair (`created` + `added`) double-firing for one item, or a
second assistant item landing while audio still drains — **but the mechanism
is UNDETERMINED: those events have no log line, and #138's rule applies (no
mechanism claim without a log line that would have to change if it were
false).**

**Why it matters beyond cosmetics — the consumer is TRUNCATION:**
`truncateAndCleanUpAssistantState` sends `conversation.item.truncate` with
`audio_end_ms: currentAssistantAudioPlaybackMilliseconds()` on every barge-in
(VAD and manual). With the counter dead at 0, a genuine barge-in tells the
server the user heard NONE of the utterance — server history drops the whole
thing, and the model no longer knows what it managed to say before being cut
off. Conversation-coherence defect, invisible until someone inspects a real
barge-in's aftermath. Second consumer: the `#138 BARGE-IN … Xs into playback`
line maps the same nil'd stamp to `"n/a"` — the instrument built for #138
under-reports at exactly its moment of use. (Barge-in DETECTION is unaffected:
the guard's `voiceState == .speaking` disjunct still fires.)

**419-A, the discriminating instrument (not built):** one `.notice` line in
the item.created/added handler — event type, role, whether it matched
`currentAssistantConversationItemID`, and state — timestamped against
`audio.started`. One session later the zeroing path is named instead of
argued. Fix follows the naming, not the other way round.

**Related:** #138 (the umbrella; the truncation path is its barge-in
machinery), #413 (the archive that exposed it), #416 (the
green-signal-covering-what-it-cannot-see family).

> **🎯 BARS 419-A1/A2 — pre-registered 2026-08-30 before any code (same go).**
> - **419-A1 (the instrument):** every assistant
>   `conversation.item.created`/`.added` arrival emits one ungated `.notice`
>   line naming the event type, the arriving item id, its relation to
>   `currentAssistantConversationItemID` (first / same item re-announced /
>   new item replacing), and — iff playback tracking is LIVE at arrival — the
>   elapsed ms about to be destroyed. Emitted BEFORE the reset and BEFORE the
>   current-id overwrite, so both destroyed values are captured. The
>   same-vs-new discrimination is the whole point: it separates the
>   beta/GA double-fire candidate from the second-item candidate.
> - **419-A2 (the formatter is pure and pinned):** `nonisolated static`
>   formatter, RED-first. Pre-registered mutations: **M1** — collapsing the
>   mid-playback branch (always "idle") reds ONLY the mid-playback pin;
>   **M2** — collapsing same/new (always "new item") reds ONLY the
>   discrimination pin.
> - **Scope fence:** this lane is the INSTRUMENT only. The truncation fix
>   follows the naming, not the other way round — no behaviour change to the
>   counter, the reset, or `truncateAndCleanUpAssistantState`.


> **✅ 2026-08-31 ~00:5x — 419-A1/A2 MET, MERGED `97e52d41` (PR #396, GATE:
> PASS on 24A5423a — 2771 units / 15 XCUITest / Release clean).** Every
> assistant `conversation.item.created`/`.added` arrival now logs
> `#419 <event> <item> — first|same item re-announced|new item (replacing
> <old>) — assistant idle|MID-PLAYBACK: resetting tracker at Nms`, emitted
> BEFORE the reset and BEFORE the id overwrite so both destroyed values are
> captured. RED-first (16 issues vs stubs); mutations M1/M2 each redded
> exactly their pre-registered pin. Scope fence held: no behaviour change to
> the counter, the reset, or truncation. **The next voice session's archive
> names the zeroing path — same-item double-fire vs second-item — instead of
> leaving it to argument; the fix lane follows that naming.**

> **⟵ 2026-09-01 HEADER POINTER (hygiene sweep):** the header still reads
> "deliberately NOT asserted (no log line can currently see it)." Bars
> 419-A1/A2 above shipped and merged 2026-08-31 (`97e52d41`, PR #396) — a
> log line now exists and will name the zeroing path on the next voice
> session. The mechanism itself remains unasserted; only the blindness is
> fixed.

> **🔴 2026-09-01 — THE ZEROING PATH IS NAMED FROM SOURCE + THREE ARCHIVES,
> AND IT IS NOT THE ONE 419-A1 WATCHES.** (Escalation read of the voice
> cluster; the log lines below are the ones that would have to change if
> this were false.)
>
> The entry's code read stopped one caller short. `resetAssistantAudioPlaybackTracking`
> has THREE in-session callers, not one: `endSession` (`:372`), the
> assistant `item.created/.added` handler (`:887`, the one 419-A1 watches)
> — **and `finalizeAssistantText` (`:1196`)**, which runs on
> `response.output_audio_transcript.done` / `response.output_text.done`.
> Realtime emits transcript-done when TEXT GENERATION completes, which is
> seconds ahead of audio playout (#138's own 2026-08-22 finding, stated
> there for the transcript UI and never carried over to the counter). So
> on every utterance: `audio.started` → tracker stamped → transcript-done
> → **tracker nil'd, `currentAssistantConversationItemID` nil'd,
> `voiceState = .listening`** — while the buffer is still draining → `audio.stopped`
> reads the banked 0. That is every reading this instrument ever produced.
>
> **Why item-arrival CANNOT be the agent, from the archives themselves:**
> - `talaria-138-fork` 19:56: `audio.started` 31.813 → `speech_started …
>   (state=listening)` 33.285 → `response.created` 36.454. **No assistant
>   item arrived in that window** (an item follows its `response.created`),
>   and the item handler never touches `voiceState` — nothing but
>   `finalizeAssistantText` can print `state=listening` 1.47 s into a
>   playback. #138's "ROOT CAUSE of the blind guard — `:825`
>   item.created" paragraph is therefore falsified ON ITS OWN ARCHIVE; a
>   correction is appended under #138.
> - `whoGoesThere-415` 17:58:40.699 (+0.58 s) and `talaria-138e`
>   20:13:46.510 (+0.52 s): same shape, same field.
> - `talaria-413-airpods`: strictly 1:1:1 turns, no item ever arrived
>   mid-playback, and all three stops still read 0 — the item path had no
>   opportunity there at all.
>
> **Consequence for 419-A1 as shipped:** it is aimed at a path that is not
> the cause. Every arrival will print `… — assistant idle` (an item always
> precedes its own `audio.started`), so the next archive would have shown
> "not the item handler" and left the zero unexplained. The instrument
> STAYS (a mid-playback item is still a real hazard worth seeing); it just
> does not name this.
>
> **The real cost is not `audio_end_ms: 0` — it is NO TRUNCATE AT ALL, plus a
> guard blind to the whole tail of every utterance.** After transcript-done
> the item id is nil, so `truncateAndCleanUpAssistantState` skips the
> truncate entirely; and `handleServerVADInterruption`'s guard
> (`.speaking || stamp != nil`) is false, so a barge-in in the tail logs
> "assistant not playing" and sends nothing. The server still interrupts
> on its own (`interrupt_response: true` — `audio.cleared` lands in the
> SAME millisecond as the "idle" `speech_started`, three archives), so the
> user hears the cut either way; server history just keeps the full text.
> **That last fact also retires #138's 138-K premise** ("a guard fix alone
> turns overlap into constant interruption"): audibility is decided
> server-side, this fix changes truncation accuracy and the log line.
>
> ### 🎯 BARS 419-B1…B6 — pre-registered before any code
> - **419-B1 (named, not argued).** The mechanism above, with the three log
>   lines; the fix targets `finalizeAssistantText` and nothing else.
> - **419-B2 (the counter survives transcript completion).** `audio.started`
>   → transcript-done → the counter keeps running, and at
>   `output_audio_buffer.stopped` it reads the real elapsed (≥ the slept
>   interval). Written RED first.
> - **419-B3 (a barge-in after transcript completion still truncates).**
>   `speech_started` after transcript-done, mid-playback, sends
>   `conversation.item.truncate` for the live item with `audio_end_ms ≥`
>   elapsed. RED first — today nothing is sent.
> - **419-B4 (state follows the audio buffer).** transcript-done mid-playback
>   leaves `.speaking`; `output_audio_buffer.stopped` flips `.listening`.
>   RED first.
> - **419-B5 (control — the audio-less path is unchanged).** transcript-done
>   with NO `audio.started` still lands `.listening`, and a following
>   `speech_started` sends nothing. Green before and after.
> - **419-B6 (isolating mutation).** Restoring the unconditional reset in
>   `finalizeAssistantText` reds B2/B3/B4 and leaves B5 plus the existing
>   `AppStoresTests` barge-in pins green.
> - **Scope fence:** no change to the guard, the item-arrival handler
>   (419-A1 stays), `truncateAndCleanUpAssistantState`, or the counter's
>   arithmetic. `currentAssistantAudioPlaybackMilliseconds` widens to
>   `// harness-visible` so B2 reads the same value the `audio.stopped`
>   line prints.

> **✅ 2026-09-01 — 419-B1…B6 MET. GATE: PASS on 24A5423a (re-run; run 1
> failed ONLY on the known `testConnectedRelaunchSkipsTheConnectEntry` flake,
> identical bytes, tree `2865888aa9e12d67`): units 2814/242 suites (count moved
> +5 — the new suite exactly), XCUITest 15 passed / 0 failed counted from the
> `Test Case '-[` ledger, Release clean. Main then moved under the lane with
> compiled inputs (#340-PROMOTE, #180-CONVENTION), so it was rebased and
> GATED AGAIN: PASS first run, 2832/244 · 15/0 · Release clean, the new suite
> green inside it. MERGED as PR #410, squash `02cad7bf`.**
>
> **The fix is one conditional.** `finalizeAssistantText` now drops the live
> item id, resets the tracker and flips to `.listening` ONLY when no playback
> is live (`assistantAudioPlaybackStartedAtUptime == nil`); while audio is
> draining, `output_audio_buffer.stopped/cleared` and
> `conversation.item.truncated` own all three, exactly as they already did
> for the pre-transcript-done window. Nothing else changed: the guard, the
> item-arrival handler (419-A1 stays), `truncateAndCleanUpAssistantState` and
> the counter arithmetic are untouched; `currentAssistantAudioPlaybackMilliseconds`
> widened to `// harness-visible`.
>
> **RED first, witnessed:** `AssistantPlaybackTrackingTests` (5 tests) ran
> against today's code — B2's two pins, B3 and B4 red (counter read 0, no
> truncate sent, state `.listening`), the B5 control green. **419-B6
> mutation:** restoring the unconditional reset (`if true {`) redded exactly
> B2/B3/B4 and left B5 plus the four pre-existing `AppStoresTests` realtime
> barge-in pins green (9 tests in 2 suites, 4 issues); the fix restored →
> 5/5 and the gate above.
>
> **What the device will show now, free, on the next voice session:**
> `#138 audio.stopped after Nms` reads the wall-clock playback; a
> `speech_started` in the tail of an utterance prints `#138 BARGE-IN …
> Xs into playback` and sends a `conversation.item.truncate` carrying the
> heard milliseconds instead of "assistant not playing" and nothing; and the
> `#419 … item.added` line stops mislabelling every arrival "first assistant
> item" (the old finalize nil'd the id, so the instrument could never say
> "new item (replacing …)"). **What a unit test cannot say:** whether the
> server's history reads better after a real barge-in is a device row —
> #138's card V1 records the values while it measures the volume arm. — 🐛 THE "AUTO-CONNECT ON LAUNCH" TOGGLE IS INERT — a shipping settings control the user can flip that NOTHING READS — **FOUND 2026-08-31 by the runbook staleness audit (read-only, static), and CONFIRMED by hand at the call sites. Mechanism is not in doubt; the fix is a product call.** **⚖️ RULED the same day (delete it, keep the key) and ✅ BUILT + MERGED 2026-09-01 — PR #398, squash `c48fcae1`: all four bars MET, the absent-reader pin watched RED before any production edit and mutation-isolated to one assertion, gate 2783/15/Release clean. CLOSED; awaiting the next sweep's archive move only.**

**The measurement:** `autoConnectOnLaunch` has exactly one writer and zero
production readers.

| site | what it does |
|---|---|
| `ServerSettingsScreen.swift:623-632` | the toggle's own `get`/`set` — label **"Auto-connect on launch"** |
| `UserSettings.swift:276, 384, 416, 458, 493` | declaration + `Codable` plumbing + decode default `true` |
| `DemoData.swift:167` | demo seed |
| `TalariaTests/AppStoresTests.swift:3021` | one test seed |

**Nothing consults it to decide anything.** Flipping it OFF changes no launch
behaviour; the value round-trips to disk and is never read back by any
connect path.

**How it got here, and why that matters more than the toggle:** the control
was *moved* to the Server screen when the Relay sub-page was retired
(`ServerSettingsScreen.swift:10-11` says so outright). The move preserved the
UI and dropped the consumer — the relay retirement (#375) removed whatever
read it, and the switch stayed. **This is the #180 honest-degradation family
arriving from the opposite direction: not a surface asserting a fact it
cannot measure, but a CONTROL promising an effect it no longer has.**

**Cost already paid:** it burned roughly 40% of the #350-D pilot's budget on
2026-08-31 — the card said "auto-connect OFF" as a precondition, the operator
could not find it on Uplink (it is on SERVER), and finding it would not have
helped, because setting it changes nothing. A dead control does not merely
mislead the user; it silently invalidates every runbook step that names it.

**⚖️ OWEN'S CALL — two honest options, deliberately NOT chosen here:**
1. **Delete the toggle** (and leave the persisted key for compatibility).
   Correct if auto-connect-on-launch is not a behaviour we intend to have.
2. **Wire it** to the launch connect path. Correct if the behaviour is wanted;
   this is a real feature decision, not a repair, because nothing currently
   defines what "auto-connect" should do post-#375.
**Do not "fix" this by making the toggle look disabled** — that keeps the
promise and hides the emptiness.

**Related:** #180 (honest degradation), #350 (asserted-vs-measured surfaces —
same disease, other direction), #375 (the relay retirement that plausibly
orphaned the reader), #416 (the green-signal-covering-what-it-cannot-see
family).

> **⚖️ RULED 2026-08-31 (Owen, interactive decision pass): DELETE THE TOGGLE.**
> The control comes out; the persisted `autoConnectOnLaunch` key stays for
> decode compatibility (`UserSettings.swift:493` defaults it `true`, and
> removing the key would break older stored settings for no benefit).
>
> **The reasoning this records:** auto-connect-on-launch is not a behaviour the
> app intends to have post-#375, so wiring it would have been inventing a
> feature to justify a leftover switch. Deleting it stops the app promising an
> effect it cannot deliver — #180's family, on the control side.
>
> **🔨 BUILD OWED (small):** remove the toggle from `ServerSettingsScreen.swift`
> (~`:623-632`) and its search-index entry (`SettingsSearchIndex.swift:65`,
> "Auto-Connect on Launch"); leave the model/Codable plumbing alone. A test
> should pin that no production code reads `autoConnectOnLaunch` — that is the
> property whose absence caused this, and it is the one worth guarding.
> **This entry closes when that lands, not before.**

> **📋 2026-09-01 — LANE OPENED (overnight; Owen's election, ruling above).
> Bars pre-registered before code:**
> - **420-A (the control is gone):** the "Auto-connect on launch" toggle no
>   longer renders on the Server screen, and the "Auto-Connect on Launch"
>   search-index row is deleted. [offline]
> - **420-B (the absent-reader pin, RED-first for real):** a structural test
>   asserts `autoConnectOnLaunch` is referenced ONLY by its declaration/
>   Codable plumbing (`UserSettings.swift`) and the demo seed
>   (`DemoData.swift`) — no other production file may touch it. This pin is
>   genuinely RED on tonight's main (the toggle's own `get` is a reader);
>   the deletion turns it GREEN. That ordering is the watched RED. [offline]
> - **420-C (compat kept):** the persisted key, its Codable plumbing, and
>   the decode default `true` survive untouched; existing decode coverage
>   stays green. [offline]
> - **420-GATE:** `lane-gate.sh` PASS. **The entry CLOSES when this lands**
>   (per the ruling — the close rides the merge, not the ruling). [Mac]

> **✅ 2026-09-01 — BUILT + MERGED. ALL FOUR BARS MET, NONE MISSED. THIS
> ENTRY IS CLOSED** (per the ruling's own *"closes when that lands"* — the
> archive MOVE waits for the next sweep). **PR #398, squash `c48fcae1`.**
>
> **420-B — MET, and the RED is the part worth reading.** The pin
> (`TalariaTests/AutoConnectTogglePinTests.swift`) was written and RUN
> **before a line of production code moved**, on the untouched tree:
> ```
> ✘ Test run with 6 tests in 1 suite failed after 0.382 seconds with 5 issues.
> ✘ autoConnectOnLaunchIsNamedOnlyByItsModelPlumbingAndDemoSeed()
>     ↳ offenders → ["Talaria/Features/Settings/ServerSettingsScreen.swift"]
> ✘ theToggleLabelIsGoneFromEveryShippingSource()      (same offender)
> ✘ settingsSearchOffersNoAutoConnectRow()             (3 issues)
>     ↳ matches("auto connect") → [SettingsSearchEntry(title: "Auto-Connect on
>       Launch", keywords: ["auto connect", "startup"], subsystem: .server)]
> ✔ theAllowListedSitesStillNameIt()  ✔ thePersistedKeyAndItsPlumbingSurvive()
> ✔ storedSettingsStillCarryTheKeyAcrossDecode()
> ```
> After the deletion: **56 tests / 4 suites passed** (the pin +
> `ServerSettingsTests` + `SettingsChannelsTests` + `SettingsSearchTests`).
>
> **MUTATION — and it isolated ONE pin, which is the claim worth making.**
> A reader put back into `ServerSettingsScreen.swift` (`private extension
> UserSettings { var mutationProbeAutoConnect: Bool { autoConnectOnLaunch } }`)
> produced **exactly one issue** — the reader pin — with both 420-A pins and
> both 420-C pins still GREEN. So the four bars are four independent
> assertions, not one assertion wearing four names; reverted, and the
> diffstat returned byte-identical to pre-mutation.
>
> **420-A — MET on two independent instruments.** The toggle's label literal
> is gone from every shipping source (raw-text scan of `Talaria/`, `Shared/`,
> `TalariaWidgets/`, `TalariaShare/`), AND the **compiled** index no longer
> matches `"auto connect"` / `"auto-connect"` — the compiled half is there
> because a row commented out rather than deleted would satisfy a source scan
> alone (`NamingSweepTests`' own lesson, borrowed).
>
> **420-C — MET, and it never wobbled.** `UserSettings.swift` and
> `DemoData.swift` are untouched in the diff; the stored property, the
> `CodingKeys` case and `decodeIfPresent(…) ?? true` are pinned by name, and
> a behavioural pin decodes `{}` → `true` and round-trips an explicit
> `false`. All three were green in the RED run, through the mutation, and
> after the deletion.
>
> **420-GATE — MET. `GATE: PASS on 24A5423a`** — Swift Testing **2783**
> (moved by exactly this lane's +6), XCUITest **15**, Release build clean;
> the only skips are the known-permanent `CondenserFidelityTests` pair.
> First run, no re-runs, no flakes.
>
> **⚠️ One design cost, recorded because the next reader will hit it.** The
> reader pin scans RAW TEXT, comments included — deliberately: a
> comment-stripper is a parser, and a parser is where this pin would be
> subtly wrong. The price is that prose outside the two allow-listed files
> cannot SPELL `autoConnectOnLaunch`, so `ServerSettingsScreen.swift`'s
> header describes the key rather than naming it, and says why in place.
>
> **CLOSE-OUT — prose this result falsified, corrected in the merge commit:**
> `planning/reports/2026-08-31-runbook-audit-visual.md` (the audit that FOUND
> this; its §350d answered *"is there still an auto-connect toggle?"* with
> *"yes, but it does nothing"* — a dated supersession note now says the
> answer is NO and flags the one stale clause in its corrected card wording),
> and the two 2026-08-05 #252 specs
> (`…-252-settings-inventory.md` §3, `…-252-settings-channels-design.md`
> row 02) which both listed the toggle as shipping SERVER surface.
> **Deliberately NOT corrected, and the distinction matters:**
> `design/T3_EXTRA_PAGES_PROMPT.md:47` and
> `design/Settings-Additional.dc.html:84` also show this toggle — but on the
> **RELAY** page, which #375 retired long before this lane. Already
> historical; not falsified by this result.
>
> **What this entry does NOT claim.** The toggle was inert, so its deletion
> changes no behaviour the user could have observed — there is nothing here
> for a device pass to confirm, which is why no device bar was registered
> and none is owed. **What it removes is a lie the runbooks kept believing.**

> **✅ 2026-09-02 19:59 — 419-B DEVICE CONFIRMATION MET.** Build 3211, corded `log collect`, one realtime session: `#138 audio.stopped after 2280ms` · `3558ms` · `7180ms` on three natural playback ends — the counter reads real elapsed time on device for the first time in this entry's history (every prior archive printed 0). The fix (`finalizeAssistantText` no longer zeroes the stamp, PR #410 `02cad7bf`) is confirmed where it matters, and a real barge-in would now send a true `audio_end_ms`. Evidence: `~/.talaria-instrument-runs/20260902-138o-gate-collect/`. **CLOSEABLE — nothing owed; archive move rides the next sweep.**

## 421. 🔴 "OJAMD'S GATEWAY IS DOWN" IS FALSE — THE HOST IS UP AND HEALTHY, AND THE PHONE'S OJAMD PROFILE CANNOT DIAL IT — **MEASURED 2026-08-31 from the Mac. Two independent reasons the profile cannot work as configured; which one is live is one screenshot away.**

**The belief this corrects:** handoffs §23 and §24 both record *"OJAMD's gateway
was down at last report"*, and that framing shaped an entire evening — the
device runbook's Hermes-host cards were run against the Mac instead, and the
phone's OJAMD failures were read as the host's fault.

**The measurement, from the Mac, 2026-08-31:**
```
curl http://100.110.102.59:8642/health          → 200 {"status":"ok", …}
curl http://ojamd:8642/health                   → 200
curl http://100.110.102.59:8642/health/detailed → {"error":{"code":"gateway_auth_failed"}}
```
A `gateway_auth_failed` is a **running server declining a key** — it is
positive proof of liveness, not a connection failure. **The gateway is up, is
answering on both the CGNAT literal and the MagicDNS name, and evidently has
been.**

**What the PHONE shows instead:** `OJAMD: gateway unreachable`, and host-fed
screens (Skills, Tasks) render **"Unreachable / unsupported URL"**.
`unsupported URL` is **`NSURLErrorUnsupportedURL` (-1002)** — a MALFORMED-URL
error. A host that is down produces -1004 (cannot connect) or -1001 (timeout).
**The error shape does not match the diagnosis the app is printing.**

**Two mechanisms, both fatal, both in our own code:**
1. **No scheme validation anywhere on the base URL.**
   `GatewayHermesHostService.normalizedBaseURL()` only trims whitespace and
   trailing slashes; `AppContainer.probeGatewayVerdict` (`:2236`) does
   `URL(string: trimmed + "/v1/models")` with no scheme check. So a stored
   `ojamd:8642` parses as **scheme `ojamd`, path `8642`** — a structurally
   valid `URL` that URLSession rejects with exactly **-1002**. This fits the
   observed error precisely. And `AppContainer+ConnectHost.displayAddress`
   (`:409`) *deliberately* falls back to the raw string when it cannot parse a
   host ("shown as typed rather than mangled"), so **the UI gives no signal
   that the address is unusable** — it just looks like what you typed.
2. **A MagicDNS name has no ATS exception and is blocked app-wide.** The
   exception is CIDR-keyed to `100.64.0.0/10` (`project.yml:392-394`) — IP
   literals in that range only. `http://ojamd:8642` is well-formed but
   **ATS-blocked** (-1022), per #166b's own four-arm experiment and the
   standing CLAUDE.md rule that MagicDNS names are blocked.

So **whichever is live, the OJAMD profile cannot work while it names the host
by anything other than a `100.64.0.0/10` literal.**

**🎯 THE ONE MEASUREMENT THAT SETTLES WHICH (not yet taken):** read the OJAMD
profile's **Base URL field verbatim** on the phone (Settings → Server → OJAMD,
or Uplink). `ojamd:8642` ⇒ mechanism 1. `http://ojamd:8642` ⇒ mechanism 2.
`http://100.110.102.59:8642` ⇒ both refuted and this entry needs re-opening
from scratch. **The stored value is on the device; everything above is
measured from the Mac plus a code read, so the mechanism is a strong
hypothesis and the liveness is a FACT.**

**Likely fix (one field):** set the OJAMD profile's base URL to
`http://100.110.102.59:8642`. **Product question that outlives it:** should the
app accept a scheme-less or non-CGNAT address at all, given it can never work?
Today it accepts silently, renders it back as typed, and reports the
consequence as *the host* being unreachable — which sends the user to debug a
healthy machine. That is #180's family (honest degradation) on the input side.

> **✅ 2026-08-31 — CONFIRMED BY OWEN + MEASUREMENT. Mechanism 1; mechanism 2
> is not needed.** Owen read the field: the OJAMD profile's base URL is
> **`/ojamd:8642`** — no scheme, and a **leading slash**. Parsed on the
> shipping toolchain:
> ```
> /ojamd:8642/v1/models         -> scheme=nil   host=nil            path=/ojamd:8642/v1/models
> ojamd:8642/v1/models          -> scheme=ojamd host=nil            path=8642/v1/models
> http://ojamd:8642/v1/models   -> scheme=http  host=ojamd          path=/v1/models
> http://100.110.102.59:8642/…  -> scheme=http  host=100.110.102.59 path=/v1/models
> ```
> **Row 1 is a RELATIVE path — no scheme, no host** — which URLSession rejects
> with exactly `NSURLErrorUnsupportedURL` (-1002), the observed error. The
> hypothesis is now a measurement.
>
> **⚠️ THE OBVIOUS FIX IS A TRAP, and this is the part worth keeping.** Merely
> prepending `http://` yields row 3 — a perfectly VALID URL whose host is a
> MagicDNS name, which sits outside `100.64.0.0/10` and is therefore
> **ATS-blocked app-wide** (-1022, #166b). That trades a -1002 for a -1022 and
> looks identical to the user. **The only value that works is the CGNAT
> literal: `http://100.110.102.59:8642`.**
>
> **The defect is confirmed as ours, not a typo's fault:** the app ACCEPTED a
> string that can never resolve, persisted it, rendered it back verbatim
> (`displayAddress` falls through to the raw string when it cannot parse a
> host — deliberately, "shown as typed rather than mangled"), and then reported
> the consequence as **the host** being unreachable — against a host that was
> up and healthy the whole time. A user following that message debugs the wrong
> machine, which is what happened here for days.
>
> **⚖️ OWEN'S CALL — the guard, not the field.** Fixing the field is one edit.
> The question is whether the app should reject-or-normalize a base URL that
> provably cannot work: no scheme, or a host outside `100.64.0.0/10`. Both are
> statically decidable at entry, and the Connect Host ladder already has an
> honest place to say so. NOT built — a decision, not a repair.
>
> **⚖️ RULED 2026-08-31 — DO NOT BUILD THE GUARD (Owen, same day):** *"Lets not.
> What if a user wanted to use this with pivpn or a self hosted wireguard."*
> **He is right and the proposal was Tailscale-shaped.** A PiVPN host lands on
> `10.8.0.x`, a self-hosted WireGuard host on whatever subnet its operator
> chose — neither is in `100.64.0.0/10`, so a validator keyed to that range
> would refuse exactly the self-hosting audience this app exists for. The
> scheme half was defensible; the range half was not, and they were proposed
> together. **Recorded as a decision, not a deferral: the field stays
> permissive.**
>
> **🔎 THE COROLLARY HIS SCENARIO EXPOSES — filed as an observation, not a
> proposal.** The same reasoning applies to ATS itself, with no validator
> involved: the exception is CIDR-keyed to `100.64.0.0/10`
> (`project.yml:392-394`), so **a WireGuard/PiVPN user pointing at
> `http://10.8.0.1:8642` is ATS-blocked at -1022 today.** HTTPS is unaffected
> (ATS permits it by default), so a self-hoster terminating TLS is fine and
> only the cleartext-HTTP-to-private-IP path is closed. **That range quietly
> defines which VPN topologies the Hermes tier supports** — worth knowing
> before launch copy makes a broader claim. Not raised as work; #166b owns the
> range and its four-arm proof.


**Related:** #414 (the other OJAMD-vs-phone puzzle — a DIFFERENT cause: a
deliberately keyless probe), #166b (the CIDR-keyed ATS exception and its
four-arm proof), #180, #350 (asserted-vs-measured surfaces), #420 (a control
whose effect is absent — same family, other direction).

> **⟵ 2026-09-01 POINTER (hygiene sweep):** the one-field fix
> (`http://100.110.102.59:8642`) named above is UNCONFIRMED as applied on
> the phone — nothing in this entry records Owen having made the edit. On
> Owen's device list.

> **✅ SETTLED ON DEVICE 2026-09-02 07:29 (Owen's screenshot):** the OJAMD profile reads `ONLINE · OJAMD` and carried a complete 7-message voice session — the base URL edit landed and the phone dials the host. The runbook's `421-confirm` card is PASS on this evidence (a live session beats the card's Test-Connection step). **CLOSEABLE — nothing owed; archive move rides the next sweep.** The standing corollary (CGNAT-only ATS exception; no validator by ruling) lives in #166's refresh and the archived #421 text.

## 350. 🐛 "LINKED · ONLINE" is an ASSERTION, not a measurement — the drawer and the settings strip claim a live host against a closed port, across a cold launch — **BUILT 2026-08-18 on Owen's go: bars 350-A..C + the banner rule MET (unit), 350-E MET (GATE: PASS, one contiguous run on an erased pool sim — 2337 units / 14 XCUITest / Release clean); 350-D's visual half owed as Owen's 30-second device fixture re-run post-merge (recorded honestly below). ~~PR open; merge is Owen's review.~~ **MERGED 2026-08-18 as `3d2e2992` (PR #318); the header carried an open-PR claim for four days after the merge — corrected 2026-08-19 by the new `oi-invariants.py` header check written because of exactly this.** OWED: 350-D's visual half, on Friday's device minutes.**

**MEASURED 2026-08-16 on `whoGoesThere` (build in hand, via iPhone Mirroring + computer use), incidentally, while standing up Group 4's standalone block. Not sought.**

**The setup, and why it is a fair fixture rather than a trick.** Group 4 needs the app hostless. Auto-connect was turned off and the base URL pointed at a port with nothing behind it. The first choice, `:9999`, turned out to be **OPEN on OJAMD** (something answers there and redirects to `/login?returnTo=%2Fhealth`) — caught by probing from the Mac (`nc -z ojamd 9999` succeeded) rather than assumed, which is the only reason the reading below is trustworthy. `:12399` was then verified **refused** and used instead.

**What was observed, on `http://ojamd:12399`, after a FULL KILL AND COLD LAUNCH:**

| surface | reading |
|---|---|
| drawer footer | `HERMES HOST` / `LINKED · ONLINE`, green pip |
| settings grid status strip | `LINKED · OJAMD · DEEPSEEK-V4-FLASH` |
| settings → UPLINK → **Test Connection** | *(the honest one — see below)* |

The drawer reading was re-checked after **20+ seconds** of dwell and did not change: no probe, no decay to a stale/unknown state, no re-verify on the cold launch that had just happened. The base URL edit itself was confirmed persisted (the field read `http://ojamd:12399` at the time).

**🔑 THE APP ALREADY HAS THE TRUTHFUL SIGNAL AND THESE SURFACES DO NOT CONSULT IT.** Test Connection on the same screen actively probes, and it was correct at every step — it reported honestly against the dead port and returned **`ONLINE · 23 MS`** the moment the URL was restored to `:8642`. So this is not "the app cannot know." It is a status label rendering a remembered pairing/connection fact as though it were a current one.

**Why it matters beyond a test fixture.** The user-facing failure is the tailnet dropping, the host going down, or a laptop sleeping: the app keeps showing a green LINKED · ONLINE while nothing will answer. That is exactly the shape #180 exists for — the app hiding its own degradation — and it is #342's *derived state survives, asserted state rots* appearing in a **UI surface** instead of a tracker entry.

**Deliberately NOT elected here:** whether the fix is a periodic probe, a decay-to-unknown after N seconds, a re-probe on foreground/cold-launch, or simply relabelling to name what is actually known (paired ≠ reachable). **#25's invariant governs whichever is chosen: an unknown state must render as ABSENT/unknown, never as a confident green.** Note also the cheap-and-honest option: the strip could show the last *successful* probe's age rather than a boolean.

**Bars pre-register in this entry before any code**, per the standing rule.

**Cross-references:** **#180** (the umbrella — the app hides its own degradation), **#191** (the status pill's local-brain honesty, where "a local brain's status line may not assert a host" was already reasoned through), **#25** (absent-not-zero), **#342** (asserted vs derived state), **#54** (transport-level reconnect, a different layer).


**2026-08-18 ~09:45 — Owen's go, in-chat: "good to start 350 as well."
Lane queued this session, after #354 opens.**

**2026-08-18 ~11:40 — LANE OPEN (Owen's go this morning); MECHANISM READ
FROM SOURCE; DESIGN ELECTED; BARS PRE-REGISTERED BEFORE CODE.**

**The lie, located exactly (two independent halves):**
1. `SessionsHermesClient.connectionStatus` initializes `.disconnected` and
   `ChatConnectionPresentation.effectiveState` maps `.connecting` AND
   `.disconnected` → `.online` ("stay optimistic so we never flash a false
   offline before the first probe resolves") — so a cold launch renders
   LINKED · ONLINE with a green pip on the chat header, the split-view
   sidebar footer, and the drawer footer (all three ride this one J-8
   mapping via `ContentView.chatConnectionState`) before ANY probe has
   run, and keeps rendering it until a probe lands.
2. The settings surfaces (`AboutSettingsContent` /
   `SettingsChannelsScreen` / `UplinkSettingsScreen`) each carry a
   VERBATIM-DUPLICATED `effectiveConnectionState` that claims `.online`
   only on a measured `.connected` — but falls back to
   `hostStore.connectionState` (relay-plane memory) for EVERY other direct
   status, including a measured `.error`: a direct-plane probe failure
   cannot darken a stale relay-online. Three copies of one computation is
   the #256 drift shape this same file already documents.

**Design (elected from the entry's open options — the "relabel to name
what is actually known" + measured-state option, no new polling
machinery; the #361 ticker already re-probes every 10–30 s while
active):**
- `HermesHostConnectionState` gains **`.checking`** — the honest
  paired-but-unmeasured state. #25 governs its rendering everywhere: no
  ONLINE text, no green (detail "LINKED · —": paired IS a local fact;
  reachability is absent until measured).
- `effectiveState`: `.connected` → `.online`; `.error` → `.offline`;
  `.connecting`/`.disconnected` → `.checking`. The optimistic arm dies.
- The settings triple collapses into ONE extracted pure function
  (`settingsEffectiveState(direct:hostFallback:hostConfigured:)` beside
  the J-8 mapping): measured `.connected` → `.online`; measured `.error`
  → `.unreachable` (a direct-plane failure outranks relay memory — the
  relay is Stopped+Disabled on the daily driver anyway); no verdict +
  host configured → `.checking`; no verdict + hostless → the hostStore
  fallback unchanged (the ON-DEVICE story keeps its honesty).
- `SettingsCardValues.uplink`/`statusStrip` + `SettingsCardAccent.uplink`
  gain compiler-forced `.checking` arms: "CHECKING", no LINKED claim, no
  accent.

**BARS (350-A..E):**
- **350-A (mapping, unit):** `.disconnected` and `.connecting` present as
  `.checking` — never `.online`; `.connected` → `.online`; `.error` →
  `.offline`. `sessionsHostDetail(.checking)` carries no ONLINE claim and
  the pip/accent for `.checking` is not the online green.
- **350-B (one settings truth, unit):** the extracted function replaces
  all three private copies (they are DELETED — by construction there is
  one call target); measured `.error` can no longer render green through
  the relay fallback; no-verdict + configured host → `.checking`;
  hostless arm byte-identical to today.
- **350-C (values, unit):** `uplink(.checking)`, `statusStrip(.checking)`
  and `SettingsCardAccent.uplink(.checking) == false` render the
  explicitly-unknown form — no "LINKED"/"CONNECTED", no green.
- **350-D (the entry's own fixture, sim):** cold launch with a configured
  host on a verified-REFUSED port — no surface renders ONLINE/green
  before the first probe, and after it the presentation is a measured
  offline form. Screenshots recorded.
- **350-E (gate):** `lane-gate.sh` PASS on an ERASED pool sim (the #354
  lesson — this lane seeds no state, but the pool carries other lanes'),
  Swift Testing count MOVED from 2340, Release clean; PR for Owen's
  review.

**2026-08-18 ~12:55 — TWO DESIGN AMENDMENTS FOUND MID-BUILD (recorded
before the gate, per the pre-registration culture):**
1. **The banner rule.** `showsConnectionBanner` was `isPaired && state !=
   .online` — with the honest mapping that would FLASH THE RED OFFLINE
   BANNER on every paired cold launch until the first probe lands, which
   is exactly the false-negative the old optimistic arm was defending
   against. Elected rule, extracted testable
   (`ChatConnectionPresentation.showsConnectionBanner`): the banner is an
   ALARM and `.checking` is not an alarm — it fires only on a MEASURED
   non-online state, never unpaired. The header still shows CHECKING with
   a dim pip through the window. (This is the honest version of what the
   optimism was for.)
2. **Drawer defaults hardened.** `SessionsDrawer.hostDetail`/`hostOnline`
   defaulted to `"LINKED"`/`true` — only previews/tests ever reach the
   defaults (both live call sites pass mapped values; verified by grep),
   but an asserting default is the #342 shape in miniature. Now
   `"LINKED · —"`/`false`.

**350-D scope note, stated honestly:** the sim leg exercised the app but
the paired-surface fixture (drawer footer / settings strip on a
configured-dead host) is NOT reachable in the sim without real keychain
credentials — the unpaired sim routes to the on-device brain and renders
local-truth surfaces (which stayed honest throughout). The mapping and
every surface value are unit-pinned (350-A..C + the banner rule); the
honest closer for 350-D's visual half is OWEN'S ORIGINAL FIXTURE re-run
on device post-merge (auto-connect off, base URL on the verified-refused
`:12399`, cold launch — 30 seconds, and he has done it once already).


**2026-08-18 ~13:30 — PER-BAR VERDICTS (branch `350-link-honesty`, commit
`adecba5b`; PR open, merge is Owen's review). RED observed on all five
mapping tests via behavior-preserving stubs before the logic landed
(11 assertion issues, each on the intended expectation):**
- **350-A — MET.** `.disconnected`/`.connecting` → `.checking`, never
  `.online`; measured verdicts map to themselves;
  `sessionsHostDetail(.checking)` = "LINKED · —" (no ONLINE claim); the
  `.checking` pip/accent is never the online green (pinned via the
  extracted values; every switch arm across chat header, banner, Connect
  screen, and Uplink screen was compiler-forced and hand-written non-green).
- **350-B — MET.** `settingsEffectiveState` replaces all three verbatim
  private copies (deleted — one call target by construction); a measured
  direct `.error` renders `.unreachable` and can no longer stay green
  through stale relay memory; no-verdict + configured host → `.checking`;
  the hostless arm is byte-identical to the old fallback.
- **350-C — MET.** `uplink(.checking)` = "CHECKING", `statusStrip`
  carries no LINKED/CONNECTED and prefixes CHECKING,
  `SettingsCardAccent.uplink(.checking)` = false.
- **Banner rule (amendment 1) — MET.**
  `connectionBannerWaitsForAMeasurement` pins: never for `.checking`,
  only for measured non-online, never unpaired.
- **350-D — unit half MET; visual half OWED as recorded in the scope
  note above:** the paired-surface fixture is unreachable in an unpaired
  sim; Owen's original device fixture (auto-connect off, cold launch on
  refused `:12399`) is the honest closer post-merge — expected reading:
  CHECKING (dim pip) rather than LINKED · ONLINE, and the red banner only
  after the probe actually fails.
- **350-E — MET: GATE: PASS in ONE CONTIGUOUS RUN on an erased CC-lane-1
  — Swift Testing 2337 (count MOVED from 2331 by exactly this lane's +6),
  XCUITest 14/14 (the known CondenserFidelity unit-suite skip pair only),
  Release clean.** MessageIdentityUITests passed at gate on the erased
  sim — further support for #236's sim-state aggravator note.

> **2026-08-18 night — merge-recording:** PR #318 merged `3d2e2992`.
> **OWED: 350-D's visual half** — Owen's 30-second fixture (auto-connect
> OFF, refused `:12399`, full kill + cold launch → CHECKING with a dim pip,
> never LINKED · ONLINE; red banner only after a measured fail). A weekday-
> evening minute, not a Saturday bar.

> **📍 2026-08-26 — POINTER (this entry's function names moved; the
> BEHAVIOUR did not).** #264 half 2 folded
> `ChatConnectionPresentation.effectiveState` and
> `.settingsEffectiveState` into **`ConnectionSignal`**
> (`Talaria/Core/ConnectionSignal.swift`) — one derivation, two documented
> surface arms. Text above naming those two functions describes a home that
> no longer exists; **every mapping expectation this entry won is unchanged
> and still pinned** (`SettingsChannelsTests`, same assertions, new callee).
> What #264 added on top: the three settings surfaces no longer pass
> `hostConfigured` at all, because they were spelling it two different ways
> — Uplink through a LEGACY settings fallback the chat plane never dials.
> **350-D's visual half is untouched and still owed.**

> **📍 2026-09-01 — THE OWED FIXTURE HAS ONE FEWER STEP (#420 closed).**
> Every description of 350-D's owed device fixture above says *"auto-connect
> OFF, refused `:12399`, full kill + cold launch."* **The auto-connect step
> is now impossible to perform and was never load-bearing:** #420 measured
> that toggle INERT — one writer, zero production readers — and Owen ruled
> it deleted (PR #398, `c48fcae1`, 2026-09-01). The control no longer exists
> on the Server screen. **The fixture is unchanged in substance** — base URL
> on the verified-refused `:12399`, force-quit, cold launch, read the drawer
> footer and the settings strip within ~10 s — and the operator should not go
> looking for a switch that is gone. The expected reading is untouched:
> CHECKING (dim pip) on the strip, `LINKED · —` with an amber pip on the
> footer, red banner only after a measured fail.

## 368. 🔧 Phase 3 slice 3E — the runs-transport CUTOVER: runs becomes the default plane — **FILED 2026-08-18 night per #268, the same session Owen RULED GO ("Go — build it Wed/Thu"; deferred that morning, unblocked by the OJAMD rollout putting the mirror on both hosts). Build 2026-08-19 PM → 08-20; M-sized. NOT STARTED; bars pre-register here before code.** **⟵ HEADER CORRECTED 2026-08-23 (stale-header sweep): MERGED 2026-08-19 as `33108d05` (PR #322).**

- Owns the cutover DECISION #362 and #283 both deferred to an unnumbered "3E";
  absorbs #283's 3E evidence-clock note (2026-08-17 — the clock has run since).
- Collapses the #235/#246 recovery-machinery class onto the runs plane; **#328
  route 1 rides this** (Stop that reaches the host), and #371's restored-✓
  honesty design belongs to the same surface.
- Post-cutover, #322's cancel-read stops being a permanent no-op (its close
  recorded that its value was tied to this rollout).


> **2026-08-19 AM — LANE OPENED. BARS PRE-REGISTERED BELOW BEFORE ANY CODE**
> (#215's convention, #216-era vehicle: they live in this entry, not a
> dispatch doc). Nothing in this block was written after a measurement.

### What 3E actually changes — the code, named before it moves

Read from HEAD `f48add84`, not from the plan's summary of it. Four seams:

1. **The transport fork.** `SessionsHermesClient.useRunsTransportProvider`
   (`SessionsHermesClient.swift:248`) is read once per turn by BOTH turn
   paths — `performSyncTurn` (`:311`) and `sendStreaming` (`:374`) — and
   picks `streamTurnViaRuns`/`syncTurnViaRuns` over `streamTurn`/
   `postSyncChat`. It is armed from `UserSettings.useRunsTransport`
   (default `false`, `UserSettings.swift:452`) via
   `AppContainer.swift:744`, surfaced as the Developer switch
   (`DeveloperSettingsScreen.swift:511`).
2. **The recovery machinery.** A dropped stream yields `.interrupted`;
   `ChatStore.armPendingRunRecovery` (`:1478`) mints a `PendingRun` and
   starts `startReconcileLoopIfNeeded` (`:1541`) → `attemptReconcile`
   (`:3577`) → `hermesClient.reconcileFromServer()`, which re-reads
   `GET /api/sessions/{id}/messages` and adopts **positionally**: "the last
   hermes row newer than `pending.sentAt`, non-empty". Budget 120 s wall
   clock (`reconcileWallClockBudget`), 2 s interval. The runs plane already
   owns a strictly better instrument for the same job —
   `pollRunToTerminal` / `readRunStatus` / `deliverPolledTerminal`
   (`+RunsTransport.swift:1023/1087/1129`) against `GET /v1/runs/{id}`,
   1 h TTL, carrying the run's OWN output and usage.
3. **Stop (#328 route 1).** `hardStopActiveRun()` (`+RunsTransport.swift:1354`)
   opens `guard let context = activeRunContext else { return false }` — and
   on the sessions plane there is never a context. The cutover is what makes
   that guard stop firing on the default path; **#328 route 1 is delivered
   by this slice, not built separately.**
4. **What the sessions plane keeps.** Session create/priming (hop setup, not
   turn transport), `openSession`, `listSessions`, `/messages`, `fork`, and
   `POST /api/sessions/{id}/model` (#241's pin). Those are untouched — the
   slice's phrase "sessions plane keeps only history/fork/model-pin" is
   about the TURN, and a run still writes its turn into the SessionDB row
   (3A-0's N4 write-half), so history survives the move by construction.

### The one SCOPE decision — ❓ QUESTION FOR OWEN (Thu review, or sooner)

The plan's §5 **Q3 was never answered** (archived #283: "Q2 answered; the
other eight stand as recommended/pending"). Q3 is exactly this slice's
scope: **wholesale, or a permanent dual path?**

- **Recommendation: WHOLESALE — delete the switch and both sessions-plane
  turn transports.** The plan's own recommendation, and the slice-table
  definition already says it ("sessions plane keeps only history/fork/
  model-pin"). A retained-but-unused branch is the #218 shape — two paths,
  one tested — and #218 cost two days on exactly that.
- **The honest counter-argument, stated rather than buried:** on 2026-08-16
  the switch was the recovery — Owen flipped it OFF and chat came back
  (archived #283's stopped-clock note). #356 later EXONERATED the transport
  (the cause was a stopped/mid-update OJAMD reached through the M-5 birth
  hop), so the escape hatch's one save was a misattribution — but it was
  still a save, and after deletion there is no equivalent lever.
- **How the build is structured so this stays Owen's call and costs nothing
  to reverse:** three commits, deletion LAST. Commits 1–2 (recovery
  collapse + default flip) are correct under either answer; commit 3 is the
  deletion. If Owen wants the hatch kept, commit 3 is dropped at review and
  the PR still ships the slice's substance.
- **Declined, with reason:** gating the flip on a live `/v1/capabilities`
  probe. It buys a graceful answer for a host that cannot serve `/v1/runs`
  — but both hosts are 0.20.3/0.20.4, no such host exists in this
  deployment, and the probe is a launch-path network dependency bought
  against a hypothetical. Bar **3E-I** covers the same risk by requiring the
  failure to be VISIBLE and named instead of graceful.

### Guardrails checked before the bars (each is a real check, not a nod)

- **S27 (plan §4.4) — NOT TRIGGERED.** The cutover does not register the app
  as a delivery target, so `splits_long_messages` and the 4000-char cap stay
  out of scope. Named here because §4.4 says in so many words that 3E is the
  slice that could cross that line quietly.
- **#310 is NOT a blocker.** `BackendProfile.relayBaseURL` being
  non-optional is a pairing/profile shape, not a turn transport; the cutover
  neither fixes nor worsens it.
- **#371 stays FILED, not built here.** Its restored-✓ honesty design "rides
  the runs plane" — the surface this slice settles — but a restored chip's
  provenance is its own question and folding it in would smuggle an
  unmeasured change into a cutover.
- **#322 becomes live automatically** (its close recorded that its value was
  tied to this rollout); no code owed, a dated note at its archived entry
  when 3E-G passes.

### BARS — pre-registered 2026-08-19 before any code

- **3E-A (cutover, unit).** With no Developer intervention, a remote streamed
  turn AND a remote sync turn both take the `/v1/runs` path — proven from
  (i) a fresh `UserSettings()` and (ii) a decoded PRE-CUTOVER settings blob
  that persisted `useRunsTransport: false`. **(ii) is the load-bearing half:
  the key is always encoded (`UserSettings.swift:600`), so every existing
  install carries an explicit `false` and a default flip alone moves
  nobody.** Falsifier: either input reaching `streamTurn` or `postSyncChat`.
- **3E-B (recovery collapse, unit).** A turn whose `/events` stream dies
  after the run is committed resolves from `GET /v1/runs/{id}`: the adopted
  reply is the run's own `output`, carrying the run's own `usage`, keyed by
  the run id. TWO negative controls, both of which the positional reconcile
  fails today: **(i)** a sessions message list whose newest hermes row is an
  UNRELATED later turn is NOT adopted; **(ii)** the #293(b) skew shape — a
  host clock BEHIND the client's `sentAt` — still resolves, because the
  timestamp predicate no longer gates adoption.
- **3E-C (durability, unit).** A run that reaches terminal at T+150 s is
  still adopted. The old wall-clock budget was 120 s against a 1 h status
  TTL. Falsifier: the loop giving up at 120 s.
- **3E-D (exactly once, unit).** #237's duplicate shape stays pinned absent:
  a late `.interrupted` for a run ALREADY resolved by status polling tears
  down quietly and never re-arms, and a status-poll adoption racing a late
  stream `.completed` leaves exactly one assistant row.
- **3E-E (deletion, structural — scored only if Owen rules WHOLESALE).**
  No call site in `Talaria/` submits a turn on the sessions plane: `grep`
  proves zero references to `chat/stream` and zero to
  `POST /api/sessions/{id}/chat`, and `useRunsTransport` is absent from the
  tree. `/api/sessions*` survives ONLY as create/open/list/messages/fork/
  model. Falsifier: any surviving turn-submitting sessions call site.
- **3E-F (#328 route 1, unit).** On a default-configured remote turn, Stop
  issues `POST /v1/runs/{id}/stop` — i.e. `hardStopActiveRun()` returns
  `true` having really had a run, rather than guard-returning `false`. This
  is #328 route 1's app half; the host-log half is 3E-H.
- **3E-G (gate).** `scripts/mac/lane-gate.sh` PASS — units **and** Release —
  with the unit count MOVED from the **2351** baseline (a count that did not
  move means `test-without-building` re-ran a stale `.xctest`; CLAUDE.md's
  named trap). TCC calendar+reminders granted on the pool sim immediately
  before the run.
- **3E-H (device, Owen — PM slot).** One real remote conversation on the
  DEFAULT path, end to end: a tool-using turn renders a chip with REAL
  content (#362's mirror, on whichever host is active), a stream killed by
  backgrounding recovers its answer, a Stop mid-tool is confirmed **from the
  host's own log** (not the app's UI — #328's whole lesson), and a
  leave-and-return shows the thread intact.
- **3E-I (honesty, negative — the cutover's own risk).** A host that cannot
  serve `/v1/runs` (submit answers 404) fails **visibly and by name**: no
  silent fallback to a plane that no longer exists, no fabricated answer, no
  spinner that never ends. #180's family bar, and the one bar whose failure
  would make the wholesale scope wrong.
- **3E-J (no behaviour smuggled, structural).** The diff changes transport
  and recovery only. Specifically unchanged and asserted so: the artifact
  correlator's `session_id`+`path` key (#362), stored-args reconstruction
  (#364), the #306 hold-slot matrix rows, and the #285 frozen-endpoint rule.
  Falsifier: any edit to those mechanisms riding this PR.

**Sequencing:** commit 1 = recovery collapse (3E-B/C/D), commit 2 = the flip
+ migration (3E-A/F/I), commit 3 = deletion (3E-E). Gate once at the end
(3E-G). Device leg 3E-H is Owen's, evening.


> **✅ 2026-08-19 ~08:40 — SCOPE RULED (Owen): *flip now, delete next week.***
> The plan's §5 **Q3 is answered** at last, and not as the plan recommended:
> the cutover ships as the default flip plus the recovery collapse, and the
> sessions-plane turn transport + the Developer switch are **deleted in a
> separate lane after a week of living on the default** — filed the same
> minute as **#382** with a dated trigger, per #268.
>
> **What this does to the bars:** **3E-E (deletion, structural) is NOT
> SCORED BY THIS LANE** — it moves verbatim to #382, which is where the
> deletion happens. It was pre-registered as conditional on exactly this
> ruling ("scored only if Owen rules WHOLESALE"), so this is the
> pre-registration working, not a bar being redefined after the fact. Every
> other bar stands unchanged.
>
> **What it costs, stated rather than buried:** for one week the tree
> carries two turn transports with only one of them exercised by default —
> the #218 shape, knowingly, on a clock. That is the trade Owen bought
> evidence with, and #382 is the thing that stops it becoming permanent.

> **2026-08-19 AM — BUILD PROGRESS (commits on `t27-368-3e-cutover`).**
>
> **Commit 1 `8e35c873` — the recovery collapse. Bars 3E-B / 3E-C / 3E-D
> MET** (11 tests, `TalariaTests/RunStatusRecoveryTests.swift`).
> - `DroppedRunResolution` + `resolveDroppedRun(runID:sessionID:)` on
>   `HermesClientProtocol`, implemented on the runs client from
>   `readRunStatus` — **one request per call; the loop stays in `ChatStore`**
>   (#292's rule: two budgets for one recovery is how that regression comes
>   back).
> - `SessionsHermesClient.resolution(from:)` is a PURE mapper, so #235 F1's
>   no-empty-bubble rule and 296-C1's `error` union are both scorable from a
>   literal status body with no URL session.
> - `ChatStore.attemptReconcile` forks on `pending.runId` and now reports
>   THREE outcomes — the old `Bool` could not say "unresolved AND
>   unpollable", so a 404'd run used to grind its whole budget.
> - The run-id loop gets its own **600 s / 5 s** budget. Longer is safe here
>   for the precise reason #145 Part C says 120 s was not safe there: the
>   per-attempt cost is now bounded by construction (one status GET at the
>   interactive timeout), where `reconcileFromServer()`'s was not.
> - **MUTATION-CHECKED, not merely green.** Four mutations were applied and
>   the suite re-run: revert the fork · revert the budget selection · mint a
>   fresh `UUID()` for the adopted reply · read `.gone` as "keep polling".
>   **All seven behavioural tests went RED; the four pure-mapper tests
>   correctly stayed green.** (The tests' own comments name the mutation
>   that kills each one — a test that cannot be made to fail is not
>   evidence.)
>
> **Two honest notes from the build:**
> - Three assertions in the first pass were WRONG ABOUT TIMING, not about
>   behaviour: the `.interrupted` arm arms the reconcile loop before any
>   manual pass runs, so `hasActiveReconcileLoop` is legitimately true for
>   one interval after a resolution. The assertions were corrected; **no
>   production code was changed to make a test pass.**
> - That lingering-loop window is PRE-EXISTING and shared with the legacy
>   path (a manual pass resolving while the loop sleeps). It was left alone
>   deliberately — closing it is a behaviour change, and bar **3E-J** forbids
>   smuggling one into this diff.


> **✅ 2026-08-19 — MERGED as `33108d05` ("Merge pull request #322 from
> AethyrionAI/t27-368-3e-cutover"), on Owen's go. `GATE: PASS` at merge.**
> ~~PR OPENED / awaiting review.~~ Corrected in the merge's own follow-up
> commit rather than days later — the four-day-stale shape #322/#328 each
> produced once. Body = `handoffs/PR-BODY-368.md` (gitignored).
> ⚠️ **PR #322 and TRACKER #322 are different things** (CLAUDE.md's standing
> disambiguation rule); both appear in this entry's neighbourhood.
>
> **THE RUNS PLANE IS NOW THE DEFAULT REMOTE TRANSPORT.** Remaining on this
> item: **3E-H, the device leg** (Owen, evening — the five-step walk above).
> The deletion half is **#382**, ⏰ 2026-08-26.

> **✅ 2026-08-19 — CLOSE-OUT DEBT PAID, in the merge's own follow-up commit
> (#317).** Every entry below now carries its dated correction. The list is
> kept rather than deleted so the discipline is auditable: this is what was
> owed, and it was paid at the merge rather than four days after it.
>
> - **#328** — route 1's question DISSOLVES rather than being answered. Its
>   entry says route 1 is "still gated on 328-A's route probe, which nobody
>   has run"; after the cutover no ordinary turn is on the sessions plane, so
>   every default Stop reaches the host and there is nothing left for that
>   probe to unblock. The entry needs a dated note saying so — and saying
>   that the residual only fully closes at **#382**, since until the switch
>   is gone a user can still turn the swallowed-Stop plane back on.
> - **#322** — its close recorded that the cancel-read's value "was tied to
>   this rollout". It is live now; a dated pointer block goes beneath the
>   ARCHIVED entry, append-only, per #317 ruling (a).
> - **#371** — its design "rides #368". #368 did not build it; the entry
>   should say the surface it rides is now the default, so the design
>   question is answerable rather than blocked.
> - **#293(b)** — its measurement-only clock-skew logging is now unreachable
>   from the run-id path. The finding is not refuted; its exposure shrank to
>   the legacy arm, which #382 deletes. Note, do not close.
> - **CLAUDE.md** — grepped 2026-08-19: it carries **no** claim about the
>   transport default or the Developer switch, so nothing there is falsified
>   by the flip. Recorded because "checked and found nothing" is a different
>   fact from "not checked".


> **✅ 2026-08-19 ~08:55 — `GATE: PASS`. THE LANE'S CODE IS COMPLETE; what
> remains is Owen's review, the merge, and the device leg.**
> `scripts/mac/lane-gate.sh` on `CC-lane-1` (TCC granted immediately before,
> per the standing hang trap): Debug suite **2372 Swift Testing / 185 suites
> + 14 XCUITest**, and the **Release build** — the check a Debug-only stack
> cannot make (#218). **The count MOVED from the 2351 baseline (+21)**, so
> this is not `test-without-building` re-running a stale `.xctest`.
> Two skips, both the known-permanent `CondenserFidelityTests` pair (needs
> Apple Intelligence hardware); no new skip was introduced.
>
> **SCORECARD**
>
> | bar | verdict | evidence |
> |---|---|---|
> | 3E-A cutover default + migration | **MET** | `RunsTransportSwitchTests` (6) — incl. the pre-cutover blob whose explicit `false` is migrated, and the post-cutover opt-out that STICKS |
> | 3E-B recovery collapse + 2 controls | **MET** | `RunStatusRecoveryTests` — unrelated-newer-row control and the #293(b) skew control both pass |
> | 3E-C durability past 120 s | **MET** | the run-id loop reads its own budget; scaled, not slept |
> | 3E-D exactly once | **MET** | deterministic id from the run id; the late-duplicate arm re-measured on the default path |
> | 3E-E deletion | **NOT SCORED — moved to #382** | Owen's ruling; pre-registered as conditional |
> | 3E-F #328 route 1 | **MET (app half)** | default turn is a runs turn (3E-A) × `hardStopActiveRunPostsStopWithAuth` / `cancelStreamingDefaultPostsStop`. ⚠️ **Honest limit: the one line that arms the provider from settings (`AppContainer.swift:744`) is CODE-READ, not test-covered.** 3E-H is what closes it end to end. |
> | 3E-G gate | **MET** | above |
> | 3E-H device | **OWED — Owen, PM slot** | see below |
> | 3E-I honesty on a runs-less host | **MET** | `RunsPlaneTransportTests.aHostThatCannotServeRunsFailsVisiblyRatherThanSilently` — one `.failed` with words, never `.interrupted` or `.unreachable` |
> | 3E-J nothing smuggled | **MET** | the artifact correlator, stored-args reconstruction, the #306 matrix and the #285 frozen-endpoint rule are untouched; the one lingering-loop imperfection found mid-build was deliberately LEFT ALONE for this reason |
>
> **What the full suite caught that the targeted suites could not:** four
> existing tests modelled the OLD recovery and went red on the flip
> (`lateDuplicateInterruptNeverResolvesTwice` and three #306 matrix tests).
> Their fixtures now implement `resolveDroppedRun` rather than being pushed
> back onto the legacy branch — otherwise #237 and the hold-slot matrix
> would be exercising a path #382 deletes. **This is the argument for the
> gate over a targeted run, happening: three green suites said nothing about
> them.**
>
> **📱 2026-08-19 — 3E-H DEVICE RESULTS, build 2848 (Owen). FOUR OF FIVE
> STEPS PASS; step 3 (Stop, host-log confirmed) NOT YET RUN.**
>
> - **Step 1 — tool-using turn: PASS.** WRITE_FILE chip with real content on
>   the runs plane.
> - **Step 2 — background mid-turn, return: PASS.** The answer recovered.
>   **This is the bar with the most new machinery behind it** — the
>   `.interrupted` hand-off, `resolveDroppedRun`, the 600 s/5 s budget and
>   the run-id-derived identity all had to be right for it, and it is the
>   first time any of them ran outside the suite.
> - **BEYOND THE BAR, and volunteered rather than asked for: FORCE QUIT and
>   returned → the answer is STILL THERE.** A `PendingRun` does not survive
>   process death, so this is not the recovery loop — it is the adoption
>   having been PERSISTED. Two mechanisms could produce it (the conversation
>   cache written by `settlePendingRun(adopted: true)`, or a refetch on
>   reopen) and **this observation does not distinguish them**, so neither
>   is claimed. Recorded because it is real evidence about durability that
>   the pre-registered walk did not think to ask for.
> - **Step 5 — the migration, visible: PASS.** Settings → Developer reads
>   **Runs Transport ON** with nobody having touched it, on a phone carrying
>   a PRE-CUTOVER settings blob. **This is the half of 3E-F the scorecard
>   flagged as code-read-only** (`AppContainer`'s one provider-arming line):
>   it is now device-confirmed end to end, so **3E-F's stated limit is
>   discharged.**
> - **Step 3 — STOP mid-tool, confirmed from THE HOST'S OWN LOG: OWED.**
>   The one bar left, and deliberately the one that cannot be scored from
>   the app's UI — #328 exists because the UI lied about exactly this.
> - **Step 4 — leave the thread and return → chip persists: AMBIGUOUS in
>   the report.** "Backgrounded and returned" is not the same walk as
>   leaving the THREAD and coming back to it, and the force-quit result may
>   or may not have covered it. Not scored either way; re-ask rather than
>   assume.

> **📱 2026-08-19 09:02 — OTA STAGED: `main @ 1a983144`, Release, BUILD
> 2848.** Install from phone Safari at
> `https://owens-mac-mini.tail5663a6.ts.net` (dev-signed upgrade-install in
> place; app data persists). **Verified END TO END over the tailnet, not
> just staged locally:** manifest 200 and titled `Talaria 27 (main @
> 1a983144 Release)`, `Talaria27.ipa` 200 at 12,247,387 bytes.
>
> **Quote build 2848 in every 3E-H result.** #200D's lesson is that a result
> from a stale install is indistinguishable from the staged one unless the
> record names its build — `ota-stage.sh` stamps the commit count into
> `CFBundleVersion` precisely so that check is possible. If the phone reads
> anything other than 2848, the walk below has not been run on the cutover.
>
> **The Runs Transport row IS visible in this Release build** — checked
> rather than assumed: `flagsSection` sits OUTSIDE `DeveloperSettingsScreen`'s
> `#if DEBUG` blocks, unlike the batteries/monetization sections. So step 5
> is real on an OTA build.

> **3E-H, the device leg — the exact walk (evening, ~5 min):**
> 1. A tool-using turn ("write test-3e.md with a short haiku") → WRITE_FILE
>    pill → chip with **real content** (#362's mirror on the active host).
> 2. Background the app mid-turn, return → the answer **recovers**. This is
>    the bar with the most new machinery behind it.
> 3. Stop mid-tool → confirm from **the host's own log**, not the app's UI
>    (#328's whole lesson: the UI has lied about this before).
> 4. Leave the thread and return → transcript intact, chip persists.
> 5. Glance at Settings → Developer: the Runs Transport row reads ON without
>    anyone having touched it. That is the migration, visible.

## 422. 🧠 MEMORY–AGENT INTEGRATION — what Talaria does with what the agent remembers — **NAMED BY OWEN 2026-08-31 at #378's close ("Open a new item for memory agent integration. Lets discuss this; i have thoughts"). FILED THE DAY IT WAS NAMED per #268. NO SCOPE YET — Owen's thoughts come first, and nothing here should be read as a design.**

**Why this exists as its own number rather than as #378 reopened:** #378 was
the *introspection* lane and it delivered exactly what it claimed — a
read-only DEVELOPER panel over a local memories directory, honest on a device
(it says UNREACHABLE, never an empty list). Closing it was right. **But the
question Owen raised is larger than the panel**, and re-opening a lane that met
its bars to hold a different question is how entries become unreadable.

**What is already TRUE and should not be re-derived when scope is written:**
- **The phone has no path to `~/.hermes/memories/*.md`.** That is why #378's
  panel reports UNREACHABLE on device and would do so *"on every device,
  forever, under that scope"* — a structural fact, not a bug.
- **There are at least TWO stores and they can disagree.** Owen runs the file
  backend AND a shared **Honcho** instance (#159's correction). If a profile's
  `memory.provider` is Honcho or Mem0, the `.md` files are one layer and **may
  be stale** — so any surface that renders them unlabelled would be asserting
  something it cannot measure (#180's family).
- **A delivery route exists in principle:** the talaria plugin already speaks a
  plane the phone speaks, and could expose memory without adding a client-side
  dependency. Ruled scope for #378 excluded new dependencies; that ruling was
  about #378 and does not bind this entry.
- **Honcho was deferred there, not refused:** *"later if ever wanted."*

**Deliberately NOT decided here:** whether this is a read surface, a write
surface, or an agent-behaviour question (what the agent remembers ABOUT the
user, and whether the user can correct it); whether it is user-facing at all;
and which store is authoritative when they disagree. **Owen routes.**

**Related:** #378 (the introspection lane this succeeds — CLOSED, delivered),
#379 (Projects introspection, PARKED post-launch), #159 (the correction that
established the two-store reality), #269/#308 (the plugin arc, if delivery
routes through it), #180 (asserting what cannot be measured).

> **🧭 SHAPED 2026-08-31 (Owen, in conversation). His opening idea and the
> correction it produced are both recorded, because the correction is the
> useful part.**
>
> **Owen's first framing:** *"tie it into my honcho and hindsight"* — Talaria as
> a client of the memory providers his host already runs. **Both are real
> Hermes memory plugins** (`~/.hermes/hermes-agent/plugins/memory/` ships
> **eight**: `byterover`, `hindsight`, `holographic`, `honcho`, `mem0`,
> `openviking`, `retaindb`, `supermemory`), so the idea maps onto an existing
> plugin set rather than inventing one.
>
> **The correction, accepted by Owen (*"your point is better"*):** that shape
> only serves users who HAVE a host, and the launch pivot says judge against
> the hostless default user. **Talaria has NO memory of its own today** —
> there is no `MemoryStore` and no memory model in the tree; `AgentMemorySection`
> is a READER of the host's files (#378) and nothing more. **So this splits
> into two different products:**
>
> - **(a) CLIENT OF THE HOST'S PROVIDERS** — modest work, needs a delivery
>   route, **host-tier only**. Cheap in one specific way worth remembering:
>   because the providers are Hermes PLUGINS, the host tier gets memory the
>   moment a delivery route exists — one route, not eight integrations.
> - **(b) TALARIA'S OWN LOCAL MEMORY** — bigger, and the one that serves the
>   default user. Can later FEED (a) when a host is attached.
>
> **⚖️ BOTH ARE POST-LAUNCH (Owen). But (b) is recorded as a DELIBERATE LAUNCH
> GAP, not a backlog line:** *"It has no memory between sessions right now."* A
> local assistant without cross-session memory is a materially different product
> from one with it, and that is a decision to have made on purpose rather than
> discovered in a review.
>
> ### The client-side options — the storage half is SOLVED, which is why it is
> ### not where the difficulty is
>
> Already in the tree: **SwiftData** (`SwiftDataLocalSessionStore`, two `@Model`
> types) and **FoundationModels** with `@Generable` structured output.
> **Probed on the shipping toolchain 2026-08-31** (measured, not assumed):
> ```
> NLContextualEmbedding(.english) : AVAILABLE  dim=512 revision=1 hasAssets=true
> NLEmbedding.sentenceEmbedding   : AVAILABLE  dim=512
> ```
> **⟵ SHARPENED 2026-09-02 (the design lane's own measurement — read before quoting the two lines above as availability):** those two readings reproduce on the **Mac host** (macOS 26.6.2, `swiftc` probe) and nowhere else on record. On the **iOS 27 simulator runtime 24A5423a** `NLContextualEmbedding(.english)` reports `hasAvailableAssets=false`, `requestAssets` returns `NLNaturalLanguageErrorDomain Code=8 "Failed to locate embedding model"` and `load()` throws `Code=7 "Embedding model requires compilation"` (3/3 runs) — **not usable on a simulator**; and `NLEmbedding.sentenceEmbedding(.english)` returns **`nil` unless an `NLContextualEmbedding(language:)` was constructed earlier in the same process** (6/6 nil-first, 6/6 works-after; the Mac host has no such dependence). **The device (`whoGoesThere`, 24A5424a) is UNMEASURED for both** — bar 422-C's device arm. "Storage is solved" survives (brute-force 20 k × 512 in 5.7 ms on the M4; no vector DB), but *which* embedder is available is a per-runtime fact, so every stored vector carries an `embedderID` and a lexical scorer is always present. Design doc §3.7(a)/§4.2.
> On-device transformer embeddings, no dependency, no entitlement, no network.
>
> | shape | build cost | fails by |
> |---|---|---|
> | **1. Rolling digest** — model summarizes each session; inject the digests | trivial | **dilution** — everything blurs to mush after ~50 sessions |
> | **2. Extracted facts** — `@Generable` subject/predicate/confidence/source into SwiftData | moderate | **extraction quality** — the real risk |
> | **3. Embedding retrieval over turns** — embed turns with `NLContextualEmbedding`, cosine top-k. **No vector DB**: brute-force over ~20k vectors is milliseconds | moderate | retrieving the lexically-related-but-irrelevant |
> | **4. Hybrid (2 + 3)** — facts answer *"who is Shelley"*, episodes answer *"what did we decide"* | largest | both of the above |
>
> ### 🎯 RECOMMENDED FIRST SHAPE: **3, not 2** — and the reason is this project's own evidence
>
> Sessions are already persisted, so there is **no new capture path**; there is
> **no extraction step, so there is nothing to get wrong**; and retrieval of
> REAL STORED TEXT cannot fabricate the way an extracted "fact" can.
> **#417 measured this model inventing content when it has nothing to say
> (20/40), and measured the fix: give it something real and fabrication goes to
> 0/40.** A memory system that surfaces a WRONG memory is worse than no memory,
> because it launders a fabrication into something that looks retrieved. Shape 3
> has the smallest lying surface. Facts are the better product eventually; they
> are also where the measured failure mode lives.
>
> ### The three hard questions, none of them technical
> 1. **What earns a memory?** A permissive rule floods the store and dilution
>    kills shape 1 and 3 alike.
> 2. **Can the user see and correct it?** Part of Honcho's value is that memory
>    is INSPECTABLE. A silent local store that quietly gets the user wrong is a
>    trust problem, not a feature — and #378 already established that a surface
>    which cannot label its own staleness should not render (#180's family).
> 3. **What happens when BOTH exist?** Local memory plus a host's Honcho is
>    #422's two-store disagreement problem moved inside one device. #159's
>    correction — that the `.md` files may be stale when the provider is Honcho
>    or Mem0 — is the same hazard one layer down.
>
> **Nothing is built and no bars are pre-registered** — this is shape, not a
> lane. A lane opens post-launch with bars written first.

> **✅ CLOSED 2026-09-02 (sweep 14) on Owen's 09-01 mandate — everything off the live board except what he tests.** Closes as PARKED — RULED 2026-08-31 (Owen): both shapes post-launch — (a) client of the host's memory plugins, (b) Talaria's own local memory recorded as a DELIBERATE LAUNCH GAP. Storage solved (`NLContextualEmbedding`); first shape when it opens is embedding retrieval over stored turns, never extracted facts. Listed on the Desk Board §04.

> **🔁 REOPENED 2026-09-02 evening (Owen: "Now that Fable 5.1 has released, I bet we could revisit giving Talaria memory") — moved back from the archive VERBATIM (sweep-14 closing block kept above; #424's set check sees a move, not a drop). Four rulings, AskUserQuestion, all the recommended arm:**
> 1. **What earns a memory — RETRIEVAL + EXPLICIT ONLY.** Two sources, neither inferred: real text retrieved from the user's own stored turns, and notes the user creates by saying "remember that…". The model never decides what is true about the user; it cannot invent a memory that does not exist (#417's 20/40 fabrication finding is the reason).
> 2. **Visibility — LIST + PER-REPLY PROVENANCE.** A Memory screen showing every memory with its SOURCE (the turn it came from, or "you told me on <date>"), edit/delete; plus a small chip on any reply that drew on memory (the #371 provenance shape). Nothing remembered is invisible.
> 3. **Two stores — NEVER MERGED.** Local memory feeds the local brain; the host's memory (Honcho/Hindsight) feeds host turns; the app labels which store a reply drew on. No reconciliation, no silent overrides.
> 4. **Scheduling — DESIGN NOW, DECIDE AFTER THE DOC.** A Fable design lane (read-only + measurement) returns the on-device token budget arithmetic, the shape, and pre-registered bars; Owen rules pre- vs post-launch with numbers in hand. Sunday's post-launch ruling stands until then.
> **Design lane dispatched 09-02; doc lands at `planning/2026-09-02-422-local-memory-design.md`. Bars for any build pre-register HERE after the doc, not before.**

> **📐 DESIGN DOC LANDED 2026-09-02 night (Fable design lane; read-only + measurement, nothing built) — `planning/2026-09-02-422-local-memory-design.md` is CANONICAL; this block is the summary plus the bars verbatim so a build lane can pre-register from here.**
>
> **THE SHAPE, in five lines.** (1) **Capture:** user-authored turns (`.user`/`.voiceUser` only — never assistant, system or `isContextPriming` rows) of LOCAL-ORIGIN threads are chunked (≤ ~60 words; `NLContextualEmbedding.maximumSequenceLength` is **256 tokens**, measured) and embedded at the existing settle seam (`ChatStore.recordLocalOriginAfterSettledTurn`, `:1764/:1781`) — milliseconds per turn, **no `BGTaskScheduler` work** (#63's refresh is discretionary, +15 min at best); one resumable foreground backfill at upgrade. (2) **Store:** a SEPARATE SwiftData container `TalariaMemory` (private `ModelContext` — the main-context trap), three `@Model`s (`MemoryNoteRecord`, `MemoryTurnIndexRecord` with `isExcluded`, `MemoryUseRecord` with `store: local|host`), 2 KB/vector, brute-force cosine (20 k × 512 in **5.7 ms** on the M4 — no vector DB ever); session delete cascades its index rows; `embedderID` on every row. (3) **Retrieval:** hybrid `0.7·cos(sentenceEmbedding) + 0.3·lexicalOverlap` with a RELATIVE, lexically-anchored admission rule and top-k = 3 — because the measurement rules out both halves alone and every absolute threshold (see numbers); skipped on `shortAffirmatives`/anaphors (the #202D interplay); cap `clamp(contextSize/10, 256…2048)` = **800 tokens on 8,192 / 2,048 on PCC**, chunks head-trimmed by `trimmed()` (truncation, never paraphrase — structurally pinned: no `LanguageModelSession` in the memory module). (4) **Injection:** explicit notes → the INSTRUCTIONS block (rebuilt once per note, like the condensed block at `LocalChatBackend.swift:1432`); retrieved chunks → the PROMPT prefix of hit turns only, through #390's one door (a per-turn session rebuild would cost ~1 ms/token × the whole transcript — derived from #206's router latency); `fitsContext` learns to count injected tokens; memory-shaped questions with no hits get the honest string *"No saved memories match this question."* (#417's protective shape); every line is `On <date> you said: "…"`, quoted and dated, never "fact". (5) **Explicit notes:** minimal shape = a DETERMINISTIC closed prefix set (`remember that`, `note that`, `don't forget that`… — `remember to`/`remind me` NEVER match) storing the user's words verbatim before the model runs, with that turn's prefix saying it HAS been saved; the `ActionClaimDetector` gains a `memory` claim kind so *"I'll remember that"* on a turn that saved nothing gets #338's appended correction; the model-mediated `rememberNote` TOOL (card, approval arms, router few-shot, clause extension — all device-measured strings) is the FULLER shape. **Provenance:** optional `Message.memoryProvenance` (#42's rule), a chip beside the brain tag (`ON-DEVICE MEMORY` / `SAVED TO MEMORY` / `HERMES MEMORY · <tool>`), a11y carries the words; the Memory screen (NOTES with *"you told me on <date>"* · RECENTLY USED with the source turn and *Don't use this* · the real index count, toggle, Forget everything) under SESSIONS so #395-D2's positional numbers do not move. **Never merged:** structural — capture is local-origin-only, retrieval is called from `LocalChatBackend` only, a `.host` chip is minted only from an OBSERVED `tool.started` naming a plugin tool (`honcho_*` / `hindsight_*` are Hermes TOOLS — but both plugins also inject via prefetch/`system_prompt_block`, invisible on the wire, so a host reply may draw on memory with no chip and the screen says so, #180).
>
> **THE NUMBERS (provenance in the doc §4).** On-device `contextSize` **8,192** (`whoGoesThere` 24A5424a, 08-28 pcc-surface; the 08-12 `4,096` readings are an `iPad`), PCC **32,768**; reply headroom 1,024/4,096 ⇒ budgets 7,168/28,672; armed instructions **450 tok** (1,841 chars, 4.09 chars/tok) + belt **~1,470** (#229 L0-C) vs toolless **340** ⇒ **5,248 / 6,828 tokens left** for history+prompt+memory on the phone; an 800-token memory block beside the 1,024 condensed cap still leaves ~3,400 tokens of verbatim tail (~40 median exchanges). Prefill ≈ **1 ms/token** derived from #206 (+800 tok ⇒ +0.81 s) ⇒ a full block ≈ +0.8 s, a typical hit turn ≈ +0.5 s, a no-hit turn +0. **Embeddings** (Mac host M4, 2026-09-02): contextual dim 512 / rev 1 / maxSeq 256 / 8.3–19.9 ms per turn; sentence dim 512 / 4.3 ms; **simulator 24A5423a:** contextual NOT loadable (Code=8 on `requestAssets`, Code=7 on `load`, 3/3), sentence **5.3 ms** but `nil` unless a contextual embedding was constructed first (6/6 both ways); **device UNMEASURED for both. Retrieval smoke (16 turns / 12 queries, Mac):** lexical top-1 9/12; sentence-only **7/12 with a NEGATIVE mean gap**; contextual-only 9/12; **hybrid 10/12 top-1, 12/12 top-3**; no absolute cosine separates (sentence relevant-min 0.060 vs irrelevant-max 0.441; contextual 0.785 vs 0.872). **Corpus sizing from a real user (Owen's Mac host `state.db`, read-only, 06-20→09-02):** **836 user turns** in 74 days (≈ 11/day), median **2** user turns per session, p90 6, max 22; user message median **131 chars**, p90 2,702; host `MEMORY.md` 6,567 B / 21 entries. ⇒ ~1,250 vectors today, ~45 k in a decade — brute force stays tens of ms on a phone.
>
> **TWO SCOPES.** **Minimal (pre-launch-shaped): 4 lanes + 2 device evenings ≈ one week at Owen's cadence** — M1 store+capture+embedder+backfill · M2 retrieval + a ≥100-turn/≥40-query labelled corpus (the slow part) · M3 injection + notes + honesty guard · M4 chip + Memory screen + privacy policy + naming pins; device: embedder availability, the fabrication cell contrast, false-claim arm, latency/energy. **Fuller (post-launch): 4–5 more lanes + 3–4 evenings** — the `rememberNote` tool (#202D-style promotion), host-memory chip from observed tool events (needs Owen's Honcho live), INDEX search on the screen, the contextual-embedding upgrade only if device-available AND better on the labelled corpus, assistant-turn corpus only if Owen reopens ruling 1's edge.
>
> **DECISIVE HAZARDS for the schedule ruling (doc §5.3):** (1) embedder availability on the DEVICE is unmeasured — a 10-minute device reading that decides whether the launch claim is semantic or keyword memory; (2) the fabrication-leakage rate (a retrieved QUESTION asserted as fact) is device-only and this brain's disposition to assert is measured (#417); (3) `docs/privacy.html`'s PCC paragraph must name memory — a change to the submission's public claims (#166, #385's shape); (4) prompt-prefix accumulation is a new overflow path on the default tier (#26→#210→#229's lineage), offline-pinnable. **Lane recommendation, held loosely: post-launch, first thing.** Owen rules.
>
> **NOT decided (Owen's, doc §7):** retention · host-tier installs still get local memory on local turns (proposed yes) · assistant turns in the corpus (proposed no) · voice turns (proposed yes) · screen under SESSIONS vs a top-level tile · always-on notes cap (≤ 8 / ≤ 300 tok) and note length cap · card on the deterministic note path (proposed none) · toggle-off semantics · PCC injection at all · 422-F's acceptance number · pre/post launch · whether 422-R's corpus may use real host turns.
>
> **BARS FOR THE MINIMAL SHAPE — pre-registered here VERBATIM from the doc §6, before any code:**
>
> - **422-A (STORE — offline).** A separate `TalariaMemory` SwiftData container with a **private `ModelContext`** (never `mainContext` — the beta-4 SIGTRAP), three `@Model`s, explicit saves, `groupContainer: .none`, `cloudKitDatabase: .none`. Upsert is idempotent by `(messageID, chunkIndex)` — RED-first: the double-upsert pin against a store with no uniqueness. **Deleting a session cascades its index rows in the same save** — RED-first; **mutation M-A:** remove the cascade ⇒ ONLY the dangling-source pin reds. `Message.memoryProvenance` is optional with no hand-written `init(from:)`: `legacyMessageJSONStillDecodes` green, watched RED with the field declared non-optional before it is trusted (296-E's procedure).
> - **422-B (CAPTURE — offline).** Only `.user` / `.voiceUser` messages of **local-origin** threads are indexed; `.hermes`, `.voiceHermes`, `.system`, `isContextPriming == true`, and any message of a non-store-member thread produce **zero** rows — one test per exclusion, each RED-first against an unfiltered capture. Chunks ≤ 60 words on sentence boundaries; a 2,702-char turn (the host p90) yields ≥ 6 rows, a 131-char turn yields 1. Indexing fires from the settle seam and **never** from a keystroke or a streaming delta. Backfill is resumable: kill it mid-run (cursor at N), restart, rows == full run's rows, no duplicates.
> - **422-C (EMBEDDER — offline + device).** *Offline, on the sim:* a test constructs `NLContextualEmbedding(language: .english)` first and asserts `NLEmbedding.sentenceEmbedding(for: .english) != nil` — the 6/6 order-dependence, pinned (the test is deleted the day a runtime makes it pass without the warm-up, and says so). With the embedder forced `nil`, retrieval still answers from the lexical scorer (top-1 ≥ 8/12 on Appendix B's corpus). Every row carries `embedderID`; a row whose id ≠ the live embedder's is never scored (RED-first: a mismatched row scored as if comparable). *Device arm:* on `whoGoesThere`, record for both embedders: constructible, `hasAvailableAssets`, `load()` result, `dimension`, per-turn latency (n=20) — with `osVersion` and build in the artifact. **No number in this lane is quoted without this row.**
> - **422-R (RETRIEVAL QUALITY — offline).** A labelled corpus of **≥ 100 user turns and ≥ 40 queries, ≥ 10 of them no-answer queries**, checked into `planning/reports/` with the run. Bars on the hybrid + relative-admission scorer: **precision@1 ≥ 0.80** on answerable queries; **false-admit rate ≤ 0.10** on no-answer queries (an admit is any chunk passing the rule); top-3 recall ≥ 0.90. Reported over the same denominator, per query class. **Mutation M-R:** lexical-only must score strictly lower on ≥ 1 of the three; if it does not, the embedder buys nothing and is **deleted from the shape** — that is a legitimate outcome, recorded as one, not a bar rewritten.
> - **422-D (BUDGET — offline).** `memoryBlockTokens(contextSize:)` returns 800 / 400 / 2,048 for 8,192 / 4,096 / 32,768 — pinned. The composed block never exceeds the cap (property test over random hit sets). Retrieved chunks are head-trimmed by `trimmed()` with a visible `…` — RED-first that the trimmed text is a **prefix** of the source (no paraphrase, structurally). **Source scan:** no `LanguageModelSession`, `respond(`, `streamResponse(` or `@Generable` token in `Talaria/Services/Live/Memory/` (378-D's shape). `fitsContext` includes `injectedMemoryTokensThisSession`; a synthetic 30-turn conversation with a 3-hit prefix on every turn triggers the accounting rebuild and **never** the #26 overflow retry — RED-first with the accounting removed. `routeTurn` receives `nextPrompt` byte-identical whether or not a prefix exists (3.5).
> - **422-E (EXPLICIT NOTE — offline).** `ExplicitMemoryIntent.parse` matches exactly the pinned prefix set (each form, each case variant); **`remember to …` / `remind me …` / `set a reminder…` never match** — one pin per form; the stored text equals the message minus the trigger, whitespace-trimmed, byte-for-byte; the note exists **before** the turn's session is prepared (ordering pin); the just-saved prefix rides that turn's prompt; the reply carries `savedNoteID`; Undo removes the row and the chip; edit preserves `createdAt` and stamps `editedAt`.
> - **422-H (HONESTY — offline + device).** *Offline:* `ActionClaimDetector` gains the `memory` claim kind; **positive control per 417-D**: it must FIRE on *"Got it, I'll remember that"*, *"I've noted that your sister lives in Austin"*, *"I'll keep that in mind"* and stay QUIET on *"I can't remember things between chats unless you ask me to"* and on any turn where a note WAS saved; the correction text pinned. *Device arm:* n ≥ 40 "remember"-shaped prompts that do **not** match the closed set (e.g. "keep in mind…", "FYI…", "just so you know…"): report `falseMemoryClaim / trials` before the guard and `uncorrectedFalseClaim / trials` after it, one denominator, `unscorable` separate. **Bar: uncorrected = 0/40.** The raw pre-guard rate is a finding, not a bar.
> - **422-F (FABRICATION CELL CONTRAST — device; the decisive number).** Same four-prompt discipline as #417. Arms, n = 40 each, on `whoGoesThere`: **`empty`** (memory-shaped questions, empty store → the honest-empty prefix), **`planted-fact`** (store holds a dated declarative), **`planted-question`** (store holds a QUESTION and a JOKE about the same subject), **`contradiction`** (two dated notes disagreeing). Report `assertedMemory`, `honestRefusal`, `quotedWithDate`, `unscorable` over one denominator per arm; scorer's positive control is the `planted-fact` arm (must assert ≥ 30/40 — a near-zero there means the detector is blind, not the model honest). **Predictions, written first:** `empty` → 0/40 asserted (the #417 fail-nodata shape); `planted-question` → **> 0**, magnitude unknown; `contradiction` → the older value asserted without its date in > 0 replies. Thermal, build, `osVersion`, `routedToollessTrials` recorded (417-E). **This is a CELL CONTRAST, not a production rate (#215).**
> - **422-P (PROVENANCE + SCREEN — offline).** Chip renders iff `memoryProvenance != nil`; `.local` and `.host` render distinct pinned labels and the a11y label carries the same words; the sheet lists every referenced entry with a resolvable source line, and a deleted source renders *"source deleted"* (RED-first against a blank row). Memory screen: every note appears with its date; every `MemoryUseRecord` appears under RECENTLY USED; *Don't use this* sets `isExcluded` and the next retrieval over the same query does not return it (RED-first); the index line shows the real count or `"—"`, never 0 while unknown; Forget everything empties both entities and the screen re-renders empty-honest, not blank.
> - **422-N (NAMING + POLICY — offline).** `NamingSweepTests`: the new Talaria-meaning literals present, `HERMES MEMORY` present as host-meaning, no `"Hermes Memory"` / `"Hermes remembers"` app-meaning literal in shipping sources. `docs/privacy.html`'s PCC paragraph and the PCC screen's copy both name memory — string pins over the file and the view.
> - **422-L (LATENCY + ENERGY — device).** Added wall-clock on a 3-hit turn vs a no-hit control, n = 10 each, same prompt family (prediction ≤ 1.0 s from the ~1 ms/token derivation); per-turn embed latency (prediction ≤ 30 ms); the #398-style energy row over a 20-turn run with and without memory; backfill total CPU time logged once. Numbers with `osVersion`, thermal, build.
> - **422-GATE.** `scripts/mac/lane-gate.sh` PASS with the test count moved, runtime named on the verdict line, Release build clean (#218), `TALARIA_SIM_NAME` from the fixed pool, ≤ 3 booted.

> **📏 2026-09-02 20:43 — 422-C's DEVICE ARM MEASURED (whoGoesThere, `Version 27.0 (Build 24A5430a)`, corded `xcodebuild test`, a recording probe on throwaway branch `422-device-probe`, never merged).** Verbatim: `contextual=[constructed hasAssets=false requestAssets=NLContextualEmbeddingAssetsResult(rawValue: 0) load=ok tokens=10 dim=512] sentence=[ok dim=512 vectorCount=512 rev=1]`. **Both embedders load on the device.** Two facts the design must carry: (1) `NLContextualEmbedding(.english)` had NO assets on the phone until `requestAssets()` fetched them — first use is an ON-DEMAND DOWNLOAD (a network dependency the privacy copy names, and a cold-start path the Memory screen must show honestly — "downloading the on-device embedding model"); (2) the sentence embedder returned a real 512-vector in the same process order the sim needed (contextual constructed first) — the warm-up construction pinned by 422-C stays. The 08-31 "AVAILABLE" line is now a DEVICE fact, not a host reading. The doc's §4.2 "UNMEASURED" is superseded by this block; the hybrid scorer is the shape, not the lexical fallback.

> **⚖️ RULED 2026-09-02 evening (Owen): "It should probably ship BEFORE LAUNCH if we have the time. With Fable 5.1, I don't see why not."** Sunday's post-launch ruling is REVERSED to pre-launch-if-time, with the measured numbers in hand (8,192-token window · 800-token cap · both embedders live on the phone · hybrid 12/12 top-3 · ~one week minimal). Owen asked for **a written PLAN to start a NEW SESSION from** — lands at `planning/PLAN-2026-09-02-422-LOCAL-MEMORY.md` (the execution contract: lanes M1–M4 with bars, the device evenings, the decisions that gate each lane, the session rules). The design doc stays canonical for the shape.

> **📋 2026-09-02 evening — THE EXECUTION PLAN IS WRITTEN: `planning/superpowers/plans/2026-09-02-422-local-memory.md`** (writing-plans shape: header with the required sub-skill, global constraints = the four rulings + the standing rules + the §7 defaults to confirm at session start, a session contract, the file structure, 17 bite-sized RED-first tasks across lanes M1 store/capture · M2 retrieval + corpus · M3 injection/notes/honesty · M4 chip/screen/policy, and the two device evenings DE1 (422-H device arm + 422-L) and DE2 (422-F, the decisive number). Owen starts a NEW session from it. 422-C's device arm is already MET, so no evening is owed for it. The policy sentence (Task 17) is a public claim — its PR HOLDS for Owen's read of the exact wording, the #390-F precedent.


> **⚖️ RULED 2026-09-02 (Owen, one AskUserQuestion at the build session's start — the plan's session-contract step 1; the §7 defaults the plan builds are now his, not the doc's):** **retention = NEVER** (Forget-everything is the only reset; no age-out field in the schema) · **toggle OFF stops retrieval AND indexing** (the index is kept until Forget everything) · **the 422-R corpus MAY use Owen's real host turns** (read-only from the Mac `~/.hermes/state.db`, the one default he overruled — synthetic was the recommended arm) · **every other §7 default accepted as a block:** host-tier installs still inject local memory on local turns · assistant turns EXCLUDED · voice turns INCLUDED · Memory screen under SESSIONS · notes cap 8 / 300 tokens, note length 500 chars with a visible notice · no card on the deterministic note path · memory IS injected on PCC with the policy line · 422-F's acceptance number is Owen's after the first cell contrast. Build session runs subagent-driven from the plan with merge-on-green authority; lanes M1→M4 on per-lane branches, the corpus chore (Task 6) in parallel with M1.

> **🔬 2026-09-02 night — 422-C's OFFLINE MECHANISM CORRECTED by the build lane (M1 Task 3 reds, then a 3-arm in-bundle probe on sim 24A5423a): the "contextual warm-up" is a MIS-ATTRIBUTION.** Inside the app test bundle `NLEmbedding.sentenceEmbedding(for: .english)` returns `nil` on the FIRST call in a process (log: `Unable to locate Asset for sentence embedding model for local en`) and the 512-dim embedder on every later call — five identical plain calls, nothing else in the process: R1 nil, R2–R5 512. The 09-02 "6/6 nil unless an `NLContextualEmbedding` was constructed first" reading came from an UNSANDBOXED `simctl spawn` probe that interposed a construction between call 1 and call 2 and never discriminated them; in-bundle the contextual path is dead on the sim (`requestAssets` → code 8, `load` → code 7, no network) and is not needed. **Consequence for the bar:** 422-C's offline arm is met by a synchronous first-call RETRY, not a construction — the test pins the retry and is deleted the day a runtime's first call returns the embedder. **Not a falsification of the shape** (the embedder is available in-bundle with the retry; the hybrid scorer stands); the design doc §3.7(a) and Appendix A carry dated corrections. **Owed to DE1:** whether one retry suffices on the DEVICE from a cold (never-downloaded) asset — the 20:43 device reading ran contextual-first, so the device's sentence-only cold path is unmeasured.

> **✅ LANE M1 RESULT — store + capture + embedder + toggle + backfill (2026-09-02 → 09-03, subagent-driven from the plan; branch `422-m1-store-capture`, squash SHA `6b52bedc`, GitHub PR #422 — the same number as this tracker item, by coincidence; disambiguate). Bars 422-A, 422-B, 422-C (offline arm): MET. 422-GATE: MET for this lane.**
>
> - **422-A (store) — MET.** `TalariaMemory` is a separate `ModelConfiguration` (`groupContainer: .none`, `cloudKitDatabase: .none`), private `ModelContext(container)` — never `mainContext` — three `@Model`s (`MemoryTurnIndexRecord` with `isExcluded`, `MemoryNoteRecord`, `MemoryUseRecord`), explicit saves, every fetch logged on failure. RED-first: compile-fail RED → 2/2 GREEN. **Mutation M-A** (cascade delete line removed): ONLY `deletingASessionCascadesItsIndexRows` reds (`indexCount() → 2`), idempotency pin stays green; restored green. Upsert idempotent by `(messageID, chunkIndex)` — via an explicit fetch, NOT `@Attribute(.unique)` (which keys `entryID`, a fresh UUID per row). `Message.memoryProvenance`'s decode pin is M4's (Task 14), not this lane's.
> - **422-B (capture) — MET, one caveat.** `MemoryChunker` verbatim on sentence boundaries, ≤ 60 words counted by ANY whitespace (a fix round: the plan's `split(separator: " ")` undercounted tabs/newlines), over-cap single sentences split on word boundaries with a word-conservation pin (the stride mutation failed CONSERVATION, not the cap — the failure a cap-only test cannot see). `MemoryIndexer` indexes `sender.isUserAuthored` (`.user`/`.voiceUser` — the #275 predicate, better than the plan's literal) and never `isContextPriming`; **one pin per exclusion** (`.hermes`, `.voiceHermes`, `.system`, priming, NON-STORE-MEMBER THREAD through the seam), each RED-verified (priming-guard mutation → only its pin reds; hoisting the index call above the membership `if` → only the non-member pin reds, `indexCount() → 3` host rows leaked). Indexing fires ONLY from `ChatStore.recordLocalOriginAfterSettledTurn` (both upsert sites) — never a keystroke or delta. A 60×8-word turn (~2,700 chars, the host p90) yields ≥ 6 rows; a one-sentence turn yields 1. **Beyond the plan, from review:** indexing is INCREMENTAL (one `reconcileSession` fetch per settle returns the already-indexed message ids; only new messages are chunked/embedded — the plan's whole-thread re-embed per settle was quadratic on the MainActor) and the same reconcile DELETES rows whose message left the conversation (retry/undo/regenerate — a ruling-2 dangling-source gap the plan missed). Backfill is resumable and lives in a testable `MemoryBackfillRunner` (one low-priority `Task` after launch; sessions walked OLDEST-FIRST with an `id` tie-break so a new session appends rather than shifting the cursor; one conversation per yield; cursor persisted in `UserSettings.memoryBackfillCursor`): a toggle flipped OFF mid-run STOPS WITHOUT ADVANCING past unread history (RED-first — the first wiring advanced the cursor on refusal and would have skipped the rest forever), resume finishes with a full run's count and no duplicates, an over-large stored cursor is clamped AND persisted (the test found the clamp was never written back), and ONE repair pass per run re-embeds rows stored with an empty vector (a turn indexed before the embedder acquired), bounded at 200, batched into one save. **Caveat:** the walk-away persist path (`persistDepartingLocalSession`) does not index — a user turn whose reply never settles is not captured (deliberate; filed as a deferred minor).
> - **422-C (embedder, OFFLINE arm) — MET, with the MECHANISM CORRECTED (see the 09-02 night block above).** In-bundle on sim 24A5423a the sentence embedder's FIRST call returns nil and later calls return 512 dims; `EmbeddingService` acquires with a plain call + one retry at init and RE-ATTEMPTS ON EVERY `embed` while nil (seam-tested: [nil, real] → init acquires, `calls == 2`; [nil, nil, nil, real] → third embed succeeds, `calls == 4`; each RED-verified by deleting the respective retry). The availability pin polls up to 3 s and PRINTS the observable number: `422-C: first vector after N acquisition attempt(s), M ms` — measured **2 and 4 attempts** on two runs (init's two attempts can BOTH fail; the self-heal then acquires), so the deletion condition ("clean-build runs print 1 attempt consistently") is far off. One 1-in-6 fresh-build flake before the window existed (three nil attempts in 3 ms — a cached negative); 3/3 clean builds green after. `embedderID = "nl.sentence.en.r1"` on every row; the foreign-id "never scored" pin is M2's (Task 7). `decode` is copy-based with a malformed-length guard (the plan's `bindMemory` on `Data` was alignment-UB and truncated silently). **Owed to DE1:** does one retry suffice on the DEVICE from a cold asset (every number here is sim 24A5423a).
> - **Toggle (Owen's ruling: OFF stops retrieval AND indexing, index kept):** `UserSettings.memoryEnabled` (default true, `decodeIfPresent ?? true`, legacy-JSON pin), read live on EVERY index/backfill call; OFF → zero rows AND zero embedder construction (both pinned), existing rows untouched. **The retrieval half is pinned in M3 when the call exists.** No user-reachable control until M4's Memory screen.
> - **VOID by plan-vs-code (found before Task 5): the plan's "wire `MemoryStore.deleteSession` beside the existing session delete" has NO HOOK SITE — `LocalSessionStoring` has no delete verb and `SessionsDrawer` only pins and archives.** Nothing was invented; the cascade stays a tested store method and wires the day a delete verb lands (the backfill cursor indexes an ORDER, not identities — revisit then).
> - **422-GATE — MET on the FINAL bytes:** **`GATE: PASS on 24A5423a`, first run, no flake**, Swift Testing **2856 → 2912** (+56 = exactly this lane's tests, in three counted steps 2896 → 2906 → 2912; the main baseline proven by an empty `git diff … -- TalariaTests/`), XCUITest **15** unchanged, Release build clean, `project.pbxproj` no drift. (An earlier gate on the pre-fix bytes hit the #219 XCUITest flake once — `XFLAKE pre hittable=false`, byte-identical to the archived occurrences — and passed on the identical-bytes re-run; that run is superseded by this one.)
> - **Whole-lane review before merge (Opus, whole branch vs main): MERGE AFTER FIXES → fixed in one wave and re-gated:** the repair loop no longer writes to a model deleted during a `Task.yield` (guard `!isDeleted && modelContext != nil` — the reviewed `isDeleted`-only guard was BLIND on 24A5423a, where a saved delete UNREGISTERS the object rather than flagging it; the deterministic test caught that and pins tolerance of a mid-yield reap, not a reproduced exception), the cursor persists every 10 conversations + at the end instead of JSON-encoding the whole `UserSettings` blob per conversation, `upsertTurnChunks` fetches once per batch instead of once per chunk, empty-vector rows carry `embedderID == ""` (never the live id they did not use), and the mis-applied `// harness-visible` tag is gone. **First-backfill cost measured on the sim (synthetic corpus, ~50 conversations): `422-B backfill: 50 conversations / 100 rows in 541 ms on Version 27.0 (Build 24A5423a)` (≈ 5 ms per row incl. embedding, one `Task.yield` per conversation)** — a sim number, not a phone number. **⚖️ RULING NEEDED (Owen): a build cut from `main` between M1 and M4 would index every local turn with NO toggle UI and NO eraser** (the Memory screen + Forget everything are M4; `memoryEnabled` defaults on and is unreachable) — either no build ships from `main` until M4 lands, or M4's toggle row lands first. **Plan notes for M2–M4 (recorded, not built):** keep the lazy embedder factory · the incremental index assumes user-message content is immutable (true today) · the positional cursor must become a `createdAt` high-water mark when a session-delete verb lands · **voice-only threads never become local-session members (#190B counts `.hermes`), so "voice turns INCLUDED" is reachable only through the next settled TEXT turn of a mixed thread** — Owen's ruling is partly unreachable as the seam stands · "every row lexical" is a normal state (stranded rows, non-English users) — M2 keys admission on the vector, not the id.
> - **Process notes:** every task RED-first with the review loop (5 tasks, 5 fix rounds total, nothing parked); Task 3 spent a 3-arm time-boxed probe on the embedder before any consequence went to Owen; the 20-real-turn corpus (Task 6) merged to main separately (`0f9484ae`). **Deferred minors for the final whole-branch review:** `indexCount()` still `try? … ?? 0` (a fetch failure reads as empty); `EmbeddingService` isolation undeclared (embed runs on the MainActor from the indexer); stop-list gaps dilute the lexical fallback (`from/can/get/will/just`, apostrophe fragments, CJK → empty tokens); malformed-blob log dedups per process.

> **🛑 2026-09-03 — LANE M2 STOPPED AT BAR 422-R: TWO PRE-REGISTERED RESULTS FALSIFY PARTS OF THE SHAPE (Task 7, branch `422-m2-retrieval` @ `98b42e5d`, NOT merged; per the plan's contract §4 the bar is filed, not redefined, and the consequence goes to Owen).** Corpus: 104 turns / 87 queries (answerable n = 75, no-answer n = 12 — all twelve adversarial near-misses by construction). Hybrid `0.7·cos + 0.3·lexical`, relative admission `z = 1.5`, lexical anchor (the brief's top-2 % clause DROPPED — it re-admitted the pure-cosine artifacts, 12/12 false admits with it vs 9/12 without): **p@1 0.827 (62/75) ✅ · false-admit 0.750 (9/12) ❌ vs ≤ 0.10 · top-3 recall 0.920 (69/75) ✅.** **Mutation M-R (lexical-only, `0/1`): p@1 0.853 · false-admit 0.750 · top-3 0.973 — strictly lower on NONE of the three; better on two.** So by the bar's own pre-registered consequence **the embedder buys nothing**: with the anchor requiring a lexical hit, cosine never ADMITS, it only re-ranks — and `NLEmbedding.sentenceEmbedding` re-ranks worse (it scores interrogative form heavily; the design's 16-turn smoke reading did not see this). **The false-admit clause is UNREACHABLE, not missed:** an exhaustive ≈ 15 k-configuration search over the scoring family (weightings × z × lexical thresholds × runner-up margin × absolute cosine floors × IDF anchors × exact/stemmed tokens; Mac twin reproduced the in-bundle numbers exactly) tops out at **p@1 0.560 under false-admit ≤ 1/12** — the three clauses are jointly infeasible on this corpus. Pareto (hybrid): z 1.0 → .827/.750/.947 · 1.5 → .827/.750/.920 · 3.0 → .627/.333/.667 · 3.5 → .520/.167/.520. A light suffix stemmer moves the ceiling .493 → .560 and the frontier .693 → .760 at fa .25 (+~0.07 p@1) — NOT made, it is a tokenizer change outside the bar's two sanctioned levers. `shouldSkip`'s `contentTokens < 2` was wrong both ways (let "another one" through, skipped 4 answerable queries) → an exact anaphor set. **Two things this does NOT measure:** the production false-admit rate (the no-answer class is adversarial, so 0.750 is a worst case) and whether a false admit HARMS a reply (the 422-F device arm's question). **Rulings put to Owen 2026-09-03:** (1) delete the embedder from the shape (lexical-only memory; retires `EmbeddingService`, the vector column, the backfill repair pass and bar 422-C's mechanism) or keep it; (2) the false-admit bar — accept the worst-case miss with the chip + quoted-dated framing as the safeguard and measure a production-shaped no-answer class, trade recall for precision, or re-scope; (3) authorize the stemmer. Lanes M3/M4's retrieval-INDEPENDENT tasks (budget, explicit notes, honesty guard, provenance, screen, policy) proceed meanwhile; Task 10 (injection) waits on the ruling.

> **⚖️ RULED 2026-09-03 (Owen, AskUserQuestion — all three the recommended arm): (1) THE EMBEDDER IS DELETED FROM THE SHAPE.** Local memory is LEXICAL: `EmbeddingService`, the `vector`/`embedderID` columns, the backfill's re-embed pass and bar 422-C's mechanism are retired (422-C is SUPERSEDED by this ruling, not falsified — both embedders DO load on the phone; they just buy nothing on the labelled corpus). The launch claim is keyword memory. **(2) THE FALSE-ADMIT MISS IS ACCEPTED for the pre-launch shape:** relative admission ships as measured; the chip, the quoted-and-dated framing and the honesty guard are the safeguard; the corpus gains a PLAIN no-answer class (~20 unrelated questions) and 422-R reports BOTH rates (adversarial and plain) — **Owen sets the acceptance number on the plain class after seeing it** (422-F's protocol); whether a false admit harms a reply is 422-F's device question. **(3) THE STEMMER IS AUTHORIZED** (a light suffix stemmer in the content tokenizer; re-measured numbers go in the M2 RESULT block). Lane M2 resumes as: lexical retriever + stemmer + plain class → embedder deletion → gate → merge. **Also recorded from M3 Task 9: the plan's `memoryBlockTokens = clamp(contextSize / 10, 256…2048)` yields 819/409 for 8,192/4,096, contradicting its own pinned 800/400 — the code floors the tenth to a whole hundred before the clamp (800/400/2048 as pinned); the formula line in the plan/design is the stale claim.**

> **✅ LANE M2 RESULT — retrieval, the labelled corpus, and the embedder's deletion (2026-09-03; branch `422-m2-retrieval`, squash SHA `0bf0af66`, GitHub PR #423). Bar 422-R: MET as RULED (see the 09-03 ruling block); bar 422-C: RETIRED with the embedder; 422-GATE: MET for this lane.**
>
> - **The corpus (Task 6, merged earlier as `0f9484ae`, extended in this lane):** 104 turns (16 Appendix B · 20 of Owen's real host turns, read-only from the Mac `state.db` copy, privacy-filtered — one phone number excluded — · 68 synthetic), **107 queries** (75 answerable, each with exactly ONE relevant turn — independently re-verified by a reviewer reading all 75 pairs · 12 ADVERSARIAL no-answer near-misses · 20 PLAIN no-answer questions sharing no content token with any turn). `planning/reports/2026-09-02-422-retrieval-corpus.json`, `meta.classCaveat` records that 3 of the 12 "adversarial" queries meet the plain definition.
> - **The measurement that changed the shape (Task 7, hybrid as designed):** p@1 **0.827** (62/75) · false-admit **0.750** (9/12) · top-3 **0.920** (69/75). **Mutation M-R (lexical-only): 0.853 · 0.750 · 0.973 — strictly lower on NONE; better on two.** With the lexical anchor in place the cosine term never admits, only re-ranks, and `NLEmbedding.sentenceEmbedding` re-ranks worse (interrogative form scored heavily; the design's 16-turn smoke reading could not see it). The false-admit clause was **jointly infeasible** with p@1 ≥ 0.80: an exhaustive ≈ 15 k-configuration search over the scoring family (Mac twin reproduced the in-bundle numbers exactly) tops out at p@1 0.560 under fa ≤ 1/12. The brief's top-2 % anchor clause was dropped (12/12 false admits with it vs 9/12 without); `shouldSkip`'s token-count threshold was wrong both ways and became an exact anaphor set. **STOPPED and filed per the contract; Owen ruled (09-03): embedder deleted · miss accepted + plain class · stemmer authorized.**
> - **Shipped (Tasks 7b/8b): LEXICAL-ONLY retrieval** — `LexicalTokenizer` (content tokens, 40-word stop list, light suffix stemmer iterated to a FIXPOINT after review caught plurals stemming one derivation short of singulars: `mornings→morning` but `morning→morn` — 11 such pairs in the corpus), `lexicalOverlap` = fraction of the query's content tokens present in the chunk; `MemoryRetriever.retrieve(query:candidates:topK:z:)` with relative admission (`z = 1.5` over the candidate set's sample sd) + lexical anchor, a **small-store FALLBACK — when relative admission admits nothing and the store holds fewer than 8 rows, anchored rows with score > 0 are admitted** (with sample-sd z-scoring the max attainable z is (n−1)/√n, which first reaches 1.5 at n = 4 for a lone outlier and only at n = 8 for two equal matches, so the first-run store could never retrieve; a fixed n < 4 branch merely moved the cliff — RED-first pins at n = 1/2/3/5/7, and the n ≥ 8 behaviour of the relative rule alone is pinned honestly), a DETERMINISTIC tie-break (score, then `sentAt` newest-first, then `chunkIndex`, then `entryID` — 13/75 answerable queries tie at rank 1, and under adversarial ordering top-3 could read 0.893), top-k 3 de-duplicated by adjacent chunk (the de-dup test was VACUOUS on its first fixture — nothing was admitted — and was made load-bearing; likewise the incremental-skip pin, which could not fail on the mutation it named, became a tamper-survival pin that reds with the skip removed). **Final numbers, stemmer on, deterministic order: p@1 **0.800** (60/75 — ON the bar, zero margin: the tie direction alone moves it 0.800 ↔ 0.867, and newer-wins was chosen on principle because the corpus's `sentAt` is synthetic) · top-3 **0.947** (71/75) · false-admit PLAIN **0/20** · false-admit ADVERSARIAL **9/12**.** Stemmer ON vs OFF: a wash (+1 p@1 / −1 top-3). **The plain-class 0/20 is TRUE BY CONSTRUCTION under a lexical scorer** (the class is defined as no shared content token; a lexical scorer admits only on shared content tokens) — it would have been a real measurement one day earlier (5 of the hybrid's 12 false admits were pure-cosine artifacts with zero overlap) and now earns its keep as a regression guard, pinned by a test that asserts the class definition itself. **Owen sets the plain-class acceptance number after seeing it — the number to rule on is 0/20 with that caveat; the adversarial 9/12 (= 9/9 of the genuine near-misses) is the worst case, un-gated.**
> - **The embedder DELETED from the shape (Task 8b):** `EmbeddingService`, the `vector`/`embedderID` columns on both models, the backfill's repair pass, the acquisition instrumentation and `EmbeddingServiceTests` are gone; rows are text-only; `MemoryStore.candidates()` (non-excluded rows) and `setExcluded(entryID:_:)` added RED-first. Bar 422-C is retired, not falsified: both embedders DO load on the phone (09-02 device arm) and the in-bundle first-call-nil mechanism was measured and corrected (09-02 night block); they buy nothing on the labelled corpus. Deletion inventory: `EmbeddingService.swift` → `LexicalTokenizer.swift` (tokenizer only), `EmbeddingServiceTests.swift` deleted, the acquisition/repair/empty-vector pins deleted (2 net tests fewer), `AppContainer` embedder bits removed, doc comments cleaned.
> - **422-GATE — MET on the final bytes:** `GATE: PASS on 24A5423a` (run 1 failed on the #219 XCUITest flake only; identical-bytes re-run — and NOTE a process finding: `lane-gate-classify.sh` prints "ASSERTION TEXT PRESENT — do NOT re-roll" on the very test the protocol grants a re-run for; the two instructions contradict at the deciding moment — a `scripts/mac` chore) — Swift Testing **2910** (reconciled exactly: 2912 on main − 2 net after the deletions and the fixes' additions), XCUITest 15 unchanged, Release build clean.
> - **Still open from this lane:** the retrieval half of the memory toggle (pinned in M3 Task 10 when the call exists); 422-F's device arm decides whether a false admit HARMS a reply (DE2). **Deferred minors:** `shouldSkip` re-implements `isShortAffirmative`'s normalization; stop-word filtering runs before stemming (`donned → don`); `doing`/`being` never stemmed.

> **⚖️ RULED 2026-09-03 afternoon (Owen, AskUserQuestion — all four the recommended arm): (1) RELEASE GATE — NO BUILD SHIPS FROM `main` UNTIL LANE M4 LANDS** (the Memory screen, the toggle UI and Forget everything): M1 indexes silently and M3 injects retrieved quotes/notes and can append a correction with no user-facing surface, so OTA/TestFlight builds stay on the pre-#422 baseline or wait for M4 (whose PR is held for the policy read anyway). **(2) THE HONESTY GUARD STAYS QUIET WHEN MEMORY IS OFF** — with the toggle off, `memoryCreation` claims are not corrected at all (the app made no promise either); no off-state string. **(3) 422-R's p@1 = 0.800 (60/75) IS ACCEPTED AS THE BAR** — the assertion stays; a future red is a real signal, not noise (the synthetic-`sentAt` tie-break caveat stands as recorded). **(4) THE PLAIN NO-ANSWER CLASS KEEPS ≤ 0.10 AS A REGRESSION GUARD** — true by construction under a lexical scorer today, it fails the day a semantic term or a looser tokenizer returns; the adversarial 9/12 stays reported and un-gated; whether a false admit HARMS a reply is 422-F's device question.

> **✅ LANE M3 RESULT — injection, explicit notes, honesty (2026-09-03; branch `422-m3-injection-notes-honesty`, squash SHA `f0325302`, GitHub PR #424). Bars 422-D, 422-E, 422-H (offline arm): MET. 422-GATE: MET for this lane.**
>
> - **422-D (budget) — MET (Task 9).** `MemoryBudget.memoryBlockTokens(contextSize:)` returns **800 / 400 / 2048 / 256** for 8,192 / 4,096 / 32,768 / 1,024 — by flooring the tenth to a whole hundred BEFORE the clamp: **the plan's bare `contextSize / 10` yields 819/409 and contradicts its own pinned numbers** (the stale claim is the formula line; the numbers were always the bar). Hits are head-trimmed through the REAL `LocalIntelligenceService.trimmed(_:toTokenBudget:)` — RED-first prefix pin: a trimmed chunk ending in `…` is a prefix of its source (truncation, never paraphrase, structurally); `trimmedHits`/`fits`/the capped `composeNotesBlock` are `@MainActor async` taking the injected service because `trimmed` is an async instance method on a `@MainActor` class (the brief's static sketch was impossible); the pure composers stay pure. A 50-iteration property test over random hit sets (5–400 words, crossing the 100-token per-hit cap) never exceeds the 8,192-window cap using the codebase's own estimator — no second estimator. Notes cap **8 / 300 tokens** pinned. Pinned strings verbatim: `## Things the user asked you to remember` + the disagreement instruction, `## From your earlier chats (quoted, may be out of date)`, `On <date> you said: "…"`, `No saved memories match this question.`, the just-saved prefix.
> - **422-D (injection) — MET (Task 10).** Explicit notes ride the INSTRUCTIONS block (`instructionsWithMemoryNotes` folded into `sessionBlueprint`'s base instructions on both exits, so every budget path counts them; the live session is rebuilt exactly ONCE per note change, never per turn — pinned by spying `session = nil`); retrieved hits, the just-saved prefix and the honest no-match line ride the hit turn's PROMPT PREFIX through #390's one door (`memoryPrefix(for:)` → `composeTurnInput`/`makeTurnPrompt`), applied AFTER `preparedSession` and AFTER routing — `routeTurn` receives `nextPrompt` byte-identical with or without a prefix (the ordering witness reds when `send` prefixes early). Retrieval is called ONLY from `LocalChatBackend` (ruling 3 structurally: `MemoryStructuralPinsTests` greps the module for model tokens and `SessionsHermesClient*` for memory tokens — both watched RED by planting a token). Toggle OFF ⇒ no retrieval, no notes block, no prefix (six pins; the mutation that ignores the toggle reds all six). Memory-shaped question with no hits ⇒ the prompt opens with `No saved memories match this question.`; an ordinary no-hit turn has no prefix. `fitsContext` counts `injectedMemoryTokensThisSession`; the accounting rebuild fires at `min(1,500, contextBudget/4)` accumulated prefix tokens (exactly 1,500 on the phone's window, proportional on smaller ones — a flat 1,500 is unreachable there) and the synthetic 30-turn × 3-hit conversation triggers it and NEVER the #26 overflow retry (RED with the accounting removed: 25 runaway issues). `MemoryStore.recordUse`/`recentUses(limit:)` record every reply that drew on hits or notes (`ChatStore` reads them; the `Message.memoryProvenance` STAMP is owed to lane M4, which owns the type). **No real turn ran (the simulator cannot generate on this model) — the first device evening reads the `memory: injected N hit(s) + M note(s)` notice.** **Two honest labels from the review:** bar (b)'s "never the #26 overflow retry" half is UNFALSIFIABLE in this harness (`overflowRetryCount` moves only from the `respond`/`streamResponse` catch blocks the synthetic test never drives) — the accumulation bound is measured, the overflow half is OWED TO THE DEVICE; and the REBUILD CADENCE is unmeasured — at ~330 prefix tokens per retrieving turn the 1,500 threshold rebuilds the session roughly every 4–5 such turns, re-prefilling the transcript (the ~1 ms/token cost the design refused to pay per turn) — 422-L measures it. The current turn's own prefix was invisible to its fit check (one unaccounted ~330-token block per generation) — fixed by reserving one memory block in `fitsContext` when memory is on (pinned as a CONTRAST: two backends differing only in the toggle, the transcript grown until ON stops fitting while OFF still does), and the just-saved notice now counts against the block cap (notes + notice + hits ≤ one cap; the notice is never trimmed — the hits give way). **Number correction (close-out): with memory ON the phone's effective prompt budget is 6,368 tokens (7,168 − the 800 reserve), so the design doc's "5,248 / 6,828 left" line is the stale claim.** Notes land BEFORE the condensed block rather than after its preamble (an undeclared improvement: the brief's placement would have missed `sessionBlueprint`'s early return and `fitsContext`). Accepted: a mid-turn rebuild undercounts one prefix; `recordUse` fires on notes-only turns (RECENTLY USED will be dense until the screen filters).
> - **422-E (explicit notes) — MET (Task 11).** `ExplicitMemoryIntent.parse` matches exactly the seven pinned prefixes (each form pinned, case-insensitive on the trigger, the BODY's case preserved verbatim; apostrophe variants folded for matching only — iOS Smart Punctuation types `’`, so the plan's straight-quote `don't forget that` was unreachable on the phone until the review caught it); `remember to …` / `remind me …` / `set a reminder…` never match (mutation: making `parse` accept `remember to ` reds ONLY `reminderShapesNeverMatch`); stored text == message minus the trigger, whitespace-trimmed, byte-for-byte; the 500-char cap is on Characters (grapheme-safe) and `parseResult` reports `truncated`, stored on the row as `wasTruncated` (the visible notice is the Memory screen's, lane M4) — the plan's own cap test was non-discriminating (`x`×900 makes head- and tail-truncation indistinguishable) and was fixed. `MemoryStore` note CRUD (`insertNote`/`deleteNote`/`updateNote` keeps `createdAt` + stamps `editedAt`/`allNotes` newest-first with a total order/`note(id:)`/`note(forSourceMessageID:)`/`deleteNotes(withSourceMessageIDs:)`) through `fetch(_:op:)`, explicit saves. **Capture is in `ChatStore`'s send path BEFORE dispatch** (the ordering pin spies the backend: the note count is already 1 when the turn is prepared); toggle OFF stores nothing. **The just-saved fact is a STORE fact, not a text fact — the first cut re-derived it from the message and would have fired with the toggle OFF, with no store, and on every VOICE turn (the voice pipeline bypasses ChatStore's capture), silencing the honesty guard on exactly the fabrications it exists for; the review caught it.** Now `LocalChatBackend.savedNoteThisTurn(clientMessageID:)` = memory enabled AND a note row whose `sourceMessageID` is this turn's `clientMessageID` (the id already crosses the protocol; voice ⇒ no row ⇒ nil ⇒ the guard FIRES); both production `honestyGuardedReply` call sites pass `savedNote: turnInput.savedNote != nil` and are WITNESSED by source-grep pins (hardcoding either kept 162 tests green before). Undo removes the note through the public `truncateTranscript(from:reason:)` (the `/undo` primitive) — and `retryMessage`, which bypasses it (#279), was DUPLICATING the note; cleanup is now keyed on the removed rows' `sourceMessageID`s from both paths. **Owed to Task 16 (lane M4 owns `Message.memoryProvenance`):** stamping the reply with `.local(savedNoteID:)` from `ChatStore.pendingSavedNoteID`. **Deferred:** notes are not gated by local origin (a note captured on a host thread names a server session); paired-thread rows lack `clientMessageID`, so Undo can miss there; a swallowed re-send restores rows but not the note; VOICE never saves a note (honest now, unwired).
> - **422-H (honesty, OFFLINE arm) — MET (Task 12).** `ActionClaimDetector.ClaimKind.memoryCreation` (`isLicensedByAnyToolCall: false` — vestigial in the licence path because the `savedNote` short-circuit returns first; commented), `unfulfilledClaim(in:executedToolNames:savedNote:)` (the brief's `executedCalls:` label never existed), both `honestyGuardedReply` overloads take `savedNote:`. **Positive controls per 417-D FIRE:** "Got it, I'll remember that." · "I've noted that your sister lives in Austin." · "I'll keep that in mind." **Quiet:** "I can't remember things between chats unless you ask me to." and every turn where a note WAS saved (`savedNote == true`). Correction text pinned verbatim; appended, never rewriting (#338). **The review's phrase battery caught two false-positive surfaces and one hole, all fixed RED-first (11 red cells → 0 on a real before/after run):** the first-person `i` + `remember` + noun row fired on RECALL ("I remember that your sister lives in Austin." — an ACCURATE recall would have got a false correction, #338's own worst case) → the verb set is split into PROMISE verbs (`remember`, reachable only from `i'll`/`i will`) and WRITE verbs (`noted`/`saved`, every frame); the passive tier had no noun gate ("Your changes have been saved." / "Your reminder has been saved." got the MEMORY correction) → a memory noun is required at the SUBJECT step; "I won't forget that." / "I'll never forget that." were silenced by the negation silencer → a narrow, quote-stripped exemption for the `won't|will not|never` + `forget` + object frame, every other negation still quiet. `ActionClaimDetectorTests` and `HonestyGuardWiringTests` are byte-untouched except one exhaustive-`switch` arm the compiler forced (`.memoryCreation` in the must-never-be-licensed partition). **Known limits (recorded, not fixed):** "Your preference has been saved." misses (`preference` ∉ memory nouns); the exemption is sentence-wide (a mixed device+memory sentence takes the memory copy); a memory claim on an ACTION-tool turn is silent (338-D's floor returns first); `honestyGuardLogLine` still prints the tool-call count and the `(#338)` key for a `memoryCreation` fire — #338-scoped decisions. **Archived #338's "one string serves every `ClaimKind`" is now false as a description of the code — an append-only pointer block sits under the archived entry (#317(a)); Owen's 2026-08-15 one-string ruling for `impersonatedCard` is untouched.**
> - **422-GATE — MET on the final bytes:** `GATE: PASS on 24A5423a` on roll 2 (roll 1 failed ONLY on the #219 XCUITest flake, `testConnectedRelaunchSkipsTheConnectEntry`, identical-bytes re-run per protocol — and for the second lane running the classifier printed "ASSERTION TEXT PRESENT — do NOT re-roll" on exactly that test: it fails safe on XCTest-shaped `error:` text, which an XCUITest flake always produces, so its advice is unconditionally wrong for #219 — a `scripts/mac` chore: a name-keyed exemption or a note in the advice). Swift Testing **2913 → 3025** (+112, computed from the branch's `@Test` declarations BEFORE reading the gate — parameterized tests print one line each), XCUITest **15** unchanged, Release build clean; skips = the known-permanent `CondenserFidelityTests` pair. **Re-gated after the whole-lane fix wave and again after its scoped round 2: `GATE: PASS on 24A5423a` FIRST roll both times, 3025 → 3036 → 3040 (+11, +4, each computed before launch), XCUITest 15, Release clean.**
> - **Whole-lane review before merge (Opus, whole branch vs main): MERGE AFTER FIXES → fixed in one wave and re-gated:** one `promptBudget()` is now read by BOTH `fitsContext` and `sessionBlueprint` (without the mirror a 6,368–7,168-token band rebuilt the session every turn while condensing NOTHING, behind a false "condensing" log line — now the rebuild condenses; **honest scope: a transcript above budget still rebuilds on every turn, because `fitsContext` reads the full transcript that condensation does not shrink — that is #26's pre-existing shape, not this lane's, and it is NOT pinned as fixed**; on the sim the 512 floor leaves a ~50-token gap, on the phone the band closes); `regenerateReply` with a swallowed re-send now restores the deleted note with its rows UNDER THE ORIGINAL `noteID` (a fresh id would orphan the chip's provenance and every `MemoryUseRecord`; it silently lost the note before, with no surface to notice) — and the FIRST cut of that fix stashed the snapshots on an instance field that `restoreRetriedRow` (retry's safety net, which never truncates) also consumed, so an UNDONE note could RESURRECT on a later swallowed retry and duplicate after Edit-and-Resend; the re-review caught it and the snapshots now travel by value (undone stays undone — pinned across both paths); the honesty comment claiming "I'll note that" fires was false (bare `note`/`save` are in no verb set — adding them would fire on "I'll save that file") → KNOWN-LIMIT rows; the two source-witness windows are bounded at the next `func` instead of a char count; the retrieval QUERY is the user's message, not the composed prompt with inlined attachments. **Two things the review re-surfaced were RULED the same afternoon (see the 09-03 PM ruling block): no build ships from `main` until M4 lands (M3 injects and corrects with no user-facing surface, and the PCC policy sentence sits on M4's branch), and the honesty guard stays QUIET when memory is OFF — implemented in this lane's fix wave (pinned: OFF + a memory promise with no row ⇒ reply byte-untouched), SCOPED after the re-review to sentences carrying no device artifact noun: "That has been saved to your reminders." classifies as a memory claim via its bare `that` and would otherwise have passed uncorrected with the toggle off — a device fabrication, #338's failure class.** **Minors riding to M4/DE1:** the just-saved turn carries its note twice (instructions + prefix); "Remember that…" turns are ALSO indexed as retrievable chunks (the same fact can return as note and hit); `pendingSavedNoteID` has no reader until M4; VOICE hears "I'll remember that" but the correction is appended only at finish (never spoken); a bare-pronoun device claim ("That has been saved to your reminders.") takes the memory copy; `candidates()` is a whole-table fetch plus ~8–10 `tokenCount` round trips per retrieving turn, all pre-turn (the #324 killer avoided) but unmeasured on the phone.
> - **Owed to DE1:** 422-H's device arm (n ≥ 40 "remember"-shaped prompts outside the closed set; bar uncorrected = 0/40) and 422-L (latency/energy, 3-hit vs no-hit). **Deferred minors:** `@MainActor` on `trimmedHits`/`fits` tighter than needed; the whole-block notes trim can cut mid-quote; `DateFormatter` locale default; unseeded property test; `allNotes()` fetched ~3× per turn (memo declined: a second source of truth synced with four write paths); `lastMemoryUse` has no production consumer (M4 reads the store row); ordering-pin window headroom 637 chars; notes not gated by local origin; paired-thread rows lack `clientMessageID` so Undo can miss there; a swallowed re-send restores rows but not the note; VOICE never saves a note (honest now, unwired); the won't-forget exemption is sentence-wide; "Your preference has been saved." misses the passive tier.

> **⏸ 2026-09-03 evening — LANE M4 IS CODE-COMPLETE AND GATED; ITS PR IS HELD FOR OWEN'S READ: GitHub PR #425 (opened as a DRAFT so it cannot merge by accident).** Branch `422-m4-provenance-screen-policy` @ `64f09c28`: `GATE: PASS on 24A5423a`, Swift Testing 3040 → 3119 (reconciled exactly), XCUITest 15, Release clean. **What Owen reads before the go — the two public-copy changes the merge PUBLISHES (`docs/` is the live Pages root):** (1) the PCC sentence, byte-identical in `docs/privacy.html` and on the Private Cloud screen (shown only while the tier is ON): *"Your request leaves the device — including any images you attached to that message and, if you have memory turned on, any notes you asked Talaria to remember and any earlier messages Talaria retrieves for that request."*; (2) two new clauses naming the on-device index of your own messages from local chats, the notes, the memory switch, Forget everything, and that *"They stay on your iPhone unless you choose Private Cloud β, where a request carries the notes and any retrieved messages to Apple's Private Cloud Compute as described above."* (the first cut of that clause said "never leave your iPhone" — false on PCC — and was caught in review); the effective date is bumped to 2026-09-03 (re-bump if the go lands later). **The lane's full RESULT block (bars 422-P/422-N, the chip's Critical the per-task tests could not see, the Memory screen, the completeness pin's pre-existing findings) is appended at MERGE with the squash SHA.** Per the 09-03 PM ruling no build ships from `main` until this PR lands. **DE1/DE2 are carded on the Device Runbook (§11, five cards) and both need this build; the two instruments the plan named (`memory-honesty`, `memory-fabrication`) are NOT built — the cards name a hand pilot in their place.** **Owen's word wanted with the go:** whether the chip should key on retrieved HITS only (today any saved note makes every local reply carry `ON-DEVICE MEMORY`); whether the voice path's "heard promise, unspoken correction" is acceptable until voice capture is wired (runbook card 422-de1-voice).

> **✅ LANE M4 RESULT — provenance chip, Memory screen, policy, naming (2026-09-03; branch `422-m4-provenance-screen-policy`, squash SHA `f007a143`, GitHub PR #425 (opened as a draft, marked ready and merged on Owen's go: "policy reads well. pr looks good." 2026-09-03 evening) — HELD for Owen's read of the policy sentence, merged on his go). Bars 422-P, 422-N: MET. 422-GATE: MET for this lane.**
>
> - **422-P (provenance, chip half — Tasks 14/15) — MET.** `MemoryProvenance` (`.local(entryIDs:noteIDs:savedNoteID:)` / `.host(observedTools:)`, `Codable`/`Hashable`/`Sendable`) and `Message.memoryProvenance: MemoryProvenance?` — OPTIONAL, added via `decodeIfPresent` in the EXISTING decoder and encoded only when non-nil (the `isContextPriming` pattern; the #42 rule read for a type that already has a hand-written decoder). **296-E's RED was real:** declared non-optional first, the pre-422 cached-message fixture (copied byte-for-byte from the #180 pin) failed with `keyNotFound`; optional → green; a nil provenance encodes WITHOUT the key (pinned by parsing the JSON keys, not by a nil decode). The chip (`MemoryProvenanceChipModel`: `ON-DEVICE MEMORY` / `SAVED TO MEMORY` / `HERMES MEMORY · <tool>`, a11y label = the same words, `.hudSingleLine()` per #42) renders beside the brain tag iff `memoryProvenance != nil`; tap → a sheet (`MemoryProvenanceSheetModel`) listing entryIDs then noteIDs with `From your chat on <date>` / `You told me on <date>`, `source deleted` for an unresolvable id (RED-first against a blank row), and — beyond the plan — the `savedNoteID` so `SAVED TO MEMORY` never opens an empty sheet. The store lookups (`turnEntry(id:)`, `note(id:)`) live ON `MemoryStore` through its diagnostic `fetch(_:op:)` after the review caught a separate-file extension re-implementing the read as a silent `try?` and widening `context`. The sheet reads `AppContainer.memoryStore` from the environment (pushed below the bubble so transcript rows do not observe the container); no store ⇒ every row `source deleted`, never blank. **Deferred:** the a11y label reaches VoiceOver as a custom action under the bubble's combined element (device pass owed); `HONCHO_SEARCH` renders upper-cased by `MonoLabel` (the host arm is the fuller shape); the chip's tap target is the house 8-pt precedent.
> - **422-P (screen half — Task 16) — MET.** `MemoryScreen` under SESSIONS (a `MEMORY` row; title `MEMORY`, subtitle `WHAT TALARIA REMEMBERS`; the deck-order pins `deckOrderIsTenAndStable` / `cardNumbersArePositionalAndContiguousOnBothDeviceShapes` byte-untouched and green), built on a closure-injected `MemoryScreenModel` pinned without SwiftUI: NOTES (`You told me on <date>` + ` · edited <date>`, the truncation notice `Saved the first 500 characters.` from `wasTruncated`, Delete/Edit through the store's note CRUD), RECENTLY USED (every `MemoryUseRecord` newest-first with `From your chat on <date>` / `You told me on <date>` per source, `source deleted` for an unresolvable id, **Don't use this** → `isExcluded` and the next `MemoryRetriever.retrieve` over `candidates()` for the same query excludes it — RED-first; mutation: no-op'ing the exclusion reds exactly that pin), INDEX (the real count — reported as MESSAGES via a new `indexedMessageCount()`, because the pinned sentence says messages while `indexCount()` counts chunks — or `—` while unknown, never a placeholder 0; the toggle bound to `UserSettings.memoryEnabled` through `SettingsStore`, the write pinned to persist; **Forget everything** with a confirmation → `MemoryStore.forgetEverything()` empties all three entities in one save and the screen renders the honest-empty copy, never blank), the host line only when a host is configured, a `Memory` Settings-search entry, and the NamingSweep pins for the screen literals. **The three readers M3 left for this lane landed here:** the reply provenance STAMP (`ChatStore.takeMemoryProvenance(forReplyID:)` at BOTH `.finished` arms — hits → `.local(entryIDs:)`, a "Remember that…" reply → `savedNoteID`, nothing drawn → nil; mutation: nulling the stamp reds both positives), the truncation notice, and the note-by-id positive pin. **The review then caught four things fixed in a round:** RECENTLY USED silently capped at 20 (`recentUses()`'s default) against "every"; **Forget everything erased the rows but left the backfill cursor, so an unfinished or in-flight backfill would have RE-INDEXED forgotten history on the next launch — ruled: forget parks the cursor forward (never to 0) and cancels the running walk, because Forget everything is the ONLY eraser and retention is never**; *Don't use this* rendered no change and had no undo (now `Excluded · Use again`); the empty-honest copy rendered when the count was UNKNOWN (`—`), contradicting the INDEX rule in the same render. The merge of `main` into this lane collided on the duplicate `note(id:)` both lanes had added (main's fetch-based one kept) and on `project.pbxproj` (main's + `xcodegen`).
> - **422-N (naming + policy — Task 17) — MET.** The PCC policy sentence, byte-identical in BOTH homes (`docs/privacy.html`'s PCC paragraph and `ConnectHostCopy.privateCloudPolicySentence`, rendered by `PrivateCloudSettingsScreen`): **"Your request leaves the device — including any images you attached to that message and, if you have memory turned on, any notes you asked Talaria to remember and any earlier messages Talaria retrieves for that request."** — the existing lead-in kept, only the memory clause spliced; the byte-identity pin compares the WHOLE sentence after entity-decoding the HTML's `&mdash;` and collapsing its hand-wrap (a literal byte comparison is impossible against the file's own entity convention). **The sentence is NEW in the app** (no in-app rendering of the PCC policy existed before — worth Owen's eyes with the wording), and it renders ONLY while the PCC toggle is ON — the review caught it sitting unconditionally beside the OFF-state line "nothing is sent to Apple's servers", a privacy-communication contradiction. `NamingSweepTests` pins: `ON-DEVICE MEMORY` / `SAVED TO MEMORY` present, `HERMES MEMORY` present (host-meaning), no `"Hermes Memory"` / `"Hermes remembers` app-meaning literal (a deliberate PREFIX match, commented), both homes carry the clause and the whole sentence — each shown RED by mutation. **`docs/privacy.html`'s effective date is NOT bumped: `docs/` is the live Pages root, the merge PUBLISHES, and the date is bumped on Owen's go at merge (#390's precedent).**
> - **Whole-lane review before the PR (Opus, whole branch vs main): NOT READY → fixed in one wave and gated.** **The Critical the per-task tests could not see:** `ChatStore.mergeConversationMetadata` rebuilds the transcript from the backend's copy after every settle/refresh and carries client-only `Message` fields across one at a time — `memoryProvenance` was not on the list, so the stamp was discarded the instant it was applied and **the chip never rendered in production**; the pins passed because the test spy never populated the backend's `currentConversation`, so the merge returned the stamped copy untouched. Fixed by carrying the field (and the `.alreadyPresent` arm), with a fixture that DOES populate the backend copy (RED with the carry removed) and a completeness pin over `Message.CodingKeys` (now `CaseIterable`) vs the carry list so the next field cannot vanish silently — **which fired on its first run and surfaced a PRE-EXISTING finding: `codeDiff` and `toolActivity` are carried by the merge but are not coding keys at all, so a cache reload drops them regardless; both are now stated in a third list rather than papered over (a filed finding, not this lane's defect).** Also fixed in the wave: the policy's effective date (2026-09-03) and its "what the app stores" / "your controls" paragraphs now name the on-device index, the notes, the memory switch and Forget everything (all in the held PR for Owen's read — and the re-review caught the FIRST cut of that clause claiming the index and notes "never leave your iPhone", false on the Private Cloud β path, where the retrieved chunks and the notes block ride the request; the clause now says so); `indexCount()`/`noteCount()` fetch failures read as UNKNOWN (`—`) instead of manufacturing the "real zero" the empty copy requires; RECENTLY USED is bounded honestly (`Showing the most recent 50 of M`, lazy); `forgetLocalMemory()`'s no-runner fallback is reachable; *Don't use this* excludes EVERY chunk of the message, not one. **Filed, pre-existing, not this lane's:** `Message.recoveredForPrompt` (#235) is client-only, has no coding key and is not carried by the merge — a refresh drops it, the same family as the chip's Critical; and four `serverOwned` entries of the new completeness partition look client-authored (`brain`, `hostReportedFailure`, `isContextPriming`, `voiceSessionDuration`) — the partition was closed by parking, a follow-up decides. **Plan-level, for DE2:** once any note exists the notes block rides every local turn, so every local reply carries `ON-DEVICE MEMORY` and mints a use row — the chip becomes permanent chrome; whether it should key on retrieved HITS only is Owen's call after the eyeball.
> - **422-GATE — MET on the final bytes (`64f09c28`):** `GATE: PASS on 24A5423a`, Swift Testing **3040 → 3119** (+79, computed from the branch's `@Test` declarations before reading the gate; the final policy-clause commit added no test and the count correctly did not move), XCUITest **15** unchanged, Release build clean; skips = the known-permanent `CondenserFidelityTests` pair. (The run on the prior bytes hit the #219 XCUITest flake and — for the THIRD lane — the classifier printed "ASSERTION TEXT PRESENT — do NOT re-roll" on exactly that test; the final-bytes run passed first attempt with no re-roll consumed.)
> - **Merged 2026-09-03 evening on Owen's read** — the policy is published with effective date 2026-09-03 (same day, no re-bump owed). **The release gate is lifted: builds may ship from `main` again.** The lane's SDD workspace is deleted; the record is git.
> - **Owed to DE2:** 422-F (the decisive cell contrast) and the Memory-screen eyeball. **Deferred minors:** the omitted-key `savedNoteID` decode form untested (framework-guaranteed); the sheet model built in `body`; the sheet header is the third copy of `CapabilitiesSheet`'s (a shared `HUDSheetHeader` earns its keep now); a leaf-level `.sheet` in a `LazyVStack` row; `indexedMessageCount()` still non-optional (feeds only a `> 0` guard); RECENTLY USED fetches all use rows and bounds only the render; `forgetLocalMemory()` untested as a unit; excluding by message is the door, the entry-level door survives for tests; the completeness partition's four parked entries (above).

> **⚖️ RULED 2026-09-04 (Owen, delegating the choice to Claude "based on the app and honesty"; the four options and the recommendation were laid out in chat): OPTION B — THE HONESTY GUARD STOPS TREATING A PROMISE TO REMEMBER AS A FABRICATION WHEN THE INDEX WILL HONOUR IT.** The post-merge review of lanes M1–M4 (2026-09-04) found two premises of the 09-02 plan that the lanes executed faithfully and that the shipped shape falsifies. **(1)** With memory ON, every user turn of a local chat is indexed at settle and is retrievable next session — so the correction the guard appends to *"I'll keep that in mind"* (*"Nothing was saved to memory. Talaria only remembers what you ask it to…"*) is false in its first clause and misleading in its second, on the commonest reply shape, with memory on by default; and DE1's bar as written (uncorrected = 0/40) rewards forty of those false corrections. The copy and the claim family were the plan's own (plan §Naming, Task 12). **(2)** Retrieval breaks on natural phrasing: light verbs and modals are content tokens, overlap is normalised by the query's token count, and ties fall newest-first, so *"can you tell me who my dentist is"* scores a cat-joke row above the dentist row and drops the dentist entirely; only 13 of the 107 corpus queries carry such a verb, which is why 422-R could not see it. A standalone copy of the shipped scorer reproduces 422-R's numbers exactly (p@1 60/75 · top-3 71/75 · adversarial 9/12 · plain 0/20) and measures the "can you tell me …" frame at **50/75 · 60/75**; a ~90-word function-word stop-list extension takes the as-written corpus to 62/75 · 72/75 and every frame tried to the same 62/75 · 72/75, plain 0/20 by construction. **(3)** The current conversation's own turns are retrieval candidates — `candidates()` has no session filter — so the *"From your earlier chats"* block quotes back what the user said three turns ago in the same chat, and DE2's empty arm is not empty from question two (each memory-shaped question is indexed at settle and retrieved by the next). **Not relitigated:** the 09-03 embedder deletion (the fix is a stop list, the same lever the stemmer was), relative admission, the accepted adversarial miss.
>
> **Bars, written before any code (RED-first, isolating mutations, one worktree lane `422-honesty-retrieval`):**
> - **422-S — phrasing invariance.** With every answerable corpus query wrapped as *"can you tell me "* + query, **p@1 ≥ 0.80 and top-3 ≥ 0.90** (today 50/75 · 60/75 — RED); the as-written numbers do not fall (60/75 · 71/75 today); plain false-admit stays 0/20 (a stop-list extension can only remove tokens, so the zero-overlap pin holds by construction); adversarial reported. **Lever: the stop list only** — light verbs, modals, discourse words; no scorer, z, or normalisation change. Mutation M-S: revert the extension → the framed test reds and nothing else moves.
> - **422-T — the current conversation is never its own memory.** A turn indexed under the current conversation's id is never quoted into that conversation's prefix; a matching turn from another conversation still is. RED-first through `memoryPrefix` with `currentConversation` set. Mutation M-T: drop the session clause → the test reds. Consequence recorded: after Forget everything, a thread's own questions no longer feed the next question, so DE2's empty arm is runnable inside one conversation (the ruling still holds that Forget everything erases the INDEX, not the transcripts — a thread the user keeps chatting in is re-indexed from the settle seam, by design).
> - **422-U — promise vs write.** (a) With memory ON and a live index for this thread, *"I'll remember that"* / *"I'll keep that in mind"* / *"I won't forget that"* get **no correction** — the index honours the promise (RED today: every one is corrected). (b) *"I've noted that …"* / *"I've saved that to memory"* / *"That's been noted"* on a turn that saved no note are still corrected, in copy that is TRUE: **`⚠️ **No note was saved.** Talaria saves a note only when you say "Remember that…" — the reply above is inaccurate. Your message can still be found later by its words.`** (c) With memory ON but no live index (no store, or a host-origin thread the settle seam does not index), promise frames are corrected too, and the copy omits the last sentence — nothing was indexed. (d) Memory OFF: quiet on both kinds, unchanged (09-03 ruling). (e) A note saved this turn licenses both kinds, unchanged. (f) Both copies are claim-free, say Talaria, never Hermes, never promise a retry. Mutation M-U: remove the index-honours-the-promise short-circuit → (a) reds, (b)–(f) stay green.
> - **422-GATE:** `lane-gate.sh` green on a `CC-lane-N` sim; the reported test count MOVES from 3119.
> - **After merge, before DE1 runs:** the DE1 honesty card is RE-CUT — the 40 "keep in mind"-shaped prompts measure (i) zero uncorrected WRITE fabrications, (ii) how many of the 40 are retrievable next session by a natural question (a finding, not a bar — the number is the deliverable), (iii) the OFF control quiet, (iv) the three positive controls chipped. DE2's empty arm note is updated for 422-T.

> **✅ LANE 422-S/T/U RESULT — promise vs write, phrasing-invariant retrieval, no self-quoting (2026-09-04 overnight; branch `422-honesty-retrieval`, squash SHA `5057c46e`, GitHub PR #426, merged on Owen's "merge on green" at bedtime). Bars 422-S, 422-T, 422-U: MET. 422-GATE: MET — run 1 (bytes b88f53d8) red on two counts — the #219 XCUITest flake (`testConnectedRelaunchSkipsTheConnectEntry`, 14/15, Swift Testing otherwise green; tonight's log adds `Computed hit point {-1, -1} after scrolling to visible` — filed under #219) and ONE REAL red the targeted suites had not covered, `NamingSweepTests.theHonestyCorrectionNamesTalariaNotTheHost`, a source grep for the retired copy that had been satisfied by a doc comment quoting it — re-pinned on the constants at `06d464a0`; run 2 on those bytes **PASS on 24A5423a — Swift Testing 3128 (from 3119), XCUITest 15/15, Release clean**.**
> - **RED first, all of it.** The bars commit (`d4bbef5e`) preceded every test; the tests preceded every production line. RED run on `origin/main` bytes + the new tests: **16 issues** — the tokenizer pin (3), the framed corpus at **50/75 · 60/75** (3), the self-quote test (1), 422-U(a) three promise rows (6), 422-U(c) two rows (2), the copy pin (1); the three controls — (b) a claimed write is still corrected, (d) memory OFF quiet, (e) a saved note licenses — green throughout. The in-suite `422-R:` line on the pre-change scorer reads **p@1 60/75 · top-3 71/75 · adversarial 9/12 · plain 0/20**, digit for digit what a standalone copy of the tokenizer + retriever measured during the review — the reproduction is what made the review's finding a measurement rather than a reading.
> - **GREEN (`46405acd`): 124 tests in 6 suites** (`LexicalTokenizerTests`, `MemoryRetrieverTests`, `MemoryInjectionTests`, `MemoryHonestyTests`, `ActionClaimDetectorTests`, `HonestyGuardWiringTests`). **422-S:** with the ~90-word function-word list the corpus scores **62/75 · 72/75 as written AND 62/75 · 72/75 under the "can you tell me …" frame** (plain 0/20 by construction — the zero-overlap pin still holds; adversarial 9/12 unchanged, still un-gated). **422-T:** `MemoryStore.candidates(excludingSession:)` filters the current conversation in the predicate; `memoryPrefix` passes `currentConversation?.id`. **422-U:** `ActionClaimDetector.ClaimKind.memoryPromise` (future frames, keep-in-mind, the negated *"I won't forget that"*) is licensed by `savedNote` OR the new `promiseKeptByIndex`; `.memoryCreation` keeps the perfect/bare-past and passive WRITE frames and is licensed by `savedNote` alone; the write frames are tried first. `LocalChatBackend.memoryIndexIsLive` = memory on ∧ store present ∧ (#190B's `isLocalThread` ∨ no settled assistant turn yet — the first-turn rule, read before the reply is appended). Copy: `memoryCorrectionNotice` = *"⚠️ **No note was saved.** Talaria saves a note only when you say "Remember that…" — the reply above is inaccurate. Your message can still be found later by its words."*; `memoryCorrectionNoticeNoIndex` drops the last sentence (no store, or a host-origin thread). The 09-03 OFF ruling now covers both kinds. **Corollary landed under 422-S:** the honest no-match line (`noMemoriesMatch`) is judged OUTSIDE the skip gate, because *"what do you know about me"* carries no content token once `know` is stopped — exactly the question the line was written for (its own RED-first test).
> - **Isolating mutations, each a one-line break on top of the GREEN commit, each reverted by git, each run over the same 124 tests:** **M-S** (stop list back to the 53 words) → 7 issues, exactly the three 422-S tests (tokenizer pin, framed corpus, the honest-line corollary via its precondition) · **M-T** (session clause dropped) → 1 issue, exactly the self-quote test · **M-U** (`promiseKeptByIndex` ignored) → 6 issues, exactly 422-U(a)'s three rows · **M-N** (honest line re-gated on skip) → 1 issue, exactly the corollary test. Nothing else moved in any of the four.
> - **Close-out corrections in the same lane:** the design doc's §2.3 note quoted 65/75 · 72/75 as "final" — that figure predates the total tie-break; the ruling's 60/75 · 71/75 is what every reproduction returns, and 422-S moved it to 62/75 · 72/75 (dated pointer under the note). The plan's naming literal and Task 12 carry SUPERSEDED notes. The M3 RESULT block above, where it says the guard corrects *"I'll remember that"*, is superseded by this block — a promise on an indexed thread is kept, not corrected.
> - **What this does NOT change:** the embedder deletion (the lever was the stop list, the same lever the stemmer was); relative admission and `z`; the accepted adversarial miss; the notes-in-instructions / hits-in-prompt split; the chip question (whether it should key on retrieved hits only) — still Owen's, on the Desk Board.
> - **Owen's side (re-cut on the runbook, build 3240+):** the DE1 honesty card now measures (i) zero uncorrected WRITE fabrications, (ii) zero corrections on promise replies, (iii) `retrieved/40` and `answeredRight/40` from a SECOND chat asking naturally phrased questions — the first production reading of whether the promise the model makes is one the index keeps (a finding, not a bar), (iv) the OFF control quiet, (v) the three positive controls chipped. DE2's empty arm can run inside one fresh chat (422-T). Build 3240 staged OTA from `main` @ `5057c46e`.

> **📋 2026-09-04 — PLAN WRITTEN (the difficulty sweep): `planning/superpowers/plans/2026-09-04-422-memory-instruments.md` — the two instruments the §11 runbook cards name as NOT BUILT (`memory-fabrication` for 422-F's four arms, `memory-honesty` for DE1 as re-cut under 422-U).** Shape: per-arm HARNESS BACKENDS with in-memory stores (`LocalChatBackend(… memoryStore: MemoryStore.make(inMemoryOnly: true) …)`), so the user's real store is never written, read or emptied by a measurement — `memoryStore` stays `private` on the live backend; a `MemoryFabricationScorer` with a Python twin and a parity test, positive control = `mem-planted-fact` ≥ 30/40 (else VOID); `deviceOnly` refusal in the conductor; cell names unique across instruments (#416-G). Bars 422-I-A..D in the plan; Task 0 probes that a harness backend generates on device with a store attached. Task 6 (spoken "Remember that…" saves) rides only on Owen's Desk Board answer to Q2. The §11 hand-pilot cards stay as the fallback until it lands. Index: `planning/2026-09-04-difficulty-sweep.md`.



## 425. 🐛 THE SHELF EMPTIES WHEN A CONFIGURED HOST IS UNREACHABLE — `ChatBackendRouter.listSessions()` fetches the LOCAL rows first and then throws them away when the host list throws; a phone off the tailnet shows NO local history at all — **FOUND 2026-09-04 ~14:00 from Owen's report ("my whole session shelf is empty now. Local, PCC and Hermes"), diagnosed the same hour from a corded `log collect`. NOT a #422 regression. FIX PROPOSED BELOW — GO RULED 2026-09-04 PM (Owen: build it, queued behind the #340 lane's merge, before tonight's #219 batches).**

> **What Owen saw (build 3239, the #422 M1–M4 memory build):** the session shelf empty across every origin; a new Local chat did not appear on the shelf even before a force-quit.
> **What the log says (`~/Desktop/talaria-shelf-20260904.logarchive`, 15:12–15:27, three app processes):** no store error of any kind — no `ModelContainer creation failed`, no `save failed`, no `decode failed` (the session store's schema and file are UNTOUCHED by the 422 lanes; `Message.memoryProvenance` is `decodeIfPresent`). The write side WORKED: `local origin established for '6AFF73D8…' — first assistant turn settled on-device (#190B)` at 15:26:57 is the line that follows `localSessions.upsertSession` (`ChatStore.swift:1903-1905`), and the same process had `memory: injected 3 hit(s)` — the local store has content. The read side is where the shelf died: every time the drawer opened, `listSessions: 'OJAMD' unreachable — The request timed out.` · `listSessions: 'Mac Mini' unreachable — The request timed out.` · **`loadSessions: FAILED — The request timed out.; serving 0 from the last real list`** (three times in ten seconds at 15:27:09–:18, and again in the earlier process).
> **Why both hosts time out:** the phone is OFF the tailnet — the Mac's `tailscale status` shows `100.68.60.11 iphone182 iOS offline, last seen 8h ago` (≈ 07:00 on 09-04). The Mac gateway is up and listening on `:8642` (PID 13607). A timeout is not a Private-Relay diagnosis (CLAUDE.md's discriminator) — this is a phone that cannot reach the CGNAT range at all.
> **The mechanism (code at `c0264495`+, unchanged for months):** `ChatBackendRouter.listSessions()` (`Talaria/Services/Support/ChatBackendRouter.swift:638-651`) does `let localSessions = (try? await local.listSessions()) ?? []`, then — because a host IS configured — `let hermesSessions = try await hermes.listSessions()`, which THROWS when every host times out; the throw propagates out of the router with `localSessions` already in hand and discarded. `ChatStore.loadSessions` (`ChatStore.swift:3751-3770`) catches it and "serves the last real list" (#175's snapshot) — which, in any launch that has not yet completed one successful host list, is **zero rows**. The not-configured branch (`guard isHermesConfigured() else { return local + stubs.asUnresumable }`) already has the honest shape; the configured-but-unreachable case never got it. All three origins ride this one call: Local and PCC threads are `LocalSessionRecord`s served by `LocalChatBackend.listSessions()` (`LocalChatBackend.swift:1549-1570`), Hermes rows are the host list (with `RemoteSessionStubRecord`s as the offline snapshot) — so one throw empties all three, which is exactly the symptom.
> **Why it surfaced today:** Tailscale dropped on the phone at ~07:00; every shelf open since then hit the failure path. Before that, the host list succeeded and the merge ran. Nothing in 3239 (or 3240) touches this path — the memory build is a coincidence of timing. **Immediate remedy: turn Tailscale back on on the phone; the shelf returns on the next open** (the local rows were never lost — the DE2/DE1 memory cards can run on 3240 as planned).
> **Who this hurts:** not the hostless launch user (that branch works) — the host-CONFIGURED user who is away from the tailnet or whose host is asleep, i.e. Owen at work with Tailscale off, or anyone whose host box is down. For that user the app shows no history of their own on-device chats, which is the worse half of the product going dark for a reason the product itself did not cause.
> **Fix proposed (app-side, one router branch, no host change — the shape the standing "fix app-side" rule prefers):** in `ChatBackendRouter.listSessions()`, catch the host-list failure and return `sortedByRecency(localSessions + stubs.asUnresumable(reason: "host unreachable"))` — the same degradation the not-configured branch already performs — logging the host error at notice level so `loadSessions` no longer sees a throw for a reachable-local/unreachable-host split. `ChatStore.loadSessions`' snapshot logic keeps serving the last successful list when it has one (unchanged); the drawer's `LINKED · ONLINE` assertion is #350's and already reflects the host state honestly. **Bars (RED-first, pre-registered here):** 425-A — with a configured host whose `listSessions` throws, the router returns every local row plus the remote stubs marked unresumable, and does NOT throw (unit, a throwing stub client; isolating mutation: restore the rethrow → the row reds); 425-B — the not-configured branch is byte-identical (pin); 425-C — with a REACHABLE host the merge is unchanged (the existing tests stay green); 425-GATE. One lane, ~S-sized; OTA after merge so Owen's phone gets it. **Not proposed:** any change to the timeout, the health poll, or the host client — the host being unreachable is a true state and the app should say so, not hide it.
> **Decision for Owen:** go on the fix lane above (recommended — it is the "user is harmed now, app-side fix exists" shape), or leave as a documented limitation.

> **✅ CONFIRMED 2026-09-04 ~15:45 (Owen): Tailscale had crashed on the phone. Restarting it, then force-quit → relaunch, brought every session back — Local, PCC and Hermes. The rows were never lost; the read path hid them. The router fix above stands proposed; go is Owen's.**

> **📌 GO 2026-09-04 ~15:50 (Owen, AskUserQuestion: "Go, after #340 lands"):** the router fix lane runs after #340's merge and OTA, before the #219 DET-C/E batches; bars 425-A..C above are the pre-registration; RED-first in its own worktree; merge on green; OTA so the phone carries it.
