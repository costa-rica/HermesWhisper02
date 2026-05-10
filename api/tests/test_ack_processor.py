from datetime import UTC, datetime

from pipecat.frames.frames import TranscriptionFrame

from app.pipecat_processors.ack_processor import (
    DeterministicAckProcessor,
    is_trivial_transcript,
    load_ack_phrases,
)


def test_trivial_classifier() -> None:
    assert is_trivial_transcript("hi")
    assert is_trivial_transcript("thank you")
    assert not is_trivial_transcript("please summarize the deployment plan")


def test_phrase_rotation_never_repeats_consecutively() -> None:
    processor = DeterministicAckProcessor(("One.", "Two."))
    frame = _final_transcript("please summarize the deployment plan")

    first = processor.ack_for(frame)
    second = processor.ack_for(frame)

    assert first is not None
    assert second is not None
    assert first.text != second.text


def test_ack_frame_carries_source_metadata() -> None:
    processor = DeterministicAckProcessor(("One.", "Two."))

    ack = processor.ack_for(_final_transcript("please summarize the deployment plan"))

    assert ack is not None
    assert ack.metadata == {"source": "ack"}


def test_load_ack_phrases_from_json() -> None:
    phrases = load_ack_phrases()

    assert "Got it." in phrases


def _final_transcript(text: str) -> TranscriptionFrame:
    return TranscriptionFrame(
        text=text,
        user_id="test-user",
        timestamp=datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        finalized=True,
    )
