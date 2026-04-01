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

    @contextmanager
    def session(self) -> Iterator[Session]:
        db = self.session_factory()
        try:
            yield db
        finally:
            db.close()
