import asyncio
from uuid import uuid4

from fastapi.testclient import TestClient

from app.config import get_settings
from app.db import Database
from app.main import create_app
from app.models import utc_now_iso
from app.routes.voice_ws import AudioTurnSegmenter, _runtime_config_from_hello
from app.services.passwords import hash_password
from app.services.pipeline import build_pipeline
from app.services.session_runtime_config import SessionRuntimeConfig
from app.services.tokens import issue_token


def test_client_hello_audio_params_apply_to_first_turn() -> None:
    hello = _client_hello()
    hello["audio_params"] = {
        "min_turn_seconds": 0.1,
        "end_silence_seconds": 0.2,
        "max_turn_seconds": 1.0,
    }
    config = _runtime_config_from_hello(hello)
    segmenter = AudioTurnSegmenter(config)
    speech_chunk = (3000).to_bytes(2, byteorder="little", signed=True) * 320
    silence_chunk = b"\x00\x00" * 320

    for _ in range(5):
        assert segmenter.add(speech_chunk) is None

    segment = None
    for _ in range(11):
        segment = segmenter.add(silence_chunk)
        if segment is not None:
            break

    assert segment is not None


async def test_deterministic_mode_still_routes_substantive_text_to_hermes() -> None:
    config = SessionRuntimeConfig(intermediary_mode="deterministic")
    pipeline = build_pipeline(runtime_config=config)

    turn = await pipeline.process_text("please summarize the deployment plan")

    assert turn.answer_text
    assert pipeline.front_llm.intermediary_mode == "deterministic"
    assert pipeline.front_llm.hermes_calls == 1


def test_set_intermediary_mode_frame_acknowledges_value(tmp_path, monkeypatch) -> None:
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
        websocket.send_json({"type": "set_intermediary_mode", "mode": "deterministic"})
        applied = websocket.receive_json()

    assert applied == {
        "type": "runtime_config_applied",
        "fields": ["intermediary_mode"],
        "values": {"intermediary_mode": "deterministic"},
    }


def test_set_audio_params_frame_clamps_ack_values(tmp_path, monkeypatch) -> None:
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
        websocket.send_json(
            {
                "type": "set_audio_params",
                "speech_rms_threshold": -1,
                "end_silence_seconds": 99,
            }
        )
        applied = websocket.receive_json()

    assert applied == {
        "type": "runtime_config_applied",
        "fields": ["speech_rms_threshold", "end_silence_seconds"],
        "values": {
            "speech_rms_threshold": 0.0001,
            "end_silence_seconds": 5.0,
        },
    }


def _client_hello() -> dict:
    return {
        "type": "client_hello",
        "protocol_version": 1,
        "downlink_format": "pcm16",
        "sample_rate": 16_000,
        "ptt_mode": False,
    }


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
