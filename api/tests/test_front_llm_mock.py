from app.services.front_llm import FrontAnswerProcessor
from app.services.pipeline import build_pipeline


async def test_non_trivial_turn_produces_ack_before_answer() -> None:
    pipeline = build_pipeline()

    turn = await pipeline.process_text("please summarize the deployment plan")

    assert [chunk.source for chunk in turn.chunks] == ["ack", "answer"]
    assert turn.chunks[0].audio
    assert turn.chunks[1].audio
    assert pipeline.front_llm.hermes_calls == 1


async def test_trivial_turn_has_no_ack_or_hermes_call() -> None:
    pipeline = build_pipeline()

    turn = await pipeline.process_text("hi there")

    assert [chunk.source for chunk in turn.chunks] == ["answer"]
    assert pipeline.front_llm.hermes_calls == 0


async def test_front_answer_processor_calls_hermes_mock() -> None:
    processor = FrontAnswerProcessor(conversation_id="conversation-1")
    pipeline = build_pipeline()
    transcript = pipeline.stt.transcribe(b"")
    transcript.text = "what changed today"

    answer = await processor.answer(transcript)

    assert "Hermes mock response" in answer.text
    assert answer.metadata == {"source": "answer"}
