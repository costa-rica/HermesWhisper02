from dataclasses import dataclass
from time import perf_counter
from uuid import uuid4

from loguru import logger

from app.config import Settings, get_settings
from app.models import VoiceMessage
from app.pipecat_processors.ack_processor import DeterministicAckProcessor
from app.services.front_llm import FrontAnswerProcessor
from app.services.stt import PipelineSTT, create_pipeline_stt
from app.services.tts import PipelineTTS, create_pipeline_tts


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
    answer_text: str
    chunks: list[PipelineAudioChunk]


class MockVoicePipeline:
    def __init__(
        self,
        conversation_id: str | None = None,
        context_messages: list[VoiceMessage] | None = None,
        settings: Settings | None = None,
        stt: PipelineSTT | None = None,
        tts: PipelineTTS | None = None,
    ) -> None:
        settings = settings or get_settings()
        self.stt = stt or create_pipeline_stt(settings)
        self.ack = DeterministicAckProcessor()
        self.front_llm = FrontAnswerProcessor(conversation_id=conversation_id or str(uuid4()))
        self.tts = tts or create_pipeline_tts(settings)
        self.context_messages = context_messages or []

    async def process_audio(self, audio: bytes, sample_rate: int = 16_000) -> PipelineTurn:
        vad_done = perf_counter()
        transcript_frame = await self.stt.transcribe(audio, sample_rate)
        return await self.process_transcript(transcript_frame, vad_done)

    async def process_text(self, text: str) -> PipelineTurn:
        transcript_frame = await self.stt.transcribe(b"")
        transcript_frame.text = text
        return await self.process_transcript(transcript_frame, perf_counter())

    async def process_transcript(
        self, transcript_frame, vad_done: float | None = None
    ) -> PipelineTurn:
        turn_id = str(uuid4())
        vad_done = vad_done or perf_counter()
        stt_done = perf_counter()
        logger.info("turn_id={} vad_to_stt_ms={:.2f}", turn_id, (stt_done - vad_done) * 1000)
        transcript_text = transcript_frame.text.strip()
        if not transcript_text:
            logger.info("turn_id={} empty_transcript_skipped", turn_id)
            return PipelineTurn(turn_id=turn_id, transcript="", answer_text="", chunks=[])
        transcript_frame.text = transcript_text

        chunks: list[PipelineAudioChunk] = []
        ack_text = self.ack.ack_for(transcript_frame)
        if ack_text is not None:
            ack_audio = await self.tts.synthesize(ack_text, turn_id)
            chunks.append(
                PipelineAudioChunk(
                    turn_id=turn_id,
                    source="ack",
                    sample_rate=ack_audio.sample_rate,
                    audio=ack_audio.audio,
                )
            )

        llm_start = perf_counter()
        answer_text = await self.front_llm.answer(transcript_frame)
        llm_done = perf_counter()
        logger.info("turn_id={} stt_to_llm_ms={:.2f}", turn_id, (llm_done - stt_done) * 1000)

        answer_audio = await self.tts.synthesize(answer_text, turn_id)
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
        return PipelineTurn(
            turn_id=turn_id,
            transcript=transcript_frame.text,
            answer_text=answer_text.text,
            chunks=chunks,
        )


def build_pipeline(
    conversation_id: str | None = None,
    context_messages: list[VoiceMessage] | None = None,
    settings: Settings | None = None,
    stt: PipelineSTT | None = None,
    tts: PipelineTTS | None = None,
) -> MockVoicePipeline:
    return MockVoicePipeline(
        conversation_id=conversation_id,
        context_messages=context_messages,
        settings=settings,
        stt=stt,
        tts=tts,
    )
