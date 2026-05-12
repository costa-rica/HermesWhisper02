from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

RunEnvironment = Literal["development", "testing", "production"]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=True,
    )

    NAME_APP: str = Field(...)
    RUN_ENVIRONMENT: RunEnvironment = Field(...)
    PATH_TO_LOGS: Path | None = None
    LOG_MAX_SIZE_IN_MB: int = 3
    LOG_MAX_FILES: int = 3

    API_HOST: str = "127.0.0.1"
    API_PORT: int = 8765
    PUBLIC_BASE_URL: str = "https://api.hermes-whisper.dashanddata.com"

    FRONT_LLM_PROVIDER: Literal["openai", "ollama", "anthropic"] = "openai"
    FRONT_LLM_MODEL: str = "gpt-4o-mini"
    OPENAI_API_KEY: SecretStr | None = None
    ANTHROPIC_API_KEY: SecretStr | None = None
    OLLAMA_BASE_URL: str = "http://127.0.0.1:11434"

    STT_PROVIDER: Literal["mock", "openai"] = "mock"
    STT_MODEL: str = "gpt-4o-mini-transcribe"
    TTS_PROVIDER: Literal["mock", "openai"] = "mock"
    TTS_MODEL: str = "tts-1"
    TTS_VOICE: str = "alloy"

    HERMES_BASE_URL: str = "http://127.0.0.1:8642"
    HERMES_CHAT_PATH: str = "/chat"
    HERMES_MOCK: bool = True

    DB_PATH: Path = Path("./var/voice_store.sqlite")
    JWT_SECRET: SecretStr = Field(...)
    TOKEN_TTL_SECONDS: int = 2_592_000
    SESSION_RESUME_WINDOW_SEC: int = 300

    EMAIL_HOST: str = "smtp.gmail.com"
    EMAIL_PORT: int = 587
    EMAIL_USER: str | None = None
    EMAIL_PASSWORD: SecretStr | None = None
    EMAIL_FROM: str = "HermesWhisper <nrodrig1@gmail.com>"
    EMAIL_DEV_CONSOLE_ONLY: bool = True

    WS_QUERY_TOKEN_FALLBACK_ENABLED: bool = False

    @field_validator("NAME_APP")
    @classmethod
    def _non_empty_name(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("NAME_APP must not be empty")
        return value

    @field_validator("PATH_TO_LOGS")
    @classmethod
    def _logs_required_outside_dev(cls, value: Path | None, info) -> Path | None:
        env = info.data.get("RUN_ENVIRONMENT")
        if env in {"testing", "production"} and value is None:
            raise ValueError("PATH_TO_LOGS is required in testing and production")
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
