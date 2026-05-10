from app.config import Settings
from app.services.stt import create_stt_service
from app.services.tts import create_tts_service


def test_openai_factories_use_pinned_pipecat_classes(tmp_path) -> None:
    settings = Settings(
        NAME_APP="hermes-whisper-02-api-test",
        RUN_ENVIRONMENT="development",
        JWT_SECRET="test-secret-with-at-least-32-bytes",
        DB_PATH=tmp_path / "test.sqlite",
        STT_PROVIDER="openai",
        TTS_PROVIDER="openai",
        OPENAI_API_KEY="test-key",
    )

    stt = create_stt_service(settings)
    tts = create_tts_service(settings)

    assert type(stt).__name__ == "OpenAIRealtimeSTTService"
    assert type(tts).__name__ == "OpenAITTSService"
