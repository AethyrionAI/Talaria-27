"""Scheduled / recurring agent runs — relay-side v0 (#98, Lane G).

The relay can already *watch* a gateway run and push on completion (#38).
This module adds the missing half: *starting* runs on a schedule. A
``Schedule`` row names a prompt and a recurrence; the trigger loop wakes on
a coarse tick, fires due schedules by creating a fresh gateway session and
starting a detached run through the existing ``GatewayClient`` path, then
registers the run with the existing completion-watch machinery — which is
what delivers the result (APNs alert with ``session_id``). No new delivery
code.

Recurrence kinds and their grammar live here in one place:

  once      run_at (aware UTC datetime, must be in the future at create)
  interval  interval_minutes (hard floor: 60 — no schedule may fire more
            often than hourly)
  daily     time_of_day "HH:MM" in timezone_name (IANA, default UTC)
  weekly    time_of_day + weekday (0=Monday … 6=Sunday) in timezone_name

Policies (the load-bearing ones, matching the Lane G dispatch):

* Missed runs: if a due time was missed (relay down, gateway down), fire at
  most ONE catch-up run — and only if the miss is smaller than one
  recurrence period; otherwise skip forward to the next occurrence without
  firing. A queue of missed runs is never backfilled. A one-shot's
  "period" for this purpose is the hourly floor (60 minutes).
* In-flight guard: a schedule whose previous run is still being watched
  (i.e. hasn't completed, and the watch TTL hasn't expired) skips the tick
  with a log line — runs never stack.

SQLite note: DateTime columns round-trip through SQLite without timezone
info and come back naive-UTC, so every datetime read from a row is passed
through ``normalize_datetime`` before comparison (same convention as
``security.py``).
"""

from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from datetime import datetime, timedelta, timezone
import logging
from zoneinfo import ZoneInfo

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import Settings
from .database import Database
from .gateway import GatewayClient, GatewayError
from .models import Schedule, utcnow
from .security import normalize_datetime
from .services import record_audit

logger = logging.getLogger("hermes.relay.scheduler")

#: Hard floor — no schedule may fire more often than hourly (matches the
#: competitor guardrail and protects the gateway).
MIN_INTERVAL_MINUTES = 60

SCHEDULE_KINDS = ("once", "interval", "daily", "weekly")
SESSION_STRATEGIES = ("fresh",)  # v0: fresh gateway session per run

#: 0=Monday … 6=Sunday (Python ``datetime.weekday()`` numbering).
WEEKDAY_RANGE = range(0, 7)


def parse_time_of_day(value: str) -> tuple[int, int]:
    """Parse ``"HH:MM"`` (24h) into ``(hour, minute)``; raise ValueError."""
    parts = value.split(":")
    if len(parts) != 2:
        raise ValueError(f"time_of_day must be 'HH:MM', got {value!r}")
    hour, minute = int(parts[0]), int(parts[1])
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        raise ValueError(f"time_of_day out of range: {value!r}")
    return hour, minute


def resolve_timezone(timezone_name: str | None) -> ZoneInfo | timezone:
    """IANA name → tzinfo (UTC when unset); raise ValueError on unknown."""
    if not timezone_name:
        return timezone.utc
    try:
        return ZoneInfo(timezone_name)
    except Exception as e:  # ZoneInfoNotFoundError, ValueError on bad keys
        raise ValueError(f"unknown timezone: {timezone_name!r}") from e


def compute_next_run_at(
    *,
    kind: str,
    after: datetime,
    run_at: datetime | None = None,
    interval_minutes: int | None = None,
    time_of_day: str | None = None,
    weekday: int | None = None,
    timezone_name: str | None = None,
) -> datetime | None:
    """The next UTC fire time strictly after ``after``, or None if there
    is no future occurrence (a one-shot whose time has passed).

    Daily/weekly arithmetic happens in the schedule's own timezone on wall
    clocks (aware-datetime + timedelta keeps the wall time, re-deriving the
    UTC offset), so "daily at 09:00 Chicago" stays 09:00 across DST.
    """
    after = normalize_datetime(after)

    if kind == "once":
        if run_at is None:
            return None
        run_at = normalize_datetime(run_at)
        return run_at if run_at > after else None

    if kind == "interval":
        if not interval_minutes:
            return None
        return after + timedelta(minutes=interval_minutes)

    if kind in ("daily", "weekly"):
        if not time_of_day:
            return None
        hour, minute = parse_time_of_day(time_of_day)
        local_after = after.astimezone(resolve_timezone(timezone_name))
        candidate = local_after.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if kind == "daily":
            if candidate <= local_after:
                candidate += timedelta(days=1)
        else:
            if weekday is None:
                return None
            candidate += timedelta(days=(weekday - candidate.weekday()) % 7)
            if candidate <= local_after:
                candidate += timedelta(days=7)
        return candidate.astimezone(timezone.utc)

    return None


