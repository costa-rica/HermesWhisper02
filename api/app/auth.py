from typing import Annotated

from fastapi import Header

from app.config import get_settings
from app.db import Database
from app.errors import APIError
from app.models import User
from app.services.tokens import verify_token


async def current_user(authorization: Annotated[str | None, Header()] = None) -> User:
    if not authorization or not authorization.startswith("Bearer "):
        raise APIError(code="AUTH_FAILED", message="Missing bearer token", status=401)

    settings = get_settings()
    token = authorization.removeprefix("Bearer ").strip()
    claims = verify_token(token, settings.JWT_SECRET.get_secret_value())

    db = Database(settings.DB_PATH)
    row = await db.fetch_one(
        "SELECT id, email, password_hash, created_at FROM users WHERE id = ?",
        (claims.sub,),
    )
    if row is None:
        raise APIError(code="AUTH_FAILED", message="Invalid bearer token", status=401)
    return User.model_validate(dict(row))
