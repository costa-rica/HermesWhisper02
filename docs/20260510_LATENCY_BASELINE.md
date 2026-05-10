# HermesWhisper02 latency baseline

1. API phase 5 OpenAI smoke test
   - Status: measured on Mac workstation on 2026-05-10.
   - STT path: `gpt-4o-mini-transcribe` via `/v1/audio/transcriptions` for the smoke test; runtime factory prefers Pipecat `OpenAIRealtimeSTTService`.
   - TTS path: OpenAI `tts-1`, voice `alloy`.
   - Samples: 3 TTS requests and 3 STT requests using generated "hello world" TTS audio.

2. Metrics to record
   - `vad_to_stt_first_token_ms`: HTTP transcription smoke proxy p50 1313 ms, sample max 1617 ms.
   - `front_llm_to_tts_first_chunk_ms`: speech request completion proxy p50 1780 ms, sample max 2200 ms.

3. Notes
   - These phase 5 numbers are provider smoke proxies, not final NFR-1 ack-path measurements. The runtime STT factory is wired for Pipecat `OpenAIRealtimeSTTService`; the smoke test uses the transcription endpoint because it is deterministic and easy to assert in CI-like local runs.
