import os

os.environ.setdefault("NAME_APP", "hermes-whisper-02-api-test")
os.environ.setdefault("RUN_ENVIRONMENT", "development")
os.environ.setdefault("JWT_SECRET", "test-secret")


import pytest
from httpx import ASGITransport, AsyncClient

from app.main import create_app


@pytest.fixture
async def client() -> AsyncClient:
    app = create_app()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://testserver") as test_client:
        yield test_client
