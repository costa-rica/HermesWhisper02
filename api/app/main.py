import sys
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from loguru import logger
from pydantic import ValidationError

from app.config import Settings, get_settings
from app.errors import install_error_handlers
from app.routes import health


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    settings = get_settings()
    logger.info("{} starting", settings.NAME_APP)
    yield
    logger.info("{} stopping", settings.NAME_APP)


def create_app() -> FastAPI:
    settings = _load_settings_or_exit()

    from app.logging_config import configure_logging

    configure_logging(settings)

    app = FastAPI(
        title="HermesWhisper02 API",
        version="0.1.0",
        lifespan=lifespan,
    )
    install_error_handlers(app)
    app.include_router(health.router)
    return app


def _load_settings_or_exit() -> Settings:
    try:
        return get_settings()
    except ValidationError as exc:
        missing_names = []
        for error in exc.errors():
            location = error.get("loc", ())
            if location:
                missing_names.append(str(location[0]))
        names = ", ".join(missing_names) or "configuration"
        logger.remove()
        logger.add(
            sink=lambda message: print(message, end="", file=sys.stderr),
            level="ERROR",
            format="{level} | {message}",
        )
        logger.error("Fatal configuration error: missing or invalid {}", names)
        raise SystemExit(1) from exc


app = create_app()
