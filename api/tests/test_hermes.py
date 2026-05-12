import httpx

from app.services.hermes import _stream_live_hermes_text


async def test_live_hermes_stream_accepts_sse_json_text() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/chat"
        return httpx.Response(
            200,
            headers={"content-type": "text/event-stream"},
            text='data: {"text": "Hello"}\n\ndata: {"content": " Hermes"}\n\ndata: [DONE]\n\n',
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        chunks = [
            chunk
            async for chunk in _stream_live_hermes_text(
                query="hello",
                conversation_id="conversation-1",
                base_url="http://hermes.test",
                chat_path="/chat",
                client=client,
            )
        ]

    assert chunks == ["Hello", " Hermes"]


async def test_live_hermes_stream_accepts_json_answer() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "application/json"},
            json={"answer": "Hermes answered."},
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        chunks = [
            chunk
            async for chunk in _stream_live_hermes_text(
                query="hello",
                conversation_id="conversation-1",
                base_url="http://hermes.test",
                chat_path="/chat",
                client=client,
            )
        ]

    assert chunks == ["Hermes answered."]


async def test_live_hermes_stream_uses_configured_path() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/api/chat"
        return httpx.Response(
            200,
            headers={"content-type": "application/json"},
            json={"text": "custom path"},
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        chunks = [
            chunk
            async for chunk in _stream_live_hermes_text(
                query="hello",
                conversation_id="conversation-1",
                base_url="http://hermes.test/",
                chat_path="api/chat",
                client=client,
            )
        ]

    assert chunks == ["custom path"]
