import os

import pytest

from app.config import get_settings
from app.services.hermes import stream_hermes_text


@pytest.mark.integration
@pytest.mark.skipif(
    os.getenv("HERMES_MOCK", "true").lower() != "false",
    reason="requires live Hermes on avatar08 with HERMES_MOCK=false",
)
async def test_live_hermes_returns_text() -> None:
    get_settings.cache_clear()
    chunks = [
        chunk
        async for chunk in stream_hermes_text(
            query="Say hello in one short sentence.",
            conversation_id="integration-test",
        )
    ]

    assert "".join(chunks).strip()
