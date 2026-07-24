# OPUS-T27-SETTINGS — #151, #152, #153: the Hermes Host surface

**Items:** OPEN_ITEMS #151, #152, #153 · **Repo:** AethyrionAI/Talaria-27 · **Base:** main
**Branch:** `claude/t27-settings-host-surface` · **Toolchain:** Xcode-beta4, pinned sim
**Baseline:** 1121 tests / 103 suites + 8 UI · `export GH_PAGER=cat` first
**Staleness check:** `gh pr list --repo AethyrionAI/Talaria-27 --state all --limit 20`

## PHASE 0 IS MANDATORY — all three items carry `source-confirm owed`

**None of these has been read against source.** They were filed from Owen using the app on
2026-07-20. Every fix shape below is a *hypothesis written by someone who could see the symptom and
not the code.*

Bundle B ran the same structure and **two of its four premises were wrong** — #174's "no downscale
anywhere" (there was one, mis-scaled) and #154's "11 dead branches" (3; deleting the other 8 would
have removed shipping behaviour). **Assume at least one hypothesis here is also wrong.**

**Do Phase 0 for all three before writing any code, and report before proceeding.** If a confirm
contradicts its hypothesis, STOP that item and report rather than implementing the guess.

### Phase 0 questions

**#151** — `grep -rn "testConnection\|Test Connection" Talaria/Features/Settings Talaria/Stores`
- Does the action already perform a probe and drop the result, or is it a stub?
- Is there an existing status enum to reuse (#84 / #71 established a wording family)?
- Which plane does it probe — Sessions API `:8642`, relay `:8000`, or shim `:8765`? **These are
  independent** (three-plane architecture); a "Test Connection" that probes the wrong one is
  worse than none.

**#152** — `grep -rn "Pair Device\|Pairing" Talaria/Features/Settings`
- Where does revoke live today?
- **Do Siri phrases, Spotlight strings, deep links, or tests hard-code "Pair Device"?** Renaming a
  string that an App Intent phrase is bound to is how #56 became permanent. Check before renaming.

**#153** — find the host/profile model
- **Single host record, or already an array?** This is the whole sizing question. If single-host,
  #153 is a DATA-MODEL lane, not a UI lane, and should be split out and re-scoped rather than
  squeezed in here.
- Keychain key layout for per-host secrets — needed before delete can purge cleanly.

## Then build — #151 and #152 only

**#151 — Test Connection feedback.** State enum (idle / testing / success / failure(reason))
driving an inline spinner, then a pass row (host + latency) or a fail row with a reason
(unreachable / auth rejected / wrong port). Use the standardized status wording family.

**Give it a 5s dedicated timeout.** #145/#136 established three distinct network shapes — fast
refuse, firewall black-hole (~60s), and accepted-but-silent warmup. A Test button that hangs
silently for 60s on black-hole is its own papercut and would land as a new item.

**#152 — rename and resurface.** Recommended: **"Pairing & Devices"** for the row; inside, lead
with current host/pairing state and a clear Disconnect/Revoke, with "Pair New Device (QR)" as the
add action. Destructive actions must not hide behind an add-only verb.

Avoid "Connection"/"Host Connection" — it collides with #151's Test Connection language on the
same screen.

**The QR pairing flow itself does not change.** Three-plane model intact; the pairing QR still
carries no Sessions API key. Do not touch it.

## #153 — gate it on Phase 0

If hosts are **already an array**, implement here: delete (distinct from revoke), explicit active
selection, and the empty-list path.

If hosts are **a single record**, STOP and report. It becomes its own lane.

**Semantics that must be answered explicitly, not left implicit:**
- **DELETE ≠ REVOKE.** Revoke severs the credential; delete removes the profile. Do not conflate.
- Deleting the ACTIVE host — block, or fall back to another / to standalone?
- Deleting the LAST host — must return to free-tier standalone **cleanly and must not wedge**
  (ties to #136/#137 posture).
- Delete confirms (destructive). Revoke may not need one.
- **Delete MUST purge the per-host Keychain secret.** An orphaned credential outliving its profile
  is exactly the lifetime bug #137 just fixed elsewhere.

## Verification

Full suite on the pinned sim `47F68496-24F9-45D9-93D3-1C778DB6B557`, `CODE_SIGNING_ALLOWED=NO`;
report against **1121 / 103** and account for the delta. `xcodegen generate` only if Swift files
are added or removed — if run, verify `aps-environment: development` survived, commit the regen
separately.

Device verification is Owen's and is owed, not done: Test Connection against a live host, against a
stopped host, and against a black-holed one.

## Commit discipline

File-scoped commits. OPEN_ITEMS.md separate from code. `gh pr merge --merge`, never squash.

## Out of scope

The QR pairing flow. Anything on the relay or gateway side. #116's shim-token work.
