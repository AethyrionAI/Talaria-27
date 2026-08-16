# Talaria-Plugin Rework (#351) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework talaria-plugin PRs #1/#2 (GitHub numbers) against tracker #351's pre-registered bars 351-A..L, replacing four design decisions in place: migration-in-connect → one-shot fail-soft initialize; no lifecycle re-homing → re-target + claim-release on rotation; sync SQLite on the event loop → `asyncio.to_thread` boundary with a read-first `pending()`; rotating-device-id addressing → id-or-install_id resolution.

**Architecture:** `database.py` owns the single path seam (`database_path()`), a hygienic low-level `_open()`, and a process-cached `initialize()` that quarantines bad legacy input instead of raising. `store.py`/`outbox.py` keep their public surfaces but call `connect()` with no args. `envelope.py` gets a dispatch catch-all and `to_thread` around every storage call. `platform_adapter.py` never raises. PR #2 keeps the package move and deletes its pip half.

**Tech Stack:** Python 3.11+, stdlib `sqlite3` (WAL), pytest 9.1.1 + pytest-asyncio (`asyncio_mode = auto`), Hermes plugin API (`register(ctx)`), `hermes_constants.get_hermes_home` / `secure_parent_dir`.

## Global Constraints

- Workspace: `$SCRATCH/pr1-tree` (git worktree, branch `pr1` = origin `fix/transactional-storage-device-routing`), where `SCRATCH=/private/tmp/claude-501/-Users-owenjones-Documents-Claude-Talaria-27/51480933-4816-4761-a740-21e412df5e48/scratchpad`. PR2 work in `$SCRATCH/pr2-tree` (branch `pr2` = origin `chore/package-layout-installability`).
- Test invocation at PR1 layout (README-documented symlink-parent shape): `mkdir -p $SCRATCH/testparent && ln -sfn $SCRATCH/pr1-tree $SCRATCH/testparent/talaria; cd $SCRATCH/testparent && ~/.hermes/hermes-agent/venv/bin/pytest talaria/tests/ -q` (focused runs: `talaria/tests/test_x.py::test_name -q`).
- ⛔ NEVER touch `~/.hermes/plugins/talaria` (live install, stays on `main`) or `~/.hermes/talaria/` (canonical state + quarantine files). 351-L verifies both untouched after every suite run.
- No Hermes-core changes. No live deploy. No gateway restart. Neither PR merges.
- Tokens stay SHA-256-hashed at rest; devices deactivate-never-delete (#144); migration reads legacy JSON, never edits its bytes (quarantine = rename only).
- Every commit: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer.
- Baseline suite count 112 (PR1) — 351-L requires the final count stated and MOVED.

---

### Task 1: Path seam + connection hygiene (`database.py` bottom half) — bars 351-A(hygiene), sub-cap index/reuse

**Files:**
- Modify: `database.py` (replace `connect()`, delete `_retry_locked`, add `database_path()`, `_open()`, `try_connect_readonly()`; add token index to `_SCHEMA_STATEMENTS`)
- Modify: `store.py`, `outbox.py` (path plumbing only)
- Modify: all 8 test files' `_redirect` helpers → single seam
- Test: `tests/test_database_hygiene.py` (new)

**Interfaces:**
- Produces: `database.database_path() -> Path` (THE test seam — tests monkeypatch this one function), `database._open(path: Path) -> sqlite3.Connection` (internal), `database.connect(path: Path | None = None) -> sqlite3.Connection` (initializes lazily via Task 2's `initialize`; until Task 2 lands keep the old schema/migration block called from `connect` — this task only reworks path + hygiene), `database.try_connect_readonly(path: Path | None = None) -> sqlite3.Connection | None`.
- Consumes: `hermes_constants.secure_parent_dir(path: Path) -> None` (chmods parent 0700 with the root guard; does NOT mkdir — call `mkdir` first).

- [ ] **Step 1: Write the failing tests**

```python
# tests/test_database_hygiene.py
import os
import sqlite3
import stat

import pytest

from talaria import database


def _redirect(monkeypatch, tmp_path):
    monkeypatch.setattr(database, "database_path", lambda: tmp_path / "talaria.db")


def test_database_file_is_0600_from_creation(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    connection = database.connect()
    connection.close()
    mode = stat.S_IMODE(os.stat(tmp_path / "talaria.db").st_mode)
    assert mode == 0o600


def test_failed_open_closes_the_connection_and_leaves_0600(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    db = tmp_path / "talaria.db"
    db.write_bytes(b"definitely not a sqlite file")
    os.chmod(db, 0o600)
    closed = []
    real_connect = sqlite3.connect

    def recording_connect(*args, **kwargs):
        connection = real_connect(*args, **kwargs)
        original_close = connection.close
        def close():
            closed.append(True)
            original_close()
        connection.close = close
        return connection

    monkeypatch.setattr(database.sqlite3, "connect", recording_connect)
    with pytest.raises(sqlite3.DatabaseError):
        database._open(database.database_path())
    assert closed == [True]
    assert stat.S_IMODE(os.stat(db).st_mode) == 0o600


def test_token_index_exists(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    connection = database.connect()
    try:
        names = {r[0] for r in connection.execute(
            "SELECT name FROM sqlite_master WHERE type = 'index'").fetchall()}
    finally:
        connection.close()
    assert "devices_token_idx" in names
```

- [ ] **Step 2: Run to verify failure** — `cd $SCRATCH/testparent && ~/.hermes/hermes-agent/venv/bin/pytest talaria/tests/test_database_hygiene.py -q`. Expected: FAIL (`database.database_path` doesn't exist).

- [ ] **Step 3: Implement.** In `database.py`: add `import logging`, `logger = logging.getLogger("talaria")`, `from hermes_constants import get_hermes_home, secure_parent_dir`. Add:

```python
def database_path() -> Path:
    """The single durable-state location; tests monkeypatch THIS."""
    return Path(get_hermes_home()) / "talaria" / "talaria.db"


def _open(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    secure_parent_dir(path)
    # Pre-create at 0600 so token hashes are never observable at a wider
    # mode; sqlite would otherwise create the file at umask default.
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o600)
    os.close(fd)
    connection = sqlite3.connect(
        path, timeout=_BUSY_TIMEOUT_MS / 1000, isolation_level=None
    )
    try:
        connection.row_factory = sqlite3.Row
        connection.execute(f"PRAGMA busy_timeout = {_BUSY_TIMEOUT_MS}")
        connection.execute("PRAGMA foreign_keys = ON")
        journal_mode = connection.execute("PRAGMA journal_mode").fetchone()[0]
        if str(journal_mode).lower() != "wal":
            connection.execute("PRAGMA journal_mode = WAL")
        connection.execute("PRAGMA synchronous = FULL")
    except Exception:
        connection.close()
        raise
    for suffix in ("-wal", "-shm"):
        sidecar = Path(f"{path}{suffix}")
        try:
            if sidecar.exists():
                os.chmod(sidecar, 0o600)
        except OSError:
            pass
    return connection


def try_connect_readonly(path: Path | None = None) -> sqlite3.Connection | None:
    """Open read-only WITHOUT creating or migrating; None when absent/unreadable."""
    resolved = path if path is not None else database_path()
    if not resolved.exists():
        return None
    try:
        connection = sqlite3.connect(
            f"file:{resolved}?mode=ro", uri=True,
            timeout=_BUSY_TIMEOUT_MS / 1000, isolation_level=None,
        )
    except sqlite3.Error:
        return None
    connection.row_factory = sqlite3.Row
    return connection
```

Rewrite `connect()` to `def connect(path: Path | None = None)`: resolve default via `database_path()`, call `_open()`, then (until Task 2) run the existing schema/migration block unchanged inside the same try/except-rollback-close-raise. Delete `_retry_locked` and both its call sites (bare `connection.execute("BEGIN IMMEDIATE")` / bare WAL pragma — busy_timeout owns the wait now). Delete the old chmod-at-end block (pre-creation replaces it). Add `devices_token_idx` to `_SCHEMA_STATEMENTS`:

```python
    """
    CREATE INDEX IF NOT EXISTS devices_token_idx
    ON devices(token_sha256)
    """,
```

In `store.py` and `outbox.py`: delete `_store_path`/`_outbox_path`/`_database_path`; every `connect(_database_path())` becomes `connect()` (`from .database import connect` stays). In each test file, replace the `_redirect` body (and `test_platform_adapter.py` / `test_smoke.py` inline pairs) with the single-seam form: `monkeypatch.setattr(database, "database_path", lambda: tmp_path / "talaria.db")` (import `database` in each; migration tests keep writing `devices.json`/`outbox.json` into the same `tmp_path` — the migration derives those names from the DB path). In `tests/test_storage_concurrency.py`'s `_redirect` do the same; its two cross-process tests already use `HERMES_HOME` env and keep working. `tests/test_database_migration.py::test_migration_is_idempotent_when_database_exists_without_marker` loses the `migrate_legacy=False` kwarg: build the pre-seeded DB with plain `sqlite3.connect` + the devices-table DDL copied from `_SCHEMA_STATEMENTS` + a manual INSERT of the first legacy device, close, then assert `store.devices()` imports without duplicating (the OR-IGNORE + read-back path).

- [ ] **Step 4: Run the full suite** — same command, whole `talaria/tests/`. Expected: PASS, count ≥ 112+3.
- [ ] **Step 5: Commit** — `git -C $SCRATCH/pr1-tree add -A && git commit -m "rework(#351): single path seam, hygienic connect, token index; drop _retry_locked"` (+trailer).

---

### Task 2: One-shot fail-soft `initialize()` — bars 351-A, 351-C

**Files:**
- Modify: `database.py` (add `initialize()`, `_INIT_LOCK`/`_INITIALIZED`, `_import_file()`, `_quarantine_file()`, `_quarantine_database()`; `_migrate_legacy_json` restructured; `connect()` stops migrating)
- Modify: `__init__.py` (`register` calls `database.initialize()` best-effort)
- Modify: `envelope.py` (dispatch catch-all; `verify` storage guard)
- Test: `tests/test_database_migration.py` (flip the hard-fail pins), `tests/test_envelope.py` (catch-all)

**Interfaces:**
- Produces: `database.initialize(path: Path | None = None) -> None` — idempotent, process-cached (`_INITIALIZED: set[str]` under `_INIT_LOCK`), never raises for bad LEGACY input (quarantines `<file>.rejected` + `logger.warning`), quarantines a corrupt DB to `talaria.db.corrupt-<utcnow YYYYmmddHHMMSS>` and recreates. `connect()` = lazy `initialize()` + `_open()`.
- Marker rule (351-C): marker row written ONLY when at least one legacy file existed at migration time; with neither file present, no marker — later-appearing JSON imports at the next `initialize()` (i.e. next process, or next test after clearing `database._INITIALIZED`).
- Per-file atomicity: each legacy file imports inside `SAVEPOINT legacy_file`; a validation failure rolls back ONLY that file's rows, quarantines that file, and the other file still imports.

- [ ] **Step 1: Write the failing tests** (in `tests/test_database_migration.py` — REPLACE the four hard-fail pins):

```python
def test_corrupt_legacy_input_quarantines_and_keeps_serving(monkeypatch, tmp_path, caplog):
    _redirect(monkeypatch, tmp_path)
    corrupt = "{ definitely not valid json"
    (tmp_path / "devices.json").write_text(corrupt, encoding="utf-8")

    with caplog.at_level("WARNING", logger="talaria"):
        assert store.devices() == []

    rejected = tmp_path / "devices.json.rejected"
    assert rejected.read_text(encoding="utf-8") == corrupt
    assert not (tmp_path / "devices.json").exists()
    assert any("quarantined" in r.message for r in caplog.records)


@pytest.mark.parametrize(("field", "value"), [
    ("token_sha256", "not-a-digest"), ("active", "false"),
    ("created", "not-a-time"), ("name", 7),
])
def test_semantically_invalid_device_file_quarantines_whole_file(monkeypatch, tmp_path, field, value):
    _redirect(monkeypatch, tmp_path)
    devices, _ = _write_legacy(tmp_path)
    devices["devices"][0][field] = value
    (tmp_path / "devices.json").write_text(json.dumps(devices), encoding="utf-8")

    assert store.devices() == []          # device file quarantined...
    assert (tmp_path / "devices.json.rejected").exists()
    assert [i["id"] for i in outbox.all_pending_for_diagnostics()] == ["pending-1"]  # ...outbox still imported


def test_invalid_outbox_file_does_not_block_device_import(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    legacy_devices, _ = _write_legacy(tmp_path)
    (tmp_path / "outbox.json").write_text('{"items": [{"id": 1}]}', encoding="utf-8")

    migrated = store.devices()
    assert {d["id"] for d in migrated} == {d["id"] for d in legacy_devices["devices"]}
    assert (tmp_path / "outbox.json.rejected").exists()


def test_fresh_install_writes_no_marker_and_imports_late_json(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    assert store.devices() == []          # fresh: no legacy files, DB created

    legacy_devices, _ = _write_legacy(tmp_path)
    # Simulate the next process: initialize() is cached per-process.
    database._INITIALIZED.clear()
    assert {d["id"] for d in store.devices()} == {
        d["id"] for d in legacy_devices["devices"]
    }


def test_corrupt_database_is_quarantined_and_rebuilt_from_json(monkeypatch, tmp_path, caplog):
    _redirect(monkeypatch, tmp_path)
    legacy_devices, _ = _write_legacy(tmp_path)
    (tmp_path / "talaria.db").write_bytes(b"garbage that is not sqlite")

    with caplog.at_level("WARNING", logger="talaria"):
        migrated = store.devices()
    assert {d["id"] for d in migrated} == {d["id"] for d in legacy_devices["devices"]}
    assert list(tmp_path.glob("talaria.db.corrupt-*"))
```

And in `tests/test_envelope.py`:

```python
async def test_dispatch_returns_clean_error_when_storage_raises(env, monkeypatch):
    service, _ = env
    paired = await service.dispatch({"type": "pair", "auth": API_KEY, "install_id": "i-1", "device_name": "p"})
    def boom(*a, **k):
        raise sqlite3.OperationalError("database is locked")
    monkeypatch.setattr(outbox, "pending", boom)
    result = await service.dispatch({
        "type": "drain", "auth": paired["device_token"],
        "device_id": paired["device_id"], "wait": False,
    })
    assert result["code"] == "storage_error"
```

(add `import sqlite3` to the test module).

- [ ] **Step 2: Run to verify failure** — migration tests fail (current code raises `MigrationError`); envelope test fails (raise propagates).

- [ ] **Step 3: Implement.** `database.py`:

```python
_INIT_LOCK = threading.Lock()
_INITIALIZED: set[str] = set()   # str(database_path) initialized this process


def _quarantine_file(path: Path, exc: Exception) -> None:
    rejected = path.with_name(path.name + ".rejected")
    try:
        if not rejected.exists():
            path.rename(rejected)
    except OSError:
        pass
    logger.warning(
        "talaria: legacy %s failed migration and was quarantined to %s "
        "(bytes preserved; see README 'Migration recovery'): %s",
        path.name, rejected.name, exc,
    )


def _quarantine_database(path: Path, exc: Exception) -> None:
    stamp = datetime.utcnow().strftime("%Y%m%d%H%M%S")
    for candidate in (path, Path(f"{path}-wal"), Path(f"{path}-shm")):
        try:
            if candidate.exists():
                candidate.rename(candidate.with_name(f"{candidate.name}.corrupt-{stamp}"))
        except OSError:
            pass
    logger.warning(
        "talaria: unreadable database quarantined to %s.corrupt-%s and recreated: %s",
        path.name, stamp, exc,
    )


def _import_file(connection, path: Path, collection_key: str, migrate_fn) -> bool:
    """One legacy file, atomically: validation failure rolls back ONLY this
    file's rows, quarantines the file, and migration continues."""
    if not path.exists():
        return False
    connection.execute("SAVEPOINT legacy_file")
    try:
        rows = _legacy_rows(path, collection_key)
        migrate_fn(connection, path, rows)
        connection.execute("RELEASE SAVEPOINT legacy_file")
    except MigrationError as exc:
        connection.execute("ROLLBACK TO SAVEPOINT legacy_file")
        connection.execute("RELEASE SAVEPOINT legacy_file")
        _quarantine_file(path, exc)
    return True


def initialize(path: Path | None = None) -> None:
    """One-shot per process: schema + legacy import. Fail-soft on bad
    legacy input; raises only if a database cannot be created at all."""
    resolved = path if path is not None else database_path()
    key = str(resolved)
    with _INIT_LOCK:
        if key in _INITIALIZED:
            return
        try:
            connection = _open(resolved)
        except sqlite3.Error as exc:
            _quarantine_database(resolved, exc)
            connection = _open(resolved)
        try:
            connection.execute("BEGIN IMMEDIATE")
            for statement in _SCHEMA_STATEMENTS:
                connection.execute(statement)
            _migrate_legacy_json(connection, resolved)
            connection.commit()
        except Exception:
            connection.rollback()
            connection.close()
            raise
        connection.close()
        _INITIALIZED.add(key)


def connect(path: Path | None = None) -> sqlite3.Connection:
    resolved = path if path is not None else database_path()
    if str(resolved) not in _INITIALIZED:
        initialize(resolved)
    return _open(resolved)
```

`_migrate_legacy_json` restructured (marker only when a file existed; count checks deleted — the per-row read-back is the completeness guarantee):

```python
def _migrate_legacy_json(connection: sqlite3.Connection, database_path: Path) -> None:
    marker = connection.execute(
        "SELECT value FROM schema_metadata WHERE key = ?", (_MIGRATION_KEY,)
    ).fetchone()
    if marker is not None:
        return
    devices_path = database_path.with_name("devices.json")
    outbox_path = database_path.with_name("outbox.json")
    saw_devices = _import_file(connection, devices_path, "devices", _migrate_devices)
    saw_outbox = _import_file(connection, outbox_path, "items", _migrate_outbox)
    if not saw_devices and not saw_outbox:
        return  # 351-C: nothing to migrate — no marker, so late JSON imports next initialize
    connection.execute(
        "INSERT INTO schema_metadata(key, value) VALUES (?, '1')", (_MIGRATION_KEY,)
    )
    connection.execute(
        "INSERT OR REPLACE INTO schema_metadata(key, value) VALUES ('schema_version', '1')"
    )
```

Add `import threading`. `__init__.py` `register()` gains, before tool/CLI registration:

```python
    try:
        from . import database
        database.initialize()
    except Exception as exc:  # register must never break gateway load
        print(f"[talaria] storage initialization deferred: {exc}")
```

`envelope.py`: wrap the handler call in `dispatch()`:

```python
        try:
            return await handler(payload)
        except Exception:
            _logger.exception("talaria: %s handler failed on a storage error", event_type)
            return {"error": "Internal storage failure", "code": "storage_error"}
```

(add `import logging`, `_logger = logging.getLogger("talaria")`, and update the module docstring's "nothing raises" paragraph to say the catch-all now enforces it). `verify()` wraps its `device_for_token` call in `try/except Exception: return False, "storage_error"` — fail closed, but cleanly.

- [ ] **Step 4: Full suite** — PASS; count moved (+5 new, some old pins replaced 1:1).
- [ ] **Step 5: Commit** — `rework(#351-A,C): one-shot fail-soft initialize; quarantine, don't brick`.

---

### Task 3: Migration targets `meta.chat_id` — bar 351-B

**Files:**
- Modify: `database.py` (`_migrate_outbox` resolution + read-back)
- Test: `tests/test_database_migration.py`

**Interfaces:**
- Produces: migrated rows resolve, uniformly per row: `meta.chat_id` names an imported ACTIVE device → (`target_device`, that id); else exactly one active imported device → (`target_device`, it); else (`legacy_any`, NULL). Devices import before outbox (already the call order), same transaction.

- [ ] **Step 1: Failing test (the reproduced disclosure, RED→GREEN):**

```python
def test_migrated_row_with_chat_id_targets_that_device_only(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    devices = {"devices": [
        {"id": "dev-a", "token_sha256": "a" * 64, "install_id": "ia",
         "name": "phone", "created": "2026-08-01T01:02:03+00:00",
         "active": True, "last_seen": None},
        {"id": "dev-b", "token_sha256": "b" * 64, "install_id": "ib",
         "name": "ipad", "created": "2026-08-01T01:02:03+00:00",
         "active": True, "last_seen": None},
    ]}
    items = {"items": [{
        "id": "secret-for-a", "kind": "message", "text": "private answer",
        "created_at": "2026-08-04T01:02:03+00:00",
        "meta": {"chat_id": "dev-a"}, "delivered_at": None, "active": True,
    }]}
    (tmp_path / "devices.json").write_text(json.dumps(devices), encoding="utf-8")
    (tmp_path / "outbox.json").write_text(json.dumps(items), encoding="utf-8")

    assert outbox.pending("dev-b") == []                      # B must never see it
    assert [i["id"] for i in outbox.pending("dev-a")] == ["secret-for-a"]
    assert outbox.mark_delivered(["secret-for-a"], device_id="dev-b") == []
    assert outbox.mark_delivered(["secret-for-a"], device_id="dev-a") == ["secret-for-a"]


def test_migrated_row_without_chat_id_targets_the_single_active_device(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    _write_legacy(tmp_path)   # one active device (phone-1) + one inactive
    connection = sqlite3.connect(tmp_path / "talaria.db")
    # force migration first
    assert len(store.devices()) == 2
    try:
        row = connection.execute(
            "SELECT target_device_id, delivery_scope FROM outbox_items WHERE id = 'pending-1'"
        ).fetchone()
    finally:
        connection.close()
    assert row == ("phone-1", "target_device")
```

(Adjust the existing `test_first_use_migrates...` assertion on `delivered-1`: with one active device it now reads `("phone-1", "target_device")` — update the expected tuple and note WHY in the test.)

- [ ] **Step 2: Run — both fail** (rows land `legacy_any`, `pending("dev-b")` claims them).
- [ ] **Step 3: Implement** in `_migrate_outbox`, replacing the fixed `NULL, 'legacy_any'` insert:

```python
        target_id = None
        chat_id = meta.get("chat_id")
        if isinstance(chat_id, str) and chat_id:
            row = connection.execute(
                "SELECT id FROM devices WHERE id = ? AND active = 1", (chat_id,)
            ).fetchone()
            if row is not None:
                target_id = chat_id
        if target_id is None:
            actives = connection.execute(
                "SELECT id FROM devices WHERE active = 1 LIMIT 2"
            ).fetchall()
            if len(actives) == 1:
                target_id = actives[0]["id"]
        scope = "target_device" if target_id is not None else "legacy_any"
```

INSERT uses `(?, ?)` for `target_device_id, delivery_scope` with `(target_id, scope)`; the read-back `expected` tuple becomes `(*values, target_id, scope, None)`.

- [ ] **Step 4: Full suite** — PASS.
- [ ] **Step 5: Commit** — `rework(#351-B): migration honors meta.chat_id — no cross-device drain`.

---

### Task 4: Lifecycle re-homing — bar 351-D

**Files:**
- Modify: `store.py` (`create_paired_device`, `deactivate`)
- Test: `tests/test_store_pairing.py`

**Interfaces:**
- Produces: inside `create_paired_device`'s existing transaction, order: deactivate old install rows → insert new device → re-target pending `target_device` rows from that install's deactivated ids to the new id → NULL out `claimed_by_device_id` on pending `legacy_any` rows held by ANY inactive device. `deactivate()` also runs the claim-release UPDATE in its transaction.

- [ ] **Step 1: Failing tests (both reproduced stranding cases):**

```python
def test_repair_rehomes_pending_targeted_rows(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    from talaria import outbox
    old_id, _ = store.create_paired_device("install-1", "phone")
    item = outbox.append("queued while offline", target_device_id=old_id)
    new_id, _ = store.create_paired_device("install-1", "phone")

    assert [r["id"] for r in outbox.pending(new_id)] == [item["id"]]
    assert outbox.mark_delivered([item["id"]], device_id=new_id) == [item["id"]]


def test_repair_releases_legacy_claims_of_inactive_devices(monkeypatch, tmp_path):
    _redirect(monkeypatch, tmp_path)
    from talaria import database, outbox
    old_id, _ = store.create_paired_device("install-1", "phone")
    connection = database.connect()
    try:
        connection.execute("BEGIN IMMEDIATE")
        connection.execute(
            "INSERT INTO outbox_items (id, kind, text, created_at, target_device_id,"
            " delivery_scope, claimed_by_device_id, delivered_at, active, meta_json)"
            " VALUES ('leg-1', 'message', 'legacy', '2026-08-01T00:00:00+00:00',"
            " NULL, 'legacy_any', NULL, NULL, 1, '{}')"
        )
        connection.commit()
    finally:
        connection.close()
    assert [r["id"] for r in outbox.pending(old_id)] == ["leg-1"]   # old device claims, never acks
    new_id, _ = store.create_paired_device("install-1", "phone")

    assert [r["id"] for r in outbox.pending(new_id)] == ["leg-1"]   # claim released, re-claimable
```

- [ ] **Step 2: Run — both fail** (rows invisible to `new_id`).
- [ ] **Step 3: Implement.** In `create_paired_device`, after the INSERT, before commit:

```python
        connection.execute(
            """
            UPDATE outbox_items SET target_device_id = ?
            WHERE delivery_scope = 'target_device' AND active = 1
              AND delivered_at IS NULL
              AND target_device_id IN (
                  SELECT id FROM devices WHERE install_id = ? AND active = 0
              )
            """,
            (device_id, install_id),
        )
        connection.execute(_RELEASE_STALE_CLAIMS)
```

with the shared statement at module top:

```python
_RELEASE_STALE_CLAIMS = """
    UPDATE outbox_items SET claimed_by_device_id = NULL
    WHERE delivery_scope = 'legacy_any' AND active = 1
      AND delivered_at IS NULL
      AND claimed_by_device_id IN (SELECT id FROM devices WHERE active = 0)
"""
```

and `deactivate()` executes `_RELEASE_STALE_CLAIMS` after its UPDATE, same transaction.

- [ ] **Step 4: Full suite** — PASS. **Step 5: Commit** — `rework(#351-D): re-pair re-homes targeted rows and releases stale claims`.

---

### Task 5: Stable addressing — bar 351-F

**Files:**
- Modify: `outbox.py` (`_insert_targeted` resolves id-or-install_id)
- Test: `tests/test_platform_adapter.py`

**Interfaces:**
- Produces: `_insert_targeted(connection, item, target)` resolves `target` to an active device id — exact id match preferred, else newest active row with `install_id == target` — and inserts with the RESOLVED id; raises `UnknownTargetError` when neither matches. `append`/`append_for_devices` signatures unchanged (`target_device_id` accepts either form).

- [ ] **Step 1: Failing test:**

```python
async def test_send_addressed_by_install_id_survives_repair(monkeypatch, tmp_path):
    from talaria import database
    monkeypatch.setattr(database, "database_path", lambda: tmp_path / "talaria.db")
    monkeypatch.setattr(platform_adapter.HUB, "wake", lambda device_id=None: None)
    adapter = object.__new__(TalariaPlatformAdapter)
    store.create_paired_device("stable-install", "phone")
    new_id, _ = store.create_paired_device("stable-install", "phone")  # rotation

    result = await adapter.send("stable-install", "hello after re-pair")
    assert result.success is True
    assert [r["id"] for r in outbox.pending(new_id)] == [result.message_id]
```

- [ ] **Step 2: Run — fails** (`UnknownTargetError: 'stable-install' is unknown or inactive` → `success is False`).
- [ ] **Step 3: Implement** — `_insert_targeted`'s guard SELECT becomes:

```python
    row = connection.execute(
        """
        SELECT id FROM devices
        WHERE active = 1 AND (id = ? OR install_id = ?)
        ORDER BY (id = ?) DESC, created DESC, rowid DESC
        LIMIT 1
        """,
        (target_device_id, target_device_id, target_device_id),
    ).fetchone()
    if row is None:
        raise UnknownTargetError(
            f"Talaria device '{target_device_id}' is unknown or inactive"
        )
    resolved = row["id"]
```

and the INSERT + `append`'s returned item use `resolved`. Update `append`'s docstring: the target may be a device id or an install_id.

- [ ] **Step 4: Full suite** — PASS. **Step 5: Commit** — `rework(#351-F): send targets resolve install_id — addressing survives rotation`.

---

### Task 6: Async boundary + read-first pending — bar 351-E

**Files:**
- Modify: `envelope.py` (`_touch`→async; `to_thread` around every storage call; `_device_authorized`→async), `platform_adapter.py` (`send` via `to_thread`), `outbox.py` (`pending` read-first), `store.py` (`touch_device` autocommit), `tools.py` (probe via `to_thread` — full change lands in Task 7)
- Test: `tests/test_envelope.py`

**Interfaces:**
- Produces: no storage call executes on the event loop from an async path; `pending()` takes `BEGIN IMMEDIATE` ONLY when an unclaimed `legacy_any` row exists (probe SELECT first — WAL readers never block on the write lock); `touch_device` is a bare autocommit UPDATE.

- [ ] **Step 1: Failing test (the loop-freeze repro made a pin):**

```python
async def test_drain_does_not_stall_the_event_loop_under_a_held_write_lock(env, monkeypatch, tmp_path):
    import threading
    from talaria import database

    service, _ = env
    paired = await service.dispatch({"type": "pair", "auth": API_KEY, "install_id": "i-1", "device_name": "p"})

    holder = database.connect()
    holder.execute("BEGIN IMMEDIATE")          # squat on the write lock
    release = threading.Event()
    def hold():
        release.wait(5.0)
        holder.rollback(); holder.close()
    threading.Thread(target=hold, daemon=True).start()

    gaps = []
    async def heartbeat():
        last = asyncio.get_running_loop().time()
        for _ in range(50):
            await asyncio.sleep(0.01)
            now = asyncio.get_running_loop().time()
            gaps.append(now - last); last = now
    beat = asyncio.create_task(heartbeat())
    result = await service.dispatch({
        "type": "drain", "auth": paired["device_token"],
        "device_id": paired["device_id"], "wait": False,
    })
    release.set()
    await beat
    assert result == {"items": [], "queries": []}   # a READ must not need the write lock
    assert max(gaps) < 0.25, f"event loop stalled {max(gaps):.3f}s"
```

- [ ] **Step 2: Run — fails today** (pending()'s unconditional `BEGIN IMMEDIATE` blocks the loop until the holder releases: heartbeat gap ≫ 0.25s).
- [ ] **Step 3: Implement.**
  - `outbox.pending` read-first:

```python
def pending(device_id: str) -> list[dict]:
    """Pending items for one authenticated active device. Read-only unless
    an unclaimed legacy row needs claiming (migration-era installs only)."""
    connection = connect()
    try:
        if connection.execute(
            "SELECT 1 FROM devices WHERE id = ? AND active = 1", (device_id,)
        ).fetchone() is None:
            return []
        claimable = connection.execute(
            """
            SELECT 1 FROM outbox_items
            WHERE active = 1 AND delivered_at IS NULL
              AND delivery_scope = 'legacy_any' AND claimed_by_device_id IS NULL
            LIMIT 1
            """
        ).fetchone()
        if claimable is not None:
            connection.execute("BEGIN IMMEDIATE")
            try:
                connection.execute(
                    """
                    UPDATE outbox_items SET claimed_by_device_id = ?
                    WHERE active = 1 AND delivered_at IS NULL
                      AND delivery_scope = 'legacy_any'
                      AND claimed_by_device_id IS NULL
                    """,
                    (device_id,),
                )
                connection.commit()
            except Exception:
                connection.rollback()
                raise
        rows = connection.execute(
            """
            SELECT * FROM outbox_items
            WHERE active = 1 AND delivered_at IS NULL
              AND (
                  (delivery_scope = 'target_device' AND target_device_id = ?)
                  OR
                  (delivery_scope = 'legacy_any' AND claimed_by_device_id = ?)
              )
            ORDER BY created_at, rowid
            """,
            (device_id, device_id),
        ).fetchall()
        return [_item_from_row(row) for row in rows]
    finally:
        connection.close()
```

  - `store.touch_device`: single autocommit UPDATE (no BEGIN, no rollback ladder).
  - `envelope.py`: `import asyncio`; `_device_authorized` becomes `async def` with `device = await asyncio.to_thread(self._store.device_for_token, auth)` (update its five call sites to `await`); `_touch` becomes `async def _touch` with `await asyncio.to_thread(self._store.touch_device, device_id)` under the existing throttle (hub.touch stays inline — it's in-memory); `_drain` uses `items = await asyncio.to_thread(self._outbox.pending, device_id)` (both sites); `_ack` wraps `mark_delivered`; `_pair` wraps `create_paired_device`; `_unpair` wraps `deactivate`.
  - `platform_adapter.send`: `item = await asyncio.to_thread(outbox.append, content, {"chat_id": chat_id}, target_device_id=chat_id)` (add `import asyncio`).

- [ ] **Step 4: Full suite** — PASS (the Task-2 catch-all test still passes: `to_thread` re-raises into the awaiting coroutine, where dispatch's except catches it).
- [ ] **Step 5: Commit** — `rework(#351-E): storage off the event loop; pending() reads before it writes`.

---

### Task 7: Send contract + tools probe + operator surface — bars 351-G, 351-I, 351-H

**Files:**
- Modify: `platform_adapter.py`, `tools.py`, `store.py` (add `active_devices_probe`), `admin.py`
- Test: `tests/test_platform_adapter.py`, `tests/test_tools.py`, `tests/test_admin_send.py`

**Interfaces:**
- Produces: `store.active_devices_probe() -> list[dict]` — read-only via `database.try_connect_readonly()`; returns `[]` when the DB is absent or unreadable; never creates, migrates, or raises. `adapter.send` never raises. `hermes talaria status` rows include name + install_id; `pair` prints the no-auto-rotate warning.

- [ ] **Step 1: Failing tests:**

```python
# tests/test_platform_adapter.py
async def test_send_never_raises_on_storage_failure(monkeypatch, tmp_path):
    from talaria import database
    monkeypatch.setattr(database, "database_path", lambda: tmp_path / "talaria.db")
    adapter = object.__new__(TalariaPlatformAdapter)
    def boom(*a, **k):
        raise sqlite3.OperationalError("database is locked")
    monkeypatch.setattr(outbox, "append", boom)
    result = await adapter.send("any-device", "content")
    assert result.success is False
    assert "database is locked" in result.error

# tests/test_tools.py
def test_probe_on_virgin_profile_creates_no_database(monkeypatch, tmp_path):
    from talaria import database, store
    monkeypatch.setattr(database, "database_path", lambda: tmp_path / "talaria.db")
    assert store.active_devices_probe() == []
    assert not (tmp_path / "talaria.db").exists()

# tests/test_admin_send.py
def test_status_prints_device_names(monkeypatch, tmp_path, capsys):
    _redirect(monkeypatch, tmp_path)
    store.create_paired_device("i-phone", "Owen's iPhone")
    admin.handle_cli(SimpleNamespace(talaria_cmd="status"))
    out = capsys.readouterr().out
    assert "Owen's iPhone" in out and "i-phone" in out
```

(`import sqlite3` where needed.)

- [ ] **Step 2: Run — all three fail.**
- [ ] **Step 3: Implement.**
  - `store.active_devices_probe()` (uses `database.try_connect_readonly()`; `except sqlite3.Error: return []` around the SELECT; `finally: connection.close()`).
  - `tools.phone_query`: replace `store.active_devices()` with `await asyncio.to_thread(store.active_devices_probe)`.
  - `platform_adapter.send`: replace the narrow except with

```python
        try:
            item = await asyncio.to_thread(
                outbox.append, content, {"chat_id": chat_id},
                target_device_id=chat_id,
            )
        except outbox.UnknownTargetError as exc:
            return SendResult(success=False, error=str(exc))
        except Exception as exc:
            logger.warning("talaria send failed on storage error: %s", exc)
            return SendResult(success=False, error=f"storage failure: {exc}")
```

  - `admin.py` status row: `name = device.get("name") or "—"`, `install = device.get("install_id") or "—"`, printed between state and created; pair output adds `print("CLI-paired records don't auto-rotate when the app re-pairs; unpair this id manually if the app later pairs itself.")`.

- [ ] **Step 4: Full suite** — PASS. **Step 5: Commit** — `rework(#351-G,H,I): send never raises; probe never creates; status names devices`.

---

### Task 8: PR1 gate + push — bar 351-L

- [ ] **Step 1:** Full suite from `$SCRATCH/testparent`; record the count (baseline 112 — must have MOVED; expect ≈ 112 + ~15 new − 0 deleted, some pins replaced 1:1). Three consecutive runs of `talaria/tests/test_storage_concurrency.py talaria/tests/test_database_migration.py -q` all green.
- [ ] **Step 2:** `~/.hermes/hermes-agent/venv/bin/python -m compileall -q $SCRATCH/pr1-tree`; ruff if available in the venv (`python -m ruff check .` — if absent, note it in the commit body rather than pip-installing anything); `cd $SCRATCH/pr1-tree && ~/.hermes/hermes-agent/venv/bin/hermes plugins doctor . --ci`.
- [ ] **Step 3:** Verify live state untouched: `git -C ~/.hermes/plugins/talaria status --short` empty + branch `main`; `ls ~/.hermes/talaria/talaria.db` → absent; quarantine files still present.
- [ ] **Step 4:** README (PR1 copy): migration section gains the quarantine semantics + a "Migration recovery" subsection (restore the `.rejected` file's name after repair, delete the `legacy_json_migration` row from `schema_metadata`, restart); "Authentication and delivery properties" line becomes "Wire pairing (the app's `pair` event) requires the gateway API key; `hermes talaria pair` is a local, credential-free fallback on the host itself."; document id-or-install_id addressing. Commit docs with the final code commit if not already amended.
- [ ] **Step 5:** `git -C $SCRATCH/pr1-tree push origin pr1:fix/transactional-storage-device-routing`. PR #1 stays open, DO-NOT-MERGE header intact.

---

### Task 9: PR2 — rebase, subtract pip half, pytest seam — bars 351-J, 351-K

**Files:**
- Branch `pr2` in `$SCRATCH/pr2-tree`
- Delete: `pyproject.toml`, `tests/test_packaging.py`
- Modify: `.github/workflows/ci.yml`, `pytest.ini`, `README.md`, `__init__.py`

- [ ] **Step 1: Rebase** — `git -C $SCRATCH/pr2-tree rebase pr1`. The ort strategy follows the 100%-similarity renames; verify content carried: `git -C $SCRATCH/pr2-tree diff pr1 --stat -- 'talaria/*.py'` must show ONLY renames (every `talaria/<mod>.py` byte-identical to pr1's root `<mod>.py`: `for f in admin database envelope outbox platform_adapter store tools transport; do cmp -s $SCRATCH/pr1-tree/$f.py $SCRATCH/pr2-tree/talaria/$f.py || echo "DRIFT $f"; done` → no output). If the rebase conflicts or drifts, abort and RECREATE: fresh branch from pr1, `git mv` the eight modules into `talaria/`, copy pr2's `talaria/__init__.py` + root shim + test import rewrites, verify with the same `cmp` loop.
- [ ] **Step 2: Subtract the pip half** — delete `pyproject.toml` and `tests/test_packaging.py`; in `ci.yml` remove the "Build and verify the pip entry-point distribution" step; in `README.md` remove the `talaria-hermes-plugin` distribution + entry-point paragraphs. In `.gitignore` keep the packaging block (harmless) or drop it with the pip half — drop it.
- [ ] **Step 3: pytest seam (351-J)** — `pytest.ini` becomes:

```ini
[pytest]
asyncio_mode = auto
pythonpath = .
```

- [ ] **Step 4: Root shim** — ~~replace the conditional with the unconditional relative import (the else-branch is unreachable under the production loader and binds the wrong package if ever reached)~~ **SUPERSEDED IN EXECUTION 2026-08-16: the unconditional form produced 129 collection errors — pytest 9.1 imports a rootdir `__init__.py` during collection with `__package__` empty, so the else-branch is load-bearing for the suite. The conditional STAYS, with an honest comment; its wrong-binding hazard is moot once the pip distribution is deleted (Step 2). The block below is the plan's original, wrong prescription — kept for the record:**

```python
"""Directory-plugin shim for the packaged Talaria implementation."""

from .talaria import register

__all__ = ["register"]
```

- [ ] **Step 5: CI + README corrections (351-K close-out)** — `ci.yml` test step runs BOTH invocations: `pytest tests/ -q` AND `python -m pytest tests/ -q`; compileall step returns to the whole workspace (`python -m compileall -q .`) so the root shim compiles. README: "place the checkout anywhere under the active profile's `plugins/` directory" → "place the checkout at `plugins/<name>/` or one category level deep (`plugins/<category>/<name>/`) — Hermes's plugin scanner caps discovery at two path segments."
- [ ] **Step 6: Gate** — from `$SCRATCH/pr2-tree`: `~/.hermes/hermes-agent/venv/bin/pytest tests/ -q` AND `~/.hermes/hermes-agent/venv/bin/python -m pytest tests/ -q` (same count, both green); compileall; `hermes plugins doctor . --ci`; live-state checks as Task 8 Step 3.
- [ ] **Step 7: Commit + push** — commit `rework(#351-J,K): drop the pip install shape; fix the pytest seam`; `git push --force-with-lease origin pr2:chore/package-layout-installability` (rebase makes force-with-lease necessary; the PR stays open).

---

## Self-Review (run after writing, before executing)

1. **Spec coverage:** 351-A→Tasks 1-2, B→3, C→2, D→4, E→6, F→5, G→7, H→7, I→7, J→9, K→9, L→8-9. Sub-cap extras folded: token index (T1), `_retry_locked` deletion (T1), COUNT-check deletion (T2), path-seam unification (T1), README truth lines (T8/T9). Not in scope (recorded in #351 as deliberately-not-bars): connection pooling, `delivery_scope` column removal, core-side chat_id consumers.
2. **Placeholder scan:** none — every step carries the code or the exact command.
3. **Type consistency:** `database_path()` (no args) is the one seam; `connect(path=None)`; `initialize(path=None)`; `_insert_targeted(connection, item, target)` returns resolved id; probe is `active_devices_probe()`.
