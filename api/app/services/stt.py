from pipecat.services.openai.stt import OpenAIRealtimeSTTService, OpenAISTTService

from app.config import Settings
from app.errors import APIError


def create_stt_service(settings: Settings):
    if settings.STT_PROVIDER == "mock":
        from app.pipecat_processors.mocks import MockSTT

        return MockSTT()

    if settings.STT_PROVIDER == "openai":
        if settings.OPENAI_API_KEY is None:
            raise APIError(
                code="SERVICE_UNAVAILABLE", message="OPENAI_API_KEY is required", status=503
            )
        return OpenAIRealtimeSTTService(
            api_key=settings.OPENAI_API_KEY.get_secret_value(),
            settings=OpenAIRealtimeSTTService.Settings(model=settings.STT_MODEL),
        )

    raise APIError(code="VALIDATION_ERROR", message="Unsupported STT provider", status=400)


def create_segmented_openai_stt_fallback(settings: Settings) -> OpenAISTTService:
    if settings.OPENAI_API_KEY is None:
        raise APIError(code="SERVICE_UNAVAILABLE", message="OPENAI_API_KEY is required", status=503)
    return OpenAISTTService(
        api_key=settings.OPENAI_API_KEY.get_secret_value(),
        settings=OpenAISTTService.Settings(model=settings.STT_MODEL),
    )
