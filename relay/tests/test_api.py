from __future__ import annotations

from fastapi.testclient import TestClient

from app.config import Settings
from app.hermes_adapter import HermesChatResult
from app.main import create_app


def build_client(tmp_path):
    settings = Settings(
        environment="test",
        public_base_url="http://testserver/v1",
        database_url=f"sqlite:///{tmp_path / 'relay.db'}",
        internal_api_key="test-internal-key",
    )
    app = create_app(settings)
    return TestClient(app)


def register_device(client: TestClient):
    response = client.post(
        "/v1/device/register",
        json={
            "device": {
                "platform": "ios",
                "deviceName": "Test iPhone",
                "appVersion": "1.0.0",
                "buildNumber": "1",
                "bundleId": "com.appfactory.HermesMobile",
                "installationId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
                "deviceModel": "iPhone17,2",
                "systemVersion": "26.4",
            },
            "client": {
                "environment": "development",
            },
        },
    )
    assert response.status_code == 200
    return response.json()["data"]


def test_device_register_session_and_refresh(tmp_path):
    with build_client(tmp_path) as client:
        register_data = register_device(client)

        access_token = register_data["auth"]["accessToken"]
        refresh_token = register_data["auth"]["refreshToken"]

        session_response = client.get(
            "/v1/session",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        assert session_response.status_code == 200
        assert session_response.json()["data"]["device"]["registered"] is True

        refresh_response = client.post(
            "/v1/auth/refresh",
            json={"refreshToken": refresh_token},
        )
        assert refresh_response.status_code == 200
        assert refresh_response.json()["data"]["accessToken"] != access_token


def test_push_and_inbox_roundtrip(tmp_path):
    with build_client(tmp_path) as client:
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]
        device_id = register_data["deviceId"]

        push_response = client.post(
            "/v1/push/register",
            headers={"Authorization": f"Bearer {access_token}"},
            json={
                "deviceId": device_id,
                "apnsToken": "deadbeef",
                "pushEnvironment": "sandbox",
                "bundleId": "com.appfactory.HermesMobile",
            },
        )
        assert push_response.status_code == 200
        assert push_response.json()["data"]["registered"] is True

        internal_response = client.post(
            "/internal/inbox/create",
            headers={"X-Relay-Internal-Key": "test-internal-key"},
            json={
                "kind": "approval",
                "title": "Approve trip plan",
                "body": "Hermes needs confirmation before booking the train.",
                "priority": "high",
                "payload": {"requestId": "trip-123"},
            },
        )
        assert internal_response.status_code == 200
        item_id = internal_response.json()["data"]["item"]["id"]

        inbox_response = client.get(
            "/v1/inbox",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        assert inbox_response.status_code == 200
        assert len(inbox_response.json()["data"]["items"]) == 1

        action_response = client.post(
            f"/v1/inbox/{item_id}/action",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"actionId": "approve"},
        )
        assert action_response.status_code == 200
        assert action_response.json()["data"]["status"] == "completed"

        actions_response = client.get(
            f"/internal/inbox/{item_id}/actions",
            headers={"X-Relay-Internal-Key": "test-internal-key"},
        )
        assert actions_response.status_code == 200
        assert actions_response.json()["data"]["actions"][0]["actionId"] == "approve"


def test_chat_roundtrip_uses_relay_conversation(tmp_path):
    with build_client(tmp_path) as client:
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]

        conversation_response = client.get(
            "/v1/conversations/current",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        assert conversation_response.status_code == 200
        assert conversation_response.json()["data"]["conversation"]["messages"] == []

        message_response = client.post(
            "/v1/messages",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"text": "Hello Hermes"},
        )
        assert message_response.status_code == 200
        assert message_response.json()["data"]["message"]["role"] == "hermes"
        assert "Hello Hermes" in message_response.json()["data"]["message"]["text"]

        updated_conversation = client.get(
            "/v1/conversations/current",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        assert updated_conversation.status_code == 200
        assert len(updated_conversation.json()["data"]["conversation"]["messages"]) == 2


def test_chat_roundtrip_persists_hermes_session_id_for_resume(tmp_path):
    class StubHermesAdapter:
        def __init__(self) -> None:
            self.calls: list[str | None] = []

        def send_message(self, *, latest_user_message, history, session_id=None):
            self.calls.append(session_id)
            if session_id is None:
                return HermesChatResult(text="First reply", session_id="session-123")
            return HermesChatResult(text="Second reply", session_id=session_id)

    stub_adapter = StubHermesAdapter()

    with build_client(tmp_path) as client:
        client.app.state.hermes_adapter = stub_adapter
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]

        first_response = client.post(
            "/v1/messages",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"text": "Hello Hermes"},
        )
        assert first_response.status_code == 200

        second_response = client.post(
            "/v1/messages",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"text": "Follow up"},
        )
        assert second_response.status_code == 200

        assert stub_adapter.calls == [None, "session-123"]


def test_chat_create_message_is_idempotent_for_client_message_id(tmp_path):
    class StubHermesAdapter:
        def __init__(self) -> None:
            self.call_count = 0

        def send_message(self, *, latest_user_message, history, session_id=None):
            self.call_count += 1
            return HermesChatResult(text=f"Reply for {latest_user_message}", session_id="session-123")

    stub_adapter = StubHermesAdapter()

    with build_client(tmp_path) as client:
        client.app.state.hermes_adapter = stub_adapter
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]
        client_message_id = "11111111-2222-3333-4444-555555555555"

        first_response = client.post(
            "/v1/messages",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"text": "Hello Hermes", "clientMessageId": client_message_id},
        )
        second_response = client.post(
            "/v1/messages",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"text": "Hello Hermes", "clientMessageId": client_message_id},
        )

        assert first_response.status_code == 200
        assert second_response.status_code == 200
        assert stub_adapter.call_count == 1
        assert first_response.json()["data"]["message"]["id"] == second_response.json()["data"]["message"]["id"]

        updated_conversation = client.get(
            "/v1/conversations/current",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        assert updated_conversation.status_code == 200
        assert len(updated_conversation.json()["data"]["conversation"]["messages"]) == 2
