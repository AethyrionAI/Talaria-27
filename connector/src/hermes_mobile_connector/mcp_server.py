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

import httpx
from mcp.server.fastmcp import FastMCP

from .sensor_store import (
    HEALTH_STALE_AFTER_SECONDS,
    LOCATION_STALE_AFTER_SECONDS,
    SensorStore,
    freshness_metadata,
)
from .state import ConnectorStateStore

mcp = FastMCP(
    "hermes-mobile",
    instructions=(
        "Provides real-time location and health data from the user's phone, "
        "and an outbound inbox channel to send the user items (approvals, "
        "notifications, reminders) they act on from the Talaria app."
    ),
)


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
    Available metrics: steps, active_calories, distance_walking, heart_rate,
    resting_heart_rate, blood_oxygen, respiratory_rate, body_mass,
    workout_minutes, stand_hours, sleep_duration.

    Args:
        metric: The metric name (e.g. "steps", "heart_rate", "sleep_duration")
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


ACTIVITY_LABELS = {0: "stationary", 1: "walking", 2: "running", 3: "automotive", 4: "cycling", 5: "unknown"}


@mcp.tool()
def get_user_activity() -> str:
    """Get the user's current physical activity (stationary, walking, running, driving, cycling).

    Returns the latest activity classification from the device's motion sensors,
    with freshness metadata. Stale if older than 15 minutes.
    """
    store = _get_store()
    try:
        row = store._read_conn.execute(
            "SELECT * FROM health_latest WHERE metric = 'user_activity'"
        ).fetchone()
        if row is None:
            return json.dumps({"activity": "unknown", "available": False})
        activity_code = int(row["value"])
        label = ACTIVITY_LABELS.get(activity_code, "unknown")
        meta = freshness_metadata(
            recorded_at=row["recorded_at"],
            updated_at=row["updated_at"],
            stale_after_seconds=LOCATION_STALE_AFTER_SECONDS,
        )
        return json.dumps({"activity": label, "activityCode": activity_code, **meta})
    finally:
        store.close()


@mcp.tool()
def get_sensor_schema() -> str:
    """Return the SQLite schema for the sensor database.

    Shows all table definitions, column types, and indexes.
    Use this to understand the data structure before writing
    custom queries with query_sensor_data.
    """
    store = _get_store()
    try:
        conn = store._conn
        cursor = conn.execute(
            "SELECT sql FROM sqlite_master WHERE type IN ('table', 'index') AND sql IS NOT NULL ORDER BY type, name"
        )
        statements = [row[0] for row in cursor.fetchall()]
        return json.dumps({"schema": statements})
    finally:
        store.close()


@mcp.tool()
def query_sensor_data(sql: str, limit: int = 100) -> str:
    """Run a read-only SQL query against the sensor database.

    Use this for custom analysis, trend queries, aggregations, or
    building dashboards. The database contains tables: location_current,
    location_history, health_samples, health_latest, health_daily.

    Args:
        sql: A SELECT query. Only SELECT statements are allowed.
        limit: Maximum rows to return (default 100, max 1000).

    Example queries:
        - "SELECT metric, AVG(value) FROM health_samples WHERE metric='steps' GROUP BY date(start_at)"
        - "SELECT * FROM location_history ORDER BY recorded_at DESC LIMIT 10"
        - "SELECT metric, value, unit FROM health_latest"
    """
    # Safety checks
    stripped = sql.strip().upper()
    if not stripped.startswith("SELECT"):
        return json.dumps({"error": "Only SELECT queries are allowed."})

    forbidden = {"DROP", "DELETE", "INSERT", "UPDATE", "ALTER", "CREATE", "ATTACH", "DETACH", "PRAGMA"}
    first_words = set(stripped.split()[:3])
    if first_words & forbidden:
        return json.dumps({"error": "Destructive or administrative statements are not allowed."})

    effective_limit = min(max(limit, 1), 1000)

    store = _get_store()
    try:
        # Open a separate read-only connection for user queries.
        # Even if the SQL contains injection (DROP, INSERT, ATTACH, etc.),
        # the read-only mode prevents any writes at the SQLite level.
        import sqlite3
        ro_conn = sqlite3.connect(f"file:{store.db_path}?mode=ro", uri=True)
        ro_conn.row_factory = sqlite3.Row
        try:
            safe_sql = f"SELECT * FROM ({sql.rstrip().rstrip(';')}) LIMIT {effective_limit}"
            cursor = ro_conn.execute(safe_sql)
            columns = [desc[0] for desc in cursor.description] if cursor.description else []
            rows = cursor.fetchall()
            return json.dumps({
                "columns": columns,
                "rows": [dict(zip(columns, row)) for row in rows],
                "count": len(rows),
            })
        finally:
            ro_conn.close()
    except Exception as e:
        return json.dumps({"error": str(e)})
    finally:
        store.close()


