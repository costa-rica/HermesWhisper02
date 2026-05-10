import asyncio
from collections.abc import AsyncIterator

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

    async with (
        httpx.AsyncClient(timeout=30) as client,
        client.stream(
            "POST",
            f"{settings.HERMES_BASE_URL.rstrip('/')}/chat",
            json={"query": query, "conversation_id": conversation_id},
        ) as response,
    ):
        response.raise_for_status()
        async for text in response.aiter_text():
            if text:
                yield text


async def collect_hermes_text(query: str, conversation_id: str) -> str:
    start = asyncio.get_running_loop().time()
    chunks = [chunk async for chunk in stream_hermes_text(query, conversation_id)]
    elapsed_ms = (asyncio.get_running_loop().time() - start) * 1000
    logger.info("conversation_id={} hermes_round_trip_ms={:.2f}", conversation_id, elapsed_ms)
    return "".join(chunks)
