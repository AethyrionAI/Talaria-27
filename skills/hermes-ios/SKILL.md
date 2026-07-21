---
name: hermes-ios
description: Access real-time iOS sensor data — location, health metrics, activity detection, and custom queries from the user's iPhone.
version: 1.0.0
author: Hermes iOS
license: MIT
platforms: [macos, linux]
metadata:
  hermes:
    tags: [ios, mobile, location, health, sensors, context]
    related_skills: [find-nearby]
---

> Tool names use Hermes's native-MCP convention: the connector's server is
> registered as `hermes_mobile`, so every tool appears to the agent as
> `mcp__hermes_mobile__<tool>`. (config.yaml `tools.include` still uses BARE
> names — the filter runs pre-prefixing.)


# Hermes iOS Context

Access real-time sensor data from the user's iPhone via the Hermes Mobile MCP server. This skill provides location awareness, health metrics, activity detection, and custom sensor queries.

## When to Use

Use this skill when:
- The user asks about their **location** ("where am I?", "how far am I from...?")
- The user asks about **health or fitness** ("how many steps today?", "how did I sleep?", "what's my heart rate?")
- The user asks about **activity** ("am I walking?", "what am I doing?")
- The user wants **location history** ("where have I been today?", "show my travel today")
- The user wants **health trends** ("steps this week", "sleep over the last 7 days")
- You need **contextual awareness** to tailor responses (e.g., shorter answers if walking, health nudges if sedentary)

Do NOT use this skill for:
- General knowledge questions unrelated to the user's device data
- Tasks that don't benefit from location/health context

## Available Tools

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `mcp__hermes_mobile__get_user_location` | Current location with address | "Where am I?", nearby queries |
| `mcp__hermes_mobile__get_location_history` | Recent location trail | "Where have I been?", travel patterns |
| `mcp__hermes_mobile__get_health_summary` | All latest health metrics | "How's my health?", general wellness |
| `mcp__hermes_mobile__get_health_metric` | Time-series for one metric | "Steps this week", "sleep last 3 days" |
| `mcp__hermes_mobile__get_health_metrics_list` | Available metrics + latest values | Discovering what data exists |
| `mcp__hermes_mobile__get_user_activity` | Current physical activity | "Am I walking?", context adaptation |
| `mcp__hermes_mobile__get_sensor_schema` | Database table structure | Before writing custom queries |
| `mcp__hermes_mobile__query_sensor_data` | Custom SQL against sensor DB | Complex analysis, correlations, trends |

## Quick Patterns

### Location

```
# Current location
→ call mcp__hermes_mobile__get_user_location

# Location history for today
→ call mcp__hermes_mobile__get_location_history with since="2026-04-08T00:00:00Z"

# Custom location query
→ call mcp__hermes_mobile__query_sensor_data with sql="SELECT address, recorded_at FROM location_history WHERE recorded_at > datetime('now', '-6 hours') ORDER BY recorded_at DESC"
```

### Health

```
# Quick health check
→ call mcp__hermes_mobile__get_health_summary

# Specific metric with history
→ call mcp__hermes_mobile__get_health_metric with metric="steps"

# Weekly sleep trend
→ call mcp__hermes_mobile__get_health_metric with metric="sleep_duration" since="2026-04-01T00:00:00Z"

# Cross-metric correlation
→ call mcp__hermes_mobile__query_sensor_data with sql="SELECT date(start_at) as day, metric, SUM(value) as total FROM health_samples WHERE metric IN ('steps', 'active_calories') AND start_at > datetime('now', '-7 days') GROUP BY day, metric ORDER BY day"
```

### Activity

```
# What's the user doing right now?
→ call mcp__hermes_mobile__get_user_activity
# Returns: stationary, walking, running, automotive, cycling, or unknown
```

## Health Metrics Reference

| Metric | Unit | Description |
|--------|------|-------------|
| `steps` | count | Daily step count |
| `active_calories` | kcal | Calories burned from activity |
| `distance_walking` | meters | Walking + running distance |
| `heart_rate` | bpm | Most recent heart rate |
| `resting_heart_rate` | bpm | Resting heart rate (daily) |
| `blood_oxygen` | % | SpO2 percentage |
| `respiratory_rate` | breaths/min | Breathing rate |
| `body_mass` | kg | Body weight |
| `workout_minutes` | minutes | Active workout time |
| `stand_hours` | hours | Hours with standing activity |
| `sleep_duration` | hours | Total sleep (attributed to wake-up day) |

## Freshness

Every tool response includes freshness metadata:
- `recordedAt` — when the sensor recorded the value
- `updatedAt` — when the connector received it
- `isFresh` — true if within the expected update window
- `ageSeconds` — seconds since recording

**Stale data guidelines:**
- Location older than 10 minutes: mention it may not be current
- Health metrics older than 1 hour: note the data age
- Activity older than 15 minutes: note it may have changed

## Sensor Database Schema

The `mcp__hermes_mobile__query_sensor_data` tool runs read-only SQL against these tables:

| Table | Contents |
|-------|----------|
| `location_current` | Single row with latest location + address |
| `location_history` | Time-series of all location updates |
| `health_samples` | Raw health metric samples with timestamps |
| `health_latest` | Most recent value per metric |
| `health_daily` | Daily aggregated health metrics |

Use `mcp__hermes_mobile__get_sensor_schema` to see exact column definitions before writing queries.

## Context-Aware Response Adaptation

When you have activity and location context, adapt your responses:

- **Walking/Running**: Keep responses brief and voice-friendly
- **Driving (automotive)**: Audio-only responses, no links or code
- **Stationary at home**: Full detailed responses with formatting
- **Late night + poor sleep**: Consider suggesting rest
- **High step count milestone**: Acknowledge the achievement

## Pitfalls

- **No data yet**: If the user just installed the app, sensor data may be empty. Say so clearly rather than guessing.
- **Stale location**: Always check freshness. A 2-hour-old location isn't "where they are now."
- **Health permissions**: Some metrics require Apple Watch. Missing metrics doesn't mean an error — the user may not have the hardware.
- **SQL injection**: `mcp__hermes_mobile__query_sensor_data` uses a read-only SQLite connection. Only SELECT statements are allowed. Don't worry about writes — they're blocked at the database level.
