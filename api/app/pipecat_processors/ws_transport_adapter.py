from dataclasses import dataclass, field
from typing import Any, Literal
from uuid import uuid4

from fastapi import WebSocket

from app.errors import APIError

UPLINK_BYTES_PER_SECOND = 16_000 * 2


@dataclass(frozen=True)
class InputAudioRawFrame:
    audio: bytes
    sample_rate: int = 16_000
    num_channels: int = 1


@dataclass(frozen=True)
class TTSAudioRawFrame:
    audio: bytes
    sample_rate: int
    turn_id: str
    source: Literal["ack", "answer"]
    metadata: dict[str, Any] = field(default_factory=dict)


class ProjectWebSocketTransportAdapter:
    def __init__(self, websocket: WebSocket) -> None:
        self.websocket = websocket
        self._sequence_by_source: dict[str, int] = {"ack": 0, "answer": 0}

    async def receive_input_frame(self, message: dict[str, Any]) -> InputAudioRawFrame | None:
        if message["type"] == "websocket.disconnect":
            return None
        if "bytes" in message:
            return InputAudioRawFrame(audio=message["bytes"])
        if "text" in message:
            return None
        raise APIError(code="VALIDATION_ERROR", message="Unsupported websocket message", status=400)

    async def send_tts_audio(self, frame: TTSAudioRawFrame) -> None:
        sequence = self._sequence_by_source[frame.source]
        self._sequence_by_source[frame.source] = sequence + 1
        await self.websocket.send_json(
            {
                "type": "audio_chunk",
                "turn_id": frame.turn_id,
                "seq": sequence,
                "format": "pcm16",
                "sample_rate": frame.sample_rate,
                "bytes": len(frame.audio),
                "source": frame.source,
            }
        )
        await self.websocket.send_bytes(frame.audio)

    async def send_audio_chunk(
        self,
        *,
        turn_id: str,
        source: Literal["ack", "answer"],
        sample_rate: int,
        audio: bytes,
    ) -> None:
        await self.send_tts_audio(
            TTSAudioRawFrame(
                audio=audio,
                sample_rate=sample_rate,
                turn_id=turn_id,
                source=source,
            )
        )

    async def send_user_started_speaking(self, ts: float) -> None:
        await self.websocket.send_json({"type": "user_started_speaking", "ts": ts})

    async def send_user_stopped_speaking(self, ts: float) -> None:
        await self.websocket.send_json({"type": "user_stopped_speaking", "ts": ts})


class PassthroughEchoPipeline:
    def __init__(self, adapter: ProjectWebSocketTransportAdapter) -> None:
        self.adapter = adapter
        self.turn_id = str(uuid4())
        self.buffered_audio_bytes = 0

    async def process_audio(self, frame: InputAudioRawFrame) -> None:
        self.buffered_audio_bytes += len(frame.audio)
        if self.buffered_audio_bytes < UPLINK_BYTES_PER_SECOND:
            return

        await self.adapter.websocket.send_json(
            {
                "type": "transcript",
                "turn_id": self.turn_id,
                "text": "hello world",
                "is_final": True,
            }
        )
        await self.adapter.send_tts_audio(
            TTSAudioRawFrame(
                audio=frame.audio,
                sample_rate=frame.sample_rate,
                turn_id=self.turn_id,
                source="ack",
            )
        )
        await self.adapter.websocket.send_json({"type": "turn_end", "turn_id": self.turn_id})
        self.turn_id = str(uuid4())
        self.buffered_audio_bytes = 0
