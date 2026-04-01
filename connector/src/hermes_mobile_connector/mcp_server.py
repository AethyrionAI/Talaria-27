"""MCP server exposing location and health sensor data to Hermes agents.

Run as:  hermes-mobile-mcp
Configure in ~/.hermes/config.yaml:
    mcp_servers:
      hermes_mobile:
        command: "/path/to/.venv/bin/hermes-mobile-mcp"
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from .sensor_store import (
    HEALTH_STALE_AFTER_SECONDS,
    LOCATION_STALE_AFTER_SECONDS,
    SensorStore,
    freshness_metadata,
)
from .state import ConnectorStateStore

mcp = FastMCP("hermes-mobile", instructions="Provides real-time location and health data from the user's phone.")


def _get_store() -> SensorStore:
    state_store = ConnectorStateStore()
    db_path = state_store.state_dir / "sensors.db"
    return SensorStore(db_path)


@mcp.tool()
def get_user_location() -> str:
    """Get the user's current location (latitude, longitude, address).

    Returns the most recent location reading from the user's phone.
    Use this when the user asks about their current location, wants
    nearby recommendations, or needs location-aware assistance.
    """
    store = _get_store()
    try:
        current = store.get_current_location()
        if current is None:
            return json.dumps({"error": "No location data available yet. The user's phone may not have sent a location update."})
        return json.dumps(
            {
                "latitude": current.latitude,
                "longitude": current.longitude,
                "altitude": current.altitude,
                "accuracy": current.accuracy,
                "address": current.address,
                **freshness_metadata(
                    recorded_at=current.recorded_at,
                    updated_at=current.updated_at,
                    stale_after_seconds=LOCATION_STALE_AFTER_SECONDS,
                ),
            }
        )
    finally:
        store.close()


@mcp.tool()
def get_location_history(since: str | None = None, limit: int = 50) -> str:
    """Get the user's recent location history.

    Returns a trail of location readings ordered newest first.
    Use this for queries like "where have I been today" or to understand
    the user's travel patterns.

    Args:
        since: ISO8601 timestamp to filter from (e.g. "2026-04-01T00:00:00Z")
        limit: Maximum number of entries to return (default 50)
    """
    store = _get_store()
    try:
        history = store.get_location_history(since=since, limit=limit)
        return json.dumps(
            {
                "locations": history,
                "count": len(history),
                "current": store.get_location_freshness(),
            }
        )
    finally:
        store.close()


@mcp.tool()
def get_health_summary() -> str:
    """Get a summary of all the user's latest health metrics.

    Returns current values for all tracked health metrics (steps, heart rate,
    calories, sleep, etc). Use this for general health queries or when the
    user asks about their overall health status.
    """
    store = _get_store()
    try:
        summary = store.get_health_summary()
        return json.dumps(summary)
    finally:
        store.close()


@mcp.tool()
def get_health_metric(metric: str, since: str | None = None, limit: int = 50) -> str:
    """Get time-series data for a specific health metric.

    Returns historical samples for the requested metric ordered newest first.
    Available metrics include: steps, heart_rate, resting_heart_rate, calories,
    active_calories, sleep_hours, distance_walking, distance_cycling, workouts.

    Args:
        metric: The metric name (e.g. "steps", "heart_rate", "sleep_hours")
        since: ISO8601 timestamp to filter from (e.g. "2026-04-01T00:00:00Z")
        limit: Maximum number of samples to return (default 50)
    """
    store = _get_store()
    try:
        samples = store.get_health_metric(metric, since=since, limit=limit)
        latest_freshness = store.get_metric_freshness(metric)
        return json.dumps(
            {
                "metric": metric,
                "samples": samples,
                "count": len(samples),
                "latest": latest_freshness,
            }
        )
    finally:
        store.close()


@mcp.tool()
def get_health_metrics_list() -> str:
    """List all available health metrics and their latest values.

    Returns the names of all health metrics that have been recorded,
    along with their most recent values. Use this to discover what
    health data is available before querying specific metrics.
    """
    store = _get_store()
    try:
        metrics = store.get_latest_metrics()
        return json.dumps(
            {
                "metrics": [
                    {
                        "metric": m.metric,
                        "value": m.value,
                        "unit": m.unit,
                        **freshness_metadata(
                            recorded_at=m.recorded_at,
                            updated_at=m.updated_at,
                            stale_after_seconds=HEALTH_STALE_AFTER_SECONDS,
                        ),
                    }
                    for m in metrics
                ],
                "count": len(metrics),
            }
        )
    finally:
        store.close()


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
