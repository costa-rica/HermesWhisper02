from datetime import UTC, datetime, timedelta
from uuid import uuid4

from app.db import Database
from app.models import TurnState, VoiceMessage, VoiceSession, utc_now_iso


class VoiceStore:
    def __init__(self, db: Database) -> None:
        self.db = db

    async def get_or_create_session(
        self,
        owner_id: str,
        session_id: str | None = None,
        resume_window_seconds: int | None = None,
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
            if row and self._is_resume_allowed(str(row["last_seen"]), resume_window_seconds):
                await self.db.execute(
                    "UPDATE voice_sessions SET last_seen = ? WHERE id = ?",
                    (now, session_id),
                )
                return VoiceSession.model_validate(dict(row)), True

        new_session = VoiceSession(
            id=str(uuid4()),
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

    async def touch_session(self, session_id: str) -> None:
        await self.db.execute(
            "UPDATE voice_sessions SET last_seen = ? WHERE id = ?",
            (utc_now_iso(), session_id),
        )

    async def get_session_for_owner(self, owner_id: str, session_id: str) -> VoiceSession | None:
        row = await self.db.fetch_one(
            """
            SELECT id, owner_id, conversation_id, created_at, last_seen
            FROM voice_sessions
            WHERE id = ? AND owner_id = ?
            """,
            (session_id, owner_id),
        )
        if row is None:
            return None
        return VoiceSession.model_validate(dict(row))

    async def session_exists(self, session_id: str) -> bool:
        row = await self.db.fetch_one(
            "SELECT 1 FROM voice_sessions WHERE id = ?",
            (session_id,),
        )
        return row is not None

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

    async def list_recent_messages(self, session_id: str, limit: int) -> list[VoiceMessage]:
        rows = await self.db.fetch_all(
            """
            SELECT id, session_id, role, content, created_at
            FROM voice_messages
            WHERE session_id = ?
            ORDER BY created_at DESC, id DESC
            LIMIT ?
            """,
            (session_id, limit),
        )
        return [VoiceMessage.model_validate(dict(row)) for row in rows]

    async def start_turn(self, session_id: str, turn_id: str) -> TurnState:
        now = utc_now_iso()
        try:
            await self.db.execute(
                """
                INSERT INTO turn_state (turn_id, session_id, source, status, ts_started)
                VALUES (?, ?, ?, ?, ?)
                """,
                (turn_id, session_id, "answer", "started", now),
            )
        except Exception as exc:
            if "UNIQUE constraint failed" in str(exc):
                raise ValueError(f"turn_id already exists: {turn_id}") from exc
            raise
        return TurnState(
            turn_id=turn_id,
            session_id=session_id,
            source="answer",
            status="started",
            ts_started=now,
        )

    async def mark_first_audio(self, turn_id: str, source: str) -> None:
        now = utc_now_iso()
        await self.db.execute(
            """
            UPDATE turn_state
            SET source = ?, ts_first_audio = COALESCE(ts_first_audio, ?)
            WHERE turn_id = ? AND status = 'started'
            """,
            (source, now, turn_id),
        )

    async def complete_turn(self, turn_id: str) -> None:
        await self.db.execute(
            """
            UPDATE turn_state
            SET status = 'completed', ts_final = ?
            WHERE turn_id = ? AND status = 'started'
            """,
            (utc_now_iso(), turn_id),
        )

    async def cancel_turn(self, turn_id: str) -> None:
        now = utc_now_iso()
        await self.db.execute(
            """
            UPDATE turn_state
            SET status = 'canceled', ts_final = ?, ts_canceled = ?
            WHERE turn_id = ? AND status = 'started'
            """,
            (now, now, turn_id),
        )

    async def fail_turn(self, turn_id: str) -> None:
        await self.db.execute(
            """
            UPDATE turn_state
            SET status = 'failed', ts_final = ?
            WHERE turn_id = ? AND status = 'started'
            """,
            (utc_now_iso(), turn_id),
        )

    async def get_turn(self, turn_id: str) -> TurnState | None:
        row = await self.db.fetch_one(
            """
            SELECT turn_id, session_id, source, status, ts_started, ts_first_audio, ts_final,
                   ts_canceled
            FROM turn_state
            WHERE turn_id = ?
            """,
            (turn_id,),
        )
        if row is None:
            return None
        return TurnState.model_validate(dict(row))

    async def append_completed_exchange(
        self,
        session_id: str,
        turn_id: str,
        user_text: str,
        assistant_text: str,
    ) -> None:
        turn = await self.get_turn(turn_id)
        if turn is None or turn.status != "completed":
            return
        await self.append_message(session_id, "user", user_text)
        await self.append_message(session_id, "assistant", assistant_text)

    @staticmethod
    def _is_resume_allowed(last_seen: str, resume_window_seconds: int | None) -> bool:
        if resume_window_seconds is None:
            return True
        try:
            parsed = datetime.fromisoformat(last_seen.replace("Z", "+00:00"))
        except ValueError:
            return False
        return datetime.now(UTC) - parsed <= timedelta(seconds=resume_window_seconds)
