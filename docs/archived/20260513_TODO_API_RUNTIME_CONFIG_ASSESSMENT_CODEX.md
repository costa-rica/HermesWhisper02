# TODO API runtime config assessment: Codex

Date: 2026-05-13

## Summary

This plan is close, but Phase 2 and Phase 6 need important corrections. The current plan says deterministic mode should short-circuit to an "ack-only path"; that would break the core voice experience. Also, long-gap resume must first make HermesWhisper02 pass the stored `conversation_id` to Hermes, because the current Chat Completions request does not appear to use it.

## Concerns

1. Deterministic mode is defined incorrectly.
   - The plan says `answer()` should use an ack-only path.
   - That would produce no substantive Hermes answer.
   - Deterministic should bypass the front LLM and call Hermes directly.

2. Hermes conversation id is not currently propagated.
   - `FrontAnswerProcessor` stores `conversation_id`.
   - `collect_hermes_text_with_progress()` receives it.
   - The live `/v1/chat/completions` request only sends `model`, `messages`, and `stream`.
   - The `conversation_id` is not sent to Hermes.

3. Long-gap resume cannot rely on front LLM context alone.
   - Current `FrontAnswerProcessor` ignores `context_messages`.
   - HermesVoice solved this by sending `conversation` to Hermes.
   - If Hermes owns memory, prefer Hermes session propagation over replaying local messages.

4. Runtime frames may not be processed while a turn is active.
   - `_voice_loop` awaits `mock_pipeline.process_audio(...)`.
   - During Hermes or TTS work, it is not reading incoming WebSocket text frames.
   - Mid-turn settings frames will be delayed until the turn finishes.
   - This is acceptable if documented, but not truly live during long turns.

5. Long-gap session lookup needs a new store method.
   - `get_or_create_session()` creates a new session when the resume window expires.
   - Phase 6 needs an explicit `get_session_for_owner()` path before creating a new session.

6. Assistant text protocol is missing.
   - API should emit final assistant text to support mobile local history.
   - HermesVoice has an `assistant_text` frame; HermesWhisper02 should add an equivalent.

## Recommended approach changes

1. Revise Phase 2 intermediary behavior.
   - `deterministic`: call Hermes directly for non-trivial turns.
   - `llm`: use the front LLM/router behavior.
   - Keep deterministic ack behavior separate from answer routing.

2. Add a Hermes session propagation phase before long-gap resume.
   - Verify whether Hermes expects `/responses` with `conversation`, a header, or a Chat Completions extension.
   - Implement that contract in `api/app/services/hermes.py`.
   - Add a test asserting the outgoing Hermes request contains the session identifier.

3. Add `assistant_text` before mobile history work depends on it.
   - Emit final answer text after Hermes completes and before or near answer audio.
   - Persist server-side completed exchanges from the same final text.

4. Document delayed live-config semantics.
   - Runtime updates are read immediately only while the socket loop is reading.
   - During active Hermes or TTS work, updates apply after the current turn.

5. Add VoiceStore methods.
   - `get_session_for_owner(owner_id, session_id)`.
   - `list_recent_messages(session_id, limit)`.
   - Keep ownership checks server-side.

## Risk if unchanged

- Deterministic mode may silence real answers.
- Long-gap resume may restore local UI but not Hermes agent context.
- Mobile history may ship without assistant text.
