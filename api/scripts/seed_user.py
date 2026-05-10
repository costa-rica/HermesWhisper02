from __future__ import annotations

import asyncio
import sys
from getpass import getpass
from pathlib import Path
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import get_settings
from app.db import Database
from app.models import utc_now_iso
from app.services.passwords import hash_password

SEED_EMAIL = "nrodrig1@gmail.com"


async def main() -> None:
    settings = get_settings()
    db = Database(settings.DB_PATH)
    await db.bootstrap()

    password = getpass(f"Password for {SEED_EMAIL}: ")
    confirm = getpass("Confirm password: ")
    if password != confirm:
        raise SystemExit("Passwords did not match")

    await db.execute(
        """
        INSERT INTO users (id, email, password_hash, created_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(email) DO UPDATE SET password_hash = excluded.password_hash
        """,
        (str(uuid4()), SEED_EMAIL, hash_password(password), utc_now_iso()),
    )
    print(f"Seeded {SEED_EMAIL}")


if __name__ == "__main__":
    asyncio.run(main())
