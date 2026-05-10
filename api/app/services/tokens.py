from datetime import UTC, datetime, timedelta

import jwt
from jwt import InvalidTokenError

from app.errors import APIError
from app.models import TokenClaims


def issue_token(user_id: str, email: str, secret: str, ttl_seconds: int) -> str:
    expires_at = datetime.now(UTC) + timedelta(seconds=ttl_seconds)
    payload = {"sub": user_id, "email": email, "exp": int(expires_at.timestamp())}
    return jwt.encode(payload, secret, algorithm="HS256")


def verify_token(token: str, secret: str) -> TokenClaims:
    try:
        payload = jwt.decode(token, secret, algorithms=["HS256"])
        return TokenClaims.model_validate(payload)
    except InvalidTokenError as exc:
        raise APIError(code="AUTH_FAILED", message="Invalid bearer token", status=401) from exc
