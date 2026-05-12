import smtplib
from email.message import EmailMessage

from loguru import logger

from app.config import Settings


class Mailer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    async def send_login_code(self, email: str, code: str) -> None:
        if self.settings.RUN_ENVIRONMENT == "development" and self.settings.EMAIL_DEV_CONSOLE_ONLY:
            logger.info(
                "Email delivery skipped for login code email={} reason=development_console_only",
                email,
            )
            logger.debug("Development login code generated for {}: {}", email, code)
            return

        if not self.settings.EMAIL_USER or not self.settings.EMAIL_PASSWORD:
            logger.error(
                "Email delivery cannot start for login code email={} "
                "host={} port={} reason=missing_credentials",
                email,
                self.settings.EMAIL_HOST,
                self.settings.EMAIL_PORT,
            )
            raise RuntimeError("EMAIL_USER and EMAIL_PASSWORD are required to send mail")

        logger.info(
            "Email delivery starting for login code email={} host={} port={} from={} user={}",
            email,
            self.settings.EMAIL_HOST,
            self.settings.EMAIL_PORT,
            self.settings.EMAIL_FROM,
            self.settings.EMAIL_USER,
        )
        message = EmailMessage()
        message["Subject"] = "Your HermesWhisper login code"
        message["From"] = self.settings.EMAIL_FROM
        message["To"] = email
        message.set_content(f"Your HermesWhisper login code is {code}. It expires in 10 minutes.")

        password = self.settings.EMAIL_PASSWORD.get_secret_value()
        try:
            with smtplib.SMTP(self.settings.EMAIL_HOST, self.settings.EMAIL_PORT) as smtp:
                logger.info(
                    "Email delivery connected for login code email={} host={} port={}",
                    email,
                    self.settings.EMAIL_HOST,
                    self.settings.EMAIL_PORT,
                )
                smtp.starttls()
                logger.info("Email delivery TLS started for login code email={}", email)
                smtp.login(self.settings.EMAIL_USER, password)
                logger.info("Email delivery SMTP login succeeded for login code email={}", email)
                refused = smtp.send_message(message)
        except Exception:
            logger.exception(
                "Email delivery failed for login code email={} host={} port={} from={} user={}",
                email,
                self.settings.EMAIL_HOST,
                self.settings.EMAIL_PORT,
                self.settings.EMAIL_FROM,
                self.settings.EMAIL_USER,
            )
            raise

        if refused:
            logger.error(
                "Email delivery completed with refused recipients "
                "for login code email={} refused={}",
                email,
                sorted(refused.keys()),
            )
            raise RuntimeError("SMTP refused one or more recipients")

        logger.info("Email delivery sent for login code email={}", email)
