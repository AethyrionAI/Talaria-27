"""Tests for the SSE job events endpoint and the streaming event bus.

Covers:
  - Completed-job fast-path (GET /v1/jobs/{id}/events on an already-finished job)
  - Live streaming: connector sends job.progress + job.result → SSE client sees
    text_delta, tool_activity, and done events with usage + result message
  - Failed-job done event includes error and status=failed
  - Auth gate: SSE returns 404 for a job owned by a different user
  - Message response includes jobId for iOS streaming correlation
  - Usage data persists and appears in conversation serialization
  - Result message carries jobId for jobId-based resolution
"""

from __future__ import annotations

import json
import time
from threading import Thread

from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app


def build_client(tmp_path, **overrides):
    base = dict(
        environment="test",
        public_base_url="https://relay.example.test/v1",
        database_url=f"sqlite:///{tmp_path / 'relay-streaming.db'}",
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
        sse_keepalive_seconds=30,
    )
    base.update(overrides)
    app = create_app(Settings(**base))
    return TestClient(app)


CONNECTOR_SETUP = {
    "ownerDisplayName": "Taylor",
    "hostDisplayName": "Home Mac mini",
    "connector": {
        "platform": "macos",
        "hostname": "test-host",
        "connectorVersion": "0.1.0",
        "hermesCommand": "/usr/local/bin/hermes",
        "hermesVersion": "hermes 1.2.3",
    },
}

HELLO_PAYLOAD = {
    "type": "hello",
    "connector": {
        "platform": "macos",
        "hostname": "test-host",
        "connectorVersion": "0.1.0",
        "hermesCommand": "/usr/local/bin/hermes",
        "hermesVersion": "hermes 1.2.3",
    },
}


def phone_pairing_payload(code, installation_id):
    return {
        "code": code,
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
    }


def setup_environment(client, installation_id="aaaa1111-bbbb-cccc-dddd-eeeeeeee0001"):
    """Set up connector + phone pairing, return (connector_credential, access_token)."""
    connector_data = client.post("/v1/connector/setup", json=CONNECTOR_SETUP).json()["data"]
    pairing = client.post(
        "/v1/connector/phone-pairing-codes",
        headers={"Authorization": f"Bearer {connector_data['connectorCredential']}"},
    ).json()["data"]
    phone = client.post(
        "/v1/phone-pairing/redeem",
        json=phone_pairing_payload(pairing["displayCode"], installation_id),
    ).json()["data"]
    return connector_data["connectorCredential"], phone["auth"]["accessToken"]


def parse_sse_events(raw_text):
    """Parse SSE text into a list of (event_type, data_dict) tuples."""
    events = []
    current_event = "message"
    current_data = ""

    for line in raw_text.split("\n"):
        if line.startswith("event:"):
            current_event = line[6:].strip()
        elif line.startswith("data:"):
            current_data = line[5:].strip()
        elif line.startswith(":"):
            continue
        elif line == "":
            if current_data:
                try:
                    events.append((current_event, json.loads(current_data)))
                except json.JSONDecodeError:
                    events.append((current_event, current_data))
                current_event = "message"
                current_data = ""

    return events


# --------------------------------------------------------------------------
# Test: Completed-job fast-path
# --------------------------------------------------------------------------

