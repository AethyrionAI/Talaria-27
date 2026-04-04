from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import AsyncIterator, Protocol

from .hermes_runner import HermesCLIExecutor, HermesConversationMessage


@dataclass(frozen=True)
class RuntimeConversationMessage:
    role: str
    text: str


@dataclass(frozen=True)
class RuntimeTurnResult:
    text: str
    session_id: str | None = None
    usage: dict | None = None


class HostRuntimeAdapter(Protocol):
    def send_text_message(
        self,
        *,
        latest_user_message: str,
        history: list[RuntimeConversationMessage],
        session_id: str | None = None,
    ) -> RuntimeTurnResult: ...

    def delegate_talk_turn(
        self,
        *,
        prompt: str,
        session_id: str | None = None,
    ) -> RuntimeTurnResult: ...


class HermesRuntimeAdapter:
    """CLI subprocess adapter (original implementation)."""

    def __init__(self, executor: HermesCLIExecutor) -> None:
        self.executor = executor

    def send_text_message(
        self,
        *,
        latest_user_message: str,
        history: list[RuntimeConversationMessage],
        session_id: str | None = None,
    ) -> RuntimeTurnResult:
        result = self.executor.send_message(
            latest_user_message=latest_user_message,
            history=[
                HermesConversationMessage(role=message.role, text=message.text)
                for message in history
            ],
            session_id=session_id,
        )
        return RuntimeTurnResult(text=result.text, session_id=result.session_id)

    def delegate_talk_turn(
        self,
        *,
        prompt: str,
        session_id: str | None = None,
    ) -> RuntimeTurnResult:
        result = self.executor.send_message(
            latest_user_message=prompt,
            history=[],
            session_id=session_id,
        )
        return RuntimeTurnResult(text=result.text, session_id=result.session_id)


class HermesAPIRuntimeAdapter:
    """HTTP API adapter — talks to the Hermes API server with streaming support."""

    def __init__(self, executor) -> None:  # HermesAPIExecutor
        self.executor = executor
        self.supports_streaming = True

    def send_text_message(
        self,
        *,
        latest_user_message: str,
        history: list[RuntimeConversationMessage],
        session_id: str | None = None,
    ) -> RuntimeTurnResult:
        """Synchronous non-streaming send (used by talk delegation and fallback)."""
        result = asyncio.run(
            self.executor.send_message(
                latest_user_message=latest_user_message,
                history=[
                    HermesConversationMessage(role=message.role, text=message.text)
                    for message in history
                ],
                session_id=session_id,
            )
        )
        return RuntimeTurnResult(
            text=result.text,
            session_id=result.session_id,
            usage=result.usage,
        )

    async def send_text_message_streaming(
        self,
        *,
        latest_user_message: str,
        history: list[RuntimeConversationMessage],
        session_id: str | None = None,
        attachments: list[dict] | None = None,
    ) -> AsyncIterator:
        """Async streaming send — yields StreamEvent objects."""
        async for event in self.executor.stream_message(
            latest_user_message=latest_user_message,
            history=[
                HermesConversationMessage(role=message.role, text=message.text)
                for message in history
            ],
            session_id=session_id,
            attachments=attachments,
        ):
            yield event

    def delegate_talk_turn(
        self,
        *,
        prompt: str,
        session_id: str | None = None,
    ) -> RuntimeTurnResult:
        result = asyncio.run(
            self.executor.send_message(
                latest_user_message=prompt,
                history=[],
                session_id=session_id,
            )
        )
        return RuntimeTurnResult(
            text=result.text,
            session_id=result.session_id,
            usage=result.usage,
        )
