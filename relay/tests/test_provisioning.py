from __future__ import annotations

import time

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.services import sanitize_provisioning_descriptor


# --- helpers (mirrors tests/test_hosts.py so this module stays self-contained) ---

DESCRIPTOR = {
    "shim_base_url": "http://100.79.222.100:8765",
    "shim_token": "shim-token-abc",
    "gateway_base_url": "http://100.79.222.100:8642",
}


def build_client(tmp_path) -> TestClient:
    settings = Settings(
        environment="test",
        public_base_url="https://relay.example.test/v1",
        database_url=f"sqlite:///{tmp_path / 'relay-provisioning.db'}",
        internal_api_key="test-internal-key",
        hermes_adapter="connector",
        connector_heartbeat_timeout_seconds=5,
        connector_idle_poll_interval_seconds=0.1,
    )
    return TestClient(create_app(settings))


def setup_connector(client: TestClient) -> dict:
    response = client.post(
        "/v1/connector/setup",
        json={
            "ownerDisplayName": "Taylor",
            "hostDisplayName": "Home Mac mini",
            "connector": {
                "platform": "macos",
                "hostname": "test-host",
                "connectorVersion": "0.1.0",
                "hermesCommand": "/usr/local/bin/hermes",
                "hermesVersion": "hermes 1.2.3",
            },
        },
    )
    assert response.status_code == 200
    return response.json()["data"]


def pair_phone(client: TestClient, connector_credential: str, installation_id: str) -> dict:
    code_response = client.post(
        "/v1/connector/phone-pairing-codes",
        headers={"Authorization": f"Bearer {connector_credential}"},
    )
    assert code_response.status_code == 200
    redeem_response = client.post(
        "/v1/phone-pairing/redeem",
        json={
            "code": code_response.json()["data"]["code"],
            "device": {
                "platform": "ios",
                "deviceName": "Taylor's iPhone",
                "appVersion": "1.0.0",
                "buildNumber": "1",
                "bundleId": "io.hermesmobile.HermesMobile",
                "installationId": installation_id,
                "deviceModel": "iPhone17,2",
                "systemVersion": "26.2",
            },
            "client": {"environment": "production"},
        },
    )
    assert redeem_response.status_code == 200
    return redeem_response.json()["data"]


def send_hello(websocket, provisioning: dict | None, *, include_provisioning: bool = True) -> None:
    message: dict = {
        "type": "hello",
        "connector": {
            "platform": "macos",
            "hostname": "test-host",
            "connectorVersion": "0.1.0",
            "hermesCommand": "/usr/local/bin/hermes",
            "hermesVersion": "hermes 1.2.3",
            "displayName": "Home Mac mini",
        },
    }
    if include_provisioning:
        message["provisioning"] = provisioning
    websocket.send_json(message)
    assert websocket.receive_json()["type"] == "ready"


def get_provisioning(client: TestClient, access_token: str) -> dict:
    response = client.get(
        "/v1/device/provisioning",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert response.status_code == 200
    return response.json()["data"]


# --- endpoint auth ---


def test_provisioning_endpoint_requires_auth(tmp_path):
    with build_client(tmp_path) as client:
        response = client.get("/v1/device/provisioning")
        assert response.status_code == 401

        bad_bearer = client.get(
            "/v1/device/provisioning",
            headers={"Authorization": "Bearer not-a-real-token"},
        )
        assert bad_bearer.status_code == 401


# --- round trip: connector hello -> stored -> device fetch ---


def test_provisioning_round_trip_survives_connector_disconnect(tmp_path):
    with build_client(tmp_path) as client:
        connector_data = setup_connector(client)
        access_token = pair_phone(
            client, connector_data["connectorCredential"], "11111111-1111-1111-1111-111111111111"
        )["auth"]["accessToken"]

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {connector_data['connectorCredential']}"},
        ) as websocket:
            send_hello(websocket, DESCRIPTOR)

        # Fetch AFTER the websocket closed: the descriptor must be DB-backed,
        # not connection-scoped (the #24f lesson).
        data = get_provisioning(client, access_token)
        assert data["provisioning"] == {
            "shimBaseURL": "http://100.79.222.100:8765",
            "shimToken": "shim-token-abc",
            "gatewayBaseURL": "http://100.79.222.100:8642",
        }
        assert data["updatedAt"] is not None


