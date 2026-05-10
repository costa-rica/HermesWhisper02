from dataclasses import dataclass
from time import perf_counter
from uuid import uuid4

from loguru import logger

from app.pipecat_processors.ack_processor import DeterministicAckProcessor
from app.pipecat_processors.mocks import MockFrontLLM, MockSTT, MockTTS


@dataclass(frozen=True)
class PipelineAudioChunk:
    turn_id: str
    source: str
    sample_rate: int
    audio: bytes


@dataclass(frozen=True)
class PipelineTurn:
    turn_id: str
    transcript: str
    chunks: list[PipelineAudioChunk]


class MockVoicePipeline:
    def __init__(self) -> None:
        self.stt = MockSTT()
        self.ack = DeterministicAckProcessor()
        self.front_llm = MockFrontLLM()
        self.tts = MockTTS()

    async def process_audio(self, audio: bytes) -> PipelineTurn:
        turn_id = str(uuid4())
        vad_done = perf_counter()
        transcript_frame = self.stt.transcribe(audio)
        stt_done = perf_counter()
        logger.info("turn_id={} vad_to_stt_ms={:.2f}", turn_id, (stt_done - vad_done) * 1000)

        chunks: list[PipelineAudioChunk] = []
        ack_text = self.ack.ack_for(transcript_frame)
        if ack_text is not None:
            ack_audio = self.tts.synthesize(ack_text, turn_id)
            chunks.append(
                PipelineAudioChunk(
                    turn_id=turn_id,
                    source="ack",
                    sample_rate=ack_audio.sample_rate,
                    audio=ack_audio.audio,
                )
            )

        llm_start = perf_counter()
        answer_text = self.front_llm.answer(transcript_frame)
        llm_done = perf_counter()
        logger.info("turn_id={} stt_to_llm_ms={:.2f}", turn_id, (llm_done - stt_done) * 1000)

        answer_audio = self.tts.synthesize(answer_text, turn_id)
        tts_done = perf_counter()
        logger.info("turn_id={} llm_to_tts_ms={:.2f}", turn_id, (tts_done - llm_start) * 1000)
        chunks.append(
            PipelineAudioChunk(
                turn_id=turn_id,
                source="answer",
                sample_rate=answer_audio.sample_rate,
                audio=answer_audio.audio,
            )
        )
        return PipelineTurn(turn_id=turn_id, transcript=transcript_frame.text, chunks=chunks)


def build_pipeline() -> MockVoicePipeline:
    return MockVoicePipeline()
