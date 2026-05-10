from pipecat.services.openai.tts import OpenAITTSService

from app.config import Settings
from app.errors import APIError


def create_tts_service(settings: Settings):
    if settings.TTS_PROVIDER == "mock":
        from app.pipecat_processors.mocks import MockTTS

        return MockTTS()

    if settings.TTS_PROVIDER == "openai":
        if settings.OPENAI_API_KEY is None:
            raise APIError(
                code="SERVICE_UNAVAILABLE", message="OPENAI_API_KEY is required", status=503
            )
        return OpenAITTSService(
            api_key=settings.OPENAI_API_KEY.get_secret_value(),
            settings=OpenAITTSService.Settings(
                voice=settings.TTS_VOICE,
                model=settings.TTS_MODEL,
            ),
            sample_rate=24_000,
        )

    raise APIError(code="VALIDATION_ERROR", message="Unsupported TTS provider", status=400)
