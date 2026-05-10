from fastapi import APIRouter
from pydantic import BaseModel

from app import __version__
from app.config import get_settings

router = APIRouter(prefix="/api/server", tags=["server"])


class ServerInfo(BaseModel):
    name: str
    version: str
    front_llm: str
    auth: str
    protocol_version: int


@router.get("/info")
async def server_info() -> ServerInfo:
    settings = get_settings()
    return ServerInfo(
        name="fsdc-avatar08",
        version=__version__,
        front_llm=f"{settings.FRONT_LLM_PROVIDER}:{settings.FRONT_LLM_MODEL}",
        auth="bearer-2fa",
        protocol_version=1,
    )