def recurrence_period(*, kind: str, interval_minutes: int | None = None) -> timedelta:
    """One recurrence period — the missed-run policy's catch-up window.

    A one-shot has no recurrence, so its window is the hourly floor: a
    one-shot missed by less than an hour still fires; anything staler is
    marked missed instead of firing arbitrarily late.
    """
    if kind == "interval" and interval_minutes:
        return timedelta(minutes=interval_minutes)
    if kind == "daily":
        return timedelta(days=1)
    if kind == "weekly":
        return timedelta(days=7)
    return timedelta(minutes=MIN_INTERVAL_MINUTES)


def next_run_at_for_schedule(schedule: Schedule, *, after: datetime) -> datetime | None:
    return compute_next_run_at(
        kind=schedule.kind,
        after=after,
        run_at=schedule.run_at,
        interval_minutes=schedule.interval_minutes,
        time_of_day=schedule.time_of_day,
        weekday=schedule.weekday,
        timezone_name=schedule.timezone_name,
    )


def get_schedule_for_user(db: Session, *, schedule_id: str, user_id: str) -> Schedule:
    schedule = db.scalar(
        select(Schedule).where(Schedule.id == schedule_id, Schedule.user_id == user_id)
    )
    if schedule is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Schedule not found.")
    return schedule


def list_schedules(db: Session, *, user_id: str) -> list[Schedule]:
    return list(
        db.scalars(
            select(Schedule)
            .where(Schedule.user_id == user_id)
            .order_by(Schedule.created_at.asc())
        ).all()
    )


def _utc_or_none(value: datetime | None) -> datetime | None:
    return normalize_datetime(value) if value is not None else None


def serialize_schedule(schedule: Schedule) -> dict:
    """Datetimes are normalized to aware UTC so the JSON carries an explicit
    offset — nextRunAt is UI-facing state for the future management lane."""
    return {
        "id": schedule.id,
        "prompt": schedule.prompt,
        "sessionStrategy": schedule.session_strategy,
        "kind": schedule.kind,
        "runAt": _utc_or_none(schedule.run_at),
        "intervalMinutes": schedule.interval_minutes,
        "timeOfDay": schedule.time_of_day,
        "weekday": schedule.weekday,
        "timezone": schedule.timezone_name,
        "enabled": schedule.enabled,
        "lastRunAt": _utc_or_none(schedule.last_run_at),
        "lastRunSessionId": schedule.last_run_session_id,
        "nextRunAt": _utc_or_none(schedule.next_run_at),
        "createdAt": _utc_or_none(schedule.created_at),
        "updatedAt": _utc_or_none(schedule.updated_at),
    }


