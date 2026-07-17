from __future__ import annotations

import os
from pathlib import Path
import sys

from .client import HermesMobileConnector
from .state import ConnectorStateStore
from .supervision import fatal_exit, run_connector_until_stopped


def run_from_state_dir(state_dir: str) -> int:
    # #113: startup failures (missing/corrupt state.json, bad runtime config)
    # must be as loud as run-loop deaths — a supervisor restarting on nonzero
    # exit needs the FATAL line to say why the restarts keep failing.
    try:
        state_store = ConnectorStateStore(state_dir=Path(state_dir))
        state = state_store.load()
        if state.runtime_config is not None and state.runtime_config.hermes_home:
            os.environ["HERMES_HOME"] = state.runtime_config.hermes_home
        connector = HermesMobileConnector(state_store=state_store)
    except Exception as error:  # noqa: BLE001
        fatal_exit(f"connector startup failed — {type(error).__name__}: {error}", error)
    return run_connector_until_stopped(connector)


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if len(args) != 1:
        raise SystemExit("Usage: hermes-mobile-service-runner <connector-state-dir>")
    return run_from_state_dir(args[0])


if __name__ == "__main__":
    raise SystemExit(main())
