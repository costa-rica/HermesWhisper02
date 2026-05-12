import io
import wave
from datetime import UTC, datetime
from typing import Protocol

import httpx
from pipecat.frames.frames import TranscriptionFrame
from pipecat.services.openai.stt import OpenAIRealtimeSTTService, OpenAISTTService

from app.config import Settings
from app.errors import APIError


class PipelineSTT(Protocol):
    async def transcribe(self, audio: bytes, sample_rate: int = 16_000) -> TranscriptionFrame: ...


class OpenAIHTTPPipelineSTT:
    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self.api_key = api_key
        self.model = model
        self.transport = transport

    async def transcribe(self, audio: bytes, sample_rate: int = 16_000) -> TranscriptionFrame:
        wav_audio = _pcm16_mono_to_wav(audio, sample_rate)
        async with httpx.AsyncClient(timeout=30, transport=self.transport) as client:
            response = await client.post(
                "https://api.openai.com/v1/audio/transcriptions",
                headers={"Authorization": f"Bearer {self.api_key}"},
                data={"model": self.model},
                files={"file": ("audio.wav", wav_audio, "audio/wav")},
            )
            response.raise_for_status()

        payload = response.json()
        text = payload.get("text", "") if isinstance(payload, dict) else ""
        return TranscriptionFrame(
            text=text.strip(),
            user_id="mobile-user",
            timestamp=datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            finalized=True,
        )


def create_pipeline_stt(settings: Settings) -> PipelineSTT:
    if settings.STT_PROVIDER == "mock":
        from app.pipecat_processors.mocks import MockSTT

        return MockSTT()

    if settings.STT_PROVIDER == "openai":
        api_key = _required_openai_api_key(settings)
        return OpenAIHTTPPipelineSTT(
            api_key=api_key,
            model=settings.STT_MODEL,
        )

    raise APIError(code="VALIDATION_ERROR", message="Unsupported STT provider", status=400)


def _required_openai_api_key(settings: Settings) -> str:
    if settings.OPENAI_API_KEY is None:
        raise APIError(code="SERVICE_UNAVAILABLE", message="OPENAI_API_KEY is required", status=503)
    api_key = settings.OPENAI_API_KEY.get_secret_value().strip()
    if not api_key:
        raise APIError(code="SERVICE_UNAVAILABLE", message="OPENAI_API_KEY is required", status=503)
    return api_key


def _pcm16_mono_to_wav(audio: bytes, sample_rate: int) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(audio)
    return buffer.getvalue()


def create_stt_service(settings: Settings):
    if settings.STT_PROVIDER == "mock":
        from app.pipecat_processors.mocks import MockSTT

        return MockSTT()

    if settings.STT_PROVIDER == "openai":
        api_key = _required_openai_api_key(settings)
        return OpenAIRealtimeSTTService(
            api_key=api_key,
            settings=OpenAIRealtimeSTTService.Settings(model=settings.STT_MODEL),
        )

    raise APIError(code="VALIDATION_ERROR", message="Unsupported STT provider", status=400)


def create_segmented_openai_stt_fallback(settings: Settings) -> OpenAISTTService:
    api_key = _required_openai_api_key(settings)
    return OpenAISTTService(
        api_key=api_key,
        settings=OpenAISTTService.Settings(model=settings.STT_MODEL),
    )
