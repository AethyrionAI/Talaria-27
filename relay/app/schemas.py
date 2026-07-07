from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field, model_validator


class Meta(BaseModel):
    requestId: str
    timestamp: datetime


class ErrorPayload(BaseModel):
    code: str
    message: str
    retryable: bool = False


class ErrorEnvelope(BaseModel):
    error: ErrorPayload


class SuccessEnvelope(BaseModel):
    data: dict[str, Any]
    meta: Meta


class DeviceInfo(BaseModel):
    platform: str
    deviceName: str
    appVersion: str
    buildNumber: str
    bundleId: str
    installationId: UUID
    deviceModel: str
    systemVersion: str


class ClientInfo(BaseModel):
    environment: str


class DeviceRegisterRequest(BaseModel):
    device: DeviceInfo
    client: ClientInfo


class PairingRedeemRequest(BaseModel):
    inviteToken: str = Field(min_length=1)
    displayName: str = Field(min_length=1, max_length=120)
    device: DeviceInfo
    client: ClientInfo


class HostEnrollmentCodeCreateRequest(BaseModel):
    displayName: str | None = Field(default=None, max_length=120)


class HostConnectorInfo(BaseModel):
    platform: str
    hostname: str
    connectorVersion: str
    hermesCommand: str
    hermesVersion: str | None = None


class ConnectorSetupRequest(BaseModel):
    connector: HostConnectorInfo
    installationSecret: str | None = None


class HostRedeemRequest(BaseModel):
    enrollmentToken: str = Field(min_length=1)
    displayName: str | None = Field(default=None, max_length=120)
    connector: HostConnectorInfo


class PhonePairingRedeemRequest(BaseModel):
    code: str = Field(min_length=1, max_length=32)
    device: DeviceInfo
    client: ClientInfo


class RefreshRequest(BaseModel):
    refreshToken: str


class PushRegisterRequest(BaseModel):
    deviceId: UUID
    apnsToken: str
    pushEnvironment: str
    bundleId: str


class PushWatchRequest(BaseModel):
    """Ask the relay to watch a gateway session for run completion (#38).

    The watermark is positional (assistant reply after the transcript's
    last user message), so no timestamp crosses the phone/host clock
    boundary — the app just names the session it detached from.
    """
    sessionId: str = Field(min_length=1, max_length=256)


class PushWatchCancelRequest(BaseModel):
    sessionId: str = Field(min_length=1, max_length=256)


class DeviceAppStateRequest(BaseModel):
    state: str = Field(pattern="^(foreground|background)$")


class AttachmentPayload(BaseModel):
    type: str = Field(min_length=1, max_length=16)    # "image" or "file"
    filename: str = Field(min_length=1, max_length=256)
    mimeType: str = Field(min_length=1, max_length=128)
    data: str = Field(min_length=1, max_length=7_000_000)  # base64-encoded
    thumbnailData: str | None = Field(default=None, max_length=250_000)


class MessageCreateRequest(BaseModel):
    conversationId: UUID | None = None
    text: str = Field(default="")
    clientMessageId: UUID | None = None
    attachments: list[AttachmentPayload] | None = Field(default=None, max_length=4)

    @model_validator(mode="after")
    def _require_text_or_attachments(self) -> "MessageCreateRequest":
        has_text = bool(self.text and self.text.strip())
        has_attachments = bool(self.attachments)
        if not has_text and not has_attachments:
            raise ValueError("Either text or attachments must be provided.")
        return self


class InboxActionRequest(BaseModel):
    actionId: str


class SensorLocationRequest(BaseModel):
    latitude: float
    longitude: float
    altitude: float | None = None
    accuracy: float | None = None
    address: str | None = None
    recordedAt: str  # ISO8601


class SensorHealthSample(BaseModel):
    metric: str = Field(min_length=1, max_length=64)
    value: float
    unit: str = Field(min_length=1, max_length=32)
    startAt: str  # ISO8601
    endAt: str | None = None


class SensorHealthRequest(BaseModel):
    samples: list[SensorHealthSample] = Field(min_length=1, max_length=100)


class VoiceTurnCreateRequest(BaseModel):
    clientTurnId: UUID | None = None
    role: str = Field(min_length=1, max_length=32)
    source: str = Field(default="realtime", min_length=1, max_length=32)
    text: str = Field(min_length=1)


class InternalInboxCreateRequest(BaseModel):
    userId: UUID | None = None
    deviceId: UUID | None = None
    kind: str
    title: str
    body: str
    priority: str = "normal"
    payload: dict[str, str] | None = None
    expiresAt: datetime | None = None
