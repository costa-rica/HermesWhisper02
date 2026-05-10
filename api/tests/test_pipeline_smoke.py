from pathlib import Path

from app.services.pipeline import build_pipeline


async def test_mock_pipeline_smoke_fixture_produces_ack_audio() -> None:
    audio = Path("tests/fixtures/hello_world.wav").read_bytes()
    pipeline = build_pipeline()

    turn = await pipeline.process_audio(audio)

    ack_chunks = [chunk for chunk in turn.chunks if chunk.source == "ack"]
    assert turn.transcript
    assert ack_chunks
    assert ack_chunks[0].audio
