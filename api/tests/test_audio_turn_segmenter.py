from app.routes.voice_ws import AudioTurnSegmenter


def test_audio_turn_segmenter_waits_for_silence_after_speech() -> None:
    segmenter = AudioTurnSegmenter()
    speech_chunk = (3000).to_bytes(2, byteorder="little", signed=True) * 320
    silence_chunk = b"\x00\x00" * 320

    for _ in range(40):
        assert segmenter.add(speech_chunk) is None

    segment = None
    for _ in range(55):
        segment = segmenter.add(silence_chunk)
        if segment is not None:
            break

    assert segment is not None
    assert len(segment) >= len(speech_chunk) * 40


def test_audio_turn_segmenter_ignores_pure_silence() -> None:
    segmenter = AudioTurnSegmenter()
    silence_chunk = b"\x00\x00" * 320

    for _ in range(100):
        assert segmenter.add(silence_chunk) is None
