#!/usr/bin/env python3
"""
Talaria relay DB cleanup — delete stale users and all dependent rows.

Issue #9: https://github.com/ChronoRixun/Talaria/issues/9

Idempotent and safe to re-run. If the stale users are already gone, the
script reports "nothing to clean" and exits 0.

Usage:
    python scripts/cleanup-stale-users.py [--dry-run] [--db PATH]

Flags:
    --dry-run    Count and report what WOULD be deleted, then exit without mutating.
    --db PATH    Override DB path (default: ../relay/hermes_mobile.db relative to this script)

Run with the relay STOPPED to avoid write contention:
    nssm stop HermesMobileRelay   # or: net stop HermesMobileRelay
    python scripts/cleanup-stale-users.py
    nssm start HermesMobileRelay
"""

from __future__ import annotations

import argparse
import os
import shutil
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

# ── Constants ────────────────────────────────────────────────────────────────

STALE_USER_IDS = [
    "15deb25d-6204-4e3b-a24f-8fcc96ac28ea",  # OJAMD — revoked 2026-06-24
    "2498777c-3bca-4bc1-98ee-b72455495bf8",  # OJAMD — never connected
]
LIVE_USER_ID = "707547ee-8894-4014-897f-062c68779ab4"  # OJAMD — live, active

# Tables with a direct user_id column, in FK-safe delete order (children first).
# Each entry: (table_name, has_user_id=True)
USER_ID_TABLES = [
    "inbox_items",          # FK → users, devices
    "voice_sessions",       # FK → users, hermes_hosts
    "phone_pairing_codes",  # FK → users, hermes_hosts, devices
    "host_enrollment_invites",  # FK → users, hermes_hosts
    "message_jobs",         # FK → users, conversations, messages, hermes_hosts
    "messages",             # FK → conversations, users
    "conversations",        # FK → users
    "auth_sessions",        # FK → users, devices
    "hermes_hosts",         # FK → users (UNIQUE user_id)
    "devices",              # FK → users
]

# Tables that reference stale rows indirectly via subquery.
# Each entry: (table_name, child_column, parent_table, parent_column)
CASCADE_TABLES = [
    ("inbox_actions", "inbox_item_id", "inbox_items", "id"),
    ("voice_turns", "voice_session_id", "voice_sessions", "id"),
    ("push_registrations", "device_id", "devices", "id"),
]

# Tables cleaned via non-FK string match.
# Each entry: (table_name, match_column)
STRING_MATCH_TABLES = [
    ("audit_log", "actor_id"),
    ("pairing_invites", "redeemed_user_id"),
]

# ── Helpers ──────────────────────────────────────────────────────────────────


def count_user_rows(cur: sqlite3.Cursor, table: str, user_ids: tuple[str, ...]) -> int:
    placeholders = ",".join("?" * len(user_ids))
    return cur.execute(
        f"SELECT COUNT(*) FROM {table} WHERE user_id IN ({placeholders})", user_ids
    ).fetchone()[0]


def count_cascade_rows(
    cur: sqlite3.Cursor, table: str, col: str, parent: str, pcol: str, user_ids: tuple[str, ...]
) -> int:
    placeholders = ",".join("?" * len(user_ids))
    return cur.execute(
        f"SELECT COUNT(*) FROM {table} WHERE {col} IN "
        f"(SELECT {pcol} FROM {parent} WHERE user_id IN ({placeholders}))",
        user_ids,
    ).fetchone()[0]


def count_string_match(cur: sqlite3.Cursor, table: str, col: str, user_ids: tuple[str, ...]) -> int:
    placeholders = ",".join("?" * len(user_ids))
    return cur.execute(
        f"SELECT COUNT(*) FROM {table} WHERE {col} IN ({placeholders})", user_ids
    ).fetchone()[0]


def count_live_user_rows(cur: sqlite3.Cursor, table: str) -> int:
    return cur.execute(
        f"SELECT COUNT(*) FROM {table} WHERE user_id = ?", (LIVE_USER_ID,)
    ).fetchone()[0]


# ── Main ─────────────────────────────────────────────────────────────────────


