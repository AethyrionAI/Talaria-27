from __future__ import annotations

from fastapi.testclient import TestClient

from app.config import Settings
from app.hermes_adapter import HermesChatResult
from app.main import create_app


def build_client(tmp_path, **overrides):
    settings = Settings(
        environment="test",
        public_base_url="http://testserver/v1",
        database_url=f"sqlite:///{tmp_path / 'relay.db'}",
        internal_api_key="test-internal-key",
        **overrides,
    )
    app = create_app(settings)
    return TestClient(app)


def register_device(client: TestClient, installation_id: str = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"):
    response = client.post(
        "/v1/device/register",
        json={
            "device": {
                "platform": "ios",
                "deviceName": "Test iPhone",
                "appVersion": "1.0.0",
                "buildNumber": "1",
                "bundleId": "io.hermesmobile.HermesMobile",
                "installationId": installation_id,
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
                "bundleId": "io.hermesmobile.HermesMobile",
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


def test_device_app_state_roundtrip(tmp_path):
    with build_client(tmp_path) as client:
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]

        response = client.post(
            "/v1/device/app-state",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"state": "foreground"},
        )
        assert response.status_code == 200
        assert response.json()["data"]["state"] == "foreground"


def test_chat_reply_triggers_push_when_device_is_backgrounded(tmp_path):
    class StubAPNsClient:
        def __init__(self) -> None:
            self.alerts = []

        async def send_alert_push(self, token: str, *, title: str, body: str, category: str | None = None, bundle_id: str | None = None, environment: str | None = None):
            from app.apns import PushResult
            self.alerts.append({
                "token": token,
                "title": title,
                "body": body,
                "category": category,
                "bundle_id": bundle_id,
                "environment": environment,
            })
            return PushResult.SENT

    with build_client(tmp_path, hermes_adapter="mock") as client:
        client.app.state.apns_client = StubAPNsClient()
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
                "bundleId": "io.hermesmobile.HermesMobile",
            },
        )
        assert push_response.status_code == 200

        state_response = client.post(
            "/v1/device/app-state",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"state": "background"},
        )
        assert state_response.status_code == 200

        message_response = client.post(
            "/v1/messages",
            headers={"Authorization": f"Bearer {access_token}"},
            json={"text": "Hello Hermes"},
        )
        assert message_response.status_code == 200

        alerts = client.app.state.apns_client.alerts
        assert len(alerts) == 1
        assert alerts[0]["token"] == "deadbeef"
        assert alerts[0]["title"] == "Hermes"
        assert "Hello Hermes" in alerts[0]["body"]


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


def test_chat_accepts_attachment_only_message_and_round_trips_metadata(tmp_path):
    with build_client(tmp_path) as client:
        register_data = register_device(client)
        access_token = register_data["auth"]["accessToken"]

        message_response = client.post(
            "/v1/messages",
            headers={"Authorization": f"Bearer {access_token}"},
            json={
                "text": "",
                "clientMessageId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                "attachments": [
                    {
                        "type": "file",
                        "filename": "note.txt",
                        "mimeType": "text/plain",
                        "data": "aGVsbG8=",
                        "thumbnailData": None,
                    }
                ],
            },
        )
        assert message_response.status_code == 200
        data = message_response.json()["data"]
        assert data["userMessage"]["text"] == ""
        assert data["userMessage"]["clientMessageId"] == "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        assert data["userMessage"]["attachments"][0]["filename"] == "note.txt"
        assert data["conversation"]["messages"][0]["attachments"][0]["mimeType"] == "text/plain"


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


