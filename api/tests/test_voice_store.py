from app.db import Database
from app.services.voice_store import VoiceStore


async def test_voice_store_creates_session_and_messages(tmp_path) -> None:
    db = Database(tmp_path / "voice.sqlite")
    await db.bootstrap()
    store = VoiceStore(db)

    session, resumed = await store.get_or_create_session("owner-1")
    message = await store.append_message(session.id, "user", "hello")
    messages = await store.list_messages(session.id)
    resumed_session, resumed_again = await store.get_or_create_session("owner-1", session.id)

    assert resumed is False
    assert resumed_again is True
    assert resumed_session.id == session.id
    assert message.content == "hello"
    assert [stored.content for stored in messages] == ["hello"]
