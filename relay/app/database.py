from __future__ import annotations

from contextlib import contextmanager
from typing import Iterator

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker


class Base(DeclarativeBase):
    pass


class Database:
    def __init__(self, database_url: str) -> None:
        connect_args = {"check_same_thread": False} if database_url.startswith("sqlite") else {}
        self.engine = create_engine(database_url, future=True, connect_args=connect_args)
        self.session_factory = sessionmaker(
            bind=self.engine,
            autoflush=False,
            autocommit=False,
            expire_on_commit=False,
            class_=Session,
        )

    def create_all(self) -> None:
        from . import models  # noqa: F401

        Base.metadata.create_all(self.engine)
        self._run_migrations()

    def _run_migrations(self) -> None:
        inspector = inspect(self.engine)

        with self.engine.begin() as connection:
            device_columns = {column["name"] for column in inspector.get_columns("devices")}
            if "app_state" not in device_columns:
                connection.execute(text("ALTER TABLE devices ADD COLUMN app_state TEXT"))
            if "app_state_updated_at" not in device_columns:
                if str(self.engine.url).startswith("sqlite"):
                    connection.execute(text("ALTER TABLE devices ADD COLUMN app_state_updated_at DATETIME"))
                else:
                    connection.execute(text("ALTER TABLE devices ADD COLUMN app_state_updated_at TIMESTAMP WITH TIME ZONE"))

            auth_session_columns = {column["name"] for column in inspector.get_columns("auth_sessions")}
            if "previous_refresh_token_hash" not in auth_session_columns:
                connection.execute(text("ALTER TABLE auth_sessions ADD COLUMN previous_refresh_token_hash TEXT"))
            if "previous_refresh_valid_until" not in auth_session_columns:
                if str(self.engine.url).startswith("sqlite"):
                    connection.execute(text("ALTER TABLE auth_sessions ADD COLUMN previous_refresh_valid_until DATETIME"))
                else:
                    connection.execute(
                        text("ALTER TABLE auth_sessions ADD COLUMN previous_refresh_valid_until TIMESTAMP WITH TIME ZONE")
                    )

            host_columns = {column["name"] for column in inspector.get_columns("hermes_hosts")}
            if "hermes_model" not in host_columns:
                connection.execute(text("ALTER TABLE hermes_hosts ADD COLUMN hermes_model TEXT"))

            conversation_columns = {column["name"] for column in inspector.get_columns("conversations")}
            if "hermes_session_id" not in conversation_columns:
                connection.execute(text("ALTER TABLE conversations ADD COLUMN hermes_session_id TEXT"))

            message_columns = {column["name"] for column in inspector.get_columns("messages")}
            if "delivery_status" not in message_columns:
                connection.execute(text("ALTER TABLE messages ADD COLUMN delivery_status TEXT"))
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_messages_user_client_message_id "
                    "ON messages (user_id, client_message_id)"
                )
            )
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_voice_sessions_user_status "
                    "ON voice_sessions (user_id, status)"
                )
            )
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_voice_sessions_tool_token_hash "
                    "ON voice_sessions (relay_tool_token_hash)"
                )
            )
            job_columns = {column["name"] for column in inspector.get_columns("message_jobs")}
            if "usage_data" not in job_columns:
                connection.execute(text("ALTER TABLE message_jobs ADD COLUMN usage_data JSON"))
            if "diff_data" not in job_columns:
                connection.execute(text("ALTER TABLE message_jobs ADD COLUMN diff_data JSON"))

            if "source" not in message_columns:
                connection.execute(text("ALTER TABLE messages ADD COLUMN source TEXT"))

            if "attachments_data" not in message_columns:
                connection.execute(text("ALTER TABLE messages ADD COLUMN attachments_data JSON"))

            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_message_jobs_user_status_created "
                    "ON message_jobs (user_id, status, created_at)"
                )
            )
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_message_jobs_status_lease "
                    "ON message_jobs (status, lease_expires_at)"
                )
            )
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_messages_conversation_created "
                    "ON messages (conversation_id, created_at)"
                )
            )
            connection.execute(
                text(
                    "CREATE INDEX IF NOT EXISTS ix_conversations_user_archived "
                    "ON conversations (user_id, is_archived)"
                )
            )

            voice_turn_columns = {column["name"] for column in inspector.get_columns("voice_turns")}
            if "client_turn_id" not in voice_turn_columns:
                connection.execute(text("ALTER TABLE voice_turns ADD COLUMN client_turn_id TEXT"))
            connection.execute(
                text(
                    "CREATE UNIQUE INDEX IF NOT EXISTS ix_voice_turns_session_client_turn_id "
                    "ON voice_turns (voice_session_id, client_turn_id)"
                )
            )

    @contextmanager
    def session(self) -> Iterator[Session]:
        db = self.session_factory()
        try:
            yield db
        finally:
            db.close()
