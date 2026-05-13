import httpx

from app.services.hermes import _stream_live_hermes_text, collect_hermes_text_with_progress


async def test_live_hermes_request_sends_session_header() -> None:
    observed_headers: dict[str, str] = {}

    async def handler(request: httpx.Request) -> httpx.Response:
        observed_headers["session_id"] = request.headers["x-hermes-session-id"]
        observed_headers["authorization"] = request.headers["authorization"]
        return httpx.Response(
            200,
            headers={"content-type": "application/json"},
            json={"choices": [{"message": {"content": "Hermes answered."}}]},
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        chunks = [
            chunk
            async for chunk in _stream_live_hermes_text(
                query="continue the conversation",
                conversation_id="conversation-123",
                base_url="http://hermes.test",
                chat_path="/v1/chat/completions",
                model="hermes-agent",
                api_key="test-key",
                client=client,
            )
        ]

    assert chunks == ["Hermes answered."]
    assert observed_headers == {
        "session_id": "conversation-123",
        "authorization": "Bearer test-key",
    }


async def test_mock_hermes_mode_still_returns_without_live_http(monkeypatch) -> None:
    monkeypatch.setenv("HERMES_MOCK", "true")
    from app.config import get_settings

    get_settings.cache_clear()

    answer = await collect_hermes_text_with_progress(
        "hello",
        "conversation-123",
    )

    assert "Hermes mock response" in answer
    assert "conversation-123" in answer
