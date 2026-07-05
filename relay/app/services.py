from __future__ import annotations

import time as _time
import uuid
from datetime import datetime, timedelta
from urllib.parse import urlparse, urlunparse

from fastapi import HTTPException, status
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from .config import Settings
from .hermes_adapter import HermesAdapter, HermesChatResult, HermesConversationMessage
from .models import (
    AuditLog,
    AuthSession,
    Conversation,
    Device,
    HermesHost,
    HostEnrollmentInvite,
    InboxAction,
    InboxItem,
    Message,
    MessageJob,
    PairingInvite,
    PhonePairingCode,
    PushRegistration,
    User,
    VoiceSession,
    VoiceTurn,
    utcnow,
)
from .pairing import generate_phone_pairing_code, normalize_phone_pairing_code
from .security import generate_token, hash_token, issue_tokens, normalize_datetime


def ensure_default_user(db: Session, settings: Settings) -> User:
    user = db.scalar(select(User).limit(1))
    if user is None:
        user = User(display_name=settings.default_user_display_name)
        db.add(user)
        db.commit()
        db.refresh(user)
    return user


def resolve_registration_user(db: Session, *, settings: Settings, installation_id: str) -> User:
    """The user a device/register call binds the device to.

    An installation that already has a device row keeps that device's current
    user: re-registration is the credential-recovery path (a device whose
    refresh token is gone or rejected re-registers to mint fresh tokens), and
    rebinding it to the default user would silently adopt whatever user row
    happens to sort first — on a database with stale users from pairing churn
    that can be a revoked identity. Only a brand-new installation falls back
    to the default user.
    """
    device = db.scalar(select(Device).where(Device.installation_id == installation_id))
    if device is not None:
        user = db.get(User, device.user_id)
        if user is not None:
            return user
    return ensure_default_user(db, settings)


def create_pairing_invite(db: Session, *, settings: Settings) -> tuple[PairingInvite, str]:
    invite_token = generate_token()
    invite = PairingInvite(
        token_hash=hash_token(invite_token),
        expires_at=utcnow() + timedelta(seconds=settings.pairing_code_ttl_seconds),
    )
    db.add(invite)
    db.commit()
    db.refresh(invite)
    return invite, invite_token


def create_host_enrollment_invite(
    db: Session,
    *,
    settings: Settings,
    user_id: str,
) -> tuple[HostEnrollmentInvite, str]:
    invite_token = generate_token()
    invite = HostEnrollmentInvite(
        user_id=user_id,
        token_hash=hash_token(invite_token),
        expires_at=utcnow() + timedelta(seconds=settings.host_enrollment_code_ttl_seconds),
    )
    db.add(invite)
    db.commit()
    db.refresh(invite)
    return invite, invite_token


def setup_connector_account(
    db: Session,
    *,
    settings: Settings,
    platform: str,
    hostname: str,
    hermes_command: str,
    hermes_version: str | None,
    connector_version: str,
) -> tuple[User, HermesHost, str]:
    connector_token = generate_token()
    user = User(display_name=hostname)
    db.add(user)
    db.flush()

    host = HermesHost(
        user_id=user.id,
        display_name=hostname,
        platform=platform,
        hostname=hostname,
        hermes_command=hermes_command,
        hermes_version=hermes_version,
        connector_version=connector_version,
        connector_token_hash=hash_token(connector_token),
    )
    db.add(host)
    db.commit()
    db.refresh(user)
    db.refresh(host)
    return user, host, connector_token


def _create_unique_phone_pairing_code(db: Session) -> str:
    for _ in range(32):
        code = generate_phone_pairing_code()
        existing = db.scalar(select(PhonePairingCode.id).where(PhonePairingCode.code_hash == hash_token(code)))
        if existing is None:
            return code
    raise RuntimeError("Could not generate a unique phone pairing code.")


def create_phone_pairing_code(
    db: Session,
    *,
    settings: Settings,
    host: HermesHost,
) -> tuple[PhonePairingCode, str]:
    code = _create_unique_phone_pairing_code(db)
    pairing_code = PhonePairingCode(
        user_id=host.user_id,
        host_id=host.id,
        created_by_host_id=host.id,
        code_hash=hash_token(code),
        expires_at=utcnow() + timedelta(seconds=settings.phone_pairing_code_ttl_seconds),
    )
    db.add(pairing_code)
    db.commit()
    db.refresh(pairing_code)
    return pairing_code, code


def record_audit(
    db: Session,
    *,
    actor_type: str,
    action: str,
    entity_type: str,
    actor_id: str | None = None,
    entity_id: str | None = None,
    payload: dict | None = None,
) -> None:
    db.add(
        AuditLog(
            actor_type=actor_type,
            actor_id=actor_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            payload=payload,
        )
    )


