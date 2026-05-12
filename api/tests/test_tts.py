import httpx
import pytest
from pipecat.frames.frames import TextFrame

from app.config import Settings
from app.errors import APIError
from app.services.tts import OpenAIHTTPPipelineTTS, create_pipeline_tts


async def test_openai_http_pipeline_tts_requests_pcm() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/audio/speech"
        assert request.headers["authorization"] == "Bearer test-key"
        assert request.headers["content-type"] == "application/json"
        assert request.content
        return httpx.Response(200, content=b"\x00\x00\x01\x00")

    tts = OpenAIHTTPPipelineTTS(
        api_key="test-key",
        model="tts-1",
        voice="alloy",
        transport=httpx.MockTransport(handler),
    )
    frame = TextFrame("hello")
    frame.metadata = {"source": "answer"}

    audio = await tts.synthesize(frame, "turn-1")

    assert audio.audio == b"\x00\x00\x01\x00"
    assert audio.sample_rate == 24_000
    assert audio.metadata == {"source": "answer"}
    assert audio.turn_id == "turn-1"


def test_pipeline_tts_rejects_empty_openai_key(tmp_path) -> None:
    settings = Settings(
        NAME_APP="hermes-whisper-02-api-test",
        RUN_ENVIRONMENT="development",
        JWT_SECRET="test-secret-with-at-least-32-bytes",
        DB_PATH=tmp_path / "test.sqlite",
        TTS_PROVIDER="openai",
        OPENAI_API_KEY="",
    )

    with pytest.raises(APIError) as exc_info:
        create_pipeline_tts(settings)

    assert exc_info.value.code == "SERVICE_UNAVAILABLE"
    assert exc_info.value.message == "OPENAI_API_KEY is required"