def test_reregister_preserves_paired_user_binding(tmp_path):
    # GH #15 recovery path: a device whose refresh token died re-registers to
    # mint fresh tokens. The device must keep the user its pairing bound it
    # to — not fall back to the default (first) user row (#46 family).
    from app.models import Device
    from app.services import create_pairing_invite
    from sqlalchemy import select

    with build_client(tmp_path) as client:
        # First user row = the default user, minted by a plain registration.
        register_device(client, installation_id="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")

        # Pair a second installation to a distinct user via an invite.
        with client.app.state.database.session() as db:
            _, invite_token = create_pairing_invite(db, settings=client.app.state.settings)
        paired_installation = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        redeem_response = client.post(
            "/v1/pairing/redeem",
            json={
                "inviteToken": invite_token,
                "displayName": "Taylor",
                "device": {
                    "platform": "ios",
                    "deviceName": "Taylor's iPhone",
                    "appVersion": "1.0.0",
                    "buildNumber": "1",
                    "bundleId": "io.hermesmobile.HermesMobile",
                    "installationId": paired_installation,
                    "deviceModel": "iPhone17,2",
                    "systemVersion": "26.4",
                },
                "client": {"environment": "production"},
            },
        )
        assert redeem_response.status_code == 200
        paired_user_id = redeem_response.json()["data"]["user"]["id"]

        # Recovery: the paired installation re-registers with no bearer token.
        recovered = register_device(client, installation_id=paired_installation)

        with client.app.state.database.session() as db:
            device = db.scalar(select(Device).where(Device.installation_id == paired_installation))
            assert device is not None
            assert device.user_id == paired_user_id

        # The recovered credentials authenticate as the paired user.
        session_response = client.get(
            "/v1/session",
            headers={"Authorization": f"Bearer {recovered['auth']['accessToken']}"},
        )
        assert session_response.status_code == 200
        assert session_response.json()["data"]["user"]["id"] == paired_user_id
        assert session_response.json()["data"]["user"]["displayName"] == "Taylor"

        # A brand-new installation still binds to the default user.
        fresh = register_device(client, installation_id="cccccccc-cccc-cccc-cccc-cccccccccccc")
        fresh_session = client.get(
            "/v1/session",
            headers={"Authorization": f"Bearer {fresh['auth']['accessToken']}"},
        )
        assert fresh_session.status_code == 200
        assert fresh_session.json()["data"]["user"]["id"] != paired_user_id


def test_refresh_grace_honors_previous_token_after_rotation(tmp_path):
    # GH #15: if the rotation response is lost in transit, the client retries
    # with the token it still holds — that retry must succeed within the
    # grace window instead of stranding the device until a manual re-pair.
    with build_client(tmp_path) as client:
        register_data = register_device(client)
        original_refresh = register_data["auth"]["refreshToken"]

        first_refresh = client.post("/v1/auth/refresh", json={"refreshToken": original_refresh})
        assert first_refresh.status_code == 200

        # Simulated lost response: retry with the pre-rotation token.
        graced_retry = client.post("/v1/auth/refresh", json={"refreshToken": original_refresh})
        assert graced_retry.status_code == 200
        recovered = graced_retry.json()["data"]

        session_response = client.get(
            "/v1/session",
            headers={"Authorization": f"Bearer {recovered['accessToken']}"},
        )
        assert session_response.status_code == 200

        # The freshly-minted refresh token rotates normally afterwards.
        final_refresh = client.post("/v1/auth/refresh", json={"refreshToken": recovered["refreshToken"]})
        assert final_refresh.status_code == 200


def test_refresh_grace_window_expires(tmp_path):
    import time

    with build_client(tmp_path, refresh_token_grace_seconds=0) as client:
        register_data = register_device(client)
        original_refresh = register_data["auth"]["refreshToken"]

        first_refresh = client.post("/v1/auth/refresh", json={"refreshToken": original_refresh})
        assert first_refresh.status_code == 200

        time.sleep(0.05)
        expired_retry = client.post("/v1/auth/refresh", json={"refreshToken": original_refresh})
        assert expired_retry.status_code == 401
        assert expired_retry.json()["detail"] == "Invalid refresh token."


def test_identity_rotation_revokes_refresh_grace(tmp_path):
    # Pairing/registration rotations are identity events: no refresh token
    # from the previous credential set may survive them, grace or not.
    with build_client(tmp_path) as client:
        register_data = register_device(client)
        original_refresh = register_data["auth"]["refreshToken"]

        first_refresh = client.post("/v1/auth/refresh", json={"refreshToken": original_refresh})
        assert first_refresh.status_code == 200

        # Re-registration rotates the auth session without grace.
        register_device(client)

        graced_retry = client.post("/v1/auth/refresh", json={"refreshToken": original_refresh})
        assert graced_retry.status_code == 401