def upsert_device(
    db: Session,
    *,
    user: User,
    platform: str,
    installation_id: str,
    device_name: str,
    device_model: str,
    system_version: str,
    app_version: str,
    build_number: str,
    bundle_id: str,
    environment: str,
) -> Device:
    device = db.scalar(select(Device).where(Device.installation_id == installation_id))

    if device is None:
        device = Device(
            user_id=user.id,
            platform=platform,
            installation_id=installation_id,
            device_name=device_name,
            device_model=device_model,
            system_version=system_version,
            app_version=app_version,
            build_number=build_number,
            bundle_id=bundle_id,
            environment=environment,
            last_seen_at=utcnow(),
        )
        db.add(device)
    else:
        device.user_id = user.id
        device.platform = platform
        device.device_name = device_name
        device.device_model = device_model
        device.system_version = system_version
        device.app_version = app_version
        device.build_number = build_number
        device.bundle_id = bundle_id
        device.environment = environment
        device.last_seen_at = utcnow()

    db.commit()
    db.refresh(device)
    return device


def rotate_auth_session(
    db: Session,
    *,
    settings: Settings,
    user: User,
    device: Device,
    grace_previous_refresh: bool = False,
) -> tuple[AuthSession, str, str]:
    access_token, refresh_token, access_expires_at, refresh_expires_at = issue_tokens(settings)
    auth_session = db.scalar(
        select(AuthSession).where(
            AuthSession.device_id == device.id,
            AuthSession.revoked_at.is_(None),
        )
    )

    if auth_session is None:
        auth_session = AuthSession(
            user_id=user.id,
            device_id=device.id,
            access_token_hash=hash_token(access_token),
            refresh_token_hash=hash_token(refresh_token),
            access_expires_at=access_expires_at,
            refresh_expires_at=refresh_expires_at,
        )
        db.add(auth_session)
    else:
        if grace_previous_refresh:
            # Keep the outgoing refresh token honored for a short window: if
            # the client never receives this response (network drop between
            # rotation and persistence), its retry with the old token can
            # still recover instead of being locked out until a re-pair.
            auth_session.previous_refresh_token_hash = auth_session.refresh_token_hash
            auth_session.previous_refresh_valid_until = utcnow() + timedelta(
                seconds=settings.refresh_token_grace_seconds
            )
        else:
            # Pairing / registration rotations are identity events — no
            # stragglers from the previous credential set survive them.
            auth_session.previous_refresh_token_hash = None
            auth_session.previous_refresh_valid_until = None
        auth_session.user_id = user.id
        auth_session.access_token_hash = hash_token(access_token)
        auth_session.refresh_token_hash = hash_token(refresh_token)
        auth_session.access_expires_at = access_expires_at
        auth_session.refresh_expires_at = refresh_expires_at
        auth_session.revoked_at = None

    db.commit()
    db.refresh(auth_session)
    return auth_session, access_token, refresh_token


def refresh_auth_session(db: Session, *, settings: Settings, refresh_token: str) -> tuple[AuthSession, str, str]:
    token_hash = hash_token(refresh_token)
    auth_session = db.scalar(
        select(AuthSession).where(
            AuthSession.refresh_token_hash == token_hash,
            AuthSession.revoked_at.is_(None),
        )
    )

    if auth_session is None:
        # Grace path: the presented token was already rotated away, but the
        # rotation response may never have reached the client. Honor the
        # previous token briefly so a lost response doesn't strand the device.
        auth_session = db.scalar(
            select(AuthSession).where(
                AuthSession.previous_refresh_token_hash == token_hash,
                AuthSession.revoked_at.is_(None),
            )
        )
        if auth_session is not None and (
            auth_session.previous_refresh_valid_until is None
            or normalize_datetime(auth_session.previous_refresh_valid_until) < utcnow()
        ):
            auth_session = None

    if auth_session is None or normalize_datetime(auth_session.refresh_expires_at) < utcnow():
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid refresh token.")

    user = db.get(User, auth_session.user_id)
    device = db.get(Device, auth_session.device_id)
    if user is None or device is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid auth session.")

    return rotate_auth_session(db, settings=settings, user=user, device=device, grace_previous_refresh=True)


def redeem_pairing_invite(
    db: Session,
    *,
    settings: Settings,
    invite_token: str,
    display_name: str,
    platform: str,
    installation_id: str,
    device_name: str,
    device_model: str,
    system_version: str,
    app_version: str,
    build_number: str,
    bundle_id: str,
    environment: str,
) -> tuple[PairingInvite, User, Device, AuthSession, str, str]:
    invite = db.scalar(select(PairingInvite).where(PairingInvite.token_hash == hash_token(invite_token)))

    if invite is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This setup code is invalid.")

    if invite.redeemed_at is not None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This setup code has already been used.")

    if normalize_datetime(invite.expires_at) < utcnow():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This setup code has expired.")

    user = User(display_name=display_name.strip())
    db.add(user)
    db.commit()
    db.refresh(user)

    device = upsert_device(
        db,
        user=user,
        platform=platform,
        installation_id=installation_id,
        device_name=device_name,
        device_model=device_model,
        system_version=system_version,
        app_version=app_version,
        build_number=build_number,
        bundle_id=bundle_id,
        environment=environment,
    )
    auth_session, access_token, refresh_token = rotate_auth_session(db, settings=settings, user=user, device=device)

    invite.redeemed_at = utcnow()
    invite.redeemed_user_id = user.id
    invite.redeemed_device_id = device.id
    db.commit()
    db.refresh(invite)

    return invite, user, device, auth_session, access_token, refresh_token


