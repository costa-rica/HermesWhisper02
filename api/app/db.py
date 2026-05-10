import asyncio
from collections.abc import AsyncIterator, Iterable, Sequence
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import aiosqlite

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS email_codes (
    email TEXT PRIMARY KEY,
    code TEXT NOT NULL,
    expires_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS voice_sessions (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL,
    conversation_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    last_seen TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS voice_messages (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('user', 'assistant', 'system')),
    content TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY(session_id) REFERENCES voice_sessions(id)
);

CREATE TABLE IF NOT EXISTS turn_state (
    turn_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    source TEXT NOT NULL CHECK(source IN ('ack','answer')),
    status TEXT NOT NULL CHECK(status IN ('started','completed','canceled','failed')),
    ts_started TEXT NOT NULL,
    ts_first_audio TEXT,
    ts_final TEXT,
    ts_canceled TEXT,
    FOREIGN KEY(session_id) REFERENCES voice_sessions(id)
);
"""


class Database:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._write_lock = asyncio.Lock()

    async def bootstrap(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        async with self._connect() as db:
            await db.executescript(SCHEMA)
            await db.commit()

    @asynccontextmanager
    async def _connect(self) -> AsyncIterator[aiosqlite.Connection]:
        db = await aiosqlite.connect(self.path)
        db.row_factory = aiosqlite.Row
        await db.execute("PRAGMA journal_mode=WAL")
        await db.execute("PRAGMA busy_timeout=5000")
        await db.execute("PRAGMA synchronous=NORMAL")
        try:
            yield db
        finally:
            await db.close()

    async def fetch_one(
        self,
        sql: str,
        params: Sequence[Any] | None = None,
    ) -> aiosqlite.Row | None:
        async with self._connect() as db:
            cursor = await db.execute(sql, params or ())
            try:
                return await cursor.fetchone()
            finally:
                await cursor.close()

    async def fetch_all(
        self,
        sql: str,
        params: Sequence[Any] | None = None,
    ) -> list[aiosqlite.Row]:
        async with self._connect() as db:
            cursor = await db.execute(sql, params or ())
            try:
                return await cursor.fetchall()
            finally:
                await cursor.close()

    async def execute(
        self,
        sql: str,
        params: Sequence[Any] | None = None,
    ) -> None:
        async with self._write_lock, self._connect() as db:
            await db.execute(sql, params or ())
            await db.commit()

    async def executemany(self, sql: str, rows: Iterable[Sequence[Any]]) -> None:
        async with self._write_lock, self._connect() as db:
            await db.executemany(sql, rows)
            await db.commit()
