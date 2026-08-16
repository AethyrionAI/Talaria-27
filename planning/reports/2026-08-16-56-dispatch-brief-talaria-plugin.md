# Handoff — Talaria plugin critical storage and device-routing fixes

**Prepared:** 2026-08-16  
**Primary repository:** `AethyrionAI/talaria-plugin`  
**Reference application:** `AethyrionAI/Talaria-27` — do not mix with Talaria Prime  
**Starting plugin commit audited:** `fd5d7d1bad008763d8318fba5f66f2f523aea541`  
**Starting Talaria-27 commit audited:** `f02b1eb55335e8a87e5c6d7366905efa075ab88d`

## Owen's non-negotiable workflow instruction

**Implement the work on a branch and submit a GitHub pull request for Owen's review. Nothing merges to `main` without Owen's explicit approval.**

This means:

- Do not commit directly to `main`.
- Do not merge the PR yourself.
- Do not enable auto-merge.
- Do not interpret green tests, CI, or a review agent's approval as permission to merge.
- Leave the branch and PR open after reporting the PR URL and evidence to Owen.
- Do not modify or deploy over a live plugin checkout on the Mac or OJAMD.
- Do not bounce a live gateway, rotate devices, unpair devices, or run live-phone experiments without a fresh, explicit authorization from Owen.

Use a fresh clone or isolated worktree. Before branching:

1. `git fetch origin`
2. Confirm local `main` and `origin/main` match.
3. Branch from the current `origin/main`, suggested name:
   `fix/transactional-storage-device-routing`

The primary deliverable is one reviewable PR in `AethyrionAI/talaria-plugin`. Do not make cross-repository Talaria-27 changes in the same lane. If an app protocol change proves necessary, stop, document the exact requirement, and ask Owen whether to open a separate Talaria-27 PR.

---

## Executive goal

Fix the two confirmed correctness defects before extending the plugin, increasing paired-device usage, or retiring more sidecars:

1. **The JSON device store and outbox lose data under concurrent access.**
2. **Outbox items are not scoped to their target device; multiple paired devices can receive the same targeted item.**

Keep the existing supported Hermes-plugin architecture. This is a stabilization lane, not a rewrite of the platform adapter or Talaria application.

---

# Critical finding 1 — persistence is not concurrency-safe

## Current code

Both stores use an unsynchronized read-modify-write cycle and a single fixed temporary filename:

- `store.py:28-50`
- `outbox.py:23-44`

Representative shape:

```python
data = _load()
# mutate data
_save(data)

# _save
path = ...
tmp = path.with_suffix(".json.tmp")
tmp.write_text(...)
tmp.replace(path)
```

The plugin already crosses event-loop/thread boundaries by design. Store/outbox operations can also come from a separate CLI process. A Python GIL is not a transaction and does not protect a load-modify-save sequence across threads or processes.

## Confirmed reproduction from the audit

A deterministic 16-worker threaded probe against current `main` produced:

| Operation | Requested | Records remaining | Exceptions |
|---|---:|---:|---:|
| Concurrent outbox appends | 100 | **3** | **72** |
| Concurrent device pairings | 100 | **2** | **60** |

The failures were competing operations losing or replacing the same `outbox.json.tmp` / `devices.json.tmp`. Even operations that do not throw can overwrite a sibling caller's update because both loaded the same earlier document.

This was a synthetic deterministic probe, not a claim that 100 live gateway writes were observed. The defect only requires two overlapping operations; the high count makes it reproducible.

## Required implementation direction

**Preferred fix: replace the two mutable JSON documents with a small plugin-owned SQLite database.**

Suggested location:

```text
<HERMES_HOME>/talaria/talaria.db
```

Do not write into Hermes core's `state.db`.

Use:

- Transactions for every read-modify-write operation.
- WAL mode where supported.
- A sensible busy timeout.
- Foreign keys where useful.
- Profile awareness through the existing `get_hermes_home()` resolution.
- Restricted file permissions where the platform supports them.
- No new third-party runtime dependency unless it is genuinely necessary; Python's `sqlite3` should be sufficient.

Keep the public module API of `store.py` and `outbox.py` as stable as practical so `admin.py`, `envelope.py`, `platform_adapter.py`, and current tests need minimal churn.

### Suggested schema

At minimum:

```text
devices
- id primary key
- token_sha256
- install_id
- name
- created
- active
- last_seen
- deactivated

outbox_items
- id primary key
- kind
- text
- created_at
- target_device_id
- delivery_scope
- delivered_at
- active
- meta_json

schema_metadata
- schema_version
- migration state/version
```

The exact schema is yours to justify in the PR, but it must support atomic pairing, deactivation, last-seen updates, appends, drains, and acknowledgements.

