# OPEN\_ITEMS.md — Accuracy Audit

**Date:** 2026-07-13  ·  **Auditor:** Claude Code (multi-agent workflow)  ·  **Baseline:** `origin/main` @ `cca1345`

Deliverable 1 of 2. Deliverable 2 is the corrected `OPEN_ITEMS.md` itself (every finding below is now
stamped inline in that file as a `> **Audit 2026-07-13:**` blockquote, matching the file's existing
retroactive-correction convention).

---

## Executive summary

All **112** open items were re-checked against three sources of ground truth: the merged/closed state of
every GitHub PR and issue, the actual code on `main` (the working tree is byte-identical to `origin/main`),
and each item's own latest dated note. Result:

| Verdict | Count | Meaning |
|---|---:|---|
| ✅ Accurate as-was | 65 | header status matches reality — no change |
| 🔴 Shown ✅ closed, **actually open** | 3 | over-reported (#17, #18, #31) |
| 🟢 Shown open, **actually done** | 7 | under-reported (#37, #47, #48, #49, #55, #76, #94) |
| 🟠 Header contradicts item's own latest note | 3 | header-stale (#25, #79, #102) |
| 🟡 Status OK but wording stale | 34 | "built in cloud / not compiled / needs merge" — PR since merged |
| **Total** | **112** | |

**The dominant pattern:** the tracker systematically *under-reports* progress. 34 items still carry
"BUILT IN CLOUD, not compiled" / "needs Mac merge" / "needs xcodegen" language even though their PRs have
since merged and the code is on `main` — merging *requires* a successful `xcodegen`+build+test pass, so that
wording is provably stale. Seven items are further along still: their work is not just merged but done, yet
they were never flipped. Only **3 items over-claim** completion, and all three are narrow (a regression that
undid a same-day fix, and two "merged but never device-verified" cases).

> **Why so few ✅→open flips?** This project deliberately treats *merged-to-main* and *device-verified* as
> separate milestones, and keeps merged-but-unverified feature work at 🔧 on purpose. The audit respected
> that rule — a merged PR alone was **not** treated as "done." That's also why 34 items stay 🔧 (only their
> prose is corrected) rather than being upgraded to ✅.

---

## Methodology

- **Fan-out:** a deterministic workflow split the 112 items into 19 contiguous batches; one **Sonnet 5**
  agent audited each batch against a shared evidence kit (PR index, issue index, full `main` commit log,
  merged-branch list) plus live repo inspection.
- **Adversarial verify:** every status-*flip* finding was handed to a second, independent **Sonnet 5**
  verifier instructed to *refute* it from scratch. This mattered — see §E.
- **Evidence hierarchy:** GitHub PR `merged_at` (authoritative for "landed") → GitHub issue state → file/
  symbol presence on `main` → commit presence. `git branch --merged` was explicitly **not** trusted: most
  early PRs were squash-merged, so ancestry shows false negatives (a trap two verifiers independently hit
  and correctly worked around).
- **36 agents, 0 errors, ~3.2M tokens, 1022 tool calls.**

---

## A. Shown ✅ closed — actually still OPEN (3)

### #17 — Relay sensor delivery resolved end-to-end, confirmed on device
**Was:** `✅`  →  **Corrected to:** ✅ Relay sensor delivery — 07-02 fix did NOT hold: connector was dead 2026-07-02→07-11 (9-day prod outage; see #87/#103 p

**Evidence.** Header claims 'RESOLVED end-to-end (crash + identity + RPC pump), confirmed on device' as of the
2026-07-02 reconciliation. This is directly contradicted by two later, more authoritative OPEN_ITEMS entries: #87
(OPEN_ITEMS.md line 2770, 'RESOLVED (ACTUALLY deployed 2026-07-11; the 07-09 claim below did not hold)') states 'the
connector had been dead since 07-02 (killed by this very defect; see #103 post-mortem)' — the identical
cp1252/UnicodeDecodeError defect item 17 claims to have fixed and confirmed that very day — and #87 directly refutes
item 17's fix mechanism ('PYTHONUTF8 does not reach the connector process' vs. item 17's own text '...+
PYTHONUTF8=1'). #103 (OPEN_ITEMS.md line 3136,…

### #18 — Session shelf scrim opacity increased, toolbar hit-testing blocked
**Was:** `✅`  →  **Corrected to:** 🔧 Session shelf — scrim opacity increased, toolbar hit-testing blocked (merged 2026-06-25; device verification not recor

**Evidence.** Code confirmed present on main: `.allowsHitTesting(!sessionsOpen)` grep-confirmed in
Talaria/Features/Chat/ChatScreen.swift; Design.Colors.scrim now resolves via ThemeRuntime (Design.swift:100),
consistent with the opacity fix surviving the later theming refactor (#49). However, unlike all four sibling items
from the same 2026-06-25 batch (#16, #17, #19, #20 — each carries an explicit 'Verified on-device'/'confirmed on
device' line), item 18's body (OPEN_ITEMS.md lines 448-461) contains only '**Fixed 2026-06-25:**' with no
verification/confirmation statement at all. Per the audit rubric a feature item is truly done (✅) only with an
explicit device-verified note; this item lacks one.…

### #31 — Paste image into composer — unblocked by #43, reconciled onto main
**Was:** `✅`  →  **Corrected to:** 🔧 Paste image into the chat composer — #43 send-side fix merged to main; full paste-then-send flow not yet re-verified o

**Evidence.** Code confirms the merge: Talaria/Features/Chat/ChatInputBar.swift:174-186/516-518 has an uncommented,
wired paste button ('// Paste image from clipboard (#31)', pasteImageFromClipboard() reading
UIPasteboard.general.image and calling onPasteImage), and Talaria/Services/Support/AttachmentInlining.swift:87 handles
the .image case inside assemble(), consumed by Talaria/Services/Live/SessionsHermesClient.swift's ChatTurnBody.make()
(line 975), whose surrounding comment (958-962) explicitly cites '(#43 — the endpoint rejects real file/document parts
with unsupported_content_type, and they used to be silently dropped here)' as now-fixed — so the send-side fix
genuinely exists on main. BUT the…

---

## B. Shown open — actually DONE (7)

### #37 — Connector win32/encoding fix applied on OJAMD; upstream commit still pending
**Was:** `🔧`  →  **Corrected to:** ✅ Connector win32/encoding fix — RESOLVED (win32 `tasklist` branch landed on main via PR #38, merged 2026-07-06; encoding fix — 17

**Evidence.** Working tree (== origin/main tip) already contains the exact fix this item describes as un-upstreamed.
connector/src/hermes_mobile_connector/mcp_registration.py lines 251-276: _hermes_chat_running() has 'if sys.platform
== "win32":' branching to subprocess.run(['tasklist','/FO','CSV','/NH'], ...) — verbatim match to the item's own
description ('the OJAMD edit adds a sys.platform == "win32" branch using tasklist /FO CSV /NH'). Traced the landing
commit: `git show b1a00a7^1:<path>` (main immediately before the merge) has NO win32/tasklist code; `git show
b1a00a7^2:<path>` (incoming branch) HAS it. b1a00a7 = 'Merge pull request #38 from…

### #47 — Owen must configure OpenAI Realtime key to enable voice
**Was:** `🎯`  →  **Corrected to:** ⏸️ Configure OpenAI Realtime talk on the Hermes host — key/config deployed + confirmed minting on OJAMD 2026-07-08, then PARKED be

**Evidence.** The connector fix this item describes (branch claude/issue-7-hermes-config-08bsbm) is confirmed merged
into current history: `git log` shows commit 8ca7741 "Merge pull request #71 from ChronoRixun/claude/issue-7-hermes-
config-08bsbm"; `realtime_talk` handling is live in connector/src/hermes_mobile_connector/{client.py,state.py}. Item
#82 (OPEN_ITEMS.md line 2560-2562, OJAMD relay logs 2026-07-08) shows `talk/readiness` 200s → `POST /v1/talk/session`
200, "**realtime session minted**" with `last_error: None` — i.e. the specific configure-the-key ask here was achieved
and working server-side by 07-08. Voice then failed end-to-end for an…

### #48 — Repo lineage cleanup, xcodegen entitlements trap, minor logging polish
**Was:** `🔧`  →  **Corrected to:** ✅ Repo hygiene — lineage divergence cleanup + xcodegen entitlements trap — RESOLVED (`BRANCHING.md` shipped; log-noise line kept a

**Evidence.** All three named threads resolved: (1) lineage divergence — item's own text says "Resolved 07-02... Build
verified on device"; (2) xcodegen trap — item's own 2026-07-03 update says "Trap closed for dev builds", confirmed
live at project.yml:45 (`aps-environment: development`); (3) the "Prevention (TODO)" ask for a BRANCHING.md doc —
`/home/user/Talaria-27/BRANCHING.md` now exists at repo root and its opening line verbatim describes "the 2026-07-02
lineage-divergence incident, where local `main` and `origin/main` silently forked and evolved *parallel, different*
implementations of the same open items (#35/#41/#24a)" — an exact match to this…

### #49 — Four-theme system + palette de-dup; Mac build/device-verify still owed
**Was:** `🔧`  →  **Corrected to:** ✅ Theme system — four themes + palette-core de-dup SHIPPED, compiled, and device-verified (4 flagships live on-device 2026-07-10 p

**Evidence.** Shared/ThemePaletteCore.swift and TalariaTests/DesignThemeTests.swift both exist with live, specific
assertions (e.g. DesignThemeTests.swift:48 `#expect(ThemeID.terminal.lockedAccentSlot == .cyan)`), confirming the
palette-core de-dup this item describes actually shipped. Stronger transitive evidence: item #91 (OPEN_ITEMS.md line
2857-2861) records "Gate: CLEARED 2026-07-11 — 'Now THAT is an outrageous theme' (device verdict, PR #66 merged)" for
Lane E — work built entirely on top of the ThemeRuntime/palette-catalog infrastructure this item shipped. A device
verdict on Lane E is only possible if the underlying theme system (this item) was…

### #55 — OJAMD reverted to out-of-the-box startup scripts; checklist open
**Was:** `🔧`  →  **Corrected to:** 💤 OJAMD service layer reverted to out-of-the-box (2026-07-04) — relay portion SUPERSEDED by NSSM reinstatement (#88, #98, #105); g

**Evidence.** The specific architecture this item documents (NSSM services deleted, relay disabled, Startup-folder-
script login launch) was reversed shortly after. Item #88 (OPEN_ITEMS.md line 2802-2810, RESOLVED 2026-07-09) states:
"the relay is NSSM-managed again (`HermesMobileRelay`, verified 2026-07-09: nssm.exe → uvicorn...)" — directly
contradicting item 55's "services deleted"/"relay set to Disabled" framing. Item #105 (line 3152-3165, Fixed
2026-07-12) explicitly says "the relay is NSSM-owned now... This is #55's competing-launch-layers problem in mirror
image" and retires a stray Startup .cmd precisely because NSSM now owns the relay again.…

### #76 — Orphan-surface audit script + report, cloud-built and self-tested
**Was:** `🔧`  →  **Corrected to:** ✅ Orphan-surface audit — hygiene tooling (GitHub #49)

**Evidence.** PR_INDEX #50 (claude/t27-49-orphan-audit→main) Merged=YES; ISSUE_INDEX #49 CLOSED. tools/orphan-audit.sh
(executable, 16235 bytes) contains `--self-test` flag and `SELF_TEST_ORACLE`; tools/orphan-audit-report.md (27059
bytes) states 'Generated by tools/orphan-audit.sh at commit 6e604e9', matching the item's claim. BRANCHING.md lines
66-68 contain the committed checklist line ('run tools/orphan-audit.sh ... review the committed tools/orphan-audit-
report.md'). The item's own latest note explicitly says 'fully verified as shipped: tools/orphan-audit.sh --self-test
ran clean' and 'No app code touched, no xcodegen' — a pure bash/python tooling…

### #94 — pair() clears old record before redeem succeeds, credential-loss risk
**Was:** `🔧`  →  **Corrected to:** ✅ Pairing hardening — pair() already redeems before clearing the old record (no ordering bug found)

**Evidence.** Talaria/Stores/PairingStore.swift lines 84-99 (read directly): `pairingService.redeemPairingCode` (async
throws, per PairingServiceProtocol.swift:6-9) executes at lines 84-87 BEFORE
`sessionStore.clearSession()`/`persistence.clearPairedRelayConfiguration()` at lines 95-96 — a throw jumps straight to
the catch block at line 107 and never reaches the clear/save code. This is exactly the 'redeem FIRST, then clear+save'
fix shape the item proposes as still-needed. Only call site of pair(using:) is ConnectHermesScreen.swift:338
(grepped), so no alternate buggy path exists. git blame on lines 84-99 shows this ordering already present at the…

---

## C. Header contradicts the item's own latest note (3)

### #25 — CTX meter: 0% fixed, denominator reads ~1.4x high
**Was:** `🔧`  →  **Corrected to:** 🐛 CTX meter — device verify FAILED 2026-07-05: shows 0 on some sessions, absent on older ones, flashes wrong; root cause unpinned

**Evidence.** Item's own latest dated note (2026-07-05, positioned first in the item, i.e. most recent) reads 'Device
verification 2026-07-05: FAILED' with a broader/different symptom set than the header claims: 'CTX shows 0 on some
sessions, absent entirely on older sessions, and occasionally flashes in before reading wrong,' with next steps
(ground-truth against Hermes's built-in context check, capture a live session with Verbose Logging + run.completed
payloads) still pending/not started. This supersedes the header's '0% fixed; denominator ~1.4x high' framing, which
only describes the intermediate…

### #79 — Turn Receipts — per-turn tokens, cost, and time (GitHub #46)
**Was:** `🔧`  →  **Corrected to:** ✅ Turn Receipts — per-turn tokens, cost, and time (GitHub #46)

**Evidence.** PR #53 (`claude/t27-46-turn-receipts`→main) Merged=YES per PR_INDEX.md, title '#46: Turn Receipts — per-
turn tokens, cost, and time'; GitHub issue #46 CLOSED and follow-up issue #57 ('Turn receipt (#46) overflows portrait
width...') also CLOSED per ISSUE_INDEX.md. Code confirmed present on main: Talaria/Services/Support/TurnReceipts.swift
(ModelPricingCatalog at line 26-27, used in ModelsSettingsScreen.swift:62,80, ChatScreen.swift:741,746,
MessageBubble.swift:309, AppContainer.swift:1290) + TalariaTests/TurnReceiptsTests.swift;
Talaria/Models/Message.swift:77,80,83…

### #102 — Local brain phrase-loop + thermal issue, still investigating root cause
**Was:** `🔍`  →  **Corrected to:** 🔧 Local brain generation health — MERGED (Lane H, PR #83), organic-trigger device-verify owed

**Evidence.** The item's own latest note ('MERGED 2026-07-13 (Lane H, PR #83) — 570/570 green (49 suites)... Device
pass 2026-07-12 (partial)... STILL OWED (organic)...') already declares a materially more-advanced status than the
header's 🔍 investigating — a self-contradiction within the item. PR #83 (claude/lane-h-setup-bmi058) Merged=YES per
PR_INDEX.md, title '(#102 #61)', merge commit 23387b7 (MAIN_LOG.txt:7), implementation commit c2de665 '#102: bound +
retune chat generation; hysteresis tail-repetition breaker' (MAIN_LOG.txt:10).
Talaria/Services/Live/LocalChatBackend.swift:76-77 defines…

---

## D. Status defensible, but wording is stale (34)

These stay **🔧** (device verification genuinely remains) — but each still claims to be un-merged / "built in
cloud" / "needs xcodegen" when its PR has already merged and the code is on `main`. The only work left is the
device-verify pass. Corrected inline in the file.

| # | Item | Merged via | Stale claim → truth |
|---|---|---|---|
| 7 | Auth token seam | (n/a — #14) | "Keychain only" → 3-tier provider (Keychain + DEBUG env + API-key fallback) |
| 21 | Agent-file present/download | relay route deployed | "Tier 2 relay follow-up" → Tier 2 relay route done + deployed to OJAMD |
| 24 | OJAMD server-side rollup | several | Private Relay onboarding doc shipped; #24e narrowed to diagnostics-panel check |
| 33 | Apple app integrations | #69/#70 | device-side EventKit shipped + device-verified; only Mac-host connectors gated |
| 34 | T6 Mac backend | — | cross-ref typo: "Phase 1 → #106" → #107 |
| 50 | Terminal accent lock | merged | 🐛→🔧: `lockedAccentSlot` merged to main; device-verify owed |
| 51 | CLI test-host resolve | project.yml override | "Next:" para stale — explicit TEST_HOST override now on main; re-run owed |
| 53 | Sensor drain | merged 07-06 | 🐛→🔧: location/health outboxes decoupled on main; verify owed |
| 56 | Ask Hermes intent | PR #11 | "not compiled" → merged; core device-verified 07-11 |
| 57 | Attachment OCR | PR #11 | "not compiled" → merged (PR #11); verify owed |
| 58 | Control Center controls | PR #11 | "not compiled" → merged; device pass 07-11 partial (Ask-control bug localized) |
| 59 | Voice-memo attachments | PR #11 | "not compiled" → merged (PR #11); verify owed |
| 60 | _thinking reasoning channel | PR #12 | "needs xcodegen+build" → merged; 07-11 device pass ran (failed → still probing) |
| 61 | On-device titles/previews | PR #12/#83 | "same not-compiled caveat" → both PRs merged; on-device runs recorded |
| 63 | BG wake tasks | PR #22 | compile-check clause stale → merged; only device-verify half open |
| 64 | Widget HealthKit | PR #21 | "Needs Mac: build" → merged; only device-verify half open |
| 65 | AlarmKit executor | PR #23 | compile-check clause stale → merged; ring-through-Silent verify owed |
| 66 | Spotlight index | PR #24 | compile-check clause stale → merged; find→tap-through verify owed |
| 67 | LocalChatBackend | PR #32 | "compile-check / after #27" → both merged; device checklist owed |
| 68 | ChatBackendRouter | PR #33 | "Needs Mac: compile" → merged; device pass + 2 product decisions owed |
| 72 | PCC tier | PR #37 | "compile-check" → compiled + running on-device (#111); blocked on Apple grant |
| 73 | Native fallback voice | PR #39 | "not compiled / Needs Mac" → merged; on-device loop checklist owed |
| 74 | CarPlay voice | PR #40 | "Needs Mac" → merged; Sim pass + Apple grant owed (entitlement disabled) |
| 75 | HUD single-line | PR #43 | "not compiled" → merged; acceptance sweep owed |
| 77 | hermes:// URL scheme | PR #51 | "not compiled" → merged; device-verify note not yet added |
| 78 | Message context menu | PR #52 | "not compiled / Needs Mac" → merged; device-verify not yet added |
| 80 | Inbox wiring | PR #54/#59 | "gh#58 built, not compiled" → Lane C merged; server-side #58 still OPEN |
| 84 | Talk preflight | PR #62 | "not compiled" → merged to main; device checklist owed |
| 91 | Theme suite (Lane E) | #66/#70/#72-74 | trailing "Phases 2+3 NOT compiled" para stale (cites dead PR #71) |
| 92 | Markdown depth (Lane B) | PR #60 | trailing "not compiled" para stale — device pass 07-11 PASS recorded above it |
| 93 | P1 continuity (Lane A) | PR #61 | "NOT compiled" + merge checklist stale; CondenserFidelity run still unconfirmed |
| 99 | Interactive HTML preview | PR #78 | "UN-GATED" → Lane I merged (PR #78); device-verify owed |
| 100 | Inline charts | (unblocked) | "awaiting device verify" clause stale — #92 flipped PASS 07-11 |
| 108 | iPad split view | PR #80/#81 | trailing "PR 2 not compiled" para stale; iPad-side device matrix still open |

---

## E. How the adversarial verify changed the outcome

The second Sonnet 5 pass was not a rubber stamp. It **overturned the first-pass call on 4 of 11**
"under-reported" claims, correctly refusing to upgrade merged-but-unverified work to *done*:

| # | First pass said | Verifier corrected to | Why |
|---|---|---|---|
| 50 | done (close the 🐛) | merged, verify owed 🔧 | `lockedAccentSlot` code merged, but no device-verify note |
| 51 | RESOLVED ✅ | stale-wording 🔧 | "landed in `9964f02`" was a **shallow-clone graft artifact**; no build re-run recorded |
| 53 | done (close the 🐛) | merged, verify owed 🔧 | outbox-decouple fix merged, device-verify still owed |
| 99 | done ✅ | merged, verify owed 🔧 | Lane I merged (PR #78) but no device-verify note |

Two verifiers independently caught the **squash-merge / shallow-clone false-negative trap** — a naive
`git branch --merged` or `git show <sha>` check makes merged work look unmerged in this repo. They fell back
to the authoritative signals (PR `merged_at` + file presence on `main`) exactly as the rubric required. On
**#76** the verifier went further and *executed* `tools/orphan-audit.sh --self-test` live (exit 0, "all 5
known graveyard types re-flagged") to confirm the tool still works today. Every one of the 13 flips in §A–C
was **upheld** under this scrutiny.

---

## Appendix — all 112 items

`cls`: none = accurate · **over** = shown closed/actually open · **under** = shown open/actually done ·
**hdr** = header vs body · **word** = stale wording.

| # | claimed | final status | cls | conf |
|---|:--:|---|:--:|:--:|
| 1 | ✅ | done ✅ | — | high |
| 2 | ✅ | superseded | — | high |
| 3 | 📝 | note 📝 | — | high |
| 4 | 💤 | dormant 💤 | — | medium |
| 5 | ✅ | done ✅ | — | high |
| 6 | 📝 | note 📝 | — | high |
| 7 | 📝 | note 📝 | word | high |
| 8 | 📝 | parked ⏸️ | — | medium |
| 9 | ✅ | done ✅ | — | high |
| 10 | ✅ | done ✅ | — | high |
| 11 | ✅ | done ✅ | — | high |
| 12 | ✅ | done ✅ | — | high |
| 13 | ✅ | done ✅ | — | medium |
| 14 | ✅ | done ✅ | — | high |
| 15 | ✅ | done ✅ | — | high |
| 16 | ✅ | done ✅ | — | high |
| 17 | ✅ | superseded | **over** | high |
| 18 | ✅ | merged, verify owed 🔧 | **over** | medium |
| 19 | ✅ | done ✅ | — | high |
| 20 | ✅ | done ✅ | — | high |
| 21 | 🔧 | in progress 🔧 | word | high |
| 22 | ✅ | done ✅ | — | high |
| 23 | ✅ | done ✅ | — | high |
| 24 | 🔧 | in progress 🔧 | word | medium |
| 25 | 🔧 | open bug 🐛 | **hdr** | high |
| 26 | ✅ | done ✅ | — | high |
| 27 | 📝 | note 📝 | — | high |
| 28 | ✅ | done ✅ | — | high |
| 29 | ✅ | done ✅ | — | high |
| 30 | ✅ | done ✅ | — | high |
| 31 | ✅ | merged, verify owed 🔧 | **over** | medium |
| 32 | ✅ | done ✅ | — | high |
| 33 | 📝 | in progress 🔧 | word | high |
| 34 | 🔧 | merged, verify owed 🔧 | word | high |
| 35 | ✅ | done ✅ | — | high |
| 36 | ✅ | done ✅ | — | high |
| 37 | 🔧 | superseded | **under** | high |
| 38 | ✅ | done ✅ | — | high |
| 39 | ✅ | done ✅ | — | high |
| 40 | ✅ | done ✅ | — | high |
| 41 | ✅ | done ✅ | — | high |
| 42 | ✅ | done ✅ | — | high |
| 43 | ✅ | done ✅ | — | medium |
| 44 | ✅ | done ✅ | — | high |
| 45 | 🔧 | blocked ⛔ | — | high |
| 46 | ✅ | done ✅ | — | high |
| 47 | 🎯 | parked ⏸️ | **under** | medium |
| 48 | 🔧 | done ✅ | **under** | high |
| 49 | 🔧 | done ✅ | **under** | medium |
| 50 | 🐛 | merged, verify owed 🔧 | word | high |
| 51 | 🔧 | merged, verify owed 🔧 | word | medium |
| 52 | 🔧 | in progress 🔧 | — | low |
| 53 | 🐛 | merged, verify owed 🔧 | word | high |
| 54 | ✅ | done ✅ | — | high |
| 55 | 🔧 | superseded | **under** | high |
| 56 | 🔧 | in progress 🔧 | word | high |
| 57 | 🔧 | merged, verify owed 🔧 | word | high |
| 58 | 🔧 | open bug 🐛 | word | high |
| 59 | 🔧 | merged, verify owed 🔧 | word | high |
| 60 | 🔧 | investigating 🔍 | word | high |
| 61 | 🔧 | merged, verify owed 🔧 | word | high |
| 62 | 🔧 | merged, verify owed 🔧 | — | medium |
| 63 | 🔧 | merged, verify owed 🔧 | word | high |
| 64 | 🔧 | merged, verify owed 🔧 | word | high |
| 65 | 🔧 | merged, verify owed 🔧 | word | high |
| 66 | 🔧 | merged, verify owed 🔧 | word | high |
| 67 | 🔧 | merged, verify owed 🔧 | word | high |
| 68 | 🔧 | merged, verify owed 🔧 | word | high |
| 69 | ✅ | done ✅ | — | high |
| 70 | ✅ | done ✅ | — | high |
| 71 | 🔧 | merged, verify owed 🔧 | — | high |
| 72 | 🔧 | blocked ⛔ | word | high |
| 73 | 🔧 | merged, verify owed 🔧 | word | high |
| 74 | 🔧 | blocked ⛔ | word | high |
| 75 | 🔧 | merged, verify owed 🔧 | word | high |
| 76 | 🔧 | done ✅ | **under** | high |
| 77 | 🔧 | merged, verify owed 🔧 | word | high |
| 78 | 🔧 | merged, verify owed 🔧 | word | high |
| 79 | 🔧 | done ✅ | **hdr** | high |
| 80 | 🔧 | merged, verify owed 🔧 | word | high |
| 81 | 🔧 | merged, verify owed 🔧 | — | high |
| 82 | ⏸️ | parked ⏸️ | — | high |
| 83 | 📝 | note 📝 | — | high |
| 84 | 🔧 | merged, verify owed 🔧 | word | high |
| 85 | 🔧 | merged, verify owed 🔧 | — | high |
| 86 | 🔧 | merged, verify owed 🔧 | — | high |
| 87 | ✅ | done ✅ | — | high |
| 88 | ✅ | done ✅ | — | high |
| 89 | ✅ | done ✅ | — | high |
| 90 | 📝 | note 📝 | — | high |
| 91 | ✅ | done ✅ | word | high |
| 92 | ✅ | done ✅ | word | high |
| 93 | 🔧 | merged, verify owed 🔧 | word | high |
| 94 | 🔧 | done ✅ | **under** | high |
| 95 | 👀 | watch 👀 | — | high |
| 96 | ✅ | done ✅ | — | high |
| 97 | ✅ | done ✅ | — | high |
| 98 | ✅ | done ✅ | — | high |
| 99 | 🔧 | merged, verify owed 🔧 | word | high |
| 100 | 📝 | note 📝 | word | high |
| 101 | 📝 | note 📝 | — | high |
| 102 | 🔍 | merged, verify owed 🔧 | **hdr** | high |
| 103 | ✅ | done ✅ | — | high |
| 104 | 🔧 | in progress 🔧 | — | high |
| 105 | ✅ | done ✅ | — | medium |
| 106 | ✅ | done ✅ | — | high |
| 107 | 🔧 | merged, verify owed 🔧 | — | high |
| 108 | 🔧 | in progress 🔧 | word | high |
| 109 | 📝 | note 📝 | — | high |
| 110 | 🔧 | open bug 🐛 | — | high |
| 111 | 🐛 | open bug 🐛 | — | high |
| 112 | ✨ | note 📝 | — | high |

---

*Generated by a 36-agent audit workflow (19 Sonnet 5 auditors + 17 Sonnet 5 adversarial verifiers).
Raw per-item verdicts with full evidence: `scratchpad/final_verdicts.json`.*