def test_sse_completed_job_fast_path_returns_done_with_usage_and_message(tmp_path):
    """When GET /v1/jobs/{id}/events is called for an already-completed job,
    it should return a single `done` event with the result message and usage."""
    with build_client(tmp_path) as client:
        credential, access_token = setup_environment(client)

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {credential}"},
        ) as websocket:
            websocket.send_json(HELLO_PAYLOAD)
            assert websocket.receive_json()["type"] == "ready"

            response_holder: dict = {}

            def send_msg():
                response_holder["r"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={"text": "Completed fast-path test"},
                )

            thread = Thread(target=send_msg)
            thread.start()
            job = websocket.receive_json()["job"]

            websocket.send_json({
                "type": "job.result",
                "jobId": job["id"],
                "text": "Fast path reply",
                "sessionId": "sess-fast",
                "usage": {"prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150},
            })
            thread.join(timeout=5)
            assert response_holder["r"].status_code == 202

        # Job is now completed — SSE endpoint should replay buffer + done
        response = client.get(
            f"/v1/jobs/{job['id']}/events",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        assert response.status_code == 200
        assert "text/event-stream" in response.headers["content-type"]

        events = parse_sse_events(response.text)
        # At least the done event (may also have buffered progress events)
        assert len(events) >= 1

        event_type, data = events[0]
        assert event_type == "done"
        assert data["status"] == "completed"
        assert data["jobId"] == job["id"]
        assert data["usage"]["total_tokens"] == 150
        assert data["message"]["role"] == "hermes"
        assert data["message"]["text"] == "Fast path reply"
        assert data["message"]["jobId"] == job["id"]


# --------------------------------------------------------------------------
# Test: Failed-job fast-path
# --------------------------------------------------------------------------

def test_sse_failed_job_fast_path_includes_error(tmp_path):
    """A failed job's SSE fast-path should include the error text and status=failed."""
    with build_client(tmp_path) as client:
        credential, access_token = setup_environment(
            client, installation_id="aaaa1111-bbbb-cccc-dddd-eeeeeeee0002"
        )

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {credential}"},
        ) as websocket:
            websocket.send_json(HELLO_PAYLOAD)
            assert websocket.receive_json()["type"] == "ready"

            holder: dict = {}

            def send_msg():
                holder["r"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={"text": "Fail this one"},
                )

            thread = Thread(target=send_msg)
            thread.start()
            job = websocket.receive_json()["job"]

            websocket.send_json({
                "type": "job.failed",
                "jobId": job["id"],
                "retryable": False,
                "error": "Tool crashed hard",
            })
            thread.join(timeout=5)

        response = client.get(
            f"/v1/jobs/{job['id']}/events",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        events = parse_sse_events(response.text)
        assert len(events) == 1

        event_type, data = events[0]
        assert event_type == "done"
        assert data["status"] == "failed"
        assert data["error"] == "Tool crashed hard"
        assert data["message"]["role"] == "system"


# --------------------------------------------------------------------------
# Test: Live streaming — progress events flow through the event bus
# --------------------------------------------------------------------------

def test_live_streaming_progress_events_flow_through_event_bus(tmp_path):
    """Full pipeline: connector sends job.progress text_delta/tool_activity
    and job.result → the SSE stream receives them in order."""
    with build_client(tmp_path) as client:
        credential, access_token = setup_environment(
            client, installation_id="aaaa1111-bbbb-cccc-dddd-eeeeeeee0003"
        )

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {credential}"},
        ) as websocket:
            websocket.send_json(HELLO_PAYLOAD)
            assert websocket.receive_json()["type"] == "ready"

            msg_holder: dict = {}

            def send_msg():
                msg_holder["r"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={"text": "Stream me"},
                )

            msg_thread = Thread(target=send_msg)
            msg_thread.start()
            job = websocket.receive_json()["job"]

            # Subscribe to SSE before sending progress events
            sse_holder: dict = {}

            def read_sse():
                sse_holder["r"] = client.get(
                    f"/v1/jobs/{job['id']}/events",
                    headers={"Authorization": f"Bearer {access_token}"},
                )

            sse_thread = Thread(target=read_sse)
            sse_thread.start()

            # Give the SSE subscriber a moment to connect
            time.sleep(0.3)

            # Send progress events
            websocket.send_json({
                "type": "job.progress",
                "jobId": job["id"],
                "kind": "tool_activity",
                "label": "Searching files...",
            })
            websocket.send_json({
                "type": "job.progress",
                "jobId": job["id"],
                "kind": "text_delta",
                "delta": "Here is ",
            })
            websocket.send_json({
                "type": "job.progress",
                "jobId": job["id"],
                "kind": "text_delta",
                "delta": "the answer.",
            })

            # Complete the job
            websocket.send_json({
                "type": "job.result",
                "jobId": job["id"],
                "text": "Here is the answer.",
                "sessionId": "sess-stream",
                "usage": {"prompt_tokens": 200, "completion_tokens": 30, "total_tokens": 230},
            })

            msg_thread.join(timeout=5)
            sse_thread.join(timeout=5)

        assert msg_holder["r"].status_code == 202

        events = parse_sse_events(sse_holder["r"].text)
        event_types = [e[0] for e in events]

        assert "tool_activity" in event_types
        assert "text_delta" in event_types
        assert "done" in event_types

        # Verify tool_activity payload
        tool_events = [(t, d) for t, d in events if t == "tool_activity"]
        assert len(tool_events) == 1
        assert tool_events[0][1]["label"] == "Searching files..."

        # Verify text_delta payloads
        text_events = [(t, d) for t, d in events if t == "text_delta"]
        assert len(text_events) == 2
        assert text_events[0][1]["delta"] == "Here is "
        assert text_events[1][1]["delta"] == "the answer."

        # Verify done event
        done_events = [(t, d) for t, d in events if t == "done"]
        assert len(done_events) == 1
        done_data = done_events[0][1]
        assert done_data["status"] == "completed"
        assert done_data["usage"]["total_tokens"] == 230
        assert done_data["message"]["text"] == "Here is the answer."
        assert done_data["message"]["jobId"] == job["id"]


# --------------------------------------------------------------------------
# Test: Auth gate — can't read another user's job events
# --------------------------------------------------------------------------

def test_sse_rejects_job_owned_by_different_user(tmp_path):
    """SSE endpoint should 404 if the authenticated user doesn't own the job."""
    with build_client(tmp_path) as client:
        credential_1, access_token_1 = setup_environment(
            client, installation_id="aaaa1111-bbbb-cccc-dddd-eeeeeeee0004"
        )

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {credential_1}"},
        ) as websocket:
            websocket.send_json(HELLO_PAYLOAD)
            assert websocket.receive_json()["type"] == "ready"

            holder: dict = {}

            def send_msg():
                holder["r"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token_1}"},
                    json={"text": "User 1 message"},
                )

            thread = Thread(target=send_msg)
            thread.start()
            job = websocket.receive_json()["job"]
            websocket.send_json({
                "type": "job.result",
                "jobId": job["id"],
                "text": "Reply for user 1",
                "sessionId": "sess-u1",
            })
            thread.join(timeout=5)

        # Set up a different user
        connector_data_2 = client.post("/v1/connector/setup", json={
            "ownerDisplayName": "Alex",
            "hostDisplayName": "Alex's Mac",
            "connector": {
                "platform": "macos",
                "hostname": "test-host",
                "connectorVersion": "0.1.0",
                "hermesCommand": "/usr/local/bin/hermes",
                "hermesVersion": "hermes 1.2.3",
            },
        }).json()["data"]
        pairing_2 = client.post(
            "/v1/connector/phone-pairing-codes",
            headers={"Authorization": f"Bearer {connector_data_2['connectorCredential']}"},
        ).json()["data"]
        phone_2 = client.post(
            "/v1/phone-pairing/redeem",
            json=phone_pairing_payload(pairing_2["displayCode"], "bbbb2222-cccc-dddd-eeee-ffff00000001"),
        ).json()["data"]
        access_token_2 = phone_2["auth"]["accessToken"]

        # User 2 tries to read user 1's job events
        response = client.get(
            f"/v1/jobs/{job['id']}/events",
            headers={"Authorization": f"Bearer {access_token_2}"},
        )
        assert response.status_code == 404


