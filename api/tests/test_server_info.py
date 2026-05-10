from httpx import AsyncClient


async def test_server_info(client: AsyncClient) -> None:
    response = await client.get("/api/server/info")

    assert response.status_code == 200
    assert response.json() == {
        "name": "fsdc-avatar08",
        "version": "0.1.0",
        "front_llm": "openai:gpt-4o-mini",
        "auth": "bearer-2fa",
        "protocol_version": 1,
    }
