# FABLE T27-255 — De-branding sweep: the inventory (hermes-mobile → talaria-mobile, dylan's remaining marks)

**Repo:** `AethyrionAI/Talaria-27` · **Branch prefix:** `claude/t27-255-*` (or continue on
an existing `t27-255-*` branch if one is opened for this)
**Dispatch date:** 2026-08-09 · **Tracks:** OPEN_ITEMS #255 (references #223, #251, #253)
**Label: FABLE** — this is a wide MECHANICAL rename across ~90 files touching Swift,
Python, PowerShell, HTML and Markdown. A cheap model will happily rename a string that
is load-bearing on a live host (OJAMD's NSSM service, a paired user's Keychain entry) and
report success, because every individual diff looks trivial. **Do not execute this on
Sonnet/Haiku-tier reasoning; the judgment calls here (which hits are FREE vs which orphan
a user's local data) are the entire point of the lane.**

**Goal in one sentence:** produce a complete, evidence-backed inventory of every surviving
upstream (`dylan-buck/Hermes-iOS`) mark and every `hermes-mobile`-family identifier, rule
each one rename/delete/leave by blast radius, and hand the executor a task list where the
free wins are separated from the ones that need Owen's go or a migration.

---

## 0. What #255 already established (2026-08-05) — this dispatch does not re-litigate it

#255 already ran a read-only grep pass and Owen already routed a decision. Restating it so
this dispatch is additive, not contradictory:

- **Zero literal "dylan" in code.** It appears only in our own history docs (`CLAUDE.md`,
  `CLEAN_CHAT_PATH.md`, two dispatch docs) and `THIRD_PARTY_LICENSES.md`'s attribution
  section. **KEEP**, re-confirmed independently below (§1).
- **`hermes-mobile`/`hermes_mobile` lives only in the EOL sidecars** (`relay/`,
  `connector/`, OJAMD's `HermesMobileRelay` NSSM service). **"The rename ask is SATISFIED
  BY #251"** — the successor surface is already `talaria`-named (the `talaria-plugin`
  repo, #251 Phase 1, shipped 2026-08-05), and the old name dies with the sidecars at
  #251 Phase 4 / #223 (relay decommission — **NOT STARTED, per #268's roadmap map, gated
  on #271**). Re-confirmed and quantified below (§1) — this dispatch's job is to prove
  that verdict with real counts, not to reopen it.
- **`skills/hermes-ios/` → `skills/talaria/` is ALREADY DONE** (git mv, `SKILL.md`
  `name:` field, README tree line, connector's refresh block). Re-verified: `skills/`
  contains only `skills/talaria/`, no `skills/hermes-ios/` on disk.
- **Open decisions Owen explicitly deferred, NOT this dispatch's to re-propose:**
  (b) a mechanical `Hermes*` Swift type sweep → `Talaria*` and (c) user-visible
  "Hermes"/"Ask Hermes" string verdicts, both parked pending the #253 pivot conversation
  (itself only a filed "maybe," no design, no lane). **This dispatch does not recommend
  executing (b) or (c).** Where the inventory below surfaces new risk relevant to that
  future decision (the persisted-key namespace, §1.5), it is flagged as a landmine for
  *whenever* (b)/(c) is decided — not as work to do now.

What this dispatch adds beyond the 2026-08-05 pass: **real counts** (the prior pass was
read-only and qualitative), a **PERSISTED-state finding the prior pass did not surface**
(app-local UserDefaults/Keychain key literals, §1.5 — the single highest-risk item in the
whole inventory), and **two stale doc breaks** left behind by the skills/ rename itself
(§3).

---

## 1. The inventory

All counts are `rg -i` occurrence counts (`-o`, piped to `wc -l`) run 2026-08-09 against
the working tree, excluding `.git`, `.claude/worktrees/*` (12 parallel worktrees of this
same repo — counting them would multiply every hit by ~13), `*.venv*`, `*egg-info*`,
`.pytest_cache`, and `OPEN_ITEMS.md` / `OPEN_ITEMS.md.bak` / `OPEN_ITEMS-ARCHIVE.md` (our
own history, already read in full above). Every row is a real, re-runnable `rg` command,
not an estimate.

| # | Pattern searched | Count (occurrences / files) | Representative paths | Blast radius | Ruling | Reason |
|---|---|---|---|---|---|---|
| 1.1 | `hermes[_-]mobile` (case-insensitive; `hermes-mobile`, `hermes_mobile`) | **333 / 68 files** | `relay/` (13 files), `connector/` (20 files), `scripts/*.ps1`/`*.py` (3), `Talaria/Features/Settings/ConnectHermesHostScreen.swift`, `Talaria/Models/RelaySetupCodePayload.swift`, `docs/*.html` (3), `skills/talaria/SKILL.md`, top-level `README.md`/`SECURITY.md`/`MAINTAINER_NOTES.md`/`CONTRIBUTING.md`/`CLAUDE.md`/`CLEAN_CHAT_PATH.md` | **WIRE + SCHEDULED FOR DELETION** (see §1.1 detail) | **LEAVE** until #251 Phase 4 / #223 relay decommission | See detail below — this is the MCP tool namespace + CLI verb name known to a live Hermes agent config on OJAMD; renaming it is update friction against a component already scheduled to die |
| 1.2 | `HermesMobile\w*` (camelCase: `HermesMobileRelay`, `HermesMobileConnector`) | **145 / 39 files** | `relay/app/config.py:55` (`service_name = "hermes-mobile-relay"`), `connector/src/hermes_mobile_connector/service_management.py:16` (`WINDOWS_TASK_NAME = "HermesMobileConnector"`), `scripts/cleanup-stale-users.py`, `scripts/update-hermes.ps1:41` (`Name = 'HermesMobileRelay'`), `connector/tests/*` (58 hits) | **PERSISTED + WIRE + SCHEDULED FOR DELETION** | **LEAVE** — see §1.2 | `HermesMobileRelay` is the literal NSSM service name installed and running on OJAMD right now; `HermesMobileConnector` is the Windows Scheduled Task name. These are live installed identifiers on a production host, not source text |
| 1.3 | `ai.hermes.mobile.connector` (dotted launchd label — not caught by 1.1/1.2's regex) | **7 / 6 files** | `connector/src/hermes_mobile_connector/service_management.py:15` (`MACOS_LABEL`), `scripts/mac/install-gateway-launchd.sh`, `scripts/mac/verify-phase1.sh` | **PERSISTED** | **LEAVE** | Installed macOS LaunchAgent label (`~/Library/LaunchAgents/{label}.plist`); a live install exists under this exact string |
| 1.4 | `hermes_delegate` | **25 / files across `relay/app/talk_mcp.py`, `connector/src/hermes_mobile_connector/client.py`, `connector/tests/`** | `relay/app/talk_mcp.py:28` — `"name": "hermes_delegate"` | **WIRE (external, third-party)** | **LEAVE, hard** | This literal string is embedded in the tool-call config sent to **OpenAI's Realtime API** for voice sessions. It is not our identifier to rename at all — it's a third party's contract, and it also rides the relay's EOL path |
| 1.5 | Persisted `"hermes.*"` UserDefaults/Keychain key string literals (Swift, app-side) | **23 / 6 files, 19 unique key strings** | `Talaria/Services/Support/UserDefaultsAppPersistenceStore.swift` (12 keys: `hermes.userSettings`, `hermes.conversationCache`, `hermes.conversationJournal`, `hermes.backendProfiles`, `hermes.sensorOutboxState`, etc.), `Talaria/Models/BackendProfile.swift:167,179,181` (`hermes.apiServerKey` — the **Keychain-stored chat bearer token**, `hermes.pairedRelayConfiguration`, `hermes.sessionState`), `Shared/ControlHandoff.swift`, `Talaria/Services/SharedWidgetDataStore.swift` + `TalariaWidgets/HermesTimelineProvider.swift` (duplicate `"hermes.widget.data"` definition, App-Group-shared) | **PERSISTED — the highest-risk item in this whole inventory** | **LEAVE, no exceptions** | See §1.5 detail — this is real users' on-disk data (conversation history, paired relay config, the Keychain-held Hermes Sessions API bearer key). Not part of the `hermes-mobile` scope at all — it is the agent-name `Hermes*` bucket already deferred to (b)/(c) — but it is the landmine that decision must clear first, so it is flagged here per the PERSISTED-class instructions even though it is out of THIS lane's execution scope |
| 1.6 | `MessageSender` Codable `rawValue`s `"hermes"` / `"voice_hermes"` | **2 / 1 file** (`Talaria/Models/MessageSender.swift:5,8`) | — | **PERSISTED** | **LEAVE** | Persisted inside every stored `Message` (via `hermes.conversationCache`/`hermes.conversationJournal`, §1.5). Changing the rawValue breaks `Codable` decoding of every existing user's stored chat history on upgrade — a silent data-loss bug, not a cosmetic rename |
| 1.7 | `relay/hermes_mobile.db` (SQLite filename) | 1 file reference in-repo (`relay/.env.example`, `relay/.env.mac.example`); the real file lives outside git on the Mac/OJAMD disk | `relay/app/config.py:14` comment | **PERSISTED + SCHEDULED FOR DELETION** | **LEAVE** | It's the actual relay database file on disk holding real sensor/pairing data. Dies when the relay is decommissioned; renaming it now is a needless migration for a file about to be deleted |
| 1.8 | `dylan` / `buck` / `dylan-buck` (word-boundary) | **14 / 5 files** | `THIRD_PARTY_LICENSES.md:184-186` (`### Dylan Buck — original author`), `CLEAN_CHAT_PATH.md:45,149`, `CLAUDE.md`, `dispatch/FABLE-T27-116-shim-provisioning.md:79`, `dispatch/RESULTS-OJAMD-SERVER-PASS-2026-07-25.md:107` | **LEGAL / HISTORICAL** | **KEEP, all of it** | `THIRD_PARTY_LICENSES.md` is legal surface (fork attribution the MIT license requires); the rest is our own dated history docs describing what actually happened. Re-confirms #255's 2026-08-05 finding with exact counts |
| 1.9 | `Hermes-iOS` (literal upstream repo name) | **7 / 6 files** | `connector/README.md:121` (accurate: `` `talaria` skill (formerly `hermes-ios`) ``), `dispatch/RESULTS-OJAMD-SERVER-PASS-2026-07-25.md:107` (git remote description, historical) — **and 2 STALE**: `relay/docs/DEPLOY_MAC.md:94`, `design/T6_MAC_BACKEND_SPEC.md:75` | **DOCS** | 5× **KEEP** (accurate), 2× **FIX** (broken since the skills/ rename) | See §3 — `DEPLOY_MAC.md` and `T6_MAC_BACKEND_SPEC.md` still instruct `cp -R ../skills/hermes-ios ~/.hermes/skills/`, a path that has not existed since 2026-08-05 |
| 1.10 | Bundle IDs / App Group / entitlements / Xcode schemes | **0 dylan/hermes hits** — `org.aethyrion.talaria27*` bundle IDs, `group.org.aethyrion.talaria` App Group, `Talaria.xcscheme`/`TalariaShare.xcscheme`/`TalariaWidgets.xcscheme` | `project.yml:5,63,85,389,406,431,459,485,502`, all three `*.entitlements` files | **APPLE-BOUND** | **N/A — already clean** | Nothing to do. Worth recording so nobody re-audits it: this surface was already fully de-branded before this lane started |
| 1.11 | `Hermes*` Swift agent-name types (`HermesHostStore`, `HermesClientProtocol`, `HermesLiveActivity`, `HermesWidgetBundle`, `AskHermesIntent`, …) | **~30+ files** | `Talaria/Stores/HermesHostStore.swift`, `Talaria/Services/Protocols/HermesClientProtocol.swift`, `TalariaWidgets/HermesLiveActivity.swift`, etc. | **AGENT NAME, not upstream mark** | **OUT OF SCOPE — do not touch** | Names Owen's own agent (Hermes), not Dylan Buck. #255 already routed this to wait for the #253 pivot conversation. Listed here only so the executor doesn't accidentally sweep it in while doing 1.1/1.2 |
| 1.12 | `hermes-mobile-plans/` (`.gitignore:57`) | 1 / 1 file | `.gitignore:57` | **FREE** | **RENAME** (optional, trivial) | Gitignore pattern for an untracked personal-paths planning dir; zero coupling to any running system |
| 1.13 | `"hermes.camera.capture"` DispatchQueue label | 1 / 1 file (`Talaria/Features/Talk/LiveCameraOverlay.swift:202`) | — | **FREE** | **RENAME** (optional) | Diagnostic-only queue label, visible in Instruments/crash traces, never persisted or read back |
| 1.14 | `/tmp/hermesmobile-uitest-config.json` (UITest scaffolding path) | 2 / 1 file (`TalariaUITests/AppTemplateUITests.swift:12,21`) | — | **FREE** | **RENAME** (optional) | Ephemeral `/tmp` fixture path used only by the UI test harness itself; not app state, not read by anything else |
| 1.15 | `"hermes_conversation_"` export filename prefix (`TalariaTests/ConversationExportTests.swift:73`) | 1 / 1 file | — | **FREE-ish but user-visible** | **Note for (c), don't act now** | Not stored/decoded — regenerated fresh on every export — so technically FREE, but it's a string the USER sees in Files/Share sheet. Folds into the deferred (c) bucket rather than being a standalone rename |
| 1.16 | `relay/fly.toml`, `relay/docs/fly-io.md`, `APNS_BUNDLE_ID=io.hermesmobile.HermesMobile` (`relay/.env.example:37`) | ~15 hits across 3 files | `relay/fly.toml:2` (`app = "hermes-mobile-relay"`) | **DEAD / UNUSED** | **DELETE, don't rename** | No evidence Fly.io is actually deployed anywhere (production is OJAMD + Mac Mini per CLAUDE.md); the APNS config is doubly dead since #238 removed the entire notification surface. Cheapest fix is deleting these files when the relay is decommissioned (#223), not renaming a deploy target nobody uses |
| 1.17 | Git history (author `Dylan Buck` / `dylan-buck`) | 2 distinct author identities across the log | `git log --format='%an <%ae>'` | **LEGAL / IMMUTABLE** | **NEVER TOUCH** | See §2 |

### §1.1 detail — why `hermes-mobile`/`hermes_mobile` is WIRE, not text

`connector/src/hermes_mobile_connector/mcp_registration.py:16` sets
`MCP_SERVER_NAME = "hermes_mobile"`. That name is what the Hermes agent's
`config.yaml` `tools.include` list references, what `skills/talaria/SKILL.md`
documents as the tool-call prefix (`mcp__hermes_mobile__get_health_summary`, etc. —
23 occurrences in that one file), and what `connector/pyproject.toml`'s
`[project.scripts]` installs as the literal `hermes-mobile` / `hermes-mobile-mcp`
console commands. **App-side UI text quotes this literal CLI verb back to the user**:
`Talaria/Features/Settings/ConnectHermesHostScreen.swift:110-112` tells the user to run
`hermes-mobile setup`, `hermes-mobile pair-phone`, `hermes-mobile service install`;
`Talaria/Models/RelaySetupCodePayload.swift:9` does the same in an error message. If
those three call sites are renamed to say "talaria-mobile" while the connector's actual
installed command stays `hermes-mobile` (or vice versa), **the app tells the user to run
a command that does not exist** — this is not cosmetic drift, it is broken setup
instructions. A correct rename therefore requires touching, in the same change: the
connector's `pyproject.toml` console-script names, `mcp_registration.py`'s
`MCP_SERVER_NAME`, `state.py`'s `mcp_server_name` default, the skill file, the three
Swift UI strings, `docs/setup.html`/`docs/screens.html`/`docs/index.html`, and every
piece of prose in `README.md`/`SECURITY.md`/`MAINTAINER_NOTES.md`/`CONTRIBUTING.md` that
quotes the verb — **and** every host that already has the connector installed (OJAMD,
the Mac Mini) needs its `config.yaml` `tools.include: hermes_mobile` updated to match, or
the agent stops seeing the sensor tools entirely. That is a coordinated, multi-host,
config-touching change to a component #251's own phase arc already schedules for full
deletion. It is not textually "hardening" (no new validation, no new robustness), but it
produces exactly the outcome the standing ⛔ rule warns about — a new hoop between the
live install and the next `hermes update`/connector refresh — for a component whose
stated direction is deletion, not maintenance. **Ruling stands: leave it, let #251 Phase 4
delete it.**

### §1.2 detail — the two live system-service identifiers

`scripts/update-hermes.ps1:41` and `scripts/cleanup-stale-users.py:18-20,351` both
hardcode `HermesMobileRelay` as the literal argument to `nssm start/stop` /
`Restart-Service` against the box that is running RIGHT NOW on OJAMD (confirmed live per
CLAUDE.md's OJAMD services section). `connector/src/hermes_mobile_connector/
service_management.py:16` hardcodes `WINDOWS_TASK_NAME = "HermesMobileConnector"` (a
Windows Scheduled Task name) and `:15` hardcodes `MACOS_LABEL = "ai.hermes.mobile.
connector"` (a macOS LaunchAgent label, written to `~/Library/LaunchAgents/{label}.plist`
on install). Renaming any of these requires **stopping and re-registering a live service
on a production host Owen is not currently reviewing** — squarely the
"🔐 LIVE-INSTALL EXPERIMENTS NEED AN EXPLICIT PER-EXPERIMENT GO" rule, and squarely the
kind of thing the "DO NOT HARDEN THE RELAY OR CONNECTOR" rule's spirit is warning against,
even though a rename isn't literally "hardening." **Ruling stands: leave until #223's
relay decommission, at which point the service is stopped and deleted, not renamed.**

### §1.5 detail — the persisted-key landmine (new finding, not in the 2026-08-05 pass)

`Talaria/Services/Support/UserDefaultsAppPersistenceStore.swift:6-20` defines the literal
UserDefaults key namespace for **every piece of durable app state**: `hermes.userSettings`,
`hermes.inboxState`, `hermes.backendProfiles`, `hermes.sessionProfileIndex`,
`hermes.sessionUsageIndex`, `hermes.sensorOutboxState`, `hermes.conversationCache`,
`hermes.conversationJournal`, `hermes.conversationListState`, `hermes.composeOutboxState`,
`hermes.agentAttachmentSidecar`, `hermes.healthAnchorPrefix`. `Talaria/Models/
BackendProfile.swift:167,179,181` derives three more from the same prefix for
**Keychain**-backed secrets: `hermes.apiServerKey` (the bearer token chat auth runs on),
`hermes.pairedRelayConfiguration`, `hermes.sessionState` — and that file's own doc comment
(lines 152-157) already states the design intent explicitly: *"no Keychain entry moves, no
persisted state is rewritten"* is what makes an earlier migration (the per-profile scoping)
byte-identical for existing installs. **That is the exact property a blind rename of these
keys would violate**: every existing installed user would silently lose their conversation
history, paired relay config, and stored Hermes API key on the first launch after the
rename, because `UserDefaults`/`Keychain` lookups are exact-string, and there is no
migration path reading the old key. `Shared/ControlHandoff.swift` and `TalariaWidgets/
HermesTimelineProvider.swift` (duplicating `Talaria/Services/SharedWidgetDataStore.swift`'s
`"hermes.widget.data"` key definition — the same twin-copy risk pattern CLAUDE.md's design
system section already flags for `HermesWidgetData.swift`) add App-Group-shared instances
of the same problem: main app and widget extension must agree on the literal string.
**This bucket is NOT part of the `hermes-mobile` rename scope** — these keys name the
*agent* ("Hermes"), not Dylan Buck, so they fall under the already-deferred (b)/(c)
decision, not this lane. It is documented here because the task's own PERSISTED-class
definition calls out exactly "a Keychain key... a UserDefaults key" and because whoever
eventually executes (b)/(c) needs this list, not a rediscovery of it.

---

## 2. What must NOT be renamed

Stated plainly so nobody re-proposes any of these:

1. **Git history and commit authorship** (`Dylan Buck <dylan.buck@icloud.com>`,
   `dylan-buck <dylan.buck@icloud.com>`, first commit `c4e5b36`). Rewriting history to
   scrub an author breaks the fork's provenance chain, is almost certainly a license
   violation (MIT requires the original copyright notice to survive, and rewriting
   commit metadata is a bad-faith way to obscure who wrote what), and buys nothing —
   `git log` is not user-facing.
2. **`LICENSE`** (MIT, `Copyright (c) 2026 Hermes iOS Contributors`) and
   **`THIRD_PARTY_LICENSES.md`**'s `### Dylan Buck — original author` section. This is
   the legal surface the fork's license requires. #255 already ruled this KEEP; adding an
   AethyrionAI copyright line alongside is fine, deleting the original is not.
3. **`hermes_delegate`** (§1.4) — a third party's (OpenAI Realtime API) literal tool-call
   name, not our identifier at all.
4. **`"object":"hermes.run"`** and other literal JSON field values pinned in
   `TalariaTests/RunsPlaneTransportTests.swift` (12 occurrences, e.g. line 207, 656, 694,
   735, 772...) — this is the **Hermes gateway's own wire format** for the `/v1/runs`
   API (CLAUDE.md's verified route table). It is not a string we emit; it is what the
   server sends back. Renaming it would desynchronize the test fixtures from the actual
   server response shape they're pinning.
5. **The `hermes-mobile`/`HermesMobile*`/`hermes_delegate`/`ai.hermes.mobile.connector`
   family while it is still installed and running** (§1.1-§1.4, §1.7) — not a permanent
   "never," but a "not yet, and not as a standalone rename": it rides #251 Phase 4 /
   #223's relay decommission, which is **NOT STARTED** and gated on #271 per #268's
   roadmap map. Renaming now duplicates work that deletion will make moot, and touches a
   live OJAMD service without the per-experiment go the standing rule requires.
6. **The persisted `hermes.*` UserDefaults/Keychain key namespace** (§1.5) — not part of
   this lane's scope at all (it's agent-name, not upstream-mark), and if it's ever
   touched under the deferred (b)/(c) decision, it needs a migration, never a rename.
7. **`Hermes*` Swift types and user-visible "Ask Hermes" strings** (§1.11) — already
   routed to wait for the #253 pivot conversation. Re-proposing this here would
   contradict Owen's own 2026-08-05 routing.
8. **Bundle IDs, the App Group (`group.org.aethyrion.talaria`), entitlements** — already
   clean (§1.10, no dylan/hermes marks present); changing them now would be a shipping
   event for zero reason.

---

## 3. ⚠️ Tracker corrections

- **#255's own text is not wrong**, but it is now slightly **stale in one place**: it
  says the `skills/hermes-ios/` → `skills/talaria/` rename left "Docs-only, no build
  surface" and implies the docs were fully updated. Two docs were missed and are
  currently **broken instructions**, not just untidy:
  - `relay/docs/DEPLOY_MAC.md:94` — `cp -R ../skills/hermes-ios ~/.hermes/skills/` —
    `../skills/hermes-ios` has not existed since 2026-08-05.
  - `design/T6_MAC_BACKEND_SPEC.md:75` — `... copy the `hermes-ios` skill into
    `~/.hermes/skills/`` — same broken path.

  Neither is a de-branding task per se — they're a regression the (a) rename left behind
  and should be fixed as part of this lane's docs-only pass (§5, Task 1) rather than
  re-opening #255's routed decision.
- **No other correction found.** #255's 2026-08-05 inventory's substantive claims (zero
  dylan in code, hermes-mobile confined to the EOL sidecars, the rename ask satisfied by
  #251) all independently re-verify against the counts in §1.

---

## 4. Proposed bars

Lettered, falsifiable, for whichever entry (#255 itself, or a fresh lane number if Owen
wants this split out) ends up carrying the executed work. Bars pre-register before the
run per CLAUDE.md's "Where the BARS live."

- **255-A (the free renames land clean):** after Task 1-3 (§5) — the `.gitignore` line,
  the DispatchQueue label, the `/tmp/` UITest fixture path, and the two stale
  `hermes-ios` doc fixes — `rg -i 'hermes[_-]mobile|hermes-ios'` against the touched
  files returns **zero** hits in the renamed/fixed locations, and `git diff --stat`
  shows **no file outside the five touched paths changed**. (Proves the free pass didn't
  quietly drift into the EOL sidecars or the persisted-key namespace.)
- **255-B (no persisted user state was orphaned):** on a build carrying Task 1-3, install
  fresh over a prior build that has real conversation history, a paired relay
  configuration, and a stored Hermes API key (Keychain). After launch: conversation
  history is present, the relay pairing is present, chat still authenticates — i.e.
  `UserDefaultsAppPersistenceStore` and `BackendProfileScopedKeys` round-trip byte-for-
  byte. Falsifiable by a single missing conversation or a re-triggered pairing flow.
  **This bar is expected to be trivially MET because Task 1-3 never touches §1.5's keys —
  its purpose is to prove that in writing, not to test something that was ever at risk.**
- **255-C (the wire still speaks — the sidecars weren't accidentally touched):** on OJAMD,
  after Task 1-3 lands and any redeploy happens, `hermes-mobile pair-phone` still works
  verbatim (prints a QR + 8-char code), the agent still lists the `hermes_mobile` MCP
  tools (`hermes mcp test hermes_mobile` per `design/T6_MAC_BACKEND_SPEC.md:75`-adjacent
  tooling), and `Get-Service`/`nssm status HermesMobileRelay` (or the OJAMD equivalent)
  still reports the service running under its current name. Falsifiable by any of: the
  connector's console-script commands failing, the MCP tool prefix changing, or the NSSM
  service name changing.
- **255-D (gate, incl. Release):** `scripts/mac/lane-gate.sh` reports the literal
  `GATE: PASS` marker (Debug suite + XCUITest + Release build, per #218's positive-marker
  discipline). Background it, poll the log — do not block a tool call on it, do not arm a
  Monitor.

---

## 5. Task breakdown

Ordered so the FREE renames land first (small, separately reviewable, zero coordination
needed with any host) and the risky/deferred work stays visibly separate.

1. **Docs-only fix (not a rename): repair the two stale `hermes-ios` paths.**
   `relay/docs/DEPLOY_MAC.md:94` and `design/T6_MAC_BACKEND_SPEC.md:75` →
   `../skills/talaria` / `talaria` skill. Zero build surface, zero risk. Bar 255-A covers
   this.
2. **Free rename — `.gitignore:57`:** `hermes-mobile-plans/` → `talaria-mobile-plans/`
   (or drop the entry if nothing currently uses that convention — check first with
   `find . -maxdepth 1 -iname "*mobile-plans*"`). Trivial, no coupling.
3. **Free rename — `Talaria/Features/Talk/LiveCameraOverlay.swift:202`:**
   `DispatchQueue(label: "hermes.camera.capture", ...)` →
   `DispatchQueue(label: "talaria.camera.capture", ...)`. Diagnostic-only label, no
   persistence, no cross-target contract. Swift edit — no file added/removed, so
   **`xcodegen generate` is NOT required** for this one (existing file, just an edit).
4. **Free rename — `TalariaUITests/AppTemplateUITests.swift:12,21`:**
   `/tmp/hermesmobile-uitest-config.json` → `/tmp/talariamobile-uitest-config.json`.
   Test-harness-only, ephemeral. Same file, no xcodegen needed. Re-run the UITest suite
   after (it's exercised directly by the suite this file belongs to) to confirm nothing
   external references the old `/tmp` path (grep `scripts/`, CI config — none found in
   this pass, but confirm before landing).
5. **Stop here and gate.** Run `scripts/mac/lane-gate.sh` (background it, poll the log
   per CLAUDE.md's build/tooling section) before touching anything below — Tasks 1-4 are
   the entire FREE bucket and should ship as one small, reviewable PR on their own.
   **Bar 255-A + 255-D.**
6. **Separately reviewable, NOT executed by this lane — present as options, let Owen
   route:**
   - **Option A — delete the dead Fly.io leftovers** (`relay/fly.toml`,
     `relay/docs/fly-io.md`, the `APNS_BUNDLE_ID=io.hermesmobile.HermesMobile` line in
     `relay/.env.example`). Zero evidence of use; cheapest to delete outright rather than
     rename, but it's a deletion inside the relay — confirm with Owen it's really dead
     before removing (a one-line question, not a live-install experiment, since these
     files aren't installed anywhere — they're only ever read by a human running the Fly
     deploy path by hand).
   - **Option B — do nothing further until #223/#251 Phase 4.** The hermes-mobile family
     (§1.1-§1.4, §1.7), the persisted-key namespace (§1.5), and the `Hermes*` Swift
     sweep (§1.11) all stay exactly as they are. This is the default if Owen doesn't
     actively route otherwise, consistent with #255's own 2026-08-05 conclusion.
   - **Neither option touches anything requiring a live-host go, a migration, or the
     #253 pivot decision.** If Owen wants (b)/(c) (the Hermes* Swift sweep / user-visible
     string verdicts) actually executed, that is a **new, separate lane** with its own
     bars — this dispatch's inventory (§1.5, §1.11) is the input to that lane's design,
     not a green light to build it now.

---

## 6. Traps

- **The relay-hardening rule bites here even though a rename "looks like" just a
  find-replace.** §1.1/§1.2's detail sections spell out why: touching `hermes-mobile`/
  `HermesMobileRelay`/`HermesMobileConnector` means touching a live NSSM service, a live
  Windows Scheduled Task, a live macOS LaunchAgent label, and a live agent `config.yaml`
  on OJAMD simultaneously with the source change — that is new update friction on a
  component with a planned end-of-life, which is exactly what the standing rule forbids
  in spirit even where it isn't textually "hardening." Do not let "it's just a rename"
  talk anyone past this.
- **Persisted state (§1.5) is the trap most likely to actually cause harm** if this lane
  scope-creeps. A `find hermes -exec ... talaria` mechanical sweep across `Talaria/`
  would absolutely catch `UserDefaultsAppPersistenceStore.swift` and
  `BackendProfileScopedKeys` — and that would silently delete every existing user's
  conversation history and force everyone to re-pair on next launch, with no error, no
  crash, and no test catching it unless bar 255-B is specifically run against a build
  carrying real prior state (a fresh simulator/fresh install proves nothing here — it
  has no old keys to lose).
- **#223's deletion path makes half this inventory moot by design, not by neglect.**
  Anything marked SCHEDULED FOR DELETION is deliberately left alone; #223 is
  **NOT STARTED** (per #268's roadmap map, gated on #271, which is itself NOT STARTED) —
  so "moot" does not mean "done," it means "don't spend effort here, the deletion vehicle
  already exists and is scoped."
- **Git history / attribution (§2.1) is a one-way door.** There is no undo for a
  history rewrite that ends up on a shared remote (`origin` = `AethyrionAI/Talaria-27`,
  `upstream` = `ChronoRixun/Talaria`) — don't even prototype it locally in a way that
  could get force-pushed by habit.
- **`xcodegen generate` is mandatory for any task that adds/removes/renames a Swift
  file** (none of Tasks 1-4 do — they're in-place string edits). If a future (b)/(c) lane
  ever renames `Hermes*.swift` files, this becomes load-bearing; note it here so it isn't
  rediscovered.
- **A green Debug suite proves nothing about this specific lane.** Even Tasks 1-4 are
  pure string literals with no compiled-code behavior change, so the risk isn't "does it
  build" — it's "did the rename stay inside its declared blast radius." The check that
  matters is the `git diff --stat` file-list check in bar 255-A, not the test suite. If
  this lane ever grows to touch §1.5 or §1.11, the **Release build** becomes load-bearing
  too (#218's lesson: a `#if DEBUG`-only mistake is invisible to Debug-only checks) —
  irrelevant to Tasks 1-4 specifically, but state it now so nobody assumes a green Debug
  suite ever clears a wider rename.

---

## 7. What is OWEN'S to decide

- **Option A vs B in §5 Task 6** — delete the dead Fly.io/APNS leftovers now, or leave
  them for the relay's full decommission. Low-stakes either way; asking because it's a
  deletion, not because it's risky.
- **Whether the #253 pivot conversation ever happens, and if so what it decides for (b)
  the `Hermes*` Swift type sweep and (c) user-visible "Hermes"/"Ask Hermes" string
  verdicts** (§1.5, §1.11). This dispatch documents the landmine (§1.5) and the scope
  (§1.11); it does not decide the product question, which #255 already routed to Owen.
- **Anything APPLE-BOUND** (§1.10) — already clean, nothing to decide, listed only for
  completeness per this dispatch's required sections.
- **Any PERSISTED item** (§1.5, §1.6, §1.7) — by definition never a blind rename; if any
  of these are ever touched, Owen decides whether a migration is worth building versus
  leaving the naming as legacy-but-functional debt.
- **When #223/#251 Phase 4 (relay decommission) actually runs** — not this dispatch's
  call; it's gated on #271 (OJAMD plugin rollout, NOT STARTED) per #268's roadmap map.

---

## 8. Close-out

- **Gate:** `scripts/mac/lane-gate.sh` on the branch carrying Tasks 1-4, backgrounded,
  polled via an `until` loop against the log file — never a Monitor, never a blocking
  foreground call given the multi-minute runtime. Literal `GATE: PASS` required (Debug
  suite + XCUITest + Release build).
- **The PR:** one small PR covering only Tasks 1-4 (the FREE bucket) — title should make
  clear it is the free slice of #255, not the whole de-branding ask, so review scope
  matches risk. Do not bundle Task 6's options into the same PR; they need their own
  Owen sign-off first.
- **What this falsifies upstream:** §3 above — #255's implication that the 2026-08-05
  skills rename was "docs-only, no build surface, [fully] updated" needs a one-line
  amendment noting the two stale paths this dispatch found and Task 1 fixes. That
  correction belongs in #255's own entry (per CLAUDE.md's close-out rule — corrections go
  upstream to the stale claim's home), filed by whoever executes Task 1, not by this
  dispatch (which does not edit OPEN_ITEMS.md).
- **What stays true after this lands:** the hermes-mobile family, the persisted `hermes.*`
  key namespace, and the `Hermes*` Swift agent-name surface are all **unchanged** — this
  lane's entire executed scope is five small, low-risk files. That is the correct
  outcome: the loud-sounding ask ("rename hermes-mobile to talaria-mobile") turns out to
  be already-satisfied-by-#251 plus a handful of truly free cleanups, and the inventory's
  real value is in clearly marking the much larger surface that must NOT move yet.
