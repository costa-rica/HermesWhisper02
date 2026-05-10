from datetime import UTC, datetime, timedelta
from random import SystemRandom

from fastapi import APIRouter
from pydantic import BaseModel, EmailStr, Field

from app.config import get_settings
from app.db import Database
from app.errors import APIError
from app.services.mailer import Mailer
from app.services.passwords import verify_password
from app.services.tokens import issue_token

router = APIRouter(prefix="/api/auth", tags=["auth"])
_random = SystemRandom()


class LoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1)


class LoginResponse(BaseModel):
    ok: bool
    expires_in: int


class VerifyRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6)


class VerifyResponse(BaseModel):
    token: str
    expires_at: str


@router.post("/login")
async def login(request: LoginRequest) -> LoginResponse:
    settings = get_settings()
    db = Database(settings.DB_PATH)
    row = await db.fetch_one(
        "SELECT id, email, password_hash, created_at FROM users WHERE email = ?",
        (request.email,),
    )
    if row is None or not verify_password(request.password, row["password_hash"]):
        raise APIError(code="AUTH_FAILED", message="Invalid email or password", status=401)

    code = f"{_random.randrange(0, 1_000_000):06d}"
    expires_in = 600
    expires_at = datetime.now(UTC) + timedelta(seconds=expires_in)
    await db.execute(
        """
        INSERT INTO email_codes (email, code, expires_at)
        VALUES (?, ?, ?)
        ON CONFLICT(email) DO UPDATE SET code = excluded.code, expires_at = excluded.expires_at
        """,
        (request.email, code, expires_at.isoformat().replace("+00:00", "Z")),
    )
    await Mailer(settings).send_login_code(str(request.email), code)
    return LoginResponse(ok=True, expires_in=expires_in)


@router.post("/verify")
async def verify(request: VerifyRequest) -> VerifyResponse:
    settings = get_settings()
    db = Database(settings.DB_PATH)
    code_row = await db.fetch_one(
        "SELECT email, code, expires_at FROM email_codes WHERE email = ?",
        (request.email,),
    )
    if code_row is None or code_row["code"] != request.code:
        raise APIError(code="AUTH_FAILED", message="Invalid verification code", status=401)

    expires_at = _parse_utc(code_row["expires_at"])
    if expires_at <= datetime.now(UTC):
        raise APIError(code="AUTH_FAILED", message="Verification code expired", status=401)

    user_row = await db.fetch_one(
        "SELECT id, email, password_hash, created_at FROM users WHERE email = ?",
        (request.email,),
    )
    if user_row is None:
        raise APIError(code="AUTH_FAILED", message="Invalid verification code", status=401)

    await db.execute("DELETE FROM email_codes WHERE email = ?", (request.email,))
    token = issue_token(
        user_id=user_row["id"],
        email=user_row["email"],
        secret=settings.JWT_SECRET.get_secret_value(),
        ttl_seconds=settings.TOKEN_TTL_SECONDS,
    )
    token_expiry = datetime.now(UTC) + timedelta(seconds=settings.TOKEN_TTL_SECONDS)
    return VerifyResponse(token=token, expires_at=token_expiry.isoformat().replace("+00:00", "Z"))


def _parse_utc(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))
