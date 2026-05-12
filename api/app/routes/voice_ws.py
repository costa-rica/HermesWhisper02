import json
from typing import Any

from fastapi import APIRouter, WebSocket
from loguru import logger
from starlette.websockets import WebSocketDisconnect

from app.config import get_settings
from app.db import Database
from app.errors import APIError, ErrorBody, ErrorEnvelope
from app.models import User
from app.pipecat_processors.ws_transport_adapter import (
    PassthroughEchoPipeline,
    ProjectWebSocketTransportAdapter,
)
from app.services.pipeline import build_pipeline
from app.services.tokens import verify_token
from app.services.voice_store import VoiceStore

router = APIRouter(tags=["voice"])

PROTOCOL_VERSION = 1
UPLINK_TURN_BYTES = 16_000 * 2


@router.websocket("/ws/voice")
async def voice_ws(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        user = await _authenticate(websocket)
        hello = await _receive_client_hello(websocket)
        settings = get_settings()
        store = VoiceStore(Database(settings.DB_PATH))
        session, resumed = await store.get_or_create_session(
            user.id,
            hello.get("session_id"),
            settings.SESSION_RESUME_WINDOW_SEC,
        )
        context_messages = await store.list_messages(session.id)
        await websocket.send_json(
            {
                "type": "session_started",
                "session_id": session.id,
                "conversation_id": session.conversation_id,
                "downlink_format": hello.get("downlink_format", "pcm16"),
                "sample_rate": 24_000,
                "front_llm": (f"{settings.FRONT_LLM_PROVIDER}:{settings.FRONT_LLM_MODEL}"),
                "resumed": resumed,
            }
        )
        await _voice_loop(
            ProjectWebSocketTransportAdapter(websocket),
            store,
            session.id,
            session.conversation_id,
            context_messages,
        )
    except APIError as exc:
        await websocket.send_json(_error_payload(exc))
        await websocket.close(code=1008)
    except WebSocketDisconnect:
        return
    except Exception as exc:
        logger.exception("voice_ws_failed error_type={} error={}", type(exc).__name__, exc)
        try:
            await websocket.send_json(
                _error_payload(
                    APIError(
                        code="SERVICE_UNAVAILABLE",
                        message="Voice service failed while processing audio",
                        status=503,
                    )
                )
            )
            await websocket.close(code=1011)
        except Exception:
            logger.exception("voice_ws_error_close_failed")


async def _voice_loop(
    adapter: ProjectWebSocketTransportAdapter,
    store: VoiceStore,
    session_id: str,
    conversation_id: str,
    context_messages,
) -> None:
    pipeline = PassthroughEchoPipeline(adapter)
    mock_pipeline = build_pipeline(conversation_id, context_messages)
    active_turn_id: str | None = None
    while True:
        websocket = adapter.websocket
        message = await websocket.receive()
        if message["type"] == "websocket.disconnect":
            if active_turn_id is not None:
                await store.fail_turn(active_turn_id)
            return
        if "text" in message:
            frame = _parse_json(message["text"])
            frame_type = frame.get("type")
            if frame_type == "ping":
                await store.touch_session(session_id)
                await websocket.send_json({"type": "pong", "ts": frame.get("ts")})
            elif frame_type == "cancel_turn":
                canceled_turn_id = frame.get("turn_id", active_turn_id or pipeline.turn_id)
                if canceled_turn_id:
                    await store.cancel_turn(canceled_turn_id)
                await websocket.send_json(
                    {
                        "type": "turn_end",
                        "turn_id": canceled_turn_id or pipeline.turn_id,
                        "canceled": True,
                    }
                )
                active_turn_id = None
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
                pipeline.buffered_audio_bytes += len(input_frame.audio)
                if pipeline.buffered_audio_bytes >= UPLINK_TURN_BYTES:
                    turn = await mock_pipeline.process_audio(input_frame.audio)
                    active_turn_id = turn.turn_id
                    try:
                        await store.start_turn(session_id, turn.turn_id)
                    except ValueError:
                        await _send_protocol_error(websocket, "Duplicate turn_id")
                        return
                    await adapter.websocket.send_json(
                        {
                            "type": "transcript",
                            "turn_id": turn.turn_id,
                            "text": turn.transcript,
                            "is_final": True,
                        }
                    )
                    for chunk in turn.chunks:
                        await adapter.websocket.send_json(
                            {"type": "assistant_state", "state": chunk.source}
                        )
                        await store.mark_first_audio(turn.turn_id, chunk.source)
                        await adapter.send_audio_chunk(
                            turn_id=chunk.turn_id,
                            source=chunk.source,  # type: ignore[arg-type]
                            sample_rate=chunk.sample_rate,
                            audio=chunk.audio,
                        )
                    await adapter.websocket.send_json({"type": "turn_end", "turn_id": turn.turn_id})
                    await store.complete_turn(turn.turn_id)
                    await store.append_completed_exchange(
                        session_id,
                        turn.turn_id,
                        turn.transcript,
                        turn.answer_text,
                    )
                    await store.touch_session(session_id)
                    active_turn_id = None
                    await adapter.websocket.send_json({"type": "assistant_state", "state": "idle"})
                    pipeline = PassthroughEchoPipeline(adapter)


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