def redeem_phone_pairing_code(
    db: Session,
    *,
    settings: Settings,
    raw_code: str,
    platform: str,
    installation_id: str,
    device_name: str,
    device_model: str,
    system_version: str,
    app_version: str,
    build_number: str,
    bundle_id: str,
    environment: str,
) -> tuple[PhonePairingCode, User, Device, AuthSession, str, str]:
    try:
        normalized_code = normalize_phone_pairing_code(raw_code)
    except ValueError as error:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(error)) from error

    pairing_code = db.scalar(select(PhonePairingCode).where(PhonePairingCode.code_hash == hash_token(normalized_code)))
    if pairing_code is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This phone pairing code is invalid.")

    pairing_code.attempt_count += 1
    pairing_code.last_attempt_at = utcnow()
    db.commit()
    db.refresh(pairing_code)

    if pairing_code.attempt_count > settings.phone_pairing_max_attempts_per_code:
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail="This phone pairing code has too many attempts.")

    if pairing_code.redeemed_at is not None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This phone pairing code has already been used.")

    if normalize_datetime(pairing_code.expires_at) < utcnow():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This phone pairing code has expired.")

    host = db.get(HermesHost, pairing_code.host_id)
    if host is None or host.revoked_at is not None or host.connector_token_hash is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This phone pairing code is invalid.")

    user = db.get(User, pairing_code.user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This phone pairing code is invalid.")

    device = upsert_device(
        db,
        user=user,
        platform=platform,
        installation_id=installation_id,
        device_name=device_name,
        device_model=device_model,
        system_version=system_version,
        app_version=app_version,
        build_number=build_number,
        bundle_id=bundle_id,
        environment=environment,
    )
    auth_session, access_token, refresh_token = rotate_auth_session(db, settings=settings, user=user, device=device)

    pairing_code.redeemed_at = utcnow()
    pairing_code.redeemed_device_id = device.id
    db.commit()
    db.refresh(pairing_code)

    return pairing_code, user, device, auth_session, access_token, refresh_token


def redeem_host_enrollment_invite(
    db: Session,
    *,
    settings: Settings,
    invite_token: str,
    connector_display_name: str | None,
    platform: str,
    hostname: str,
    hermes_command: str,
    hermes_version: str | None,
    connector_version: str,
) -> tuple[HostEnrollmentInvite, HermesHost, str]:
    invite = db.scalar(select(HostEnrollmentInvite).where(HostEnrollmentInvite.token_hash == hash_token(invite_token)))

    if invite is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This host setup code is invalid.")

    if invite.redeemed_at is not None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This host setup code has already been used.")

    if normalize_datetime(invite.expires_at) < utcnow():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="This host setup code has expired.")

    connector_token = generate_token()
    host = db.scalar(select(HermesHost).where(HermesHost.user_id == invite.user_id))
    if host is None:
        host = HermesHost(
            user_id=invite.user_id,
            display_name=connector_display_name,
            platform=platform,
            hostname=hostname,
            hermes_command=hermes_command,
            hermes_version=hermes_version,
            connector_version=connector_version,
            connector_token_hash=hash_token(connector_token),
        )
        db.add(host)
    else:
        host.display_name = connector_display_name
        host.platform = platform
        host.hostname = hostname
        host.hermes_command = hermes_command
        host.hermes_version = hermes_version
        host.connector_version = connector_version
        host.connector_token_hash = hash_token(connector_token)
        host.active_connection_nonce = None
        host.revoked_at = None
        host.last_seen_at = None

    db.commit()
    db.refresh(host)

    invite.redeemed_at = utcnow()
    invite.redeemed_host_id = host.id
    db.commit()
    db.refresh(invite)

    return invite, host, connector_token


def revoke_auth_session(db: Session, *, auth_session: AuthSession) -> AuthSession:
    auth_session.revoked_at = utcnow()
    db.commit()
    db.refresh(auth_session)
    return auth_session


def current_hermes_host_for_user(db: Session, *, user_id: str) -> HermesHost | None:
    host = db.scalar(select(HermesHost).where(HermesHost.user_id == user_id))
    if host is None or host.revoked_at is not None or host.connector_token_hash is None:
        return None
    return host


def revoke_current_hermes_host(db: Session, *, user_id: str) -> HermesHost | None:
    host = db.scalar(select(HermesHost).where(HermesHost.user_id == user_id))
    if host is None:
        return None

    host.connector_token_hash = None
    host.active_connection_nonce = None
    host.revoked_at = utcnow()
    db.commit()
    db.refresh(host)
    return host


def authenticate_hermes_host(db: Session, *, connector_token: str) -> HermesHost:
    host = db.scalar(
        select(HermesHost).where(
            HermesHost.connector_token_hash == hash_token(connector_token),
            HermesHost.revoked_at.is_(None),
        )
    )
    if host is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid connector credential.")
    return host


