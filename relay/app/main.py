from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
import uuid

from fastapi import Body, Depends, FastAPI, Header, HTTPException, Request, WebSocket, WebSocketDisconnect, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import Settings
from .database import Database
from .hermes_adapter import build_hermes_adapter
from .models import Conversation, HermesHost, Message, PushRegistration
from .pairing import HostSetupCodePayload, format_phone_pairing_code, build_host_setup_code
from .rate_limit import PhonePairingRateLimiter
from .schemas import (
    ConnectorSetupRequest,
    DeviceRegisterRequest,
    HostEnrollmentCodeCreateRequest,
    HostRedeemRequest,
    InboxActionRequest,
    InternalInboxCreateRequest,
    MessageCreateRequest,
    PairingRedeemRequest,
    PhonePairingRedeemRequest,
    SensorHealthRequest,
    SensorLocationRequest,
    PushRegisterRequest,
    RefreshRequest,
)
from .security import AuthContext, get_auth_context, get_db, get_settings, require_internal_key
from .services import (
    activate_hermes_host_connection,
    append_message,
    authenticate_hermes_host,
    build_connector_websocket_url,
    claim_next_message_job,
    complete_message_job,
    conversation_history_before_message,
    create_phone_pairing_code,
    create_host_enrollment_invite,
    create_inbox_item,
    create_message_job,
    current_hermes_host_for_user,
    deactivate_hermes_host_connection,
    ensure_default_user,
    fail_message_job,
    get_inbox_item_for_user,
    get_message_job,
    get_message_job_for_user_message,
    get_or_create_current_conversation,
    get_user_message_by_client_message_id,
    hermes_host_is_online,
    list_conversation_messages,
    list_inbox_actions,
    list_inbox_items,
    list_message_jobs_for_conversation,
    record_audit,
    record_inbox_action,
    redeem_phone_pairing_code,
    redeem_host_enrollment_invite,
    redeem_pairing_invite,
    refresh_auth_session,
    revoke_auth_session,
    revoke_current_hermes_host,
    rotate_auth_session,
    serialize_conversation,
    serialize_hermes_host,
    serialize_inbox_item,
    serialize_message,
    setup_connector_account,
    touch_hermes_host_connection,
    upsert_device,
    upsert_push_registration,
    process_message_job_with_adapter,
)


