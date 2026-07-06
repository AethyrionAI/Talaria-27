from __future__ import annotations

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app, resolve_agent_file


# --- helpers (mirrors tests/test_api.py so this module stays self-contained) ---

def build_client(tmp_path, **overrides) -> TestClient:
    settings = Settings(
        environment="test",
        public_base_url="http://testserver/v1",
        database_url=f"sqlite:///{tmp_path / 'relay.db'}",
        internal_api_key="test-internal-key",
        **overrides,
    )
    return TestClient(create_app(settings))


def register_device(client: TestClient) -> dict:
    response = client.post(
        "/v1/device/register",
        json={
            "device": {
                "platform": "ios",
                "deviceName": "Test iPhone",
                "appVersion": "1.0.0",
                "buildNumber": "1",
                "bundleId": "io.hermesmobile.HermesMobile",
                "installationId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                "deviceModel": "iPhone17,2",
                "systemVersion": "26.4",
            },
            "client": {"environment": "development"},
        },
    )
    assert response.status_code == 200
    return response.json()["data"]


# --- resolve_agent_file: pure path-safety unit tests ---

def test_resolver_returns_file_inside_base(tmp_path):
    base = tmp_path / "MobileDL"
    base.mkdir()
    target = base / "report.md"
    target.write_text("# hi")

    # Relative request.
    assert resolve_agent_file("report.md", str(base)) == target.resolve()
    # Absolute request inside base.
    assert resolve_agent_file(str(target), str(base)) == target.resolve()


def test_resolver_rejects_traversal(tmp_path):
    base = tmp_path / "MobileDL"
    base.mkdir()
    secret = tmp_path / "secret.txt"
    secret.write_text("nope")

    # ../secret.txt escapes the base -> 404, not the file.
    with pytest.raises(HTTPException) as exc:
        resolve_agent_file("../secret.txt", str(base))
    assert exc.value.status_code == 404


def test_resolver_rejects_absolute_outside_base(tmp_path):
    base = tmp_path / "MobileDL"
    base.mkdir()
    outside = tmp_path / "other" / "x.txt"
    outside.parent.mkdir()
    outside.write_text("nope")

    with pytest.raises(HTTPException) as exc:
        resolve_agent_file(str(outside), str(base))
    assert exc.value.status_code == 404


def test_resolver_404_when_unconfigured_or_missing(tmp_path):
    base = tmp_path / "MobileDL"
    base.mkdir()

    # No agent_files_dir configured.
    with pytest.raises(HTTPException) as exc:
        resolve_agent_file("report.md", None)
    assert exc.value.status_code == 404

    # Configured, but file doesn't exist.
    with pytest.raises(HTTPException) as exc:
        resolve_agent_file("ghost.md", str(base))
    assert exc.value.status_code == 404

    # Directory (not a file) -> 404.
    with pytest.raises(HTTPException):
        resolve_agent_file(".", str(base))


# --- /v1/device/files route tests ---

def test_download_route_happy_path(tmp_path):
    files_dir = tmp_path / "MobileDL"
    files_dir.mkdir()
    (files_dir / "report.md").write_bytes(b"# Hermes report\nbody")

    with build_client(tmp_path, agent_files_dir=str(files_dir)) as client:
        token = register_device(client)["auth"]["accessToken"]
        response = client.get(
            "/v1/device/files",
            params={"path": "report.md"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 200
        assert response.text == "# Hermes report\nbody"
        assert "report.md" in response.headers.get("content-disposition", "")


def test_download_route_requires_auth(tmp_path):
    files_dir = tmp_path / "MobileDL"
    files_dir.mkdir()
    (files_dir / "report.md").write_bytes(b"x")

    with build_client(tmp_path, agent_files_dir=str(files_dir)) as client:
        response = client.get("/v1/device/files", params={"path": "report.md"})
        assert response.status_code == 401


def test_download_route_traversal_is_404(tmp_path):
    files_dir = tmp_path / "MobileDL"
    files_dir.mkdir()
    (tmp_path / "secret.txt").write_text("nope")

    with build_client(tmp_path, agent_files_dir=str(files_dir)) as client:
        token = register_device(client)["auth"]["accessToken"]
        response = client.get(
            "/v1/device/files",
            params={"path": "../secret.txt"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 404


def test_download_route_disabled_when_dir_unset(tmp_path):
    with build_client(tmp_path) as client:  # no agent_files_dir
        token = register_device(client)["auth"]["accessToken"]
        response = client.get(
            "/v1/device/files",
            params={"path": "report.md"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 404