def activate_hermes_host_connection(
    db: Session,
    *,
    host: HermesHost,
    connection_nonce: str,
    connector_version: str,
    platform: str,
    hostname: str,
    hermes_command: str,
    hermes_version: str | None,
    hermes_model: str | None = None,
    display_name: str | None = None,
) -> HermesHost:
    host.active_connection_nonce = connection_nonce
    host.connector_version = connector_version
    host.platform = platform
    host.hostname = hostname
    host.hermes_command = hermes_command
    host.hermes_version = hermes_version
    host.hermes_model = hermes_model
    host.display_name = display_name
    host.last_seen_at = utcnow()
    host.last_connected_at = utcnow()
    db.commit()
    db.refresh(host)
    return host


def touch_hermes_host_connection(db: Session, *, host_id: str, connection_nonce: str) -> HermesHost | None:
    host = db.get(HermesHost, host_id)
    if host is None or host.revoked_at is not None:
        return None
    if host.active_connection_nonce != connection_nonce:
        return None

    host.last_seen_at = utcnow()
    db.commit()
    db.refresh(host)
    return host


def deactivate_hermes_host_connection(db: Session, *, host_id: str, connection_nonce: str) -> HermesHost | None:
    host = db.get(HermesHost, host_id)
    if host is None:
        return None
    if host.active_connection_nonce != connection_nonce:
        return host

    host.active_connection_nonce = None
    db.commit()
    db.refresh(host)
    return host


def create_voice_session(
    db: Session,
    *,
    user_id: str,
    host_id: str,
) -> tuple[VoiceSession, str]:
    active_sessions = db.scalars(
        select(VoiceSession).where(
            VoiceSession.user_id == user_id,
            VoiceSession.status == "active",
            VoiceSession.ended_at.is_(None),
        )
    ).all()
    for existing in active_sessions:
        existing.status = "ended"
        existing.ended_at = utcnow()
        existing.relay_tool_token_hash = None

    relay_tool_token = generate_token()
    voice_session = VoiceSession(
        user_id=user_id,
        host_id=host_id,
        relay_tool_token_hash=hash_token(relay_tool_token),
    )
    db.add(voice_session)
    db.commit()
    db.refresh(voice_session)
    return voice_session, relay_tool_token


def get_voice_session(db: Session, *, voice_session_id: str) -> VoiceSession | None:
    return db.get(VoiceSession, voice_session_id)


def get_voice_session_for_tool_token(db: Session, *, relay_tool_token: str) -> VoiceSession | None:
    voice_session = db.scalar(
        select(VoiceSession).where(
            VoiceSession.relay_tool_token_hash == hash_token(relay_tool_token),
            VoiceSession.status == "active",
            VoiceSession.ended_at.is_(None),
        )
    )
    return voice_session


def mark_voice_session_started(
    db: Session,
    *,
    voice_session_id: str,
    realtime_session_id: str | None,
    realtime_model: str | None,
    realtime_voice: str | None,
) -> VoiceSession | None:
    voice_session = db.get(VoiceSession, voice_session_id)
    if voice_session is None:
        return None
    voice_session.realtime_session_id = realtime_session_id
    voice_session.realtime_model = realtime_model
    voice_session.realtime_voice = realtime_voice
    db.commit()
    db.refresh(voice_session)
    return voice_session


def end_voice_session(
    db: Session,
    *,
    voice_session_id: str,
    last_error: str | None = None,
) -> VoiceSession | None:
    voice_session = db.get(VoiceSession, voice_session_id)
    if voice_session is None:
        return None
    if voice_session.status != "ended":
        voice_session.status = "ended"
        voice_session.ended_at = voice_session.ended_at or utcnow()
        voice_session.relay_tool_token_hash = None
    if last_error and not voice_session.last_error:
        voice_session.last_error = last_error
    db.commit()
    db.refresh(voice_session)
    return voice_session


def serialize_voice_session(voice_session: VoiceSession) -> dict:
    return {
        "id": voice_session.id,
        "status": voice_session.status,
        "model": voice_session.realtime_model,
        "voice": voice_session.realtime_voice,
        "startedAt": voice_session.started_at,
        "endedAt": voice_session.ended_at,
        "lastError": voice_session.last_error,
    }


def record_voice_turn(
    db: Session,
    *,
    voice_session_id: str,
    role: str,
    source: str,
    text: str,
    client_turn_id: str | None = None,
) -> VoiceTurn:
    if client_turn_id:
        existing = db.scalar(
            select(VoiceTurn).where(
                VoiceTurn.voice_session_id == voice_session_id,
                VoiceTurn.client_turn_id == client_turn_id,
            )
        )
        if existing is not None:
            return existing

    turn = VoiceTurn(
        voice_session_id=voice_session_id,
        client_turn_id=client_turn_id,
        role=role,
        source=source,
        text=text,
    )
    db.add(turn)
    db.commit()
    db.refresh(turn)
    return turn


