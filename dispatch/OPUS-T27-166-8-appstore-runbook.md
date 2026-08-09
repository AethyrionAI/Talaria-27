# OPUS-T27-166+8 — App Store runbook: what is left, who owns it, and why #8 is not a lane

**Label:** OPUS · **Items:** #166 (App Store review-risk register) + #8 (TestFlight) ·
**Written:** 2026-08-09
**Status:** DISPATCH ONLY. No App Store Connect entry, no TestFlight build, no GitHub
release, no public artifact, no `OPEN_ITEMS.md` edit, nothing submitted anywhere.

**Goal:** turn #166's open sub-items into an executable checklist with honest ownership,
correct the four sub-items its own entry still describes as open when they shipped
2026-07-22, add the four review risks the register never had, and settle whether #8 is a
gate, a lane, or a step.

> **THE ANSWER ON #8, UP FRONT: it is a STEP inside #166's submission sequence, not an
> independent lane.** Every sentence of its filing is falsified (§4.2), and what remains
> real about TestFlight — the upload rehearsal — is *already* gated on #166e's portal
> pre-flight and #166f's runbook. **#268's rule applies exactly: a name is not a filing.**
> Bundled here. Justification in §3.3.

> **Owen's two rulings are load-bearing and are NOT re-decided anywhere below:**
> **(1) the App Store gate goes LAST** (`PLAN-FINISH-OPEN-ITEMS.md:15-27`), and
> **(2) #166c is much smaller than it was filed** — *"A reviewer need not join a tailnet.
> They're testing the local brain. Everything else is extra"* (`:29-47`). Both hold at
> HEAD; §2.4 re-verifies the single condition ruling (2) depends on.

---

## 1. What this lane is

#166 is a **register**, not a lane — a severity-ordered list of what App Review will hit
us with. Half of it shipped 2026-07-22 and the entry was never updated. This dispatch
produces the executable remainder.

**Nothing here is submission.** The deliverable is a runbook in
`planning/LAUNCH_PASS-2026-07-20.md` §P-4 and a set of pre-flight checks. The moment
anything would be *sent* to Apple, GitHub, or a public URL, it stops and waits for Owen.

---

## 2. Verified state

Read at HEAD (`35c6234`) today. **VERIFIED** = read in the named file. **ASSUMED** =
inferred, flagged.

### 2.1 VERIFIED — three of the six sub-items are DONE, and #166 does not say so

| sub-item | #166 says (`OPEN_ITEMS.md`) | HEAD says | verdict |
|---|---|---|---|
| **166a** privacy manifests | `:3849` — *"Talaria has **none** for any target (app, TalariaWidgets, TalariaShare — verified by find)"* | `Talaria/Resources/PrivacyInfo.xcprivacy`, `TalariaWidgets/PrivacyInfo.xcprivacy`, `TalariaShare/PrivacyInfo.xcprivacy` all exist; shipped by `6d1515e` 2026-07-22 | ✅ **DONE** |
| **166b** ATS | `:3851` — *"**Test on a dev build:** strip our global exception…"* | `project.yml:333-347` — `NSAllowsArbitraryLoads` gone, replaced by a range-scoped `NSExceptionDomains` keyed `"100.64.0.0/10"` | ✅ **DONE** (with a caveat — §2.5) |
| **166d** encryption key | `:3855` — *"Ours: **absent** from project.yml (verified)"* | `project.yml:352` — `ITSAppUsesNonExemptEncryption: false` | ✅ **DONE** |

**All three closed under #167** (`OPEN_ITEMS-ARCHIVE.md:4846`, PR #138, merge `cbcc824`),
whose own line `:4873` reads: *"Remaining from #166: 166c … 166e … 166f."*

**So the correction exists — it just lives downstream, in a different item, in a different
file, and #166 was never told.** A reader opening #166 today is told to do three jobs that
are done. That is the CLOSE-OUT RULE violation this dispatch's §4.1 fixes.

### 2.2 VERIFIED — what actually remains