## Migration requirements

The Mac and OJAMD already have live JSON state. A correct implementation must not strand or silently delete it.

On first use when the SQLite DB is absent:

1. Detect existing `devices.json` and `outbox.json`.
2. Import them in one transaction.
3. Preserve all existing IDs, token hashes, active/deactivated state, names, install IDs, timestamps, metadata, and delivered/pending state.
4. Validate the imported counts and key fields before marking migration complete.
5. Keep the original JSON files as recovery evidence; do not delete them. A clear suffix such as `.migrated-backup` is acceptable only after successful validation.
6. Make migration idempotent. A crash or second startup must not duplicate rows.
7. A malformed legacy file must fail loudly and preserve the evidence. Do not silently convert a corrupt durable outbox into an empty one.

Do not run this migration on either live host as part of the coding lane. Test it entirely against temporary directories and fixtures. Live deployment is a separate, explicitly authorized step after Owen reviews and merges the PR.

## Required RED/GREEN tests

Write failing tests first, then implement. Include at least:

- Concurrent outbox appends preserve every unique item and raise no exceptions.
- Concurrent pairings preserve every unique device and raise no exceptions.
- Concurrent append plus acknowledgement does not lose the new item or resurrect the acknowledged item.
- Pairing plus `touch_device` does not overwrite either update.
- Cross-**process** coverage, not only threads, because the CLI and gateway are separate processes.
- Legacy devices migration preserves every field.
- Legacy outbox migration preserves pending and delivered items.
- Interrupted/idempotent migration does not duplicate or lose records.
- Corrupt legacy input is preserved and reported rather than silently treated as empty state.
- Existing deactivate-never-delete and token-hash properties remain pinned.

If SQLite is proven infeasible in the installed plugin environment, stop and report the evidence before substituting file locks. Do not silently downgrade to a weaker solution merely because it is smaller.

---

# Critical finding 2 — outbox items are not device-targeted

## Current code

`TalariaPlatformAdapter.send(chat_id, ...)` appears to target a recipient but only places `chat_id` in item metadata:

- `platform_adapter.py:52-61`

The actual drain ignores that value:

- `envelope.py:136-149` calls global `outbox.pending()`.
- `outbox.py:73-78` returns every active, undelivered item.

## Confirmed reproduction from the audit

The audit paired a phone and an iPad, queued one item with the phone's device ID as its declared `chat_id`, then drained both devices before acknowledgement.

Result:

```text
phone_item_ids: [same item]
ipad_item_ids:  [same item]
both_received_same_item: true
```

Depending on drain/ack timing, the current behavior is either duplicate delivery or first-device-wins delivery. Neither is a valid implementation of a recipient-bearing `send(chat_id, ...)` contract.

## Required semantics

Use explicit, machine-enforced routing:

1. `TalariaPlatformAdapter.send(chat_id, ...)` targets exactly the active device represented by `chat_id`.
2. A target that is absent or inactive returns an honest failed `SendResult`; do not queue an undeliverable item while reporting success.
3. `pending(device_id)` returns only items that device is entitled to drain.
4. An acknowledgement can settle only an item delivered/targeted to the authenticated device. A different device must not be able to acknowledge it.
5. Broadcast, if supported, must be explicit. Never infer broadcast from a missing target.
6. The existing CLI must behave safely with multiple devices:
   - One active device: `hermes talaria send <text>` may target it automatically.
   - Multiple active devices: require `--device <id>` or an explicit `--all`; do not guess.
   - `--all` should fan out one targeted row per active device unless the schema implements equally explicit per-device delivery state.
7. Maintain exactly-once acknowledgement semantics per target device.

### Legacy unscoped pending items

Old outbox JSON rows have no authoritative target. Do not pretend otherwise.

Recommended migration behavior:

- Delivered legacy rows can remain historical without a target.
- A pending legacy row should migrate as an explicit `legacy_any`/first-available item that is atomically claimed by one device on drain, preventing both duplication and loss.
- Record this compatibility behavior in code and README.

If a materially better compatibility rule is discovered, explain it in the PR. Do not silently fan pending messages to every device or arbitrarily choose a target without documenting the decision.

## Required RED/GREEN tests

Include at least:

- Two active devices drain concurrently; a phone-targeted item appears only on the phone.
- Reversing drain order does not change the recipient.
- The non-target device cannot acknowledge the item.
- An inactive/unknown target produces a failed `SendResult` and no queued row.
- CLI with one active device targets it.
- CLI with multiple active devices and no selector refuses with actionable text.
- CLI `--device` targets exactly one device.
- CLI `--all` creates explicit per-device deliveries with independent acknowledgements.
- Legacy unscoped pending migration has deterministic, documented, exactly-once behavior.
- Existing app envelope fields remain compatible unless a separate app PR is explicitly approved.