def serialize_voice_turn(turn: VoiceTurn) -> dict:
    return {
        "id": turn.id,
        "voiceSessionId": turn.voice_session_id,
        "clientTurnId": turn.client_turn_id,
        "role": turn.role,
        "source": turn.source,
        "text": turn.text,
        "createdAt": turn.created_at,
    }


def inject_voice_transcript(
    db: Session,
    *,
    voice_session_id: str,
    user_id: str,
) -> Conversation:
    """Inject finalized voice turns into the current chat conversation.

    Reads all VoiceTurn rows for the given session and creates corresponding
    Message rows in the user's active conversation. Appends a system banner
    marking the end of the voice session.
    """
    turns = (
        db.scalars(
            select(VoiceTurn)
            .where(VoiceTurn.voice_session_id == voice_session_id)
            .order_by(VoiceTurn.created_at)
        )
        .all()
    )

    conversation = get_or_create_current_conversation(db, user_id=user_id)

    existing_messages = list_conversation_messages(db, conversation_id=conversation.id)
    last_message_at = existing_messages[-1].created_at if existing_messages else None
    base_created_at = utcnow()
    if last_message_at is not None:
        base_created_at = max(normalize_datetime(last_message_at), base_created_at)

    for index, turn in enumerate(turns):
        role = "voice_user" if turn.role == "user" else "voice_hermes"
        append_message(
            db,
            conversation=conversation,
            user_id=user_id,
            role=role,
            text=turn.text,
            source="voice_transcript",
            delivery_status="delivered",
            created_at_override=base_created_at + timedelta(milliseconds=index),
        )

    # System banner
    append_message(
        db,
        conversation=conversation,
        user_id=user_id,
        role="system",
        text="[Voice session ended]",
        source="voice_transcript",
        delivery_status="delivered",
        created_at_override=base_created_at + timedelta(milliseconds=len(turns)),
    )

    return conversation


def hermes_host_is_online(db: Session, *, host: HermesHost | None, settings: Settings) -> bool:
    if host is None or host.revoked_at is not None or host.last_seen_at is None:
        return False

    age = utcnow() - normalize_datetime(host.last_seen_at)

    # If the WebSocket is actively connected, the host is online.
    if host.active_connection_nonce is not None:
        if age <= timedelta(seconds=settings.connector_heartbeat_timeout_seconds):
            return True

    # Grace period: even if the WebSocket disconnected briefly (e.g., during
    # message processing), consider the host online if it was seen recently.
    # This prevents the iOS app from flashing "offline" on transient blips.
    if age <= timedelta(seconds=min(settings.connector_heartbeat_timeout_seconds, 15)):
        return True

    # If a job is actively running, the host is working even if the
    # WebSocket cycled.
    active_job = db.scalar(
        select(MessageJob.id).where(
            MessageJob.host_id == host.id,
            MessageJob.status == "running",
            MessageJob.lease_expires_at.is_not(None),
            MessageJob.lease_expires_at > utcnow(),
        )
    )
    return active_job is not None


def upsert_push_registration(
    db: Session,
    *,
    device: Device,
    apns_token: str,
    push_environment: str,
    bundle_id: str,
) -> PushRegistration:
    registration = db.scalar(select(PushRegistration).where(PushRegistration.device_id == device.id))

    if registration is None:
        registration = PushRegistration(
            device_id=device.id,
            apns_token=apns_token,
            push_environment=push_environment,
            bundle_id=bundle_id,
            last_registered_at=utcnow(),
        )
        db.add(registration)
    else:
        registration.apns_token = apns_token
        registration.push_environment = push_environment
        registration.bundle_id = bundle_id
        registration.is_active = True
        registration.last_registered_at = utcnow()

    db.commit()
    db.refresh(registration)
    return registration


def update_device_app_state(
    db: Session,
    *,
    device: Device,
    state: str,
) -> Device:
    device.app_state = state
    device.app_state_updated_at = utcnow()
    device.last_seen_at = utcnow()
    db.commit()
    db.refresh(device)
    return device


def active_push_registrations_for_user(
    db: Session,
    *,
    user_id: str,
) -> list[tuple[Device, PushRegistration]]:
    rows = db.execute(
        select(Device, PushRegistration)
        .join(PushRegistration, PushRegistration.device_id == Device.id)
        .where(
            Device.user_id == user_id,
            Device.is_active.is_(True),
            PushRegistration.is_active.is_(True),
        )
    ).all()
    return [(device, registration) for device, registration in rows]


def device_is_foreground(device: Device, *, stale_seconds: int) -> bool:
    if device.app_state != "foreground" or device.app_state_updated_at is None:
        return False
    return normalize_datetime(device.app_state_updated_at) >= utcnow() - timedelta(seconds=stale_seconds)


def create_inbox_item(
    db: Session,
    *,
    user_id: str,
    device_id: str | None,
    kind: str,
    title: str,
    body: str,
    priority: str,
    payload: dict | None,
    expires_at: datetime | None,
) -> InboxItem:
    item = InboxItem(
        user_id=user_id,
        device_id=device_id,
        kind=kind,
        title=title,
        body=body,
        priority=priority,
        payload=payload,
        expires_at=expires_at,
    )
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