- **166c** — review-notes framing. Re-scoped by Owen 2026-08-01 from "launch requires a
  public review host" to a **writing task**. Not started.
- **166e** — portal capability pre-flight. **Owen's**, per `PLAN-FINISH-OPEN-ITEMS.md:246`.
  Not started. **Its checklist is now partly wrong** — §3.1.
- **166f** — adopt hermex's runbook skeleton (Stop Conditions / Review Notes / Risk
  Register / Definition of Ready) into `planning/LAUNCH_PASS-2026-07-20.md` §P-4, *not* a
  new file. Not started.
- **#127's ASC half** — product id **exactly** `org.aethyrion.talaria27.connected` +
  a sandbox tester. Owen's. Not started.
- **#8** — see §3.3.

### 2.3 VERIFIED — the ownership split, from the plan's own table

`PLAN-FINISH-OPEN-ITEMS.md:243-250` assigns: **166c** → *"Claude drafts, Owen approves"*;
**166e** → *"Owen"*; **166f** → *"Claude"*; **#127** → Owen; **#8** → *"both"*;
**#140** → Claude.

**Note a conflict, resolved in favour of the newer record:** #166's own line `:3862` says
*"166c/166e/166f are Owen-side prep."* The plan (2026-08-01) re-assigned 166c and 166f to
Claude when it re-scoped 166c. **The plan wins — it is Owen's later ruling** — but #166
was never corrected, so the two disagree in the repo today (§4.1). **166e is Owen's under
both records and is treated as Owen's throughout.**

### 2.4 VERIFIED — the condition Owen's #166c ruling depends on still holds

The re-scope holds *"under one condition"*: that the monetization gate ships dormant, so
there is no purchasable feature for a reviewer to be unable to exercise (2.1 / 2.3.1).

Re-verified at HEAD:
- `Talaria/Services/Support/MonetizationGate.swift:29` — `static let isEnabled = false`
- The paywall has exactly **three** presentation sites, all behind
  `container.connectGateVerdict(for:)`: `ContentView.swift:233-234`,
  `ServerSettingsScreen.swift:231`, `UplinkSettingsScreen.swift:164`. With `isEnabled =
  false` the verdict is `.allow` and none of them render.
