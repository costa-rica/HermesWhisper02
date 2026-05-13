import asyncio
import json
from collections.abc import AsyncIterator
from dataclasses import dataclass
from typing import Any

import httpx
from loguru import logger

from app.config import get_settings


@dataclass(frozen=True)
class SpeakableDelta:
    text: str


@dataclass(frozen=True)
class ProgressEvent:
    kind: str
    text: str
    raw: dict[str, Any]


HermesEvent = SpeakableDelta | ProgressEvent


async def stream_hermes_text(query: str, conversation_id: str) -> AsyncIterator[str]:
    async for event in stream_hermes_events(query, conversation_id):
        if isinstance(event, SpeakableDelta):
            yield event.text


async def stream_hermes_events(query: str, conversation_id: str) -> AsyncIterator[HermesEvent]:
    settings = get_settings()
    if settings.HERMES_MOCK:
        events: tuple[HermesEvent, ...] = (
            ProgressEvent(
                kind="response_started",
                text="Hermes accepted the request.",
                raw={"mock": True},
            ),
            ProgressEvent(
                kind="tool_call",
                text="Mock Hermes started a tool call.",
                raw={"mock": True},
            ),
            ProgressEvent(
                kind="tool_result",
                text="Mock Hermes received a tool result.",
                raw={"mock": True},
            ),
            SpeakableDelta("Hermes mock response: "),
            SpeakableDelta(f"I received '{query}'. "),
            SpeakableDelta(f"Conversation {conversation_id} is using local mock mode."),
        )
        for event in events:
            await asyncio.sleep(0.02)
            yield event
        return

    async with httpx.AsyncClient(timeout=30) as client:
        async for event in _stream_live_hermes_events(
            query=query,
            conversation_id=conversation_id,
            base_url=settings.HERMES_BASE_URL,
            chat_path=settings.HERMES_CHAT_PATH,
            model=settings.HERMES_MODEL,
            api_key=(
                settings.HERMES_API_KEY.get_secret_value() if settings.HERMES_API_KEY else None
            ),
            client=client,
        ):
            yield event


async def _stream_live_hermes_text(
    **kwargs: Any,
) -> AsyncIterator[str]:
    async for event in _stream_live_hermes_events(**kwargs):
        if isinstance(event, SpeakableDelta):
            yield event.text


async def _stream_live_hermes_events(
    *,
    query: str,
    conversation_id: str,
    base_url: str,
    chat_path: str,
    model: str,
    api_key: str | None,
    client: httpx.AsyncClient,
) -> AsyncIterator[HermesEvent]:
    normalized_path = chat_path if chat_path.startswith("/") else f"/{chat_path}"
    url = f"{base_url.rstrip('/')}{normalized_path}"
    headers = {"Authorization": f"Bearer {api_key}"} if api_key else {}
    logger.info("hermes_live_request_starting url={} conversation_id={}", url, conversation_id)
    async with client.stream(
        "POST",
        url,
        headers=headers,
        json={
            "model": model,
            "messages": [{"role": "user", "content": query}],
            "stream": True,
        },
    ) as response:
        logger.info(
            "hermes_live_response_started url={} status={} content_type={}",
            url,
            response.status_code,
            response.headers.get("content-type", ""),
        )
        yield ProgressEvent(
            kind="response_started",
            text="Hermes accepted the request.",
            raw={"status": response.status_code},
        )
        if response.is_error:
            body = (await response.aread()).decode(errors="replace")[:500]
            logger.error(
                "hermes_live_response_error url={} status={} body={}",
                url,
                response.status_code,
                body,
            )
        response.raise_for_status()
        content_type = response.headers.get("content-type", "")
        if "application/json" in content_type:
            payload = json.loads((await response.aread()).decode())
            text = _extract_hermes_text(payload)
            if text:
                yield SpeakableDelta(text)
            return

        event_name: str | None = None
        data_lines: list[str] = []
        async for line in response.aiter_lines():
            async for event in _parse_sse_line(line, event_name, data_lines):
                yield event
            if line.startswith("event:"):
                event_name = line.removeprefix("event:").strip()
            elif line.startswith("data:"):
                data_lines.append(line.removeprefix("data:").strip())
            elif not line.strip():
                event_name = None
                data_lines.clear()