class ScheduleRunner:
    """The trigger loop. Wakes on a coarse tick and fires due schedules
    through the existing gateway run path + completion-watch machinery.

    Collaborators are injected so tests can drive ticks with a fake clock
    and no real sleeps:

      get_gateway      () -> GatewayClient | None — read at fire time (the
                       app swaps clients on state, tests install stubs).
      register_watch   (user_id=, session_id=) -> None — the same
                       registration ``POST /v1/push/watch`` performs.
      is_watch_active  (user_id=, session_id=) -> bool — the in-flight
                       guard consults the live watch registry.
      clock            () -> aware-UTC datetime.
      sleep            async (seconds) -> None.
    """

    def __init__(
        self,
        *,
        database: Database,
        settings: Settings,
        get_gateway: Callable[[], GatewayClient | None],
        register_watch: Callable[..., None],
        is_watch_active: Callable[..., bool],
        clock: Callable[[], datetime] = utcnow,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        self.database = database
        self.settings = settings
        self.get_gateway = get_gateway
        self.register_watch = register_watch
        self.is_watch_active = is_watch_active
        self.clock = clock
        self.sleep = sleep

    async def run_forever(self) -> None:
        logger.info(
            "scheduler: trigger loop started (tick %.0fs)",
            self.settings.scheduler_tick_seconds,
        )
        while True:
            await self.sleep(self.settings.scheduler_tick_seconds)
            try:
                await self.tick()
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.warning("scheduler: tick failed", exc_info=True)

    async def tick(self, now: datetime | None = None) -> int:
        """Fire every due schedule once. Returns the number of runs started."""
        now = normalize_datetime(now) if now is not None else normalize_datetime(self.clock())
        with self.database.session() as db:
            due_ids = list(
                db.scalars(
                    select(Schedule.id)
                    .where(
                        Schedule.enabled == True,  # noqa: E712 — SQLAlchemy expression
                        Schedule.next_run_at.is_not(None),
                        Schedule.next_run_at <= now,
                    )
                    .order_by(Schedule.next_run_at.asc())
                ).all()
            )

        fired = 0
        for schedule_id in due_ids:
            try:
                if await self._process_due(schedule_id, now):
                    fired += 1
            except Exception:
                logger.warning(
                    "scheduler: unexpected error processing schedule %s",
                    schedule_id,
                    exc_info=True,
                )
        return fired

    async def _process_due(self, schedule_id: str, now: datetime) -> bool:
        """One due schedule: in-flight guard → missed-run policy → fire."""
        with self.database.session() as db:
            schedule = db.get(Schedule, schedule_id)
            if schedule is None or not schedule.enabled or schedule.next_run_at is None:
                return False
            next_run_at = normalize_datetime(schedule.next_run_at)
            if next_run_at > now:
                return False
            snapshot = {
                "user_id": schedule.user_id,
                "prompt": schedule.prompt,
                "kind": schedule.kind,
                "interval_minutes": schedule.interval_minutes,
                "last_run_session_id": schedule.last_run_session_id,
            }

        if snapshot["last_run_session_id"] and self.is_watch_active(
            user_id=snapshot["user_id"], session_id=snapshot["last_run_session_id"]
        ):
            logger.info(
                "scheduler: schedule %s due but previous run (session %s) is still in flight; skipping tick",
                schedule_id,
                snapshot["last_run_session_id"],
            )
            return False

        miss = now - next_run_at
        period = recurrence_period(
            kind=snapshot["kind"], interval_minutes=snapshot["interval_minutes"]
        )
        if miss >= period:
            self._skip_forward(schedule_id, now=now, miss=miss)
            return False

        return await self._fire(schedule_id, snapshot=snapshot, now=now)

    def _skip_forward(self, schedule_id: str, *, now: datetime, miss: timedelta) -> None:
        """Missed by a full period or more: never backfill — move to the
        next natural occurrence (one-shots simply become missed)."""
        with self.database.session() as db:
            schedule = db.get(Schedule, schedule_id)
            if schedule is None or not schedule.enabled:
                return
            if schedule.kind == "once":
                schedule.enabled = False
                schedule.next_run_at = None
            else:
                schedule.next_run_at = next_run_at_for_schedule(schedule, after=now)
            schedule.updated_at = now
            record_audit(
                db,
                actor_type="relay",
                action="schedule.skip_forward",
                entity_type="schedule",
                entity_id=schedule_id,
                payload={"missedBySeconds": int(miss.total_seconds())},
            )
            db.commit()
        logger.warning(
            "scheduler: schedule %s missed its due time by %s (≥ one period); skipped forward without firing",
            schedule_id,
            miss,
        )

    async def _fire(self, schedule_id: str, *, snapshot: dict, now: datetime) -> bool:
        """Start the run through the existing gateway path and hand the
        result off to the existing watch → completion-push machinery."""
        gateway = self.get_gateway()
        if gateway is None:
            logger.warning(
                "scheduler: schedule %s is due but the gateway is not configured (set GATEWAY_API_KEY)",
                schedule_id,
            )
            return False

        try:
            session_id = await gateway.create_session()
            await gateway.start_detached_run(session_id, snapshot["prompt"])
        except GatewayError as e:
            # Row left untouched: still due next tick, so a transient gateway
            # outage retries; the missed-run policy caps how late it can fire.
            logger.warning("scheduler: failed to start run for schedule %s: %s", schedule_id, e)
            return False

        self.register_watch(user_id=snapshot["user_id"], session_id=session_id)

        with self.database.session() as db:
            schedule = db.get(Schedule, schedule_id)
            if schedule is None:
                # Deleted mid-fire; the run is already started and watched.
                logger.info(
                    "scheduler: schedule %s deleted while firing; run %s continues",
                    schedule_id,
                    session_id,
                )
                return True
            schedule.last_run_at = now
            schedule.last_run_session_id = session_id
            if schedule.kind == "once":
                schedule.enabled = False
                schedule.next_run_at = None
            else:
                schedule.next_run_at = next_run_at_for_schedule(schedule, after=now)
            schedule.updated_at = now
            record_audit(
                db,
                actor_type="relay",
                action="schedule.fire",
                entity_type="schedule",
                entity_id=schedule_id,
                payload={"sessionId": session_id},
            )
            db.commit()

        logger.info("scheduler: schedule %s fired (gateway session %s)", schedule_id, session_id)
        return True