def list_inbox_items(db: Session, *, user_id: str) -> list[InboxItem]:
    items = db.scalars(
        select(InboxItem)
        .where(InboxItem.user_id == user_id)
        .order_by(InboxItem.created_at.desc())
    ).all()
    return list(items)


def record_inbox_action(
    db: Session,
    *,
    item: InboxItem,
    action_id: str,
    actor_type: str,
) -> InboxAction:
    now = utcnow()

    if action_id == "dismiss":
        item.status = "dismissed"
        item.dismissed_at = now
    elif action_id in {"approve", "confirm"}:
        item.status = "completed"
        item.completed_at = now
    else:
        item.status = "opened"
        item.opened_at = now

    item.updated_at = now

    action = InboxAction(
        inbox_item_id=item.id,
        action_id=action_id,
        actor_type=actor_type,
        result={"status": item.status},
    )
    db.add(action)
    db.commit()
    db.refresh(action)
    db.refresh(item)
    return action


def get_inbox_item_for_user(db: Session, *, item_id: str, user_id: str) -> InboxItem:
    item = db.scalar(select(InboxItem).where(InboxItem.id == item_id, InboxItem.user_id == user_id))
    if item is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Inbox item not found.")
    return item


def list_inbox_actions(db: Session, *, item_id: str) -> list[InboxAction]:
    return list(
        db.scalars(
            select(InboxAction)
            .where(InboxAction.inbox_item_id == item_id)
            .order_by(InboxAction.created_at.asc())
        ).all()
    )


def default_action_titles(kind: str) -> tuple[str | None, str | None]:
    if kind == "approval":
        return "Approve", "Dismiss"
    if kind in {"suggestion", "notification", "alert", "reminder"}:
        return "Open", "Dismiss"
    return None, "Dismiss"


def get_or_create_current_conversation(db: Session, *, user_id: str) -> Conversation:
    conversation = db.scalar(
        select(Conversation).where(
            Conversation.user_id == user_id,
            Conversation.is_archived.is_(False),
        )
    )

    if conversation is None:
        conversation = Conversation(user_id=user_id, title="Hermes")
        db.add(conversation)
        db.commit()
        db.refresh(conversation)

    return conversation


def archive_current_conversation(db: Session, *, user_id: str) -> Conversation | None:
    conversation = db.scalar(
        select(Conversation).where(
            Conversation.user_id == user_id,
            Conversation.is_archived.is_(False),
        )
    )

    if conversation is None:
        return None

    conversation.is_archived = True
    conversation.hermes_session_id = None
    conversation.updated_at = utcnow()
    db.commit()
    db.refresh(conversation)
    return conversation


def list_conversation_messages(db: Session, *, conversation_id: str) -> list[Message]:
    return list(
        db.scalars(
            select(Message)
            .where(Message.conversation_id == conversation_id)
            .order_by(Message.created_at.asc())
        ).all()
    )


def get_user_message_by_client_message_id(
    db: Session,
    *,
    user_id: str,
    client_message_id: str,
) -> Message | None:
    return db.scalar(
        select(Message)
        .where(
            Message.user_id == user_id,
            Message.role == "user",
            Message.client_message_id == client_message_id,
        )
        .order_by(Message.created_at.asc())
    )


def get_message_job_for_user_message(db: Session, *, user_message_id: str) -> MessageJob | None:
    return db.scalar(select(MessageJob).where(MessageJob.user_message_id == user_message_id))


def conversation_history_before_message(db: Session, *, conversation_id: str, message_id: str) -> list[Message]:
    history: list[Message] = []
    for message in list_conversation_messages(db, conversation_id=conversation_id):
        if message.id == message_id:
            break
        history.append(message)
    return history


def append_message(
    db: Session,
    *,
    conversation: Conversation,
    user_id: str,
    role: str,
    text: str,
    client_message_id: str | None = None,
    delivery_status: str | None = None,
    source: str | None = None,
    created_at_override: datetime | None = None,
    attachments_data: list[dict] | None = None,
) -> Message:
    message = Message(
        conversation_id=conversation.id,
        user_id=user_id,
        role=role,
        text=text,
        client_message_id=client_message_id,
        delivery_status=delivery_status,
        source=source,
        attachments_data=attachments_data,
    )
    if created_at_override is not None:
        message.created_at = created_at_override
    conversation.last_message_at = utcnow()
    conversation.updated_at = utcnow()
    db.add(message)
    db.commit()
    db.refresh(message)
    db.refresh(conversation)
    return message


def update_message_delivery_status(db: Session, *, message: Message, delivery_status: str) -> Message:
    message.delivery_status = delivery_status
    db.commit()
    db.refresh(message)
    return message


def create_message_job(
    db: Session,
    *,
    user_id: str,
    conversation_id: str,
    user_message_id: str,
    session_id_snapshot: str | None,
) -> MessageJob:
    job = MessageJob(
        user_id=user_id,
        conversation_id=conversation_id,
        user_message_id=user_message_id,
        session_id_snapshot=session_id_snapshot,
        status="queued",
        retryable=True,
    )
    db.add(job)
    db.commit()
    db.refresh(job)
    return job


