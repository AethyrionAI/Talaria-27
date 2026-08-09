# OPUS-T27-140 — the public face, third pass: SECURITY.md was never swept

> ## ⚠️ AMENDED 2026-08-09 — MUCH OF THIS IS ALREADY DONE. READ BEFORE EXECUTING.
>
> Owen asked for the stale docs to be corrected directly, so **the highest-value
> items in this dispatch were executed the same night** (commit `9b6008c`). An
> executor starting from the body below will duplicate work and may "fix" text
> that is already correct.
>
> **DONE — do not redo:**
> - **`SECURITY.md:15`** — no longer names a third service. The models-shim line
>   is gone, with a note telling anyone running one from an older release to stop
>   it.
> - **`SECURITY.md:25`** — APNs push removed from the relay's live-jobs list, and
>   replaced with something stronger than a deletion: the relay's push machinery
>   is still live (`main.py:230` creates an APNs client, `:420` accepts and
>   persists `apns_token`) while the app has no push at all, so the deployment
>   holds **an authenticated endpoint collecting push tokens nothing will use.**
>   Recorded as unused surface, not a vulnerability.
> - **`SECURITY.md:46`** — camera/mic entry now carries **#221's brain gate**: the
>   brain selection is consulted *before* pairing, so an on-device brain stops
>   realtime — and any camera frame reaching OpenAI — from starting. This was an
>   *improvement*, not just a correction: brain choice is a privacy control.
> - **The "session pin" claim in all four places** — `README.md:27`, `README.md:75`,
>   `docs/index.html:182`, `docs/screens.html:150`. There is no session pin: the
>   app never POSTs `/api/sessions/{id}/model` (zero occurrences in Swift) and
>   `ModelsSettingsScreen.swift:84` says so outright.
> - **Two broken deploy steps** that had been silently copying nothing since the
>   2026-08-05 rename — `relay/docs/DEPLOY_MAC.md:94` and
>   `design/T6_MAC_BACKEND_SPEC.md:75` both said `cp -R ../skills/hermes-ios`;
>   only `skills/talaria` exists.
>
> **VERIFIED CURRENT — do not "fix" these:** `~/.hermes-mobile/secrets.json` is
> still real (the connector uses it); the `hermes-mobile` CLI still exists
> (`connector/pyproject.toml:19`), so the app's onboarding copy is accurate
> rather than broken; `CLEAN_CHAT_PATH.md` has no stale claims;
> `connector/README.md:144` removes both old and new skill paths on uninstall,
> which is correct and defensive.
>
> **WHAT REMAINS FOR THIS LANE:** re-derive the residue against HEAD rather than
> trusting the list below. The lane is now **small** — verify what is left, then
> close. Its own finding still stands as the lesson: **the brief for this
> dispatch was itself stale** (the "wedge narrative" it was commissioned to fix
> had been corrected on 2026-08-04), which is why re-deriving beats executing.

**Label:** OPUS · **Item:** #140 (README + GitHub Pages refresh) · **Written:** 2026-08-09
**Status:** DISPATCH ONLY — no code, no `docs/` edits, no `OPEN_ITEMS.md` edits, nothing published.

**Goal:** bring every public-facing artifact into agreement with the app as it exists at
HEAD, judged against the **default (hostless) user**, and close the gap the 2026-08-04
copy sweep left open — it corrected `README.md` and `docs/` and **never touched
`SECURITY.md`**.

> **⚠️ THE DISPATCH BRIEF FOR THIS LANE WAS ITSELF STALE.** The tasking said the public
> face "currently carries a stale wedge narrative and pre-freemium positioning." It does
> not. That was true when #140 was filed 2026-07-20 and it was **fixed 2026-08-04**
> (`d1356b1`, `93f4223`, `8ca91a4`). The wedge sentence is gone, the positioning is
> on-device-first, the shim is named as retired on both README and Pages. **The stale
> framing survives only in `OPEN_ITEMS.md`'s #140 header and in
> `PLAN-FINISH-OPEN-ITEMS.md:250`** — see §4. The real remaining work is a different,
> smaller, sharper set of claims, listed below.

---

## 1. What this lane is

Three public surfaces, one standard: **a reader who acts on what they read must not be
harmed by it.**

