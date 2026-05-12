from typing import Protocol

import httpx
from pipecat.frames.frames import TextFrame, TTSAudioRawFrame
from pipecat.services.openai.tts import OpenAITTSService

from app.config import Settings
from app.errors import APIError


class PipelineTTS(Protocol):
    async def synthesize(self, frame: TextFrame, turn_id: str) -> TTSAudioRawFrame: ...


class OpenAIHTTPPipelineTTS:
    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        voice: str,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.api_key = api_key
        self.model = model
        self.voice = voice
        self.transport = transport

    async def synthesize(self, frame: TextFrame, turn_id: str) -> TTSAudioRawFrame:
        async with httpx.AsyncClient(timeout=30, transport=self.transport) as client:
            response = await client.post(
                "https://api.openai.com/v1/audio/speech",
                headers={"Authorization": f"Bearer {self.api_key}"},
                json={
                    "model": self.model,
                    "voice": self.voice,
                    "input": frame.text,
                    "response_format": "pcm",
                },
            )
            response.raise_for_status()

        audio_frame = TTSAudioRawFrame(response.content, sample_rate=24_000, num_channels=1)
        audio_frame.metadata = {"source": getattr(frame, "metadata", {}).get("source", "answer")}
        audio_frame.turn_id = turn_id
        return audio_frame


def create_pipeline_tts(settings: Settings) -> PipelineTTS:
    if settings.TTS_PROVIDER == "mock":
        from app.pipecat_processors.mocks import MockTTS

        return MockTTS()

    if settings.TTS_PROVIDER == "openai":
        if settings.OPENAI_API_KEY is None:
            raise APIError(
                code="SERVICE_UNAVAILABLE", message="OPENAI_API_KEY is required", status=503
            )
        return OpenAIHTTPPipelineTTS(
            api_key=settings.OPENAI_API_KEY.get_secret_value(),
            model=settings.TTS_MODEL,
            voice=settings.TTS_VOICE,
        )

    raise APIError(code="VALIDATION_ERROR", message="Unsupported TTS provider", status=400)


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
