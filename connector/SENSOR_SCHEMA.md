# Hermes Mobile Sensor Database Schema

SQLite database at `~/.hermes-mobile/state/sensors.db` (WAL mode).

## Tables

### `location_current`
Single-row table (id=1) with the latest known location. Updated on every location delivery.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Always 1 |
| latitude | REAL | Decimal degrees |
| longitude | REAL | Decimal degrees |
| altitude | REAL | Meters above sea level |
| accuracy | REAL | Horizontal accuracy in meters |
| address | TEXT | Reverse-geocoded address (nullable) |
| recorded_at | TEXT | ISO 8601 timestamp from the device |
| updated_at | TEXT | ISO 8601 when the row was last written |

### `location_history`
Append-only trail of distinct locations. Near-duplicate readings are suppressed (~1m tolerance).

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT | UUID primary key |
| latitude, longitude, altitude, accuracy, address | | Same as location_current |
| recorded_at | TEXT | Device timestamp |
| created_at | TEXT | When the row was inserted |

Indexed on `recorded_at DESC`. Pruned after 90 days.

### `health_samples`
Time-series health readings from HealthKit.

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT | UUID primary key |
| metric | TEXT | e.g. "steps", "heart_rate", "sleep_duration" |
| value | REAL | Numeric value |
| unit | TEXT | e.g. "count", "bpm", "hours", "kcal" |
| start_at | TEXT | ISO 8601 start of measurement window |
| end_at | TEXT | ISO 8601 end (null for point-in-time readings) |
| source | TEXT | Always "healthkit" |
| created_at | TEXT | When inserted |

Indexed on `(metric, start_at DESC)`. Pruned after 90 days.

### `health_latest`
One row per metric with the most recent value. O(1) "current state" lookups.

| Column | Type | Description |
|--------|------|-------------|
| metric | TEXT | Primary key |
| value, unit | | Latest reading |
| recorded_at, start_at, end_at | TEXT | Timestamps |
| updated_at | TEXT | When last upserted |

### `health_daily`
Daily aggregates computed from `health_samples`. Populated automatically for completed days (not today).

| Column | Type | Description |
|--------|------|-------------|
| metric | TEXT | Metric name |
| date | TEXT | YYYY-MM-DD |
| sum_value | REAL | Sum of values for the day |
| avg_value | REAL | Average |
| min_value | REAL | Minimum |
| max_value | REAL | Maximum |
| count | INTEGER | Number of samples |
| unit | TEXT | Unit |
| updated_at | TEXT | Last rollup time |

Primary key: `(metric, date)`. Indexed on `date DESC`. Pruned after 90 days (same as raw samples).

**Rollup semantics:**
- Cumulative metrics (steps, calories, distance, workout_minutes, stand_hours, sleep_duration): `sum_value` = MAX of the day's snapshots (each snapshot is a running total)
- Point metrics (heart_rate, blood_oxygen, etc.): `sum_value` = NULL (sum is meaningless), `avg_value`/`min_value`/`max_value` are meaningful

## Available Metrics

| Metric | Unit | Query Style | Description |
|--------|------|-------------|-------------|
| steps | count | Cumulative today | Daily step count |
| active_calories | kcal | Cumulative today | Active energy burned |
| distance_walking | meters | Cumulative today | Walking + running distance |
| heart_rate | bpm | Latest sample (24h) | Most recent heart rate |
| resting_heart_rate | bpm | Latest sample (24h) | Resting heart rate |
| blood_oxygen | % | Latest sample (24h) | SpO2 |
| respiratory_rate | breaths/min | Latest sample (24h) | Breathing rate |
| body_mass | kg | Latest sample (7d) | Body weight |
| workout_minutes | minutes | Cumulative today | Apple Exercise Time |
| stand_hours | hours | Cumulative today | Standing time |
| sleep_duration | hours | Sum of asleep intervals ending that calendar day | Total sleep attributed to the wake-up day |

## MCP Tools

| Tool | Description |
|------|-------------|
| `get_user_location()` | Current location with freshness metadata |
| `get_location_history(since?, limit?)` | Location trail |
| `get_health_summary()` | All latest metric values |
| `get_health_metric(metric, since?, limit?)` | Time-series for one metric |
| `get_health_metrics_list()` | Available metrics with latest values |
| `get_sensor_schema()` | Full SQLite schema |
| `query_sensor_data(sql, limit?)` | Custom read-only SQL queries |

## Architecture Notes

The connector is a bridge: it receives sensor data via WebSocket from the relay and writes to SQLite. A future native Hermes iOS integration would:
1. Write to the same `sensors.db` schema directly (bypassing the relay/connector)
2. Expose the same MCP tool interface
3. Use the same table structure for web tools and dashboards
