import httpx

from app.services.stt import OpenAIHTTPPipelineSTT


async def test_openai_http_pipeline_stt_uploads_wav() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/audio/transcriptions"
        assert request.headers["authorization"] == "Bearer test-key"
        assert b"audio/wav" in request.content
        assert b"gpt-4o-mini-transcribe" in request.content
        return httpx.Response(200, json={"text": "real spoken words"})

    stt = OpenAIHTTPPipelineSTT(
        api_key="test-key",
        model="gpt-4o-mini-transcribe",
        transport=httpx.MockTransport(handler),
    )

    transcript = await stt.transcribe(b"\x00\x00\x01\x00", sample_rate=16_000)

    assert transcript.text == "real spoken words"
    assert transcript.finalized is True
