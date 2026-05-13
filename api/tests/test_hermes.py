import httpx

from app.services.hermes import (
    ProgressEvent,
    SpeakableDelta,
    _stream_live_hermes_events,
    _stream_live_hermes_text,
)


async def test_live_hermes_stream_accepts_sse_json_text() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/chat/completions"
        assert request.headers["authorization"] == "Bearer test-key"
        payload = json_from_request(request)
        assert payload == {
            "model": "hermes-agent",
            "messages": [{"role": "user", "content": "hello"}],
            "stream": True,
        }
        return httpx.Response(
            200,
            headers={"content-type": "text/event-stream"},
            text=(
                'data: {"choices":[{"delta":{"role":"assistant"},"finish_reason":null}]}\n\n'
                'data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}\n\n'
                'data: {"choices":[{"delta":{"content":" Hermes"},"finish_reason":null}]}\n\n'
                'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\n'
                "data: [DONE]\n\n"
            ),
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        chunks = [
            chunk
            async for chunk in _stream_live_hermes_text(
                query="hello",
                conversation_id="conversation-1",
                base_url="http://hermes.test",
                chat_path="/v1/chat/completions",
                model="hermes-agent",
                api_key="test-key",
                client=client,
            )
        ]

    assert chunks == ["Hello", " Hermes"]


async def test_live_hermes_stream_surfaces_tool_progress() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/event-stream"},
            text=(
                "event: response.output_item.added\n"
                'data: {"type":"response.output_item.added",'
                '"item":{"type":"function_call","name":"search_documents"}}\n\n'
                "event: response.output_item.done\n"
                'data: {"type":"response.output_item.done",'
                '"item":{"type":"function_call_output","output":"Found 2 documents"}}\n\n'
                'data: {"choices":[{"delta":{"content":"Done."}}]}\n\n'
                "data: [DONE]\n\n"
            ),
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        events = [
            event
            async for event in _stream_live_hermes_events(
                query="find docs",
                conversation_id="conversation-1",
                base_url="http://hermes.test",
                chat_path="/v1/chat/completions",
                model="hermes-agent",
                api_key=None,
                client=client,
            )
        ]

    assert events == [
        ProgressEvent(
            kind="tool_call",
            text="search_documents",
            raw={
                "type": "response.output_item.added",
                "item": {"type": "function_call", "name": "search_documents"},
            },
        ),
        ProgressEvent(
            kind="tool_result",
            text="Found 2 documents",
            raw={
                "type": "response.output_item.done",
                "item": {"type": "function_call_output", "output": "Found 2 documents"},
            },
        ),
        SpeakableDelta("Done."),
    ]


async def test_live_hermes_stream_accepts_json_answer() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "application/json"},
            json={"choices": [{"message": {"role": "assistant", "content": "Hermes answered."}}]},
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        chunks = [
            chunk
            async for chunk in _stream_live_hermes_text(
                query="hello",
                conversation_id="conversation-1",
                base_url="http://hermes.test",
                chat_path="/chat",
                model="hermes-agent",
                api_key=None,
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
                model="hermes-agent",
                api_key=None,
                client=client,
            )
        ]

    assert chunks == ["custom path"]


def json_from_request(request: httpx.Request) -> dict:
    import json

    return json.loads(request.content.decode())
