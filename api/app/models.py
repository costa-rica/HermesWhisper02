from datetime import UTC, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr


def utc_now_iso() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


class User(BaseModel):
    id: str
    email: EmailStr
    password_hash: str
    created_at: str


class VoiceSession(BaseModel):
    id: str
    owner_id: str
    conversation_id: str
    created_at: str
    last_seen: str


class VoiceMessage(BaseModel):
    id: str
    session_id: str
    role: Literal["user", "assistant", "system"]
    content: str
    created_at: str


class TokenClaims(BaseModel):
    model_config = ConfigDict(extra="ignore")

    sub: str
    email: EmailStr
    exp: int