# --------------------------------------------------------------------------
# Test: Message response includes jobId
# --------------------------------------------------------------------------

def test_message_response_includes_job_id(tmp_path):
    """POST /v1/messages response should include jobId so iOS can open SSE immediately."""
    with build_client(tmp_path) as client:
        credential, access_token = setup_environment(
            client, installation_id="aaaa1111-bbbb-cccc-dddd-eeeeeeee0005"
        )

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {credential}"},
        ) as websocket:
            websocket.send_json(HELLO_PAYLOAD)
            assert websocket.receive_json()["type"] == "ready"

            holder: dict = {}

            def send_msg():
                holder["r"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={"text": "Give me the job ID"},
                )

            thread = Thread(target=send_msg)
            thread.start()
            job = websocket.receive_json()["job"]
            websocket.send_json({
                "type": "job.result",
                "jobId": job["id"],
                "text": "Job ID test reply",
                "sessionId": "sess-id",
            })
            thread.join(timeout=5)

        data = holder["r"].json()["data"]
        assert "jobId" in data
        assert data["jobId"] == job["id"]


# --------------------------------------------------------------------------
# Test: Usage data in conversation serialization
# --------------------------------------------------------------------------

def test_usage_data_appears_in_conversation_serialization(tmp_path):
    """After a job completes with usage, the conversation should include latestUsage."""
    with build_client(tmp_path) as client:
        credential, access_token = setup_environment(
            client, installation_id="aaaa1111-bbbb-cccc-dddd-eeeeeeee0006"
        )

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {credential}"},
        ) as websocket:
            websocket.send_json(HELLO_PAYLOAD)
            assert websocket.receive_json()["type"] == "ready"

            holder: dict = {}

            def send_msg():
                holder["r"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={"text": "Check usage"},
                )

            thread = Thread(target=send_msg)
            thread.start()
            job = websocket.receive_json()["job"]
            websocket.send_json({
                "type": "job.result",
                "jobId": job["id"],
                "text": "Usage test reply",
                "sessionId": "sess-usage",
                "usage": {"prompt_tokens": 500, "completion_tokens": 100, "total_tokens": 600},
            })
            thread.join(timeout=5)

        conv_response = client.get(
            "/v1/conversations/current",
            headers={"Authorization": f"Bearer {access_token}"},
        )
        assert conv_response.status_code == 200
        conv_data = conv_response.json()["data"]["conversation"]
        assert "latestUsage" in conv_data
        assert conv_data["latestUsage"]["total_tokens"] == 600


