# HermesWhisper02 API plan assessment, Codex

Date: 2026-05-10

Assessed file: `docs/20260510_PLAN_API_V01.md`

Summary:

The API plan is generally coherent and has a good phased shape. I do not see a fatal architectural blocker that makes the API impossible to build. The biggest success risk is latency and Pipecat integration shape: the plan currently combines a custom WebSocket protocol, OpenAI Whisper-style segmented STT, LLM-driven acknowledgments, and a later ParallelPipeline refactor. That can work, but it leaves the most latency-sensitive and least-proven pieces until the middle of the project. The best alternative approach is to add an early protocol/transport spike and make the acknowledgment path deterministic and independent of the main front LLM/tool call.

1. Fatal or near-fatal issues

- No confirmed fatal issue in the overall API plan.
- The closest near-fatal issue is the assumption that OpenAI Whisper-style STT will meet NFR-1. The plan names OpenAI Whisper and `WhisperSTTService`, but current Pipecat OpenAI STT docs distinguish segmented HTTP STT from realtime WebSocket STT. Segmented STT only returns final transcriptions after VAD commits a speech segment, which makes the 800 ms p50 ack budget much harder.
- The plan should not enter full implementation with `WhisperSTTService` as a concrete dependency name. Use the current Pipecat class names and extras after pinning the version. As of current docs, Pipecat shows `OpenAISTTService` and `OpenAIRealtimeSTTService`, installed with `pipecat-ai[openai]`.

2. Highest leverage alternative approach

- Add a Phase 3.5 transport/protocol spike before mocked Pipecat pipeline work.
- Goal: prove the custom JSON prelude plus binary audio protocol can be implemented as a Pipecat transport serializer or adapter, not just as a hand-written FastAPI WebSocket loop.
- Acceptance:
  1. `client_hello` is handled outside or inside the transport adapter consistently.
  2. Uplink binary frames become Pipecat audio frames with the expected sample rate and channels.
  3. `TTSAudioRawFrame` output becomes `audio_chunk` JSON followed by one binary WebSocket message.
  4. `user_started_speaking`, cancellation, and close/error frames flow through the same adapter.
- Reason: Pipecat already provides FastAPI/WebSocket transports and expects transport `input()` and `output()` processors in the pipeline. The project protocol is intentionally custom, so the adapter is the seam most likely to cause hidden rework if delayed until Phase 4.

3. Latency risk: STT choice

- Phase 5 should prefer streaming STT from the start if NFR-1 is real.
- Better options:
  1. Use `OpenAIRealtimeSTTService` with local Pipecat VAD if staying within OpenAI.
  2. Use Deepgram streaming if provider choice is still flexible, matching the earlier requirement-issues recommendation.
  3. Keep segmented OpenAI HTTP STT only as a fallback profile, not the main NFR path.
- Update the plan wording from “OpenAI Whisper STT” to “OpenAI realtime transcription or another streaming STT provider” unless the team intentionally accepts a likely latency miss.

4. Latency risk: acknowledgment generation

- The current plan asks the front LLM to emit an acknowledgment and then call Hermes. This is fragile because tool-call behavior, streaming text emission, and TTS start timing depend on provider and Pipecat service details.
- A safer design is a dedicated ack processor:
  1. After finalized transcript, generate a short deterministic or template-varied acknowledgment immediately.
  2. Send that text to TTS without waiting for the front LLM.
  3. Start the Hermes/front-LLM answer path at the same time.
  4. Let the front LLM handle routing, small talk, and final answer wording, but not the first audible ack.
- This greatly increases the chance of meeting NFR-1 because the first audio byte no longer waits on LLM policy compliance.

5. ParallelPipeline phase risk

- Phase 8 is useful, but `ParallelPipeline` should not be the only path to low ack latency.
- A deterministic ack processor plus concurrent Hermes task can meet the user experience goal with less branch-merging complexity.
- If `ParallelPipeline` is used, add explicit merge rules:
  1. `ack` audio may start first.
  2. `answer` audio must not interleave at the PCM message level with an incomplete `ack` chunk.
  3. `turn_id`, `source`, and `seq` are monotonic per source.
  4. Barge-in cancellation must cancel TTS, LLM generation, and Hermes streaming together.

6. SQLite concurrency risk

- The plan says “SQLite connection at DB_PATH” but does not name an async/concurrency strategy.
- Add:
  1. `aiosqlite` or a small sync DB executor wrapper.
  2. WAL mode.
  3. `busy_timeout`.
  4. One connection per request/task or a clearly serialized write path.
- Reason: four concurrent voice sessions plus auth writes can otherwise produce intermittent “database is locked” failures.

7. WebSocket auth and reverse proxy risk

- The API plan should explicitly require Nginx to forward WebSocket upgrade headers and the `Authorization` header.
- The query-token fallback should stay disabled in production unless there is a proven iOS/proxy limitation.
- If query-token fallback is enabled, require short-lived one-time WS tickets instead of the long-lived bearer token in the URL.

8. Persistence and resume risk

- Phase 7 persists finalized assistant turns, but the plan should define what “finalized” means when playback is canceled by barge-in.
- Add a turn state table or fields for:
  1. `turn_id`
  2. `status`: `started`, `completed`, `canceled`, `failed`
  3. `source`: `ack`, `answer`
  4. timestamps for start, first audio, final audio, cancel
- Reason: reconnect/resume and “idempotent across reconnect” are hard to verify without explicit turn state.

9. Deployment artifact gaps

- The systemd unit should include `WorkingDirectory`, a concrete non-root user/group, restart backoff, and a clear `PATH`/`UV_PROJECT_ENVIRONMENT` or venv strategy.
- The Nginx config should include:
  1. `proxy_http_version 1.1`
  2. `proxy_set_header Upgrade $http_upgrade`
  3. `proxy_set_header Connection "upgrade"`
  4. `proxy_set_header Authorization $http_authorization`
  5. raised body and timeout settings only where needed

10. Suggested edits to the API plan

- Insert a Phase 3.5: Pipecat transport adapter spike.
- Change Phase 5 to prefer streaming STT and current Pipecat OpenAI service names.
- Change Phase 6/8 to split deterministic ack generation from substantive answer generation.
- Add DB concurrency requirements to Phase 1.
- Add production WS auth/proxy requirements to Phase 10.
- Add turn-state persistence details to Phase 7.

11. References checked

- Pipecat pipeline docs: https://docs.pipecat.ai/pipecat/learn/pipeline
- Pipecat transport docs: https://docs.pipecat.ai/pipecat/learn/transports
- Pipecat OpenAI STT docs: https://docs.pipecat.ai/api-reference/server/services/stt/openai
- Pipecat ParallelPipeline docs: https://docs.pipecat.ai/api-reference/server/pipeline/parallel-pipeline
