import asyncio
import json
from collections.abc import AsyncIterator
from typing import Any

import httpx
from loguru import logger

from app.config import get_settings


async def stream_hermes_text(query: str, conversation_id: str) -> AsyncIterator[str]:
    settings = get_settings()
    if settings.HERMES_MOCK:
        chunks = (
            "Hermes mock response: ",
            f"I received '{query}'. ",
            f"Conversation {conversation_id} is using local mock mode.",
        )
        for chunk in chunks:
            await asyncio.sleep(0.02)
            yield chunk
        return

    async with httpx.AsyncClient(timeout=30) as client:
        async for chunk in _stream_live_hermes_text(
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
            yield chunk


async def _stream_live_hermes_text(
    *,
    query: str,
    conversation_id: str,
    base_url: str,
    chat_path: str,
    model: str,
    api_key: str | None,
    client: httpx.AsyncClient,
) -> AsyncIterator[str]:
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
                yield text
            return

        async for line in response.aiter_lines():
            text = _parse_hermes_stream_line(line)
            if text:
                yield text


def _parse_hermes_stream_line(line: str) -> str | None:
    stripped = line.strip()
    if not stripped:
        return None
    if stripped.startswith(":"):
        return None
    if stripped.startswith("data:"):
        stripped = stripped.removeprefix("data:").strip()
    if stripped == "[DONE]":
        return None

    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError:
        return stripped
    return _extract_hermes_text(payload)


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
    start = asyncio.get_running_loop().time()
    chunks = [chunk async for chunk in stream_hermes_text(query, conversation_id)]
    elapsed_ms = (asyncio.get_running_loop().time() - start) * 1000
    logger.info("conversation_id={} hermes_round_trip_ms={:.2f}", conversation_id, elapsed_ms)
    return "".join(chunks)
