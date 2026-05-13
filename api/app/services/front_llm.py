from collections.abc import Awaitable, Callable
from dataclasses import dataclass

from loguru import logger
from pipecat.frames.frames import TextFrame, TranscriptionFrame
from pipecat.services.openai.llm import OpenAILLMService

from app.config import Settings
from app.errors import APIError
from app.pipecat_processors.ack_processor import is_trivial_transcript
from app.services.hermes import ProgressEvent, collect_hermes_text_with_progress

SYSTEM_PROMPT = (
    "You are the answer voice of an AI agent. A separate processor handles short "
    "acknowledgments; do not emit got-it/checking prefaces. For non-trivial requests, "
    "call the call_hermes tool and relay its answer. For small talk or trivial "
    "clarifications, answer directly without the tool. Be concise."
)


def create_front_llm_service(settings: Settings) -> OpenAILLMService:
    if settings.FRONT_LLM_PROVIDER != "openai":
        raise APIError(
            code="VALIDATION_ERROR", message="Unsupported front LLM provider", status=400
        )
    if settings.OPENAI_API_KEY is None:
        raise APIError(code="SERVICE_UNAVAILABLE", message="OPENAI_API_KEY is required", status=503)
    return OpenAILLMService(
        api_key=settings.OPENAI_API_KEY.get_secret_value(),
        model=settings.FRONT_LLM_MODEL,
    )


@dataclass
class FrontAnswerProcessor:
    conversation_id: str
    hermes_calls: int = 0

    async def answer(
        self,
        transcript: TranscriptionFrame,
        *,
        turn_id: str | None = None,
        progress_handler: Callable[[str, str, str], Awaitable[None]] | None = None,
    ) -> TextFrame:
        if is_trivial_transcript(transcript.text):
            text_frame = TextFrame("Hi. I am here.")
        else:
            self.hermes_calls += 1
            try:
                answer_text = await collect_hermes_text_with_progress(
                    transcript.text,
                    self.conversation_id,
                    progress_handler=(
                        _progress_forwarder(turn_id, progress_handler)
                        if turn_id is not None and progress_handler is not None
                        else None
                    ),
                )
            except Exception as exc:
                logger.exception(
                    "call_hermes_failed conversation_id={} error_type={} error={}",
                    self.conversation_id,
                    type(exc).__name__,
                    exc,
                )
                answer_text = "I could not reach Hermes right now."
            if not answer_text.strip():
                logger.warning(
                    "call_hermes_empty_response conversation_id={}", self.conversation_id
                )
                answer_text = "Hermes returned an empty response."
            text_frame = TextFrame(answer_text)
        text_frame.metadata = {"source": "answer"}
        return text_frame


def _progress_forwarder(
    turn_id: str,
    progress_handler: Callable[[str, str, str], Awaitable[None]],
) -> Callable[[ProgressEvent], Awaitable[None]]:
    async def forward(event: ProgressEvent) -> None:
        await progress_handler(turn_id, event.kind, event.text)

    return forward
