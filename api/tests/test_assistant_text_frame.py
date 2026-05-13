import asyncio
from uuid import uuid4

from fastapi.testclient import TestClient

from app.config import get_settings
from app.db import Database
from app.main import create_app
from app.models import utc_now_iso
from app.services.passwords import hash_password
from app.services.tokens import issue_token


def test_completed_turn_emits_assistant_text_frame(tmp_path, monkeypatch) -> None:
    token = _configure_and_seed_user(tmp_path, monkeypatch)

    with (
        TestClient(create_app()) as client,
        client.websocket_connect(
            "/ws/voice",
            headers={"Authorization": f"Bearer {token}"},
        ) as websocket,
    ):
        websocket.send_json(_client_hello())
        websocket.receive_json()
        _send_test_turn_audio(websocket)
        _, transcript = _receive_until_type(websocket, "transcript")
        assistant_text = websocket.receive_json()

    assert transcript["type"] == "transcript"
    assert assistant_text["type"] == "assistant_text"
    assert assistant_text["turn_id"] == transcript["turn_id"]
    assert assistant_text["final"] is True
    assert assistant_text["text"]
    assert isinstance(assistant_text["ts"], int | float)


def test_canceled_turn_does_not_emit_or_persist_assistant_text(tmp_path, monkeypatch) -> None:
    token = _configure_and_seed_user(tmp_path, monkeypatch)
    canceled_turn_id = "turn-canceled-before-audio"

    with (
        TestClient(create_app()) as client,
        client.websocket_connect(
            "/ws/voice",
            headers={"Authorization": f"Bearer {token}"},
        ) as websocket,
    ):
        websocket.send_json(_client_hello())
        started = websocket.receive_json()
        websocket.send_json({"type": "cancel_turn", "turn_id": canceled_turn_id})
        turn_end = websocket.receive_json()

    assert turn_end == {
        "type": "turn_end",
        "turn_id": canceled_turn_id,
        "canceled": True,
    }
    assert _message_count(started["session_id"]) == 0


def _configure_and_seed_user(tmp_path, monkeypatch) -> str:
    monkeypatch.setenv("DB_PATH", str(tmp_path / "test.sqlite"))
    monkeypatch.setenv("NAME_APP", "hermes-whisper-02-api-test")
    monkeypatch.setenv("RUN_ENVIRONMENT", "development")
    monkeypatch.setenv("JWT_SECRET", "test-secret-with-at-least-32-bytes")
    get_settings.cache_clear()
    user_id = _seed_user_sync("nrodrig1@gmail.com", "password")
    return issue_token(
        user_id,
        "nrodrig1@gmail.com",
        get_settings().JWT_SECRET.get_secret_value(),
        60,
    )


def _client_hello() -> dict:
    return {
        "type": "client_hello",
        "protocol_version": 1,
        "downlink_format": "pcm16",
        "sample_rate": 16_000,
        "ptt_mode": False,
    }


def _send_test_turn_audio(websocket) -> None:
    speech_chunk = (3000).to_bytes(2, byteorder="little", signed=True) * 320
    silence_chunk = b"\x00\x00" * 320
    for _ in range(40):
        websocket.send_bytes(speech_chunk)
    for _ in range(60):
        websocket.send_bytes(silence_chunk)


def _receive_until_type(websocket, frame_type: str):
    skipped = []
    while True:
        frame = websocket.receive_json()
        if frame["type"] == frame_type:
            return skipped, frame
        skipped.append(frame)


def _seed_user_sync(email: str, password: str) -> str:
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


def _message_count(session_id: str) -> int:
    async def count() -> int:
        row = await Database(get_settings().DB_PATH).fetch_one(
            "SELECT COUNT(*) AS count FROM voice_messages WHERE session_id = ?",
            (session_id,),
        )
        return int(row["count"])

    return asyncio.run(count())
