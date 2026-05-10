import os
from collections.abc import AsyncIterator

os.environ.setdefault("NAME_APP", "hermes-whisper-02-api-test")
os.environ.setdefault("RUN_ENVIRONMENT", "development")
os.environ.setdefault("JWT_SECRET", "test-secret-with-at-least-32-bytes")


import pytest
from httpx import ASGITransport, AsyncClient

from app.config import get_settings
from app.db import Database
from app.main import create_app


@pytest.fixture
async def client(tmp_path, monkeypatch) -> AsyncIterator[AsyncClient]:
    monkeypatch.setenv("DB_PATH", str(tmp_path / "test.sqlite"))
    monkeypatch.setenv("NAME_APP", "hermes-whisper-02-api-test")
    monkeypatch.setenv("RUN_ENVIRONMENT", "development")
    monkeypatch.setenv("JWT_SECRET", "test-secret-with-at-least-32-bytes")
    get_settings.cache_clear()
    await Database(get_settings().DB_PATH).bootstrap()
    app = create_app()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as test_client:
        yield test_client
    get_settings.cache_clear()
