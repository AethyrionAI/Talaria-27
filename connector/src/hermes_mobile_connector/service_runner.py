from __future__ import annotations

import asyncio
import os
from pathlib import Path
import sys

from .client import HermesMobileConnector
from .state import ConnectorStateStore


def run_from_state_dir(state_dir: str) -> int:
    state_store = ConnectorStateStore(state_dir=Path(state_dir))
    state = state_store.load()
    if state.runtime_config is not None and state.runtime_config.hermes_home:
        os.environ["HERMES_HOME"] = state.runtime_config.hermes_home
    connector = HermesMobileConnector(state_store=state_store)
    try:
        asyncio.run(connector.run_forever())
    except KeyboardInterrupt:
        return 0
    return 0


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if len(args) != 1:
        raise SystemExit("Usage: hermes-mobile-service-runner <connector-state-dir>")
    return run_from_state_dir(args[0])


if __name__ == "__main__":
    raise SystemExit(main())
