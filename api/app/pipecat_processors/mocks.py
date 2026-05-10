import math
from datetime import UTC, datetime

from pipecat.frames.frames import TextFrame, TranscriptionFrame, TTSAudioRawFrame


class MockSTT:
    def transcribe(self, _audio: bytes) -> TranscriptionFrame:
        return TranscriptionFrame(
            text="hello world from the mock pipeline",
            user_id="local-test-user",
            timestamp=datetime.now(UTC).isoformat().replace("+00:00", "Z"),
            finalized=True,
        )


class MockFrontLLM:
    def answer(self, transcript: TranscriptionFrame) -> TextFrame:
        text_frame = TextFrame(f"Mock Hermes answer for: {transcript.text}")
        text_frame.metadata = {"source": "answer"}
        return text_frame


class MockTTS:
    def synthesize(self, frame: TextFrame, turn_id: str) -> TTSAudioRawFrame:
        sample_rate = 24_000
        duration_seconds = 0.2
        samples = int(sample_rate * duration_seconds)
        pcm = bytearray()
        for index in range(samples):
            # A tiny nonzero tone keeps tests deterministic without requiring a real TTS call.
            value = int(math.sin(index / 12) * 200)
            pcm.extend(value.to_bytes(2, byteorder="little", signed=True))
        audio_frame = TTSAudioRawFrame(bytes(pcm), sample_rate=sample_rate, num_channels=1)
        audio_frame.metadata = {"source": getattr(frame, "metadata", {}).get("source", "answer")}
        audio_frame.turn_id = turn_id
        return audio_frame
