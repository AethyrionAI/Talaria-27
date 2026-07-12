from __future__ import annotations

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

from .scheduler import MIN_INTERVAL_MINUTES, resolve_timezone


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


_TIME_OF_DAY_PATTERN = r"^([01]\d|2[0-3]):[0-5]\d$"


def _validate_recurrence_fields(
    *,
    kind: str,
    runAt: datetime | None,
    intervalMinutes: int | None,
    timeOfDay: str | None,
    weekday: int | None,
    tz: str | None,
) -> None:
    """Per-kind field consistency for the schedule recurrence grammar (#98).

    Each kind requires exactly its own fields; anything cross-kind is
    rejected so the stored row (and the future management UI's contract)
    is unambiguous. The hourly floor on intervalMinutes and the weekday /
    HH:MM ranges are enforced by the Field constraints.
    """
    if kind == "once":
        if runAt is None:
            raise ValueError("kind 'once' requires runAt.")
        if intervalMinutes is not None or timeOfDay is not None or weekday is not None or tz is not None:
            raise ValueError("kind 'once' accepts only runAt.")
    elif kind == "interval":
        if intervalMinutes is None:
            raise ValueError("kind 'interval' requires intervalMinutes.")
        if runAt is not None or timeOfDay is not None or weekday is not None or tz is not None:
            raise ValueError("kind 'interval' accepts only intervalMinutes.")
    elif kind == "daily":
        if timeOfDay is None:
            raise ValueError("kind 'daily' requires timeOfDay.")
        if runAt is not None or intervalMinutes is not None or weekday is not None:
            raise ValueError("kind 'daily' accepts only timeOfDay and timezone.")
    elif kind == "weekly":
        if timeOfDay is None or weekday is None:
            raise ValueError("kind 'weekly' requires timeOfDay and weekday.")
        if runAt is not None or intervalMinutes is not None:
            raise ValueError("kind 'weekly' accepts only timeOfDay, weekday, and timezone.")
    if tz is not None:
        resolve_timezone(tz)  # raises ValueError on unknown IANA names


class ScheduleCreateRequest(BaseModel):
    """Create a scheduled run (#98). Recurrence grammar:

    once     → runAt (ISO datetime; must be in the future)
    interval → intervalMinutes (≥ 60 — the hourly floor)
    daily    → timeOfDay "HH:MM" [+ timezone, IANA, default UTC]
    weekly   → timeOfDay + weekday (0=Monday … 6=Sunday) [+ timezone]
    """

    prompt: str = Field(min_length=1, max_length=8000)
    kind: Literal["once", "interval", "daily", "weekly"]
    runAt: datetime | None = None
    intervalMinutes: int | None = Field(default=None, ge=MIN_INTERVAL_MINUTES, le=527_040)
    timeOfDay: str | None = Field(default=None, pattern=_TIME_OF_DAY_PATTERN)
    weekday: int | None = Field(default=None, ge=0, le=6)
    timezone: str | None = Field(default=None, min_length=1, max_length=64)
    sessionStrategy: Literal["fresh"] = "fresh"

    @model_validator(mode="after")
    def _validate_recurrence(self) -> "ScheduleCreateRequest":
        if not self.prompt.strip():
            raise ValueError("prompt must not be blank.")
        _validate_recurrence_fields(
            kind=self.kind,
            runAt=self.runAt,
            intervalMinutes=self.intervalMinutes,
            timeOfDay=self.timeOfDay,
            weekday=self.weekday,
            tz=self.timezone,
        )
        return self


class ScheduleUpdateRequest(BaseModel):
    """Partial update. Changing the recurrence requires sending `kind`
    together with its full field set (same shape as create); prompt and
    sessionStrategy may change independently. Enabled state is managed via
    the pause/resume endpoints, not here."""

    prompt: str | None = Field(default=None, min_length=1, max_length=8000)
    kind: Literal["once", "interval", "daily", "weekly"] | None = None
    runAt: datetime | None = None
    intervalMinutes: int | None = Field(default=None, ge=MIN_INTERVAL_MINUTES, le=527_040)
    timeOfDay: str | None = Field(default=None, pattern=_TIME_OF_DAY_PATTERN)
    weekday: int | None = Field(default=None, ge=0, le=6)
    timezone: str | None = Field(default=None, min_length=1, max_length=64)
    sessionStrategy: Literal["fresh"] | None = None

    @model_validator(mode="after")
    def _validate_recurrence(self) -> "ScheduleUpdateRequest":
        if self.prompt is not None and not self.prompt.strip():
            raise ValueError("prompt must not be blank.")
        recurrence_fields_present = any(
            value is not None
            for value in (self.runAt, self.intervalMinutes, self.timeOfDay, self.weekday, self.timezone)
        )
        if self.kind is None:
            if recurrence_fields_present:
                raise ValueError("recurrence changes require 'kind' with its full field set.")
            return self
        _validate_recurrence_fields(
            kind=self.kind,
            runAt=self.runAt,
            intervalMinutes=self.intervalMinutes,
            timeOfDay=self.timeOfDay,
            weekday=self.weekday,
            tz=self.timezone,
        )
        return self


class InternalInboxCreateRequest(BaseModel):
    userId: UUID | None = None
    deviceId: UUID | None = None
    kind: str
    title: str
    body: str
    priority: str = "normal"
    payload: dict[str, str] | None = None
    expiresAt: datetime | None = None
