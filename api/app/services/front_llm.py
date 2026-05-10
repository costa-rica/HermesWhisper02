from dataclasses import dataclass

from pipecat.frames.frames import TextFrame, TranscriptionFrame
from pipecat.services.openai.llm import OpenAILLMService

from app.config import Settings
from app.errors import APIError
from app.pipecat_processors.ack_processor import is_trivial_transcript
from app.services.hermes import collect_hermes_text

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

    async def answer(self, transcript: TranscriptionFrame) -> TextFrame:
        if is_trivial_transcript(transcript.text):
            text_frame = TextFrame("Hi. I am here.")
        else:
            self.hermes_calls += 1
            text_frame = TextFrame(await collect_hermes_text(transcript.text, self.conversation_id))
        text_frame.metadata = {"source": "answer"}
        return text_frame
