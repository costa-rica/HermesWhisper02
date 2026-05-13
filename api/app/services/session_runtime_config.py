from dataclasses import dataclass
from typing import Any, Literal

IntermediaryMode = Literal["deterministic", "llm"]


@dataclass
class SessionRuntimeConfig:
    intermediary_mode: IntermediaryMode = "llm"
    speech_rms_threshold: float = 0.003
    end_silence_seconds: float = 1.1
    min_turn_seconds: float = 0.8
    max_turn_seconds: float = 8.0

    def apply_partial(self, updates: dict[str, Any]) -> dict[str, Any]:
        accepted: dict[str, Any] = {}
        if "intermediary_mode" in updates:
            self.intermediary_mode = _coerce_mode(updates["intermediary_mode"])
            accepted["intermediary_mode"] = self.intermediary_mode

        for field, limits in _AUDIO_LIMITS.items():
            if field in updates:
                value = _clamp_float(updates[field], limits[0], limits[1])
                setattr(self, field, value)
                accepted[field] = value

        if self.max_turn_seconds < self.min_turn_seconds:
            self.max_turn_seconds = self.min_turn_seconds
            accepted["max_turn_seconds"] = self.max_turn_seconds

        return accepted

    def audio_values(self) -> dict[str, float]:
        return {
            "speech_rms_threshold": self.speech_rms_threshold,
            "end_silence_seconds": self.end_silence_seconds,
            "min_turn_seconds": self.min_turn_seconds,
            "max_turn_seconds": self.max_turn_seconds,
        }


_AUDIO_LIMITS = {
    "speech_rms_threshold": (0.0001, 0.1),
    "end_silence_seconds": (0.2, 5.0),
    "min_turn_seconds": (0.1, 5.0),
    "max_turn_seconds": (1.0, 180.0),
}


def _coerce_mode(value: Any) -> IntermediaryMode:
    if value in ("deterministic", "llm"):
        return value
    raise ValueError(f"Unsupported intermediary_mode: {value}")


def _clamp_float(value: Any, lower: float, upper: float) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        parsed = lower
    return min(max(parsed, lower), upper)
