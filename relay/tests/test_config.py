from __future__ import annotations

from app.config import normalize_database_url


def test_normalize_database_url_maps_postgres_urls_to_psycopg():
    assert (
        normalize_database_url("postgresql://user:pass@db.example.com/app")
        == "postgresql+psycopg://user:pass@db.example.com/app"
    )
    assert (
        normalize_database_url("postgres://user:pass@db.example.com/app")
        == "postgresql+psycopg://user:pass@db.example.com/app"
    )
    # SQLite relative paths are now resolved to absolute (GH #59) so the DB
    # doesn't move when the process working directory changes.
    resolved = normalize_database_url("sqlite:///./relay.db")
    assert "relay.db" in resolved
    assert resolved.startswith("sqlite:///")
    assert not resolved.endswith("./relay.db"), f"Expected absolute path, got: {resolved}"
