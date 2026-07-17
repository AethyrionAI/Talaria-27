"""#113 die-loudly supervision: every death is a nonzero exit + a FATAL log line.

No network, no real state: fake connectors raise (or return) through the real
entry paths and the tests assert the exit code and the final log line a
supervisor depends on.
"""

from __future__ import annotations

import asyncio
import logging

import pytest

from hermes_mobile_connector import cli, service_runner
from hermes_mobile_connector.state import ConnectorState, ConnectorStateStore
from hermes_mobile_connector.supervision import run_connector_until_stopped


class FakeConnector:
    """Stands in for HermesMobileConnector — run_forever ends however the test says."""

    def __init__(self, outcome: BaseException | None = None):
        self.outcome = outcome

    async def run_forever(self) -> None:
        if self.outcome is not None:
            raise self.outcome


def assert_fatal_logged(caplog: pytest.LogCaptureFixture, fragment: str) -> None:
    fatal_lines = [r for r in caplog.records if r.levelno == logging.CRITICAL and r.getMessage().startswith("FATAL: ")]
    assert fatal_lines, "expected a FATAL log line"
    assert fragment in fatal_lines[-1].getMessage()


def test_unhandled_exception_exits_nonzero_with_fatal_line(caplog):
    with pytest.raises(SystemExit) as exit_info:
        run_connector_until_stopped(FakeConnector(RuntimeError("relay handshake exploded")))
    assert exit_info.value.code == 1
    assert_fatal_logged(caplog, "relay handshake exploded")
    assert_fatal_logged(caplog, "RuntimeError")


def test_cancelled_error_is_not_a_silent_death(caplog):
    # CancelledError is a BaseException — the run loop's `except Exception`
    # can never absorb it, so it must land here as a loud death.
    with pytest.raises(SystemExit) as exit_info:
        run_connector_until_stopped(FakeConnector(asyncio.CancelledError()))
    assert exit_info.value.code == 1
    assert_fatal_logged(caplog, "CancelledError")


def test_clean_return_from_run_forever_is_a_crash(caplog):
    # run_forever is an infinite loop; returning at all IS the silent-death
    # shape the two incidents had. It must exit nonzero, not 0.
    with pytest.raises(SystemExit) as exit_info:
        run_connector_until_stopped(FakeConnector(None))
    assert exit_info.value.code == 1
    assert_fatal_logged(caplog, "returned without an error")


def test_zero_system_exit_from_inside_the_loop_is_made_loud(caplog):
    # A stray SystemExit(0) escaping the loop would otherwise be the perfect
    # silent death: process gone, exit code says "fine".
    with pytest.raises(SystemExit) as exit_info:
        run_connector_until_stopped(FakeConnector(SystemExit(0)))
    assert exit_info.value.code == 1
    assert_fatal_logged(caplog, "SystemExit")


def test_keyboard_interrupt_is_a_deliberate_stop(caplog):
    caplog.set_level(logging.INFO, logger="hermes.mobile.connector")
    assert run_connector_until_stopped(FakeConnector(KeyboardInterrupt())) == 0
    assert not any(r.levelno == logging.CRITICAL for r in caplog.records)


def test_cli_run_foreground_dies_loudly(caplog, capsys):
    with pytest.raises(SystemExit) as exit_info:
        cli._run_foreground(FakeConnector(ValueError("ws loop fell over")))
    assert exit_info.value.code == 1
    assert_fatal_logged(caplog, "ws loop fell over")


def test_service_runner_dies_loudly_on_run_loop_death(tmp_path, monkeypatch, caplog):
    store = ConnectorStateStore(state_dir=tmp_path)
    store.save(
        ConnectorState(
            relay_url="https://relay.example.com/v1",
            web_socket_url="wss://relay.example.com/v1/hosts/ws",
            user_id="user-123",
            host_id="host-123",
            connector_credential="secret",
        )
    )

    async def doomed_run_forever(self) -> None:
        raise OSError("event loop died")

    monkeypatch.setattr("hermes_mobile_connector.client.HermesMobileConnector.run_forever", doomed_run_forever)
    with pytest.raises(SystemExit) as exit_info:
        service_runner.run_from_state_dir(str(tmp_path))
    assert exit_info.value.code == 1
    assert_fatal_logged(caplog, "event loop died")


def test_service_runner_dies_loudly_on_startup_failure(tmp_path, caplog):
    # Empty state dir: load() raises before the loop ever starts. The
    # supervisor restarting on nonzero exit needs the log to say why the
    # restarts keep failing.
    with pytest.raises(SystemExit) as exit_info:
        service_runner.run_from_state_dir(str(tmp_path / "missing"))
    assert exit_info.value.code == 1
    assert_fatal_logged(caplog, "startup failed")