def main() -> int:
    parser = argparse.ArgumentParser(description="Clean up stale Talaria relay users.")
    parser.add_argument("--dry-run", action="store_true", help="Report only; do not mutate.")
    parser.add_argument(
        "--db",
        type=str,
        default=None,
        help="Path to hermes_mobile.db (default: ../relay/hermes_mobile.db)",
    )
    args = parser.parse_args()

    # Resolve DB path
    if args.db:
        db_path = Path(args.db)
    else:
        db_path = Path(__file__).resolve().parent.parent / "relay" / "hermes_mobile.db"

    if not db_path.exists():
        print(f"ERROR: DB not found at {db_path}", file=sys.stderr)
        return 1

    stale = tuple(STALE_USER_IDS)
    print(f"DB: {db_path}")
    print(f"Stale users: {len(stale)}")
    for uid in stale:
        print(f"  - {uid}")
    print(f"Live user (protected): {LIVE_USER_ID}")
    print()

    # ── Open read-only first for assessment ───────────────────────────────
    ro_uri = f"file:{db_path}?mode=ro"
    ro = sqlite3.connect(ro_uri, uri=True)
    ro.row_factory = sqlite3.Row
    ro_cur = ro.cursor()

    # 1. Verify live user exists and is healthy
    live_row = ro_cur.execute(
        "SELECT id, display_name FROM users WHERE id = ?", (LIVE_USER_ID,)
    ).fetchone()
    if not live_row:
        print(f"ABORT: Live user {LIVE_USER_ID} not found in users table!", file=sys.stderr)
        ro.close()
        return 1

    live_sessions = ro_cur.execute(
        "SELECT COUNT(*) FROM auth_sessions WHERE user_id = ? AND revoked_at IS NULL",
        (LIVE_USER_ID,),
    ).fetchone()[0]
    live_devices = ro_cur.execute(
        "SELECT COUNT(*) FROM devices WHERE user_id = ? AND is_active = 1", (LIVE_USER_ID,)
    ).fetchone()[0]
    live_host = ro_cur.execute(
        "SELECT COUNT(*) FROM hermes_hosts WHERE user_id = ? AND revoked_at IS NULL",
        (LIVE_USER_ID,),
    ).fetchone()[0]

    print(f"Live user verification:")
    print(f"  display_name : {live_row['display_name']}")
    print(f"  active sessions: {live_sessions}")
    print(f"  active devices : {live_devices}")
    print(f"  active hosts   : {live_host}")
    if live_sessions == 0 and live_devices == 0 and live_host == 0:
        print(
            "WARNING: Live user has no active sessions, devices, or hosts.\n"
            "Proceeding anyway (this user may be legitimately dormant).",
            file=sys.stderr,
        )
    print()

    # 2. Check if stale users still exist
    existing_stale = []
    for uid in stale:
        row = ro_cur.execute("SELECT id FROM users WHERE id = ?", (uid,)).fetchone()
        if row:
            existing_stale.append(uid)

    if not existing_stale:
        print("Nothing to clean — stale users already removed. ✅")
        ro.close()
        return 0

    stale_existing = tuple(existing_stale)

    # 3. Count all rows that will be deleted
    print("=" * 60)
    print("ROWS TO BE DELETED")
    print("=" * 60)

    total = 0
    delete_plan: list[tuple[str, int]] = []

    for table in USER_ID_TABLES:
        n = count_user_rows(ro_cur, table, stale_existing)
        if n > 0:
            delete_plan.append((table, n))
            total += n
            print(f"  {table:30s} {n:5d}")

    for table, col, parent, pcol in CASCADE_TABLES:
        n = count_cascade_rows(ro_cur, table, col, parent, pcol, stale_existing)
        if n > 0:
            delete_plan.append((f"{table} (via {parent})", n))
            total += n
            print(f"  {table:30s} {n:5d}  (via {parent}.{pcol})")

    for table, col in STRING_MATCH_TABLES:
        n = count_string_match(ro_cur, table, col, stale_existing)
        if n > 0:
            delete_plan.append((f"{table} (by {col})", n))
            total += n
            print(f"  {table:30s} {n:5d}  (by {col})")

    # users table itself
    n_users = len(stale_existing)
    delete_plan.append(("users", n_users))
    total += n_users
    print(f"  {'users':30s} {n_users:5d}")

    print(f"  {'─' * 36}")
    print(f"  {'TOTAL':30s} {total:5d}")
    print()

    # Capture live user row counts BEFORE delete for post-verification
    live_before: dict[str, int] = {}
    for table in USER_ID_TABLES:
        live_before[table] = count_live_user_rows(ro_cur, table)

    ro.close()

    if args.dry_run:
        print("DRY RUN — no changes made. Re-run without --dry-run to execute.")
        return 0

    # ── Mutation phase ────────────────────────────────────────────────────
    # 4. Back up the DB
    timestamp = datetime.now().strftime("%Y%m%dT%H%M%S")
    backup_path = db_path.parent / f"hermes_mobile.db.pre-cleanup-{timestamp}.bak"
    print(f"Backing up DB → {backup_path}")
    shutil.copy2(str(db_path), str(backup_path))

    # Also back up WAL and SHM if they exist (SQLite WAL mode)
    for ext in ("-wal", "-shm"):
        sidecar = Path(str(db_path) + ext)
        if sidecar.exists():
            shutil.copy2(str(sidecar), str(backup_path) + ext)

    # 5. Open read-write and execute deletes
    con = sqlite3.connect(str(db_path))
    con.execute("PRAGMA foreign_keys = OFF")  # explicit; we manage order ourselves
    cur = con.cursor()

    deleted: dict[str, int] = {}
    placeholders = ",".join("?" * len(stale_existing))

    try:
        # Cascade tables first (children of children)
        for table, col, parent, pcol in CASCADE_TABLES:
            sql = (
                f"DELETE FROM {table} WHERE {col} IN "
                f"(SELECT {pcol} FROM {parent} WHERE user_id IN ({placeholders}))"
            )
            n = cur.execute(sql, stale_existing).rowcount
            if n:
                deleted[f"{table} (via {parent})"] = n

        # user_id-keyed tables in FK-safe order
        for table in USER_ID_TABLES:
            sql = f"DELETE FROM {table} WHERE user_id IN ({placeholders})"
            n = cur.execute(sql, stale_existing).rowcount
            if n:
                deleted[table] = n

        # String-match tables
        for table, col in STRING_MATCH_TABLES:
            sql = f"DELETE FROM {table} WHERE {col} IN ({placeholders})"
            n = cur.execute(sql, stale_existing).rowcount
            if n:
                deleted[f"{table} (by {col})"] = n

        # Finally, the users themselves
        n = cur.execute(
            f"DELETE FROM users WHERE id IN ({placeholders})", stale_existing
        ).rowcount
        deleted["users"] = n

        con.commit()
    except Exception as e:
        con.rollback()
        print(f"ERROR during delete: {e}", file=sys.stderr)
        print(f"DB unchanged. Backup at: {backup_path}", file=sys.stderr)
        con.close()
        return 1

    # 6. Post-delete verification — live user rows must be intact
    print()
    print("=" * 60)
    print("POST-DELETE VERIFICATION")
    print("=" * 60)

    all_ok = True
    for table in USER_ID_TABLES:
        after = count_live_user_rows(cur, table)
        before = live_before[table]
        ok = after == before
        status = "✅" if ok else "❌ MISMATCH"
        if not ok:
            all_ok = False
        print(f"  {table:30s} before={before:4d}  after={after:4d}  {status}")

    # Verify stale users are gone
    remaining_stale = cur.execute(
        f"SELECT COUNT(*) FROM users WHERE id IN ({placeholders})", stale_existing
    ).fetchone()[0]
    if remaining_stale > 0:
        print(f"\n❌ {remaining_stale} stale users still present!")
        all_ok = False
    else:
        print(f"\n✅ All stale users removed.")

    con.close()

    # 7. Final report
    print()
    print("=" * 60)
    print("DELETE SUMMARY")
    print("=" * 60)
    actual_total = 0
    for label, n in deleted.items():
        print(f"  {label:40s} {n:5d}")
        actual_total += n
    print(f"  {'─' * 46}")
    print(f"  {'TOTAL DELETED':40s} {actual_total:5d}")
    print()
    print(f"Backup: {backup_path}")
    print(f"Verification: {'PASSED ✅' if all_ok else 'FAILED ❌ — restore from backup'}")
    print()

    if not all_ok:
        print("VERIFICATION FAILED. Restore the backup before restarting the relay:", file=sys.stderr)
        print(f"  copy /Y \"{backup_path}\" \"{db_path}\"", file=sys.stderr)
        return 1

    print("Done. Restart the relay:")
    print("  nssm start HermesMobileRelay")
    return 0


if __name__ == "__main__":
    sys.exit(main())