# --------------------------------------------------------------------------
# Test: Result message carries jobId for iOS resolution
# --------------------------------------------------------------------------

def test_result_message_carries_job_id(tmp_path):
    """The assistant result message should carry the jobId so iOS can resolve
    the final message by jobId instead of grabbing the last conversation message."""
    with build_client(tmp_path) as client:
        credential, access_token = setup_environment(
            client, installation_id="aaaa1111-bbbb-cccc-dddd-eeeeeeee0007"
        )

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {credential}"},
        ) as websocket:
            websocket.send_json(HELLO_PAYLOAD)
            assert websocket.receive_json()["type"] == "ready"

            holder: dict = {}

            def send_msg():
                holder["r"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={"text": "Job ID on result"},
                )

            thread = Thread(target=send_msg)
            thread.start()
            job = websocket.receive_json()["job"]
            websocket.send_json({
                "type": "job.result",
                "jobId": job["id"],
                "text": "Result with job reference",
                "sessionId": "sess-ref",
            })
            thread.join(timeout=5)

        data = holder["r"].json()["data"]
        # With connector adapter, message is delivered via SSE (not in POST response)
        assert data["replyState"] == "pending"
        assert "message" not in data


def test_pending_message_response_does_not_leak_completed_result_into_conversation(tmp_path):
    """Even if the connector completes before the POST returns, the pending payload
    should not include the assistant result inside conversation.messages."""
    with build_client(tmp_path) as client:
        credential, access_token = setup_environment(
            client, installation_id="aaaa1111-bbbb-cccc-dddd-eeeeeeee0008"
        )

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {credential}"},
        ) as websocket:
            websocket.send_json(HELLO_PAYLOAD)
            assert websocket.receive_json()["type"] == "ready"

            holder: dict = {}

            def send_msg():
                holder["r"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={"text": "Pending response should not leak final message"},
                )

            thread = Thread(target=send_msg)
            thread.start()
            job = websocket.receive_json()["job"]
            websocket.send_json({
                "type": "job.result",
                "jobId": job["id"],
                "text": "Finished too quickly",
                "sessionId": "sess-fast",
            })
            thread.join(timeout=5)

        data = holder["r"].json()["data"]
        assert data["replyState"] == "pending"
        assert "message" not in data
        assert all(
            not (message.get("jobId") == job["id"] and message.get("role") != "user")
            for message in data["conversation"]["messages"]
        )