# ---------------------------------------------------------------------------
# Agent → phone: inbox producer (#45)
#
# The relay's inbox routes and the finished iOS Inbox UI shipped end-to-end
# with no producer — these two tools are the missing writer half. They call
# the relay's internal routes, which require the relay's INTERNAL_API_KEY
# (NOT the connector credential): set `internal_api_key` in
# ~/.hermes-mobile/secrets.json or export HERMES_MOBILE_INTERNAL_API_KEY.
# ---------------------------------------------------------------------------

INBOX_KINDS = {"approval", "notification", "reminder", "suggestion", "alert"}
INBOX_PRIORITIES = {"low", "normal", "high", "urgent"}
NOTIFY_MODES = {"silent", "alert", "none"}


def relay_root_url(relay_url: str) -> str:
    """The relay's server root. Connector state stores the /v1 API base
    (e.g. "https://relay.example/v1"); the internal routes live at the root.
    """
    trimmed = relay_url.rstrip("/")
    return trimmed[: -len("/v1")] if trimmed.endswith("/v1") else trimmed


def _internal_api_key() -> str | None:
    env_key = os.getenv("HERMES_MOBILE_INTERNAL_API_KEY") or os.getenv("INTERNAL_API_KEY")
    if env_key:
        return env_key
    return ConnectorStateStore().load_secrets().internal_api_key


