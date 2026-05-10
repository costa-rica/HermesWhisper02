import os
from io import BytesIO
from time import perf_counter

import pytest
from openai import OpenAI


@pytest.mark.integration
@pytest.mark.skipif(
    not os.getenv("OPENAI_API_KEY") or os.getenv("RUN_OPENAI_SMOKE") != "1",
    reason="OPENAI_API_KEY and RUN_OPENAI_SMOKE=1 are required",
)
def test_openai_tts_then_stt_smoke() -> None:
    client = OpenAI(api_key=os.environ["OPENAI_API_KEY"])

    tts_start = perf_counter()
    speech = client.audio.speech.create(
        model=os.getenv("TTS_MODEL", "tts-1"),
        voice=os.getenv("TTS_VOICE", "alloy"),
        input="hello world",
        response_format="wav",
    )
    audio = speech.read()
    first_audio_ms = (perf_counter() - tts_start) * 1000

    stt_start = perf_counter()
    transcript = client.audio.transcriptions.create(
        model=os.getenv("STT_MODEL", "gpt-4o-mini-transcribe"),
        file=("hello_world.wav", BytesIO(audio), "audio/wav"),
    )
    stt_ms = (perf_counter() - stt_start) * 1000

    assert audio
    assert "hello" in transcript.text.lower()
    assert first_audio_ms > 0
    assert stt_ms > 0
