# Device Test Script — Merged Waves (2026-07-10)

**Target:** whoGoesThere · `main @ 8830b11` (PRs #63 baseline, #59 Lane C, #60 Lane B, #61 Lane A, #62 #84-preflight).
**Sim suite:** 416/416 green. Device build: SUCCEEDED (arm64), entitlements intact.

## Prereqs
- Chat plane: DIRECT → `ojamd:8642`, API key in Keychain (Host: LINKED·DIRECT).
- Relay plane: paired; Tailscale up + OJAMD relay live at `100.110.102.59:8000` (Reachability should leave STANDBY).
- Themes to switch during test: **Deep Field** (dark) + **Paper Tape** (light), via Appearance & HUD.
- Have a real Hermes conversation to work in.

## 0 — Regression sanity (2 min)
- [ ] Send/receive a normal Hermes turn — reply streams, receipt shows.
- [ ] History/sessions drawer loads prior conversations.
- [ ] Models → SELECT switches model without error.

## 1 — Lane C: correctness batch (#59)

**1a. `/save` honesty + share sheet**
- [ ] In a chat, type `/save`.
- Expect: system line **naming the file** ("…saved to Documents folder as `<name>.json`") **AND a share sheet** (Save to Files / AirDrop).
- Fail if: it claims success but no file / no share sheet, or the old generic "Conversation saved" with no name.

**1b. Failed-send error haptic**
- [ ] Airplane mode (or kill relay/host), send a message so it fails terminally.
- Expect: an **error buzz** on the failure.
- [ ] Then force-quit + relaunch (with the old failed turn in cache).
- Expect: **NO buzz at launch** (cold-load of an old failure must stay silent).

**1c. Inbox resilience (#58) — opportunistic**
- [ ] If you can push a malformed/bad-`kind` row to the relay inbox, open the inbox.
- Expect: good rows still load (no false "relay offline"); Console logs `fetchInbox: skipped unparseable inbox row id=… kind=…`.
- Skip if you can't inject a bad row.

## 2 — Lane B: markdown depth (#60)

**2a. Rich render**
- [ ] Ask Hermes for a reply mixing: a few **headings** (#…###), a **GFM table**, a **nested list** (ordered + unordered), a **block quote**, and a **swift fenced code block**.
- Expect: graduated heading sizes; table as a **horizontally-scrollable grid** (header rule + faint row striping); quote with accent bar; nested bullets/ordinals; **syntax-highlighted** code.

**2b. Theme legibility**
- [ ] View that same reply under **Deep Field** (dark) and **Paper Tape** (light).
- Expect: code-block token colors legible in **both**; table scroll works inside the bubble.

## 3 — Lane A: continuity fabric (#61) — the headline

**3a. Brain-hop context transplant** (the key one)
- [ ] In a Hermes chat, establish context + a **correction** (e.g. "My cat is named Max" → later "Actually, correct that — his name is Milo").
- [ ] Force-quit + relaunch (drops the in-memory server session; journal persists).
- [ ] Send a turn that leans on that context (e.g. "What's my cat's name?").
- Expect: a **"[Context transplanted into a fresh session — N tokens]"** notice row appears, AND the reply reflects the **latest** value (Milo, not Max).
- Fail if: no transplant notice on the first post-relaunch Hermes turn, or the reply regresses to the pre-correction value.

**3b. Priming token cost**
- [ ] On that transplanted turn, open the status/receipt card.
- Expect: the **priming cost surfaces separately** from the metered turn tokens.

**3c. Offline compose outbox**
- [ ] Airplane mode (or relay/host down). Compose + send a message.
- Expect: turn **parks/queues** (not a hard failure).
- [ ] Force-quit + relaunch while still offline.
- Expect: the queued turn **survives** (still pending).
- [ ] Restore connectivity.
- Expect: outbox **drains and sends** — and a drained turn also transplants (notice row).

**3d. Journal persistence**
- [ ] Confirm conversations persist across relaunch independent of any server session (they should always come back locally, even offline).

## 4 — #62: talk preflight third state (#84) — WEDGE-CAVEATED
> #82: the current Apple beta seed breaks all third-party mic capture, so the real "no mic input" path can't be truly exercised until a fixed seed. Verify graceful behavior only:
- [ ] Open Talk. Expect it to **block with guidance and not hang / not falsely show "Connected."**
- [ ] If capture is wedged, the guidance should be **reboot** wording (not a Settings dead-end).
- [ ] Deny mic permission → expect the **"enable in Settings"** message **with a Settings deep link** (distinct from the reboot case).

## Not in scope
- **#63** green baseline — test-only, no device surface.
- **Lane D (#65)** — not merged (DO-NOT-MERGE probe rung).
- **Lane E (#66)** — not merged; you're building/verifying that one separately.

## Notes / found issues
-