| surface | last swept | state |
|---|---|---|
| `README.md` | 2026-08-04 (`d1356b1`, `93f4223`) | mostly true; **3 falsified claims** |
| `docs/index.html` · `setup.html` · `screens.html` | 2026-08-04 (`8ca91a4`, PR #266 bake) | mostly true; **3 falsified claims**, same family |
| **`SECURITY.md`** | **2026-07-22 (`aa2145e`)** | **NEVER SWEPT. 3 falsified claims, one of them material** |
| `docs/img/` (13 renders) | 2026-07 | stale by admission; **batched with P-4, out of scope here** |

---

## 2. Verified state

Everything in this section was read at HEAD (`35c6234`) today. **VERIFIED** = read in the
named file or proven by source. **ASSUMED** = inferred, not proven, and flagged as such.

### 2.1 VERIFIED — the artifacts

**`SECURITY.md:15`** (the lead of the deployment-model section):

> "The expected deployment puts all three host services (Sessions API `:8642`, relay
> `:8000`, **models shim `:8765`**) on a Tailscale tailnet or equivalent private network"

**`SECURITY.md:25`:**

> "The relay carries everything phone-facing except chat: pairing and auth, sensor
> ingestion, **APNs push**, the inbox/directives channel, scheduled runs, agent-file
> downloads, and the voice WebRTC bootstrap."

**`SECURITY.md:46`:**

> "**Camera frames for voice mode are sent directly to OpenAI via WebRTC**, not through
> the relay."

**`SECURITY.md:50`** (Known Limitations, the ATS entry) asserts as fact:

> "(Verified 2026-07-22: with no exception, or with only `NSAllowsLocalNetworking`, ATS
> blocks tailnet IP traffic outright — **the exception is load-bearing**, and the CIDR
> scoping was confirmed with an outside-range negative control.)"

…and immediately above it:

> "If you serve the backends over HTTPS (e.g. `tailscale serve` with MagicDNS), you can
> remove even this scoped exception from `project.yml` locally."

**`README.md:27`** (status table, Model picking row) and **`README.md:47`** (features
list) and **`docs/index.html:182`** all carry the same sentence:

> "Picks apply as a per-turn model lock **plus a session pin**."

**`README.md:169`** repeats the SECURITY.md ATS framing verbatim in shorter form.

**`README.md:184`** (repository layout):

> "`tools/models-shim/`    Legacy model-switching shim (Python; retired — current app
> builds are gateway-native)"

**`docs/index.html:122`** — SOLO / **ZERO HOST SETUP** column, presented as a thing that
works with no host:

> "Siri and App Intents; conversations index into Spotlight"

**`docs/index.html:240`** (capability card 03, Voice mode):

> "Realtime WebRTC speech-to-speech with server-side voice, continuous mic and barge-in —
> **falling back to an on-device engine when the relay is unreachable**."

`README.md:44` carries the same clause: "falls back to an on-device engine when the relay
is unpaired or unreachable."

**`docs/index.html:86`** (hero sub, describing the PAIRED tier):

> "Pair a Hermes agent you host yourself and it grows your desktop model roster, server
> sessions, and a live sensor feed. **No cloud.** No relay you don't own."

**`docs/index.html:91`:** "NO APP STORE · NO TESTFLIGHT · YOU BUILD AND SIGN IT YOURSELF"
— **true today**; flagged only because #166/#8 will falsify it on submission day and it
is easy to forget.

### 2.2 VERIFIED — the source that judges those claims

- **No session pin is sent.** `Talaria/Features/Settings/ModelsSettingsScreen.swift:84`,
  the doc comment on `apply()`, in so many words:
  `/// Instant by design: no shim POST, no session pin, nothing to await.`
  `apply()` (`:85-94`) writes the selection to the active profile and returns; there is
  no network call at all. `SessionsHermesClient.swift:1952,1964` sets
  `requireModelLock: selection == nil ? nil : true` on the per-turn body.
  **The per-turn lock half is TRUE; the session-pin half is FALSE.**
- **The per-turn lock genuinely governs.** #223 Lane 5's re-verify round 2 (2026-08-04,
  `OPEN_ITEMS.md` ~:9250) reproduced `P3 lock honored (nous/deepseek,
  model_lock: "confirmed")` on fresh sessions. So the picker is not a label-only
  picker — only the *mechanism sentence* is wrong. Recorded because #170's 2026-08-02
  result (a bare `model` field is a silent no-op) makes the opposite reading tempting.
