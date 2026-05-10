import json
from typing import Any

from fastapi import APIRouter, WebSocket
from starlette.websockets import WebSocketDisconnect

from app.config import get_settings
from app.db import Database
from app.errors import APIError, ErrorBody, ErrorEnvelope
from app.models import User
from app.pipecat_processors.ws_transport_adapter import (
    PassthroughEchoPipeline,
    ProjectWebSocketTransportAdapter,
)
from app.services.tokens import verify_token
from app.services.voice_store import VoiceStore

router = APIRouter(tags=["voice"])

PROTOCOL_VERSION = 1


@router.websocket("/ws/voice")
async def voice_ws(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        user = await _authenticate(websocket)
        hello = await _receive_client_hello(websocket)
        store = VoiceStore(Database(get_settings().DB_PATH))
        session, resumed = await store.get_or_create_session(user.id, hello.get("session_id"))
        await websocket.send_json(
            {
                "type": "session_started",
                "session_id": session.id,
                "conversation_id": session.conversation_id,
                "downlink_format": hello.get("downlink_format", "pcm16"),
                "sample_rate": 24_000,
                "front_llm": (
                    f"{get_settings().FRONT_LLM_PROVIDER}:{get_settings().FRONT_LLM_MODEL}"
                ),
                "resumed": resumed,
            }
        )
        await _voice_loop(ProjectWebSocketTransportAdapter(websocket))
    except APIError as exc:
        await websocket.send_json(_error_payload(exc))
        await websocket.close(code=1008)
    except WebSocketDisconnect:
        return


async def _voice_loop(adapter: ProjectWebSocketTransportAdapter) -> None:
    pipeline = PassthroughEchoPipeline(adapter)
    while True:
        websocket = adapter.websocket
        message = await websocket.receive()
        if message["type"] == "websocket.disconnect":
            return
        if "text" in message:
            frame = _parse_json(message["text"])
            frame_type = frame.get("type")
            if frame_type == "ping":
                await websocket.send_json({"type": "pong", "ts": frame.get("ts")})
            elif frame_type == "cancel_turn":
                await websocket.send_json(
                    {
                        "type": "turn_end",
                        "turn_id": frame.get("turn_id", pipeline.turn_id),
                        "canceled": True,
                    }
                )
                pipeline = PassthroughEchoPipeline(adapter)
            elif frame_type == "client_bye":
                await websocket.close(code=1000)
                return
            else:
                await _send_protocol_error(websocket, f"Unsupported frame type: {frame_type}")
                return
        elif "bytes" in message:
            input_frame = await adapter.receive_input_frame(message)
            if input_frame is not None:
                await pipeline.process_audio(input_frame)


async def _authenticate(websocket: WebSocket) -> User:
    settings = get_settings()
    authorization = websocket.headers.get("authorization")
    token = None
    if authorization and authorization.startswith("Bearer "):
        token = authorization.removeprefix("Bearer ").strip()
    elif settings.WS_QUERY_TOKEN_FALLBACK_ENABLED:
        token = websocket.query_params.get("token")
    if not token:
        raise APIError(code="AUTH_FAILED", message="Missing bearer token", status=401)

    claims = verify_token(token, settings.JWT_SECRET.get_secret_value())
    row = await Database(settings.DB_PATH).fetch_one(
        "SELECT id, email, password_hash, created_at FROM users WHERE id = ?",
        (claims.sub,),
    )
    if row is None:
        raise APIError(code="AUTH_FAILED", message="Invalid bearer token", status=401)
    return User.model_validate(dict(row))


async def _receive_client_hello(websocket: WebSocket) -> dict[str, Any]:
    message = await websocket.receive_text()
    frame = _parse_json(message)
    if frame.get("type") != "client_hello":
        raise APIError(code="VALIDATION_ERROR", message="Expected client_hello", status=400)
    if frame.get("protocol_version") != PROTOCOL_VERSION:
        raise APIError(code="VALIDATION_ERROR", message="Unsupported protocol version", status=400)
    if frame.get("sample_rate") != 16_000:
        raise APIError(
            code="VALIDATION_ERROR", message="Unsupported uplink sample rate", status=400
        )
    return frame


def _parse_json(payload: str) -> dict[str, Any]:
    try:
        frame = json.loads(payload)
    except json.JSONDecodeError as exc:
        raise APIError(code="VALIDATION_ERROR", message="Invalid JSON frame", status=400) from exc
    if not isinstance(frame, dict) or "type" not in frame:
        raise APIError(code="VALIDATION_ERROR", message="Invalid protocol frame", status=400)
    return frame


async def _send_protocol_error(websocket: WebSocket, message: str) -> None:
    await websocket.send_json(
        _error_payload(APIError(code="VALIDATION_ERROR", message=message, status=400))
    )
    await websocket.close(code=1003)


def _error_payload(exc: APIError) -> dict[str, Any]:
    return ErrorEnvelope(
        error=ErrorBody(code=exc.code, message=exc.message, status=exc.status, details=exc.details)
    ).model_dump()
