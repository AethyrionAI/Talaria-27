"""Scheduled runs (#98, Lane G): recurrence math, CRUD validation, the
trigger loop's firing / missed-run / in-flight policies, and the handoff
to the existing watch → completion-push machinery.

Trigger-loop tests inject a fake clock (and a fake sleep for the loop
itself) — ticks are driven explicitly, no real sleeps pace a schedule.
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone

import httpx
import pytest
from sqlalchemy import inspect, select, text

from app.config import Settings
from app.database import Database
from app.gateway import GatewayClient, GatewayError
from app.models import Schedule
from app.scheduler import (
    MIN_INTERVAL_MINUTES,
    ScheduleRunner,
    compute_next_run_at,
    recurrence_period,
)
from app.services import ensure_default_user

from test_api import build_client, register_device
from test_push_watch import StubAPNsClient, register_push_token


# A fixed aware-UTC "now" — 2026-07-12 is a Sunday (weekday 6).
T0 = datetime(2026, 7, 12, 12, 0, tzinfo=timezone.utc)


class FakeClock:
    def __init__(self, now: datetime = T0) -> None:
        self.now = now

    def __call__(self) -> datetime:
        return self.now


class StubSchedulerGateway:
    """Scripted gateway for the scheduler path: session creation, detached
    run starts, and the completion polls the watch machinery performs."""

    def __init__(self) -> None:
        self.sessions_created = 0
        self.runs: list[tuple[str, str]] = []
        self.fail_next_create = 0
        self.completed_replies: dict[str, str] = {}

    async def create_session(self) -> str:
        if self.fail_next_create:
            self.fail_next_create -= 1
            raise GatewayError("gateway down")
        self.sessions_created += 1
        return f"api_sess_{self.sessions_created}"

    async def start_detached_run(self, session_id: str, prompt: str) -> None:
        self.runs.append((session_id, prompt))

    async def fetch_completed_reply(self, session_id: str):
        return self.completed_replies.get(session_id)


# ---------------------------------------------------------------------------
# Recurrence math (pure)
# ---------------------------------------------------------------------------

def test_next_run_once_future_and_past():
    future = T0 + timedelta(hours=3)
    assert compute_next_run_at(kind="once", after=T0, run_at=future) == future
    assert compute_next_run_at(kind="once", after=T0, run_at=T0 - timedelta(minutes=1)) is None
    assert compute_next_run_at(kind="once", after=T0, run_at=T0) is None


def test_next_run_interval():
    assert compute_next_run_at(kind="interval", after=T0, interval_minutes=60) == T0 + timedelta(minutes=60)
    assert compute_next_run_at(kind="interval", after=T0, interval_minutes=1440) == T0 + timedelta(days=1)


def test_next_run_daily_before_and_after_time():
    # 12:00Z now; 15:30 UTC today is still ahead → today.
    assert compute_next_run_at(kind="daily", after=T0, time_of_day="15:30") == T0.replace(hour=15, minute=30)
    # 09:00 UTC already passed → tomorrow.
    assert compute_next_run_at(kind="daily", after=T0, time_of_day="09:00") == T0.replace(hour=9) + timedelta(days=1)


def test_next_run_daily_timezone():
    # 09:00 in Chicago (CDT, UTC-5 in July) = 14:00Z, still ahead of 12:00Z.
    result = compute_next_run_at(
        kind="daily", after=T0, time_of_day="09:00", timezone_name="America/Chicago"
    )
    assert result == T0.replace(hour=14, minute=0)
    assert result.tzinfo == timezone.utc


def test_next_run_weekly():
    # T0 is Sunday. Monday (0) 09:00 UTC → tomorrow.
    assert compute_next_run_at(
        kind="weekly", after=T0, time_of_day="09:00", weekday=0
    ) == T0.replace(hour=9) + timedelta(days=1)
    # Sunday 09:00 already passed this week → next Sunday.
    assert compute_next_run_at(
        kind="weekly", after=T0, time_of_day="09:00", weekday=6
    ) == T0.replace(hour=9) + timedelta(days=7)
    # Sunday 15:00 still ahead today.
    assert compute_next_run_at(
        kind="weekly", after=T0, time_of_day="15:00", weekday=6
    ) == T0.replace(hour=15)


def test_recurrence_period_values():
    assert recurrence_period(kind="interval", interval_minutes=90) == timedelta(minutes=90)
    assert recurrence_period(kind="daily") == timedelta(days=1)
    assert recurrence_period(kind="weekly") == timedelta(days=7)
    # A one-shot's catch-up window is the hourly floor.
    assert recurrence_period(kind="once") == timedelta(minutes=MIN_INTERVAL_MINUTES)


# ---------------------------------------------------------------------------
# GatewayClient — the two new calls, via MockTransport
# ---------------------------------------------------------------------------

def make_gateway_client(handler) -> GatewayClient:
    return GatewayClient(
        base_url="http://gateway.test:8642",
        api_key="test-api-server-key",
        transport=httpx.MockTransport(handler),
    )


def run_with_client(handler, action):
    async def run():
        client = make_gateway_client(handler)
        try:
            return await action(client)
        finally:
            await client.close()
    return asyncio.run(run())


def test_gateway_create_session():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["auth"] = request.headers.get("Authorization")
        return httpx.Response(200, json={"object": "hermes.session", "session": {"id": "api_123"}})

    session_id = run_with_client(handler, lambda c: c.create_session())
    assert session_id == "api_123"
    assert seen["url"] == "http://gateway.test:8642/api/sessions"
    assert seen["auth"] == "Bearer test-api-server-key"


def test_gateway_create_session_errors():
    with pytest.raises(GatewayError):
        run_with_client(lambda r: httpx.Response(500, text="boom"), lambda c: c.create_session())
    with pytest.raises(GatewayError):
        run_with_client(lambda r: httpx.Response(200, json={"nope": True}), lambda c: c.create_session())


def test_gateway_start_detached_run_disconnects_after_first_event():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["body"] = request.content
        return httpx.Response(
            200,
            headers={"content-type": "text/event-stream"},
            content=b'event: run.started\ndata: {"run_id":"r1"}\n\n',
        )

    result = run_with_client(handler, lambda c: c.start_detached_run("api_1", "do the thing"))
    assert result is None
    assert seen["url"] == "http://gateway.test:8642/api/sessions/api_1/chat/stream"
    assert b'"input"' in seen["body"] and b"do the thing" in seen["body"]


def test_gateway_start_detached_run_errors():
    with pytest.raises(GatewayError):
        run_with_client(
            lambda r: httpx.Response(401, text="unauthorized"),
            lambda c: c.start_detached_run("api_1", "p"),
        )
    # Stream that closes before any event ever arrives.
    with pytest.raises(GatewayError):
        run_with_client(
            lambda r: httpx.Response(200, headers={"content-type": "text/event-stream"}, content=b""),
            lambda c: c.start_detached_run("api_1", "p"),
        )


# ---------------------------------------------------------------------------
# App-level helpers
# ---------------------------------------------------------------------------

def scheduler_client(tmp_path, **overrides):
    """TestClient with the background loop off (ticks are test-driven) and
    fast watch polling for the end-to-end delivery test."""
    return build_client(
        tmp_path,
        scheduler_enabled=False,
        push_watch_poll_seconds=0.01,
        push_watch_fast_window_seconds=60.0,
        push_watch_ttl_seconds=10.0,
        **overrides,
    )


def install_stubs(client, now: datetime = T0):
    apns = StubAPNsClient()
    gateway = StubSchedulerGateway()
    client.app.state.apns_client = apns
    client.app.state.gateway_client = gateway
    clock = FakeClock(now)
    client.app.state.schedule_runner.clock = clock
    return apns, gateway, clock


def register_and_auth(client) -> tuple[dict, str]:
    data = register_device(client)
    token = data["auth"]["accessToken"]
    return data, {"Authorization": f"Bearer {token}"}


def create_schedule(client, headers, **body) -> dict:
    response = client.post("/v1/schedules", headers=headers, json=body)
    assert response.status_code == 200, response.text
    return response.json()["data"]["schedule"]


def run_tick(client, now: datetime) -> int:
    runner = client.app.state.schedule_runner
    runner.clock.now = now
    return asyncio.run(runner.tick(now))


def fetch_schedule_row(client, schedule_id: str) -> dict:
    with client.app.state.database.session() as db:
        row = db.get(Schedule, schedule_id)
        assert row is not None
        return {
            "enabled": row.enabled,
            "last_run_at": row.last_run_at,
            "next_run_at": row.next_run_at,
            "last_run_session_id": row.last_run_session_id,
        }


def as_utc(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def parse_api_datetime(value: str) -> datetime:
    return as_utc(datetime.fromisoformat(value))


# ---------------------------------------------------------------------------
# CRUD API
# ---------------------------------------------------------------------------

def test_schedule_crud_roundtrip(tmp_path):
    with scheduler_client(tmp_path) as client:
        install_stubs(client)
        _, headers = register_and_auth(client)

        schedule = create_schedule(
            client, headers, prompt="check the overnight logs", kind="interval", intervalMinutes=120
        )
        assert schedule["kind"] == "interval"
        assert schedule["sessionStrategy"] == "fresh"
        assert schedule["enabled"] is True
        assert parse_api_datetime(schedule["nextRunAt"]) == T0 + timedelta(minutes=120)

        listed = client.get("/v1/schedules", headers=headers)
        assert listed.status_code == 200
        assert [s["id"] for s in listed.json()["data"]["schedules"]] == [schedule["id"]]

        got = client.get(f"/v1/schedules/{schedule['id']}", headers=headers)
        assert got.status_code == 200
        assert got.json()["data"]["schedule"]["prompt"] == "check the overnight logs"

        updated = client.patch(
            f"/v1/schedules/{schedule['id']}",
            headers=headers,
            json={"prompt": "check the overnight logs and the backup job"},
        )
        assert updated.status_code == 200
        assert updated.json()["data"]["schedule"]["prompt"] == "check the overnight logs and the backup job"
        # Prompt-only update does not re-anchor the next fire.
        assert parse_api_datetime(updated.json()["data"]["schedule"]["nextRunAt"]) == T0 + timedelta(minutes=120)

        paused = client.post(f"/v1/schedules/{schedule['id']}/pause", headers=headers)
        assert paused.status_code == 200
        assert paused.json()["data"]["schedule"]["enabled"] is False
        assert paused.json()["data"]["schedule"]["nextRunAt"] is None

        resumed = client.post(f"/v1/schedules/{schedule['id']}/resume", headers=headers)
        assert resumed.status_code == 200
        assert resumed.json()["data"]["schedule"]["enabled"] is True
        assert parse_api_datetime(resumed.json()["data"]["schedule"]["nextRunAt"]) == T0 + timedelta(minutes=120)

        deleted = client.delete(f"/v1/schedules/{schedule['id']}", headers=headers)
        assert deleted.status_code == 200
        assert client.get(f"/v1/schedules/{schedule['id']}", headers=headers).status_code == 404


def test_schedule_create_validation(tmp_path):
    with scheduler_client(tmp_path) as client:
        install_stubs(client)
        _, headers = register_and_auth(client)

        def attempt(body: dict) -> int:
            return client.post("/v1/schedules", headers=headers, json=body).status_code

        # The hourly floor.
        assert attempt({"prompt": "p", "kind": "interval", "intervalMinutes": 59}) == 422
        assert attempt({"prompt": "p", "kind": "interval", "intervalMinutes": 30}) == 422
        # Past (and exactly-now) one-shots.
        assert attempt({"prompt": "p", "kind": "once", "runAt": "2020-01-01T00:00:00Z"}) == 400
        assert attempt({"prompt": "p", "kind": "once", "runAt": T0.isoformat()}) == 400
        # Per-kind field consistency.
        assert attempt({"prompt": "p", "kind": "once"}) == 422
        assert attempt({"prompt": "p", "kind": "weekly", "timeOfDay": "09:00"}) == 422
        assert attempt({"prompt": "p", "kind": "daily"}) == 422
        assert attempt(
            {"prompt": "p", "kind": "once", "runAt": "2030-01-01T00:00:00Z", "intervalMinutes": 60}
        ) == 422
        # Grammar details.
        assert attempt({"prompt": "p", "kind": "daily", "timeOfDay": "25:00"}) == 422
        assert attempt({"prompt": "p", "kind": "daily", "timeOfDay": "09:00", "timezone": "Not/AZone"}) == 422
        assert attempt({"prompt": "p", "kind": "weekly", "timeOfDay": "09:00", "weekday": 7}) == 422
        assert attempt({"prompt": "   ", "kind": "interval", "intervalMinutes": 60}) == 422
        # Unsupported session strategy (v0 is fresh-only).
        assert attempt(
            {"prompt": "p", "kind": "interval", "intervalMinutes": 60, "sessionStrategy": "continue"}
        ) == 422


def test_schedule_requires_auth(tmp_path):
    with scheduler_client(tmp_path) as client:
        install_stubs(client)
        assert client.get("/v1/schedules").status_code == 401
        assert client.post("/v1/schedules", json={"prompt": "p", "kind": "interval", "intervalMinutes": 60}).status_code == 401


def test_schedule_create_rejected_without_gateway(tmp_path):
    with scheduler_client(tmp_path) as client:
        install_stubs(client)
        client.app.state.gateway_client = None
        _, headers = register_and_auth(client)
        response = client.post(
            "/v1/schedules", headers=headers, json={"prompt": "p", "kind": "interval", "intervalMinutes": 60}
        )
        assert response.status_code == 503
        assert "GATEWAY_API_KEY" in response.json()["detail"]


def test_schedule_update_recurrence_requires_full_kind(tmp_path):
    with scheduler_client(tmp_path) as client:
        install_stubs(client)
        _, headers = register_and_auth(client)
        schedule = create_schedule(client, headers, prompt="p", kind="interval", intervalMinutes=60)

        # A recurrence subfield without `kind` is rejected.
        response = client.patch(
            f"/v1/schedules/{schedule['id']}", headers=headers, json={"intervalMinutes": 120}
        )
        assert response.status_code == 422

        # A full recurrence change re-anchors nextRunAt from now.
        client.app.state.schedule_runner.clock.now = T0 + timedelta(minutes=10)
        response = client.patch(
            f"/v1/schedules/{schedule['id']}",
            headers=headers,
            json={"kind": "daily", "timeOfDay": "18:00"},
        )
        assert response.status_code == 200
        body = response.json()["data"]["schedule"]
        assert body["kind"] == "daily"
        assert body["intervalMinutes"] is None
        assert parse_api_datetime(body["nextRunAt"]) == T0.replace(hour=18, minute=0)


def test_resume_expired_one_shot_conflicts(tmp_path):
    with scheduler_client(tmp_path) as client:
        _, _, clock = install_stubs(client)
        _, headers = register_and_auth(client)
        schedule = create_schedule(
            client, headers, prompt="p", kind="once", runAt=(T0 + timedelta(hours=1)).isoformat()
        )
        assert client.post(f"/v1/schedules/{schedule['id']}/pause", headers=headers).status_code == 200

        clock.now = T0 + timedelta(hours=2)
        response = client.post(f"/v1/schedules/{schedule['id']}/resume", headers=headers)
        assert response.status_code == 409


# ---------------------------------------------------------------------------
# Trigger loop — firing and policies (fake clock, test-driven ticks)
# ---------------------------------------------------------------------------

def test_tick_fires_due_schedule_exactly_once_and_updates_row(tmp_path):
    """The acceptance path: a schedule created via the API fires exactly
    once at its due tick and updates last_run_at / next_run_at."""
    with scheduler_client(tmp_path) as client:
        _, gateway, _ = install_stubs(client)
        _, headers = register_and_auth(client)
        schedule = create_schedule(client, headers, prompt="hourly check-in", kind="interval", intervalMinutes=60)

        # One tick before the due time: nothing fires.
        assert run_tick(client, T0 + timedelta(minutes=59)) == 0
        assert gateway.runs == []

        # The due tick fires exactly once, through the gateway run path.
        due = T0 + timedelta(minutes=60)
        assert run_tick(client, due) == 1
        assert gateway.runs == [("api_sess_1", "hourly check-in")]

        row = fetch_schedule_row(client, schedule["id"])
        assert as_utc(row["last_run_at"]) == due
        assert as_utc(row["next_run_at"]) == due + timedelta(minutes=60)
        assert row["last_run_session_id"] == "api_sess_1"

        # The next tick (already past due) does not re-fire.
        assert run_tick(client, due + timedelta(minutes=1)) == 0
        assert len(gateway.runs) == 1


def test_once_schedule_fires_then_disables(tmp_path):
    with scheduler_client(tmp_path) as client:
        _, gateway, _ = install_stubs(client)
        _, headers = register_and_auth(client)
        run_at = T0 + timedelta(hours=2)
        schedule = create_schedule(client, headers, prompt="one shot", kind="once", runAt=run_at.isoformat())
        assert parse_api_datetime(schedule["nextRunAt"]) == run_at

        assert run_tick(client, run_at) == 1
        row = fetch_schedule_row(client, schedule["id"])
        assert row["enabled"] is False
        assert row["next_run_at"] is None
        assert as_utc(row["last_run_at"]) == run_at

        assert run_tick(client, run_at + timedelta(hours=5)) == 0
        assert len(gateway.runs) == 1


def test_paused_schedule_does_not_fire(tmp_path):
    with scheduler_client(tmp_path) as client:
        _, gateway, clock = install_stubs(client)
        _, headers = register_and_auth(client)
        schedule = create_schedule(client, headers, prompt="p", kind="interval", intervalMinutes=60)

        assert client.post(f"/v1/schedules/{schedule['id']}/pause", headers=headers).status_code == 200
        assert run_tick(client, T0 + timedelta(minutes=90)) == 0
        assert gateway.runs == []

        # Resume re-anchors from now — no stale catch-up fires...
        clock.now = T0 + timedelta(minutes=90)
        resumed = client.post(f"/v1/schedules/{schedule['id']}/resume", headers=headers)
        assert resumed.status_code == 200
        assert parse_api_datetime(resumed.json()["data"]["schedule"]["nextRunAt"]) == T0 + timedelta(minutes=150)
        assert run_tick(client, T0 + timedelta(minutes=91)) == 0

        # ...and the re-anchored due time fires normally.
        assert run_tick(client, T0 + timedelta(minutes=150)) == 1


# ---------------------------------------------------------------------------
# Unit-level runner harness (no HTTP) for policy branches
# ---------------------------------------------------------------------------

def make_unit_harness(tmp_path, *, is_active=None, clock=None):
    settings = Settings(
        environment="test",
        public_base_url="http://testserver/v1",
        database_url=f"sqlite:///{tmp_path / 'scheduler-unit.db'}",
        internal_api_key="test-internal-key",
    )
    database = Database(settings.database_url)
    database.create_all()
    with database.session() as db:
        user = ensure_default_user(db, settings)
        user_id = user.id

    gateway = StubSchedulerGateway()
    watches: list[tuple[str, str]] = []
    runner = ScheduleRunner(
        database=database,
        settings=settings,
        get_gateway=lambda: gateway,
        register_watch=lambda *, user_id, session_id: watches.append((user_id, session_id)),
        is_watch_active=is_active or (lambda *, user_id, session_id: False),
        clock=clock or FakeClock(),
    )
    return runner, database, gateway, watches, user_id


def insert_schedule(database, user_id, **fields) -> str:
    defaults = dict(
        user_id=user_id,
        prompt="unit prompt",
        kind="interval",
        interval_minutes=60,
        enabled=True,
    )
    defaults.update(fields)
    with database.session() as db:
        schedule = Schedule(**defaults)
        db.add(schedule)
        db.commit()
        return schedule.id


def read_schedule(database, schedule_id) -> Schedule:
    with database.session() as db:
        row = db.get(Schedule, schedule_id)
        db.expunge(row)
        return row


def test_missed_run_fires_one_catch_up_when_miss_under_period(tmp_path):
    runner, database, gateway, watches, user_id = make_unit_harness(tmp_path)
    schedule_id = insert_schedule(database, user_id, next_run_at=T0)

    # Relay was down past the due time, but by less than one period.
    now = T0 + timedelta(minutes=30)
    assert asyncio.run(runner.tick(now)) == 1
    assert len(gateway.runs) == 1
    assert watches == [(user_id, "api_sess_1")]

    row = read_schedule(database, schedule_id)
    assert as_utc(row.last_run_at) == now
    assert as_utc(row.next_run_at) == now + timedelta(minutes=60)


def test_missed_run_skips_forward_when_miss_at_or_over_period(tmp_path):
    runner, database, gateway, watches, user_id = make_unit_harness(tmp_path)
    schedule_id = insert_schedule(database, user_id, next_run_at=T0)

    # Down for two full periods: never backfill, never fire late.
    now = T0 + timedelta(hours=2)
    assert asyncio.run(runner.tick(now)) == 0
    assert gateway.runs == []
    assert watches == []

    row = read_schedule(database, schedule_id)
    assert row.last_run_at is None
    assert row.enabled is True
    assert as_utc(row.next_run_at) == now + timedelta(minutes=60)

    # The skipped-forward due time then fires normally.
    assert asyncio.run(runner.tick(now + timedelta(minutes=60))) == 1


def test_missed_one_shot_fires_within_hour_otherwise_marked_missed(tmp_path):
    runner, database, gateway, _, user_id = make_unit_harness(tmp_path)

    fired_id = insert_schedule(
        database, user_id, kind="once", interval_minutes=None, run_at=T0, next_run_at=T0
    )
    assert asyncio.run(runner.tick(T0 + timedelta(minutes=30))) == 1
    row = read_schedule(database, fired_id)
    assert row.enabled is False and row.next_run_at is None
    assert len(gateway.runs) == 1

    missed_id = insert_schedule(
        database, user_id, kind="once", interval_minutes=None, run_at=T0, next_run_at=T0
    )
    assert asyncio.run(runner.tick(T0 + timedelta(minutes=90))) == 0
    row = read_schedule(database, missed_id)
    assert row.enabled is False and row.next_run_at is None
    assert row.last_run_at is None
    assert len(gateway.runs) == 1  # no second run


def test_in_flight_previous_run_skips_the_tick(tmp_path):
    active_sessions: set[str] = {"api_prev"}
    runner, database, gateway, watches, user_id = make_unit_harness(
        tmp_path,
        is_active=lambda *, user_id, session_id: session_id in active_sessions,
    )
    schedule_id = insert_schedule(
        database, user_id, next_run_at=T0, last_run_session_id="api_prev"
    )

    # Previous run still watched → the tick is skipped, nothing changes.
    assert asyncio.run(runner.tick(T0 + timedelta(minutes=5))) == 0
    assert gateway.runs == []
    row = read_schedule(database, schedule_id)
    assert as_utc(row.next_run_at) == T0

    # The run completes (watch gone) → the next tick fires.
    active_sessions.clear()
    assert asyncio.run(runner.tick(T0 + timedelta(minutes=6))) == 1
    assert watches == [(user_id, "api_sess_1")]


def test_gateway_failure_leaves_schedule_due_for_retry(tmp_path):
    runner, database, gateway, watches, user_id = make_unit_harness(tmp_path)
    schedule_id = insert_schedule(database, user_id, next_run_at=T0)
    gateway.fail_next_create = 1

    assert asyncio.run(runner.tick(T0)) == 0
    row = read_schedule(database, schedule_id)
    assert as_utc(row.next_run_at) == T0  # untouched → still due
    assert row.last_run_at is None
    assert watches == []

    # Gateway recovers on the next tick (miss still under one period).
    assert asyncio.run(runner.tick(T0 + timedelta(minutes=1))) == 1
    assert len(gateway.runs) == 1


def test_unconfigured_gateway_skips_firing(tmp_path):
    runner, database, gateway, _, user_id = make_unit_harness(tmp_path)
    runner.get_gateway = lambda: None
    schedule_id = insert_schedule(database, user_id, next_run_at=T0)

    assert asyncio.run(runner.tick(T0)) == 0
    row = read_schedule(database, schedule_id)
    assert as_utc(row.next_run_at) == T0


def test_run_forever_uses_injected_clock_and_sleep(tmp_path):
    """The loop itself: fake sleep advances the fake clock — no real
    sleeps — and a due schedule fires on the tick that crosses it."""
    clock = FakeClock(T0)

    class FakeSleep:
        def __init__(self, limit: int) -> None:
            self.calls = 0
            self.limit = limit

        async def __call__(self, seconds: float) -> None:
            self.calls += 1
            if self.calls > self.limit:
                raise asyncio.CancelledError
            clock.now += timedelta(seconds=seconds)

    runner, database, gateway, _, user_id = make_unit_harness(tmp_path, clock=clock)
    sleep = FakeSleep(limit=3)
    runner.sleep = sleep
    insert_schedule(database, user_id, next_run_at=T0 + timedelta(seconds=90))

    with pytest.raises(asyncio.CancelledError):
        asyncio.run(runner.run_forever())

    # Tick cadence came from settings (60s); the schedule crossed its due
    # time on the second tick and fired exactly once across all ticks.
    assert sleep.calls == 4
    assert len(gateway.runs) == 1


# ---------------------------------------------------------------------------
# End-to-end: a fired run rides the EXISTING watch → completion push
# ---------------------------------------------------------------------------

def test_fired_run_delivers_completion_push_via_existing_watch(tmp_path):
    with scheduler_client(tmp_path) as client:
        apns, gateway, _ = install_stubs(client)
        register_data, headers = register_and_auth(client)
        register_push_token(client, headers["Authorization"].split(" ", 1)[1], register_data["deviceId"])

        create_schedule(client, headers, prompt="nightly digest", kind="interval", intervalMinutes=60)
        gateway.completed_replies["api_sess_1"] = "Digest ready: 3 items need attention."

        async def fire_and_settle() -> int:
            runner = client.app.state.schedule_runner
            fired = await runner.tick(T0 + timedelta(minutes=60))
            watchers = list(client.app.state.push_watchers.values())
            if watchers:
                await asyncio.gather(*watchers, return_exceptions=True)
            return fired

        assert asyncio.run(fire_and_settle()) == 1

        assert len(apns.alerts) == 1
        alert = apns.alerts[0]
        assert alert["title"] == "Hermes"
        assert "Digest ready" in alert["body"]
        assert alert["payload_extra"] == {"session_id": "api_sess_1"}
        # #47 lockstep: the Reply category rides scheduler-run completions too.
        assert alert["category"] == "HERMES_RUN_COMPLETED"
        # The watcher removed itself once it pushed.
        assert client.app.state.push_watchers == {}


# ---------------------------------------------------------------------------
# Additive migration — the production DB predates the schedules table
# ---------------------------------------------------------------------------

def test_additive_migration_on_existing_db_file(tmp_path):
    db_url = f"sqlite:///{tmp_path / 'pre-lane-g.db'}"
    settings = Settings(
        environment="test",
        public_base_url="http://testserver/v1",
        database_url=db_url,
        internal_api_key="test-internal-key",
    )

    # Build a "production" DB, then strip the Lane G surface to simulate a
    # file created before this change — every other table already populated.
    database = Database(db_url)
    database.create_all()
    with database.session() as db:
        user = ensure_default_user(db, settings)
        user_id = user.id
    with database.engine.begin() as connection:
        connection.execute(text("DROP INDEX IF EXISTS ix_schedules_enabled_next_run"))
        connection.execute(text("DROP TABLE schedules"))
    assert not inspect(database.engine).has_table("schedules")

    # A fresh boot on the existing file adds the table + index additively.
    reopened = Database(db_url)
    reopened.create_all()
    inspector = inspect(reopened.engine)
    assert inspector.has_table("schedules")
    index_names = {index["name"] for index in inspector.get_indexes("schedules")}
    assert "ix_schedules_enabled_next_run" in index_names

    # Existing rows survived, and the new table is usable.
    with reopened.session() as db:
        from app.models import User

        assert db.get(User, user_id) is not None
        db.add(Schedule(user_id=user_id, prompt="post-migration", kind="interval", interval_minutes=60))
        db.commit()
        assert db.scalar(select(Schedule).where(Schedule.prompt == "post-migration")) is not None

    # Idempotent: booting again over the migrated file is a no-op.
    Database(db_url).create_all()