- **The shim is retired.** `CLAUDE.md`'s "Model switching (gateway-only — #223 Lane 5)"
  section: the OJAMD `TalariaModelsShim` service is stopped and disabled, the picker
  makes no shim POST. README and Pages already say so; **SECURITY.md does not.**
- **Notifications are gone.** #238 (`OPEN_ITEMS-ARCHIVE.md:9583`) — "✅ CLOSED
  2026-08-03 evening — ALL FIVE BARS MET." README:30 and the Pages status table already
  carry the honest "REMOVED BY DESIGN" row; **SECURITY.md:25 still lists APNs push.**
- **Realtime voice is brain-gated.** #221 (`OPEN_ITEMS-ARCHIVE.md:8826`, FIXED
  2026-08-01): `VoiceEngineRouter.realtimeIsPermitted(for:)` gates on `.hermes` only,
  wired at three points, and "a forbidden brain must not reach OpenAI *at all*, not
  merely avoid speaking to it." `.privateCloud` is forbidden too. **So the engine is
  chosen by the brain selection, not by relay reachability** — the README/Pages sentence
  describes the pre-#221 behaviour.
- **Control Center / lock-screen controls DO work.** #254 (`OPEN_ITEMS.md:~7900`,
  downgraded to WATCH 2026-08-05 on build 2034): Owen re-tested repeatedly, "chat →
  composer and talk → voice session, consistently, every time." **The README/Pages
  "lock-screen controls" claim is therefore DEFENSIBLE** — I flag this explicitly
  because #58's own header still reads "controls DEAD on device 2026-07-25" and
  transcribing that header would have produced a false correction. See §4.
- **"11 HealthKit metrics" is exact.** `LiveHealthService.swift` — 10
  `HKQuantityType.quantityType(forIdentifier:)` calls (steps, activeEnergyBurned,
  distanceWalkingRunning, heartRate, restingHeartRate, oxygenSaturation, respiratoryRate,
  bodyMass, appleExerciseTime, appleStandTime) plus `HKCategoryType(.sleepAnalysis)` at
  `:523`. **11. Leave it alone.**
- **"Thirty channels" is exact.** 30 `ThemePaletteDefinition(` entries in
  `Shared/ThemePaletteCore.swift`. Leave it alone.
- **Offline/airplane-mode claim holds.** #136 closed, device-verified 2026-07-20 under a
  relay+shim black-hole; Owen's own airplane-mode test on 2026-08-01 is what surfaced
  #221. Leave it alone.
- **Keychain service name is right.** `AppContainer.swift:347` —
  `KeychainSecureStore(serviceName: "org.aethyrion.talaria.session")`, matching
  `SECURITY.md:44`.

### 2.3 ASSUMED — not proven, do not ship a claim resting on these

- **ASSUMED: Siri / App Intents work on the hostless default.** `docs/index.html:122`
  puts them in the SOLO column. I could not find a device check of the Ask intent against
  the **local brain**. #56's own device sub-checks (2026-07-20) were run paired, and one
  of the three FAILED: *"Tailnet-unreachable: FAIL. Off tailnet AND wifi, the intent still
  presented as a working run"* — i.e. the one recorded run closest to hostless conditions
  did not behave. The intent routes through `ChatStore.sendMessage`, so it *probably*
  follows the active brain, but "probably" is not what a public capability list is for.
  **This wants a device check before the claim stays.** (Related and unresolved: the
  intent's spoken copy says "What should I ask **Hermes**?" and "**Hermes** is still
  working on it" — nonsense to a user who has no Hermes. That is #255's de-branding
  sweep, cross-referenced not duplicated.)
