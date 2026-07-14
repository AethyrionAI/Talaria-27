# HANDOFF — 2026-07-13 (eve) — OJAMD + open work

**Repo:** AethyrionAI/Talaria-27 `main` @ `f51b911` (audit + eve verdicts folded into OPEN_ITEMS).
**Branches pushed, UNMERGED (Owen's merge+device bucket):**
- `claude/t27-pcc-crash-stopgap` (`c595bf4`) — **merge first** (stops the PCC send-crash)
- `claude/t27-61-fallback-card-dedup` (`07d8d9a`)
- `claude/t27-hermes-switch-nudge` (`ef5dbd9`)
**Dispatch specs on main:** `FABLE-T27-21`, `-104`, `-110`.
**GitHub issues (dev backlog):** #87→#93  (= OI #60 / #66 / #58 / #25 / #104 / #110 / #21).
**OJAMD:** services **online** (confirmed by Owen). NB — Mac→OJAMD HTTP health probes timed out tonight while ICMP + tailnet were clean; earlier in the session they answered (relay 200 / gateway 401). Treat as a Mac-vantage HTTP quirk, not an outage — run OJAMD tasks from OJAMD or the phone, or reconcile the Mac's HTTP path first.
`planning/` untracked by design.

---

## OJAMD — DO (needs the box / live Hermes; cloud CC can't reach it)

1. **#21 probe — the Tier-2 gate (blocks GH #93).** Drive one real **non-text** `write_file` (ask the agent to save a small PDF into `MobileDL` = `AGENT_FILES_DIR`), capture that turn's `:8642/chat/stream` SSE, and record whether the `write_file` `tool.started.args` carries `content` (base64? absent?) for a binary. That answer decides the app-side fetch trigger.
2. **#21 Hermes-side nudge.** Confirm/So the agent writes shareable artifacts into `MobileDL` (config/prompt on OJAMD, not app code).
3. **#85 deploy** — `hermes_delegate` MCP path (built in cloud, OJAMD deploy owed).
4. **#86 deploy** — relay QueuePool exhaustion fix (built in cloud, OJAMD deploy owed).
5. **#60 capture (blocks GH #87).** Grab ONE raw `tool.progress` event where `tool_name == "_thinking"` off `:8642/chat/stream` (a "show your reasoning" prompt). Pin (a) the real reasoning key, (b) increments vs snapshots, (c) whether the model emits distinct reasoning at all. → then the `thinkingDelta` fix.
6. **#25 capture (blocks GH #90).** A live session with Verbose Logging + `run.completed` payloads; ground-truth the CTX denominator against Hermes's own context check.

## OJAMD — VERIFY (confirm prior work is actually deployed AND running)

- Services healthy: relay `:8000`, gateway `:8642` (pythonw, ~15–20s warmup), shim `:8765`; **connector ATTACHED** — check `Get-NetTCPConnection -State Established` to `:8000`, not the 202-retry trap (a dead connector looks like an endless retry).
- Deploy checkout `O:\Hermes\Talaria` (`ojamd-deploy` tracking `t27/main`) is **not lagging** `t27/main` — rebase (not fast-forward) if behind. Past incident: 107 commits behind.
- After #85/#86: confirm the code is **running**, not just pulled (restart the owning service — relay = `Restart-Service HermesMobileRelay`; gateway is the user `pythonw` process, NOT an NSSM service).
- Recon the Mac↔OJAMD HTTP path (see header note) so Mac-driven probes work again.

## OFF-OJAMD — DO / VERIFY (Owen's bucket)

- **Merge the 3 branches (PCC FIRST)** → one device build on **whoGoesThere** → verify: PCC gone from the picker + no crash; #61 cards have distinct title/preview; the Uplink nudge appears when paired-but-unkeyed.
- **iPad:** Settings → Uplink → paste the Hermes API key (from OJAMD `~/.hermes/.env`); set the Sessions host to `100.110.102.59:8642`. Unlocks Hermes on the iPad.
- **Dispatch to CC now** (cloud-safe, no OJAMD): #104 (GH #91) and #110 (GH #92).
- OPEN_ITEMS already reflects tonight's device passes (#18/#50/#53/#63/#64/#65/#71 → ✅) and #66 → 🐛; the ~34 merged-verify-owed items remain your device passes.

## AFTER-WORK captures (each unblocks a bug)

- **#60 / GH #87** — the `_thinking` payload (see OJAMD DO #5).
- **#25 / GH #90** — the CTX live-session capture (see OJAMD DO #6).

---

## Session recap (what changed tonight)

- **Start:** merged the OPEN_ITEMS accuracy audit (`cf5609f`); spot-verified its two riskiest flips (#94 no-bug, #17 outage) before merging.
- **Device pass (whoGoesThere):** #18 / #50 / #53 / #63 / #64 / #65 / #71 → ✅; #66 Spotlight → 🐛; #61 titles FAILED (then fixed); iPad (#108) reached the local brain but not Hermes.
- **Sim run:** build ✅ @ `cf5609f` (iOS 27, Xcode-beta), full suite **582/582** (26 skipped — incl. #93 `CondenserFidelity`, which is model-gated so it **skips on sim = still owed on AI hardware**). Deep-link #77 scheme/router fired; composer-seed needs a configured backend.
- **Fixed on branches:** #61 (fallback card echoed the reply's first line into both title+preview on empty-user turns); #72+#111 (PCC send-crash + churn — a `pccGrantConfirmed` master gate stops constructing `PrivateCloudComputeLanguageModel` until Apple grants the entitlement); the Hermes-switch nudge (paired-but-unkeyed → "add your key in Uplink" banner). All suites green (up to 587/587 on the nudge branch).
- **Specs + issues:** dispatch specs for #21/#104/#110; GitHub issues #87–#93; bugs localized in code — #58 (Ask control wiring, `HermesControls.swift`), #66, #25, #60 (reasoning carbon-copy = `thinkingDelta` likely grabbing `preview`).
- **Diagnosis:** iPad #108 is NOT a Lane J defect — it's the three-plane onboarding gap (pairing ≠ Sessions-API key).

## Next-session opening moves

1. Confirm OJAMD services + connector attach; reconcile the Mac↔OJAMD HTTP path.
2. Run the #21 probe (unblocks GH #93) and the #60/#25 captures (unblock GH #87/#90).
3. Deploy #85/#86; verify running.
4. Merge the 3 branches (PCC first), device build, run the verify list.