def test_retryable_job_failure_keeps_sse_open_until_requeued_job_completes(tmp_path):
    with build_client(tmp_path) as client:
        credential, access_token = setup_environment(
            client, installation_id="aaaa1111-bbbb-cccc-dddd-eeeeeeee0009"
        )

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {credential}"},
        ) as websocket:
            websocket.send_json(HELLO_PAYLOAD)
            assert websocket.receive_json()["type"] == "ready"

            msg_holder: dict = {}

            def send_msg():
                msg_holder["r"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={"text": "Retry this queued job"},
                )

            msg_thread = Thread(target=send_msg)
            msg_thread.start()
            job = websocket.receive_json()["job"]

            sse_holder: dict = {}

            def read_sse():
                sse_holder["r"] = client.get(
                    f"/v1/jobs/{job['id']}/events",
                    headers={"Authorization": f"Bearer {access_token}"},
                )

            sse_thread = Thread(target=read_sse)
            sse_thread.start()
            time.sleep(0.3)

            websocket.send_json({
                "type": "job.failed",
                "jobId": job["id"],
                "retryable": True,
                "error": "connector temporarily unavailable",
            })

            retried_job = websocket.receive_json()["job"]
            assert retried_job["id"] == job["id"]

            websocket.send_json({
                "type": "job.result",
                "jobId": job["id"],
                "text": "Recovered after retry",
                "sessionId": "sess-retry",
            })

            msg_thread.join(timeout=5)
            sse_thread.join(timeout=5)

        assert msg_holder["r"].status_code == 202

        events = parse_sse_events(sse_holder["r"].text)
        done_events = [(t, d) for t, d in events if t == "done"]
        assert len(done_events) == 1
        assert done_events[0][1]["status"] == "completed"
        assert done_events[0][1]["message"]["text"] == "Recovered after retry"

# --------------------------------------------------------------------------
# Test: open SSE stream must not pin a pooled DB connection (#86)
# --------------------------------------------------------------------------

def test_sse_live_stream_releases_db_connection(tmp_path):
    """FastAPI closes the get_db dependency only after the stream finishes,
    so job_events_stream must release its pooled connection before handing
    back the StreamingResponse — otherwise every open SSE run pins one of
    the pool's 15 connections for minutes (the 7/8 QueuePool exhaustion).

    TestClient buffers the whole response in one call, so the stream is
    held open from a thread (same shape as the live-streaming test above)
    while the main thread watches the pool."""
    with build_client(tmp_path) as client:
        credential, access_token = setup_environment(
            client, installation_id="aaaa1111-bbbb-cccc-dddd-eeeeeeee0086"
        )
        pool = client.app.state.database.engine.pool

        with client.websocket_connect(
            "/v1/hosts/ws",
            headers={"Authorization": f"Bearer {credential}"},
        ) as websocket:
            websocket.send_json(HELLO_PAYLOAD)
            assert websocket.receive_json()["type"] == "ready"

            msg_holder: dict = {}

            def send_msg():
                msg_holder["r"] = client.post(
                    "/v1/messages",
                    headers={"Authorization": f"Bearer {access_token}"},
                    json={"text": "Pool release probe"},
                )

            msg_thread = Thread(target=send_msg)
            msg_thread.start()
            job = websocket.receive_json()["job"]

            sse_holder: dict = {}

            def read_sse():
                sse_holder["r"] = client.get(
                    f"/v1/jobs/{job['id']}/events",
                    headers={"Authorization": f"Bearer {access_token}"},
                )

            sse_thread = Thread(target=read_sse)
            sse_thread.start()
            # Give the SSE subscriber a moment to connect
            time.sleep(0.3)

            # The stream is now open and idle. Pre-#86 its request session
            # pinned a pooled connection for the stream's whole lifetime, so
            # checkedout() never returned to 0; other requests (the message
            # POST's sync-wait polls) only produce transient blips, so
            # observing a single zero proves the stream released its slot.
            released = False
            for _ in range(100):
                if pool.checkedout() == 0:
                    released = True
                    break
                time.sleep(0.05)
            assert released, "open SSE stream pinned a pooled DB connection"

            # End the stream cleanly so the reader thread can finish.
            websocket.send_json({
                "type": "job.result",
                "jobId": job["id"],
                "text": "Pool probe reply",
                "sessionId": "sess-pool",
            })
            msg_thread.join(timeout=5)
            sse_thread.join(timeout=5)
            assert not sse_thread.is_alive()

        events = parse_sse_events(sse_holder["r"].text)
        assert events[-1][0] == "done"
