from uuid import uuid4

from app.db import Database
from app.models import VoiceMessage, VoiceSession, utc_now_iso


class VoiceStore:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def get_or_create_session(
        self,
        owner_id: str,
        session_id: str | None = None,
    ) -> tuple[VoiceSession, bool]:
        now = utc_now_iso()
        if session_id:
            row = await self.db.fetch_one(
                """
                SELECT id, owner_id, conversation_id, created_at, last_seen
                FROM voice_sessions
                WHERE id = ? AND owner_id = ?
                """,
                (session_id, owner_id),
            )
            if row:
                await self.db.execute(
                    "UPDATE voice_sessions SET last_seen = ? WHERE id = ?",
                    (now, session_id),
                )
                return VoiceSession.model_validate(dict(row)), True

        new_session = VoiceSession(
            id=session_id or str(uuid4()),
            owner_id=owner_id,
            conversation_id=str(uuid4()),
            created_at=now,
            last_seen=now,
        )
        await self.db.execute(
            """
            INSERT INTO voice_sessions (id, owner_id, conversation_id, created_at, last_seen)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                new_session.id,
                new_session.owner_id,
                new_session.conversation_id,
                new_session.created_at,
                new_session.last_seen,
            ),
        )
        return new_session, False

    async def append_message(self, session_id: str, role: str, content: str) -> VoiceMessage:
        message = VoiceMessage(
            id=str(uuid4()),
            session_id=session_id,
            role=role,  # type: ignore[arg-type]
            content=content,
            created_at=utc_now_iso(),
        )
        await self.db.execute(
            """
            INSERT INTO voice_messages (id, session_id, role, content, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                message.id,
                message.session_id,
                message.role,
                message.content,
                message.created_at,
            ),
        )
        return message

    async def list_messages(self, session_id: str) -> list[VoiceMessage]:
        rows = await self.db.fetch_all(
            """
            SELECT id, session_id, role, content, created_at
            FROM voice_messages
            WHERE session_id = ?
            ORDER BY created_at ASC, id ASC
            """,
            (session_id,),
        )
        return [VoiceMessage.model_validate(dict(row)) for row in rows]