async def _parse_sse_line(
    line: str, event_name: str | None, data_lines: list[str]
) -> AsyncIterator[HermesEvent]:
    if line.strip():
        return
    if not data_lines:
        return
    data = "\n".join(data_lines).strip()
    if data == "[DONE]":
        return
    try:
        payload = json.loads(data)
    except json.JSONDecodeError:
        if data:
            yield SpeakableDelta(data)
        return

    progress = _extract_progress_event(event_name, payload)
    if progress is not None:
        yield progress
        return

    text = _extract_hermes_text(payload)
    if text:
        yield SpeakableDelta(text)


def _extract_hermes_text(payload: Any) -> str | None:
    if isinstance(payload, str):
        return payload
    if isinstance(payload, list):
        return "".join(text for item in payload if (text := _extract_hermes_text(item)))
    if not isinstance(payload, dict):
        return None

    choices = payload.get("choices")
    if isinstance(choices, list):
        return "".join(text for item in choices if (text := _extract_hermes_text(item)))

    for key in ("delta", "text", "content", "answer", "response", "message"):
        text = _extract_hermes_text(payload.get(key))
        if text:
            return text
    return None


async def collect_hermes_text(query: str, conversation_id: str) -> str:
    return await collect_hermes_text_with_progress(query, conversation_id)


async def collect_hermes_text_with_progress(
    query: str,
    conversation_id: str,
    progress_handler: Any | None = None,
) -> str:
    start = asyncio.get_running_loop().time()
    chunks: list[str] = []
    await _emit_progress(
        progress_handler,
        ProgressEvent(
            kind="sent_to_hermes",
            text="Sent request to Hermes.",
            raw={"conversation_id": conversation_id},
        ),
    )
    try:
        async for event in stream_hermes_events(query, conversation_id):
            if isinstance(event, SpeakableDelta):
                chunks.append(event.text)
            else:
                await _emit_progress(progress_handler, event)
        await _emit_progress(
            progress_handler,
            ProgressEvent(
                kind="finished",
                text="Hermes finished.",
                raw={"conversation_id": conversation_id},
            ),
        )
        return "".join(chunks)
    except Exception as exc:
        await _emit_progress(
            progress_handler,
            ProgressEvent(
                kind="failed",
                text="Hermes failed before returning an answer.",
                raw={"error_type": type(exc).__name__, "error": str(exc)},
            ),
        )
        raise
    finally:
        elapsed_ms = (asyncio.get_running_loop().time() - start) * 1000
        logger.info("conversation_id={} hermes_round_trip_ms={:.2f}", conversation_id, elapsed_ms)


async def _emit_progress(progress_handler: Any | None, event: ProgressEvent) -> None:
    if progress_handler is not None:
        await progress_handler(event)


def _extract_progress_event(event_name: str | None, payload: Any) -> ProgressEvent | None:
    if not isinstance(payload, dict):
        return None

    kind = _progress_kind(event_name, payload)
    if kind is None:
        return None

    text = _extract_progress_text(payload)
    if not text:
        text = "Hermes is using a tool." if kind == "tool_call" else "Hermes received tool output."
    return ProgressEvent(kind=kind, text=text, raw=payload)


def _progress_kind(event_name: str | None, payload: dict[str, Any]) -> str | None:
    haystack = " ".join(
        str(value)
        for value in (
            event_name,
            payload.get("type"),
            payload.get("event"),
            _nested_value(payload, ("item", "type")),
            _nested_value(payload, ("delta", "type")),
        )
        if value is not None
    ).lower()
    if "tool_result" in haystack or "tool_output" in haystack or "function_call_output" in haystack:
        return "tool_result"
    if "tool_call" in haystack or "function_call" in haystack:
        return "tool_call"
    return None


def _extract_progress_text(payload: dict[str, Any]) -> str:
    for key in ("summary", "name", "text", "content", "arguments", "output"):
        value = _extract_hermes_text(payload.get(key))
        if value:
            return value
    for key in ("item", "delta", "result", "tool_call", "tool_result"):
        nested = payload.get(key)
        if isinstance(nested, dict):
            text = _extract_progress_text(nested)
            if text:
                return text
    return ""


def _nested_value(payload: dict[str, Any], path: tuple[str, ...]) -> Any:
    current: Any = payload
    for key in path:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current
