import os
import sys
from pathlib import Path

import httpx
from loguru import logger


def main() -> int:
    name_app = os.getenv("NAME_APP", "hermes-whisper-02-api")
    public_base_url = os.getenv("PUBLIC_BASE_URL", "https://api.hermes-whisper.dashanddata.com")
    path_to_logs = Path(os.getenv("PATH_TO_LOGS", "/var/log/hermes-whisper-02"))
    timeout = float(os.getenv("HEALTHCHECK_TIMEOUT_SECONDS", "10"))

    path_to_logs.mkdir(parents=True, exist_ok=True)
    logger.remove()
    logger.add(
        path_to_logs / f"{name_app}-healthcheck.log",
        rotation="3 MB",
        retention=3,
        enqueue=True,
    )

    health_url = f"{public_base_url.rstrip('/')}/api/health"
    try:
        response = httpx.get(health_url, timeout=timeout)
        response.raise_for_status()
    except Exception as exc:
        logger.error("healthcheck_failed url={} error={}", health_url, exc)
        return 1

    logger.info("healthcheck_ok url={} status={}", health_url, response.status_code)
    return 0


if __name__ == "__main__":
    sys.exit(main())
