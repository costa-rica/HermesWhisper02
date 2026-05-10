from loguru import logger

from app.config import Settings
from app.services.mailer import Mailer


async def test_mailer_development_console_mode_does_not_send(tmp_path, capsys) -> None:
    logger.remove()
    logger.add(lambda message: print(message, end=""))
    settings = Settings(
        NAME_APP="hermes-whisper-02-api-test",
        RUN_ENVIRONMENT="development",
        JWT_SECRET="secret",
        DB_PATH=tmp_path / "test.sqlite",
    )

    await Mailer(settings).send_login_code("nrodrig1@gmail.com", "123456")

    captured = capsys.readouterr()
    assert "Development login code generated" in captured.out
