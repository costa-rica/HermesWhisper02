import smtplib
from email.message import EmailMessage

from loguru import logger

from app.config import Settings


class Mailer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    async def send_login_code(self, email: str, code: str) -> None:
        if self.settings.RUN_ENVIRONMENT == "development" and self.settings.EMAIL_DEV_CONSOLE_ONLY:
            logger.debug("Development login code generated for {}: {}", email, code)
            return

        if not self.settings.EMAIL_USER or not self.settings.EMAIL_PASSWORD:
            raise RuntimeError("EMAIL_USER and EMAIL_PASSWORD are required to send mail")

        message = EmailMessage()
        message["Subject"] = "Your HermesWhisper login code"
        message["From"] = self.settings.EMAIL_FROM
        message["To"] = email
        message.set_content(f"Your HermesWhisper login code is {code}. It expires in 10 minutes.")

        password = self.settings.EMAIL_PASSWORD.get_secret_value()
        with smtplib.SMTP(self.settings.EMAIL_HOST, self.settings.EMAIL_PORT) as smtp:
            smtp.starttls()
            smtp.login(self.settings.EMAIL_USER, password)
            smtp.send_message(message)