def success(data: dict) -> dict:
    return {
        "data": data,
        "meta": {
            "requestId": str(uuid.uuid4()),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }


def success_response(data: dict, *, status_code: int = status.HTTP_200_OK) -> JSONResponse:
    return JSONResponse(status_code=status_code, content=jsonable_encoder(success(data)))


def parse_bearer_token(authorization_header: str | None) -> str | None:
    if authorization_header is None:
        return None
    prefix = "Bearer "
    if not authorization_header.startswith(prefix):
        return None
    return authorization_header[len(prefix) :].strip() or None


def reply_state_for_job(job_status: str) -> str:
    if job_status == "completed":
        return "delivered"
    if job_status == "failed":
        return "failed"
    return "pending"


@dataclass
class ConnectorSession:
    websocket: WebSocket
    host_id: str
    connection_nonce: str
    busy: bool = False


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    database = Database(settings.database_url)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        database.create_all()
        yield

    app = FastAPI(title=settings.service_name, version=settings.version, lifespan=lifespan)
    app.state.settings = settings
    app.state.database = database
    app.state.hermes_adapter = build_hermes_adapter(settings)
    app.state.phone_pairing_rate_limiter = PhonePairingRateLimiter(
        max_attempts=settings.phone_pairing_max_attempts_per_ip,
        window_seconds=settings.phone_pairing_rate_limit_window_seconds,
    )
    app.state.connector_sessions: dict[str, ConnectorSession] = {}
    app.state.sensor_delivery_waiters: dict[str, asyncio.Future[bool]] = {}

    def require_connector_host(
        authorization: str | None = Header(default=None),
        db: Session = Depends(get_db),
    ) -> HermesHost:
        connector_token = parse_bearer_token(authorization)
        if connector_token is None:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing connector credential.")
        return authenticate_hermes_host(db, connector_token=connector_token)

    async def wait_for_job_completion(job_id: str, timeout_seconds: int) -> object | None:
        deadline = asyncio.get_running_loop().time() + timeout_seconds
        while asyncio.get_running_loop().time() < deadline:
            with database.session() as db:
                job = get_message_job(db, job_id=job_id)
                if job is None or job.status in {"completed", "failed"}:
                    return job
            await asyncio.sleep(0.25)
        return None

    def connector_session_for_user(user_id: str) -> ConnectorSession | None:
        return app.state.connector_sessions.get(user_id)

    def set_connector_session(user_id: str, session: ConnectorSession) -> None:
        app.state.connector_sessions[user_id] = session

    def clear_connector_session(user_id: str | None, connection_nonce: str | None) -> None:
        if user_id is None or connection_nonce is None:
            return
        session = connector_session_for_user(user_id)
        if session is None or session.connection_nonce != connection_nonce:
            return
        app.state.connector_sessions.pop(user_id, None)

    def resolve_sensor_delivery(delivery_id: str | None, *, delivered: bool) -> None:
        if delivery_id is None:
            return
        waiter = app.state.sensor_delivery_waiters.pop(delivery_id, None)
        if waiter is not None and not waiter.done():
            waiter.set_result(delivered)

    async def forward_sensor_payload(
        *,
        user_id: str,
        payload: dict,
        ack_timeout_seconds: float,
    ) -> JSONResponse:
        session = connector_session_for_user(user_id)
        if session is None or session.busy:
            return success_response({"deliveryState": "retry"}, status_code=status.HTTP_202_ACCEPTED)

        delivery_id = str(uuid.uuid4())
        message = dict(payload)
        message["deliveryId"] = delivery_id
        waiter: asyncio.Future[bool] = asyncio.get_running_loop().create_future()
        app.state.sensor_delivery_waiters[delivery_id] = waiter

        try:
            await session.websocket.send_json(message)
        except Exception:
            clear_connector_session(user_id, session.connection_nonce)
            app.state.sensor_delivery_waiters.pop(delivery_id, None)
            return success_response({"deliveryState": "retry"}, status_code=status.HTTP_202_ACCEPTED)

        try:
            delivered = await asyncio.wait_for(waiter, timeout=ack_timeout_seconds)
        except asyncio.TimeoutError:
            app.state.sensor_delivery_waiters.pop(delivery_id, None)
            return success_response({"deliveryState": "retry"}, status_code=status.HTTP_202_ACCEPTED)

        status_code = status.HTTP_200_OK if delivered else status.HTTP_202_ACCEPTED
        delivery_state = "delivered" if delivered else "retry"
        return success_response({"deliveryState": delivery_state}, status_code=status_code)

    def build_message_response_payload(db: Session, *, conversation_id: str, job_id: str) -> tuple[dict, int]:
        job = get_message_job(db, job_id=job_id)
        if job is None:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Message job not found.")

        conversation = db.get(Conversation, conversation_id)
        if conversation is None:
            raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Conversation not found.")

        user_message = db.get(Message, job.user_message_id)
        messages = list_conversation_messages(db, conversation_id=conversation_id)
        jobs = list_message_jobs_for_conversation(db, conversation_id=conversation_id)

        payload = {
            "replyState": reply_state_for_job(job.status),
            "conversation": serialize_conversation(conversation, messages, jobs=jobs),
            "userMessage": serialize_message(user_message, job=job) if user_message else None,
        }

        if job.result_message_id:
            result_message = db.get(Message, job.result_message_id)
            if result_message is not None:
                payload["message"] = serialize_message(result_message)

        status_code = status.HTTP_202_ACCEPTED if job.status in {"queued", "running"} else status.HTTP_200_OK
        return payload, status_code

    def build_job_execute_payload(db: Session, *, job_id: str) -> dict:
        job = get_message_job(db, job_id=job_id)
        if job is None:
            raise RuntimeError("Message job not found.")

        user_message = db.get(Message, job.user_message_id)
        if user_message is None:
            raise RuntimeError("User message not found for job.")

        history = conversation_history_before_message(
            db,
            conversation_id=job.conversation_id,
            message_id=user_message.id,
        )
        return {
            "type": "job.execute",
            "version": 1,
            "job": {
                "id": job.id,
                "conversationId": job.conversation_id,
                "latestUserMessage": user_message.text,
                "history": [{"role": message.role, "text": message.text} for message in history],
                "sessionId": job.session_id_snapshot,
                "timeoutSeconds": settings.connector_job_lease_seconds,
            },
        }

    @app.get("/v1/health")
    def health() -> dict:
        return success({"status": "ok"})

    @app.get("/v1/version")
    def version(request_settings: Settings = Depends(get_settings)) -> dict:
        return success(
            {
                "service": request_settings.service_name,
                "version": request_settings.version,
                "environment": request_settings.environment,
            }
        )

    @app.post("/v1/connector/setup")
    def connector_setup(
        payload: ConnectorSetupRequest,
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> dict:
        user, host, connector_token = setup_connector_account(
            db,
            settings=request_settings,
            platform=payload.connector.platform,
            hostname=payload.connector.hostname,
            hermes_command=payload.connector.hermesCommand,
            hermes_version=payload.connector.hermesVersion,
            connector_version=payload.connector.connectorVersion,
        )
        record_audit(
            db,
            actor_type="connector",
            actor_id=host.id,
            action="connector.setup",
            entity_type="hermes_host",
            entity_id=host.id,
            payload={"userId": user.id},
        )
        db.commit()
        return success(
            {
                "user": {
                    "id": user.id,
                    "displayName": user.display_name,
                },
                "host": {
                    "id": host.id,
                    "userId": host.user_id,
                },
                "connectorCredential": connector_token,
                "webSocketURL": build_connector_websocket_url(request_settings.public_base_url),
                "relayURL": request_settings.public_base_url,
            }
        )

    @app.post("/v1/connector/phone-pairing-codes")
    def create_phone_pairing(
        host: HermesHost = Depends(require_connector_host),
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> dict:
        pairing_code, normalized_code = create_phone_pairing_code(
            db,
            settings=request_settings,
            host=host,
        )
        display_code = format_phone_pairing_code(normalized_code)
        record_audit(
            db,
            actor_type="connector",
            actor_id=host.id,
            action="phone_pairing_code.create",
            entity_type="phone_pairing_code",
            entity_id=pairing_code.id,
            payload={"displayCode": display_code},
        )
        db.commit()
        return success(
            {
                "code": normalized_code,
                "displayCode": display_code,
                "expiresAt": pairing_code.expires_at,
            }
        )

    @app.post("/v1/phone-pairing/redeem")
    def redeem_phone_pairing(
        payload: PhonePairingRedeemRequest,
        request: Request,
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> dict:
        client_host = request.client.host if request.client else ""
        rate_limiter: PhonePairingRateLimiter = request.app.state.phone_pairing_rate_limiter
        if rate_limiter.is_limited(client_host):
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="Too many pairing attempts. Try again later.")

        try:
            pairing_code, user, device, auth_session, access_token, refresh_token = redeem_phone_pairing_code(
                db,
                settings=request_settings,
                raw_code=payload.code,
                platform=payload.device.platform,
                installation_id=str(payload.device.installationId),
                device_name=payload.device.deviceName,
                device_model=payload.device.deviceModel,
                system_version=payload.device.systemVersion,
                app_version=payload.device.appVersion,
                build_number=payload.device.buildNumber,
                bundle_id=payload.device.bundleId,
                environment=payload.client.environment,
            )
        except HTTPException as error:
            rate_limiter.register_failure(client_host)
            raise error

        record_audit(
            db,
            actor_type="app",
            actor_id=device.id,
            action="phone_pairing.redeem",
            entity_type="phone_pairing_code",
            entity_id=pairing_code.id,
            payload={"installationId": str(payload.device.installationId)},
        )
        db.commit()

        return success(
            {
                "user": {
                    "id": user.id,
                    "displayName": user.display_name,
                },
                "deviceId": device.id,
                "deviceRegistered": True,
                "session": {
                    "connectionStatus": "connected",
                    "isMockMode": False,
                    "backendEndpoint": request_settings.public_base_url,
                    "lastSyncAt": auth_session.updated_at,
                },
                "auth": {
                    "accessToken": access_token,
                    "refreshToken": refresh_token,
                    "expiresAt": auth_session.access_expires_at,
                },
            }
        )

    # ── Sensor data forwarding ─────────────────────────────────

    @app.post("/v1/device/sensor/location")
    async def sensor_location(
        payload: SensorLocationRequest,
        request_settings: Settings = Depends(get_settings),
        auth: AuthContext = Depends(get_auth_context),
    ) -> JSONResponse:
        return await forward_sensor_payload(
            user_id=auth.user.id,
            ack_timeout_seconds=request_settings.connector_sensor_ack_timeout_seconds,
            payload={
                "type": "sensor.location",
                "latitude": payload.latitude,
                "longitude": payload.longitude,
                "altitude": payload.altitude,
                "accuracy": payload.accuracy,
                "address": payload.address,
                "recordedAt": payload.recordedAt,
            },
        )

    @app.post("/v1/device/sensor/health")
    async def sensor_health(
        payload: SensorHealthRequest,
        request_settings: Settings = Depends(get_settings),
        auth: AuthContext = Depends(get_auth_context),
    ) -> JSONResponse:
        return await forward_sensor_payload(
            user_id=auth.user.id,
            ack_timeout_seconds=request_settings.connector_sensor_ack_timeout_seconds,
            payload={
                "type": "sensor.health",
                "samples": [
                    {
                        "metric": s.metric,
                        "value": s.value,
                        "unit": s.unit,
                        "startAt": s.startAt,
                        "endAt": s.endAt,
                    }
                    for s in payload.samples
                ],
            },
        )

    def _meta() -> dict:
        return {"requestId": str(uuid.uuid4()), "timestamp": datetime.now(timezone.utc).isoformat()}

    @app.post("/v1/device/register")
    def register_device(
        payload: DeviceRegisterRequest,
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> dict:
        user = ensure_default_user(db, request_settings)
        device = upsert_device(
            db,
            user=user,
            platform=payload.device.platform,
            installation_id=str(payload.device.installationId),
            device_name=payload.device.deviceName,
            device_model=payload.device.deviceModel,
            system_version=payload.device.systemVersion,
            app_version=payload.device.appVersion,
            build_number=payload.device.buildNumber,
            bundle_id=payload.device.bundleId,
            environment=payload.client.environment,
        )
        auth_session, access_token, refresh_token = rotate_auth_session(
            db,
            settings=request_settings,
            user=user,
            device=device,
        )

        record_audit(
            db,
            actor_type="app",
            actor_id=device.id,
            action="device.register",
            entity_type="device",
            entity_id=device.id,
            payload={"installationId": str(payload.device.installationId)},
        )
        db.commit()

        return success(
            {
                "deviceId": device.id,
                "deviceRegistered": True,
                "session": {
                    "connectionStatus": "connected",
                    "isMockMode": False,
                    "backendEndpoint": request_settings.public_base_url,
                    "lastSyncAt": None,
                },
                "auth": {
                    "accessToken": access_token,
                    "refreshToken": refresh_token,
                    "expiresAt": auth_session.access_expires_at,
                },
            }
        )

    @app.post("/v1/pairing/redeem")
    def redeem_pairing(
        payload: PairingRedeemRequest,
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> dict:
        invite, user, device, auth_session, access_token, refresh_token = redeem_pairing_invite(
            db,
            settings=request_settings,
            invite_token=payload.inviteToken,
            display_name=payload.displayName,
            platform=payload.device.platform,
            installation_id=str(payload.device.installationId),
            device_name=payload.device.deviceName,
            device_model=payload.device.deviceModel,
            system_version=payload.device.systemVersion,
            app_version=payload.device.appVersion,
            build_number=payload.device.buildNumber,
            bundle_id=payload.device.bundleId,
            environment=payload.client.environment,
        )

        record_audit(
            db,
            actor_type="app",
            actor_id=device.id,
            action="pairing.redeem",
            entity_type="pairing_invite",
            entity_id=invite.id,
            payload={"installationId": str(payload.device.installationId)},
        )
        db.commit()

        return success(
            {
                "user": {
                    "id": user.id,
                    "displayName": user.display_name,
                },
                "deviceId": device.id,
                "deviceRegistered": True,
                "session": {
                    "connectionStatus": "connected",
                    "isMockMode": False,
                    "backendEndpoint": request_settings.public_base_url,
                    "lastSyncAt": auth_session.updated_at,
                },
                "auth": {
                    "accessToken": access_token,
                    "refreshToken": refresh_token,
                    "expiresAt": auth_session.access_expires_at,
                },
            }
        )

    @app.post("/v1/hosts/enrollment-codes")
    def create_host_enrollment_code(
        payload: HostEnrollmentCodeCreateRequest | None = Body(default=None),
        auth: AuthContext = Depends(get_auth_context),
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> dict:
        invite, invite_token = create_host_enrollment_invite(db, settings=request_settings, user_id=auth.user.id)
        setup_code = build_host_setup_code(
            HostSetupCodePayload(
                relay_url=request_settings.public_base_url,
                enrollment_token=invite_token,
                expires_at=invite.expires_at,
            )
        )
        host = current_hermes_host_for_user(db, user_id=auth.user.id)
        record_audit(
            db,
            actor_type="user",
            actor_id=auth.user.id,
            action="host.enrollment_code.create",
            entity_type="host_enrollment_invite",
            entity_id=invite.id,
            payload={"displayName": payload.displayName if payload else None},
        )
        db.commit()
        return success(
            {
                "setupCode": setup_code,
                "expiresAt": invite.expires_at,
                "relayHost": request_settings.public_base_url,
                "host": serialize_hermes_host(db, host=host, settings=request_settings),
            }
        )

    @app.get("/v1/hosts/current")
    def current_host(
        auth: AuthContext = Depends(get_auth_context),
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> dict:
        host = current_hermes_host_for_user(db, user_id=auth.user.id)
        return success({"host": serialize_hermes_host(db, host=host, settings=request_settings)})

    @app.post("/v1/hosts/current/revoke")
    def revoke_current_host(
        auth: AuthContext = Depends(get_auth_context),
        db: Session = Depends(get_db),
    ) -> dict:
        host = revoke_current_hermes_host(db, user_id=auth.user.id)
        record_audit(
            db,
            actor_type="user",
            actor_id=auth.user.id,
            action="host.revoke",
            entity_type="hermes_host",
            entity_id=host.id if host else None,
        )
        db.commit()
        return success({"revoked": host is not None})

    @app.post("/v1/hosts/redeem")
    def redeem_host(
        payload: HostRedeemRequest,
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> dict:
        invite, host, connector_token = redeem_host_enrollment_invite(
            db,
            settings=request_settings,
            invite_token=payload.enrollmentToken,
            connector_display_name=payload.displayName,
            platform=payload.connector.platform,
            hostname=payload.connector.hostname,
            hermes_command=payload.connector.hermesCommand,
            hermes_version=payload.connector.hermesVersion,
            connector_version=payload.connector.connectorVersion,
        )
        record_audit(
            db,
            actor_type="connector",
            actor_id=host.id,
            action="host.redeem",
            entity_type="host_enrollment_invite",
            entity_id=invite.id,
            payload={"hostname": payload.connector.hostname},
        )
        db.commit()
        return success(
            {
                "host": {
                    "id": host.id,
                    "userId": host.user_id,
                },
                "connectorCredential": connector_token,
                "webSocketURL": build_connector_websocket_url(request_settings.public_base_url),
                "relayURL": request_settings.public_base_url,
            }
        )

    @app.get("/v1/session")
    def session(
        auth: AuthContext = Depends(get_auth_context),
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> dict:
        push_registered = db.scalar(
            select(PushRegistration).where(
                PushRegistration.device_id == auth.device.id,
                PushRegistration.is_active.is_(True),
            )
        )

        return success(
            {
                "user": {
                    "id": auth.user.id,
                    "displayName": auth.user.display_name,
                },
                "device": {
                    "id": auth.device.id,
                    "registered": True,
                },
                "session": {
                    "connectionStatus": "connected",
                    "isMockMode": False,
                    "backendEndpoint": request_settings.public_base_url,
                    "lastSyncAt": auth.device.last_seen_at,
                },
                "push": {
                    "tokenRegistered": push_registered is not None,
                },
            }
        )

    @app.post("/v1/auth/refresh")
    def refresh_auth(
        payload: RefreshRequest,
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> dict:
        auth_session, access_token, refresh_token = refresh_auth_session(
            db,
            settings=request_settings,
            refresh_token=payload.refreshToken,
        )
        record_audit(
            db,
            actor_type="app",
            actor_id=auth_session.device_id,
            action="auth.refresh",
            entity_type="auth_session",
            entity_id=auth_session.id,
        )
        db.commit()

        return success(
            {
                "accessToken": access_token,
                "refreshToken": refresh_token,
                "expiresAt": auth_session.access_expires_at,
            }
        )

    @app.post("/v1/auth/revoke")
    def revoke_auth(
        auth: AuthContext = Depends(get_auth_context),
        db: Session = Depends(get_db),
    ) -> dict:
        revoke_auth_session(db, auth_session=auth.auth_session)
        record_audit(
            db,
            actor_type="app",
            actor_id=auth.device.id,
            action="auth.revoke",
            entity_type="auth_session",
            entity_id=auth.auth_session.id,
        )
        db.commit()

        return success({"revoked": True})

    @app.post("/v1/push/register")
    def register_push(
        payload: PushRegisterRequest,
        auth: AuthContext = Depends(get_auth_context),
        db: Session = Depends(get_db),
    ) -> dict:
        if str(payload.deviceId) != auth.device.id:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Cannot register push token for another device.")

        registration = upsert_push_registration(
            db,
            device=auth.device,
            apns_token=payload.apnsToken,
            push_environment=payload.pushEnvironment,
            bundle_id=payload.bundleId,
        )
        record_audit(
            db,
            actor_type="app",
            actor_id=auth.device.id,
            action="push.register",
            entity_type="push_registration",
            entity_id=registration.id,
        )
        db.commit()

        return success(
            {
                "registered": True,
                "updatedAt": registration.updated_at,
            }
        )

    @app.get("/v1/conversations/current")
    def current_conversation(auth: AuthContext = Depends(get_auth_context), db: Session = Depends(get_db)) -> dict:
        conversation = get_or_create_current_conversation(db, user_id=auth.user.id)
        messages = list_conversation_messages(db, conversation_id=conversation.id)
        jobs = list_message_jobs_for_conversation(db, conversation_id=conversation.id)
        return success({"conversation": serialize_conversation(conversation, messages, jobs=jobs)})

    @app.post("/v1/messages")
    async def create_message(
        payload: MessageCreateRequest,
        auth: AuthContext = Depends(get_auth_context),
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> JSONResponse:
        client_message_id = str(payload.clientMessageId) if payload.clientMessageId else None
        if client_message_id is not None:
            existing_user_message = get_user_message_by_client_message_id(
                db,
                user_id=auth.user.id,
                client_message_id=client_message_id,
            )
            if existing_user_message is not None:
                existing_job = get_message_job_for_user_message(db, user_message_id=existing_user_message.id)
                if existing_job is not None:
                    payload_data, status_code = build_message_response_payload(
                        db,
                        conversation_id=existing_user_message.conversation_id,
                        job_id=existing_job.id,
                    )
                    record_audit(
                        db,
                        actor_type="user",
                        actor_id=auth.user.id,
                        action="chat.message.create",
                        entity_type="conversation",
                        entity_id=existing_user_message.conversation_id,
                        payload={
                            "jobId": existing_job.id,
                            "replyState": payload_data["replyState"],
                            "deduplicated": True,
                            "clientMessageId": client_message_id,
                        },
                    )
                    db.commit()
                    return success_response(payload_data, status_code=status_code)

        conversation = get_or_create_current_conversation(db, user_id=auth.user.id)
        initial_delivery_status = "pending" if request_settings.hermes_adapter == "connector" else "sent"
        user_message = append_message(
            db,
            conversation=conversation,
            user_id=auth.user.id,
            role="user",
            text=payload.text,
            client_message_id=client_message_id,
            delivery_status=initial_delivery_status,
        )

        job = create_message_job(
            db,
            user_id=auth.user.id,
            conversation_id=conversation.id,
            user_message_id=user_message.id,
            session_id_snapshot=conversation.hermes_session_id,
        )

        if request_settings.hermes_adapter == "connector":
            host = current_hermes_host_for_user(db, user_id=auth.user.id)
            if host is not None and hermes_host_is_online(db, host=host, settings=request_settings):
                await wait_for_job_completion(job.id, request_settings.connector_sync_wait_seconds)
        else:
            process_message_job_with_adapter(
                db,
                job_id=job.id,
                adapter=app.state.hermes_adapter,
            )

        db.expire_all()
        payload_data, status_code = build_message_response_payload(db, conversation_id=conversation.id, job_id=job.id)
        record_audit(
            db,
            actor_type="user",
            actor_id=auth.user.id,
            action="chat.message.create",
            entity_type="conversation",
            entity_id=conversation.id,
            payload={"jobId": job.id, "replyState": payload_data["replyState"]},
        )
        db.commit()
        return success_response(payload_data, status_code=status_code)

    @app.get("/v1/inbox")
    def inbox(auth: AuthContext = Depends(get_auth_context), db: Session = Depends(get_db)) -> dict:
        items = [serialize_inbox_item(item) for item in list_inbox_items(db, user_id=auth.user.id)]
        return success({"items": items})

    @app.post("/v1/inbox/{item_id}/action")
    def inbox_action(
        item_id: str,
        payload: InboxActionRequest,
        auth: AuthContext = Depends(get_auth_context),
        db: Session = Depends(get_db),
    ) -> dict:
        item = get_inbox_item_for_user(db, item_id=item_id, user_id=auth.user.id)
        action = record_inbox_action(db, item=item, action_id=payload.actionId, actor_type="user")
        record_audit(
            db,
            actor_type="user",
            actor_id=auth.user.id,
            action=f"inbox.{payload.actionId}",
            entity_type="inbox_item",
            entity_id=item.id,
        )
        db.commit()

        return success(
            {
                "itemID": item.id,
                "actionID": action.action_id,
                "status": item.status,
                "completedAt": action.created_at,
            }
        )

    @app.post("/internal/inbox/create", dependencies=[Depends(require_internal_key)])
    def internal_create_inbox(
        payload: InternalInboxCreateRequest,
        db: Session = Depends(get_db),
        request_settings: Settings = Depends(get_settings),
    ) -> dict:
        user = ensure_default_user(db, request_settings)
        target_user_id = str(payload.userId) if payload.userId else user.id
        target_device_id = str(payload.deviceId) if payload.deviceId else None
        item = create_inbox_item(
            db,
            user_id=target_user_id,
            device_id=target_device_id,
            kind=payload.kind,
            title=payload.title,
            body=payload.body,
            priority=payload.priority,
            payload=payload.payload,
            expires_at=payload.expiresAt,
        )
        record_audit(
            db,
            actor_type="hermes",
            action="internal.inbox.create",
            entity_type="inbox_item",
            entity_id=item.id,
        )
        db.commit()

        return success({"item": serialize_inbox_item(item)})

    @app.get("/internal/inbox/{item_id}/actions", dependencies=[Depends(require_internal_key)])
    def internal_inbox_actions(item_id: str, db: Session = Depends(get_db)) -> dict:
        actions = list_inbox_actions(db, item_id=item_id)
        return success(
            {
                "actions": [
                    {
                        "id": action.id,
                        "actionId": action.action_id,
                        "actorType": action.actor_type,
                        "result": action.result,
                        "createdAt": action.created_at,
                    }
                    for action in actions
                ]
            }
        )

    @app.websocket("/v1/hosts/ws")
    async def hosts_websocket(websocket: WebSocket) -> None:
        await websocket.accept()
        authorization = websocket.headers.get("authorization")
        connector_token = parse_bearer_token(authorization)
        if connector_token is None:
            await websocket.close(code=4401)
            return

        try:
            hello_message = await websocket.receive_json()
        except WebSocketDisconnect:
            return

        if hello_message.get("type") != "hello":
            await websocket.close(code=4400)
            return

        connector_info = hello_message.get("connector") or {}
        connection_nonce = str(uuid.uuid4())
        host_id: str | None = None
        user_id: str | None = None

        try:
            with database.session() as db:
                host = authenticate_hermes_host(db, connector_token=connector_token)
                activated_host = activate_hermes_host_connection(
                    db,
                    host=host,
                    connection_nonce=connection_nonce,
                    connector_version=connector_info.get("connectorVersion", "unknown"),
                    platform=connector_info.get("platform", "unknown"),
                    hostname=connector_info.get("hostname", "unknown"),
                    hermes_command=connector_info.get("hermesCommand", "hermes"),
                    hermes_version=connector_info.get("hermesVersion"),
                    display_name=connector_info.get("displayName"),
                )
                host_id = activated_host.id
                user_id = activated_host.user_id
                set_connector_session(
                    user_id,
                    ConnectorSession(
                        websocket=websocket,
                        host_id=host_id,
                        connection_nonce=connection_nonce,
                    ),
                )
                ready_payload = {
                    "type": "ready",
                    "version": 1,
                    "host": serialize_hermes_host(db, host=activated_host, settings=settings),
                }

            await websocket.send_json(jsonable_encoder(ready_payload))

            while True:
                with database.session() as db:
                    host = db.get(HermesHost, host_id)
                    if host is None or host.active_connection_nonce != connection_nonce or host.revoked_at is not None:
                        await websocket.close(code=4401)
                        return

                    claimed_job = claim_next_message_job(
                        db,
                        host=host,
                        connection_nonce=connection_nonce,
                        settings=settings,
                    )

                    if claimed_job is not None:
                        job_payload = build_job_execute_payload(db, job_id=claimed_job.id)
                    else:
                        job_payload = None

                if job_payload is not None:
                    session = connector_session_for_user(user_id)
                    if session is not None and session.connection_nonce == connection_nonce:
                        session.busy = True

                    try:
                        await websocket.send_json(job_payload)

                        while True:
                            try:
                                incoming = await asyncio.wait_for(
                                    websocket.receive_json(),
                                    timeout=settings.connector_heartbeat_timeout_seconds,
                                )
                            except asyncio.TimeoutError:
                                await websocket.close(code=1011)
                                return

                            message_type = incoming.get("type")
                            if message_type == "heartbeat":
                                with database.session() as db:
                                    touched = touch_hermes_host_connection(db, host_id=host_id, connection_nonce=connection_nonce)
                                if touched is None:
                                    await websocket.close(code=4401)
                                    return
                                continue

                            if message_type == "sensor.ack":
                                resolve_sensor_delivery(
                                    incoming.get("deliveryId"),
                                    delivered=incoming.get("deliveryState", "delivered") == "delivered",
                                )
                                continue

                            if message_type == "job.result" and incoming.get("jobId") == claimed_job.id:
                                with database.session() as db:
                                    completed = complete_message_job(
                                        db,
                                        job_id=claimed_job.id,
                                        connection_nonce=connection_nonce,
                                        text=incoming.get("text", "").strip(),
                                        session_id=incoming.get("sessionId"),
                                    )
                                    if completed is None:
                                        await websocket.close(code=1011)
                                        return
                                break

                            if message_type == "job.failed" and incoming.get("jobId") == claimed_job.id:
                                with database.session() as db:
                                    failed = fail_message_job(
                                        db,
                                        job_id=claimed_job.id,
                                        connection_nonce=connection_nonce,
                                        error_text=incoming.get("error", "Hermes connector failed."),
                                        retryable=bool(incoming.get("retryable", False)),
                                    )
                                    if failed is None:
                                        await websocket.close(code=1011)
                                        return
                                break

                            await websocket.close(code=4400)
                            return
                    finally:
                        session = connector_session_for_user(user_id)
                        if session is not None and session.connection_nonce == connection_nonce:
                            session.busy = False

                    continue

                try:
                    incoming = await asyncio.wait_for(
                        websocket.receive_json(),
                        timeout=settings.connector_idle_poll_interval_seconds,
                    )
                except asyncio.TimeoutError:
                    continue

                if incoming.get("type") == "heartbeat":
                    with database.session() as db:
                        touched = touch_hermes_host_connection(db, host_id=host_id, connection_nonce=connection_nonce)
                    if touched is None:
                        await websocket.close(code=4401)
                        return
                    continue

                if incoming.get("type") == "sensor.ack":
                    resolve_sensor_delivery(
                        incoming.get("deliveryId"),
                        delivered=incoming.get("deliveryState", "delivered") == "delivered",
                    )
                    with database.session() as db:
                        touched = touch_hermes_host_connection(db, host_id=host_id, connection_nonce=connection_nonce)
                    if touched is None:
                        await websocket.close(code=4401)
                        return
                    continue

                await websocket.close(code=4400)
                return
        except HTTPException:
            await websocket.close(code=4401)
            return
        except WebSocketDisconnect:
            return
        finally:
            if host_id is not None:
                clear_connector_session(user_id, connection_nonce)
                with database.session() as db:
                    deactivate_hermes_host_connection(db, host_id=host_id, connection_nonce=connection_nonce)

    return app


app = create_app()