---

# Scope guardrails

## Must remain true

- Authentication stays fail-closed.
- Pairing tokens remain hashed at rest.
- Device tokens stay bound to their claimed device ID.
- Deactivation remains deactivate-never-delete.
- The cross-loop wake/resolve fix in `transport.py` must not regress.
- The plugin remains profile-aware through `get_hermes_home()`.
- No Hermes core modifications.
- No Talaria Prime changes.
- No live plugin deployment or gateway restart in this lane.

## Out of scope unless required by the critical fixes

- Runs transport migration.
- Desktop `plugin.js` face.
- Conversational installation.
- Making the plugin public.
- Relay decommission.
- App-side UI changes.
- Broad renaming/refactoring of transport code.

---

# OI #269 and publication decision

Owen has decided:

> **Keep `AethyrionAI/talaria-plugin` private while Talaria itself is private. When the Talaria app goes public, the plugin can go public at the same time.**

Consequences for this lane:

- The private repository is **not** a blocker to ongoing plugin development.
- Do not change repository visibility.
- Do not publish releases or installation instructions aimed at the general public yet.
- OI #269-B's public conversational-installer path remains intentionally deferred until the app-publication milestone and a restart/reload story are settled.
- The storage and routing fixes in this handoff proceed now and are independent of publication.
- It is still worthwhile to keep the repository publication-ready: no secrets, personal paths, host addresses, or private operational details in new commits.

---

# Secondary improvements allowed in the PR

Only do these after both critical fixes and their tests are green. Keep them small and separately committed so Owen can review or drop them independently.

## Recommended

1. **Manifest truth**
   - Bump the plugin version from stale `0.1.0` to an accurate next version.
   - Update the Phase-1-only description.
   - Add `provides_tools` for `talaria_phone_query` so `hermes plugins doctor . --ci` has no warning.

2. **README truth**
   - Describe the webhook adapter as shipped.
   - Document the new storage location/migration and multi-device CLI semantics.
   - Preserve the warning about the expected `talaria` import/package name until packaging is fixed.

3. **CI**
   - Add a plugin workflow that runs pytest, compileall, and `hermes plugins doctor . --ci` against supported Python/Hermes versions.
   - CI must not require real phone credentials or touch a real `HERMES_HOME`.

4. **Contributor packaging**
   - A conventional `pyproject.toml` / import layout is desirable so tests run from a default `talaria-plugin` clone, but do not let a packaging refactor obscure the critical storage/routing diff. Prefer a later PR if it expands substantially.

5. **Protocol description**
   - A machine-readable plugin version/protocol/capabilities `describe` envelope remains recommended for OI #269-A, but it likely crosses into app work. Do not add an app contract change in this PR without Owen's approval.

---

# Verification gates before opening the PR

The baseline before changes was:

- Plugin pytest: **80 passed**
- `compileall`: passed
- `hermes plugins doctor . --ci`: passed with one `provides_tools` warning
- Talaria-27 Xcode 27 beta 5 `build-for-testing`: **TEST BUILD SUCCEEDED**

The PR must show:

1. All pre-existing 80 plugin tests still pass unmodified unless a test was genuinely pinning the defective behavior; explain any changed existing test.
2. All new storage, migration, cross-process, and multi-device tests pass.
3. `python -m compileall` passes.
4. `hermes plugins doctor . --ci` passes; ideally with the existing manifest warning removed.
5. A fresh temporary `HERMES_HOME` smoke test covers pair → targeted send → correct-device drain → ack → empty re-drain → unpair.
6. No test or command touches `~/.hermes/talaria`, the live plugin checkout, a live gateway, or a real device.
7. `git diff --check` passes.
8. Secret/artifact scan is clean.

Existing package-layout caveat: the suite currently passes when the checkout is exposed under package name `talaria`. If packaging is not addressed, use an isolated temporary parent with a `talaria` symlink and state that accurately in the PR; do not misreport an import-layout collection failure as a code failure.

---

# PR instructions

Use a body file, not an inline `--body` string containing backticks.

Suggested PR title:

```text
fix: make Talaria persistence transactional and device-targeted
```

The PR body must include:

- The two reproduced pre-fix failures.
- The selected schema and migration strategy.
- Exact multi-device delivery semantics.
- RED results before implementation and GREEN results after.
- Full test counts and plugin-doctor output.
- Confirmation that no live host was modified or restarted.
- Rollback/recovery behavior for the migration.
- A prominent line: **DO NOT MERGE — awaiting Owen's review and explicit approval.**

Push the branch, open the PR, report its URL and current checks to Owen, and stop. Do not merge it, even if every check is green.
