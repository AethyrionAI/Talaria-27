"""Die-loudly process supervision seam (#113).

The connector is kept alive by an external supervisor (an NSSM service or
the scheduled-task watchdog committed at ``scripts/connector-watchdog.ps1``).
A supervisor can only restart what visibly dies: twice (2026-07-14 and
2026-07-16) the process ended without a final log line, and the only symptom
was sensor backlogs piling up on every paired device while the relay
202-busied each ingest.

This module makes every way the run loop can end loud and machine-readable:

* A deliberate stop (Ctrl+C / SIGINT) exits **0** — supervisors that honor
  exit codes must not treat a human stop as a crash.
* Everything else — an exception escaping the reconnect loop, event-loop
  death, silent task cancellation (``CancelledError`` is a ``BaseException``,
  so the loop's ``except Exception`` never sees it), or ``run_forever()``
  returning at all — logs a final ``FATAL: <reason>`` line with a traceback
  and exits **1** via ``sys.exit``.

Single-instance note: the enforcer lives in the OJAMD launcher
(``start-connector.bat``) and keys off the live process/port, not a lock
file. ``sys.exit`` here runs after ``asyncio.run`` has torn down the event
loop — the relay WebSocket is closed and its socket released — so a
supervisor-triggered relaunch is never blocked by a ghost instance.
"""

from __future__ import annotations

import asyncio
import logging
import sys
from typing import NoReturn, Protocol

# Same logger name as client.py so the FATAL line lands in the stream the
# connector already logs to.
logger = logging.getLogger("hermes.mobile.connector")


class _RunsForever(Protocol):
    async def run_forever(self) -> None: ...


def _ensure_fatal_is_visible() -> None:
    """Guarantee the FATAL line lands somewhere durable.

    The connector configures no logging handlers of its own; without one,
    logging's last-resort handler prints bare messages to stderr. That is
    enough for the bat/NSSM log redirection to capture, but a timestamp is
    exactly what the #113 forensics were missing — attach a real stderr
    handler (once) when nothing else is configured.
    """
    if logging.getLogger().handlers or logger.handlers:
        return
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
    logger.addHandler(handler)


def fatal_exit(reason: str, error: BaseException | None = None) -> NoReturn:
    """Log ``FATAL: <reason>`` (with traceback when available) and exit 1."""
    _ensure_fatal_is_visible()
    logger.critical("FATAL: %s", reason, exc_info=error)
    sys.exit(1)


def run_connector_until_stopped(connector: _RunsForever) -> int:
    """Run the connector's forever-loop; any end other than SIGINT is fatal.

    Returns 0 only for a deliberate stop. Every other outcome — including a
    clean return from ``run_forever()``, which must never happen — calls
    :func:`fatal_exit` so the process dies with a nonzero code and a final
    log line a supervisor (and a human reading the log) can act on.
    """
    try:
        asyncio.run(connector.run_forever())
    except KeyboardInterrupt:
        logger.info("Connector stopped by user (SIGINT).")
        return 0
    except BaseException as error:  # noqa: BLE001 — CancelledError/SystemExit included: nothing may die silently
        fatal_exit(f"connector run loop died — {type(error).__name__}: {error}", error)
    fatal_exit("connector run loop returned without an error — treating as a crash (the loop must never end on its own)")
