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
        _send_test_turn_audio(websocket)
        progress_frames, transcript = _receive_until_type(websocket, "transcript")
        ack_state = websocket.receive_json()
        prelude = websocket.receive_json()
        audio = websocket.receive_bytes()
        answer_state = websocket.receive_json()
        answer_prelude = websocket.receive_json()
        answer_audio = websocket.receive_bytes()
        turn_end = websocket.receive_json()
        idle_state = websocket.receive_json()

    assert started["type"] == "session_started"
    assert started["resumed"] is False
    assert [frame["kind"] for frame in progress_frames] == [
        "sent_to_hermes",
        "response_started",
        "tool_call",
        "tool_result",
        "finished",
    ]
    assert transcript["type"] == "transcript"
    assert ack_state == {"type": "assistant_state", "state": "ack"}
    assert prelude["type"] == "audio_chunk"
    assert prelude["source"] == "ack"
    assert prelude["bytes"] == len(audio)
    assert answer_state == {"type": "assistant_state", "state": "answer"}
    assert answer_prelude["type"] == "audio_chunk"
    assert answer_prelude["source"] == "answer"
    assert answer_prelude["bytes"] == len(answer_audio)
    assert turn_end["type"] == "turn_end"
    assert idle_state == {"type": "assistant_state", "state": "idle"}


def test_voice_ws_rejects_unauthorized(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DB_PATH", str(tmp_path / "test.sqlite"))
    monkeypatch.setenv("NAME_APP", "hermes-whisper-02-api-test")
    monkeypatch.setenv("RUN_ENVIRONMENT", "development")
    monkeypatch.setenv("JWT_SECRET", "test-secret-with-at-least-32-bytes")
    get_settings.cache_clear()

    with TestClient(create_app()) as client, client.websocket_connect("/ws/voice") as websocket:
        error = websocket.receive_json()

    assert error["error"]["code"] == "AUTH_FAILED"


def test_voice_ws_ping_is_control_only(tmp_path, monkeypatch) -> None:
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
        websocket.receive_json()
        websocket.send_json({"type": "ping", "ts": 12.5})
        pong = websocket.receive_json()
        _send_test_turn_audio(websocket)
        _, transcript = _receive_until_type(websocket, "transcript")

    assert pong == {"type": "pong", "ts": 12.5}
    assert transcript["type"] == "transcript"


def test_voice_ws_resumes_same_owner_session(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DB_PATH", str(tmp_path / "test.sqlite"))
    monkeypatch.setenv("NAME_APP", "hermes-whisper-02-api-test")
    monkeypatch.setenv("RUN_ENVIRONMENT", "development")
    monkeypatch.setenv("JWT_SECRET", "test-secret-with-at-least-32-bytes")
    monkeypatch.setenv("SESSION_RESUME_WINDOW_SEC", "300")
    get_settings.cache_clear()
    user_id = _seed_user_sync("nrodrig1@gmail.com", "password")
    token = issue_token(
        user_id,
        "nrodrig1@gmail.com",
        get_settings().JWT_SECRET.get_secret_value(),
        60,
    )

    with TestClient(create_app()) as client:
        with client.websocket_connect(
            "/ws/voice",
            headers={"Authorization": f"Bearer {token}"},
        ) as websocket:
            websocket.send_json(_client_hello())
            first_started = websocket.receive_json()

        with client.websocket_connect(
            "/ws/voice",
            headers={"Authorization": f"Bearer {token}"},
        ) as websocket:
            websocket.send_json(_client_hello(session_id=first_started["session_id"]))
            second_started = websocket.receive_json()

    assert first_started["type"] == "session_started"
    assert first_started["resumed"] is False
    assert second_started["type"] == "session_started"
    assert second_started["session_id"] == first_started["session_id"]
    assert second_started["resumed"] is True


def test_voice_ws_rejects_foreign_owner_resume_with_fresh_session(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("DB_PATH", str(tmp_path / "test.sqlite"))
    monkeypatch.setenv("NAME_APP", "hermes-whisper-02-api-test")
    monkeypatch.setenv("RUN_ENVIRONMENT", "development")
    monkeypatch.setenv("JWT_SECRET", "test-secret-with-at-least-32-bytes")
    monkeypatch.setenv("SESSION_RESUME_WINDOW_SEC", "300")
    get_settings.cache_clear()
    first_user_id = _seed_user_sync("nrodrig1@gmail.com", "password")
    second_user_id = _seed_user_sync("other@example.com", "password")
    first_token = issue_token(
        first_user_id,
        "nrodrig1@gmail.com",
        get_settings().JWT_SECRET.get_secret_value(),
        60,
    )
    second_token = issue_token(
        second_user_id,
        "other@example.com",
        get_settings().JWT_SECRET.get_secret_value(),
        60,
    )

    with TestClient(create_app()) as client:
        with client.websocket_connect(
            "/ws/voice",
            headers={"Authorization": f"Bearer {first_token}"},
        ) as websocket:
            websocket.send_json(_client_hello())
            first_started = websocket.receive_json()

        with client.websocket_connect(
            "/ws/voice",
            headers={"Authorization": f"Bearer {second_token}"},
        ) as websocket:
            websocket.send_json(_client_hello(session_id=first_started["session_id"]))
            second_started = websocket.receive_json()

    assert second_started["type"] == "session_started"
    assert second_started["session_id"] != first_started["session_id"]
    assert second_started["resumed"] is False


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
