from __future__ import annotations

from hermes_mobile_connector.sensor_store import (
    HealthSample,
    LocationReading,
    SensorStore,
)


def make_store(tmp_path) -> SensorStore:
    return SensorStore(tmp_path / "sensors.db")


def test_store_and_retrieve_current_location(tmp_path):
    store = make_store(tmp_path)
    store.store_location(LocationReading(latitude=35.6762, longitude=139.6503, accuracy=10.0, address="Shibuya, Tokyo"))
    current = store.get_current_location()
    assert current is not None
    assert current.latitude == 35.6762
    assert current.longitude == 139.6503
    assert current.address == "Shibuya, Tokyo"


def test_current_location_is_overwritten(tmp_path):
    store = make_store(tmp_path)
    store.store_location(LocationReading(latitude=35.0, longitude=139.0))
    store.store_location(LocationReading(latitude=40.0, longitude=-74.0, address="New York"))
    current = store.get_current_location()
    assert current is not None
    assert current.latitude == 40.0
    assert current.address == "New York"


def test_location_history_returns_entries(tmp_path):
    store = make_store(tmp_path)
    store.store_location(LocationReading(latitude=35.0, longitude=139.0, recorded_at="2026-04-01T10:00:00Z"))
    store.store_location(LocationReading(latitude=36.0, longitude=140.0, recorded_at="2026-04-01T11:00:00Z"))
    store.store_location(LocationReading(latitude=37.0, longitude=141.0, recorded_at="2026-04-01T12:00:00Z"))

    history = store.get_location_history(limit=10)
    assert len(history) == 3
    # Most recent first
    assert history[0]["latitude"] == 37.0


def test_location_history_since_filter(tmp_path):
    store = make_store(tmp_path)
    store.store_location(LocationReading(latitude=35.0, longitude=139.0, recorded_at="2026-04-01T08:00:00Z"))
    store.store_location(LocationReading(latitude=36.0, longitude=140.0, recorded_at="2026-04-01T12:00:00Z"))

    history = store.get_location_history(since="2026-04-01T10:00:00Z")
    assert len(history) == 1
    assert history[0]["latitude"] == 36.0


def test_location_history_skips_near_duplicate_foreground_updates(tmp_path):
    store = make_store(tmp_path)
    store.store_location(LocationReading(latitude=35.0, longitude=139.0, accuracy=15.0, recorded_at="2026-04-01T08:00:00Z"))
    store.store_location(LocationReading(latitude=35.000001, longitude=139.000001, accuracy=17.0, recorded_at="2026-04-01T08:01:00Z"))

    history = store.get_location_history(limit=10)
    assert len(history) == 1


def test_store_and_retrieve_health_samples(tmp_path):
    store = make_store(tmp_path)
    samples = [
        HealthSample(metric="steps", value=4230, unit="count", start_at="2026-04-01T00:00:00Z", end_at="2026-04-01T10:00:00Z"),
        HealthSample(metric="heart_rate", value=72, unit="bpm", start_at="2026-04-01T10:00:00Z"),
    ]
    count = store.store_health_samples(samples)
    assert count == 2

    latest = store.get_latest_metrics()
    assert len(latest) == 2
    metrics = {m.metric: m for m in latest}
    assert metrics["steps"].value == 4230
    assert metrics["heart_rate"].value == 72


def test_health_latest_is_upserted(tmp_path):
    store = make_store(tmp_path)
    store.store_health_samples([HealthSample(metric="steps", value=1000, unit="count", start_at="2026-04-01T08:00:00Z")])
    store.store_health_samples([HealthSample(metric="steps", value=5000, unit="count", start_at="2026-04-01T12:00:00Z")])

    latest = store.get_latest_metrics()
    assert len(latest) == 1
    assert latest[0].value == 5000


def test_get_health_metric_history(tmp_path):
    store = make_store(tmp_path)
    store.store_health_samples([
        HealthSample(metric="steps", value=1000, unit="count", start_at="2026-04-01T06:00:00Z"),
        HealthSample(metric="steps", value=3000, unit="count", start_at="2026-04-01T12:00:00Z"),
        HealthSample(metric="heart_rate", value=72, unit="bpm", start_at="2026-04-01T12:00:00Z"),
    ])

    steps = store.get_health_metric("steps")
    assert len(steps) == 2
    assert steps[0]["value"] == 3000  # Most recent first

    hr = store.get_health_metric("heart_rate")
    assert len(hr) == 1


def test_windowed_health_samples_collapse_unchanged_snapshots(tmp_path):
    store = make_store(tmp_path)
    store.store_health_samples([
        HealthSample(metric="steps", value=1000, unit="count", start_at="2026-04-01T00:00:00Z", end_at="2026-04-01T10:00:00Z")
    ])
    store.store_health_samples([
        HealthSample(metric="steps", value=1000, unit="count", start_at="2026-04-01T00:00:00Z", end_at="2026-04-01T10:05:00Z")
    ])

    history = store.get_health_metric("steps")
    assert len(history) == 1
    assert history[0]["end_at"] == "2026-04-01T10:05:00Z"


def test_get_health_summary(tmp_path):
    store = make_store(tmp_path)
    store.store_health_samples([
        HealthSample(metric="steps", value=4230, unit="count", start_at="2026-04-01T10:00:00Z"),
        HealthSample(metric="heart_rate", value=72, unit="bpm", start_at="2026-04-01T10:00:00Z"),
    ])
    summary = store.get_health_summary()
    assert summary["count"] == 2
    assert summary["metrics"]["steps"]["value"] == 4230
    assert summary["metrics"]["heart_rate"]["unit"] == "bpm"
    assert "ageSeconds" in summary["metrics"]["steps"]


def test_no_current_location_returns_none(tmp_path):
    store = make_store(tmp_path)
    assert store.get_current_location() is None


def test_sensor_freshness_summary_reports_counts(tmp_path):
    store = make_store(tmp_path)
    store.store_location(LocationReading(latitude=35.0, longitude=139.0, recorded_at="2026-04-01T12:00:00Z"))
    store.store_health_samples([
        HealthSample(metric="heart_rate", value=72, unit="bpm", start_at="2026-04-01T12:00:00Z"),
    ])

    summary = store.get_sensor_freshness_summary()
    assert summary["location"] is not None
    assert summary["health"]["count"] == 1
