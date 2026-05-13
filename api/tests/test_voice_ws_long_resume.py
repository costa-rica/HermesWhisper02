import asyncio
from uuid import uuid4

from fastapi.testclient import TestClient

import app.routes.voice_ws as voice_ws_module
from app.config import get_settings
from app.db import Database
from app.main import create_app
from app.models import utc_now_iso
from app.services.passwords import hash_password
from app.services.tokens import issue_token
from app.services.voice_store import VoiceStore


def test_voice_ws_cold_resume_reuses_original_conversation_id(tmp_path, monkeypatch) -> None:
    token = _configure_and_seed_user(tmp_path, monkeypatch)
    session = _create_expired_session("user-1")

    with (
        TestClient(create_app()) as client,
        client.websocket_connect(
            "/ws/voice",
            headers={"Authorization": f"Bearer {token}"},
        ) as websocket,
    ):
        websocket.send_json(_client_hello(session_id=session.id))
        started = websocket.receive_json()

    assert started["type"] == "session_started"
    assert started["session_id"] == session.id
    assert started["conversation_id"] == session.conversation_id
    assert started["resumed"] is True
    assert started["created"] is False


def test_voice_ws_long_resume_seeds_prior_context(tmp_path, monkeypatch) -> None:
    token = _configure_and_seed_user(tmp_path, monkeypatch)
    session = _create_expired_session("user-1")
    _append_completed_exchange(session.id, "turn-1", "hello", "answer")
    captured = {}
    original_build_pipeline = voice_ws_module.build_pipeline

    def capture_build_pipeline(conversation_id, context_messages, *args, **kwargs):
        captured["conversation_id"] = conversation_id
        captured["context"] = context_messages
        return original_build_pipeline(conversation_id, context_messages, *args, **kwargs)

    monkeypatch.setattr(voice_ws_module, "build_pipeline", capture_build_pipeline)

    with (
        TestClient(create_app()) as client,
        client.websocket_connect(
            "/ws/voice",
            headers={"Authorization": f"Bearer {token}"},
        ) as websocket,
    ):
        websocket.send_json(_client_hello(session_id=session.id))
        started = websocket.receive_json()

    assert started["resumed"] is True
    assert captured["conversation_id"] == session.conversation_id
    assert [(message.role, message.content) for message in captured["context"]] == [
        ("user", "hello"),
        ("assistant", "answer"),
    ]


def test_voice_ws_long_resume_rejects_foreign_owner(tmp_path, monkeypatch) -> None:
    first_token = _configure_and_seed_user(tmp_path, monkeypatch)
    session = _create_expired_session("user-1")
    second_user_id = _seed_user_sync("other@example.com", "password")
    second_token = issue_token(
        second_user_id,
        "other@example.com",
        get_settings().JWT_SECRET.get_secret_value(),
        60,
    )
    assert first_token

    with (
        TestClient(create_app()) as client,
        client.websocket_connect(
            "/ws/voice",
            headers={"Authorization": f"Bearer {second_token}"},
        ) as websocket,
    ):
        websocket.send_json(_client_hello(session_id=session.id))
        error = websocket.receive_json()

    assert error["error"]["code"] == "FORBIDDEN"
    assert error["error"]["status"] == 403


def test_voice_ws_missing_resume_session_falls_back_to_new_session(tmp_path, monkeypatch) -> None:
    token = _configure_and_seed_user(tmp_path, monkeypatch)

    with (
        TestClient(create_app()) as client,
        client.websocket_connect(
            "/ws/voice",
            headers={"Authorization": f"Bearer {token}"},
        ) as websocket,
    ):
        websocket.send_json(_client_hello(session_id="missing-session"))
        started = websocket.receive_json()

    assert started["type"] == "session_started"
    assert started["session_id"] != "missing-session"
    assert started["resumed"] is False
    assert started["created"] is True


def _configure_and_seed_user(tmp_path, monkeypatch) -> str:
    monkeypatch.setenv("DB_PATH", str(tmp_path / "test.sqlite"))
    monkeypatch.setenv("NAME_APP", "hermes-whisper-02-api-test")
    monkeypatch.setenv("RUN_ENVIRONMENT", "development")
    monkeypatch.setenv("JWT_SECRET", "test-secret-with-at-least-32-bytes")
    monkeypatch.setenv("SESSION_RESUME_WINDOW_SEC", "300")
    monkeypatch.setenv("LONG_RESUME_MAX_MESSAGES", "50")
    get_settings.cache_clear()
    user_id = _seed_user_sync("nrodrig1@gmail.com", "password", user_id="user-1")
    return issue_token(
        user_id,
        "nrodrig1@gmail.com",
        get_settings().JWT_SECRET.get_secret_value(),
        60,
    )


def _client_hello(session_id: str | None = None) -> dict:
    frame = {
        "type": "client_hello",
        "protocol_version": 1,
        "downlink_format": "pcm16",
        "sample_rate": 16_000,
        "ptt_mode": False,
    }
    if session_id is not None:
        frame["session_id"] = session_id
    return frame


def _seed_user_sync(email: str, password: str, user_id: str | None = None) -> str:
    async def seed() -> str:
        db = Database(get_settings().DB_PATH)
        await db.bootstrap()
        seeded_user_id = user_id or str(uuid4())
        await db.execute(
            """
            INSERT INTO users (id, email, password_hash, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (seeded_user_id, email, hash_password(password), utc_now_iso()),
        )
        return seeded_user_id

    return asyncio.run(seed())


def _create_expired_session(owner_id: str):
    async def create():
        store = VoiceStore(Database(get_settings().DB_PATH))
        session, _ = await store.get_or_create_session(owner_id)
        await store.db.execute(
            "UPDATE voice_sessions SET last_seen = ? WHERE id = ?",
            ("2000-01-01T00:00:00Z", session.id),
        )
        return session

    return asyncio.run(create())


def _append_completed_exchange(
    session_id: str,
    turn_id: str,
    user_text: str,
    assistant_text: str,
) -> None:
    async def append() -> None:
        store = VoiceStore(Database(get_settings().DB_PATH))
        await store.start_turn(session_id, turn_id)
        await store.complete_turn(turn_id)
        await store.append_completed_exchange(session_id, turn_id, user_text, assistant_text)

    asyncio.run(append())