- **ASSUMED: nothing else in the 13 `docs/img/` renders has drifted further.** They are
  already labelled honestly as stylized renders (the "real captures from hardware" claim
  was removed in the PR #266 bake) and are batched with P-4. Not re-checked here.
- **ASSUMED: `~/.hermes/.env` is the right macOS path** (`docs/setup.html:190`,
  `README.md:159`). CLAUDE.md only pins the *Windows* location and states that
  `C:\Users\Owen\.hermes\.env` does **not** exist. The macOS half is unverified by me.

---

## 3. What is stale and why — the six claims

Ordered by how much harm a reader acting on them takes.

### 3.1 🔴 `SECURITY.md:15` — the security document tells you to secure a service that does not exist

> "all three host services (Sessions API `:8642`, relay `:8000`, **models shim `:8765`**)"

**Falsified by:** #223 Lane 5, 2026-08-04. The shim is retired; the OJAMD service is
stopped and disabled; the app never calls it. README:184 and `docs/index.html`'s
architecture panel both say "RETIRED" already.

**Why this is the worst one on the page.** It is not a marketing sentence — it is the
deployment guidance in the file a security-conscious self-hoster reads *before opening
firewall ports*. Following it means standing up and exposing an eighth-thousand port for
a Python service that current builds never contact. It is the **only** public surface
that still asserts the shim is part of the architecture, and it is the surface where being
wrong costs the reader the most.

**Root cause, and this is the lesson:** the 2026-08-04 sweep corrected `README.md` and
`docs/` in the same commit and did not grep `SECURITY.md`. That is exactly the
CLOSE-OUT RULE failure the rule was written for — *every doc whose text the result
falsifies, in the same commit.* Two files got it; the third was invisible because nobody
listed the surfaces first.

### 3.2 🔴 `SECURITY.md:25` — claims a data flow the app removed

> "the relay carries … **APNs push** …"

**Falsified by:** #238, closed 2026-08-03, all five bars met. The app posts no
notifications and registers for no push. README:30 and the Pages status table were both
corrected 2026-08-04. **This line is a privacy-material claim in a security document**,
and it is the kind of statement the App Privacy questionnaire (#166a) will be checked
against. Fix it before it gets copied into review answers.

### 3.3 🟠 `SECURITY.md:46` — describes camera frames going to OpenAI, ungated

> "Camera frames for voice mode are sent directly to OpenAI via WebRTC, not through the
> relay."

**True only on the `.hermes` brain, since #221 (2026-08-01).** As written it tells a
reader on the on-device brain that their camera frames go to OpenAI. They do not — #221
wired the gate at three points precisely so a forbidden brain never *reaches* OpenAI.
The sentence is now both wrong and needlessly alarming, in a security doc, about the
tier most users will be on. Same for `SECURITY.md:39`'s OpenAI-key line, which reads as
unconditional.

### 3.4 🟠 `SECURITY.md:50` + `README.md:169` — the ATS entry rests on a contradiction we have not resolved

Two records in this repo disagree about **why** tailnet HTTP works, and `SECURITY.md:50`
publishes one of them as verified fact.

| record | claim | basis |
|---|---|---|
| **#166b** (archive `:4867`), and `CLAUDE.md`'s ATS section | The CIDR-keyed exception **is load-bearing**: arm 1 (no exception) → BLOCKED −1022; arm 3 (CIDR form) → ALLOWED; arm 4 (outside-range control) → BLOCKED | four-arm experiment, **in the app test host on the simulator** (CLAUDE.md's own correction says "sim, not device") |
| **#167** (archive `:4846`) | The exception is **INERT** — `NSExceptionDomains` keys are domain names, ATS never expands a CIDR, so it "can never match a host like `100.79.222.100`"; traffic works because **bare-IP hosts are not policed** | reasoning from the ATS contract + a device observation that traffic flowed |

They cannot both be right: if bare IPs were unpoliced, **#166b's arm 1 would have
succeeded**. #167's own closing line is the sting — *"an in-session claim that a
successful `curl` … was WRONG. curl does not exercise ATS at all … Only on-device traffic
tests it."* — and #166b's decisive arms were run on **sim**.

**What is not in dispute, and is the part that can hurt a reader:** #167's MagicDNS
consequence. Point a host field at `ojamd.<tailnet>.ts.net` over plain HTTP and ATS
blocks it, with no exception matching and no diagnostic beyond −1022. **`SECURITY.md:50`
and `README.md:169` both invite exactly that move** ("If you serve the backends over
HTTPS (e.g. `tailscale serve` with MagicDNS), you can remove even this scoped
exception") without naming the trap for anyone who tries MagicDNS *without* HTTPS.

**This lane does not resolve the contradiction** — that is bar 140-D and it needs a
device, not a doc edit. **It does stop publishing the disputed half as settled fact and
does name the MagicDNS trap.**

### 3.5 🟡 `README.md:27` · `README.md:47` · `docs/index.html:182` — "plus a session pin"

**Falsified by the source comment written for this exact mechanism**:
`ModelsSettingsScreen.swift:84` — *"no shim POST, no session pin, nothing to await."*
Three public surfaces carry the same wrong half-sentence, presumably because the
2026-08-04 sweep updated the *shim* half of that sentence and left the *pin* half
standing. A session-pin endpoint (`POST /api/sessions/{id}/model`) does exist on `:8642`
— which is probably how the claim survived a skim — **but the app does not call it.**

Harm is low but it is a flat contradiction with our own code, in the row of a table whose
whole purpose is to be believed.

### 3.6 🟡 `README.md:44` · `docs/index.html:240` — voice fallback described by the wrong trigger

> "falling back to an on-device engine **when the relay is unreachable**"

Post-#221 the engine is chosen by **the brain selection**, and only secondarily by
reachability. As written it implies that selecting the on-device brain still lets voice
reach OpenAI whenever the relay happens to be up — which is the precise bug #221 fixed,
found by Owen when it billed tokens he did not intend to spend. Publishing the old
mechanism invites the old expectation.

**Also note, unresolved and Owen's:** #221's own still-open half — *"should a voice
session running on realtime show a visible indicator?"* — is a product question with a
public-copy shadow. `docs/index.html:86` says of the paired tier "**No cloud.** No relay
you don't own." Realtime voice on the `.hermes` brain **does** reach a cloud provider.
"No cloud" is defensible as "no Talaria-operated cloud" and indefensible as read. See §8.

---

## 4. ⚠️ Tracker corrections

Corrections go **upstream, to the stale claim's own home** (CLOSE-OUT RULE). None are
applied here — this is a dispatch. The orchestrator files them.

**4.1 — `OPEN_ITEMS.md` #140's header is falsified by its own body.**
Header (`:3165`): *"stale wedge narrative + pre-freemium positioning."* The body four
lines down (`:3176-3213`) records the copy half DONE 2026-08-04 and the redesign SHIPPED
2026-08-04 night. The header describes a state the entry itself says ended five days ago.
**Proposed header:** `140. 🔧 Public-face accuracy — copy half DONE 2026-08-04 (README +
Pages); SECURITY.md never swept; screenshots still batched with P-4`.
*(This is Phase 0's own failure shape again — the top of an entry reads as its summary.
The INDEX mirror at `OPEN_ITEMS.md:151` carries the same stale text and moves with it.)*

**4.2 — `PLAN-FINISH-OPEN-ITEMS.md:250` is falsified.**
> "| **#140** | README + GitHub Pages refresh — **currently carries a stale wedge
> narrative and pre-freemium positioning** | Claude |"

Written 2026-08-01; falsified 2026-08-04 by `d1356b1`. **Proposed replacement:**
`README + Pages positioning DONE 2026-08-04; remaining = SECURITY.md sweep (never done)
+ the P-4 screenshot batch`.

**4.3 — `PLAN-FINISH-OPEN-ITEMS.md:252-256`'s ⚠️ box publishes the #167 side of an
unresolved contradiction as settled.**
> "**#167's MagicDNS landmine stays defused** — the shipped ATS exception keys a CIDR
> literal, **which ATS never matches**, so plain-IP tailnet traffic works only because
> bare IPs are not policed."

That is #167's mechanism stated as fact, and #166b's four-arm result contradicts it (§3.4).
The *operational* advice ("do not point a host field at MagicDNS") is right under **both**
readings and should stay; the mechanism sentence should be marked disputed pending 140-D.

**4.4 — `OPEN_ITEMS.md` #58's header is stale and would have caused a false correction here.**
Header (`:831`): *"controls DEAD on device 2026-07-25."* #254 (2026-08-05, build 2034)
records both Control Center buttons **confirmed working, repeatedly**. I nearly filed the
README's "lock-screen controls" row as a false claim on the strength of #58's header.
**#58's header needs #254's result folded in, upstream**, and the correction belongs in
#58, not only in #254.

**4.5 — `planning/LAUNCH_PASS-2026-07-20.md` P-4 still assumes iPad screenshot sets.**
`:178` — "Screenshots: 6.9" + 13" iPad sets (iPad in scope)" resting on the doc's header
decision *"iPad IS in v1.0 scope (Lane J matrix is launch-blocking)."* #109 (True iPad
multi-window) is still open on the live board. **Not falsified — flagged as a decision
that has gone 20 days without re-confirmation** and that doubles the screenshot batch.
Owen's to re-affirm or drop (§8).

**4.6 — a note on method, since this lane exists because of it.** Four of the six live
claims in §3 were introduced or preserved by a sweep that *did* correct the same
sentences elsewhere. The failure was never the writing; it was that **no sweep began by
listing the surfaces it owed.** Task 0 below exists to make that impossible next time.

---

## 5. Proposed bars

**Bars go in the `OPEN_ITEMS.md` #140 entry before any work starts.** Proposed in full
here; the orchestrator files them. **This is a documentation lane: 140-A/B/C cannot be
tests, and I say so plainly under each.** Only 140-D is a measurement, and it is the one
that needs a device.

---

**140-A — every public surface agrees with HEAD on the six §3 claims.**

*Evidence that settles it (not a test — an enumerated diff review):* a single commit
whose diff touches `SECURITY.md`, `README.md`, `docs/index.html` and shows, for each of
the six claims in §3, either corrected text or an explicit written reason it stands.
**Met** = all six accounted for, and a fresh grep of all three files for the retired
terms returns only intentional "retired"/"removed" framings:

```
grep -rniE 'models shim|:8765|APNs|push notif|session pin' README.md SECURITY.md docs/*.html
```

**Why this cannot be a unit test:** nothing compiles these files. There is no assertion
surface. The grep is the closest thing to a mechanical check and it is a *guard*, not a
proof — it cannot tell a corrected sentence from a deleted one. The diff review is the
evidence; the grep only stops a regression.

**140-B — no public surface asserts a capability the app has not been shown to have.**

*Evidence:* a written claim inventory (Task 0's artifact) in which every capability
sentence on README/Pages carries one of three marks — **VERIFIED** (with the file:line or
tracker item that proves it), **HEDGED** (copy softened to what is proven), or
**REMOVED**. **Met** = zero sentences left unmarked, and zero marked VERIFIED without a
citation. The `docs/index.html:122` Siri-in-the-SOLO-column claim (§2.3) must resolve to
VERIFIED-with-a-device-check or HEDGED; it may not stay as-is.

**Why this cannot be a test:** it is an audit of prose against evidence. The falsifiable
part is the *inventory*, not the app — an unmarked sentence fails the bar.

**140-C — SECURITY.md is re-derived, not patched.**

*Evidence:* the Deployment-model and Relay sections describe **two** services; the iOS
section's OpenAI/camera claims are brain-conditional; and the ATS entry no longer states
a disputed mechanism as verified. **Met** = a reviewer handed only `SECURITY.md` and the
architecture diagram from `README.md:62-73` finds no disagreement between them.

**Why this cannot be a test:** same reason. The specific, checkable failure condition is
"SECURITY.md and README's architecture diagram describe a different number of services" —
which is exactly the defect that survived 2026-08-04 for five days.

**140-D — the ATS mechanism contradiction is settled ON DEVICE, or the public text stops claiming to know.**

*Evidence, and this one IS a measurement:* on the physical device (`whoGoesThere`, not
sim — #167's own method correction says only device traffic tests ATS), three arms
against a live tailnet host over plain HTTP:
1. shipping `project.yml` (CIDR exception present), bare IP → expect 200
2. exception stripped, bare IP → **#166b predicts −1022 · #167 predicts 200**. This arm
   alone decides it.
3. shipping `project.yml`, **MagicDNS name** over HTTP → expect −1022 under both readings
   (this is the landmine; confirming it is cheap and it is what the public warning rests on)

**Met** = arm 2 returns an unambiguous result, recorded in #166b's *and* #167's entries
(upstream, both), and `SECURITY.md:50` / `README.md:169` / `CLAUDE.md`'s ATS section /
`PLAN-FINISH-OPEN-ITEMS.md:255` all agree with it afterwards.

**Fallback if no device sitting is available:** 140-D is **not** a blocker for A/B/C.
The fallback is to publish neither mechanism — state the *observed* fact ("plain HTTP to
tailnet IP addresses works on the shipping configuration; do not point a host field at a
MagicDNS name over HTTP") and drop the parenthetical that explains why. **Honest and
shorter beats confident and contested.**

**140-E — the P-4 screenshot batch stays OUT.**

*Evidence:* the commit touches no file under `docs/img/`. **Met** = trivially checkable,
and it exists to stop this lane from quietly absorbing a device-time-expensive job that
Owen sequenced into P-4 on purpose. The 13 renders are already labelled honestly; they
are not a lie, only old.

---

## 6. Task breakdown

Real paths. **Every proposed copy line below is a PROPOSAL AWAITING OWEN'S APPROVAL** —
none of it may be written to a file until he has read the exact text. `docs/` is the live
Pages web root; nothing under it is edited without his go.

### Task 0 — the surface inventory (do this FIRST; it is why the lane exists)

Produce, in the working branch, a claim inventory: every capability sentence in
`README.md`, `SECURITY.md`, `docs/index.html`, `docs/setup.html`, `docs/screens.html`,
each with file:line, the mark VERIFIED / HEDGED / REMOVED, and its citation. This is
140-B's evidence and it is the artifact that makes the next sweep impossible to
half-finish. Est. 45 min. **No file outside the branch is touched.**

### Task 1 — `SECURITY.md`, the never-swept surface (the bulk of the lane)

**1a — `SECURITY.md:15`.** *Proposed — AWAITING OWEN:*

> "Talaria is designed for **private-network self-hosting**. The expected deployment puts
> both host services (Sessions API `:8642`, relay `:8000`) on a Tailscale tailnet or
> equivalent private network, reachable only by your own devices. Neither service is
> intended to be exposed to the public internet. *(Earlier versions used a third service,
> a models shim on `:8765`; it is retired and current builds never call it.)*"

**1b — `SECURITY.md:25`.** *Proposed — AWAITING OWEN:*

> "The relay carries everything phone-facing except chat: pairing and auth, sensor
> ingestion, the inbox/directives channel, scheduled runs, agent-file downloads, and the
> voice WebRTC bootstrap. *(The app registers for no remote push and posts no
> notifications; the relay's APNs plumbing is legacy and unused by current builds.)*"

**1c — `SECURITY.md:46`, and `:39` alongside it.** *Proposed — AWAITING OWEN:*

> "**Camera/mic:** Requested just-in-time, not at launch. Realtime voice runs **only when
> the Hermes brain is selected** — on the on-device brain the app never contacts the
> realtime provider at all. When realtime is in use, camera frames go directly to OpenAI
> via WebRTC, not through the relay."

**1d — `SECURITY.md:50`.** Two edits. Drop the "(Verified 2026-07-22 …)" parenthetical
that publishes the disputed mechanism (§3.4) — or, if 140-D has run, replace it with the
device result. Then add the MagicDNS trap, which is true under both readings.
*Proposed addition — AWAITING OWEN:*

> "**Note:** the exception is keyed to the CGNAT **address range**. Plain-HTTP traffic to
> a **MagicDNS name** (`host.<tailnet>.ts.net`) is not covered and iOS will block it. If
> you want to use MagicDNS names, serve the backends over HTTPS (`tailscale serve`) — at
> which point you can remove this exception from `project.yml` entirely."

**1e — while in the file:** `SECURITY.md` has **no privacy-policy link**, and neither does
`README.md` or any Pages file (verified: `grep -rniE 'privacy.?polic'` over all of them
returns nothing). A public privacy-policy URL is #166a's Owen-side hard stop condition
and it is one of the two items in Plan B's "startable any time" carve-out. **Do not
invent one.** Add the link only once Owen has a URL; flag it here so the lane knows it is
the natural home for it. See §8.

### Task 2 — the "session pin" sentence, three files

`README.md:27`, `README.md:47`, `docs/index.html:182`. *Proposed — AWAITING OWEN:*

> "The full provider roster comes from the gateway's own API. Your pick rides **every
> turn** as a model lock — no session restart, no third service."

(Applies with light rewording at each of the three sites; the important part is that
"plus a session pin" does not survive anywhere.)

### Task 3 — the voice fallback trigger, two files

`README.md:44`, `docs/index.html:240`. *Proposed — AWAITING OWEN:*

> "**Voice mode** — realtime WebRTC speech-to-speech with server-side voice, continuous
> mic, mute and barge-in, **when the Hermes brain is selected**. On the on-device brain
> voice runs entirely on an on-device engine and never reaches a remote provider."

### Task 4 — the Siri-in-SOLO claim (`docs/index.html:122`)

**Blocked on evidence, by design.** Two exits, and 140-B forces one of them:
- **If a device check confirms** the Ask intent answers from the local brain with no
  host: the line stands as VERIFIED and the check goes in the tracker.
- **If no check is run:** hedge. *Proposed — AWAITING OWEN:*
  > "Siri and App Intents, and conversations index into Spotlight *(Siri asks are routed
  > to whichever brain is selected)*"

Cross-reference #255 for the "Ask **Hermes**" spoken copy; do not fix branding here.

### Task 5 — the deferred-by-design list, recorded so it is not re-discovered

Not touched by this lane, named so the next reader knows it was a decision:
`docs/img/` (P-4), the "NO APP STORE · NO TESTFLIGHT" line at `docs/index.html:91`
(true today, falsified by #8/#166 on submission day — belongs to that lane's checklist,
see `OPUS-T27-166-8-appstore-runbook.md` §6 Task 9), and #255's de-branding.

### Task 6 — the gate

`scripts/mac/lane-gate.sh`. **Yes, on a docs-only lane** — cheap, and it proves the
branch did not pick up a stray source edit. If the diff is genuinely markdown+HTML only,
say so and record the gate result anyway.

---

## 7. Ownership split

**Claude's:**
- Task 0's inventory; drafting all copy in Tasks 1–4; the greps and file:line citations
- The four upstream tracker corrections in §4 (as edits proposed to the orchestrator —
  **this dispatch does not touch `OPEN_ITEMS.md`**)
- Running the gate; opening the PR **as a draft**

**Owen's:**
- **Reading and approving the exact text of every proposed line above before it is
  written.** This is the standing no-external-submissions rule applied to the repo's
  public face: `docs/` is a live website.
- 140-D's device arms (a phone sitting; ~15 min, foldable into any sitting — it is a
  three-arm HTTP check, not a battery)
- The privacy-policy URL itself (Task 1e) — external latency, startable any time
- The `docs/img/` screenshot batch, when P-4 runs
- Merging. **Nothing here gets published without his go.**

**Neither, and stated so it is not silently assumed:** nobody files a GitHub issue,
publishes a release, or edits the live Pages deployment out of band. The Pages site
updates only when Owen merges to the branch that serves it.

---

## 8. What is OWEN'S to decide

1. **The privacy-policy URL.** #166a names it a hard stop condition; there is none
   anywhere in the repo today. Where does it live — a `docs/privacy.html` page on the
   existing Pages site (cheapest, one more static file, same domain), or somewhere off-
   repo? **Claude can draft the policy text from the app's actual data flows; Owen owns
   publishing it.** This is one of only two items Plan B lets start early.
2. **"No cloud" on the paired tier** (`docs/index.html:86`). Realtime voice on the
   `.hermes` brain reaches OpenAI. Keep the line as shorthand for "no Talaria-operated
   cloud", or qualify it? This is the copy shadow of #221's still-open product question
   (*"should a voice session running on realtime show a visible indicator?"*) — **the same
   decision in two places, and answering it once should answer both.**
3. **Is iPad still in v1.0 scope?** `LAUNCH_PASS-2026-07-20.md`'s header decision says
   yes and P-4 sizes the screenshot batch accordingly (6.9" + 13" sets). #109 is still
   open. Twenty days without re-confirmation, and it doubles a job that is already the
   expensive part of P-4.
4. **Does 140-D run, or does the ATS text go silent on mechanism?** Both are honest. The
   device arm is cheap and would settle a contradiction that currently spans four
   documents including `CLAUDE.md`.
5. **Does the Siri-in-SOLO claim get its device check, or get hedged?** (Task 4.)

---

## 9. Close-out

**#140 does not close until:**

- 140-A, 140-B, 140-C, 140-E are met and recorded in the `OPEN_ITEMS.md` #140 entry with
  their evidence, not their intentions
- 140-D is either met, or explicitly declined with the fallback text shipped
- **Every entry this lane's result falsifies is corrected in the same commit, upstream:**
  #140's own header (§4.1), `PLAN-FINISH-OPEN-ITEMS.md:250` (§4.2) and `:252-256` (§4.3),
  #58's header (§4.4), and — if 140-D runs — #166b, #167, `CLAUDE.md`'s ATS section and
  `PLAN-FINISH-OPEN-ITEMS.md:255`, all four together
- The claim inventory from Task 0 is committed. **It is the deliverable that outlives the
  lane** — the next sweep starts by reading it instead of by guessing which files are
  public.

**Explicitly NOT closed by this lane:** the P-4 screenshot batch, #255's de-branding,
#109's iPad question, #221's realtime-indicator question, and the "NO TESTFLIGHT" line
that #8/#166 will falsify. All are filed elsewhere and stay there.
