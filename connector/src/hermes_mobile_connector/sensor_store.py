"""Local SQLite store for context-first sensor data.

The connector stores all sensor data locally after the phone receives a live
ACK from the connector path. MCP tools query this store directly.
"""

from __future__ import annotations

import sqlite3
import threading
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4


WINDOWED_HEALTH_METRICS = {
    "steps",
    "active_calories",
    "distance_walking",
}

LOCATION_STALE_AFTER_SECONDS = 15 * 60
HEALTH_STALE_AFTER_SECONDS = 60 * 60


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def utcnow_iso() -> str:
    return utcnow().strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def parse_iso8601(value: str | None) -> datetime | None:
    if not value:
        return None
    normalized = value
    if normalized.endswith("Z"):
        normalized = normalized[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(normalized)
    except ValueError:
        return None


def freshness_metadata(
    *,
    recorded_at: str | None,
    updated_at: str | None,
    stale_after_seconds: int,
) -> dict:
    recorded = parse_iso8601(recorded_at)
    age_seconds = int((utcnow() - recorded).total_seconds()) if recorded else None
    return {
        "recordedAt": recorded_at,
        "updatedAt": updated_at,
        "ageSeconds": age_seconds,
        "stale": age_seconds is None or age_seconds > stale_after_seconds,
    }


def _same_value(left: float | None, right: float | None, tolerance: float = 0.0) -> bool:
    if left is None or right is None:
        return left is right
    return abs(left - right) <= tolerance


@dataclass(frozen=True)
class LocationReading:
    latitude: float
    longitude: float
    altitude: float | None = None
    accuracy: float | None = None
    address: str | None = None
    recorded_at: str | None = None


@dataclass(frozen=True)
class HealthSample:
    metric: str
    value: float
    unit: str
    start_at: str
    end_at: str | None = None
    source: str = "healthkit"

    @property
    def recorded_at(self) -> str:
        return self.end_at or self.start_at


@dataclass(frozen=True)
class CurrentLocation:
    latitude: float
    longitude: float
    altitude: float | None
    accuracy: float | None
    address: str | None
    recorded_at: str
    updated_at: str


@dataclass(frozen=True)
class LatestMetric:
    metric: str
    value: float
    unit: str
    recorded_at: str | None
    start_at: str | None
    end_at: str | None
    updated_at: str


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS location_history (
    id          TEXT PRIMARY KEY,
    latitude    REAL NOT NULL,
    longitude   REAL NOT NULL,
    altitude    REAL,
    accuracy    REAL,
    address     TEXT,
    recorded_at TEXT NOT NULL,
    created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE INDEX IF NOT EXISTS idx_location_history_time ON location_history(recorded_at DESC);

CREATE TABLE IF NOT EXISTS location_current (
    id          INTEGER PRIMARY KEY CHECK (id = 1),
    latitude    REAL NOT NULL,
    longitude   REAL NOT NULL,
    altitude    REAL,
    accuracy    REAL,
    address     TEXT,
    recorded_at TEXT NOT NULL,
    updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS health_samples (
    id         TEXT PRIMARY KEY,
    metric     TEXT NOT NULL,
    value      REAL NOT NULL,
    unit       TEXT NOT NULL,
    start_at   TEXT NOT NULL,
    end_at     TEXT,
    source     TEXT NOT NULL DEFAULT 'healthkit',
    created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE INDEX IF NOT EXISTS idx_health_samples_metric_time ON health_samples(metric, start_at DESC);

CREATE TABLE IF NOT EXISTS health_latest (
    metric      TEXT PRIMARY KEY,
    value       REAL NOT NULL,
    unit        TEXT NOT NULL,
    recorded_at TEXT,
    start_at    TEXT,
    end_at      TEXT,
    updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS health_daily (
    metric     TEXT NOT NULL,
    date       TEXT NOT NULL,
    sum_value  REAL,
    avg_value  REAL,
    min_value  REAL,
    max_value  REAL,
    count      INTEGER NOT NULL DEFAULT 0,
    unit       TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
    PRIMARY KEY (metric, date)
);
CREATE INDEX IF NOT EXISTS idx_health_daily_date ON health_daily(date DESC);
"""


class SensorStore:
    """SQLite-backed store for location and health sensor data."""

    def __init__(self, db_path: str | Path) -> None:
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()

        # Write connection — used exclusively under self._lock
        self._conn = self._open_connection(str(self.db_path))
        self._conn.executescript(SCHEMA_SQL)
        self._migrate_schema()

        # Read connection — separate connection for concurrent reads.
        # WAL mode allows readers and writers to operate concurrently
        # as long as they use different connections.
        self._read_conn = self._open_connection(str(self.db_path))

    @staticmethod
    def _open_connection(path: str) -> sqlite3.Connection:
        conn = sqlite3.connect(path, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("PRAGMA synchronous = NORMAL")
        conn.execute("PRAGMA foreign_keys = ON")
        conn.execute("PRAGMA busy_timeout = 5000")
        return conn

    def _commit(self) -> None:
        """Commit — call within a locked context."""
        self._conn.commit()

    def close(self) -> None:
        self._conn.close()
        self._read_conn.close()

    def _migrate_schema(self) -> None:
        required_columns = {
            "health_latest": {
                "recorded_at": "TEXT",
                "start_at": "TEXT",
                "end_at": "TEXT",
            }
        }
        for table_name, columns in required_columns.items():
            existing = {
                row["name"]
                for row in self._conn.execute(f"PRAGMA table_info({table_name})").fetchall()
            }
            for column_name, definition in columns.items():
                if column_name not in existing:
                    self._conn.execute(f"ALTER TABLE {table_name} ADD COLUMN {column_name} {definition}")
        self._commit()

    # ── Location ─────────────────────────────────────────────────

    def store_location(self, reading: LocationReading) -> str:
        with self._lock:
            return self._store_location_locked(reading)

    def _store_location_locked(self, reading: LocationReading) -> str:
        row_id = str(uuid4())
        recorded_at = reading.recorded_at or utcnow_iso()
        now = utcnow_iso()
        current = self.get_current_location()

        should_append_history = self._location_changed(current, reading)
        if should_append_history:
            self._conn.execute(
                "INSERT INTO location_history (id, latitude, longitude, altitude, accuracy, address, recorded_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (row_id, reading.latitude, reading.longitude, reading.altitude, reading.accuracy, reading.address, recorded_at),
            )

        self._conn.execute(
            "INSERT INTO location_current (id, latitude, longitude, altitude, accuracy, address, recorded_at, updated_at) "
            "VALUES (1, ?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(id) DO UPDATE SET "
            "latitude=excluded.latitude, longitude=excluded.longitude, altitude=excluded.altitude, "
            "accuracy=excluded.accuracy, address=excluded.address, recorded_at=excluded.recorded_at, updated_at=excluded.updated_at",
            (reading.latitude, reading.longitude, reading.altitude, reading.accuracy, reading.address, recorded_at, now),
        )
        self._commit()
        self.prune_location_history()
        return row_id

    def _location_changed(self, current: CurrentLocation | None, reading: LocationReading) -> bool:
        if current is None:
            return True
        if not _same_value(current.latitude, reading.latitude, tolerance=0.00001):
            return True
        if not _same_value(current.longitude, reading.longitude, tolerance=0.00001):
            return True
        if not _same_value(current.altitude, reading.altitude, tolerance=3.0):
            return True
        if not _same_value(current.accuracy, reading.accuracy, tolerance=5.0):
            return True
        return current.address != reading.address

    def get_current_location(self) -> CurrentLocation | None:
        row = self._read_conn.execute("SELECT * FROM location_current WHERE id = 1").fetchone()
        if row is None:
            return None
        return CurrentLocation(
            latitude=row["latitude"],
            longitude=row["longitude"],
            altitude=row["altitude"],
            accuracy=row["accuracy"],
            address=row["address"],
            recorded_at=row["recorded_at"],
            updated_at=row["updated_at"],
        )

    def get_location_history(self, *, since: str | None = None, limit: int = 50) -> list[dict]:
        if since:
            rows = self._read_conn.execute(
                "SELECT * FROM location_history WHERE recorded_at >= ? ORDER BY recorded_at DESC LIMIT ?",
                (since, limit),
            ).fetchall()
        else:
            rows = self._read_conn.execute(
                "SELECT * FROM location_history ORDER BY recorded_at DESC LIMIT ?",
                (limit,),
            ).fetchall()
        return [dict(row) for row in rows]

    def get_location_freshness(self) -> dict | None:
        current = self.get_current_location()
        if current is None:
            return None
        return freshness_metadata(
            recorded_at=current.recorded_at,
            updated_at=current.updated_at,
            stale_after_seconds=LOCATION_STALE_AFTER_SECONDS,
        )

    # ── Health ───────────────────────────────────────────────────

    def store_health_samples(self, samples: list[HealthSample]) -> int:
        with self._lock:
            return self._store_health_samples_locked(samples)

    def _store_health_samples_locked(self, samples: list[HealthSample]) -> int:
        now = utcnow_iso()
        stored = 0
        for sample in samples:
            if sample.metric in WINDOWED_HEALTH_METRICS and self._collapse_windowed_duplicate(sample):
                self._upsert_latest_metric(sample, updated_at=now)
                continue
            if self._sample_exists(sample):
                self._upsert_latest_metric(sample, updated_at=now)
                continue

            row_id = str(uuid4())
            self._conn.execute(
                "INSERT INTO health_samples (id, metric, value, unit, start_at, end_at, source) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (row_id, sample.metric, sample.value, sample.unit, sample.start_at, sample.end_at, sample.source),
            )
            self._upsert_latest_metric(sample, updated_at=now)
            stored += 1

        self._commit()
        self.prune_health_samples()
        self._rollup_daily_aggregates()
        return stored

    def _collapse_windowed_duplicate(self, sample: HealthSample) -> bool:
        row = self._conn.execute(
            "SELECT id, value, unit FROM health_samples "
            "WHERE metric = ? AND start_at = ? ORDER BY COALESCE(end_at, start_at) DESC, created_at DESC LIMIT 1",
            (sample.metric, sample.start_at),
        ).fetchone()
        if row is None:
            return False
        if not _same_value(row["value"], sample.value) or row["unit"] != sample.unit:
            return False

        self._conn.execute(
            "UPDATE health_samples SET end_at = ?, source = ? WHERE id = ?",
            (sample.end_at, sample.source, row["id"]),
        )
        return True

    def _sample_exists(self, sample: HealthSample) -> bool:
        row = self._conn.execute(
            "SELECT id FROM health_samples "
            "WHERE metric = ? AND value = ? AND unit = ? AND start_at = ? AND COALESCE(end_at, '') = COALESCE(?, '') "
            "LIMIT 1",
            (sample.metric, sample.value, sample.unit, sample.start_at, sample.end_at),
        ).fetchone()
        return row is not None

    def _upsert_latest_metric(self, sample: HealthSample, *, updated_at: str) -> None:
        self._conn.execute(
            "INSERT INTO health_latest (metric, value, unit, recorded_at, start_at, end_at, updated_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT(metric) DO UPDATE SET "
            "value=excluded.value, unit=excluded.unit, recorded_at=excluded.recorded_at, "
            "start_at=excluded.start_at, end_at=excluded.end_at, updated_at=excluded.updated_at",
            (sample.metric, sample.value, sample.unit, sample.recorded_at, sample.start_at, sample.end_at, updated_at),
        )

    def get_latest_metrics(self) -> list[LatestMetric]:
        rows = self._read_conn.execute("SELECT * FROM health_latest ORDER BY metric").fetchall()
        return [
            LatestMetric(
                metric=row["metric"],
                value=row["value"],
                unit=row["unit"],
                recorded_at=row["recorded_at"],
                start_at=row["start_at"],
                end_at=row["end_at"],
                updated_at=row["updated_at"],
            )
            for row in rows
        ]

    def get_health_metric(self, metric: str, *, since: str | None = None, limit: int = 50) -> list[dict]:
        if since:
            rows = self._read_conn.execute(
                "SELECT * FROM health_samples WHERE metric = ? AND COALESCE(end_at, start_at) >= ? "
                "ORDER BY COALESCE(end_at, start_at) DESC, created_at DESC LIMIT ?",
                (metric, since, limit),
            ).fetchall()
        else:
            rows = self._read_conn.execute(
                "SELECT * FROM health_samples WHERE metric = ? "
                "ORDER BY COALESCE(end_at, start_at) DESC, created_at DESC LIMIT ?",
                (metric, limit),
            ).fetchall()
        results = [dict(row) for row in rows]
        for item in results:
            item["recordedAt"] = item["end_at"] or item["start_at"]
        return results

    def get_metric_freshness(self, metric: str) -> dict | None:
        row = self._read_conn.execute("SELECT * FROM health_latest WHERE metric = ?", (metric,)).fetchone()
        if row is None:
            return None
        return freshness_metadata(
            recorded_at=row["recorded_at"],
            updated_at=row["updated_at"],
            stale_after_seconds=HEALTH_STALE_AFTER_SECONDS,
        )

    def get_health_summary(self) -> dict:
        metrics = self.get_latest_metrics()
        return {
            "metrics": {
                metric.metric: {
                    "value": metric.value,
                    "unit": metric.unit,
                    "recordedAt": metric.recorded_at,
                    "startAt": metric.start_at,
                    "endAt": metric.end_at,
                    **freshness_metadata(
                        recorded_at=metric.recorded_at,
                        updated_at=metric.updated_at,
                        stale_after_seconds=HEALTH_STALE_AFTER_SECONDS,
                    ),
                }
                for metric in metrics
            },
            "count": len(metrics),
        }

    def get_sensor_freshness_summary(self) -> dict:
        metrics = self.get_latest_metrics()
        fresh_health = 0
        stale_health = 0
        latest_recorded_at: str | None = None
        for metric in metrics:
            freshness = freshness_metadata(
                recorded_at=metric.recorded_at,
                updated_at=metric.updated_at,
                stale_after_seconds=HEALTH_STALE_AFTER_SECONDS,
            )
            if freshness["stale"]:
                stale_health += 1
            else:
                fresh_health += 1
            if metric.recorded_at and (latest_recorded_at is None or metric.recorded_at > latest_recorded_at):
                latest_recorded_at = metric.recorded_at

        return {
            "location": self.get_location_freshness(),
            "health": {
                "count": len(metrics),
                "freshCount": fresh_health,
                "staleCount": stale_health,
                "latestRecordedAt": latest_recorded_at,
            },
        }

    # ── Daily Aggregates ─────────────────────────────────────────

    # Cumulative/windowed metrics where the daily value is the MAX of the
    # snapshots (each snapshot is a running total, not an increment).
    _CUMULATIVE_METRICS = {"steps", "active_calories", "distance_walking",
                           "workout_minutes", "stand_hours", "sleep_duration"}

    # Point-in-time metrics where avg/min/max are meaningful but sum is not.
    # For these, sum_value is set to NULL.

    def _rollup_daily_aggregates(self) -> None:
        """Roll up health_samples into health_daily for completed days.

        Cumulative metrics (steps, calories, etc.) use MAX as the daily total
        because each sample is a running total since start of day.
        Point metrics (heart_rate, blood_oxygen, etc.) use AVG/MIN/MAX
        with sum_value set to NULL (summing heart rates is meaningless).
        """
        now = utcnow().strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        today = utcnow().strftime("%Y-%m-%d")

        # Use parameterized placeholders for metric names (no f-string SQL injection risk)
        cumulative = list(self._CUMULATIVE_METRICS)
        placeholders = ",".join("?" * len(cumulative))

        # Cumulative metrics: daily value = MAX of the day's snapshots
        self._conn.execute(
            f"""
            INSERT OR REPLACE INTO health_daily
                (metric, date, sum_value, avg_value, min_value, max_value, count, unit, updated_at)
            SELECT metric, date(start_at) AS day, MAX(value), AVG(value), MIN(value),
                   MAX(value), COUNT(*), unit, ?
            FROM health_samples
            WHERE date(start_at) < ? AND metric IN ({placeholders})
            GROUP BY metric, date(start_at)
            """,
            (now, today, *cumulative),
        )

        # Point metrics: avg/min/max are meaningful, sum is not
        self._conn.execute(
            f"""
            INSERT OR REPLACE INTO health_daily
                (metric, date, sum_value, avg_value, min_value, max_value, count, unit, updated_at)
            SELECT metric, date(start_at) AS day, NULL, AVG(value), MIN(value),
                   MAX(value), COUNT(*), unit, ?
            FROM health_samples
            WHERE date(start_at) < ? AND metric NOT IN ({placeholders})
            GROUP BY metric, date(start_at)
            """,
            (now, today, *cumulative),
        )

        self._commit()

    # ── Maintenance ──────────────────────────────────────────────

    def prune_location_history(self, retention_days: int = 90) -> int:
        cutoff_dt = utcnow() - timedelta(days=retention_days)
        cutoff = cutoff_dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        cursor = self._conn.execute("DELETE FROM location_history WHERE recorded_at < ?", (cutoff,))
        self._commit()
        return cursor.rowcount

    def prune_health_samples(self, retention_days: int = 90) -> int:
        cutoff_dt = utcnow() - timedelta(days=retention_days)
        cutoff = cutoff_dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        cutoff_date = cutoff_dt.strftime("%Y-%m-%d")
        cursor = self._conn.execute(
            "DELETE FROM health_samples WHERE COALESCE(end_at, start_at) < ?",
            (cutoff,),
        )
        # Also prune daily aggregates older than retention
        self._conn.execute("DELETE FROM health_daily WHERE date < ?", (cutoff_date,))
        self._commit()
        return cursor.rowcount
