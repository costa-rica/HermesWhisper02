from datetime import UTC, datetime, timedelta
from uuid import uuid4

from httpx import AsyncClient

from app.config import get_settings
from app.db import Database
from app.models import utc_now_iso
from app.services.passwords import hash_password


async def test_login_verify_round_trip(client: AsyncClient) -> None:
    await _seed_user("nrodrig1@gmail.com", "correct horse battery staple")

    login_response = await client.post(
        "/api/auth/login",
        json={"email": "nrodrig1@gmail.com", "password": "correct horse battery staple"},
    )
    code = await _latest_code("nrodrig1@gmail.com")
    verify_response = await client.post(
        "/api/auth/verify",
        json={"email": "nrodrig1@gmail.com", "code": code},
    )
    info_response = await client.get(
        "/api/server/info",
        headers={"Authorization": f"Bearer {verify_response.json()['token']}"},
    )

    assert login_response.status_code == 200
    assert login_response.json() == {"ok": True, "expires_in": 600}
    assert verify_response.status_code == 200
    assert verify_response.json()["token"]
    assert info_response.status_code == 200
    assert info_response.json()["protocol_version"] == 1


async def test_login_rejects_missing_user(client: AsyncClient) -> None:
    response = await client.post(
        "/api/auth/login",
        json={"email": "missing@example.com", "password": "nope"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "AUTH_FAILED"


async def test_verify_rejects_bad_code(client: AsyncClient) -> None:
    await _seed_user("nrodrig1@gmail.com", "password")
    await client.post(
        "/api/auth/login",
        json={"email": "nrodrig1@gmail.com", "password": "password"},
    )

    response = await client.post(
        "/api/auth/verify",
        json={"email": "nrodrig1@gmail.com", "code": "000000"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "AUTH_FAILED"


async def test_verify_rejects_expired_code(client: AsyncClient) -> None:
    await _seed_user("nrodrig1@gmail.com", "password")
    db = _db()
    await db.execute(
        """
        INSERT INTO email_codes (email, code, expires_at)
        VALUES (?, ?, ?)
        """,
        (
            "nrodrig1@gmail.com",
            "123456",
            (datetime.now(UTC) - timedelta(seconds=1)).isoformat().replace("+00:00", "Z"),
        ),
    )

    response = await client.post(
        "/api/auth/verify",
        json={"email": "nrodrig1@gmail.com", "code": "123456"},
    )

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "AUTH_FAILED"


async def test_protected_dependency_rejects_missing_header(client: AsyncClient) -> None:
    from app.auth import current_user

    try:
        await current_user(None)
    except Exception as exc:
        assert exc.code == "AUTH_FAILED"
        assert exc.status == 401
    else:
        raise AssertionError("current_user accepted a missing Authorization header")


async def _seed_user(email: str, password: str) -> None:
    db = _db()
    await db.bootstrap()
    await db.execute(
        """
        INSERT INTO users (id, email, password_hash, created_at)
        VALUES (?, ?, ?, ?)
        """,
        (str(uuid4()), email, hash_password(password), utc_now_iso()),
    )


async def _latest_code(email: str) -> str:
    row = await _db().fetch_one("SELECT code FROM email_codes WHERE email = ?", (email,))
    assert row is not None
    return row["code"]


def _db() -> Database:
    return Database(get_settings().DB_PATH)