def test_provisioning_empty_shape_before_connector_reports(tmp_path):
    with build_client(tmp_path) as client:
        connector_data = setup_connector(client)
        access_token = pair_phone(
            client, connector_data["connectorCredential"], "22222222-2222-2222-2222-222222222222"
        )["auth"]["accessToken"]

        data = get_provisioning(client, access_token)
        assert data["provisioning"] == {
            "shimBaseURL": None,
            "shimToken": None,
            "gatewayBaseURL": None,
        }
        assert data["updatedAt"] is None


def test_provisioning_empty_shape_without_any_host(tmp_path):
    with build_client(tmp_path) as client:
        register = client.post(
            "/v1/device/register",
            json={
                "device": {
                    "platform": "ios",
                    "deviceName": "Test iPhone",
                    "appVersion": "1.0.0",
                    "buildNumber": "1",
                    "bundleId": "io.hermesmobile.HermesMobile",
                    "installationId": "33333333-3333-3333-3333-333333333333",
                    "deviceModel": "iPhone17,2",
                    "systemVersion": "26.4",
                },
                "client": {"environment": "development"},
            },
        )
        assert register.status_code == 200
        access_token = register.json()["data"]["auth"]["accessToken"]

        data = get_provisioning(client, access_token)
        assert data["provisioning"] == {
            "shimBaseURL": None,
            "shimToken": None,
            "gatewayBaseURL": None,
        }
        assert data["updatedAt"] is None


# --- refresh semantics ---


def test_provisioning_update_message_rotates_descriptor(tmp_path):
    with build_client(tmp_path) as client:
        connector_data = setup_connector(client)
        access_token = pair_phone(
            client, connector_data["connectorCredential"], "44444444-4444-4444-4444-444444444444"
        )["auth"]["accessToken"]

        rotated = dict(DESCRIPTOR, shim_token="shim-token-rotated")
        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {connector_data['connectorCredential']}"},
        ) as websocket:
            send_hello(websocket, DESCRIPTOR)
            websocket.send_json({"type": "provisioning.update", "provisioning": rotated})

            # The update is handled by the server's idle loop; poll briefly
            # instead of guessing at its scheduling.
            deadline = time.monotonic() + 5.0
            while time.monotonic() < deadline:
                data = get_provisioning(client, access_token)
                if data["provisioning"]["shimToken"] == "shim-token-rotated":
                    break
                time.sleep(0.05)

        assert data["provisioning"]["shimToken"] == "shim-token-rotated"
        assert data["provisioning"]["shimBaseURL"] == "http://100.79.222.100:8765"


def test_hello_without_provisioning_keeps_stored_descriptor(tmp_path):
    with build_client(tmp_path) as client:
        connector_data = setup_connector(client)
        access_token = pair_phone(
            client, connector_data["connectorCredential"], "55555555-5555-5555-5555-555555555555"
        )["auth"]["accessToken"]
        headers = {"Authorization": f"Bearer {connector_data['connectorCredential']}"}

        with client.websocket_connect("/v1/hosts/ws", headers=headers) as websocket:
            send_hello(websocket, DESCRIPTOR)

        # A pre-provisioning connector reconnecting must not wipe the bundle.
        with client.websocket_connect("/v1/hosts/ws", headers=headers) as websocket:
            send_hello(websocket, None, include_provisioning=False)

        data = get_provisioning(client, access_token)
        assert data["provisioning"]["shimToken"] == "shim-token-abc"

        # An explicitly empty descriptor IS the connector's current truth —
        # e.g. the shim was decommissioned — and clears the stored bundle.
        with client.websocket_connect("/v1/hosts/ws", headers=headers) as websocket:
            send_hello(websocket, {})

        data = get_provisioning(client, access_token)
        assert data["provisioning"] == {
            "shimBaseURL": None,
            "shimToken": None,
            "gatewayBaseURL": None,
        }


# --- sanitizer unit tests ---


def test_sanitize_provisioning_descriptor_shapes():
    assert sanitize_provisioning_descriptor(None) is None
    assert sanitize_provisioning_descriptor("junk") == {}
    assert sanitize_provisioning_descriptor(["list"]) == {}
    assert sanitize_provisioning_descriptor({}) == {}
    assert sanitize_provisioning_descriptor(
        {
            "shim_base_url": "  http://h:8765 ",
            "shim_token": "",
            "gateway_base_url": 42,
            "unknown_key": "dropped",
        }
    ) == {"shim_base_url": "http://h:8765"}
