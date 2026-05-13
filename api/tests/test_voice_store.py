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


async def test_voice_store_rejects_expired_resume_window(tmp_path) -> None:
    db = Database(tmp_path / "voice.sqlite")
    await db.bootstrap()
    store = VoiceStore(db)
    session, _ = await store.get_or_create_session("owner-1")
    await db.execute(
        "UPDATE voice_sessions SET last_seen = ? WHERE id = ?",
        ("2000-01-01T00:00:00Z", session.id),
    )

    resumed_session, resumed = await store.get_or_create_session(
        "owner-1",
        session.id,
        resume_window_seconds=300,
    )

    assert resumed is False
    assert resumed_session.id != session.id


async def test_voice_store_rejects_foreign_owner_resume(tmp_path) -> None:
    db = Database(tmp_path / "voice.sqlite")
    await db.bootstrap()
    store = VoiceStore(db)
    session, _ = await store.get_or_create_session("owner-1")

    resumed_session, resumed = await store.get_or_create_session(
        "owner-2",
        session.id,
        resume_window_seconds=300,
    )

    assert resumed is False
    assert resumed_session.id != session.id
    assert resumed_session.owner_id == "owner-2"


async def test_voice_store_get_session_for_owner(tmp_path) -> None:
    db = Database(tmp_path / "voice.sqlite")
    await db.bootstrap()
    store = VoiceStore(db)
    session, _ = await store.get_or_create_session("owner-1")

    found = await store.get_session_for_owner("owner-1", session.id)
    missing = await store.get_session_for_owner("owner-1", "missing-session")
    foreign = await store.get_session_for_owner("owner-2", session.id)

    assert found == session
    assert missing is None
    assert foreign is None


async def test_voice_store_lists_recent_messages_newest_first(tmp_path) -> None:
    db = Database(tmp_path / "voice.sqlite")
    await db.bootstrap()
    store = VoiceStore(db)
    session, _ = await store.get_or_create_session("owner-1")
    await store.append_message(session.id, "user", "one")
    await store.append_message(session.id, "assistant", "two")
    await store.append_message(session.id, "user", "three")

    messages = await store.list_recent_messages(session.id, limit=2)

    assert [message.content for message in messages] == ["three", "two"]


async def test_voice_store_persists_only_completed_turn_messages(tmp_path) -> None:
    db = Database(tmp_path / "voice.sqlite")
    await db.bootstrap()
    store = VoiceStore(db)
    session, _ = await store.get_or_create_session("owner-1")

    await store.start_turn(session.id, "turn-canceled")
    await store.cancel_turn("turn-canceled")
    await store.append_completed_exchange(session.id, "turn-canceled", "hello", "nope")

    await store.start_turn(session.id, "turn-completed")
    await store.mark_first_audio("turn-completed", "ack")
    await store.complete_turn("turn-completed")
    await store.append_completed_exchange(session.id, "turn-completed", "hello", "answer")

    messages = await store.list_messages(session.id)

    assert [(message.role, message.content) for message in messages] == [
        ("user", "hello"),
        ("assistant", "answer"),
    ]


async def test_voice_store_rejects_duplicate_turn_id(tmp_path) -> None:
    db = Database(tmp_path / "voice.sqlite")
    await db.bootstrap()
    store = VoiceStore(db)
    session, _ = await store.get_or_create_session("owner-1")

    await store.start_turn(session.id, "turn-1")

    try:
        await store.start_turn(session.id, "turn-1")
    except ValueError as exc:
        assert "turn_id already exists" in str(exc)
    else:
        raise AssertionError("duplicate turn_id was accepted")
