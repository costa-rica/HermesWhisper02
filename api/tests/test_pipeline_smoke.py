from datetime import UTC, datetime
from pathlib import Path

from pipecat.frames.frames import TranscriptionFrame

from app.pipecat_processors.mocks import MockTTS
from app.services.pipeline import build_pipeline


async def test_mock_pipeline_smoke_fixture_produces_ack_audio() -> None:
    audio = Path("tests/fixtures/hello_world.wav").read_bytes()
    pipeline = build_pipeline()

    turn = await pipeline.process_audio(audio)

    ack_chunks = [chunk for chunk in turn.chunks if chunk.source == "ack"]
    assert turn.transcript
    assert ack_chunks
    assert ack_chunks[0].audio


async def test_pipeline_skips_empty_transcripts() -> None:
    class EmptySTT:
        async def transcribe(self, _audio: bytes, sample_rate: int = 16_000) -> TranscriptionFrame:
            return TranscriptionFrame(
                text=" ",
                user_id="local-test-user",
                timestamp=datetime.now(UTC).isoformat().replace("+00:00", "Z"),
                finalized=True,
            )

    pipeline = build_pipeline(stt=EmptySTT(), tts=MockTTS())

    turn = await pipeline.process_audio(b"\0" * 640)

    assert turn.transcript == ""
    assert turn.answer_text == ""
    assert turn.chunks == []
