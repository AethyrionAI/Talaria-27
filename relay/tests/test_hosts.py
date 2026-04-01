from __future__ import annotations

from threading import Thread

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def build_client(tmp_path):
    settings = Settings(
        environment="test",
        public_base_url="https://relay.example.test/v1",
        database_url=f"sqlite:///{tmp_path / 'relay-hosts.db'}",
        internal_api_key="test-internal-key",
        pairing_code_ttl_seconds=900,
        phone_pairing_code_ttl_seconds=900,
        phone_pairing_max_attempts_per_code=3,
        phone_pairing_max_attempts_per_ip=3,
        phone_pairing_rate_limit_window_seconds=300,
        host_enrollment_code_ttl_seconds=900,
        hermes_adapter="connector",
        connector_sync_wait_seconds=2,
        connector_job_lease_seconds=30,
        connector_heartbeat_timeout_seconds=5,
        connector_idle_poll_interval_seconds=0.1,
    )
    app = create_app(settings)
    return TestClient(app)


def connector_setup_payload(owner_display_name: str = "Taylor") -> dict:
    return {
        "ownerDisplayName": owner_display_name,
        "hostDisplayName": "Home Mac mini",
        "connector": {
            "platform": "macos",
            "hostname": "dylans-mac-mini",
            "connectorVersion": "0.1.0",
            "hermesCommand": "/Users/dylan/.local/bin/hermes",
            "hermesVersion": "hermes 1.2.3",
        },
    }


def phone_pairing_payload(code: str, installation_id: str) -> dict:
    return {
        "code": code,
        "device": {
            "platform": "ios",
            "deviceName": "Taylor's iPhone",
            "appVersion": "1.0.0",
            "buildNumber": "1",
            "bundleId": "com.appfactory.HermesMobile",
            "installationId": installation_id,
            "deviceModel": "iPhone17,2",
            "systemVersion": "26.2",
        },
        "client": {
            "environment": "production",
        },
    }


def setup_connector(client: TestClient) -> dict:
    response = client.post("/v1/connector/setup", json=connector_setup_payload())
    assert response.status_code == 200
    return response.json()["data"]


def create_phone_pairing_code(client: TestClient, connector_credential: str) -> dict:
    response = client.post(
        "/v1/connector/phone-pairing-codes",
        headers={"Authorization": f"Bearer {connector_credential}"},
    )
    assert response.status_code == 200
    return response.json()["data"]


def redeem_phone(client: TestClient, code: str, installation_id: str) -> dict:
    response = client.post(
        "/v1/phone-pairing/redeem",
        json=phone_pairing_payload(code=code, installation_id=installation_id),
    )
    assert response.status_code == 200
    return response.json()["data"]


def sensor_location_payload() -> dict:
    return {
        "latitude": 40.7128,
        "longitude": -74.0060,
        "altitude": 12.0,
        "accuracy": 35.0,
        "address": "New York, NY",
        "recordedAt": "2026-04-01T15:00:00Z",
    }


def test_connector_setup_and_phone_pairing_attach_phone_to_existing_user(tmp_path):
    with build_client(tmp_path) as client:
        connector_data = setup_connector(client)
        pairing_code = create_phone_pairing_code(client, connector_data["connectorCredential"])

        assert pairing_code["displayCode"].count("-") == 1
        first_phone = redeem_phone(client, pairing_code["displayCode"], "11111111-1111-1111-1111-111111111111")
        second_pairing_code = create_phone_pairing_code(client, connector_data["connectorCredential"])
        second_phone = redeem_phone(client, second_pairing_code["code"], "22222222-2222-2222-2222-222222222222")

        assert first_phone["user"]["id"] == connector_data["user"]["id"]
        assert second_phone["user"]["id"] == connector_data["user"]["id"]
        assert first_phone["deviceId"] != second_phone["deviceId"]

        current_host = client.get(
            "/v1/hosts/current",
            headers={"Authorization": f"Bearer {first_phone['auth']['accessToken']}"},
        )
        assert current_host.status_code == 200
        assert current_host.json()["data"]["host"]["id"] == connector_data["host"]["id"]


