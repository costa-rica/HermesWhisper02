from app.routes.voice_ws import AudioTurnSegmenter, _runtime_config_from_hello
from app.services.pipeline import build_pipeline
from app.services.session_runtime_config import SessionRuntimeConfig


def test_client_hello_audio_params_apply_to_first_turn() -> None:
    hello = _client_hello()
    hello["audio_params"] = {
        "min_turn_seconds": 0.1,
        "end_silence_seconds": 0.2,
        "max_turn_seconds": 1.0,
    }
    config = _runtime_config_from_hello(hello)
    segmenter = AudioTurnSegmenter(config)
    speech_chunk = (3000).to_bytes(2, byteorder="little", signed=True) * 320
    silence_chunk = b"\x00\x00" * 320

    for _ in range(5):
        assert segmenter.add(speech_chunk) is None

    segment = None
    for _ in range(11):
        segment = segmenter.add(silence_chunk)
        if segment is not None:
            break

    assert segment is not None


async def test_deterministic_mode_still_routes_substantive_text_to_hermes() -> None:
    config = SessionRuntimeConfig(intermediary_mode="deterministic")
    pipeline = build_pipeline(runtime_config=config)

    turn = await pipeline.process_text("please summarize the deployment plan")

    assert turn.answer_text
    assert pipeline.front_llm.intermediary_mode == "deterministic"
    assert pipeline.front_llm.hermes_calls == 1


def _client_hello() -> dict:
    return {
        "type": "client_hello",
        "protocol_version": 1,
        "downlink_format": "pcm16",
        "sample_rate": 16_000,
        "ptt_mode": False,
    }
