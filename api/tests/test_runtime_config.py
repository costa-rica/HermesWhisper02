import pytest

from app.services.session_runtime_config import SessionRuntimeConfig


def test_runtime_config_clamps_audio_params() -> None:
    config = SessionRuntimeConfig()

    accepted = config.apply_partial(
        {
            "speech_rms_threshold": -1,
            "end_silence_seconds": 99,
            "min_turn_seconds": 0,
            "max_turn_seconds": 0.5,
        }
    )

    assert accepted == {
        "speech_rms_threshold": 0.0001,
        "end_silence_seconds": 5.0,
        "min_turn_seconds": 0.1,
        "max_turn_seconds": 1.0,
    }


def test_runtime_config_rejects_unknown_intermediary_mode() -> None:
    config = SessionRuntimeConfig()

    with pytest.raises(ValueError):
        config.apply_partial({"intermediary_mode": "surprise"})


def test_runtime_config_accepts_intermediary_mode() -> None:
    config = SessionRuntimeConfig()

    accepted = config.apply_partial({"intermediary_mode": "deterministic"})

    assert accepted == {"intermediary_mode": "deterministic"}
    assert config.intermediary_mode == "deterministic"