- `MonetizationGateTests.swift` pins dormancy (#127: *"the test fails loudly on flip day"*).

**✅ The condition holds. Owen's ruling stands.** And the corollary he named stands too:
**the day "Connected" becomes purchasable, the reviewer-reachable-host question comes
back.**

### 2.5 VERIFIED — 166b shipped, but its *explanation* is disputed in-repo

`project.yml:333-347` is unambiguous about what shipped. **Why it works is not settled.**
#166b (archive `:4867`) says the CIDR-keyed exception is load-bearing on a four-arm
experiment; #167 (archive `:4846`) says it is **inert** and traffic flows only because
bare IPs are unpoliced. They are mutually exclusive — if bare IPs were unpoliced, #166b's
no-exception arm would not have returned −1022. #166b's arms ran on **sim**; #167's own
closing note says only device traffic tests ATS.

**Consequence for this lane, and it is narrow:** 166c's review notes and the App Privacy
answers must not repeat a mechanism we cannot defend. **Full analysis and the deciding
device arm live in the sibling dispatch** — `OPUS-T27-140-public-face-refresh.md` §3.4
and bar 140-D. Do not duplicate the experiment here.

### 2.6 VERIFIED — capabilities actually present in the tree

Read from `project.yml` and the three `.entitlements` files:

| capability | app | widgets | share |
|---|---|---|---|
| App Group `group.org.aethyrion.talaria` | ✅ `:62-63` | ✅ `:388-389` | ✅ `:430-431` |
| HealthKit (+ `.access`, + background-delivery on app) | ✅ `:46-48` | ✅ `:386-387` | — |
| **WeatherKit** | ✅ `:52` | — | — |
| `aps-environment` (push) | **ABSENT** | ABSENT | ABSENT |
| CarPlay voice entitlement | **commented out**, `:61` | — | — |
| Siri / SiriKit entitlement | **not present** (App Intents needs none) | — | — |

Bundle ids: `org.aethyrion.talaria27` · `.Widgets` · `.share` (`:85`, `:406`, `:459`).
`CODE_SIGN_STYLE: Automatic` on all three (`:102`, `:411`, `:464`).
`DEVELOPMENT_TEAM: DNL25ZFSD2` on all three — **a real team, not a placeholder** (`:101`,
`:412`, `:465`).

### 2.7 ASSUMED — not proven, and I am not able to prove it from this machine

- **ASSUMED: the portal state.** Whether the three bundle IDs are registered, whether the
  App Group exists, whether HealthKit/WeatherKit are enabled on the App ID, whether an
  ASC app record exists at all. **None of this is inspectable from the repo.** It is
  166e, it is Owen's, and it is the single largest unknown in this dispatch.
- **ASSUMED: no build has ever been uploaded**, so no ITMS validation has ever run
  against this binary. Nothing in the repo records one. If one has, its error list
  supersedes half of §3.
- **ASSUMED: hermex's `TESTFLIGHT.md` is still the reference.** It was read from a
  shallow clone 2026-07-22 and is not in this tree. 166f's port works from #166's summary
  of it, which is what we have.

---

## 3. What the register is missing — four risks it never had

#166 was built by mapping hermex's runbook onto Talaria. **hermex did not have HealthKit,
background location, background audio, CarPlay, or an agent that renames itself.** These
four are ours alone and none appears in the register.

### 3.1 🔴 166e's checklist is now WRONG in two directions

`OPEN_ITEMS.md:3857` reads: *"bundle IDs for app + widgets + share extension registered;
App Group enabled across all three; **push (aps-environment)**, HealthKit,
**Siri/App Intents** capabilities on the App ID; CarPlay deliberately NOT requested."*

- **Push must come OUT.** `aps-environment` is absent from `project.yml` and from all
  three `.entitlements` files (verified §2.6). #238 removed notifications entirely
  2026-08-03. Enabling push on the App ID now provisions a capability the binary does not
  claim — at best noise in the profile, at worst a mismatch at validation.
- **Siri is not an entitlement we carry.** Modern App Intents need none; only legacy
  SiriKit does. Nothing to enable.
- **🔴 WeatherKit is MISSING from the checklist and it is the one most likely to cost a
  cycle.** `project.yml:52` declares `com.apple.developer.weatherkit: true`. WeatherKit
  requires the capability enabled on the App ID **and** the bundle ID registered with
  Apple's weather service. If it is not enabled in the portal, automatic signing cannot
  mint a matching profile and **the archive fails** — which is the exact failure mode
  166e exists to prevent, named in its own last sentence.

### 3.2 🔴 NEW — a CarPlay scene is declared with no CarPlay entitlement

`project.yml:364-370` ships a scene manifest containing
`CPTemplateApplicationSceneSessionRoleApplication` → `CarPlaySceneDelegate`, while the
CarPlay entitlement at `:61` is **commented out** (correctly — #45/#74 are parked on
Apple's discretionary grant).

The app builds and runs fine; the scene simply never connects. **The risk is at upload
validation and at review**, where a declared CarPlay scene role with no corresponding
entitlement is an inconsistency Apple's tooling checks for. #166e's line *"CarPlay
deliberately NOT requested (parked)"* records the entitlement decision and **misses that
the Info.plist still advertises the scene.**

**This is cheap to settle and impossible to settle from here** — it surfaces at Xcode's
*Validate App* step (§6 Task 7), which is exactly why that step is a bar.

### 3.3 🟠 NEW — every system permission dialog says "Hermes"

`project.yml:150-158` and `:165-175`. Verbatim, these are the strings iOS shows the user:

> `NSLocationWhenInUseUsageDescription: "Hermes uses your location to provide contextual
> recommendations and nearby suggestions."`
> `NSHealthShareUsageDescription: "Hermes reads your health data to offer personalized
> wellness insights."`
> `NSContactsUsageDescription: "Hermes looks up contacts you ask about…"`

The app's display name is **`Talaria27`** (`project.yml:103`, `:116`). Two problems, one
of them a review risk:

1. **Review risk (5.1.1(i), purpose strings).** A permission dialog for an app called
   Talaria27 that explains what "Hermes" will do with your health data is, to a reviewer
   with no context, a naming mismatch on the most scrutinized dialogs in the OS.
2. **It is wrong for the default user.** Per the launch pivot, the default user is
   **hostless**. They have no Hermes. The dialogs name a thing that does not exist in
   their install. *(The widget target already says "Talaria" — `project.yml:403` — so the
   tree is internally inconsistent too.)*
3. **`NSHealthUpdateUsageDescription: "Hermes does not write health data, but this
   permission is required by the system."`** It is not required by the system if you do
   not write. Declaring a write purpose you do not use is the kind of inconsistency the
   App Privacy questionnaire will contradict. **Check whether the app writes any
   HealthKit sample before shipping this string.**

**Filed relationship:** the naming half overlaps **#255** (de-branding sweep). This
dispatch does **not** do #255's rename — it flags that the purpose strings are a
**launch-blocking subset** of it and must not wait for the full sweep.

### 3.4 🟠 NEW — background location + background audio are the two most-scrutinized modes, and nothing records our defence

`project.yml:353-357`: `UIBackgroundModes: [fetch, processing, location, audio]`, plus
`NSLocationAlwaysAndWhenInUseUsageDescription`.

Background location is a standing App Review focus; "audio" is checked against whether
the app genuinely plays audio in the background. **Both are defensible here** — the
sensor pipeline is opt-in and **off by default** (#137), and voice mode is real
background audio. **But the defence exists only in our heads and in tracker entries.** It
belongs in 166c's review notes, in one paragraph, before a reviewer asks.

---

## 3.5 Is #8 a gate, a lane, or a step? — a step. Here is the working.

**#8 in full** (`OPEN_ITEMS.md:259-262`):

> "On-device + HealthKit work is gated on a TestFlight build. Ties to item 1 (base URL)
> and the `tailscale serve` HTTPS work. Add Shelley as the second tester when ready."

**Every clause is falsified:**

| clause | status |
|---|---|
| *"On-device + HealthKit work is gated on a TestFlight build"* | **FALSE.** Both have been developed and device-verified for months via corded install and the OTA-over-Tailscale path (`scripts/mac/ota-stage.sh`, proven 2026-07-27, upgrade-install in place). #78's 78-F2 bar was met on the local brain on **OTA 2171** on 2026-08-07. TestFlight gates nothing we are doing. |
| *"Ties to item 1 (base URL)"* | **DEAD LINK.** Item 1 is `OPEN_ITEMS-ARCHIVE.md:25` — *"✅ T4 — Host reconciliation — RESOLVED."* |
| *"and the `tailscale serve` HTTPS work"* | **ABSORBED.** `tailscale serve --bg 8477` is live and carries OTA distribution today. Whatever #8 meant by this, the OTA path met the need. |
| *"Add Shelley as the second tester when ready"* | **The only live clause** — and it is a *step*, not a lane. |

**What is genuinely true about TestFlight, and why it still matters:** it is the **upload
rehearsal.** Archiving and pushing a build runs Apple's full ITMS validation —
ITMS-91053 required-reason errors, export-compliance, capability/profile mismatches, the
CarPlay scene question in §3.2 — **without a public artifact and without App Review.**
That is a genuinely valuable dry run for #166.

**But it cannot happen before #166e**, because uploading needs registered bundle IDs, the
App Group, HealthKit + WeatherKit on the App ID, and an ASC app record. And **external**
TestFlight (which is what "add Shelley" means unless she is an ASC user) needs **Beta App
Review**, which needs 166c's review notes and 166f's runbook.

**Therefore: #8 has no independently actionable content.** Its prerequisites are 166e,
166c and 166f; its only surviving task is one line inside them. **Recommendation: fold
#8 into #166 as step 166g, retitle the tracker entry to record the supersession, and stop
carrying it as a separate future gate.** Owen's call to ratify (§8).

---

## 4. ⚠️ Tracker corrections

Upstream, to each stale claim's own home. **None applied here** — the orchestrator files
them.

**4.1 — `OPEN_ITEMS.md` #166 describes three completed jobs as open.** `:3849` (166a),
`:3851` (166b), `:3855` (166d) all read as unstarted; all three shipped 2026-07-22 under
#167 (PR #138, `cbcc824`). The recommended-sequencing paragraph `:3862` compounds it —
*"166a + 166d are one small speccable lane … 166b is a 30-minute experiment that should
happen BEFORE that lane"* — sequencing work that is done. **Proposed:** a dated
supersession block at the top of #166 marking a/b/d ✅ with the #167 pointer, and
correcting `:3862` to name only 166c/166e/166f. Also correct `:3862`'s *"166c/166e/166f
are Owen-side prep"* to match the plan's re-assignment (§2.3).

**4.2 — `OPEN_ITEMS.md` #8 is falsified in every clause** (§3.5). **Proposed:** retitle to
`8. 📝 TestFlight — SUPERSEDED, folded into #166 as the upload-rehearsal step (see 166g);
original rationale falsified 2026-08-09` and record the four falsifications verbatim.
The INDEX line at `OPEN_ITEMS.md:117` moves with it.

**4.3 — `PLAN-FINISH-OPEN-ITEMS.md:249` still owes `#90`.** > "| **#8** | TestFlight gate;
**#90** DEVELOPMENT_TEAM placeholder cleanup | both |". **#90 closed 2026-08-06**
(`OPEN_ITEMS-ARCHIVE.md:13255`, *"archived as terminal"*), and `project.yml` carries a
real team on all three targets (§2.6). **Proposed:** strike #90 from the Phase 7 table.

**4.4 — `OPEN_ITEMS.md` #166e's checklist is wrong on push and silent on WeatherKit**
(§3.1). This is the correction most likely to cost a real cycle if it is not made, because
166e is the item Owen will work *from*.

**4.5 — `PLAN-FINISH-OPEN-ITEMS.md:252-256` publishes the disputed ATS mechanism as
settled** (§2.5). Detail and the deciding bar are in the #140 dispatch (§4.3 there); noted
here only so the two dispatches do not each half-fix it.

**4.6 — a refinement to the plan's carve-out, not a falsification.**
`PLAN-FINISH-OPEN-ITEMS.md:258-262` says *"creating the App Store Connect records"* is
startable any time because its latency is external. **True for the app record. Handle the
IAP product with more care:** creating `org.aethyrion.talaria27.connected` early is fine
and useful (it unblocks #127's sandbox round-trip), but **it must not be submitted for
review alongside a build whose gate is inert** — a configured, reviewable product with no
reachable purchase path is precisely the 2.3.1 shape #166f warns about. **Create early,
submit at the flip.** Owen's to confirm (§8).

**4.7 — the review-risk register has no owner for §3.2–3.4.** They are new risks found
today, they belong in #166 as new sub-items (proposed: **166h** CarPlay scene/entitlement
mismatch, **166i** purpose-string naming + the HealthKit-write string, **166j** background
modes justification), and per #268's rule they get numbers the day they are named — not
when someone gets to them.

---

## 5. Proposed bars

**Bars go in the `OPEN_ITEMS.md` #166 entry before any work starts.** Proposed in full;
the orchestrator files them.

**This is a process-and-documents lane. 166-A, 166-B, 166-D and 166-F cannot be tests, and
I say what settles each instead. 166-C and 166-E are mechanical and genuinely checkable.**

---

**166-A — the register is true: every sub-item's stated status matches HEAD.**

*Evidence (not a test — a line-by-line reconciliation):* a table in the #166 entry with one
row per sub-item a–f plus the new h–j, each carrying its status and the file:line or
commit that proves it. **Met** = a reader who opens #166 and does exactly what it says
does no completed work and skips no live work. **Falsified by** any sub-item whose text
asserts a state the tree contradicts — which is the current condition of three of them.

**166-B — the review notes exist, are ≤2 pages, and answer the reviewer's actual questions.**

*Evidence:* a drafted review-notes section in `planning/LAUNCH_PASS-2026-07-20.md` §P-4
that answers, each in one paragraph: (1) why no account or login is needed; (2) that the
on-device brain is the reviewable product and needs no server — Owen's ruling; (3) that
paired features require the reviewer's own hardware and are not exercisable, and why that
is normal for self-hosted clients; (4) why background location and background audio exist
and that sensors are **off by default** (§3.4); (5) that no purchase flow is reachable
(§2.4). **Met** = all five present, and **a person who has never seen this repo can read
it and predict what the app will do when launched cold.**

**Why this cannot be a test:** it is prose aimed at a human reviewer. The falsifiable
proxy is the five-question checklist — a missing answer fails the bar.

**166-C — a Release archive builds and passes Apple's own validation, with zero ITMS errors.**

*Evidence — and this one IS mechanical:* `xcodebuild archive` on the Release
configuration, then **Xcode Organizer → Validate App** against the ASC record. **Met** =
validation returns no errors. **This is the bar that catches §3.1's WeatherKit provisioning
gap, §3.2's CarPlay scene mismatch, and any ITMS-91053 the privacy manifests missed** —
none of which any test in this repo can see.

**Two hard constraints:** *Validate App* requires the ASC record (166e, Owen's), and
**validation is not submission** — it uploads nothing to a public surface and creates no
TestFlight build. **The archive is Claude's to produce; pressing Validate is Owen's**, and
the run stops there regardless of the result.

**166-D — the purpose strings name the app, not the host.**

*Evidence:* every `NS*UsageDescription` in `project.yml` reads correctly for a user with
**no host paired**, and `NSHealthUpdateUsageDescription` is either removed or justified by
an actual HealthKit write. **Met** = a grep of `project.yml` for `UsageDescription` shows
no string containing "Hermes" that describes a device-local capability, and the app target
agrees with the widget target's existing "Talaria" phrasing.

```
grep -n 'UsageDescription' project.yml | grep -i hermes
```
must return nothing. **Why this is a bar and not a #255 line item:** these strings are
shown by the OS to every user at first grant and are read by App Review.

**166-E — the review build has no reachable purchase surface.**

*Evidence:* `MonetizationGate.swift:29` still `false`; `MonetizationGateTests`'
dormancy test still green; and — because a green **Debug** suite cannot see a mis-set
gate (#218's corollary) — **a Release build** confirming the DEBUG override compiles out.
`scripts/mac/lane-gate.sh` covers both halves. **Met** = gate PASS with the Release marker
positive, plus a walk of the three paywall sites (§2.4) showing none renders.

**166-F — the runbook skeleton lands in P-4, not in a new file.**

*Evidence:* `planning/LAUNCH_PASS-2026-07-20.md` §P-4 gains four labelled subsections —
**Stop Conditions**, **Review Notes** (166-B's output), **Known Risk Register**,
**Definition of Ready** — and **no new runbook document is created anywhere outside
`dispatch/`**:

```
find . -path ./.claude -prune -o -iname '*RUNBOOK*' -print
```
must return **only this dispatch file**. **Met** = both halves. #166f's own instruction is
*"Fold into the existing launch-pass doc rather than a new file"*, and the second half of
that bar is the part that gets forgotten.

**166-G (the #8 remnant) — TestFlight is recorded as a step with a prerequisite chain, not
as a standing gate.**

*Evidence:* #8's entry carries the four falsifications from §3.5 and points at 166g;
166g's step in P-4 names its prerequisites in order (166e → archive → 166-C validation →
internal testers → Beta App Review only if external). **Met** = a reader can tell, from
#8 alone, that there is nothing to do there yet and exactly what would change that.
**Explicitly NOT met by** creating a TestFlight build — no build is created by this lane.

---

## 6. Task breakdown

Real paths. **Every task stops at the boundary where something would be sent.**

### Claude's tasks

**Task 1 — reconcile #166 (166-A).** Draft the supersession block and the corrected
sub-item table for `OPEN_ITEMS.md` #166, incl. the corrections in §4.1 and §4.4 and the
three new sub-items 166h/166i/166j from §3.2–3.4. **Hand to the orchestrator; do not edit
`OPEN_ITEMS.md`.**

**Task 2 — draft #8's supersession (§4.2, bar 166-G).** Same handling.

**Task 3 — 166f: the runbook skeleton.** Edit
`planning/LAUNCH_PASS-2026-07-20.md` §P-4 to add the four subsections (166-F). `planning/`
is **not** the Pages web root — this file is safe to edit. Populate **Known Risk Register**
from #166a–j with today's statuses; populate **Stop Conditions** from hermex's, translated:
privacy-policy URL live · support URL live · ASC record exists · export compliance
answered · gate inert · archive validates clean.

**Task 4 — 166c: draft the review notes (166-B).** Five paragraphs, into the same §P-4
section. **Owen approves the exact text before it goes anywhere near App Store Connect.**
Cross-reference the sibling #140 dispatch: the ATS mechanism must not be asserted here
while §2.5's contradiction stands.

**Task 5 — 166i: the purpose strings (166-D).** Propose replacement
`NS*UsageDescription` text in `project.yml`, app target, `:150-175`. **Propose, then wait
for Owen's read** — these are user-visible strings in permission dialogs, and the naming
question is his. Resolve the `NSHealthUpdateUsageDescription` question first by checking
whether any HealthKit write exists in `Talaria/Services/Live/LiveHealthService.swift`; if
none, propose removing the key with the entitlement, not just rewording it.

**Task 6 — 166e's corrected checklist.** Rewrite §3.1's list into a portal checklist Owen
can execute in one sitting: three bundle IDs · App Group across all three · HealthKit on
app **and widgets** · **WeatherKit on the app** · **no push** · **no Siri** · CarPlay not
requested. **Claude writes the checklist; Owen executes it.** Nothing in this task touches
the portal.

**Task 7 — the archive half of 166-C.** Produce a Release archive with
`DEVELOPER_DIR=/Applications/Xcode-beta4.app/Contents/Developer`, backgrounded and polled
(the gate and archives both exceed the 4-min MCP cap). **Stop at the archive.** Do not
press Validate; do not export; do not upload.

**Task 8 — the gate (166-E).** `scripts/mac/lane-gate.sh`, backgrounded, with a positive
Release marker confirmed.

**Task 9 — the copy that submission day falsifies.** One line, recorded in P-4's
Definition of Ready: `docs/index.html:91` reads *"NO APP STORE · NO TESTFLIGHT · YOU BUILD
AND SIGN IT YOURSELF"*, and `README.md:34` says the same. Both are true today and both are
false the moment #8's step runs. **Recorded, not fixed** — the #140 dispatch owns the
public face and explicitly defers this.

### Owen's tasks

**Task O1 — 166e, the portal pre-flight.** Task 6's checklist, in the Developer portal.
**The single largest unknown in this dispatch** (§2.7) and the prerequisite for everything
downstream.

**Task O2 — the ASC app record.** In the carve-out; startable any time.

**Task O3 — #127's IAP product** `org.aethyrion.talaria27.connected`, exactly, plus a
sandbox tester. **Create early; do not submit for review until the flip** (§4.6).

**Task O4 — the privacy-policy URL.** #166a's hard stop condition; **there is none in the
repo today** (verified — `grep -rniE 'privacy.?polic'` across `README.md`, `SECURITY.md`,
`docs/*.html`, `CONTRIBUTING.md` returns nothing). Claude can draft the text from the
app's real data flows; Owen owns publishing it. See the #140 dispatch §8 for where it
could live.

**Task O5 — press Validate (166-C).** After O1 and Task 7.

**Task O6 — read and approve** Task 4's review notes and Task 5's purpose strings.

---

## 7. Ownership split

**Claude's, unambiguously:** Tasks 1–9. Drafting, reconciling, checklists, the runbook,
the archive, the gate. **Every deliverable is a file in this repo or a proposal handed to
the orchestrator.**

**Owen's, unambiguously:** O1–O6. **Everything that touches Apple, everything that touches
a public URL, and every user-visible string.** Per `PLAN-FINISH-OPEN-ITEMS.md:246`, 166e
is his by name, and this dispatch does not spec Claude doing portal work — Task 6 produces
the checklist he executes and stops there.

**Neither, and stated so it cannot be assumed:** no App Store Connect entry is created by
this lane, no TestFlight build is uploaded, no GitHub release is cut, no issue or PR is
filed with anyone outside this repo, and nothing under `docs/` is published. **If a task
appears to require one of those, it has left the lane — stop and ask.**

---

## 8. What is OWEN'S to decide

1. **Ratify folding #8 into #166 as 166g** (§3.5), or keep it filed separately with a
   corrected rationale. My recommendation is to fold it; the argument is in §3.5 and the
   evidence is that all four of its clauses are dead.
2. **The purpose strings, and how far the rename goes** (§3.3). Do the dialogs say
   "Talaria", "Talaria27", or something else — and does that decision pull #255's
   de-branding forward, or does only the launch-blocking subset move now? *(Related, and
   worth deciding once: `CFBundleDisplayName` is `Talaria27`, which is also what binds
   the Siri phrase to "Ask Talaria27" per #56. The App Store name, the dialog name and
   the Siri phrase are one decision wearing three hats.)*
3. **When the IAP product gets created vs submitted** (§4.6). Early creation unblocks
   #127's sandbox round-trip; early *submission* is a 2.3.1 risk.
4. **Is iPad still in v1.0 scope?** `LAUNCH_PASS-2026-07-20.md`'s header decision says yes
   and P-4 sizes screenshots for 6.9" **+ 13" iPad**. #109 is still open on the live
   board. This doubles P-4's most expensive job. *(Raised in the #140 dispatch too — one
   answer serves both.)*
5. **Does the ATS mechanism get settled on device before the review notes are written?**
   (§2.5, bar 140-D in the sibling dispatch.) The notes can be written either way; they
   are shorter and safer if we stop claiming to know.
6. **Where the privacy policy lives** (O4).

---

## 9. Close-out

**#166 does not close until:**

- 166-A through 166-G are met and recorded **in the `OPEN_ITEMS.md` #166 entry**, each
  with its evidence
- **Every entry this lane falsifies is corrected in the same commit, upstream:** #166's
  own a/b/d text and its sequencing paragraph (§4.1), #166e's checklist (§4.4), #8's four
  clauses (§4.2), `PLAN-FINISH-OPEN-ITEMS.md:249`'s dead #90 reference (§4.3), and — if
  bar 140-D runs — the ATS mechanism across #166b, #167, `CLAUDE.md` and
  `PLAN-FINISH-OPEN-ITEMS.md:255`, all four together
- The three new sub-items **166h/166i/166j** are filed with numbers **the day they are
  named**, not the day someone starts them (#268)
- `planning/LAUNCH_PASS-2026-07-20.md` §P-4 carries the runbook, and no new runbook
  document was created outside `dispatch/` (bar 166-F's find)

**#8 closes when** its entry records its own supersession and points at 166g — **not when
a TestFlight build exists.** No build is created by this lane.

**Explicitly NOT closed by this lane, and each stays where it is filed:** the actual
submission, the P-4 screenshot batch, #127's flip, #255's full de-branding, #45/#74's
CarPlay entitlement, and #109's iPad question.

**And the standing rule that outranks all of it:** *outward-facing issues, PRs and
submissions need Owen's read of the exact text plus his explicit go.* Everything in §6
was written to stop one step short of that line.