def get_message_job(db: Session, *, job_id: str) -> MessageJob | None:
    return db.get(MessageJob, job_id)


def requeue_expired_message_jobs(db: Session) -> None:
    now = utcnow()
    db.execute(
        update(MessageJob)
        .where(
            MessageJob.status == "running",
            MessageJob.lease_expires_at.is_not(None),
            MessageJob.lease_expires_at < now,
        )
        .values(
            status="queued",
            host_id=None,
            claimed_connection_nonce=None,
            claimed_at=None,
            lease_expires_at=None,
            updated_at=now,
        )
    )
    db.commit()


_last_requeue_at: float = 0.0
_REQUEUE_INTERVAL: float = 30.0


def claim_next_message_job(
    db: Session,
    *,
    host: HermesHost,
    connection_nonce: str,
    settings: Settings,
) -> MessageJob | None:
    global _last_requeue_at
    now_mono = _time.monotonic()
    if now_mono - _last_requeue_at >= _REQUEUE_INTERVAL:
        requeue_expired_message_jobs(db)
        _last_requeue_at = now_mono

    job = db.scalar(
        select(MessageJob)
        .where(
            MessageJob.user_id == host.user_id,
            MessageJob.status == "queued",
        )
        .order_by(MessageJob.created_at.asc())
    )
    if job is None:
        return None

    now = utcnow()
    lease_expires_at = now + timedelta(seconds=settings.connector_job_lease_seconds)
    result = db.execute(
        update(MessageJob)
        .where(
            MessageJob.id == job.id,
            MessageJob.status == "queued",
        )
        .values(
            status="running",
            host_id=host.id,
            claimed_connection_nonce=connection_nonce,
            claimed_at=now,
            lease_expires_at=lease_expires_at,
            updated_at=now,
        )
    )
    db.commit()

    if result.rowcount != 1:
        return None

    return db.get(MessageJob, job.id)


def _finalize_job_message(
    db: Session,
    *,
    job: MessageJob,
    role: str,
    text: str,
    delivery_status: str,
    attachments_data: list[dict] | None = None,
) -> Message:
    conversation = db.get(Conversation, job.conversation_id)
    if conversation is None:
        raise RuntimeError("Conversation not found for job.")

    message = Message(
        conversation_id=conversation.id,
        user_id=job.user_id,
        role=role,
        text=text,
        delivery_status=delivery_status,
        attachments_data=attachments_data,
    )
    conversation.last_message_at = utcnow()
    conversation.updated_at = utcnow()
    db.add(message)
    db.flush()
    return message


def complete_message_job(
    db: Session,
    *,
    job_id: str,
    connection_nonce: str | None,
    text: str,
    session_id: str | None,
    usage: dict | None = None,
    diff: dict | None = None,
    attachments: list[dict] | None = None,
) -> MessageJob | None:
    job = db.get(MessageJob, job_id)
    if job is None:
        return None
    if connection_nonce is not None and job.claimed_connection_nonce != connection_nonce:
        return job
    if job.result_message_id is not None or job.status == "completed":
        return job

    user_message = db.get(Message, job.user_message_id)
    conversation = db.get(Conversation, job.conversation_id)
    if user_message is None or conversation is None:
        raise RuntimeError("Message job references missing records.")

    result_message = _finalize_job_message(
        db,
        job=job,
        role="hermes",
        text=text,
        delivery_status="delivered",
        attachments_data=attachments,
    )
    user_message.delivery_status = "delivered"
    conversation.hermes_session_id = session_id or conversation.hermes_session_id
    job.status = "completed"
    job.completed_at = utcnow()
    job.result_text = text
    job.result_session_id = session_id or job.result_session_id
    job.result_message_id = result_message.id
    job.usage_data = usage
    job.diff_data = diff
    job.retryable = False
    db.commit()
    db.refresh(job)
    return job


def fail_message_job(
    db: Session,
    *,
    job_id: str,
    connection_nonce: str | None,
    error_text: str,
    retryable: bool,
) -> MessageJob | None:
    job = db.get(MessageJob, job_id)
    if job is None:
        return None
    if connection_nonce is not None and job.claimed_connection_nonce != connection_nonce:
        return job
    if job.result_message_id is not None or job.status == "completed":
        return job

    if retryable:
        job.status = "queued"
        job.host_id = None
        job.claimed_connection_nonce = None
        job.claimed_at = None
        job.lease_expires_at = None
        job.error_text = error_text
        job.retryable = True
        db.commit()
        db.refresh(job)
        return job

    user_message = db.get(Message, job.user_message_id)
    if user_message is None:
        raise RuntimeError("Message job references a missing user message.")

    system_message = _finalize_job_message(
        db,
        job=job,
        role="system",
        text=f"Hermes could not process this message: {error_text}",
        delivery_status="delivered",
    )
    user_message.delivery_status = "failed"
    job.status = "failed"
    job.completed_at = utcnow()
    job.error_text = error_text
    job.retryable = False
    job.result_message_id = system_message.id
    db.commit()
    db.refresh(job)
    return job


