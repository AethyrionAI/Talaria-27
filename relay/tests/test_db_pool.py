"""#86: engine pool hygiene + exhaustion/unhandled-exception visibility.

The 7/8 incident: `QueuePool limit of size 5 overflow 10 reached` twice,
plus a one-off `RuntimeError: 'NoneType' object has no attribute
'splitlines'` in an ASGI handler that surfaced with no usable traceback.
These tests pin the engine configuration and the middleware that gives
both failure classes full diagnostics.
"""

from __future__ import annotations

import logging

from fastapi.testclient import TestClient
from sqlalchemy.exc import TimeoutError as SAPoolTimeoutError

from app.config import Settings
from app.database import Database
from app.main import create_app


def make_settings(tmp_path, db_name="relay-pool.db"):
    return Settings(
        environment="test",
        public_base_url="https://relay.example.test/v1",
        database_url=f"sqlite:///{tmp_path / db_name}",
        internal_api_key="test-internal-key",
    )


def test_engine_pool_configured_with_pre_ping_and_recycle(tmp_path):
    database = Database(f"sqlite:///{tmp_path / 'pool-config.db'}")
    assert database.engine.pool._pre_ping is True
    assert database.engine.pool._recycle == 1800


def test_pool_status_reports_stats(tmp_path):
    database = Database(f"sqlite:///{tmp_path / 'pool-status.db'}")
    assert "Pool size" in database.pool_status()


def test_pool_timeout_logs_pool_stats_with_traceback(tmp_path, caplog):
    app = create_app(make_settings(tmp_path, "pool-timeout.db"))

    @app.get("/__test/pool-timeout")
    def boom() -> None:
        raise SAPoolTimeoutError("QueuePool limit of size 5 overflow 10 reached")

    with TestClient(app, raise_server_exceptions=False) as client:
        with caplog.at_level(logging.ERROR, logger="hermes.relay"):
            response = client.get("/__test/pool-timeout")

    assert response.status_code == 500
    record = next(r for r in caplog.records if "DB pool exhausted" in r.getMessage())
    assert "Pool size" in record.getMessage()
    assert record.exc_info is not None


def test_unhandled_exception_logs_route_and_traceback(tmp_path, caplog):
    app = create_app(make_settings(tmp_path, "pool-unhandled.db"))

    @app.get("/__test/none-splitlines")
    def boom() -> None:
        payload = None
        payload.splitlines()  # the 7/8 one-off, minus the mystery

    with TestClient(app, raise_server_exceptions=False) as client:
        with caplog.at_level(logging.ERROR, logger="hermes.relay"):
            response = client.get("/__test/none-splitlines")

    assert response.status_code == 500
    record = next(r for r in caplog.records if "Unhandled exception" in r.getMessage())
    assert "/__test/none-splitlines" in record.getMessage()
    assert record.exc_info is not None


def test_http_exceptions_do_not_hit_the_error_log(tmp_path, caplog):
    app = create_app(make_settings(tmp_path, "pool-404.db"))

    with TestClient(app) as client:
        with caplog.at_level(logging.ERROR, logger="hermes.relay"):
            response = client.get("/v1/hosts/current")  # 401: no bearer token

    assert response.status_code == 401
    assert not [r for r in caplog.records if "Unhandled exception" in r.getMessage()]
