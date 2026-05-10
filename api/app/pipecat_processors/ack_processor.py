import json
import re
from itertools import cycle
from pathlib import Path

from pipecat.frames.frames import TextFrame, TranscriptionFrame

ACK_PHRASES_PATH = Path(__file__).resolve().parents[1] / "services" / "ack_phrases.json"
_TRIVIAL_RE = re.compile(r"^(hi|hey|hello|yo|yes|no|ok|okay|thanks|thank you)[.!?\\s]*$", re.I)


class DeterministicAckProcessor:
    def __init__(self, phrases: tuple[str, ...] | None = None) -> None:
        phrases = phrases or load_ack_phrases()
        self._phrases = cycle(phrases)
        self._last_phrase: str | None = None

    def ack_for(self, frame: TranscriptionFrame) -> TextFrame | None:
        if not frame.finalized or is_trivial_transcript(frame.text):
            return None

        phrase = next(self._phrases)
        if phrase == self._last_phrase:
            phrase = next(self._phrases)
        self._last_phrase = phrase
        text_frame = TextFrame(phrase)
        text_frame.metadata = {"source": "ack"}
        return text_frame


def is_trivial_transcript(text: str) -> bool:
    normalized = text.strip().lower()
    return len(normalized) <= 12 and bool(_TRIVIAL_RE.match(normalized))


def load_ack_phrases(path: Path = ACK_PHRASES_PATH) -> tuple[str, ...]:
    phrases = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(phrases, list) or not all(isinstance(item, str) for item in phrases):
        raise ValueError("ack phrases must be a JSON string list")
    if len(phrases) < 2:
        raise ValueError("ack phrases must contain at least two entries")
    return tuple(phrases)
