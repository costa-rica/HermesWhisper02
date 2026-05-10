import sys
from pathlib import Path
from types import TracebackType

from loguru import logger

from app.config import Settings

DEV_FORMAT = "{time:HH:mm:ss.SSS} | {level} | {module}:{function}:{line} | {message}"
FILE_FORMAT = "{time:YYYY-MM-DD HH:mm:ss.SSS} | {level} | {module}:{function}:{line} | {message}"


def configure_logging(settings: Settings) -> None:
    logger.remove()

    if settings.RUN_ENVIRONMENT == "development":
        logger.add(
            sys.stderr,
            level="DEBUG",
            format=DEV_FORMAT,
            backtrace=True,
            diagnose=True,
            enqueue=False,
        )
    else:
        log_dir = settings.PATH_TO_LOGS or Path("./logs")
        log_dir.mkdir(parents=True, exist_ok=True)
        log_path = log_dir / f"{settings.NAME_APP}.log"
        rotation = f"{settings.LOG_MAX_SIZE_IN_MB} MB"
        logger.add(
            log_path,
            level="INFO",
            format=FILE_FORMAT,
            rotation=rotation,
            retention=settings.LOG_MAX_FILES,
            backtrace=True,
            diagnose=True,
            enqueue=True,
        )
        if settings.RUN_ENVIRONMENT == "testing":
            logger.add(
                sys.stderr,
                level="INFO",
                format=FILE_FORMAT,
                backtrace=True,
                diagnose=True,
                enqueue=True,
            )

    sys.excepthook = _log_uncaught_exception


def _log_uncaught_exception(
    exc_type: type[BaseException],
    exc: BaseException,
    traceback: TracebackType | None,
) -> None:
    if issubclass(exc_type, KeyboardInterrupt):
        sys.__excepthook__(exc_type, exc, traceback)
        return
    logger.opt(exception=(exc_type, exc, traceback)).critical("Uncaught exception")
