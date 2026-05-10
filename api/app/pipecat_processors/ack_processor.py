from itertools import cycle

from pipecat.frames.frames import TextFrame, TranscriptionFrame

ACK_PHRASES = (
    "Got it.",
    "I'm checking.",
    "On it.",
    "Let me look.",
)


class DeterministicAckProcessor:
    def __init__(self, phrases: tuple[str, ...] = ACK_PHRASES) -> None:
        self._phrases = cycle(phrases)
        self._last_phrase: str | None = None

    def ack_for(self, frame: TranscriptionFrame) -> TextFrame | None:
        if not frame.finalized or _is_trivial(frame.text):
            return None

        phrase = next(self._phrases)
        if phrase == self._last_phrase:
            phrase = next(self._phrases)
        self._last_phrase = phrase
        text_frame = TextFrame(phrase)
        text_frame.metadata = {"source": "ack"}
        return text_frame


def _is_trivial(text: str) -> bool:
    normalized = text.strip().lower()
    return len(normalized) <= 2 or normalized in {"hi", "hey", "hello", "yes", "no", "ok"}