def generate_hermes_reply(
    *,
    adapter: HermesAdapter,
    latest_user_message: str,
    history: list[Message],
    session_id: str | None = None,
) -> HermesChatResult:
    replay_history = [
        HermesConversationMessage(role=message.role, text=message.text)
        for message in history
    ]
    return adapter.send_message(
        latest_user_message=latest_user_message,
        history=replay_history,
        session_id=session_id,
    )


def process_message_job_with_adapter(
    db: Session,
    *,
    job_id: str,
    adapter: HermesAdapter,
) -> MessageJob | None:
    job = db.get(MessageJob, job_id)
    if job is None:
        return None

    user_message = db.get(Message, job.user_message_id)
    if user_message is None:
        raise RuntimeError("Message job references a missing user message.")

    history = conversation_history_before_message(
        db,
        conversation_id=job.conversation_id,
        message_id=user_message.id,
    )
    try:
        hermes_reply = generate_hermes_reply(
            adapter=adapter,
            latest_user_message=user_message.text,
            history=history,
            session_id=job.session_id_snapshot,
        )
    except RuntimeError as error:
        return fail_message_job(
            db,
            job_id=job.id,
            connection_nonce=None,
            error_text=str(error),
            retryable=False,
        )

    return complete_message_job(
        db,
        job_id=job.id,
        connection_nonce=None,
        text=hermes_reply.text,
        session_id=hermes_reply.session_id or job.session_id_snapshot,
    )


def default_message_delivery_status(message: Message) -> str:
    if message.delivery_status:
        return message.delivery_status
    if message.role == "user":
        return "sent"
    return "delivered"


def list_message_jobs_for_conversation(db: Session, *, conversation_id: str) -> list[MessageJob]:
    return list(
        db.scalars(
            select(MessageJob)
            .where(MessageJob.conversation_id == conversation_id)
            .order_by(MessageJob.created_at.asc())
        ).all()
    )


def serialize_message(message: Message, *, job: MessageJob | None = None) -> dict:
    payload = {
        "id": message.id,
        "role": message.role,
        "text": message.text,
        "timestamp": message.created_at,
        "deliveryStatus": default_message_delivery_status(message),
    }
    if message.client_message_id:
        payload["clientMessageId"] = message.client_message_id
    if job is not None and (
        payload["deliveryStatus"] in {"pending", "failed"} or message.id == job.result_message_id
    ):
        payload["jobId"] = job.id
    if message.attachments_data:
        # Strip the heavy base64 data — only send metadata for display
        payload["attachments"] = [
            {
                "type": att.get("type", "file"),
                "filename": att.get("filename", "file"),
                "mimeType": att.get("mimeType", "application/octet-stream"),
                "thumbnailData": att.get("thumbnailData"),
            }
            for att in message.attachments_data
        ]
    return payload


def serialize_conversation(conversation: Conversation, messages: list[Message], jobs: list[MessageJob] | None = None) -> dict:
    jobs_by_message_id: dict[str, MessageJob] = {}
    for job in jobs or []:
        jobs_by_message_id[job.user_message_id] = job
        if job.result_message_id:
            jobs_by_message_id[job.result_message_id] = job
    latest_usage = None
    for job in reversed(jobs or []):
        if job.status == "completed" and job.usage_data:
            latest_usage = job.usage_data
            break
    result = {
        "id": conversation.id,
        "title": conversation.title,
        "updatedAt": conversation.updated_at,
        "messages": [
            serialize_message(message, job=jobs_by_message_id.get(message.id))
            for message in messages
        ],
    }
    if latest_usage:
        result["latestUsage"] = latest_usage
    return result


def serialize_inbox_item(item: InboxItem) -> dict:
    primary_title, secondary_title = default_action_titles(item.kind)
    return {
        "id": uuid.UUID(item.id),
        "kind": item.kind,
        "title": item.title,
        "body": item.body,
        "priority": item.priority,
        "status": item.status,
        "payload": item.payload or None,
        "createdAt": item.created_at,
        "primaryActionTitle": primary_title,
        "secondaryActionTitle": secondary_title,
    }


def serialize_hermes_host(db: Session, *, host: HermesHost | None, settings: Settings) -> dict | None:
    if host is None or host.revoked_at is not None or host.connector_token_hash is None:
        return None

    return {
        "id": host.id,
        "displayName": host.display_name,
        "hostname": host.hostname,
        "platform": host.platform,
        "connectorVersion": host.connector_version,
        "hermesCommand": host.hermes_command,
        "hermesVersion": host.hermes_version,
        "hermesModel": host.hermes_model,
        "lastSeenAt": host.last_seen_at,
        "lastConnectedAt": host.last_connected_at,
        "isOnline": hermes_host_is_online(db, host=host, settings=settings),
    }


def build_connector_websocket_url(public_base_url: str) -> str:
    parsed = urlparse(public_base_url)
    scheme = "wss" if parsed.scheme == "https" else "ws"
    return urlunparse((scheme, parsed.netloc, f"{parsed.path}/hosts/ws", "", "", ""))