def test_phone_pairing_rejects_reused_and_rate_limited_codes(tmp_path):
    with build_client(tmp_path) as client:
        connector_data = setup_connector(client)
        pairing_code = create_phone_pairing_code(client, connector_data["connectorCredential"])

        redeem_phone(client, pairing_code["displayCode"], "33333333-3333-3333-3333-333333333333")

        reused = client.post(
            "/v1/phone-pairing/redeem",
            json=phone_pairing_payload(pairing_code["displayCode"], "44444444-4444-4444-4444-444444444444"),
        )
        assert reused.status_code == 400
        assert reused.json()["detail"] == "This phone pairing code has already been used."

        invalid_one = client.post(
            "/v1/phone-pairing/redeem",
            json=phone_pairing_payload("ZZZZ-ZZZZ", "55555555-5555-5555-5555-555555555555"),
        )
        invalid_two = client.post(
            "/v1/phone-pairing/redeem",
            json=phone_pairing_payload("ZZZZ-ZZZZ", "66666666-6666-6666-6666-666666666666"),
        )
        limited = client.post(
            "/v1/phone-pairing/redeem",
            json=phone_pairing_payload("ZZZZ-ZZZZ", "77777777-7777-7777-7777-777777777777"),
        )

        assert invalid_one.status_code == 400
        assert invalid_two.status_code == 400
        assert limited.status_code == 429
        assert limited.json()["detail"] == "Too many pairing attempts. Try again later."


def test_messages_return_pending_when_host_is_offline(tmp_path):
    with build_client(tmp_path) as client:
        connector_data = setup_connector(client)
        pairing_code = create_phone_pairing_code(client, connector_data["connectorCredential"])
        access_token = redeem_phone(
            client,
            pairing_code["displayCode"],
            "99999990-8888-8888-8888-888888888888",
        )["auth"]["accessToken"]

        message_response = client.post(
            "/v1/messages",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"text": "Hello while offline"},
        )
        assert message_response.status_code == 202
        data = message_response.json()["data"]
        assert data["replyState"] == "pending"
        assert data["message"] is None if "message" in data else True
        assert data["conversation"]["messages"][0]["deliveryStatus"] == "pending"


def test_connected_host_gets_job_and_preserves_session_resume(tmp_path):
    with build_client(tmp_path) as client:
        connector_data = setup_connector(client)
        pairing_code = create_phone_pairing_code(client, connector_data["connectorCredential"])
        access_token = redeem_phone(
            client,
            pairing_code["displayCode"],
            "99999999-9999-9999-9999-999999999999",
        )["auth"]["accessToken"]

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {connector_data['connectorCredential']}"},
        ) as websocket:
            websocket.send_json(
                {
                    "type": "hello",
                    "connector": {
                        "platform": "macos",
                        "hostname": "dylans-mac-mini",
                        "connectorVersion": "0.1.0",
                        "hermesCommand": "/Users/dylan/.local/bin/hermes",
                        "hermesVersion": "hermes 1.2.3",
                        "displayName": "Home Mac mini",
                    },
                }
            )
            ready = websocket.receive_json()
            assert ready["type"] == "ready"

            first_response: dict = {}

            def send_first_message() -> None:
                first_response["payload"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={"text": "Hello from phone"},
                )

            thread = Thread(target=send_first_message)
            thread.start()
            first_job = websocket.receive_json()
            assert first_job["type"] == "job.execute"
            assert first_job["job"]["sessionId"] is None

            websocket.send_json(
                {
                    "type": "job.result",
                    "jobId": first_job["job"]["id"],
                    "text": "First connector reply",
                    "sessionId": "session-123",
                }
            )
            thread.join(timeout=5)
            assert first_response["payload"].status_code == 200
            assert first_response["payload"].json()["data"]["replyState"] == "delivered"

            second_response: dict = {}

            def send_second_message() -> None:
                second_response["payload"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={"text": "Follow up"},
                )

            second_thread = Thread(target=send_second_message)
            second_thread.start()
            second_job = websocket.receive_json()
            assert second_job["job"]["sessionId"] == "session-123"
            websocket.send_json(
                {
                    "type": "job.result",
                    "jobId": second_job["job"]["id"],
                    "text": "Second connector reply",
                    "sessionId": "session-123",
                }
            )
            second_thread.join(timeout=5)
            assert second_response["payload"].status_code == 200
            messages = second_response["payload"].json()["data"]["conversation"]["messages"]
            assert messages[-1]["text"] == "Second connector reply"


