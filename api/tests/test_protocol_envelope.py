from uuid import uuid4

from fastapi.testclient import TestClient

from app.config import get_settings
from app.db import Database
from app.main import create_app
from app.models import utc_now_iso
from app.services.passwords import hash_password
from app.services.tokens import issue_token


def test_voice_ws_session_and_audio_echo(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DB_PATH", str(tmp_path / "test.sqlite"))
    monkeypatch.setenv("NAME_APP", "hermes-whisper-02-api-test")
    monkeypatch.setenv("RUN_ENVIRONMENT", "development")
    monkeypatch.setenv("JWT_SECRET", "test-secret-with-at-least-32-bytes")
    get_settings.cache_clear()
    user_id = _seed_user_sync("nrodrig1@gmail.com", "password")
    token = issue_token(
        user_id,
        "nrodrig1@gmail.com",
        get_settings().JWT_SECRET.get_secret_value(),
        60,
    )

    with (
        TestClient(create_app()) as client,
        client.websocket_connect(
            "/ws/voice",
            headers={"Authorization": f"Bearer {token}"},
        ) as websocket,
    ):
        websocket.send_json(
            {
                "type": "client_hello",
                "protocol_version": 1,
                "downlink_format": "pcm16",
                "sample_rate": 16_000,
                "ptt_mode": False,
            }
        )
        started = websocket.receive_json()
        websocket.send_bytes(b"\x00\x00" * 16_000)
        transcript = websocket.receive_json()
        prelude = websocket.receive_json()
        audio = websocket.receive_bytes()
        turn_end = websocket.receive_json()

    assert started["type"] == "session_started"
    assert started["resumed"] is False
    assert transcript["type"] == "transcript"
    assert prelude["type"] == "audio_chunk"
    assert prelude["bytes"] == len(audio)
    assert turn_end["type"] == "turn_end"


def test_voice_ws_rejects_unauthorized(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DB_PATH", str(tmp_path / "test.sqlite"))
    monkeypatch.setenv("NAME_APP", "hermes-whisper-02-api-test")
    monkeypatch.setenv("RUN_ENVIRONMENT", "development")
    monkeypatch.setenv("JWT_SECRET", "test-secret-with-at-least-32-bytes")
    get_settings.cache_clear()

    with TestClient(create_app()) as client, client.websocket_connect("/ws/voice") as websocket:
        error = websocket.receive_json()

    assert error["error"]["code"] == "AUTH_FAILED"


def _seed_user_sync(email: str, password: str) -> str:
    import asyncio

    async def seed() -> str:
        db = Database(get_settings().DB_PATH)
        await db.bootstrap()
        user_id = str(uuid4())
        await db.execute(
            """
            INSERT INTO users (id, email, password_hash, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (user_id, email, hash_password(password), utc_now_iso()),
        )
        return user_id

    return asyncio.run(seed())