@mcp.tool()
def send_inbox_item(
    title: str,
    body: str,
    kind: str = "notification",
    priority: str = "normal",
    notify: str = "silent",
) -> str:
    """Send an item to the user's phone Inbox (the agent → phone channel).

    The item appears in the Talaria app's Inbox where the user can act on it
    (approvals get Approve/Dismiss; other kinds get Open/Dismiss). Use this
    for anything that should outlive the current conversation: asking the
    user to authorize something, surfacing a reminder, or flagging something
    that needs attention. Check the user's verdict later with
    get_inbox_verdict.

    Args:
        title: Short headline shown in the inbox row.
        body: The full item text.
        kind: One of "approval", "notification", "reminder", "suggestion",
            "alert" (default "notification"). Use "approval" when you need an
            explicit Approve/Dismiss decision.
        priority: One of "low", "normal", "high", "urgent" (default "normal").
        notify: How to announce it — "silent" (default: background push wakes
            the app so the item is waiting), "alert" (visible notification
            with the title/body), or "none" (item appears on next app open).

    Returns JSON with the created item's id (save it for get_inbox_verdict)
    and whether a push was sent.
    """
    if kind not in INBOX_KINDS:
        return json.dumps({"error": f"Invalid kind '{kind}'. Use one of: {sorted(INBOX_KINDS)}"})
    if priority not in INBOX_PRIORITIES:
        return json.dumps({"error": f"Invalid priority '{priority}'. Use one of: {sorted(INBOX_PRIORITIES)}"})
    if notify not in NOTIFY_MODES:
        return json.dumps({"error": f"Invalid notify mode '{notify}'. Use one of: {sorted(NOTIFY_MODES)}"})

    internal_key = _internal_api_key()
    if not internal_key:
        return json.dumps(
            {
                "error": (
                    "No relay internal key configured. Set internal_api_key in "
                    "~/.hermes-mobile/secrets.json to the relay's INTERNAL_API_KEY, "
                    "or export HERMES_MOBILE_INTERNAL_API_KEY."
                )
            }
        )

    try:
        state = ConnectorStateStore().load()
    except RuntimeError as exc:
        return json.dumps({"error": str(exc)})

    root = relay_root_url(state.relay_url)
    headers = {"X-Relay-Internal-Key": internal_key}

    try:
        with httpx.Client(timeout=15.0) as client:
            response = client.post(
                f"{root}/internal/inbox/create",
                headers=headers,
                json={"kind": kind, "title": title, "body": body, "priority": priority},
            )
            response.raise_for_status()
            item = response.json()["data"]["item"]

            push: dict[str, object] = {"requested": notify}
            if notify != "none":
                if state.user_id:
                    push_body: dict[str, object] = {"user_id": state.user_id, "type": notify}
                    if notify == "alert":
                        push_body["title"] = title
                        push_body["body"] = body
                    push_response = client.post(
                        f"{root}/v1/push/send", headers=headers, json=push_body
                    )
                    # Best-effort: 503 = APNs not configured on the relay; the
                    # item still lands and surfaces on the next app open.
                    if push_response.status_code == 200:
                        push["sent"] = push_response.json().get("data", {}).get("sent", 0)
                    else:
                        push["error"] = f"HTTP {push_response.status_code}"
                else:
                    push["error"] = "connector state has no user_id — re-run setup to enable push"

            return json.dumps(
                {
                    "itemId": str(item["id"]),
                    "status": item.get("status"),
                    "kind": kind,
                    "push": push,
                    "next": "Call get_inbox_verdict with this itemId to read the user's decision.",
                }
            )
    except httpx.HTTPStatusError as exc:
        return json.dumps({"error": f"Relay rejected the item: HTTP {exc.response.status_code} {exc.response.text[:200]}"})
    except httpx.HTTPError as exc:
        return json.dumps({"error": f"Could not reach the relay: {exc}"})


@mcp.tool()
def get_inbox_verdict(item_id: str) -> str:
    """Read the user's verdict on an inbox item sent with send_inbox_item.

    Returns the actions the user has taken on the item ("approve", "open",
    "dismiss", ...), newest first. An empty list means the user hasn't acted
    yet — the item is still pending in their Inbox.

    Args:
        item_id: The itemId returned by send_inbox_item.
    """
    internal_key = _internal_api_key()
    if not internal_key:
        return json.dumps(
            {
                "error": (
                    "No relay internal key configured. Set internal_api_key in "
                    "~/.hermes-mobile/secrets.json to the relay's INTERNAL_API_KEY, "
                    "or export HERMES_MOBILE_INTERNAL_API_KEY."
                )
            }
        )

    try:
        state = ConnectorStateStore().load()
    except RuntimeError as exc:
        return json.dumps({"error": str(exc)})

    root = relay_root_url(state.relay_url)
    try:
        with httpx.Client(timeout=15.0) as client:
            response = client.get(
                f"{root}/internal/inbox/{item_id}/actions",
                headers={"X-Relay-Internal-Key": internal_key},
            )
            response.raise_for_status()
            actions = response.json()["data"]["actions"]
            return json.dumps(
                {
                    "itemId": item_id,
                    "actions": actions,
                    "pending": len(actions) == 0,
                }
            )
    except httpx.HTTPStatusError as exc:
        return json.dumps({"error": f"Relay rejected the lookup: HTTP {exc.response.status_code} {exc.response.text[:200]}"})
    except httpx.HTTPError as exc:
        return json.dumps({"error": f"Could not reach the relay: {exc}"})


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