def test_sensor_delivery_returns_retry_offline_and_delivered_after_connector_ack(tmp_path):
    with build_client(tmp_path) as client:
        connector_data = setup_connector(client)
        pairing_code = create_phone_pairing_code(client, connector_data["connectorCredential"])
        access_token = redeem_phone(
            client,
            pairing_code["displayCode"],
            "12121212-3434-5656-7878-909090909090",
        )["auth"]["accessToken"]

        offline = client.post(
            "/v1/device/sensor/location",
            headers={"Authorization": f"Bearer {access_token}"},
            json=sensor_location_payload(),
        )
        assert offline.status_code == 202
        assert offline.json()["data"]["deliveryState"] == "retry"

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {connector_data['connectorCredential']}"},
        ) as websocket:
            websocket.send_json(
                {
                    "type": "hello",
                    "connector": {
                        "platform": "macos",
                        "hostname": "dylans-mac-mini",
                        "connectorVersion": "0.1.0",
                        "hermesCommand": "/Users/dylan/.local/bin/hermes",
                        "hermesVersion": "hermes 1.2.3",
                    },
                }
            )
            assert websocket.receive_json()["type"] == "ready"

            response: dict = {}

            def send_location() -> None:
                response["payload"] = client.post(
                    "/v1/device/sensor/location",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json=sensor_location_payload(),
                )

            thread = Thread(target=send_location)
            thread.start()
            sensor_message = websocket.receive_json()
            assert sensor_message["type"] == "sensor.location"
            assert sensor_message["deliveryId"]

            websocket.send_json(
                {
                    "type": "sensor.ack",
                    "deliveryId": sensor_message["deliveryId"],
                    "deliveryState": "delivered",
                }
            )
            thread.join(timeout=5)

            delivered = response["payload"]
            assert delivered.status_code == 200
            assert delivered.json()["data"]["deliveryState"] == "delivered"


def test_stale_connector_disconnect_does_not_remove_newer_live_socket(tmp_path):
    with build_client(tmp_path) as client:
        connector_data = setup_connector(client)
        pairing_code = create_phone_pairing_code(client, connector_data["connectorCredential"])
        access_token = redeem_phone(
            client,
            pairing_code["displayCode"],
            "78787878-5656-3434-1212-000000000000",
        )["auth"]["accessToken"]

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {connector_data['connectorCredential']}"},
        ) as first_socket:
            first_socket.send_json(
                {
                    "type": "hello",
                    "connector": {
                        "platform": "macos",
                        "hostname": "dylans-mac-mini",
                        "connectorVersion": "0.1.0",
                        "hermesCommand": "/Users/dylan/.local/bin/hermes",
                        "hermesVersion": "hermes 1.2.3",
                    },
                }
            )
            assert first_socket.receive_json()["type"] == "ready"

            with client.websocket_connect(
                "/v1/hosts/ws",
                headers={"Authorization": f"Bearer {connector_data['connectorCredential']}"},
            ) as second_socket:
                second_socket.send_json(
                    {
                        "type": "hello",
                        "connector": {
                            "platform": "macos",
                            "hostname": "dylans-mac-mini",
                            "connectorVersion": "0.1.0",
                            "hermesCommand": "/Users/dylan/.local/bin/hermes",
                            "hermesVersion": "hermes 1.2.3",
                        },
                    }
                )
                assert second_socket.receive_json()["type"] == "ready"

                first_socket.close()

                response: dict = {}

                def send_location() -> None:
                    response["payload"] = client.post(
                        "/v1/device/sensor/location",
                        headers={"Authorization": f"Bearer {access_token}"},
                        json=sensor_location_payload(),
                    )

                thread = Thread(target=send_location)
                thread.start()
                sensor_message = second_socket.receive_json()
                assert sensor_message["type"] == "sensor.location"

                second_socket.send_json(
                    {
                        "type": "sensor.ack",
                        "deliveryId": sensor_message["deliveryId"],
                        "deliveryState": "delivered",
                    }
                )
                thread.join(timeout=5)
                assert response["payload"].status_code == 200
                assert response["payload"].json()["data"]["deliveryState"] == "delivered"
