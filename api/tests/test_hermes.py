import httpx

from app.services.hermes import (
    ProgressEvent,
    SpeakableDelta,
    _stream_live_hermes_events,
    _stream_live_hermes_text,
    collect_hermes_text_with_progress,
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
            kind="response_started",
            text="Hermes accepted the request.",
            raw={"status": 200},
        ),
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


async def test_live_hermes_stream_formats_tool_arguments_for_activity() -> None:
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"content-type": "text/event-stream"},
            text=(
                "event: response.output_item.added\n"
                'data: {"type":"response.output_item.added",'
                '"item":{"type":"function_call","name":"terminal",'
                '"arguments":"{\\"command\\":\\"set -euo pipefail python3 - <<PY\\"}"}}\n\n'
                "event: response.output_item.added\n"
                'data: {"type":"response.output_item.added",'
                '"item":{"type":"function_call","name":"read_file",'
                '"arguments":{"path":"/home/nick/hermes/config.yaml"}}}\n\n'
                "data: [DONE]\n\n"
            ),
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        events = [
            event
            async for event in _stream_live_hermes_events(
                query="inspect config",
                conversation_id="conversation-1",
                base_url="http://hermes.test",
                chat_path="/v1/chat/completions",
                model="hermes-agent",
                api_key=None,
                client=client,
            )
        ]

    assert events[1:3] == [
        ProgressEvent(
            kind="tool_call",
            text='terminal: "set -euo pipefail python3 - <<PY"',
            raw={
                "type": "response.output_item.added",
                "item": {
                    "type": "function_call",
                    "name": "terminal",
                    "arguments": '{"command":"set -euo pipefail python3 - <<PY"}',
                },
            },
        ),
        ProgressEvent(
            kind="tool_call",
            text='read_file: "/home/nick/hermes/config.yaml"',
            raw={
                "type": "response.output_item.added",
                "item": {
                    "type": "function_call",
                    "name": "read_file",
                    "arguments": {"path": "/home/nick/hermes/config.yaml"},
                },
            },
        ),
    ]


async def test_collect_hermes_text_reports_lifecycle_progress(monkeypatch) -> None:
    events = []

    async def handle_progress(event: ProgressEvent) -> None:
        events.append(event.kind)

    monkeypatch.setenv("HERMES_MOCK", "true")
    from app.config import get_settings

    get_settings.cache_clear()

    answer = await collect_hermes_text_with_progress(
        "tell me a story",
        "conversation-1",
        progress_handler=handle_progress,
    )

    assert "Hermes mock response" in answer
    assert events == [
        "sent_to_hermes",
        "response_started",
        "tool_call",
        "tool_result",
        "finished",
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
